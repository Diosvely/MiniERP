-- =====================================================================
-- PRUEBAS FASE 38 · Fin de ejercicio I: periodificaciones y deterioro de clientes (migración 0043)
-- ---------------------------------------------------------------------
-- SUPUESTO DE REFERENCIA (calculado a mano desde la norma: PGC 2007, marco conceptual, principio de devengo;
-- NRV 9.ª 2.1.3, deterioro de créditos; Ley 27/2014 del IS, arts. 13.1 y 104):
--  Comercial Atlántico SL (Península), ejercicios 2026 y 2027.
--  PERIODIFICACIONES al 31/12/2026
--   A) Seguro anual del local pagado el 01/10/2026: 1.200 (625; exento de IVA, art. 20.Uno.16.º LIVA).
--      Cubre 12 meses; de 2026 son 3 (300). Gasto anticipado 9/12 = 900:      480 D 900  / 625 H 900
--   B) Alquiler de un local cobrado por adelantado el 01/11/2026: semestre 6.000 + IVA (752).
--      De 2026 son 2 meses (2.000). Ingreso anticipado 4/6 = 4.000:           752 D 4.000 / 485 H 4.000
--   C) Luz de diciembre, sin factura al cierre: estimación 350:               628 D 350  / 4009 H 350
--   D) Mantenimiento de nov-dic-ene que se facturará el 31/01/2027 por 900:
--      devengados 2 de 3 meses = 600:                                          4309 D 600 / 705 H 600
--   Reversión el 01/01/2027 (asientos al revés): el gasto o el ingreso anticipado pasa al año en que se devenga; en
--   los devengados (C, D), la reversión deja la 628 y la 705 en negativo, y la factura que llega en 2027 por el total
--   las compensa (en 2027 solo queda lo que es de 2027).
--   Efecto en el resultado de 2026: −300 (seguro) + 2.000 (alquiler) − 350 (luz) + 600 (mantenimiento).
--  DETERIORO DE CLIENTES al 31/12/2026
--   E) Moroso: factura del 15/03/2026 por 2.000 + IVA = 2.420, vencida el mismo día y sin cobrar. Individual al 100 %:
--      694 D 2.420 / 490 H 2.420. Han pasado más de 6 meses del vencimiento: deducible (art. 13.1.a LIS).
--   F) Dudoso: factura del 01/10/2026 por 1.000 + IVA = 1.210, cobra 410 el 15/11 → pendiente 800. Individual al 50 %:
--      694 D 400 / 490 H 400. Vencida hace menos de 6 meses: NO deducible hasta el 01/04/2027.
--   G) Global por antigüedad sobre el resto de clientes (no vencido 0 %, 1-90 días 5 %, 91-180 10 %, 181-365 25 %):
--      Cliente General, con 30 días de pago:
--        · 10/04/2026: 500 + IVA = 605, vence el 10/05 → 235 días → 25 % = 151,25
--        · 15/06/2026: 1.000 + IVA = 1.210, vence el 15/07 → 169 días → 10 % = 121,00
--        · 20/12/2026: 3.000 + IVA = 3.630, vence el 19/01/2027 → no vencida → 0
--      Deterioro global 272,25 (694 / 490). No deducible (art. 13.1 LIS); una empresa de reducida dimensión podría
--      deducir hasta el 1 % de los deudores: 1 % de 5.445 = 54,45 (art. 104 LIS).
--  2027
--   H) 15/02: Dudoso paga los 800 → se revierte su deterioro: 490 D 400 / 794 H 400
--   I) 10/03: Moroso, insolvencia firme (concurso sin bienes): 650 D 2.420 / 430 H 2.420 · 490 D 2.420 / 794 H 2.420
--      La partida abierta del Moroso queda a cero (como un cobro sin banco).
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
-- Saldo de las cuentas de un prefijo en el año, solo con los asientos normales (sin cierre ni apertura)
create or replace function public.mov(e uuid, y int, prefijo text) returns numeric language sql as $$
  select coalesce(sum(l.debit - l.credit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  join erp.fiscal_years fy on fy.id = j.fiscal_year_id and fy.year = y join erp.gl_accounts g on g.id = l.gl_account_id
  where j.company_id = e and j.status = 'posted' and j.entry_type = 'normal' and g.account_no like prefijo || '%';
$$;
create or replace function public.asiento(e uuid, y int, n int) returns text language sql as $$
  select string_agg(g.account_no || ' ' || case when l.debit > 0 then 'D ' || l.debit else 'H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_entries j join erp.fiscal_years fy on fy.id = j.fiscal_year_id and fy.year = y
  join erp.journal_lines l on l.entry_id = j.id join erp.gl_accounts g on g.id = l.gl_account_id
  where j.company_id = e and j.entry_no = n;
$$;
create or replace function public.pendiente(e uuid, f uuid, d date) returns numeric language sql as $$
  select pending from erp.open_items(e, d) where invoice_id = f;
$$;
create or replace function public.comprueba() returns void language plpgsql as $$
begin execute 'set constraints all immediate'; execute 'set constraints all deferred'; end $$;
grant execute on function public.falla(text, text), public.factura(uuid, text, uuid, date, jsonb), public.saldo(uuid, int, text),
  public.mov(uuid, int, text), public.asiento(uuid, int, int), public.pendiente(uuid, uuid, date), public.comprueba() to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare
  e uuid; aseg uuid; inq uuid; moroso uuid; dudoso uuid; general uuid;
  fseg uuid; falq uuid; fmor uuid; fdud uuid; g1 uuid; g2 uuid; g3 uuid;
  r record; s text; a_seg uuid; d_mor uuid; d_dud uuid; d_glo uuid; w uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Comercial Atlántico SL', 'retail', 'mainland', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  perform erp.create_fiscal_year(e, 2026);
  perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  perform erp.set_control_mode(e, 'strict');      -- los módulos funcionan en modo estricto
  perform erp.create_posting_account(e, x.no, x.name) from (values
    ('62500001', 'Seguro del local'), ('62800001', 'Electricidad'), ('75200001', 'Alquiler del local'),
    ('70500001', 'Mantenimiento'), ('70000001', 'Ventas'), ('57200001', 'Banco')) as x(no, name);
  select partner_id into aseg    from erp.create_partner(e, 'creditor', 'Seguros del Norte SA', 'B12345674');
  select partner_id into inq     from erp.create_partner(e, 'customer', 'Inquilino Local SL', 'A58818501');
  select partner_id into moroso  from erp.create_partner(e, 'customer', 'Moroso', '12345678Z');
  select partner_id into dudoso  from erp.create_partner(e, 'customer', 'Dudoso', '87654321X');
  select partner_id into general from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  update erp.business_partners set payment_days = 30 where id = general;

  -- ---------- 1. Periodificaciones al 31/12/2026 ----------
  fseg := public.factura(e, 'purchase', aseg, '2026-10-01', '[{"account_no":"62500001","amount":1200,"tax_code":"VAT_E20"}]');
  select * into r from erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'prepaid_expense', 'description', 'Seguro anual del local',
    'pl_account_no', '62500001', 'cutoff_date', '2026-12-31', 'total_amount', 1200, 'coverage_start', '2026-10-01',
    'coverage_months', 12, 'invoice_id', fseg));
  a_seg := r.accrual_id;
  assert r.code = 'PER-0001' and r.amount = 900, 'seguro: 9/12 de 1.200 = 900: ' || row_to_json(r)::text;
  assert public.asiento(e, 2026, r.entry_no) = '48000001 D 900.00 | 62500001 H 900.00', public.asiento(e, 2026, r.entry_no);

  falq := public.factura(e, 'sale', inq, '2026-11-01', '[{"account_no":"75200001","amount":6000,"tax_code":"VAT21"}]');
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', 'collection', 'partner_id', inq,
    'payment_date', '2026-11-01', 'cash_account_no', '57200001', 'applications', jsonb_build_array(jsonb_build_object('invoice_id', falq, 'amount', 7260))));
  select * into r from erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'deferred_income', 'description', 'Alquiler cobrado por adelantado',
    'pl_account_no', '75200001', 'cutoff_date', '2026-12-31', 'total_amount', 6000, 'coverage_start', '2026-11-01', 'coverage_months', 6));
  assert r.amount = 4000 and public.asiento(e, 2026, r.entry_no) = '75200001 D 4000.00 | 48500001 H 4000.00', 'alquiler: 4/6 de 6.000 = 4.000';

  select * into r from erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'accrued_expense', 'description', 'Luz de diciembre',
    'pl_account_no', '62800001', 'cutoff_date', '2026-12-31', 'amount', 350));
  assert public.asiento(e, 2026, r.entry_no) = '62800001 D 350.00 | 40090001 H 350.00', public.asiento(e, 2026, r.entry_no);

  select * into r from erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'accrued_income', 'description', 'Mantenimiento nov-ene',
    'pl_account_no', '70500001', 'cutoff_date', '2026-12-31', 'total_amount', 900, 'coverage_start', '2026-11-01', 'coverage_months', 3));
  assert r.amount = 600 and public.asiento(e, 2026, r.entry_no) = '43090001 D 600.00 | 70500001 H 600.00', 'mantenimiento: 2/3 de 900 = 600';

  assert public.saldo(e, 2026, '625') = 300 and public.saldo(e, 2026, '752') = -2000
     and public.saldo(e, 2026, '628') = 350 and public.saldo(e, 2026, '705') = -600, 'gastos e ingresos de 2026 por devengo';
  assert public.saldo(e, 2026, '480') = 900 and public.saldo(e, 2026, '485') = -4000
     and public.saldo(e, 2026, '4009') = -350 and public.saldo(e, 2026, '4309') = 600, 'cuentas de periodificación';
  raise notice 'OK  · periodificaciones: 480 900 · 485 4.000 · 4009 350 · 4309 600; gasto del seguro 300 e ingreso del alquiler 2.000 en 2026';

  -- …errores
  assert public.falla(format('select * from erp.create_accrual(%L)', jsonb_build_object('company_id', e, 'kind', 'prepaid_expense',
           'description', 'X', 'pl_account_no', '70500001', 'cutoff_date', '2026-12-31', 'amount', 10)), 'expense account'), 'gasto en el grupo 6';
  assert public.falla(format('select * from erp.create_accrual(%L)', jsonb_build_object('company_id', e, 'kind', 'prepaid_expense',
           'description', 'X', 'pl_account_no', '62500001', 'cutoff_date', '2026-12-31', 'total_amount', 1200,
           'coverage_start', '2026-01-01', 'coverage_months', 12)), 'Nothing to accrue'), 'un periodo que acaba en el corte no se periodifica';
  assert public.falla(format('select * from erp.create_accrual(%L)', jsonb_build_object('company_id', e, 'kind', 'otro',
           'description', 'X', 'pl_account_no', '62500001', 'cutoff_date', '2026-12-31', 'amount', 10)), 'Invalid accrual type');
  raise notice 'OK  · errores: cuenta del grupo equivocado, nada que periodificar y tipo desconocido';

  -- …modo estricto: la 480 no se toca a mano; el asiento no se anula desde el diario
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-12-31', 'A mano') returning id into w;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (w, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '48000001'), 10, 0),
    (w, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '62500001'), 0, 10);
  assert public.falla(format('select erp.post_entry(%L); select public.comprueba()', w), 'controlled by accruals'), 'estricto: 480 a mano no';
  delete from erp.journal_lines where entry_id = w; delete from erp.journal_entries where id = w;
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', (select entry_id from erp.accruals where id = a_seg), '2026-12-31', 'x'),
           'belongs to an accrual'), 'no se anula desde el diario';
  raise notice 'OK  · modo estricto: la 480 solo la mueve el módulo; su asiento no se anula desde el diario';

  -- ---------- 2. Deterioro individual ----------
  fmor := public.factura(e, 'sale', moroso, '2026-03-15', '[{"account_no":"70000001","amount":2000,"tax_code":"VAT21"}]');
  fdud := public.factura(e, 'sale', dudoso, '2026-10-01', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"}]');
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', 'collection', 'partner_id', dudoso,
    'payment_date', '2026-11-15', 'cash_account_no', '57200001', 'applications', jsonb_build_array(jsonb_build_object('invoice_id', fdud, 'amount', 410))));
  select * into r from erp.impair_receivable(jsonb_build_object('invoice_id', fmor, 'impair_date', '2026-12-31'));
  d_mor := r.impairment_id;
  assert r.code = 'DET-0001' and r.amount = 2420 and r.warnings = '[]', 'Moroso: 100 % de 2.420, deducible: ' || row_to_json(r)::text;
  assert public.asiento(e, 2026, r.entry_no) = '69400001 D 2420.00 | 49000001 H 2420.00', public.asiento(e, 2026, r.entry_no);
  select * into r from erp.impair_receivable(jsonb_build_object('invoice_id', fdud, 'impair_date', '2026-12-31', 'pct', 50));
  d_dud := r.impairment_id;
  assert r.amount = 400, 'Dudoso: 50 % de lo pendiente (800) = 400';
  assert r.warnings->0->>'code' = 'not_deductible_6m' and r.warnings->0->>'deductible_from' = '2027-04-01', 'aviso fiscal: ' || r.warnings::text;
  assert public.pendiente(e, fmor, '2026-12-31') = 2420, 'la deuda sigue en la 430: la partida abierta no cambia';
  raise notice 'OK  · deterioro individual: Moroso 2.420 (deducible) y Dudoso 400 (no deducible hasta el 01/04/2027, art. 13.1.a LIS)';

  assert public.falla(format('select * from erp.impair_receivable(%L)', jsonb_build_object('invoice_id', fmor, 'impair_date', '2026-12-31')),
           'already impaired'), 'un deterioro activo por factura';
  assert public.falla(format('select * from erp.impair_receivable(%L)', jsonb_build_object('invoice_id', falq, 'impair_date', '2026-12-31')),
           'nothing pending'), 'una factura cobrada no se deteriora';
  assert public.falla(format('select * from erp.impair_receivable(%L)', jsonb_build_object('invoice_id', fseg, 'impair_date', '2026-12-31')),
           'Only issued invoices'), 'solo facturas emitidas';
  assert public.falla(format('select * from erp.impair_receivable(%L)', jsonb_build_object('invoice_id', fmor, 'impair_date', '2026-12-31', 'pct', 120)),
           'between 0 and 100');
  raise notice 'OK  · errores: deterioro repetido, factura cobrada, factura recibida y porcentaje fuera de rango';

  -- ---------- 3. Deterioro global por antigüedad ----------
  g1 := public.factura(e, 'sale', general, '2026-04-10', '[{"account_no":"70000001","amount":500,"tax_code":"VAT21"}]');
  g2 := public.factura(e, 'sale', general, '2026-06-15', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"}]');
  g3 := public.factura(e, 'sale', general, '2026-12-20', '[{"account_no":"70000001","amount":3000,"tax_code":"VAT21"}]');
  select string_agg(tier || ':' || basis || '×' || pct || '=' || amount, ' ' order by tier) into s
  from erp.global_impairment_calc(e, '2026-12-31', '{"not_due":0,"d1_90":5,"d91_180":10,"d181_365":25}');
  assert s = 'd181_365:605.00×25=151.25 d1_90:0×5=0.00 d365_plus:0×0=0.00 d91_180:1210.00×10=121.00 not_due:3630.00×0=0.00', s;
  select * into r from erp.impair_receivables_global(jsonb_build_object('company_id', e, 'impair_date', '2026-12-31',
    'rates', '{"not_due":0,"d1_90":5,"d91_180":10,"d181_365":25}'::jsonb));
  d_glo := r.impairment_id;
  assert r.amount = 272.25, 'global 151,25 + 121 = 272,25: ' || r.amount;
  assert r.warnings->0->>'code' = 'global_not_deductible' and (r.warnings->0->>'erd_limit')::numeric = 54.45, 'ERD: 1 % de 5.445: ' || r.warnings::text;
  assert public.falla(format('select * from erp.impair_receivables_global(%L)', jsonb_build_object('company_id', e, 'impair_date', '2026-12-31',
           'rates', '{"not_due":1}'::jsonb)), 'already a global'), 'un global activo';
  assert public.saldo(e, 2026, '694') = 2420 + 400 + 272.25 and public.saldo(e, 2026, '490') = -(2420 + 400 + 272.25), '694 y 490 = 3.092,25';
  raise notice 'OK  · global: 25 %% de 605 + 10 %% de 1.210 = 272,25 (sin Moroso ni Dudoso); no deducible, tope ERD 54,45 (art. 104 LIS)';

  -- ---------- 4. Cierre de 2026 y reversión en la apertura de 2027 ----------
  perform erp.close_fiscal_year(e, 2026, true);
  assert erp.reverse_accruals(e, '2027-01-01') = 4, 'las cuatro';
  assert public.saldo(e, 2027, '480') = 0 and public.saldo(e, 2027, '485') = 0
     and public.saldo(e, 2027, '4009') = 0 and public.saldo(e, 2027, '4309') = 0, 'cuentas de periodificación a cero en 2027';
  assert public.mov(e, 2027, '625') = 900 and public.mov(e, 2027, '752') = -4000
     and public.mov(e, 2027, '628') = -350 and public.mov(e, 2027, '705') = 600,
         'el seguro (900) y el alquiler (4.000) pasan a 2027; la luz y el mantenimiento, en negativo: los compensa la factura de 2027';
  assert (select reversal_entry_no is not null and reversal_year = 2027 from erp.v_accruals where id = a_seg), 'la ficha enlaza la reversión';
  assert public.falla(format('select erp.reverse_accrual(%L)', a_seg), 'not pending'), 'no se revierte dos veces';
  raise notice 'OK  · cierre de 2026 y reversión el 01/01/2027: 480/485/4009/4309 a cero; 900 de seguro y 4.000 de alquiler en 2027';

  -- …deshacer: primero la reversión, después la periodificación (y se vuelve a hacer)
  perform erp.cancel_accrual(a_seg);
  assert (select status from erp.accruals where id = a_seg) = 'active' and public.saldo(e, 2027, '480') = 900, 'reversión deshecha';
  perform erp.reverse_accrual(a_seg, '2027-01-01');
  assert public.saldo(e, 2027, '480') = 0;
  raise notice 'OK  · la reversión se deshace y se vuelve a hacer';

  -- ---------- 5. 2027: cobro del Dudoso y reversión de su deterioro ----------
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', 'collection', 'partner_id', dudoso,
    'payment_date', '2027-02-15', 'cash_account_no', '57200001', 'applications', jsonb_build_array(jsonb_build_object('invoice_id', fdud, 'amount', 800))));
  select erp.reverse_impairment(d_dud, '2027-02-15') into r;
  assert public.asiento(e, 2027, (select end_entry_no from erp.v_receivable_impairments where id = d_dud))
         = '49000001 D 400.00 | 79400001 H 400.00', 'reversión 490 / 794';
  raise notice 'OK  · cobrado el Dudoso: se revierte su deterioro (490 D 400 / 794 H 400)';

  -- ---------- 6. Insolvencia firme del Moroso ----------
  select * into r from erp.write_off_receivable(jsonb_build_object('invoice_id', fmor, 'writeoff_date', '2027-03-10'));
  w := r.writeoff_id;
  assert r.amount = 2420 and r.impairment_applied = 2420, row_to_json(r)::text;
  assert public.asiento(e, 2027, r.entry_no) = '65000001 D 2420.00 | 43000002 H 2420.00 | 49000001 D 2420.00 | 79400001 H 2420.00',
         public.asiento(e, 2027, r.entry_no);   -- 43000002: la subcuenta del Moroso
  assert public.pendiente(e, fmor, '2027-03-10') = 0, 'la partida abierta del Moroso queda a cero';
  assert (select status from erp.receivable_impairments where id = d_mor) = 'written_off';
  assert (select items from erp.run_audit_checks(e, 2027) where code = 'partners') = 0, 'terceros: pendiente = saldo';
  raise notice 'OK  · insolvencia firme: 650 D 2.420 / 430 H 2.420 · 490 D 2.420 / 794 H 2.420; la partida abierta queda a cero';

  -- …no se anula desde Cobros y pagos, sí desde el módulo
  assert public.falla(format('select erp.cancel_payment(%L)', (select payment_id from erp.receivable_writeoffs where id = w)),
           'receivable impairment'), 'no desde Cobros y pagos';
  assert public.falla(format('select erp.cancel_impairment(%L)', d_mor), 'cancel the write-off first');
  perform erp.cancel_write_off(w);
  assert public.pendiente(e, fmor, '2027-03-10') = 2420 and (select status from erp.receivable_impairments where id = d_mor) = 'active', 'vuelve a estar pendiente y deteriorada';
  select * into r from erp.write_off_receivable(jsonb_build_object('invoice_id', fmor, 'writeoff_date', '2027-03-10'));
  raise notice 'OK  · la insolvencia no se anula desde Cobros y pagos; desde el módulo, sí (y la factura vuelve a deber)';

  -- ---------- 7. El global se re-estima cada año: reversión y deshacer ----------
  perform erp.reverse_impairment(d_glo, '2027-12-31');
  assert public.falla(format('select erp.reverse_impairment(%L, %L)', d_glo, '2027-12-31'), 'not active');
  perform erp.cancel_impairment(d_glo);
  assert (select status from erp.receivable_impairments where id = d_glo) = 'active', 'reversión deshecha';
  perform erp.reverse_impairment(d_glo, '2027-12-31');
  assert public.saldo(e, 2027, '490') = 0, 'la 490 queda a cero en 2027: ' || public.saldo(e, 2027, '490');
  assert public.mov(e, 2027, '794') = -(400 + 2420 + 272.25), '794 = 3.092,25';
  raise notice 'OK  · el global se revierte al año siguiente; la 490 queda a cero (794 = 3.092,25)';

  -- ---------- 8. Invariantes, diario y comprobaciones ----------
  perform public.comprueba();
  assert not exists (select 1 from erp.integrity_checks(e, 2026) where status = 'fail'),
         '2026: ' || (select string_agg(code, ', ') from erp.integrity_checks(e, 2026) where status = 'fail');
  assert not exists (select 1 from erp.integrity_checks(e, 2027) where status = 'fail'),
         '2027: ' || (select string_agg(code, ', ') from erp.integrity_checks(e, 2027) where status = 'fail');
  assert (select items from erp.run_audit_checks(e, 2027) where code = 'controlled') = 0, 'los asientos de los módulos no son manuales';
  assert (select count(distinct entry_no) from erp.v_general_journal where company_id = e and fiscal_year = 2026 and source = 'accrual') = 4;
  assert (select count(distinct entry_no) from erp.v_general_journal where company_id = e and fiscal_year = 2027 and source = 'impairment') >= 3;
  raise notice 'OK  · invariantes en verde; el diario marca periodificaciones y deterioros, y no salen como manuales';
