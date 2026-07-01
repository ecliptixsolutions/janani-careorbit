
drop policy "Authenticated can update patients" on public.patients;
drop policy "Authenticated can update appointments" on public.appointments;

create policy "Staff can update patients"
  on public.patients for update to authenticated
  using (
    public.has_role(auth.uid(),'admin')
    or public.has_role(auth.uid(),'doctor')
    or public.has_role(auth.uid(),'staff')
    or public.has_role(auth.uid(),'custom')
  );

create policy "Staff can update appointments"
  on public.appointments for update to authenticated
  using (
    public.has_role(auth.uid(),'admin')
    or public.has_role(auth.uid(),'doctor')
    or public.has_role(auth.uid(),'staff')
    or public.has_role(auth.uid(),'custom')
  );
