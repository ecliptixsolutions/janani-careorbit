alter table public.patients
  add column if not exists case_fee numeric(12,2),
  add column if not exists sonography_fee numeric(12,2);

alter table public.patients
  drop constraint if exists patients_case_fee_check,
  add constraint patients_case_fee_check check (case_fee is null or case_fee >= 0),
  drop constraint if exists patients_sonography_fee_check,
  add constraint patients_sonography_fee_check check (
    sonography_fee is null or sonography_fee >= 0
  );

alter table public.pharmacy_items
  add column if not exists mrp numeric(12,2),
  add column if not exists gst_rate numeric(5,2) not null default 0,
  add column if not exists hsn_code text;

update public.pharmacy_items set mrp = unit_price where mrp is null;

alter table public.pharmacy_items
  alter column mrp set default 0,
  alter column mrp set not null,
  drop constraint if exists pharmacy_items_mrp_check,
  add constraint pharmacy_items_mrp_check check (mrp >= 0),
  drop constraint if exists pharmacy_items_gst_rate_check,
  add constraint pharmacy_items_gst_rate_check check (gst_rate between 0 and 100);

alter table public.organization_settings
  add column if not exists drug_license_numbers text[] not null default '{}'::text[],
  add column if not exists invoice_accent_color text not null default '#2563eb';

alter table public.organization_settings
  drop constraint if exists organization_invoice_accent_color_check,
  add constraint organization_invoice_accent_color_check
    check (invoice_accent_color ~ '^#[0-9A-Fa-f]{6}$');

alter table public.invoices
  alter column patient_id drop not null,
  add column if not exists invoice_type text not null default 'general',
  add column if not exists walk_in_name text,
  add column if not exists walk_in_phone text,
  add column if not exists cgst_amount numeric(12,2) not null default 0,
  add column if not exists sgst_amount numeric(12,2) not null default 0,
  add column if not exists amount_received numeric(12,2) not null default 0,
  add column if not exists change_due numeric(12,2) not null default 0,
  add column if not exists brand_snapshot jsonb not null default '{}'::jsonb;

alter table public.invoices
  drop constraint if exists invoices_invoice_type_check,
  add constraint invoices_invoice_type_check check (invoice_type in ('general', 'pharmacy')),
  drop constraint if exists invoices_patient_or_walk_in_check,
  add constraint invoices_patient_or_walk_in_check check (
    invoice_type <> 'pharmacy'
    or patient_id is not null
    or length(trim(coalesce(walk_in_name, ''))) >= 2
  );

alter table public.dispensations
  alter column patient_id drop not null,
  add column if not exists invoice_id uuid references public.invoices(id) on delete set null;

create table if not exists public.pharmacy_invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  pharmacy_item_id uuid references public.pharmacy_items(id) on delete set null,
  medicine_name text not null,
  sku text,
  hsn_code text,
  batch_number text,
  expires_on date,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  mrp numeric(12,2) not null check (mrp >= 0),
  discount_percent numeric(5,2) not null default 0 check (discount_percent between 0 and 100),
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  gst_rate numeric(5,2) not null default 0 check (gst_rate between 0 and 100),
  taxable_amount numeric(12,2) not null default 0 check (taxable_amount >= 0),
  tax_amount numeric(12,2) not null default 0 check (tax_amount >= 0),
  line_total numeric(12,2) not null default 0 check (line_total >= 0),
  created_at timestamptz not null default now()
);

create index if not exists pharmacy_invoice_items_invoice_idx
  on public.pharmacy_invoice_items(invoice_id);
create index if not exists invoices_type_created_idx
  on public.invoices(invoice_type, created_at desc);
create index if not exists dispensations_invoice_idx
  on public.dispensations(invoice_id);

alter table public.pharmacy_invoice_items enable row level security;

drop policy if exists "Pharmacy users view pharmacy invoices" on public.invoices;
create policy "Pharmacy users view pharmacy invoices"
  on public.invoices for select to authenticated
  using (
    invoice_type = 'pharmacy'
    and (
      public.has_role(auth.uid(), 'admin')
      or public.has_custom_role(auth.uid(), 'pharmacist')
    )
  );

drop policy if exists "Pharmacy users view pharmacy payments" on public.payments;
create policy "Pharmacy users view pharmacy payments"
  on public.payments for select to authenticated
  using (
    exists (
      select 1 from public.invoices i
      where i.id = payments.invoice_id
        and i.invoice_type = 'pharmacy'
    )
    and (
      public.has_role(auth.uid(), 'admin')
      or public.has_custom_role(auth.uid(), 'pharmacist')
    )
  );

