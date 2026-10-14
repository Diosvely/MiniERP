-- =====================================================================
-- PRUEBAS FASE 29 · Cobros y pagos contra factura (migración 0035)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb,
                                          retencion text default null, clase text default 'invoice', corrige uuid default null)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object(
    'company_id', e, 'invoice_type', tipo, 'document_kind', clase, 'partner_id', tercero,
    'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Prueba', 'withholding_code', retencion,
    'corrected_invoice_id', corrige, 'lines', lineas));
$$;
-- Asiento de un pago en texto
create or replace function public.asiento_pago(p uuid) returns text language sql as $$
  select string_agg(g.account_no || case when l.debit > 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.payments py join erp.journal_lines l on l.entry_id = py.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id where py.id = p;
$$;
create or replace function public.pago(e uuid, tipo text, tercero uuid, fecha date, caja text, apps jsonb) returns uuid language sql as $$
  select payment_id from erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', tipo, 'partner_id', tercero,
    'payment_date', fecha, 'cash_account_no', caja, 'applications', apps));
$$;
create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
create or replace function public.item(e uuid, f uuid, d date) returns record language sql as $$
  select (o.pending, o.status, o.days_overdue, o.due_date)::record from erp.open_items(e, d) o where o.invoice_id = f;
$$;
grant execute on function public.factura(uuid, text, uuid, date, jsonb, text, text, uuid), public.asiento_pago(uuid),
  public.pago(uuid, text, uuid, date, text, jsonb), public.falla(text, text) to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; abogada uuid; otro uuid; viejo uuid; cli uuid; f1 uuid; f2 uuid; f3 uuid; f4 uuid; fv uuid; fo uuid;
        p1 uuid; p2 uuid; pc uuid; pl uuid; manual uuid; n int; o record; a record;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Pagos Madrid SL', 'services', 'mainland', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('62300001', 'Servicios profesionales'), ('70500001', 'Prestaciones de servicios'),
    ('57200001', 'Banco'), ('57000001', 'Caja')) as s(no, name);
  select partner_id into abogada from erp.create_partner(e, 'creditor', 'Abogada Ruiz', '12345678Z');
  select partner_id into otro    from erp.create_partner(e, 'creditor', 'Asesoría Gómez SL', 'B12345674');
  select partner_id into viejo   from erp.create_partner(e, 'creditor', 'Proveedor Antiguo', '87654321X');
  select partner_id into cli     from erp.create_partner(e, 'customer', 'Cliente Madrid SL', 'B11111119');
  update erp.business_partners set payment_days = 30 where id = abogada;

  -- ---------- 1. Vencimiento: fecha de factura + días de pago del tercero ----------
  f1 := public.factura(e, 'purchase', abogada, '2026-02-10', '[{"account_no":"62300001","amount":1000,"tax_code":"VAT21"}]', 'IRPF15');
  assert (select due_date from erp.v_invoices where id = f1) = '2026-03-12', 'vence a 30 días';
  assert (select payment_days from erp.v_partners where id = abogada) = 30;
  select * into o from erp.open_items(e, '2026-03-01') x where x.invoice_id = f1;
  assert o.pending = 1060 and o.status = 'pending' and o.days_overdue = 0, 'pendiente 1.060 (1.210 − 150), sin vencer';
  select * into o from erp.open_items(e, '2026-04-20') x where x.invoice_id = f1;
  assert o.days_overdue = 39, 'vencida hace 39 días: ' || o.days_overdue;
  raise notice 'OK  · vencimiento con los días de pago del tercero; pendiente = total − retención';

  -- ---------- 2. Pago parcial: el ERP hace el asiento 410 a 572 ----------
  p1 := public.pago(e, 'payment', abogada, '2026-03-15', '57200001', jsonb_build_array(jsonb_build_object('invoice_id', f1, 'amount', 500)));
  assert public.asiento_pago(p1) = '41000001 D 500.00 | 57200001 H 500.00', public.asiento_pago(p1);
  select * into o from erp.open_items(e, '2026-03-31') x where x.invoice_id = f1;
  assert o.pending = 560 and o.status = 'partial', 'parcial: quedan 560';
  select * into o from erp.open_items(e, '2026-03-10') x where x.invoice_id = f1;
  assert o.pending = 1060, 'a una fecha anterior al pago, sigue entera';
  assert (select source from erp.v_general_journal where entry_id = (select entry_id from erp.payments where id = p1) limit 1) = 'payment';
  raise notice 'OK  · pago parcial: 41000001 D 500 | 57200001 H 500, la factura queda parcial (y a fecha)';

  -- ---------- 3. Un pago a varias facturas ----------
  f2 := public.factura(e, 'purchase', abogada, '2026-03-01', '[{"account_no":"62300001","amount":1000,"tax_code":"VAT21"}]');
  assert public.falla(format('select public.pago(%L, %L, %L, %L, %L, %L)', e, 'payment', abogada, '2026-04-01', '57200001',
           jsonb_build_array(jsonb_build_object('invoice_id', f1, 'amount', 600))), 'only has 560.00 pending'), 'no se paga de más';
  p2 := public.pago(e, 'payment', abogada, '2026-04-01', '57200001', jsonb_build_array(
          jsonb_build_object('invoice_id', f1, 'amount', 560), jsonb_build_object('invoice_id', f2, 'amount', 1210)));
  assert (select amount from erp.payments where id = p2) = 1770;
  assert (select count(*) from erp.open_items(e, '2026-04-30') x where x.partner_id = abogada and x.status = 'paid') = 2, 'las dos pagadas';
  assert (select invoices from erp.v_payments where id = p2) like '%, %', 'el pago lista sus facturas';
  raise notice 'OK  · un pago liquida dos facturas (560 + 1.210 = 1.770)';

  -- ---------- 4. Cobro de una factura emitida, por caja ----------
  fv := public.factura(e, 'sale', cli, '2026-04-01', '[{"account_no":"70500001","amount":2000,"tax_code":"VAT21"}]');
  pc := public.pago(e, 'collection', cli, '2026-04-05', '57000001', jsonb_build_array(jsonb_build_object('invoice_id', fv, 'amount', 2420)));
  assert public.asiento_pago(pc) = '57000001 D 2420.00 | 43000001 H 2420.00', public.asiento_pago(pc);
  raise notice 'OK  · cobro: 57000001 D 2.420 | 43000001 H 2.420';

  -- ---------- 5. Lo que no se puede ----------
  f3 := public.factura(e, 'purchase', otro, '2026-04-10', '[{"account_no":"62300001","amount":300,"tax_code":"VAT21"}]');
  assert public.falla(format('select public.pago(%L, %L, %L, %L, %L, %L)', e, 'payment', cli, '2026-04-20', '57200001',
           jsonb_build_array(jsonb_build_object('invoice_id', f3, 'amount', 10))), 'needs a vendor or creditor'), 'un pago no es a un cliente';
  assert public.falla(format('select public.pago(%L, %L, %L, %L, %L, %L)', e, 'payment', otro, '2026-04-20', '62300001',
           jsonb_build_array(jsonb_build_object('invoice_id', f3, 'amount', 10))), 'cash or bank account (57)'), 'solo desde una 57';
  assert public.falla(format('select public.pago(%L, %L, %L, %L, %L, %L)', e, 'payment', otro, '2026-04-20', '57200001',
           jsonb_build_array(jsonb_build_object('invoice_id', f2, 'amount', 10))), 'belongs to another partner'), 'factura de otro tercero';
  assert public.falla(format('select public.pago(%L, %L, %L, %L, %L, %L)', e, 'collection', cli, '2026-04-20', '57200001',
           jsonb_build_array(jsonb_build_object('invoice_id', f3, 'amount', 10))), 'another partner'), 'un cobro no paga facturas recibidas';
  assert public.falla(format('select public.pago(%L, %L, %L, %L, %L, %L)', e, 'payment', otro, '2026-04-20', '57200001',
           jsonb_build_array(jsonb_build_object('invoice_id', f3, 'amount', 10), jsonb_build_object('invoice_id', f3, 'amount', 5))), 'twice'),
         'la misma factura dos veces';
  assert public.falla(format('select public.pago(%L, %L, %L, %L, %L, %L)', e, 'payment', otro, '2027-01-20', '57200001',
           jsonb_build_array(jsonb_build_object('invoice_id', f3, 'amount', 10))), 'No fiscal year'), 'sin ejercicio';
  raise notice 'OK  · se rechazan: tercero equivocado, cuenta que no es 57, factura de otro, duplicada, sin ejercicio';

  -- ---------- 6. Rectificativa: reduce lo pendiente; no se le aplican pagos ----------
  f4 := public.factura(e, 'purchase', otro, '2026-04-15', '[{"account_no":"62300001","amount":100,"tax_code":"VAT21"}]', null, 'credit_memo', f3);
  select * into o from erp.open_items(e, '2026-04-30') x where x.invoice_id = f3;
  assert o.pending = 242 and o.credited = -121 and o.status = 'partial', 'pendiente 363 − 121 = 242: ' || o.pending;
  assert public.falla(format('select public.pago(%L, %L, %L, %L, %L, %L)', e, 'payment', otro, '2026-04-20', '57200001',
           jsonb_build_array(jsonb_build_object('invoice_id', f4, 'amount', 10))), 'not to credit memos'), 'no a una rectificativa';
  raise notice 'OK  · la rectificativa reduce lo pendiente (363 − 121 = 242)';

  -- ---------- 7. Anular un cobro: contraasiento y la factura vuelve a estar pendiente ----------
  assert public.falla(format('select erp.reverse_entry(%L)', (select entry_id from erp.payments where id = pc)), 'cancel the payment instead'),
         'el asiento del pago no se anula suelto';
  n := erp.cancel_payment(pc, '2026-04-30', 'Devuelto');
  assert n is not null and (select cancel_entry_no from erp.v_payments where id = pc) = n;
  select * into o from erp.open_items(e, '2026-05-01') x where x.invoice_id = fv;
  assert o.pending = 2420 and o.status = 'pending', 'otra vez pendiente';
  select * into o from erp.open_items(e, '2026-04-20') x where x.invoice_id = fv;
  assert o.pending = 0, 'a una fecha anterior a la anulación, estaba cobrada';
  assert public.falla(format('select erp.cancel_payment(%L)', pc), 'already cancelled');
  raise notice 'OK  · anular un cobro: contraasiento nº % y la factura vuelve a pendiente', n;

  -- ---------- 8. Vincular un pago que ya estaba hecho a mano (contabilidad anterior o importada) ----------
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-05-02', 'Transferencia a Asesoría Gómez')
  returning id into manual;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (manual, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '41000002'), 242, 0),
    (manual, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), 0, 242);
  perform erp.post_entry(manual);
  select count(*) into n from erp.journal_entries where company_id = e;
  assert public.falla(format('select erp.link_payment(%L)', jsonb_build_object('company_id', e, 'entry_id', manual, 'partner_id', otro,
           'applications', jsonb_build_array(jsonb_build_object('invoice_id', f3, 'amount', 242), jsonb_build_object('invoice_id', f4, 'amount', 1)))),
           'not to credit memos'), 'vínculo con una rectificativa';
  pl := erp.link_payment(jsonb_build_object('company_id', e, 'entry_id', manual, 'partner_id', otro,
          'applications', jsonb_build_array(jsonb_build_object('invoice_id', f3, 'amount', 242))));
  assert (select count(*) from erp.journal_entries where company_id = e) = n, 'vincular no crea asientos';
  assert (select status from erp.open_items(e, '2026-05-31') x where x.invoice_id = f3) = 'paid';
  assert (select cash_account_no from erp.v_payments where id = pl) = '57200001' and (select linked from erp.payments where id = pl);
  assert (select source from erp.v_general_journal where entry_id = manual limit 1) = 'manual', 'sigue siendo un asiento manual';
  -- No se vincula más de lo que mueve el asiento, ni un asiento de factura
  fo := public.factura(e, 'purchase', otro, '2026-05-03', '[{"account_no":"62300001","amount":10,"tax_code":"VAT21"}]');
  assert public.falla(format('select erp.link_payment(%L)', jsonb_build_object('company_id', e, 'entry_id', manual, 'partner_id', otro,
           'applications', jsonb_build_array(jsonb_build_object('invoice_id', fo, 'amount', 12.10)))), 'already linked'), 'ya está usado entero';
  assert public.falla(format('select erp.link_payment(%L)', jsonb_build_object('company_id', e, 'entry_id', (select entry_id from erp.invoices where id = f2),
           'partner_id', abogada, 'applications', jsonb_build_array(jsonb_build_object('invoice_id', f1, 'amount', 1)))), 'generated by a document'),
         'el asiento de una factura no es un pago';
  -- Anular el vínculo no toca el asiento manual
  assert erp.cancel_payment(pl) is null;
  assert (select reversed_by from erp.journal_entries where id = manual) is null, 'el asiento manual sigue intacto';
  assert (select status from erp.open_items(e, '2026-05-31') x where x.invoice_id = f3) <> 'paid';
  pl := erp.link_payment(jsonb_build_object('company_id', e, 'entry_id', manual, 'partner_id', otro,
          'applications', jsonb_build_array(jsonb_build_object('invoice_id', f3, 'amount', 242))));
  assert public.falla(format('select erp.reverse_entry(%L)', manual), 'cancel the payment instead'), 'vinculado: se anula el pago primero';
  raise notice 'OK  · un pago hecho a mano se vincula a su factura sin asiento nuevo (y se puede desvincular)';

  -- ---------- 9. Antigüedad de saldos ----------
  f1 := public.factura(e, 'purchase', viejo, '2026-01-10', '[{"account_no":"62300001","amount":500,"tax_code":"VAT21"}]');   -- 605, vence ese día
  -- Un pago a mano al proveedor antiguo, sin vincular: el saldo contable ya no coincide con lo pendiente
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-05-20', 'Pago a cuenta sin factura')
  returning id into manual;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (manual, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '41000003'), 100, 0),
    (manual, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), 0, 100);
  perform erp.post_entry(manual);

  select * into a from erp.aging(e, 'purchase', '2026-05-31') x where x.partner_id = viejo;
  assert a.d90_plus = 605 and a.total = 605 and a.open_invoices = 1, 'vencida hace 141 días → más de 90';
  assert a.account_balance = 505, 'saldo contable 605 − 100: ' || a.account_balance;
  select * into a from erp.aging(e, 'purchase', '2026-05-31') x where x.partner_id = otro;
  assert a.total = 12.10 and a.d1_30 = 12.10 and a.account_balance = 12.10, 'Asesoría: solo la última factura (al contado: vencida hace 28 días)';
  assert not exists (select 1 from erp.aging(e, 'purchase', '2026-05-31') x where x.partner_id = abogada), 'la abogada no debe nada';
  select * into a from erp.aging(e, 'sale', '2026-05-31') x where x.partner_id = cli;
  assert a.total = 2420 and a.d31_60 = 2420 and a.account_balance = 2420, 'el cliente: 2.420, vencido hace 60 días';
  raise notice 'OK  · antigüedad: por tramos, y el saldo contable al lado (605 pendiente ≠ 505 en la cuenta: hay un pago sin vincular)';
