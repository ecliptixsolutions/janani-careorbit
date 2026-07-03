-- Run this once in the Supabase SQL Editor for a fresh CareOrbit project.
-- It creates the tables, roles, policies, triggers, and backfills users who signed up
-- before this schema existed.
-- Then run migrations/20260702090000_add_notifications.sql and
-- migrations/20260703120000_add_clinical_operations.sql in timestamp order.

create extension if not exists pgcrypto with schema extensions;

do $$
begin
  if not exists (select 1 from pg_type where typnamespace = 'public'::regnamespace and typname = 'app_role') then
    create type public.app_role as enum ('admin', 'doctor', 'staff', 'custom');
  end if;

  if not exists (select 1 from pg_type where typnamespace = 'public'::regnamespace and typname = 'appointment_status') then
    create type public.appointment_status as enum ('scheduled', 'confirmed', 'completed', 'cancelled', 'no_show');
  end if;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  organization text,
  custom_role_label text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  custom_label text,
  created_at timestamptz not null default now(),
  unique (user_id, role, custom_label)
);

create table if not exists public.patients (
  id uuid primary key default gen_random_uuid(),
  mrn text unique not null default ('MRN-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
  full_name text not null,
  date_of_birth date,
  gender text,
  phone text,
  email text,
  address text,
  blood_group text,
  allergies text,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  doctor_id uuid references auth.users(id) on delete set null,
  scheduled_at timestamptz not null,
  duration_minutes int not null default 30,
  reason text,
  status public.appointment_status not null default 'scheduled',
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  appointment_id uuid references public.appointments(id) on delete cascade,
  patient_id uuid references public.patients(id) on delete set null,
  channel text not null default 'in_app',
  recipient_phone text,
  title text not null,
  body text not null,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.patients enable row level security;
alter table public.appointments enable row level security;
alter table public.notifications enable row level security;

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = _user_id and role = _role
  )
$$;

create or replace function public.handle_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.app_role;
  v_custom text;
begin
  insert into public.profiles (id, full_name, phone, organization, custom_role_label)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.raw_user_meta_data->>'phone',
    new.raw_user_meta_data->>'organization',
    new.raw_user_meta_data->>'custom_role_label'
  )
  on conflict (id) do update set
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    organization = coalesce(excluded.organization, public.profiles.organization),
    custom_role_label = coalesce(excluded.custom_role_label, public.profiles.custom_role_label),
    updated_at = now();

  v_role := case
    when new.raw_user_meta_data->>'role' in ('admin', 'doctor', 'staff', 'custom')
      then (new.raw_user_meta_data->>'role')::public.app_role
    else 'staff'::public.app_role
  end;
  v_custom := new.raw_user_meta_data->>'custom_role_label';

  insert into public.user_roles (user_id, role, custom_label)
  select new.id, v_role, case when v_role = 'custom' or v_custom is not null then v_custom else null end
  where not exists (
    select 1 from public.user_roles
    where user_id = new.id
      and role = v_role
      and custom_label is not distinct from case when v_role = 'custom' or v_custom is not null then v_custom else null end
  );

  return new;
end;
$$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.handle_updated_at();

drop trigger if exists patients_updated_at on public.patients;
create trigger patients_updated_at before update on public.patients
  for each row execute function public.handle_updated_at();

