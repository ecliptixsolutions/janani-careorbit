alter table public.profiles add column if not exists email text;

update public.profiles p
set email = u.email
from auth.users u
where p.id = u.id and p.email is null;

create unique index if not exists profiles_email_lower_idx
  on public.profiles (lower(email))
  where email is not null;

create table if not exists public.organization_settings (
  id uuid primary key default '00000000-0000-0000-0000-000000000001',
  hospital_name text not null default 'CareOrbit Hospital',
  legal_name text,
  logo_path text,
  address_line_1 text,
  address_line_2 text,
  city text,
  state text,
  postal_code text,
  primary_phone text,
  secondary_phone text,
  email text,
  website text,
  gstin text,
  pan_registration text,
  invoice_prefix text not null default 'INV',
  currency text not null default 'INR',
  invoice_terms text,
  payment_details text,
  invoice_footer text,
  authorized_signatory text,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_settings_singleton check (
    id = '00000000-0000-0000-0000-000000000001'
  ),
  constraint organization_currency_check check (currency = 'INR')
);

insert into public.organization_settings (id)
values ('00000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

create table if not exists public.service_catalog (
  id uuid primary key default gen_random_uuid(),
  service_code text not null,
  service_name text not null,
  category text,
  default_price numeric(12,2) not null default 0 check (default_price >= 0),
  tax_rate numeric(5,2) not null default 0 check (tax_rate between 0 and 100),
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists service_catalog_code_lower_idx
  on public.service_catalog (lower(service_code));

create table if not exists public.import_batches (
  id uuid primary key default gen_random_uuid(),
  import_type text not null check (
    import_type in ('patients', 'pharmacy', 'services', 'appointments', 'staff')
  ),
  file_name text not null,
  total_rows integer not null default 0 check (total_rows >= 0),
  imported_rows integer not null default 0 check (imported_rows >= 0),
  skipped_rows integer not null default 0 check (skipped_rows >= 0),
  error_rows integer not null default 0 check (error_rows >= 0),
  summary jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.invoices
  add column if not exists finalized_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text,
  add column if not exists updated_by uuid references auth.users(id) on delete set null;

alter table public.payments
  add column if not exists receipt_number text,
  add column if not exists notes text;

update public.payments
set receipt_number = 'RCT-' || to_char(paid_at, 'YYYYMM') || '-' ||
  upper(substr(replace(id::text, '-', ''), 1, 6))
where receipt_number is null;

alter table public.payments alter column receipt_number set not null;
create unique index if not exists payments_receipt_number_idx
  on public.payments(receipt_number);

create or replace function public.assign_invoice_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  prefix text;
begin
  select upper(coalesce(nullif(trim(invoice_prefix), ''), 'INV'))
  into prefix
  from public.organization_settings
  where id = '00000000-0000-0000-0000-000000000001';

  new.invoice_number := coalesce(prefix, 'INV') || '-' || to_char(now(), 'YYYYMM') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  return new;
end;
$$;

drop trigger if exists invoices_assign_number on public.invoices;
create trigger invoices_assign_number
before insert on public.invoices
for each row execute function public.assign_invoice_number();

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.pharmacy_items'::regclass
      and conname = 'pharmacy_items_sku_key'
  ) then
    alter table public.pharmacy_items drop constraint pharmacy_items_sku_key;
  end if;
end;
$$;

create unique index if not exists pharmacy_sku_batch_idx
  on public.pharmacy_items (lower(sku), lower(coalesce(batch_number, '')))
  where sku is not null;

alter table public.organization_settings enable row level security;
alter table public.service_catalog enable row level security;
alter table public.import_batches enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'organization_settings'
      and policyname = 'Authenticated view organization settings'
  ) then
    create policy "Authenticated view organization settings"
      on public.organization_settings for select to authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'organization_settings'
      and policyname = 'Admins manage organization settings'
  ) then
    create policy "Admins manage organization settings"
      on public.organization_settings for all to authenticated
      using (public.has_role(auth.uid(), 'admin'))
      with check (public.has_role(auth.uid(), 'admin') and updated_by = auth.uid());
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'service_catalog'
      and policyname = 'Billing users view service catalog'
  ) then
    create policy "Billing users view service catalog"
      on public.service_catalog for select to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_role(auth.uid(), 'staff')
        or public.has_custom_role(auth.uid(), 'billing_operator')
      );
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'service_catalog'
      and policyname = 'Billing users manage service catalog'
  ) then
    create policy "Billing users manage service catalog"
      on public.service_catalog for all to authenticated
      using (
        public.has_role(auth.uid(), 'admin')
        or public.has_custom_role(auth.uid(), 'billing_operator')
      )
      with check (
        public.has_role(auth.uid(), 'admin')
        or public.has_custom_role(auth.uid(), 'billing_operator')
      );
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'import_batches'
      and policyname = 'Users view own imports'
  ) then
    create policy "Users view own imports"
      on public.import_batches for select to authenticated
      using (created_by = auth.uid() or public.has_role(auth.uid(), 'admin'));
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'import_batches'
      and policyname = 'Users create own imports'
  ) then
    create policy "Users create own imports"
      on public.import_batches for insert to authenticated
      with check (created_by = auth.uid());
  end if;
