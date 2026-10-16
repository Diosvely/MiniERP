-- =====================================================================
-- PRUEBAS FASE 36 · Inmovilizado (migración 0041) · con su SUPUESTO DE REFERENCIA
-- ---------------------------------------------------------------------
-- Supuesto (calculado a mano desde la norma: PGC NRV 2.ª y 3.ª; tabla del art. 12.1.a de la Ley 27/2014 del IS):
--  Talleres Norte SL (Península), 2026-2027.
--  A) Ordenador: compra el 01/07/2026 por 1.200 + IVA 21 % (252). Vida útil 4 años (48 meses), sin valor residual.
--     Cuota mensual 1.200 / 48 = 25 · 2026: 6 meses = 150 · 2027-2029: 300 al año · 2030: 150 · total 1.200
--     Coeficiente 100 / 4 = 25 % = máximo fiscal de «Equipos para procesos de información» (25 %): sin ajuste.
--  B) Furgoneta: compra el 15/03/2026 por 18.000 + IVA. Vida útil 8 años (96 meses), valor residual 2.000.
--     Base amortizable 18.000 − 2.000 = 16.000 · cuota mensual 16.000 / 96 = 166,666…
--     2026 (del 15/03 al 31/12): 9 meses completos (1.500) + 17 días de 31 del primer mes incompleto (91,40) = 1.591,40
--     Coeficiente 12,5 % ≤ 16 % (transporte externo): sin ajuste.
--     Venta el 30/06/2027 por 14.000 + IVA 21 % (2.940):
--       amortización acumulada al 30/06/2027: 15 meses (2.500) + 16/30 de mes (88,89) = 2.588,89
--       → amortización de 2027 hasta la venta: 2.588,89 − 1.591,40 = 997,49
--       valor neto contable 18.000 − 2.588,89 = 15.411,11 · precio 14.000 → PÉRDIDA 1.411,11 (671)
--       Factura de venta: 430 D 16.940 / 218 H 14.000 · 477 H 2.940
--       Baja: 681 D 997,49 / 281 H 997,49 · 281 D 2.588,89 · 218 H 4.000 · 671 D 1.411,11
--       Tras la baja: 218 y 2818 de la furgoneta a cero.
--  C) Un ordenador amortizado en 2 años (50 % > 25 %): el ERP avisa del ajuste fiscal (diferencia temporaria en el IS).
--  D) Un terreno no se amortiza (NRV 2.ª).
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local');
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
create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb) returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', tipo, 'document_kind', 'invoice',
    'partner_id', tercero, 'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Supuesto', 'lines', lineas));
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
create or replace function public.comprueba() returns void language plpgsql as $$
begin execute 'set constraints all immediate'; execute 'set constraints all deferred'; end $$;
grant execute on function public.falla(text, text), public.factura(uuid, text, uuid, date, jsonb), public.saldo(uuid, int, text),
  public.asiento(uuid, int, int), public.comprueba() to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; prov uuid; cli uuid; fpc uuid; fvan uuid; fventa uuid; pc uuid; van uuid; r record; s text; n int;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Talleres Norte SL', 'services', 'mainland', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  perform erp.create_fiscal_year(e, 2026);
  perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  perform erp.set_control_mode(e, 'strict');      -- el módulo funciona en modo estricto
  perform erp.create_posting_account(e, x.no, x.name) from (values
    ('21700001', 'Ordenadores'), ('21800001', 'Furgoneta'), ('21000001', 'Solar'), ('57200001', 'Banco')) as x(no, name);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Suministros Técnicos SL', 'B12345674');
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');

  -- ---------- 1. Tabla fiscal ----------
  assert (select max_pct || '/' || max_years from erp.depreciation_classes where code = 'INFORMATICA') = '25.00/8', 'equipos informáticos 25 % / 8 años';
  assert (select max_pct || '/' || max_years from erp.depreciation_classes where code = 'TRANSPORTE') = '16.00/14', 'transporte externo 16 % / 14 años';
  raise notice 'OK  · tabla de coeficientes del art. 12.1.a LIS';

  -- ---------- 2. Alta desde la factura recibida ----------
  fpc := public.factura(e, 'purchase', prov, '2026-07-01', '[{"account_no":"21700001","amount":1200,"tax_code":"VAT21"}]');
  select * into r from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Ordenador del taller',
    'asset_account_no', '21700001', 'cost', 1200, 'start_date', '2026-07-01', 'useful_life_months', 48,
    'class_code', 'INFORMATICA', 'invoice_id', fpc));
  pc := r.asset_id;
  assert r.code = 'INM-0001' and r.warnings = '[]', 'alta sin avisos: ' || row_to_json(r)::text;
  assert (select depreciation_account_no || ' / ' || expense_account_no || ' / ' || annual_pct from erp.v_fixed_assets where id = pc)
         = '28170001 / 68100001 / 25.00', 'crea la 2817 y la 681';
  fvan := public.factura(e, 'purchase', prov, '2026-03-15', '[{"account_no":"21800001","amount":18000,"tax_code":"VAT21"}]');
  select asset_id into van from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Furgoneta de reparto',
    'asset_account_no', '21800001', 'cost', 18000, 'residual_value', 2000, 'start_date', '2026-03-15',
    'useful_life_months', 96, 'class_code', 'TRANSPORTE', 'invoice_id', fvan));
  raise notice 'OK  · alta desde la factura: 2817 y 2818 de amortización acumulada y 681 de gasto';

  -- ---------- 3. Cuadro de amortización ----------
  select string_agg(year || ':' || amount, ' ' order by year) into s from erp.depreciation_schedule(pc);
  assert s = '2026:150.00 2027:300.00 2028:300.00 2029:300.00 2030:150.00', 'cuadro del ordenador: ' || s;
  assert (select sum(amount) from erp.depreciation_schedule(pc)) = 1200, 'suma el coste';
  assert (select amount from erp.depreciation_schedule(van) where year = 2026) = 1591.40, 'furgoneta 2026: 1.591,40';
  assert (select sum(amount) from erp.depreciation_schedule(van)) = 16000, 'la furgoneta amortiza 16.000 (sin el residual)';
  assert (select net_book_value from erp.depreciation_schedule(van) order by year desc limit 1) = 2000, 'queda el residual';
  raise notice 'OK  · cuadro: ordenador 150 / 300 / 300 / 300 / 150; furgoneta 1.591,40 en 2026 y queda el residual 2.000';

  -- ---------- 4. Amortización del año (o de cada mes) ----------
  select * into r from erp.post_depreciation(e, '2026-06-30');
  assert r.assets = 1 and r.amount = round(16000 * (3 + 16.0/30) / 96, 2), 'a junio solo la furgoneta: ' || r.amount;
  select * into r from erp.post_depreciation(e, '2026-12-31');
  assert r.assets = 2, 'a diciembre los dos';
  assert public.saldo(e, 2026, '681') = 150 + 1591.40, 'gasto de 2026 = 150 + 1.591,40: ' || public.saldo(e, 2026, '681');
  assert public.saldo(e, 2026, '2817') = -150 and public.saldo(e, 2026, '2818') = -1591.40, 'amortización acumulada';
  assert public.falla(format('select * from erp.post_depreciation(%L, %L)', e, '2026-12-31'), 'Nothing to depreciate'), 'no se repite';
  raise notice 'OK  · amortización 2026: 681 = 1.741,40 (150 + 1.591,40), en dos asientos (junio y diciembre) que suman lo mismo';

  -- …no se anula desde el diario; sí desde el módulo (la última)
  n := (select entry_no from erp.journal_entries j join erp.asset_depreciations d on d.entry_id = j.id
        where d.asset_id = pc limit 1);
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', (select entry_id from erp.asset_depreciations where asset_id = pc),
           '2026-12-31', 'x'), 'fixed assets module'), 'no se anula suelta';
  assert public.falla(format('select erp.cancel_depreciation(%L)',
           (select entry_id from erp.asset_depreciations where asset_id = van and period_end = '2026-06-30')), 'Only the last'), 'solo la última';
  perform erp.cancel_depreciation((select entry_id from erp.asset_depreciations where asset_id = pc));
  assert public.saldo(e, 2026, '2817') = 0, 'anulada';
  perform erp.post_depreciation(e, '2026-12-31');
  assert public.saldo(e, 2026, '681') = 1741.40, 'y se vuelve a contabilizar igual';
  raise notice 'OK  · la amortización no se anula desde el diario; la última, sí desde el módulo';

  -- ---------- 5. Modo estricto: la 281 y la 21x no se tocan a mano ----------
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-12-31', 'A mano') returning id into fpc;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (fpc, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '68100001'), 10, 0),
    (fpc, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '28170001'), 0, 10);
  assert public.falla(format('select erp.post_entry(%L); select public.comprueba()', fpc), 'controlled by assets'), 'estricto: no';
  delete from erp.journal_lines where entry_id = fpc; delete from erp.journal_entries where id = fpc;
  raise notice 'OK  · modo estricto: una amortización manual (681 a 281) no se contabiliza';

  -- ---------- 6. Venta de la furgoneta con factura emitida ----------
  fventa := public.factura(e, 'sale', cli, '2027-06-30', '[{"account_no":"21800001","amount":14000,"tax_code":"VAT21"}]');
  select * into r from erp.dispose_asset(jsonb_build_object('asset_id', van, 'disposal_date', '2027-06-30', 'invoice_id', fventa));
  assert r.net_book_value = 15411.11 and r.result = -1411.11, 'VNC 15.411,11 y pérdida 1.411,11: ' || row_to_json(r)::text;
  assert public.asiento(e, 2027, r.entry_no)
       = '68100001 D 997.49 | 28180001 H 997.49 | 28180001 D 2588.89 | 21800001 H 4000.00 | 67100001 D 1411.11', public.asiento(e, 2027, r.entry_no);
  assert public.saldo(e, 2027, '218') + (select coalesce(sum(debit - credit), 0) from erp.journal_lines l
          join erp.journal_entries j on j.id = l.entry_id join erp.fiscal_years fy on fy.id = j.fiscal_year_id and fy.year = 2026
          join erp.gl_accounts g on g.id = l.gl_account_id where j.company_id = e and g.account_no like '218%') = 0,
         'la 218 queda a cero (18.000 en 2026 − 14.000 − 4.000 en 2027)';
  assert (select coalesce(sum(l.debit - l.credit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
          join erp.gl_accounts g on g.id = l.gl_account_id where j.company_id = e and g.account_no like '2818%') = 0, 'y la 2818 también';
  assert (select tax_amount from erp.v_invoice_register where invoice_id = fventa) = 2940, 'el IVA de la venta, en el libro registro';
  assert (select status from erp.v_fixed_assets where id = van) = 'disposed';
  raise notice 'OK  · venta: 681 997,49 / 281 · 281 2.588,89 · 218 4.000 · 671 1.411,11; 218 y 2818 a cero; IVA 2.940 en el libro';

  -- …una amortización posterior ya no la incluye, y la baja se puede deshacer
  select * into r from erp.post_depreciation(e, '2027-06-30');
  assert r.assets = 1, 'solo el ordenador';
  raise notice 'OK  · tras la venta, la furgoneta ya no se amortiza';

  -- ---------- 7. Avisos fiscales y errores ----------
  select * into r from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Portátil', 'asset_account_no', '21700001',
    'cost', 800, 'start_date', '2027-01-01', 'useful_life_months', 24, 'class_code', 'INFORMATICA'));
  assert r.warnings->0->>'code' = 'above_tax_max' and (r.warnings->0->>'rate')::numeric = 50, 'aviso: 50 % > 25 %: ' || r.warnings::text;
  assert public.falla(format('select * from erp.create_fixed_asset(%L)', jsonb_build_object('company_id', e, 'name', 'Solar',
           'asset_account_no', '21000001', 'cost', 50000, 'start_date', '2027-01-01', 'useful_life_months', 600)), 'Land is not depreciated'), 'terreno';
  assert public.falla(format('select * from erp.create_fixed_asset(%L)', jsonb_build_object('company_id', e, 'name', 'X',
           'asset_account_no', '57200001', 'cost', 10, 'start_date', '2027-01-01', 'useful_life_months', 12)), 'asset account'), 'cuenta 2x';
  assert public.falla(format('select * from erp.create_fixed_asset(%L)', jsonb_build_object('company_id', e, 'name', 'X',
           'asset_account_no', '21700001', 'cost', 100, 'residual_value', 100, 'start_date', '2027-01-01', 'useful_life_months', 12)), 'residual'), 'residual < coste';
  assert public.falla(format('select * from erp.dispose_asset(%L)', jsonb_build_object('asset_id', van, 'disposal_date', '2027-07-01')), 'already disposed');
  raise notice 'OK  · aviso fiscal (50 %% > 25 %%: ajuste en el IS); terrenos, cuentas y residual, rechazados';

  -- ---------- 8. Retiro sin venta (siniestro): todo el valor neto a pérdidas ----------
  select * into r from erp.dispose_asset(jsonb_build_object('asset_id', (select id from erp.fixed_assets where company_id = e and name = 'Portátil'),
    'disposal_date', '2027-03-31'));
  assert r.net_book_value = 800 - 100 and r.result = -700, 'tres meses de 800/24 = 100; pérdida 700: ' || row_to_json(r)::text;
  raise notice 'OK  · retiro por siniestro: amortiza hasta la fecha (100) y lleva el valor neto (700) a la 671';

  -- …y se deshace
  perform erp.cancel_disposal((select id from erp.fixed_assets where company_id = e and name = 'Portátil'), '2027-03-31');
  assert (select status from erp.v_fixed_assets where name = 'Portátil') = 'active' and (select accumulated from erp.v_fixed_assets where name = 'Portátil') = 0;
  raise notice 'OK  · deshacer la baja: el activo vuelve a estar en uso';

  -- ---------- 9. Invariantes y comprobaciones ----------
  assert not exists (select 1 from erp.integrity_checks(e, 2026) where status = 'fail'), '2026 en verde';
  assert not exists (select 1 from erp.integrity_checks(e, 2027) where status = 'fail'),
         '2027 en verde: ' || (select string_agg(code || '=' || coalesce(detail::text, actual::text), ', ') from erp.integrity_checks(e, 2027) where status = 'fail');
  assert (select items from erp.run_audit_checks(e, 2027) where code = 'controlled') = 0, 'los asientos del módulo no son manuales';
  assert (select count(*) from erp.v_general_journal where company_id = e and source = 'asset') > 0, 'el diario los marca';
  raise notice 'OK  · invariantes en verde; los asientos del módulo no salen como manuales y el diario los marca';
end $$;

-- ---------- 10. Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa');
begin
  assert (select count(*) from erp.v_fixed_assets where company_id = e) = 3, 'el lector ve las fichas';
  assert public.falla(format('select * from erp.post_depreciation(%L, %L)', e, '2027-12-31'), 'No permission'), 'pero no amortiza';
  begin
    insert into erp.fixed_assets (company_id, code, name, asset_account_id, depreciation_account_id, expense_account_id,
      acquisition_date, start_date, cost, useful_life_months)
    select e, 'X', 'X', id, id, id, current_date, current_date, 1, 1 from erp.gl_accounts where company_id = e limit 1;
    raise exception 'no debería poder insertar';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK  · el lector ve, no amortiza ni escribe en las tablas';
end $$;

-- ---------- 11. Borrar la empresa con inmovilizado ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa'); n int;
begin
  loop n := erp.delete_company_step(e, 5); exit when n = 0; end loop;
  perform public.comprueba();
  assert not exists (select 1 from erp.companies where id = e);
  raise notice 'OK  · una empresa con inmovilizado se borra entera';
end $$;

\echo '✔ FASE 36 OK · inmovilizado'
