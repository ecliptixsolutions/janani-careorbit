
-- ============ ENUM ============
create type public.app_role as enum ('admin', 'doctor', 'staff', 'custom');

create type public.appointment_status as enum ('scheduled', 'confirmed', 'completed', 'cancelled', 'no_show');

-- ============ PROFILES ============
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  organization text,
  custom_role_label text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Profiles viewable by authenticated users"
  on public.profiles for select
  to authenticated
  using (true);

create policy "Users update own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id);

create policy "Users insert own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

-- ============ USER ROLES ============
create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role app_role not null,
  custom_label text,
  created_at timestamptz not null default now(),
  unique (user_id, role, custom_label)
);

alter table public.user_roles enable row level security;

create or replace function public.has_role(_user_id uuid, _role app_role)
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

create policy "Users can view their own roles"
  on public.user_roles for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Admins can view all roles"
  on public.user_roles for select
  to authenticated
  using (public.has_role(auth.uid(), 'admin'));

create policy "Admins manage roles"
  on public.user_roles for all
  to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

-- ============ PATIENTS ============
create table public.patients (
  id uuid primary key default gen_random_uuid(),
  mrn text unique not null default ('MRN-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
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

alter table public.patients enable row level security;

create policy "Authenticated can view patients"
  on public.patients for select to authenticated using (true);
create policy "Authenticated can insert patients"
  on public.patients for insert to authenticated with check (auth.uid() = created_by);
create policy "Authenticated can update patients"
  on public.patients for update to authenticated using (true);
create policy "Admins can delete patients"
  on public.patients for delete to authenticated using (public.has_role(auth.uid(),'admin'));

-- ============ APPOINTMENTS ============
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  doctor_id uuid references auth.users(id) on delete set null,
  scheduled_at timestamptz not null,
  duration_minutes int not null default 30,
  reason text,
  status appointment_status not null default 'scheduled',
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.appointments enable row level security;

create policy "Authenticated can view appointments"
  on public.appointments for select to authenticated using (true);
create policy "Authenticated can insert appointments"
  on public.appointments for insert to authenticated with check (auth.uid() = created_by);
create policy "Authenticated can update appointments"
  on public.appointments for update to authenticated using (true);
create policy "Admins can delete appointments"
  on public.appointments for delete to authenticated using (public.has_role(auth.uid(),'admin'));

-- ============ TRIGGERS ============
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.handle_updated_at();
create trigger patients_updated_at before update on public.patients
  for each row execute function public.handle_updated_at();
create trigger appointments_updated_at before update on public.appointments
  for each row execute function public.handle_updated_at();

-- Auto-create profile + default role on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role app_role;
  v_custom text;
begin
  insert into public.profiles (id, full_name, organization, custom_role_label)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.raw_user_meta_data->>'organization',
    new.raw_user_meta_data->>'custom_role_label'
  );

  v_role := coalesce((new.raw_user_meta_data->>'role')::app_role, 'staff');
  v_custom := new.raw_user_meta_data->>'custom_role_label';

  insert into public.user_roles (user_id, role, custom_label)
  values (new.id, v_role, case when v_role = 'custom' then v_custom else null end);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