end;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'hospital-assets',
  'hospital-assets',
  true,
  2097152,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Public view hospital assets'
  ) then
    create policy "Public view hospital assets"
      on storage.objects for select
      using (bucket_id = 'hospital-assets');
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'Admins manage hospital assets'
  ) then
    create policy "Admins manage hospital assets"
      on storage.objects for all to authenticated
      using (bucket_id = 'hospital-assets' and public.has_role(auth.uid(), 'admin'))
      with check (bucket_id = 'hospital-assets' and public.has_role(auth.uid(), 'admin'));
  end if;
end;
$$;

create or replace function public.guard_invoice_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  payment_total numeric;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception 'Only draft invoices can be deleted';
    end if;
    return old;
  end if;

  if old.status <> 'draft' and (
    new.invoice_number is distinct from old.invoice_number
    or new.patient_id is distinct from old.patient_id
    or new.appointment_id is distinct from old.appointment_id
    or new.items is distinct from old.items
    or new.subtotal is distinct from old.subtotal
    or new.discount_amount is distinct from old.discount_amount
    or new.tax_amount is distinct from old.tax_amount
    or new.total_amount is distinct from old.total_amount
    or new.created_by is distinct from old.created_by
    or new.notes is distinct from old.notes
  ) then
    raise exception 'Finalized invoice financial details cannot be edited';
  end if;

  if old.status = 'draft' and new.paid_amount <> 0 then
    raise exception 'Draft invoices cannot contain payments';
  end if;

  if old.status = 'draft' and new.status not in ('draft', 'issued') then
    raise exception 'Draft invoices must be finalized before further status changes';
  end if;
  if old.status = 'draft' and new.status = 'issued' then
    if new.total_amount <= 0 then raise exception 'Invoice total must be greater than zero'; end if;
    new.finalized_at := coalesce(new.finalized_at, now());
  end if;
  if old.status = 'cancelled' then
    raise exception 'Cancelled invoices cannot be changed';
  end if;
  if new.status = 'cancelled' and old.status <> 'cancelled' then
    if not (
      public.has_role(auth.uid(), 'admin')
      or public.has_custom_role(auth.uid(), 'billing_operator')
    ) then raise exception 'Billing administrator access required'; end if;
    if old.status not in ('issued', 'partially_paid') or old.paid_amount > 0 then
      raise exception 'Only unpaid issued invoices can be cancelled';
    end if;
    if length(trim(coalesce(new.cancellation_reason, ''))) < 3 then
      raise exception 'Cancellation reason is required';
    end if;
    new.cancelled_at := coalesce(new.cancelled_at, now());
  end if;

  if new.paid_amount is distinct from old.paid_amount then
    select coalesce(sum(amount), 0) into payment_total
    from public.payments where invoice_id = old.id;
    if new.paid_amount <> payment_total then
      raise exception 'Invoice paid amount must match recorded payments';
    end if;
  end if;

  if new.status = 'paid' and new.paid_amount < new.total_amount then
    raise exception 'Invoice cannot be paid while a balance remains';
  end if;
  if new.status = 'partially_paid' and (
    new.paid_amount <= 0 or new.paid_amount >= new.total_amount
  ) then
    raise exception 'Partially paid status requires a remaining balance';
  end if;
  if new.status = 'issued' and new.paid_amount <> 0 then
    raise exception 'Issued status requires zero paid amount';
  end if;

  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end;
$$;

drop trigger if exists invoices_guard_changes on public.invoices;
create trigger invoices_guard_changes
before update or delete on public.invoices
for each row execute function public.guard_invoice_changes();

