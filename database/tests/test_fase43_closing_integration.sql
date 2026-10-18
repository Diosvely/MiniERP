-- =====================================================================
-- PRUEBAS FASE 43 · Fin de ejercicio II integrado (migración 0048)
--   comprobaciones (provisiones y existencias frente a sus módulos, provisiones sin revisar), avisos del cierre,
--   el deterioro del inmovilizado en «inmovilizado frente a sus fichas» y conceptos del glosario
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.chk(e uuid, c text, d date) returns text language sql as $$
  select r.status || ' · ' || r.items from erp.run_audit_checks(e, extract(year from d)::int, d) r where r.code = c;
$$;
create or replace function public.manual(e uuid, d date, l jsonb) returns uuid language plpgsql as $$
declare v uuid; x jsonb; n int := 0;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, 'A mano') returning id into v;
  for x in select * from jsonb_array_elements(l) loop
    n := n + 1;
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
    values (v, e, n, (select id from erp.gl_accounts where company_id = e and account_no = x->>0), (x->>1)::numeric, (x->>2)::numeric);
  end loop;
  perform erp.post_entry(v);
  return v;
end $$;
grant execute on function public.chk(uuid, text, date), public.manual(uuid, date, jsonb) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; prov uuid; p uuid; m uuid; c jsonb; r record; f uuid; a uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Integración Cierre SL', 'retail', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, x.no, x.name) from (values
    ('67800001', 'Gastos excepcionales'), ('57200001', 'Banco'), ('10000001', 'Capital'), ('30000001', 'Mercaderías'),
    ('60000001', 'Compras'), ('21300001', 'Maquinaria')) as x(no, name);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Proveedor SL', 'B12345674');

  -- ---------- 1. Conceptos ----------
  assert (select term from erp.concepts where key = 'provision') = 'Provisión';
  assert (select string_agg(key, ',' order by key) from erp.concepts_for_account('14200001')) like '%provision%', 'la 142 → provisión';
  assert (select string_agg(key, ',' order by key) from erp.concepts_for_account('29130001')) like '%assetImpairment%', 'la 2913 → deterioro del inmovilizado';
  assert (select string_agg(key, ',' order by key) from erp.concepts_for_account('61000001')) like '%inventoryChange%', 'la 610 → variación de existencias';
  assert (select sort from erp.audit_checks where code = 'tax_territory') = 65;
  raise notice 'OK  · conceptos «Provisión», «Deterioro del inmovilizado» y «Variación de existencias»';

  -- ---------- 2. Provisiones: el módulo cuadra; un asiento manual (modo guiado), no ----------
  select provision_id into p from erp.create_provision(jsonb_build_object('company_id', e, 'kind', 'liabilities', 'description', 'Litigio',
    'amount', 5000, 'provision_date', '2026-12-31', 'expense_account_no', '67800001'));
  assert public.chk(e, 'provisions_ledger', '2026-12-31') = 'ok · 0', public.chk(e, 'provisions_ledger', '2026-12-31');
  m := public.manual(e, '2026-12-31', '[["67800001",700,0],["14200001",0,700]]');
  select * into r from erp.run_audit_checks(e, 2026, '2026-12-31') x where x.code = 'provisions_ledger';
  assert r.status = 'warning' and r.details->0->>'account_no' = '14200001' and (r.details->0->>'book')::numeric = -5000
     and (r.details->0->>'balance')::numeric = -5700, 'módulo −5.000 · cuenta −5.700: ' || r.details::text;
  perform erp.reverse_entry(m, '2026-12-31', 'Se registra en Provisiones');
  assert public.chk(e, 'provisions_ledger', '2026-12-31') = 'ok · 0', 'anulado, cuadra';
  raise notice 'OK  · provisiones: un asiento manual de 700 a la 142 descuadra (módulo 5.000, cuenta 5.700); anulado, cuadra';

  -- ---------- 3. Provisión sin revisar en el cierre siguiente ----------
  perform erp.close_fiscal_year(e, 2026, true);
  assert public.chk(e, 'provisions_review', '2027-06-30') = 'ok · 0', 'a mitad de año no se exige';
  assert public.chk(e, 'provisions_review', '2027-12-31') = 'warning · 1', 'al cierre sí';
  c := erp.year_closing_preview(e, 2027);
  assert c->'checks' @> jsonb_build_array(jsonb_build_object('code', 'provisions_not_reviewed', 'detail', 'PRV-0001')), (c->'checks')::text;
  perform erp.revise_provision(jsonb_build_object('provision_id', p, 'review_date', '2027-12-31', 'new_amount', 4000));
  assert public.chk(e, 'provisions_review', '2027-12-31') = 'ok · 0' and public.chk(e, 'provisions_ledger', '2027-12-31') = 'ok · 0';
  c := erp.year_closing_preview(e, 2027);
  assert not (c->'checks' @> '[{"code":"provisions_not_reviewed"}]');
  raise notice 'OK  · provisión de 2026 sin revisar en el cierre de 2027: comprobación y aviso; revisada, en verde';

  -- ---------- 4. Existencias: aviso del cierre, inventario y asiento manual ----------
  perform erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'document_kind', 'invoice', 'partner_id', prov,
    'external_document_no', 'M-1', 'invoice_date', '2027-03-01', 'description', 'Mercaderías',
    'lines', '[{"account_no":"60000001","amount":10000,"tax_code":"VAT21"}]'::jsonb));
  c := erp.year_closing_preview(e, 2027);
  assert c->'checks' @> '[{"code":"inventory_not_counted"}]', 'hay compras y no hay inventario: avisa';
  perform erp.post_inventory(jsonb_build_object('company_id', e, 'count_date', '2027-12-31',
    'lines', '[{"account_no":"30000001","final_value":2500}]'::jsonb));
  c := erp.year_closing_preview(e, 2027);
  assert not (c->'checks' @> '[{"code":"inventory_not_counted"}]'), 'contado, ya no avisa';
  assert public.chk(e, 'inventory_ledger', '2027-12-31') = 'ok · 0';
  m := public.manual(e, '2027-12-31', '[["30000001",300,0],["57200001",0,300]]');
  select * into r from erp.run_audit_checks(e, 2027, '2027-12-31') x where x.code = 'inventory_ledger';
  assert r.status = 'warning' and (r.details->0->>'book')::numeric = 2500 and (r.details->0->>'balance')::numeric = 2800, r.details::text;
  raise notice 'OK  · existencias: aviso del cierre sin inventario; una compra a mano a la 300 descuadra (2.500 frente a 2.800)';

  -- ---------- 5. Deterioro del inmovilizado en «inmovilizado frente a sus fichas» ----------
  f := (select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'document_kind', 'invoice',
    'partner_id', prov, 'external_document_no', 'MQ-1', 'invoice_date', '2027-01-01', 'description', 'Máquina',
    'lines', '[{"account_no":"21300001","amount":12000,"tax_code":"VAT21"}]'::jsonb)));
  select asset_id into a from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Máquina', 'asset_account_no', '21300001',
    'cost', 12000, 'start_date', '2027-01-01', 'useful_life_months', 120, 'invoice_id', f));
  perform erp.post_depreciation(e, '2027-12-31');
  perform erp.impair_asset(jsonb_build_object('asset_id', a, 'impairment_date', '2027-12-31', 'recoverable_value', 9000));
  assert public.chk(e, 'assets_ledger', '2027-12-31') = 'ok · 0', '2913 = deterioro de la ficha (1.800): ' || public.chk(e, 'assets_ledger', '2027-12-31');
  raise notice 'OK  · el deterioro (2913 1.800) cuadra con la ficha';
end $$;

\echo '✔ FASE 43 OK · fin de ejercicio II integrado'
