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

alter table public.notifications enable row level security;
alter table public.notifications replica identity full;

create index if not exists notifications_recipient_created_idx
  on public.notifications (recipient_id, created_at desc);
create index if not exists notifications_appointment_idx
  on public.notifications (appointment_id);

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and policyname = 'Users can view own notifications'
  ) then
    create policy "Users can view own notifications"
      on public.notifications for select
      to authenticated
      using (recipient_id = auth.uid() or public.has_role(auth.uid(), 'admin'));
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and policyname = 'Users can mark own notifications read'
  ) then
    create policy "Users can mark own notifications read"
      on public.notifications for update
      to authenticated
      using (recipient_id = auth.uid())
      with check (recipient_id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'notifications'
      and policyname = 'Authenticated can create notifications'
  ) then
    create policy "Authenticated can create notifications"
      on public.notifications for insert
      to authenticated
      with check (actor_id = auth.uid() or public.has_role(auth.uid(), 'admin'));
  end if;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception
  when duplicate_object then null;
  when undefined_object then null;
end;
$$;

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
  insert into public.profiles (id, full_name, phone, organization, custom_role_label)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.raw_user_meta_data->>'phone',
    new.raw_user_meta_data->>'organization',
    new.raw_user_meta_data->>'custom_role_label'
  )
  on conflict (id) do update
  set
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    organization = coalesce(excluded.organization, public.profiles.organization),
    custom_role_label = coalesce(excluded.custom_role_label, public.profiles.custom_role_label),
    updated_at = now();

  v_role := coalesce((new.raw_user_meta_data->>'role')::app_role, 'staff');
  v_custom := new.raw_user_meta_data->>'custom_role_label';

  insert into public.user_roles (user_id, role, custom_label)
  values (new.id, v_role, case when v_role = 'custom' then v_custom else null end)
  on conflict do nothing;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'user_roles'
      and policyname = 'Authenticated can view doctor roles'
  ) then
    create policy "Authenticated can view doctor roles"
      on public.user_roles for select
      to authenticated
      using (role = 'doctor');
  end if;
end;
$$;
