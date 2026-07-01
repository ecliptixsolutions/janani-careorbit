-- Allow authenticated RLS policies to evaluate has_role().
-- Without this grant, authenticated users can sign up but cannot read user_roles,
-- which makes the app appear stuck after login.
grant execute on function public.has_role(uuid, public.app_role) to authenticated;