create or replace function public.finalize_invoice(_invoice_id uuid)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  current_invoice public.invoices%rowtype;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'staff')
    or public.has_custom_role(auth.uid(), 'billing_operator')
  ) then
    raise exception 'Billing access required';
  end if;

  select * into current_invoice from public.invoices
  where id = _invoice_id for update;

  if current_invoice.id is null then raise exception 'Invoice not found'; end if;
  if current_invoice.status <> 'draft' then raise exception 'Only drafts can be finalized'; end if;
  if current_invoice.total_amount <= 0 then raise exception 'Invoice total must be greater than zero'; end if;

  update public.invoices
  set status = 'issued', finalized_at = now(), updated_by = auth.uid()
  where id = _invoice_id
  returning * into current_invoice;
  return current_invoice;
end;
$$;

create or replace function public.cancel_invoice(_invoice_id uuid, _reason text)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  current_invoice public.invoices%rowtype;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_custom_role(auth.uid(), 'billing_operator')
  ) then
    raise exception 'Billing administrator access required';
  end if;
  if length(trim(coalesce(_reason, ''))) < 3 then
    raise exception 'Cancellation reason is required';
  end if;

  select * into current_invoice from public.invoices
  where id = _invoice_id for update;

  if current_invoice.id is null then raise exception 'Invoice not found'; end if;
  if current_invoice.status in ('draft', 'paid', 'cancelled') then
    raise exception 'This invoice cannot be cancelled';
  end if;
  if current_invoice.paid_amount > 0 then
    raise exception 'Paid invoices require a refund workflow before cancellation';
  end if;

  update public.invoices
  set status = 'cancelled', cancelled_at = now(),
      cancellation_reason = trim(_reason), updated_by = auth.uid()
  where id = _invoice_id
  returning * into current_invoice;
  return current_invoice;
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
  receipt text;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'staff')
    or public.has_custom_role(auth.uid(), 'billing_operator')
  ) then
    raise exception 'Billing access required';
  end if;

  select * into current_invoice from public.invoices
  where id = _invoice_id for update;

  if current_invoice.id is null then raise exception 'Invoice not found'; end if;
  if current_invoice.status not in ('issued', 'partially_paid') then
    raise exception 'Payments can only be recorded against issued invoices';
  end if;
  if _amount <= 0 or _amount > current_invoice.total_amount - current_invoice.paid_amount then
    raise exception 'Payment must be within the outstanding balance';
  end if;
  if _method not in ('cash', 'card', 'upi', 'bank_transfer', 'insurance', 'other') then
    raise exception 'Unsupported payment method';
  end if;

  receipt := 'RCT-' || to_char(now(), 'YYYYMM') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  insert into public.payments (
    invoice_id, amount, method, reference, received_by, receipt_number
  )
  values (
    _invoice_id, _amount, _method, nullif(trim(_reference), ''),
    auth.uid(), receipt
  )
  returning id into payment_id;

  next_paid := current_invoice.paid_amount + _amount;
  update public.invoices
  set paid_amount = next_paid,
      status = case when next_paid >= total_amount then 'paid' else 'partially_paid' end,
      updated_by = auth.uid()
  where id = _invoice_id;

  return payment_id;
end;
$$;

