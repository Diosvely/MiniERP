-- =====================================================================
-- PRUEBAS FASE 6 · registro de facturas (migración 0011)
-- Ejecutar en una base limpia: stub + migraciones 0001-0011.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local');

create or replace function public.debe_fallar(p_sql text, p_texto text, p_prueba text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm ilike '%' || p_texto || '%' then
      raise notice 'OK  · %  →  %', p_prueba, sqlerrm;
      return;
    end if;
    raise exception 'FALLO · % · error inesperado: %', p_prueba, sqlerrm;
  end;
  raise exception 'FALLO · % · debía dar error y no lo dio', p_prueba;
end $$;
grant execute on function public.debe_fallar(text, text, text) to authenticated;
create table public.ctx (clave text primary key, valor uuid);
grant all on public.ctx to authenticated;

-- Asiento de una factura en texto: "cuenta D/H importe" ordenado por línea
create or replace function public.asiento(p_invoice uuid) returns text language sql as $$
  select string_agg(g.account_no || case when l.debit > 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.invoices i join erp.journal_lines l on l.entry_id = i.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id where i.id = p_invoice;
$$;
grant execute on function public.asiento(uuid) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare
  e uuid; ej uuid; prov uuid; acre uuid; cli uuid; r record; f1 uuid; v text; j jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Comercial Canaria', 'retail', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  ej := erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('60000001', 'Compras de mercaderías'), ('60800001', 'Devoluciones de compras'),
    ('60900001', 'Rappels por compras'), ('62300001', 'Servicios profesionales'),
    ('70000001', 'Ventas de mercaderías'), ('70800001', 'Devoluciones de ventas'),
    ('70600001', 'Descuentos sobre ventas por pronto pago'), ('57200001', 'Banco')) as s(no, name);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Distribuciones Atlántico SL', 'B12345674');
  select partner_id into acre from erp.create_partner(e, 'creditor', 'Asesoría Martín', '12345678Z');
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Hotel Playa SL', 'B11111119');

  -- ---------- 1. Factura recibida: compra de mercaderías con IGIC 7 % ----------
  j := jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'partner_id', prov,
        'external_document_no', 'DA-0451', 'invoice_date', '2026-01-10', 'posting_date', '2026-01-12',
        'lines', jsonb_build_array(jsonb_build_object('account_no', '60000001', 'amount', 1000, 'tax_code', 'IGIC7')));
  -- La vista previa no guarda nada
  assert (select count(*) from erp.preview_invoice(j)) = 3;
  assert (select count(*) from erp.invoices) = 0, 'la vista previa no registra';
  select * into r from erp.post_invoice(j);
  f1 := r.invoice_id;
  assert r.invoice_no = 'C-2026-0001', r.invoice_no;
  v := public.asiento(f1);
  assert v = '60000001 D 1000.00 | 47210007 D 70.00 | 40000001 H 1070.00', v;
  assert (select total_base || '/' || total_tax || '/' || total_amount from erp.invoices where id = f1) = '1000.00/70.00/1070.00';
  assert (select status from erp.journal_entries where id = (select entry_id from erp.invoices where id = f1)) = 'posted';
  raise notice 'OK  · recibida: 600 D 1.000 · 472 D 70 · 400 H 1.070 (asiento contabilizado, nº registro C-2026-0001)';

  -- ---------- 2. Factura duplicada del mismo proveedor ----------
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', j), 'already registered', 'factura del proveedor repetida');

  -- ---------- 3. Recibida con devolución (608) y rappel (609) en la misma factura ----------
  select * into r from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'partner_id', prov,
        'external_document_no', 'DA-0480', 'invoice_date', '2026-02-01',
        'lines', jsonb_build_array(
          jsonb_build_object('account_no', '60000001', 'amount', 2000, 'tax_code', 'IGIC7'),
          jsonb_build_object('account_no', '60800001', 'amount', 200, 'tax_code', 'IGIC7'),
          jsonb_build_object('account_no', '60900001', 'amount', 100, 'tax_code', 'IGIC7'))));
  v := public.asiento(r.invoice_id);
  assert v = '60000001 D 2000.00 | 60800001 H 200.00 | 60900001 H 100.00 | 47210007 D 119.00 | 40000001 H 1819.00', v;
  raise notice 'OK  · regla del lado: 608 y 609 al Haber; cuota sobre la base neta 1.700 → 119';

  -- ---------- 4. Rectificativa recibida (abono del proveedor por devolución) ----------
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', jsonb_build_object('company_id', e,
        'invoice_type', 'purchase', 'document_kind', 'credit_memo', 'partner_id', prov, 'external_document_no', 'AB-01',
        'invoice_date', '2026-02-10', 'lines', jsonb_build_array(jsonb_build_object('account_no', '60800001', 'amount', 100, 'tax_code', 'IGIC7')))),
        'must identify', 'rectificativa sin factura de origen');
  select * into r from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase',
        'document_kind', 'credit_memo', 'partner_id', prov, 'external_document_no', 'AB-01', 'corrected_invoice_id', f1,
        'invoice_date', '2026-02-10',
        'lines', jsonb_build_array(jsonb_build_object('account_no', '60800001', 'amount', 100, 'tax_code', 'IGIC7'))));
  assert r.invoice_no = 'CR-2026-0001', r.invoice_no;
  v := public.asiento(r.invoice_id);
  assert v = '60800001 H 100.00 | 47210007 H 7.00 | 40000001 D 107.00', v;
  assert (select total_amount from erp.invoices where id = r.invoice_id) = -107;
  raise notice 'OK  · rectificativa recibida: 400 D 107 · 608 H 100 · 472 H 7 (total −107)';

  -- ---------- 5. Servicios de un acreedor con varios tipos y redondeo ----------
  select * into r from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'partner_id', acre,
        'external_document_no', '2026/15', 'invoice_date', '2026-03-05',
        'lines', jsonb_build_array(
          jsonb_build_object('account_no', '62300001', 'amount', 333.33, 'tax_code', 'IGIC7'),
          jsonb_build_object('account_no', '62300001', 'amount', 50, 'tax_code', 'IGIC0'))));
  v := public.asiento(r.invoice_id);
  assert v = '62300001 D 333.33 | 62300001 D 50.00 | 47210007 D 23.33 | 41000001 H 406.66', v;
  assert (select count(*) from erp.v_invoice_register where invoice_id = r.invoice_id) = 2, 'el 0 % también va al libro registro';
  raise notice 'OK  · varios tipos: el IGIC 0 %% no genera apunte pero sí línea en el libro registro; 333,33 × 7 %% = 23,33';

  -- ---------- 6. Factura emitida y rectificativa emitida ----------
  select * into r from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'sale', 'partner_id', cli,
        'invoice_date', '2026-03-10', 'description', 'Venta marzo',
        'lines', jsonb_build_array(
          jsonb_build_object('account_no', '70000001', 'amount', 5000, 'tax_code', 'IGIC7'),
          jsonb_build_object('account_no', '70600001', 'amount', 100, 'tax_code', 'IGIC7'))));
  assert r.invoice_no = 'F-2026-0001';
  f1 := r.invoice_id;
  v := public.asiento(f1);
  assert v = '70000001 H 5000.00 | 70600001 D 100.00 | 47710007 H 343.00 | 43000001 D 5243.00', v;
  assert (select document_no from erp.journal_entries where id = (select entry_id from erp.invoices where id = f1)) = 'F-2026-0001';
  select * into r from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'sale', 'partner_id', cli,
        'document_kind', 'credit_memo', 'corrected_invoice_id', f1, 'invoice_date', '2026-03-20',
        'lines', jsonb_build_array(jsonb_build_object('account_no', '70800001', 'amount', 500, 'tax_code', 'IGIC7'))));
  assert r.invoice_no = 'R-2026-0001';
  v := public.asiento(r.invoice_id);
  assert v = '70800001 D 500.00 | 47710007 D 35.00 | 43000001 H 535.00', v;
  raise notice 'OK  · emitida: 430 D 5.243 · 700 H 5.000 · 706 D 100 · 477 H 343 · rectificativa R-2026-0001: 708 D · 477 D · 430 H';

  -- Libro registro y saldo del cliente
  assert (select sum(tax_amount) from erp.v_invoice_register where company_id = e and invoice_type = 'sale') = 308;
  assert (select balance from erp.v_partners where id = cli) = 4708;
  assert (select sum(tax_amount) from erp.v_tax_book where company_id = e and tax_class = 'output') = 308,
         'el libro de IVA/IGIC cuadra con el registro de facturas';
  raise notice 'OK  · libro registro de emitidas = libro de IGIC repercutido (308) · saldo cliente 4.708';

  -- ---------- 7. Reglas contables ----------
  j := jsonb_build_object('company_id', e, 'invoice_type', 'sale', 'partner_id', cli, 'invoice_date', '2026-04-01',
        'lines', jsonb_build_array(jsonb_build_object('account_no', '60000001', 'amount', 10, 'tax_code', 'IGIC7')));
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', j), 'use group 7', 'venta a una cuenta de gastos');
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', jsonb_set(j, '{partner_id}', to_jsonb(prov))),
        'needs a customer', 'emitida a un proveedor');
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', jsonb_set(j, '{lines,0}',
        '{"account_no":"70000001","amount":10,"tax_code":"VAT21"}')), 'not set up', 'tipo de IVA no configurado');
  update erp.tax_setup set blocked = true where company_id = e and tax_code = 'IGIC20';
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', jsonb_set(j, '{lines,0}',
        '{"account_no":"70000001","amount":10,"tax_code":"IGIC20"}')), 'not set up', 'tipo bloqueado');
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', jsonb_set(j, '{lines,0}',
        '{"account_no":"70800001","amount":10,"tax_code":"IGIC7"}')), 'credit memo', 'factura con total negativo');
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', jsonb_set(j, '{lines,0}',
        '{"account_no":"70000001","amount":0,"tax_code":"IGIC7"}')), 'greater than zero', 'importe cero');
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', jsonb_set(jsonb_set(j, '{lines,0}',
        '{"account_no":"70000001","amount":10,"tax_code":"IGIC7"}'), '{posting_date}', '"2026-03-01"')),
        'earlier than the invoice date', 'contabilizar antes de la fecha de factura');
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', jsonb_build_object('company_id', e,
        'invoice_type', 'purchase', 'partner_id', prov, 'invoice_date', '2026-04-01',
        'lines', jsonb_build_array(jsonb_build_object('account_no', '60000001', 'amount', 10, 'tax_code', 'IGIC7')))),
        'vendor invoice number', 'recibida sin nº de factura del proveedor');

  -- ---------- 8. Inmutabilidad ----------
  perform public.debe_fallar(format('update erp.invoices set total_amount = 1 where id = %L', f1), 'permission denied', 'modificar una factura (sin permiso de UPDATE)');
  perform public.debe_fallar(format('delete from erp.invoices where id = %L', f1), 'permission denied', 'borrar una factura (sin permiso de DELETE)');
  perform public.debe_fallar(format('select erp.reverse_entry(%L)', (select entry_id from erp.invoices where id = f1)),
        'issue a credit memo', 'anular el asiento de una factura');
  perform public.debe_fallar(format('insert into erp.invoice_tax_lines values (%L, %L, %L, 1, 1)', f1, e, 'IGIC3'),
        'post_invoice', 'insertar a mano en el libro registro');
end $$;

-- ---------- Un lector no registra facturas ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  assert (select count(*) from erp.v_invoices where company_id = e) = 6, 'el lector ve las facturas';
  perform public.debe_fallar(format('select * from erp.post_invoice(%L)', jsonb_build_object('company_id', e,
        'invoice_type', 'sale', 'invoice_date', '2026-04-01')), 'No permission', 'un viewer no registra facturas');
end $$;

-- ---------- Borrar la empresa borra sus facturas ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  perform erp.delete_company(e);
  assert not exists (select 1 from erp.invoices where company_id = e);
  raise notice 'OK  · borrar la empresa borra sus facturas';
end $$;

reset role;
drop table public.ctx;
drop function public.debe_fallar(text, text, text);
drop function public.asiento(uuid);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 6 (FACTURAS) PASARON ==========='
