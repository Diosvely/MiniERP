-- =====================================================================
-- PRUEBAS FASE 39 · Ajustes de cierre integrados (migración 0044)
--   comprobaciones (480 / 485 / 4009 / 4309 / 490 frente a sus fichas, periodificaciones sin revertir, deterioros de
--   facturas cobradas), aviso en el cierre y conceptos del glosario
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb) returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', tipo, 'document_kind', 'invoice',
    'partner_id', tercero, 'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Prueba', 'lines', lineas));
$$;
create or replace function public.chk(e uuid, c text, d date) returns text language sql as $$
  select r.status || ' · ' || r.items from erp.run_audit_checks(e, extract(year from d)::int, d) r where r.code = c;
$$;
grant execute on function public.factura(uuid, text, uuid, date, jsonb), public.chk(uuid, text, date) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; cli uuid; f uuid; a uuid; d uuid; r record; c jsonb; l uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Integración Ajustes SL', 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, x.no, x.name) from (values
    ('62500001', 'Seguros'), ('70500001', 'Servicios'), ('57200001', 'Banco')) as x(no, name);
  select partner_id into cli from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');

  -- ---------- 1. Conceptos del glosario ----------
  assert (select term from erp.concepts where key = 'deferral') = 'Periodificación';
  assert (select term from erp.concepts where key = 'badDebt') = 'Deterioro de clientes';
  assert (select string_agg(key, ',' order by key) from erp.concepts_for_account('48000001')) like '%deferral%', 'la 480 → periodificación';
  assert (select string_agg(key, ',' order by key) from erp.concepts_for_account('49000001')) like '%badDebt%', 'la 490 → deterioro';
  assert (select concept from erp.audit_checks where code = 'impairments_collected') = 'badDebt';
  raise notice 'OK  · conceptos «Periodificación» y «Deterioro de clientes» (la 480 y la 490 los encuentran)';

  -- ---------- 2. Ajustes con ficha: todo cuadra ----------
  select accrual_id into a from erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'prepaid_expense', 'description', 'Seguro',
    'pl_account_no', '62500001', 'cutoff_date', '2026-12-31', 'amount', 900));
  f := public.factura(e, 'sale', cli, '2026-03-01', '[{"account_no":"70500001","amount":1000,"tax_code":"VAT21"}]');
  select impairment_id into d from erp.impair_receivable(jsonb_build_object('invoice_id', f, 'impair_date', '2026-12-31'));
  assert public.chk(e, 'adjustments_ledger', '2026-12-31') = 'ok · 0', public.chk(e, 'adjustments_ledger', '2026-12-31');
  assert public.chk(e, 'adjustments_ledger', '2026-12-30') = 'ok · 0', 'antes del corte, nada (ni ficha ni saldo)';
  raise notice 'OK  · 480 = 900 y 490 = 1.210, igual que sus fichas';

  -- ---------- 3. Un asiento manual a la 480 (modo guiado) descuadra ----------
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-12-31', 'Periodificación a mano') returning id into l;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (l, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '48000001'), 100, 0),
    (l, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '62500001'), 0, 100);
  perform erp.post_entry(l);
  select * into r from erp.run_audit_checks(e, 2026, '2026-12-31') x where x.code = 'adjustments_ledger';
  assert r.status = 'warning' and r.items = 1 and r.details->0->>'account_no' = '48000001'
     and (r.details->0->>'book')::numeric = 900 and (r.details->0->>'balance')::numeric = 1000 and r.screen = 'adjustments',
     'fichas 900 · cuenta 1.000: ' || r.details::text;
  perform erp.reverse_entry(l, '2026-12-31', 'Se registra en Ajustes de cierre');
  assert public.chk(e, 'adjustments_ledger', '2026-12-31') = 'ok · 0', 'anulado, vuelve a cuadrar';
  raise notice 'OK  · un asiento manual de 100 a la 480: fichas 900 frente a la cuenta 1.000; anulado, cuadra';

  -- ---------- 4. Periodificación sin revertir: comprobación y aviso del cierre ----------
  assert public.chk(e, 'accruals_unreversed', '2026-12-31') = 'ok · 0', 'en su año, no';
  assert public.chk(e, 'accruals_unreversed', '2027-01-01') = 'warning · 1', 'en el siguiente, sí';
  c := erp.year_closing_preview(e, 2027);
  assert c->'checks' @> jsonb_build_array(jsonb_build_object('code', 'accruals_unreversed', 'severity', 'warning', 'detail', 'PER-0001')),
         'el cierre de 2027 avisa: ' || (c->'checks')::text;
  perform erp.reverse_accrual(a);
  assert public.chk(e, 'accruals_unreversed', '2027-01-01') = 'ok · 0';
  assert public.chk(e, 'adjustments_ledger', '2027-01-01') = 'ok · 0', 'revertida: la 480 a cero, como su ficha';
  c := erp.year_closing_preview(e, 2027);
  assert not (c->'checks' @> '[{"code":"accruals_unreversed"}]'), 'revertida, ya no avisa';
  raise notice 'OK  · periodificación de 2026 sin revertir en 2027: comprobación y aviso del cierre; revertida, en verde';

  -- ---------- 5. Deterioro de una factura ya cobrada ----------
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', 'collection', 'partner_id', cli,
    'payment_date', '2027-02-10', 'cash_account_no', '57200001', 'applications', jsonb_build_array(jsonb_build_object('invoice_id', f, 'amount', 1210))));
  assert public.chk(e, 'impairments_collected', '2027-02-09') = 'ok · 0', 'antes del cobro, no';
  select * into r from erp.run_audit_checks(e, 2027, '2027-02-10') x where x.code = 'impairments_collected';
  assert r.status = 'warning' and r.items = 1 and r.details->0->>'code' = 'DET-0001' and (r.details->0->>'amount')::numeric = 1210,
         'cobrada con deterioro vivo: ' || r.details::text;
  perform erp.reverse_impairment(d, '2027-02-10');
  assert public.chk(e, 'impairments_collected', '2027-02-10') = 'ok · 0' and public.chk(e, 'adjustments_ledger', '2027-02-10') = 'ok · 0';
  raise notice 'OK  · factura cobrada con su deterioro vivo: aviso; revertido (794), en verde';
end $$;

\echo '✔ FASE 39 OK · ajustes de cierre integrados'