end $$;

-- ---------- 10. Permisos ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa');
begin
  assert (select count(*) from erp.v_payments where company_id = e) > 0, 'el lector ve los pagos';
  assert (select count(*) from erp.open_items(e, '2026-05-31')) > 0, 'y las partidas abiertas';
  assert public.falla(format('select public.pago(%L, %L, %L, %L, %L, %L)', e, 'payment',
           (select id from erp.business_partners where company_id = e and name = 'Asesoría Gómez SL'), '2026-05-20', '57200001',
           '[]'), 'No permission'), 'el lector no paga';
  assert public.falla(format('select erp.cancel_payment(%L)', (select id from erp.payments where company_id = e limit 1)), 'no permission'),
         'ni anula';
  begin
    insert into erp.payments (company_id, payment_type, partner_id, payment_date, amount, entry_id)
    select e, 'payment', partner_id, payment_date, 1, entry_id from erp.payments limit 1;
    raise exception 'FALLO: se ha insertado un pago a mano';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK  · el lector ve pagos y partidas abiertas, pero no paga, no anula ni escribe en las tablas';
end $$;

-- ---------- 11. Borrar la empresa con pagos ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa'); n int; vueltas int := 0;
begin
  loop
    n := erp.delete_company_step(e, 3);
    vueltas := vueltas + 1;
    exit when n = 0;
    assert vueltas < 30, 'el borrado no termina';
  end loop;
  assert not exists (select 1 from erp.companies where id = e);
  raise notice 'OK  · una empresa con pagos se borra entera (% tandas)', vueltas;
end $$;
reset role;
do $$ begin
  assert not exists (select 1 from erp.payments) and not exists (select 1 from erp.payment_applications), 'no quedan pagos';
end $$;

\echo '✔ FASE 29 OK · cobros y pagos contra factura'