create or replace function public.import_patients(_rows jsonb, _file_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  row_no integer := 0;
  imported integer := 0;
  skipped integer := 0;
  errors jsonb := '[]'::jsonb;
  dob date;
  supplied_mrn text;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'staff')
    or public.has_custom_role(auth.uid(), 'nurse')
  ) then raise exception 'Patient import access required'; end if;
  if jsonb_array_length(_rows) > 2000 then raise exception 'Maximum 2000 rows per import'; end if;

  for item in select * from jsonb_array_elements(_rows)
  loop
    row_no := row_no + 1;
    begin
      if length(trim(coalesce(item->>'full_name', ''))) < 2 then
        raise exception 'Full name is required';
      end if;
      dob := nullif(item->>'date_of_birth', '')::date;
      supplied_mrn := nullif(trim(item->>'mrn'), '');
      if exists (
        select 1 from public.patients p where
          (supplied_mrn is not null and lower(p.mrn) = lower(supplied_mrn))
          or (nullif(trim(item->>'phone'), '') is not null and p.phone = trim(item->>'phone'))
          or (nullif(trim(item->>'email'), '') is not null and lower(p.email) = lower(trim(item->>'email')))
          or (lower(p.full_name) = lower(trim(item->>'full_name')) and p.date_of_birth is not distinct from dob)
      ) then
        skipped := skipped + 1;
        errors := errors || jsonb_build_array(jsonb_build_object(
          'row', row_no, 'error', 'Possible duplicate patient'
        ));
        continue;
      end if;

      insert into public.patients (
        mrn, full_name, date_of_birth, gender, phone, email, address,
        blood_group, notes, created_by
      ) values (
        coalesce(supplied_mrn, 'MRN-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
        trim(item->>'full_name'), dob, nullif(trim(item->>'gender'), ''),
        nullif(trim(item->>'phone'), ''), nullif(lower(trim(item->>'email')), ''),
        nullif(trim(item->>'address'), ''), nullif(trim(item->>'blood_group'), ''),
        concat_ws(E'\n',
          nullif(trim(item->>'notes'), ''),
          case when nullif(trim(item->>'emergency_contact'), '') is not null
            then 'Guardian: ' || trim(item->>'emergency_contact') end
        ),
        auth.uid()
      );
      imported := imported + 1;
    exception when others then
      skipped := skipped + 1;
      errors := errors || jsonb_build_array(jsonb_build_object(
        'row', row_no, 'error', sqlerrm
      ));
    end;
  end loop;

  insert into public.import_batches (
    import_type, file_name, total_rows, imported_rows, skipped_rows,
    error_rows, summary, created_by
  ) values (
    'patients', _file_name, row_no, imported, skipped,
    jsonb_array_length(errors), jsonb_build_object('errors', errors), auth.uid()
  );
  return jsonb_build_object('total', row_no, 'imported', imported, 'skipped', skipped, 'errors', errors);
end;
$$;

create or replace function public.import_pharmacy(
  _rows jsonb,
  _file_name text,
  _update_existing boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  row_no integer := 0;
  imported integer := 0;
  skipped integer := 0;
  errors jsonb := '[]'::jsonb;
  existing_id uuid;
  qty integer;
  reorder_qty integer;
  price numeric;
  expiry date;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_custom_role(auth.uid(), 'pharmacist')
  ) then raise exception 'Pharmacy import access required'; end if;
  if jsonb_array_length(_rows) > 2000 then raise exception 'Maximum 2000 rows per import'; end if;

  for item in select * from jsonb_array_elements(_rows)
  loop
    row_no := row_no + 1;
    begin
      if length(trim(coalesce(item->>'medicine_name', ''))) < 2 then
        raise exception 'Medicine name is required';
      end if;
      qty := coalesce(nullif(item->>'quantity', '')::integer, 0);
      reorder_qty := coalesce(nullif(item->>'reorder_level', '')::integer, 0);
      price := coalesce(nullif(item->>'unit_price', '')::numeric, 0);
      expiry := nullif(item->>'expiry_date', '')::date;
      if qty < 0 or reorder_qty < 0 or price < 0 then
        raise exception 'Quantity, reorder level and price cannot be negative';
      end if;
      if expiry is not null and expiry < current_date then
        raise exception 'Expiry date is in the past';
      end if;

      select id into existing_id from public.pharmacy_items
      where nullif(trim(item->>'sku'), '') is not null
        and lower(sku) = lower(trim(item->>'sku'))
        and lower(coalesce(batch_number, '')) = lower(coalesce(trim(item->>'batch_number'), ''))
      limit 1;

      if existing_id is not null and not _update_existing then
        skipped := skipped + 1;
        errors := errors || jsonb_build_array(jsonb_build_object(
          'row', row_no, 'error', 'Matching SKU and batch already exists; enable confirmed updates'
        ));
        continue;
      end if;

      if existing_id is not null then
        update public.pharmacy_items set
          medicine_name = trim(item->>'medicine_name'),
          expires_on = expiry,
          stock_quantity = qty,
          reorder_level = reorder_qty,
          unit_price = price
        where id = existing_id;
      else
        insert into public.pharmacy_items (
          medicine_name, sku, batch_number, expires_on, stock_quantity,
          reorder_level, unit_price, created_by
        ) values (
          trim(item->>'medicine_name'), nullif(trim(item->>'sku'), ''),
          nullif(trim(item->>'batch_number'), ''), expiry, qty,
          reorder_qty, price, auth.uid()
        );
      end if;
      imported := imported + 1;
      existing_id := null;
    exception when others then
      existing_id := null;
      skipped := skipped + 1;
      errors := errors || jsonb_build_array(jsonb_build_object(
        'row', row_no, 'error', sqlerrm
      ));
    end;
  end loop;

  insert into public.import_batches (
    import_type, file_name, total_rows, imported_rows, skipped_rows,
    error_rows, summary, created_by
  ) values (
    'pharmacy', _file_name, row_no, imported, skipped,
    jsonb_array_length(errors),
    jsonb_build_object('errors', errors, 'update_existing', _update_existing),
    auth.uid()
  );
  return jsonb_build_object('total', row_no, 'imported', imported, 'skipped', skipped, 'errors', errors);
end;
$$;

create or replace function public.import_services(_rows jsonb, _file_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  row_no integer := 0;
  imported integer := 0;
  skipped integer := 0;
  errors jsonb := '[]'::jsonb;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_custom_role(auth.uid(), 'billing_operator')
  ) then raise exception 'Service import access required'; end if;
  if jsonb_array_length(_rows) > 2000 then raise exception 'Maximum 2000 rows per import'; end if;

  for item in select * from jsonb_array_elements(_rows)
  loop
    row_no := row_no + 1;
    begin
      if length(trim(coalesce(item->>'service_code', ''))) < 1 then raise exception 'Service code is required'; end if;
      if length(trim(coalesce(item->>'service_name', ''))) < 2 then raise exception 'Service name is required'; end if;
      if coalesce(nullif(item->>'default_price', '')::numeric, 0) < 0 then raise exception 'Price cannot be negative'; end if;
      if coalesce(nullif(item->>'tax_rate', '')::numeric, 0) not between 0 and 100 then raise exception 'Tax rate must be 0 to 100'; end if;

      insert into public.service_catalog (
        service_code, service_name, category, default_price,
        tax_rate, is_active, created_by
      ) values (
        trim(item->>'service_code'), trim(item->>'service_name'),
        nullif(trim(item->>'category'), ''),
        coalesce(nullif(item->>'default_price', '')::numeric, 0),
        coalesce(nullif(item->>'tax_rate', '')::numeric, 0),
        coalesce(nullif(item->>'active', '')::boolean, true),
        auth.uid()
      )
      on conflict ((lower(service_code))) do update set
        service_name = excluded.service_name,
        category = excluded.category,
        default_price = excluded.default_price,
        tax_rate = excluded.tax_rate,
        is_active = excluded.is_active,
        updated_at = now();
      imported := imported + 1;
    exception when others then
      skipped := skipped + 1;
      errors := errors || jsonb_build_array(jsonb_build_object(
        'row', row_no, 'error', sqlerrm
      ));
    end;
  end loop;

  insert into public.import_batches (
    import_type, file_name, total_rows, imported_rows, skipped_rows,
    error_rows, summary, created_by
  ) values (
    'services', _file_name, row_no, imported, skipped,
    jsonb_array_length(errors), jsonb_build_object('errors', errors), auth.uid()
  );
  return jsonb_build_object('total', row_no, 'imported', imported, 'skipped', skipped, 'errors', errors);
end;
$$;

create or replace function public.import_appointments(_rows jsonb, _file_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  row_no integer := 0;
  imported integer := 0;
  skipped integer := 0;
  errors jsonb := '[]'::jsonb;
  target_patient uuid;
  target_doctor uuid;
  scheduled timestamptz;
  requested_status public.appointment_status;
  appointment_id uuid;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_role(auth.uid(), 'staff')
    or public.has_custom_role(auth.uid(), 'nurse')
  ) then raise exception 'Appointment import access required'; end if;
  if jsonb_array_length(_rows) > 2000 then raise exception 'Maximum 2000 rows per import'; end if;

  for item in select * from jsonb_array_elements(_rows)
  loop
    row_no := row_no + 1;
    begin
      select id into target_patient from public.patients
      where lower(mrn) = lower(trim(item->>'patient_mrn')) limit 1;
      if target_patient is null then raise exception 'Patient MRN was not found'; end if;

      select p.id into target_doctor
      from public.profiles p
      join public.user_roles ur on ur.user_id = p.id and ur.role = 'doctor'
      where lower(p.email) = lower(trim(item->>'doctor_email'))
      limit 1;
      if target_doctor is null then raise exception 'Doctor email was not found'; end if;

      scheduled := ((item->>'appointment_date') || ' ' || (item->>'appointment_time'))::timestamp
        at time zone 'Asia/Kolkata';
      requested_status := coalesce(nullif(item->>'status', ''), 'scheduled')::public.appointment_status;
      if requested_status not in ('scheduled', 'confirmed', 'completed', 'cancelled', 'no_show') then
        raise exception 'Unsupported appointment status';
      end if;
      if exists (
        select 1 from public.appointments
        where doctor_id = target_doctor
          and status not in ('cancelled', 'no_show')
          and scheduled_at = scheduled
      ) then raise exception 'Doctor already has an appointment at this time'; end if;

      insert into public.appointments (
        patient_id, doctor_id, scheduled_at, reason, status, created_by
      ) values (
        target_patient, target_doctor, scheduled,
        nullif(trim(item->>'reason'), ''), requested_status, auth.uid()
      )
      returning id into appointment_id;

      insert into public.notifications (
        recipient_id, actor_id, appointment_id, patient_id, title, body, channel, metadata
      ) values (
        target_doctor, auth.uid(), appointment_id, target_patient,
        'Imported appointment assigned',
        'An appointment was imported for ' || to_char(scheduled at time zone 'Asia/Kolkata', 'DD Mon YYYY HH12:MI AM') || '.',
        'in_app',
        jsonb_build_object('source', 'appointment_import')
      );
      imported := imported + 1;
      target_patient := null;
      target_doctor := null;
      appointment_id := null;
    exception when others then
      target_patient := null;
      target_doctor := null;
      appointment_id := null;
      skipped := skipped + 1;
      errors := errors || jsonb_build_array(jsonb_build_object(
        'row', row_no, 'error', sqlerrm
      ));
    end;
  end loop;

  insert into public.import_batches (
    import_type, file_name, total_rows, imported_rows, skipped_rows,
    error_rows, summary, created_by
  ) values (
    'appointments', _file_name, row_no, imported, skipped,
    jsonb_array_length(errors), jsonb_build_object('errors', errors), auth.uid()
  );
  return jsonb_build_object('total', row_no, 'imported', imported, 'skipped', skipped, 'errors', errors);
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

drop trigger if exists organization_settings_updated_at on public.organization_settings;
create trigger organization_settings_updated_at
before update on public.organization_settings
for each row execute function public.handle_clinical_updated_at();

drop trigger if exists service_catalog_updated_at on public.service_catalog;
create trigger service_catalog_updated_at
before update on public.service_catalog
for each row execute function public.handle_clinical_updated_at();

drop trigger if exists organization_settings_audit on public.organization_settings;
create trigger organization_settings_audit
after insert or update or delete on public.organization_settings
for each row execute function public.capture_audit_log();

drop trigger if exists service_catalog_audit on public.service_catalog;
create trigger service_catalog_audit
after insert or update or delete on public.service_catalog
for each row execute function public.capture_audit_log();

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
    custom_role_label = coalesce(excluded.custom_role_label, public.profiles.custom_role_label);

  v_role := coalesce((new.raw_user_meta_data->>'role')::public.app_role, 'staff');
  v_custom := new.raw_user_meta_data->>'custom_role_label';

  insert into public.user_roles (user_id, role, custom_label)
  values (new.id, v_role, case when v_role = 'custom' then v_custom else null end)
  on conflict (user_id, role, custom_label) do nothing;
  return new;
end;
$$;

revoke all on function public.guard_invoice_changes() from public, anon, authenticated;
revoke all on function public.assign_invoice_number() from public, anon, authenticated;
revoke all on function public.finalize_invoice(uuid) from public, anon;
grant execute on function public.finalize_invoice(uuid) to authenticated;
revoke all on function public.cancel_invoice(uuid, text) from public, anon;
grant execute on function public.cancel_invoice(uuid, text) to authenticated;
revoke all on function public.import_patients(jsonb, text) from public, anon;
grant execute on function public.import_patients(jsonb, text) to authenticated;
revoke all on function public.import_pharmacy(jsonb, text, boolean) from public, anon;
grant execute on function public.import_pharmacy(jsonb, text, boolean) to authenticated;
revoke all on function public.import_services(jsonb, text) from public, anon;
grant execute on function public.import_services(jsonb, text) to authenticated;
revoke all on function public.import_appointments(jsonb, text) from public, anon;
grant execute on function public.import_appointments(jsonb, text) to authenticated;