drop policy if exists "Pharmacy users view invoice items" on public.pharmacy_invoice_items;
create policy "Pharmacy users view invoice items"
  on public.pharmacy_invoice_items for select to authenticated
  using (
    public.has_role(auth.uid(), 'admin')
    or public.has_custom_role(auth.uid(), 'pharmacist')
    or public.has_custom_role(auth.uid(), 'billing_operator')
  );

create or replace function public.assign_invoice_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  prefix text;
begin
  if new.invoice_type = 'pharmacy' then
    prefix := 'PH-INV';
  else
    select upper(coalesce(nullif(trim(invoice_prefix), ''), 'INV'))
    into prefix
    from public.organization_settings
    where id = '00000000-0000-0000-0000-000000000001';
  end if;

  new.invoice_number := coalesce(prefix, 'INV') || '-' || to_char(now(), 'YYYYMM') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  return new;
end;
$$;

create or replace function public.create_pharmacy_bill(
  _patient_id uuid,
  _walk_in_name text,
  _walk_in_phone text,
  _items jsonb,
  _payment_amount numeric default 0,
  _payment_method text default 'cash',
  _payment_reference text default null,
  _notes text default null,
  _save_as_draft boolean default false,
  _draft_id uuid default null
)
returns public.invoices
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  current_item public.pharmacy_items%rowtype;
  invoice_row public.invoices%rowtype;
  invoice_items jsonb := '[]'::jsonb;
  quantity_value integer;
  discount_percent_value numeric;
  gross_value numeric;
  discount_value numeric;
  taxable_value numeric;
  tax_value numeric;
  line_total_value numeric;
  subtotal_value numeric := 0;
  discount_total_value numeric := 0;
  tax_total_value numeric := 0;
  total_value numeric := 0;
  receipt text;
  settings_snapshot jsonb;
