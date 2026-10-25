-- =====================================================================
-- PRUEBAS FASE 42 · Regularización de existencias y asistente de cierre (migración 0047)
-- ---------------------------------------------------------------------
-- SUPUESTO DE REFERENCIA (calculado a mano desde la norma: PGC 2007, NRV 10.ª; cuentas 300, 310, 390, 610, 611, 693 y 793):
--  Distribuciones Orotava SL (Canarias), 2026 y 2027. Inventario por recuento al cierre (método administrativo).
--   2026: compra mercaderías por 50.000 (600) y materias primas por 10.000 (601). Al 31/12 el recuento da:
--         mercaderías 8.000 (a coste), con un valor neto realizable de 7.500 → deterioro 500; materias primas 2.000.
--         30000001 D 8.000 / 61000001 H 8.000 · 69310001 D 500 / 39000001 H 500 · 31000001 D 2.000 / 61100001 H 2.000
--         Consumo de mercaderías 2026 = 50.000 − 8.000 = 42.000 (600 + 610).
--   2027: compra mercaderías por 40.000. Al 31/12: mercaderías 6.000 (sin deterioro) y materias primas 0.
--         Se da de baja la existencia inicial, de alta la final y se revierte el deterioro del año anterior:
--         61000001 D 8.000 / 30000001 H 8.000 · 30000001 D 6.000 / 61000001 H 6.000 · 39000001 D 500 / 79310001 H 500
--         · 61100001 D 2.000 / 31000001 H 2.000
--         Consumo de mercaderías 2027 = 8.000 + 40.000 − 6.000 = 42.000 (600 40.000 + 610 2.000).
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
create or replace function public.factura(e uuid, tercero uuid, fecha date, lineas jsonb) returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'document_kind', 'invoice',
    'partner_id', tercero, 'external_document_no', 'P-' || substr(md5(random()::text), 1, 8),
    'invoice_date', fecha, 'description', 'Supuesto', 'lines', lineas));
