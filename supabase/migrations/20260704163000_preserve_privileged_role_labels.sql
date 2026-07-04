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
  insert into public.profiles (
    id, full_name, phone, email, organization, custom_role_label
  )
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.raw_user_meta_data->>'phone',
    new.email,
    new.raw_user_meta_data->>'organization',
    new.raw_user_meta_data->>'custom_role_label'
  )
  on conflict (id) do update set
    full_name = coalesce(excluded.full_name, public.profiles.full_name),
    phone = coalesce(excluded.phone, public.profiles.phone),
    email = coalesce(excluded.email, public.profiles.email),
    organization = coalesce(excluded.organization, public.profiles.organization),
    custom_role_label = coalesce(excluded.custom_role_label, public.profiles.custom_role_label),
    updated_at = now();

  v_role := coalesce((new.raw_user_meta_data->>'role')::public.app_role, 'staff');
  v_custom := nullif(new.raw_user_meta_data->>'custom_role_label', '');

  insert into public.user_roles (user_id, role, custom_label)
  values (new.id, v_role, v_custom)
  on conflict do nothing;
  return new;
end;
$$;

update public.user_roles ur
set custom_label = p.custom_role_label
from public.profiles p
where ur.user_id = p.id
  and ur.role = 'admin'
  and ur.custom_label is null
  and p.custom_role_label in ('hospital_admin', 'super_admin');