drop trigger if exists appointments_updated_at on public.appointments;
create trigger appointments_updated_at before update on public.appointments
  for each row execute function public.handle_updated_at();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'Profiles viewable by authenticated users') then
    create policy "Profiles viewable by authenticated users" on public.profiles for select to authenticated using (true);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'Users update own profile') then
    create policy "Users update own profile" on public.profiles for update to authenticated using (auth.uid() = id);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles' and policyname = 'Users insert own profile') then
    create policy "Users insert own profile" on public.profiles for insert to authenticated with check (auth.uid() = id);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_roles' and policyname = 'Users can view their own roles') then
    create policy "Users can view their own roles" on public.user_roles for select to authenticated using (auth.uid() = user_id);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_roles' and policyname = 'Admins can view all roles') then
    create policy "Admins can view all roles" on public.user_roles for select to authenticated using (public.has_role(auth.uid(), 'admin'));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_roles' and policyname = 'Authenticated can view doctor roles') then
    create policy "Authenticated can view doctor roles" on public.user_roles for select to authenticated using (role = 'doctor');
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_roles' and policyname = 'Admins manage roles') then
    create policy "Admins manage roles" on public.user_roles for all to authenticated
      using (public.has_role(auth.uid(), 'admin'))
      with check (public.has_role(auth.uid(), 'admin'));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'patients' and policyname = 'Authenticated can view patients') then
    create policy "Authenticated can view patients" on public.patients for select to authenticated using (true);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'patients' and policyname = 'Authenticated can insert patients') then
    create policy "Authenticated can insert patients" on public.patients for insert to authenticated with check (auth.uid() = created_by);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'patients' and policyname = 'Staff can update patients') then
    create policy "Staff can update patients" on public.patients for update to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'doctor')
        or public.has_role(auth.uid(), 'staff')
        or public.has_role(auth.uid(), 'custom')
      );
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'patients' and policyname = 'Admins can delete patients') then
    create policy "Admins can delete patients" on public.patients for delete to authenticated using (public.has_role(auth.uid(), 'admin'));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'appointments' and policyname = 'Authenticated can view appointments') then
    create policy "Authenticated can view appointments" on public.appointments for select to authenticated using (true);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'appointments' and policyname = 'Authenticated can insert appointments') then
    create policy "Authenticated can insert appointments" on public.appointments for insert to authenticated with check (auth.uid() = created_by);
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'appointments' and policyname = 'Staff can update appointments') then
    create policy "Staff can update appointments" on public.appointments for update to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'doctor')
        or public.has_role(auth.uid(), 'staff')
        or public.has_role(auth.uid(), 'custom')
      );
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'appointments' and policyname = 'Admins can delete appointments') then
    create policy "Admins can delete appointments" on public.appointments for delete to authenticated using (public.has_role(auth.uid(), 'admin'));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notifications' and policyname = 'Users can view own notifications') then
    create policy "Users can view own notifications" on public.notifications for select to authenticated using (recipient_id = auth.uid() or public.has_role(auth.uid(), 'admin'));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notifications' and policyname = 'Users can mark own notifications read') then
    create policy "Users can mark own notifications read" on public.notifications for update to authenticated using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notifications' and policyname = 'Authenticated can create notifications') then
    create policy "Authenticated can create notifications" on public.notifications for insert to authenticated with check (actor_id = auth.uid() or public.has_role(auth.uid(), 'admin'));
  end if;
end $$;

revoke all on function public.has_role(uuid, public.app_role) from public, anon;
grant execute on function public.has_role(uuid, public.app_role) to authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.handle_updated_at() from public, anon, authenticated;

insert into public.profiles (id, full_name, phone, organization, custom_role_label)
select
  u.id,
  coalesce(u.raw_user_meta_data->>'full_name', u.email),
  u.raw_user_meta_data->>'phone',
  u.raw_user_meta_data->>'organization',
  u.raw_user_meta_data->>'custom_role_label'
from auth.users u
on conflict (id) do update set
  full_name = coalesce(excluded.full_name, public.profiles.full_name),
  phone = coalesce(excluded.phone, public.profiles.phone),
  organization = coalesce(excluded.organization, public.profiles.organization),
  custom_role_label = coalesce(excluded.custom_role_label, public.profiles.custom_role_label),
  updated_at = now();

insert into public.user_roles (user_id, role, custom_label)
select
  u.id,
  case
    when u.raw_user_meta_data->>'role' in ('admin', 'doctor', 'staff', 'custom')
      then (u.raw_user_meta_data->>'role')::public.app_role
    else 'staff'::public.app_role
  end as role,
  u.raw_user_meta_data->>'custom_role_label' as custom_label
from auth.users u
where not exists (
  select 1
  from public.user_roles r
  where r.user_id = u.id
);