begin
  if not (
    public.has_role(auth.uid(), 'admin')
    or public.has_custom_role(auth.uid(), 'pharmacist')
  ) then
    raise exception 'Pharmacy access required';
  end if;
  if _patient_id is null and length(trim(coalesce(_walk_in_name, ''))) < 2 then
    raise exception 'Select a patient or enter the walk-in customer name';
  end if;
  if _patient_id is not null and not exists (
    select 1 from public.patients where id = _patient_id
  ) then
    raise exception 'Patient not found';
  end if;
  if jsonb_typeof(_items) <> 'array' or jsonb_array_length(_items) = 0 then
    raise exception 'Add at least one medicine';
  end if;
  if jsonb_array_length(_items) > 100 then
    raise exception 'A pharmacy bill can contain at most 100 lines';
  end if;
  if _payment_method not in ('cash', 'card', 'upi') then
    raise exception 'Unsupported pharmacy payment method';
  end if;

  for item in select * from jsonb_array_elements(_items)
  loop
    quantity_value := coalesce((item->>'quantity')::integer, 0);
    discount_percent_value := coalesce((item->>'discountPercent')::numeric, 0);
    if quantity_value <= 0 then raise exception 'Medicine quantity must be greater than zero'; end if;
    if discount_percent_value not between 0 and 100 then
      raise exception 'Discount must be between 0 and 100';
    end if;

    select * into current_item
    from public.pharmacy_items
    where id = (item->>'pharmacyItemId')::uuid
    for update;

    if current_item.id is null then raise exception 'Medicine batch not found'; end if;
    if current_item.expires_on is not null and current_item.expires_on < current_date then
      raise exception '% batch % is expired', current_item.medicine_name, current_item.batch_number;
    end if;
    if not _save_as_draft and current_item.stock_quantity < quantity_value then
      raise exception 'Insufficient stock for % batch %',
        current_item.medicine_name, current_item.batch_number;
    end if;

    gross_value := round(current_item.unit_price * quantity_value, 2);
    discount_value := round(gross_value * discount_percent_value / 100, 2);
    taxable_value := gross_value - discount_value;
    tax_value := round(taxable_value * current_item.gst_rate / 100, 2);
    line_total_value := taxable_value + tax_value;
    subtotal_value := subtotal_value + gross_value;
    discount_total_value := discount_total_value + discount_value;
    tax_total_value := tax_total_value + tax_value;
    total_value := total_value + line_total_value;

    invoice_items := invoice_items || jsonb_build_array(jsonb_build_object(
      'pharmacyItemId', current_item.id,
      'description', current_item.medicine_name,
      'medicineName', current_item.medicine_name,
      'serviceCode', current_item.sku,
      'sku', current_item.sku,
      'hsnCode', current_item.hsn_code,
      'batchNumber', current_item.batch_number,
      'expiryDate', current_item.expires_on,
      'quantity', quantity_value,
      'unitPrice', current_item.unit_price,
      'mrp', current_item.mrp,
      'discountPercent', discount_percent_value,
      'discountAmount', discount_value,
      'taxRate', current_item.gst_rate,
      'taxableAmount', taxable_value,
      'taxAmount', tax_value,
      'amount', line_total_value
    ));
  end loop;

  if total_value <= 0 then raise exception 'Bill total must be greater than zero'; end if;
  if _payment_amount < 0 then
    raise exception 'Payment cannot be negative';
  end if;
  if _payment_method <> 'cash' and _payment_amount > total_value then
    raise exception 'Card or UPI payment cannot exceed the bill total';
  end if;
  if _save_as_draft and _payment_amount <> 0 then
    raise exception 'Draft bills cannot contain payments';
  end if;

  if _draft_id is not null then
    if not exists (
      select 1 from public.invoices
      where id = _draft_id
        and invoice_type = 'pharmacy'
        and status = 'draft'
        and (created_by = auth.uid() or public.has_role(auth.uid(), 'admin'))
    ) then
      raise exception 'Pharmacy draft not found or cannot be changed';
    end if;
    delete from public.invoices where id = _draft_id;
  end if;

  select to_jsonb(s) - 'updated_by' into settings_snapshot
  from public.organization_settings s
  where id = '00000000-0000-0000-0000-000000000001';

  insert into public.invoices (
    patient_id, items, subtotal, discount_amount, tax_amount, total_amount,
    paid_amount, status, notes, created_by, updated_by, invoice_type,
    walk_in_name, walk_in_phone, cgst_amount, sgst_amount, brand_snapshot,
    amount_received, change_due, finalized_at
  ) values (
    _patient_id, invoice_items, round(subtotal_value, 2), round(discount_total_value, 2),
    round(tax_total_value, 2), round(total_value, 2), 0,
    case when _save_as_draft then 'draft' else 'issued' end,
    nullif(trim(coalesce(_notes, '')), ''), auth.uid(), auth.uid(), 'pharmacy',
    case when _patient_id is null then trim(_walk_in_name) else null end,
    case when _patient_id is null then nullif(trim(coalesce(_walk_in_phone, '')), '') else null end,
    round(tax_total_value / 2, 2), round(tax_total_value - round(tax_total_value / 2, 2), 2),
    coalesce(settings_snapshot, '{}'::jsonb),
    case when _save_as_draft then 0 else round(_payment_amount, 2) end,
    case
      when _save_as_draft then 0
      else greatest(round(_payment_amount - total_value, 2), 0)
    end,
    case when _save_as_draft then null else now() end
  )
  returning * into invoice_row;

  if not _save_as_draft then
    for item in select * from jsonb_array_elements(invoice_items)
    loop
      insert into public.pharmacy_invoice_items (
        invoice_id, pharmacy_item_id, medicine_name, sku, hsn_code, batch_number,
        expires_on, quantity, unit_price, mrp, discount_percent, discount_amount,
        gst_rate, taxable_amount, tax_amount, line_total
      ) values (
        invoice_row.id, (item->>'pharmacyItemId')::uuid, item->>'medicineName',
        nullif(item->>'sku', ''), nullif(item->>'hsnCode', ''), nullif(item->>'batchNumber', ''),
        nullif(item->>'expiryDate', '')::date, (item->>'quantity')::integer,
        (item->>'unitPrice')::numeric, (item->>'mrp')::numeric,
        (item->>'discountPercent')::numeric, (item->>'discountAmount')::numeric,
        (item->>'taxRate')::numeric, (item->>'taxableAmount')::numeric,
        (item->>'taxAmount')::numeric, (item->>'amount')::numeric
      );

      update public.pharmacy_items
      set stock_quantity = stock_quantity - (item->>'quantity')::integer
      where id = (item->>'pharmacyItemId')::uuid;

      insert into public.dispensations (
        patient_id, pharmacy_item_id, quantity, unit_price, dispensed_by, invoice_id
      ) values (
        _patient_id, (item->>'pharmacyItemId')::uuid, (item->>'quantity')::integer,
        (item->>'unitPrice')::numeric, auth.uid(), invoice_row.id
      );
    end loop;

    if _payment_amount > 0 then
      receipt := 'RCT-' || to_char(now(), 'YYYYMM') || '-' ||
        upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
      insert into public.payments (
        invoice_id, amount, method, reference, received_by, receipt_number
      ) values (
        invoice_row.id, round(least(_payment_amount, total_value), 2), _payment_method,
        nullif(trim(coalesce(_payment_reference, '')), ''), auth.uid(), receipt
      );

      update public.invoices
      set paid_amount = round(least(_payment_amount, total_amount), 2),
          status = case
            when round(least(_payment_amount, total_amount), 2) >= total_amount then 'paid'
            else 'partially_paid'
          end,
          updated_by = auth.uid()
      where id = invoice_row.id
      returning * into invoice_row;
    end if;
  end if;

  return invoice_row;
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
    or new.invoice_type is distinct from old.invoice_type
    or new.patient_id is distinct from old.patient_id
    or new.walk_in_name is distinct from old.walk_in_name
    or new.walk_in_phone is distinct from old.walk_in_phone
    or new.appointment_id is distinct from old.appointment_id
    or new.items is distinct from old.items
    or new.subtotal is distinct from old.subtotal
    or new.discount_amount is distinct from old.discount_amount
    or new.tax_amount is distinct from old.tax_amount
    or new.cgst_amount is distinct from old.cgst_amount
    or new.sgst_amount is distinct from old.sgst_amount
    or new.total_amount is distinct from old.total_amount
    or new.amount_received is distinct from old.amount_received
    or new.change_due is distinct from old.change_due
    or new.brand_snapshot is distinct from old.brand_snapshot
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

