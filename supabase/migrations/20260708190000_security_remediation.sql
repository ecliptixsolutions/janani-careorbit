alter table public.profiles
  add column if not exists status text not null default 'active';

alter table public.profiles
  drop constraint if exists profiles_status_check,
  add constraint profiles_status_check check (status in ('active', 'pending_approval', 'disabled'));

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requested_role text;
  v_pending_label text;
begin
  v_requested_role := coalesce(nullif(new.raw_user_meta_data->>'requested_role', ''), 'staff');
  v_pending_label := 'pending:' || regexp_replace(lower(v_requested_role), '[^a-z0-9_]+', '_', 'g');

  insert into public.profiles (
    id,
    full_name,
    phone,
    email,
    organization,
    custom_role_label,
    status
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.raw_user_meta_data->>'phone',
    new.email,
    new.raw_user_meta_data->>'organization',
    v_pending_label,
    'pending_approval'
  )
  on conflict (id) do update set
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    email = coalesce(excluded.email, public.profiles.email),
    organization = coalesce(excluded.organization, public.profiles.organization),
    custom_role_label = excluded.custom_role_label,
    status = 'pending_approval',
    updated_at = now();

  delete from public.user_roles where user_id = new.id;
  insert into public.user_roles (user_id, role, custom_label)
  values (new.id, 'custom', v_pending_label)
  on conflict (user_id, role, custom_label) do nothing;

  return new;
end;
$$;

create or replace function public.approve_user_role(
  _user_id uuid,
  _role public.app_role,
  _custom_label text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_role(auth.uid(), 'admin') then
    raise exception 'Administrator access required';
  end if;

  if _role = 'admin'
    and _custom_label = 'super_admin'
    and auth.uid() <> _user_id
    and exists (
      select 1
      from public.user_roles
      where role = 'admin'
        and custom_label = 'super_admin'
        and user_id <> _user_id
    )
  then
    raise exception 'Only one Super Admin is allowed';
  end if;

  delete from public.user_roles where user_id = _user_id;

  insert into public.user_roles (user_id, role, custom_label)
  values (_user_id, _role, nullif(_custom_label, ''));

  update public.profiles
  set
    status = 'active',
    custom_role_label = nullif(_custom_label, ''),
    updated_at = now()
  where id = _user_id;
end;
$$;

revoke all on function public.approve_user_role(uuid, public.app_role, text) from public, anon;
grant execute on function public.approve_user_role(uuid, public.app_role, text) to authenticated;

drop policy if exists "Authenticated can view patients" on public.patients;
drop policy if exists "Authenticated can update patients" on public.patients;
drop policy if exists "Clinical users view patients" on public.patients;
create policy "Clinical users view patients"
  on public.patients for select
  to authenticated
  using (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'doctor')
    or public.has_role(auth.uid(), 'staff')
    or public.has_custom_role(auth.uid(), 'nurse')
    or public.has_custom_role(auth.uid(), 'pharmacist')
    or public.has_custom_role(auth.uid(), 'lab_technician')
    or public.has_custom_role(auth.uid(), 'billing_operator')
  );

drop policy if exists "Clinical users update patients" on public.patients;
create policy "Clinical users update patients"
  on public.patients for update
  to authenticated
  using (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'doctor')
    or public.has_role(auth.uid(), 'staff')
    or public.has_custom_role(auth.uid(), 'nurse')
  )
  with check (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'doctor')
    or public.has_role(auth.uid(), 'staff')
    or public.has_custom_role(auth.uid(), 'nurse')
  );

drop policy if exists "Authenticated can view appointments" on public.appointments;
drop policy if exists "Clinical users view appointments" on public.appointments;
create policy "Clinical users view appointments"
  on public.appointments for select
  to authenticated
  using (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'doctor')
    or public.has_role(auth.uid(), 'staff')
    or public.has_custom_role(auth.uid(), 'nurse')
    or public.has_custom_role(auth.uid(), 'lab_technician')
    or public.has_custom_role(auth.uid(), 'billing_operator')
  );

