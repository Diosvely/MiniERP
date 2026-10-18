-- =====================================================================
-- PRUEBAS FASE 41 · Deterioro del inmovilizado y rectificativas de compra de activos (migración 0046)
-- ---------------------------------------------------------------------
-- SUPUESTO DE REFERENCIA (calculado a mano desde la norma: PGC 2007, NRV 2.ª 2.2; cuentas 291, 691 y 791):
--  Industrias Anaga SL (Península), 2026-2030.
--   A) Máquina comprada el 01/01/2026 por 60.000 + IVA, vida útil 10 años, sin valor residual: 6.000 al año.
--      31/12/2027  amortizado 12.000 → valor neto 48.000. El valor recuperable baja a 40.000 → DETERIORO 8.000:
--                  691 D 8.000 / 2913 H 8.000
--      2028 y 2029 la amortización se recalcula sobre el nuevo valor: 40.000 / 96 meses × 12 = 5.000 al año
--      31/12/2029  amortizado 22.000, deterioro 8.000 → valor neto 30.000. Sin el deterioro valdría 60.000 − 24.000 =
--                  36.000. El valor recuperable sube a 38.000, pero la REVERSIÓN tiene como límite 36.000:
--                  2913 D 6.000 / 791 H 6.000 (no 8.000)
--      2030        lo que queda (60.000 − 22.000 − 2.000 = 36.000) en 72 meses: 6.000 al año, como el plan original
--      31/12/2030  venta por 25.000: amortizado 28.000, deterioro 2.000 → valor neto 30.000 → pérdida 5.000:
--                  2813 D 28.000 · 2913 D 2.000 / 213 H 35.000 (el resto lo abona la factura) · 671 D 5.000
--   B) Ordenador comprado el 01/07/2026 por 1.200, 4 años. 2026: 150. El proveedor hace un descuento de 240 en una
--      rectificativa del 31/01/2027 → coste 960 (NRV 2.ª 1.1). Al 31/01/2027 van 7 meses (175); quedan 785 en 41 meses:
--      2027 = 175 − 150 + 785 × 11 / 41 = 25 + 210,61 = 235,61.
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
create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb, kind text default 'invoice', corr uuid default null) returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', tipo, 'document_kind', kind,
    'partner_id', tercero, 'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'corrected_invoice_id', corr, 'invoice_date', fecha, 'description', 'Supuesto', 'lines', lineas));