drop trigger if exists pharmacy_invoice_items_audit on public.pharmacy_invoice_items;
create trigger pharmacy_invoice_items_audit
after insert or update or delete on public.pharmacy_invoice_items
for each row execute function public.capture_audit_log();

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
  mrp_value numeric;
  gst_value numeric;
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
      existing_id := null;
      if length(trim(coalesce(item->>'medicine_name', ''))) < 2 then
        raise exception 'Medicine name is required';
      end if;
      qty := coalesce(nullif(item->>'quantity', '')::integer, 0);
      reorder_qty := coalesce(nullif(item->>'reorder_level', '')::integer, 0);
      price := coalesce(nullif(item->>'unit_price', '')::numeric, 0);
      mrp_value := coalesce(nullif(item->>'mrp', '')::numeric, price);
      gst_value := coalesce(nullif(item->>'gst_rate', '')::numeric, 0);
      expiry := nullif(item->>'expiry_date', '')::date;
      if qty < 0 or reorder_qty < 0 or price < 0 or mrp_value < 0 then
        raise exception 'Quantity, reorder level, unit price and MRP cannot be negative';
      end if;
      if gst_value not between 0 and 100 then
        raise exception 'GST rate must be between 0 and 100';
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
          unit_price = price,
          mrp = mrp_value,
          gst_rate = gst_value,
          hsn_code = nullif(trim(item->>'hsn_code'), '')
        where id = existing_id;
      else
        insert into public.pharmacy_items (
          medicine_name, sku, batch_number, expires_on, stock_quantity,
          reorder_level, unit_price, mrp, gst_rate, hsn_code, created_by
        ) values (
          trim(item->>'medicine_name'), nullif(trim(item->>'sku'), ''),
          nullif(trim(item->>'batch_number'), ''), expiry, qty,
          reorder_qty, price, mrp_value, gst_value,
          nullif(trim(item->>'hsn_code'), ''), auth.uid()
        );
      end if;
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
    'pharmacy', _file_name, row_no, imported, skipped,
    jsonb_array_length(errors),
    jsonb_build_object('errors', errors, 'update_existing', _update_existing),
    auth.uid()
  );
  return jsonb_build_object(
    'total', row_no, 'imported', imported, 'skipped', skipped, 'errors', errors
  );
end;
$$;

revoke all on function public.create_pharmacy_bill(
  uuid, text, text, jsonb, numeric, text, text, text, boolean, uuid
) from public, anon;
grant execute on function public.create_pharmacy_bill(
  uuid, text, text, jsonb, numeric, text, text, text, boolean, uuid
) to authenticated;