$$;
create or replace function public.mov(e uuid, y int, prefijo text) returns numeric language sql as $$
  select coalesce(sum(l.debit - l.credit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  join erp.fiscal_years fy on fy.id = j.fiscal_year_id and fy.year = y join erp.gl_accounts g on g.id = l.gl_account_id
  where j.company_id = e and j.status = 'posted' and j.entry_type = 'normal' and g.account_no like prefijo || '%';
$$;
create or replace function public.saldo(e uuid, y int, prefijo text) returns numeric language sql as $$
  select coalesce(sum(debit_balance - credit_balance), 0) from erp.trial_balance(e, y) where account_no like prefijo || '%';
$$;
create or replace function public.asiento(e uuid, y int, n int) returns text language sql as $$
  select string_agg(g.account_no || ' ' || case when l.debit > 0 then 'D ' || l.debit else 'H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_entries j join erp.fiscal_years fy on fy.id = j.fiscal_year_id and fy.year = y
  join erp.journal_lines l on l.entry_id = j.id join erp.gl_accounts g on g.id = l.gl_account_id
  where j.company_id = e and j.entry_no = n;
$$;
create or replace function public.paso(e uuid, y int, c text) returns text language sql as $$
  select status from erp.closing_checklist(e, y) where code = c;
$$;
create or replace function public.comprueba() returns void language plpgsql as $$
begin execute 'set constraints all immediate'; execute 'set constraints all deferred'; end $$;
grant execute on function public.falla(text, text), public.factura(uuid, uuid, date, jsonb), public.mov(uuid, int, text),
  public.saldo(uuid, int, text), public.asiento(uuid, int, int), public.paso(uuid, int, text), public.comprueba() to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; prov uuid; r record; c uuid; w uuid; q int; s text;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Distribuciones Orotava SL', 'retail', 'canary_islands', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  perform erp.set_control_mode(e, 'strict');
  perform erp.create_posting_account(e, x.no, x.name) from (values
    ('60000001', 'Compras de mercaderías'), ('60100001', 'Compras de materias primas'),
    ('30000001', 'Mercaderías'), ('31000001', 'Materias primas')) as x(no, name);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Mayorista Canario SL', 'B12345674');

  -- ---------- 1. El asistente de cierre, al empezar ----------
  perform public.factura(e, prov, '2026-03-10', '[{"account_no":"60000001","amount":50000,"tax_code":"IGIC7"}]');
  perform public.factura(e, prov, '2026-05-20', '[{"account_no":"60100001","amount":10000,"tax_code":"IGIC7"}]');
  select string_agg(step || ':' || code || '=' || status, ' ' order by step) into s from erp.closing_checklist(e, 2026);
  assert s = '1:settlements=pending 2:accruals_reversed=done 3:depreciation=na 4:asset_impairment=na 5:accruals=review '
             '6:bad_debts=done 7:provisions=review 8:inventory=pending 9:financing=na 10:grants=na 11:audit_checks=done 12:corporate_tax=pending 13:close=pending', s;
  raise notice 'OK  · asistente de 2026: faltan las liquidaciones, el inventario y el cierre; el resto, revisar o hecho';

  -- ---------- 2. Inventario del 31/12/2026 ----------
  select string_agg(account_no || ':' || initial_value || '>' || variation_account_no, ' ' order by account_no) into s
  from erp.inventory_preview(e, '2026-12-31');
  assert s = '30000001:0>610 31000001:0>611', 'vista previa: ' || s;
  select * into r from erp.post_inventory(jsonb_build_object('company_id', e, 'count_date', '2026-12-31', 'lines', jsonb_build_array(
    jsonb_build_object('account_no', '30000001', 'final_value', 8000, 'impairment', 500),
    jsonb_build_object('account_no', '31000001', 'final_value', 2000))));
  c := r.count_id;
  assert r.variation = 10000, 'variación +10.000';
  assert public.asiento(e, 2026, r.entry_no)
       = '30000001 D 8000.00 | 61000001 H 8000.00 | 69310001 D 500.00 | 39000001 H 500.00 | 31000001 D 2000.00 | 61100001 H 2000.00',
         public.asiento(e, 2026, r.entry_no);
  assert public.mov(e, 2026, '600') + public.mov(e, 2026, '610') = 42000, 'consumo de mercaderías 2026 = 42.000';
  assert public.falla(format('select * from erp.post_inventory(%L)', jsonb_build_object('company_id', e, 'count_date', '2026-12-31',
           'lines', '[{"account_no":"30000001","final_value":1}]'::jsonb)), 'already posted'), 'un inventario por ejercicio';
  raise notice 'OK  · inventario 2026: 300 8.000 / 610 · deterioro 693 500 / 390 · 310 2.000 / 611; consumo de mercaderías 42.000';

  -- …se deshace y se rehace; no se anula desde el diario; la 300 no se toca a mano
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', (select entry_id from erp.inventory_counts where id = c), '2026-12-31', 'x'),
           'inventory count'), 'no desde el diario';
  perform erp.cancel_inventory(c);
  assert public.saldo(e, 2026, '300') = 0, 'deshecho';
  perform erp.post_inventory(jsonb_build_object('company_id', e, 'count_date', '2026-12-31', 'lines', jsonb_build_array(
    jsonb_build_object('account_no', '30000001', 'final_value', 8000, 'impairment', 500),
    jsonb_build_object('account_no', '31000001', 'final_value', 2000))));
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-12-31', 'A mano') returning id into w;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (w, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '30000001'), 10, 0),
    (w, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '61000001'), 0, 10);
  assert public.falla(format('select erp.post_entry(%L); select public.comprueba()', w), 'controlled by inventory'), 'estricto: 300 a mano no';
  delete from erp.journal_lines where entry_id = w; delete from erp.journal_entries where id = w;
  raise notice 'OK  · el inventario se deshace desde el módulo; la 300 no admite asientos manuales (modo estricto)';

  -- ---------- 3. Liquidaciones y cierre: el asistente lo ve ----------
  for q in 1..4 loop perform erp.post_tax_settlement(e, 'IGIC', 2026, q); end loop;
  assert public.paso(e, 2026, 'settlements') = 'done' and public.paso(e, 2026, 'inventory') = 'done';
  perform erp.set_control_mode(e, 'guided');   -- v0.41.0: en estricto no se cierra sin el Impuesto sobre Sociedades (aquí no se calcula)
  perform erp.close_fiscal_year(e, 2026, true);
  perform erp.set_control_mode(e, 'strict');
  assert public.paso(e, 2026, 'close') = 'done';
  assert public.saldo(e, 2027, '300') = 8000 and public.saldo(e, 2027, '390') = -500 and public.saldo(e, 2027, '310') = 2000, 'apertura de 2027';
  raise notice 'OK  · asistente: liquidaciones, inventario y cierre hechos; la apertura de 2027 trae 300 8.000, 390 −500 y 310 2.000';

  -- ---------- 4. Inventario del 31/12/2027 ----------
  perform public.factura(e, prov, '2027-04-15', '[{"account_no":"60000001","amount":40000,"tax_code":"IGIC7"}]');
  assert public.falla(format('select * from erp.post_inventory(%L)', jsonb_build_object('company_id', e, 'count_date', '2027-12-31',
           'lines', '[{"account_no":"30000001","final_value":6000}]'::jsonb)), 'Include every stock account with a balance in the count: 31000001'),
         'hay que contar también las materias primas (aunque sean 0)';
  select string_agg(account_no || ':' || initial_value || ':' || prev_impairment, ' ' order by account_no) into s from erp.inventory_preview(e, '2027-12-31');
  assert s = '30000001:8000.00:500.00 31000001:2000.00:0', 'vista previa 2027: ' || s;
  select * into r from erp.post_inventory(jsonb_build_object('company_id', e, 'count_date', '2027-12-31', 'lines', jsonb_build_array(
    jsonb_build_object('account_no', '30000001', 'final_value', 6000),
    jsonb_build_object('account_no', '31000001', 'final_value', 0))));
  assert public.asiento(e, 2027, r.entry_no)
       = '61000001 D 8000.00 | 30000001 H 8000.00 | 30000001 D 6000.00 | 61000001 H 6000.00 | 39000001 D 500.00 | 79310001 H 500.00 | 61100001 D 2000.00 | 31000001 H 2000.00',
         public.asiento(e, 2027, r.entry_no);
  assert public.mov(e, 2027, '600') + public.mov(e, 2027, '610') = 42000, 'consumo de mercaderías 2027 = 8.000 + 40.000 − 6.000';
  assert public.saldo(e, 2027, '300') = 6000 and public.saldo(e, 2027, '390') = 0 and public.saldo(e, 2027, '310') = 0;
  assert public.mov(e, 2027, '793') = -500, 'reversión del deterioro anterior (793)';
  raise notice 'OK  · inventario 2027: baja de los 8.000 iniciales, alta de los 6.000 finales, 793 500; consumo 42.000';

  -- ---------- 5. Invariantes ----------
  perform public.comprueba();
  assert not exists (select 1 from erp.integrity_checks(e, 2026) where status = 'fail');
  assert not exists (select 1 from erp.integrity_checks(e, 2027) where status = 'fail'),
         (select string_agg(code, ', ') from erp.integrity_checks(e, 2027) where status = 'fail');
  assert (select items from erp.run_audit_checks(e, 2027) where code = 'controlled') = 0, 'el inventario no es un asiento manual';
  assert (select count(distinct entry_no) from erp.v_general_journal where company_id = e and fiscal_year = 2027 and source = 'inventory') = 1;
  raise notice 'OK  · invariantes en verde; el diario marca el inventario';
end $$;

\echo '✔ FASE 42 OK · existencias y asistente de cierre'