$$;
create or replace function public.asiento(e uuid, y int, n int) returns text language sql as $$
  select string_agg(g.account_no || ' ' || case when l.debit > 0 then 'D ' || l.debit else 'H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_entries j join erp.fiscal_years fy on fy.id = j.fiscal_year_id and fy.year = y
  join erp.journal_lines l on l.entry_id = j.id join erp.gl_accounts g on g.id = l.gl_account_id
  where j.company_id = e and j.entry_no = n;
$$;
create or replace function public.comprueba() returns void language plpgsql as $$
begin execute 'set constraints all immediate'; execute 'set constraints all deferred'; end $$;
grant execute on function public.falla(text, text), public.factura(uuid, text, uuid, date, jsonb, text, uuid),
  public.asiento(uuid, int, int), public.comprueba() to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; prov uuid; cli uuid; f uuid; fpc uuid; maq uuid; pc uuid; r record; s text; y int;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Industrias Anaga SL', 'manufacturing', 'mainland', auth.uid()) returning id into e;
  for y in 2026..2030 loop perform erp.create_fiscal_year(e, y); end loop;
  perform erp.setup_taxes(e);
  perform erp.set_control_mode(e, 'strict');
  perform erp.create_posting_account(e, x.no, x.name) from (values ('21300001', 'Maquinaria'), ('21700001', 'Ordenadores')) as x(no, name);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Maquinaria Canaria SL', 'B12345674');
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');

  -- ---------- A) Máquina: amortización, deterioro y reversión ----------
  f := public.factura(e, 'purchase', prov, '2026-01-01', '[{"account_no":"21300001","amount":60000,"tax_code":"VAT21"}]');
  select asset_id into maq from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Máquina de corte', 'asset_account_no', '21300001',
    'cost', 60000, 'start_date', '2026-01-01', 'useful_life_months', 120, 'class_code', 'MAQUINARIA', 'invoice_id', f));
  perform erp.post_depreciation(e, '2026-12-31');
  assert public.falla(format('select * from erp.impair_asset(%L)', jsonb_build_object('asset_id', maq, 'impairment_date', '2027-12-31',
           'recoverable_value', 40000)), 'Post the depreciation'), 'primero se amortiza hasta la fecha';
  perform erp.post_depreciation(e, '2027-12-31');
  assert public.falla(format('select * from erp.reverse_asset_impairment(%L)', jsonb_build_object('asset_id', maq, 'reversal_date', '2027-12-31',
           'recoverable_value', 50000)), 'no impairment to reverse');
  assert public.falla(format('select * from erp.impair_asset(%L)', jsonb_build_object('asset_id', maq, 'impairment_date', '2027-12-31',
           'recoverable_value', 50000)), 'not below the net book value'), 'si vale más, no hay deterioro';
  select * into r from erp.impair_asset(jsonb_build_object('asset_id', maq, 'impairment_date', '2027-12-31', 'recoverable_value', 40000));
  assert r.amount = 8000 and r.net_book_value = 40000, row_to_json(r)::text;
  assert public.asiento(e, 2027, r.entry_no) = '69100001 D 8000.00 | 29130001 H 8000.00', public.asiento(e, 2027, r.entry_no);
  raise notice 'OK  · deterioro al 31/12/2027: valor neto 48.000, recuperable 40.000 → 691 D 8.000 / 2913 H 8.000';

  select string_agg(year || ':' || amount, ' ' order by year) into s from erp.depreciation_schedule(maq) where year <= 2030;
  assert s = '2026:6000.00 2027:6000.00 2028:5000.00 2029:5000.00 2030:5000.00', 'cuadro recalculado: ' || s;
  perform erp.post_depreciation(e, '2028-12-31');
  perform erp.post_depreciation(e, '2029-12-31');
  assert (select sum(amount) from erp.asset_depreciations where asset_id = maq) = 22000, 'amortizado 22.000';
  raise notice 'OK  · tras el deterioro, 40.000 / 96 meses: 5.000 al año en 2028 y 2029';

  select * into r from erp.reverse_asset_impairment(jsonb_build_object('asset_id', maq, 'reversal_date', '2029-12-31', 'recoverable_value', 38000));
  assert r.amount = 6000 and r.capped and r.net_book_value = 36000, 'reversión limitada a 6.000: ' || row_to_json(r)::text;
  assert public.asiento(e, 2029, r.entry_no) = '29130001 D 6000.00 | 79100001 H 6000.00', public.asiento(e, 2029, r.entry_no);
  assert (select amount from erp.depreciation_schedule(maq) where year = 2030) = 6000, 'vuelve al plan original: 6.000';
  assert (select net_book_value || ' ' || impairment from erp.v_fixed_assets where id = maq) = '36000.00 2000.00', 'ficha: neto 36.000, deterioro 2.000';
  raise notice 'OK  · reversión al 31/12/2029: recuperable 38.000 pero el límite es 36.000 (sin deterioro) → 2913 D 6.000 / 791 H 6.000';

  -- …deshacer la reversión y rehacerla; el diario no la anula suelta
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', (select entry_id from erp.asset_events where asset_id = maq and kind = 'reversal'),
           '2029-12-31', 'x'), 'fixed assets module'), 'no se anula desde el diario';
  perform erp.cancel_asset_impairment(maq);
  assert (select impairment from erp.v_fixed_assets where id = maq) = 8000, 'reversión deshecha';
  perform erp.reverse_asset_impairment(jsonb_build_object('asset_id', maq, 'reversal_date', '2029-12-31', 'recoverable_value', 38000));
  perform erp.post_depreciation(e, '2030-12-31');
  assert (select amount from erp.asset_depreciations where asset_id = maq and period_end = '2030-12-31') = 6000, '2030: 6.000';
  assert (select status from erp.run_audit_checks(e, 2030) where code = 'assets_ledger') = 'ok', 'la 2913 cuadra con la ficha';

  -- …venta
  f := public.factura(e, 'sale', cli, '2030-12-31', '[{"account_no":"21300001","amount":25000,"tax_code":"VAT21"}]');
  select * into r from erp.dispose_asset(jsonb_build_object('asset_id', maq, 'disposal_date', '2030-12-31', 'invoice_id', f));
  assert r.net_book_value = 30000 and r.result = -5000, row_to_json(r)::text;
  assert public.asiento(e, 2030, r.entry_no) = '28130001 D 28000.00 | 29130001 D 2000.00 | 21300001 H 35000.00 | 67100001 D 5000.00',
         public.asiento(e, 2030, r.entry_no);
  assert (select coalesce(sum(l.debit - l.credit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
          join erp.gl_accounts g on g.id = l.gl_account_id where j.company_id = e and g.account_no like '2913%') = 0, 'la 2913 a cero';
  raise notice 'OK  · venta por 25.000: 2813 28.000 · 2913 2.000 / 213 35.000 · 671 5.000; la 2913 queda a cero';

  -- ---------- Invariantes ----------
  perform public.comprueba();
  for y in 2026..2030 loop
    assert not exists (select 1 from erp.integrity_checks(e, y) where status = 'fail'),
           y || ': ' || (select string_agg(code, ', ') from erp.integrity_checks(e, y) where status = 'fail');
  end loop;
  assert (select items from erp.run_audit_checks(e, 2029) where code = 'controlled') = 0, 'deterioro y reversión no son manuales';
  raise notice 'OK  · invariantes en verde de 2026 a 2030';
end $$;

-- ---------- B) Ordenador: rectificativa de la compra (NRV 2.ª 1.1) ----------
do $$
declare e uuid; prov uuid; f uuid; m uuid; pc uuid; r record;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Oficina Anaga SL', 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, '21700001', 'Ordenadores');
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Informática Canaria SL', 'B12345674');
  f := public.factura(e, 'purchase', prov, '2026-07-01', '[{"account_no":"21700001","amount":1200,"tax_code":"VAT21"}]');
  select asset_id into pc from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Ordenador', 'asset_account_no', '21700001',
    'cost', 1200, 'start_date', '2026-07-01', 'useful_life_months', 48, 'invoice_id', f));
  perform erp.post_depreciation(e, '2026-12-31');

  -- La rectificativa no puede ir antes de una amortización ya contabilizada…
  perform erp.post_depreciation(e, '2027-02-28');
  assert public.falla(format('select public.factura(%L, %L, %L, %L, %L, %L, %L)', e, 'purchase', prov, '2027-01-31',
           '[{"account_no":"21700001","amount":240,"tax_code":"VAT21"}]', 'credit_memo', f), 'already depreciated after'), 'primero se deshace';
  perform erp.cancel_depreciation((select entry_id from erp.asset_depreciations where asset_id = pc and period_end = '2027-02-28'));
  -- …y ajusta el coste de la ficha
  m := public.factura(e, 'purchase', prov, '2027-01-31', '[{"account_no":"21700001","amount":240,"tax_code":"VAT21"}]', 'credit_memo', f);
  assert (select cost from erp.v_fixed_assets where id = pc) = 960, 'coste 1.200 − 240 = 960';
  assert (select events->0->>'kind' || ' ' || (events->0->>'amount') from erp.v_fixed_assets where id = pc) = 'cost_adjustment -240.00';
  assert (select status from erp.run_audit_checks(e, 2027, '2027-01-31') where code = 'assets_ledger') = 'ok', 'la 217 (960) cuadra con la ficha';
  select * into r from erp.post_depreciation(e, '2027-12-31');
  assert r.amount = 235.61, '2027: 25 + 785 × 11 / 41 = 235,61: ' || r.amount;
  assert (select sum(amount) from erp.depreciation_schedule(pc)) = 960, 'en toda la vida se amortizan 960';
  assert (select amount from erp.depreciation_schedule(pc) order by year desc limit 1) > 0;
  raise notice 'OK  · rectificativa de 240 el 31/01/2027: coste 960; 2027 = 235,61; en total se amortizan 960';

  assert public.falla(format('select public.factura(%L, %L, %L, %L, %L, %L, %L)', e, 'purchase', prov, '2027-12-31',
           '[{"account_no":"21700001","amount":2000,"tax_code":"VAT21"}]', 'credit_memo', f), 'without depreciable cost'), 'no deja la ficha sin coste';
  perform public.comprueba();
  assert not exists (select 1 from erp.integrity_checks(e, 2027) where status = 'fail');
  raise notice 'OK  · una rectificativa mayor que el coste se rechaza (hay que dar de baja el activo)';
end $$;

\echo '✔ FASE 41 OK · deterioro del inmovilizado y rectificativas de compra'
