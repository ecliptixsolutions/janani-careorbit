create or replace function public.has_custom_role(_user_id uuid, _label text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles
    where user_id = _user_id
      and role = 'custom'
      and lower(coalesce(custom_label, '')) = lower(_label)
  )
$$;

create table if not exists public.prescriptions (
  id uuid primary key default gen_random_uuid(),
  prescription_number text unique not null
    default ('RX-' || to_char(now(), 'YYYYMM') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6))),
  patient_id uuid not null references public.patients(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  doctor_id uuid references auth.users(id) on delete set null,
  diagnosis text,
  medicines jsonb not null default '[]'::jsonb,
  advice text,
  status text not null default 'issued' check (status in ('draft', 'issued', 'cancelled')),
  issued_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text unique not null
    default ('INV-' || to_char(now(), 'YYYYMM') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6))),
  patient_id uuid not null references public.patients(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  items jsonb not null default '[]'::jsonb,
  subtotal numeric(12,2) not null default 0,
  discount_amount numeric(12,2) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  paid_amount numeric(12,2) not null default 0,
  status text not null default 'issued'
    check (status in ('draft', 'issued', 'partially_paid', 'paid', 'cancelled')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  method text not null check (method in ('cash', 'card', 'upi', 'bank_transfer', 'insurance', 'other')),
  reference text,
  received_by uuid references auth.users(id) on delete set null,
  paid_at timestamptz not null default now()
);

create table if not exists public.lab_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null
    default ('LAB-' || to_char(now(), 'YYYYMM') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6))),
  patient_id uuid not null references public.patients(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  test_name text not null,
  priority text not null default 'routine' check (priority in ('routine', 'urgent')),
  status text not null default 'ordered'
    check (status in ('ordered', 'sample_collected', 'processing', 'completed', 'cancelled')),
  result text,
  reference_range text,
  ordered_by uuid references auth.users(id) on delete set null,
  completed_by uuid references auth.users(id) on delete set null,
  ordered_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pharmacy_items (
  id uuid primary key default gen_random_uuid(),
  medicine_name text not null,
  sku text unique,
  batch_number text,
  expires_on date,
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  reorder_level integer not null default 10 check (reorder_level >= 0),
  unit_price numeric(12,2) not null default 0 check (unit_price >= 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.dispensations (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  prescription_id uuid references public.prescriptions(id) on delete set null,
  pharmacy_item_id uuid not null references public.pharmacy_items(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null default 0,
  dispensed_by uuid references auth.users(id) on delete set null,
  dispensed_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists prescriptions_patient_idx on public.prescriptions(patient_id, created_at desc);
create index if not exists invoices_patient_idx on public.invoices(patient_id, created_at desc);
create index if not exists payments_invoice_idx on public.payments(invoice_id, paid_at desc);
create index if not exists lab_orders_patient_idx on public.lab_orders(patient_id, created_at desc);
create index if not exists dispensations_patient_idx on public.dispensations(patient_id, dispensed_at desc);
create index if not exists audit_logs_created_idx on public.audit_logs(created_at desc);

alter table public.prescriptions enable row level security;
alter table public.invoices enable row level security;
alter table public.payments enable row level security;
alter table public.lab_orders enable row level security;
alter table public.pharmacy_items enable row level security;
alter table public.dispensations enable row level security;
alter table public.audit_logs enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'user_roles' and policyname = 'Authenticated can view workflow roles') then
    create policy "Authenticated can view workflow roles" on public.user_roles for select to authenticated
      using (
        role = 'custom'
        and lower(coalesce(custom_label, '')) in ('pharmacist', 'lab_technician', 'billing_operator')
      );
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'prescriptions' and policyname = 'Clinical users view prescriptions') then
    create policy "Clinical users view prescriptions" on public.prescriptions for select to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'doctor')
        or public.has_custom_role(auth.uid(), 'pharmacist')
        or public.has_custom_role(auth.uid(), 'nurse')
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'prescriptions' and policyname = 'Doctors manage prescriptions') then
    create policy "Doctors manage prescriptions" on public.prescriptions for all to authenticated
      using (public.has_role(auth.uid(), 'admin') or doctor_id = auth.uid())
      with check (
        public.has_role(auth.uid(), 'admin')
        or (public.has_role(auth.uid(), 'doctor') and doctor_id = auth.uid() and created_by = auth.uid())
      );
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invoices' and policyname = 'Billing users view invoices') then
    create policy "Billing users view invoices" on public.invoices for select to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'staff')
        or public.has_custom_role(auth.uid(), 'billing_operator')
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'invoices' and policyname = 'Billing users manage invoices') then
    create policy "Billing users manage invoices" on public.invoices for all to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'staff')
        or public.has_custom_role(auth.uid(), 'billing_operator')
      )
      with check (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'staff')
        or public.has_custom_role(auth.uid(), 'billing_operator')
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'payments' and policyname = 'Billing users manage payments') then
    create policy "Billing users manage payments" on public.payments for all to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'staff')
        or public.has_custom_role(auth.uid(), 'billing_operator')
      )
      with check (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'staff')
        or public.has_custom_role(auth.uid(), 'billing_operator')
      );
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'lab_orders' and policyname = 'Clinical users view lab orders') then
    create policy "Clinical users view lab orders" on public.lab_orders for select to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'doctor')
        or public.has_custom_role(auth.uid(), 'nurse')
        or public.has_custom_role(auth.uid(), 'lab_technician')
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'lab_orders' and policyname = 'Clinical users create lab orders') then
    create policy "Clinical users create lab orders" on public.lab_orders for insert to authenticated
      with check (
        public.has_role(auth.uid(), 'admin')
        or (public.has_role(auth.uid(), 'doctor') and ordered_by = auth.uid())
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'lab_orders' and policyname = 'Lab users update lab orders') then
    create policy "Lab users update lab orders" on public.lab_orders for update to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_custom_role(auth.uid(), 'lab_technician')
      )
      with check (
        public.has_role(auth.uid(), 'admin')
        or public.has_custom_role(auth.uid(), 'lab_technician')
      );
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pharmacy_items' and policyname = 'Authenticated view pharmacy stock') then
    create policy "Authenticated view pharmacy stock" on public.pharmacy_items for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'pharmacy_items' and policyname = 'Pharmacy users manage stock') then
    create policy "Pharmacy users manage stock" on public.pharmacy_items for all to authenticated
      using (public.has_role(auth.uid(), 'admin') or public.has_custom_role(auth.uid(), 'pharmacist'))
      with check (public.has_role(auth.uid(), 'admin') or public.has_custom_role(auth.uid(), 'pharmacist'));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'dispensations' and policyname = 'Clinical users view dispensations') then
    create policy "Clinical users view dispensations" on public.dispensations for select to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'doctor')
        or public.has_custom_role(auth.uid(), 'pharmacist')
      );
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'dispensations' and policyname = 'Pharmacy users create dispensations') then
    create policy "Pharmacy users create dispensations" on public.dispensations for insert to authenticated
      with check (
        public.has_role(auth.uid(), 'admin')
        or (public.has_custom_role(auth.uid(), 'pharmacist') and dispensed_by = auth.uid())
      );
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'audit_logs' and policyname = 'Admins view audit logs') then
    create policy "Admins view audit logs" on public.audit_logs for select to authenticated
      using (public.has_role(auth.uid(), 'admin'));
  end if;