drop policy if exists "Authenticated view pharmacy stock" on public.pharmacy_items;
drop policy if exists "Pharmacy users view stock" on public.pharmacy_items;
create policy "Pharmacy users view stock"
  on public.pharmacy_items for select
  to authenticated
  using (
    public.has_role(auth.uid(), 'admin')
    or public.has_custom_role(auth.uid(), 'pharmacist')
    or public.has_custom_role(auth.uid(), 'billing_operator')
  );

create table if not exists public.role_session_policies (
  role text primary key,
  idle_timeout_minutes int not null check (idle_timeout_minutes > 0),
  absolute_timeout_minutes int not null check (absolute_timeout_minutes > 0)
);

insert into public.role_session_policies (role, idle_timeout_minutes, absolute_timeout_minutes) values
  ('super_admin', 15, 240),
  ('hospital_admin', 15, 240),
  ('admin', 15, 480),
  ('doctor', 20, 720),
  ('nurse', 20, 720),
  ('pharmacist', 20, 720),
  ('lab_technician', 20, 720),
  ('billing_operator', 20, 480),
  ('staff', 20, 480),
  ('patient', 30, 1440),
  ('custom', 20, 480)
on conflict (role) do update set
  idle_timeout_minutes = excluded.idle_timeout_minutes,
  absolute_timeout_minutes = excluded.absolute_timeout_minutes;

create table if not exists public.user_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  created_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  ip_address inet,
  user_agent text,
  device_label text,
  revoked_at timestamptz,
  revoked_reason text,
  constraint user_sessions_revoked_reason_check check (
    revoked_reason is null
    or revoked_reason in (
      'user_logout',
      'password_change',
      'role_change',
      'admin_revoke',
      'idle_timeout',
      'absolute_timeout'
    )
  )
);

alter table public.user_sessions enable row level security;

drop policy if exists "Users view own sessions" on public.user_sessions;
create policy "Users view own sessions"
  on public.user_sessions for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "Admins view user sessions" on public.user_sessions;
create policy "Admins view user sessions"
  on public.user_sessions for select
  to authenticated
  using (public.has_role(auth.uid(), 'admin'));

drop policy if exists "Users create own sessions" on public.user_sessions;
create policy "Users create own sessions"
  on public.user_sessions for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Users revoke own sessions" on public.user_sessions;
create policy "Users revoke own sessions"
  on public.user_sessions for update
  to authenticated
  using (user_id = auth.uid() or public.has_role(auth.uid(), 'admin'))
  with check (user_id = auth.uid() or public.has_role(auth.uid(), 'admin'));

drop trigger if exists user_sessions_audit on public.user_sessions;
create trigger user_sessions_audit
after insert or update or delete on public.user_sessions
for each row execute function public.capture_audit_log();

create or replace function public.revoke_sessions_on_password_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.encrypted_password is distinct from new.encrypted_password then
    update public.user_sessions
    set revoked_at = now(), revoked_reason = 'password_change'
    where user_id = new.id
      and revoked_at is null;
  end if;

  return new;
end;
$$;

drop trigger if exists on_password_change_revoke_sessions on auth.users;
create trigger on_password_change_revoke_sessions
after update of encrypted_password on auth.users
for each row execute function public.revoke_sessions_on_password_change();

create or replace function public.revoke_sessions_on_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  v_user_id := coalesce(new.user_id, old.user_id);

  update public.user_sessions
  set revoked_at = now(), revoked_reason = 'role_change'
  where user_id = v_user_id
    and revoked_at is null;

  return coalesce(new, old);
end;
$$;

drop trigger if exists user_roles_revoke_sessions on public.user_roles;
create trigger user_roles_revoke_sessions
after insert or update or delete on public.user_roles
for each row execute function public.revoke_sessions_on_role_change();

create table if not exists public.notification_read_states (
  user_id uuid not null references auth.users(id) on delete cascade,
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (user_id, appointment_id)
);

alter table public.notification_read_states enable row level security;

drop policy if exists "Users manage own notification read states" on public.notification_read_states;
create policy "Users manage own notification read states"
  on public.notification_read_states for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table if not exists public.custom_role_templates (
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  label text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, key)
);

alter table public.custom_role_templates enable row level security;

drop policy if exists "Users manage own custom role templates" on public.custom_role_templates;
create policy "Users manage own custom role templates"
  on public.custom_role_templates for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