end $$;

-- ---------- 9. Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa');
begin
  assert (select count(*) from erp.v_accruals where company_id = e) = 4, 'el lector ve las periodificaciones';
  assert (select count(*) from erp.v_receivable_impairments where company_id = e) = 3, 'y los deterioros';
  assert public.falla(format('select * from erp.create_accrual(%L)', jsonb_build_object('company_id', e, 'kind', 'accrued_expense',
           'description', 'X', 'pl_account_no', '62800001', 'cutoff_date', '2027-12-31', 'amount', 10)), 'No permission'), 'pero no periodifica';
  assert public.falla(format('select erp.adjust_account(%L, %L, %L)', e, '480', 'X'), 'permission denied'), 'las ayudas no son públicas';
  begin
    insert into erp.accruals (company_id, code, kind, description, pl_account_id, balance_account_id, cutoff_date, amount, entry_id)
    select e, 'X', 'accrued_expense', 'X', id, id, current_date, 1, (select id from erp.journal_entries where company_id = e limit 1)
    from erp.gl_accounts where company_id = e limit 1;
    raise exception 'no debería poder insertar';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK  · el lector ve, no periodifica ni escribe en las tablas';
end $$;

-- ---------- 10. Borrar la empresa ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa'); n int;
begin
  loop n := erp.delete_company_step(e, 5); exit when n = 0; end loop;
  perform public.comprueba();
  assert not exists (select 1 from erp.companies where id = e);
  raise notice 'OK  · una empresa con periodificaciones, deterioros e insolvencias se borra entera';
end $$;

\echo '✔ FASE 38 OK · periodificaciones y deterioro de clientes'