end;
$$;

create or replace function public.handle_clinical_updated_at()
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

drop trigger if exists prescriptions_updated_at on public.prescriptions;
create trigger prescriptions_updated_at before update on public.prescriptions
  for each row execute function public.handle_clinical_updated_at();
drop trigger if exists invoices_updated_at on public.invoices;
create trigger invoices_updated_at before update on public.invoices
  for each row execute function public.handle_clinical_updated_at();
drop trigger if exists lab_orders_updated_at on public.lab_orders;
create trigger lab_orders_updated_at before update on public.lab_orders
  for each row execute function public.handle_clinical_updated_at();
drop trigger if exists pharmacy_items_updated_at on public.pharmacy_items;
create trigger pharmacy_items_updated_at before update on public.pharmacy_items
  for each row execute function public.handle_clinical_updated_at();

create or replace function public.capture_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  row_id text;
begin
  if tg_op = 'DELETE' then
    row_id := old.id::text;
  else
    row_id := new.id::text;
  end if;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, old_data, new_data)
  values (
    auth.uid(),
    lower(tg_op),
    tg_table_name,
    row_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.dispense_medicine(
  _patient_id uuid,
  _prescription_id uuid,
  _pharmacy_item_id uuid,
  _quantity integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_item public.pharmacy_items%rowtype;
  dispensation_id uuid;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_custom_role(auth.uid(), 'pharmacist')
  ) then
    raise exception 'Pharmacy access required';
  end if;
  if _quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select * into current_item
  from public.pharmacy_items
  where id = _pharmacy_item_id
  for update;

  if current_item.id is null then
    raise exception 'Medicine not found';
  end if;
  if current_item.stock_quantity < _quantity then
    raise exception 'Insufficient stock';
  end if;

  update public.pharmacy_items
  set stock_quantity = stock_quantity - _quantity
  where id = _pharmacy_item_id;

  insert into public.dispensations (
    patient_id, prescription_id, pharmacy_item_id, quantity, unit_price, dispensed_by
  )
  values (
    _patient_id, _prescription_id, _pharmacy_item_id, _quantity, current_item.unit_price, auth.uid()
  )
  returning id into dispensation_id;

  return dispensation_id;
end;
$$;

create or replace function public.record_invoice_payment(
  _invoice_id uuid,
  _amount numeric,
  _method text,
  _reference text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_invoice public.invoices%rowtype;
  payment_id uuid;
  next_paid numeric;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'staff')
    or public.has_custom_role(auth.uid(), 'billing_operator')
  ) then
    raise exception 'Billing access required';
  end if;

  select * into current_invoice
  from public.invoices
  where id = _invoice_id
  for update;

  if current_invoice.id is null then
    raise exception 'Invoice not found';
  end if;
  if _amount <= 0 or _amount > current_invoice.total_amount - current_invoice.paid_amount then
    raise exception 'Payment must be within the outstanding balance';
  end if;

  insert into public.payments (invoice_id, amount, method, reference, received_by)
  values (_invoice_id, _amount, _method, nullif(_reference, ''), auth.uid())
  returning id into payment_id;

  next_paid := current_invoice.paid_amount + _amount;
  update public.invoices
  set
    paid_amount = next_paid,
    status = case
      when next_paid >= total_amount then 'paid'
      else 'partially_paid'
    end
  where id = _invoice_id;

  return payment_id;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'patients', 'appointments', 'prescriptions', 'invoices', 'payments',
    'lab_orders', 'pharmacy_items', 'dispensations'
  ]
  loop
    execute format('drop trigger if exists %I_audit on public.%I', table_name, table_name);
    execute format(
      'create trigger %I_audit after insert or update or delete on public.%I for each row execute function public.capture_audit_log()',
      table_name,
      table_name
    );
  end loop;
end;
$$;

revoke all on function public.has_custom_role(uuid, text) from public, anon;
grant execute on function public.has_custom_role(uuid, text) to authenticated;
revoke all on function public.dispense_medicine(uuid, uuid, uuid, integer) from public, anon;
grant execute on function public.dispense_medicine(uuid, uuid, uuid, integer) to authenticated;
revoke all on function public.record_invoice_payment(uuid, numeric, text, text) from public, anon;
grant execute on function public.record_invoice_payment(uuid, numeric, text, text) to authenticated;
revoke all on function public.capture_audit_log() from public, anon, authenticated;
revoke all on function public.handle_clinical_updated_at() from public, anon, authenticated;
