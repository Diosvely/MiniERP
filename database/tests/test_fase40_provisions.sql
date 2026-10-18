-- =====================================================================
-- PRUEBAS FASE 40 · Provisiones (migración 0045) · con su SUPUESTO DE REFERENCIA
-- ---------------------------------------------------------------------
-- Supuesto (calculado a mano desde la norma: PGC 2007, NRV 15.ª y cuentas 141, 142, 499, 529, 695 y 795):
--  Servicios Teide SL, ejercicios 2026 a 2028.
--   A) LITIGIO. Un cliente demanda a la empresa en 2026; el abogado ve probable una condena de 12.000 que se resolverá
--      en 2028 (más de un año: largo plazo).
--        31/12/2026  dotación                678 D 12.000 / 142 H 12.000
--        31/12/2027  nueva estimación 15.000  678 D 3.000  / 142 H 3.000
--                    vence en menos de un año → reclasificación  142 D 15.000 / 5293 H 15.000
--        15/03/2028  sentencia: paga 14.000   5293 D 15.000 / 572 H 14.000 · 7953 H 1.000 (exceso)
--   B) GARANTÍAS (operaciones comerciales). Estimación del 2 % de las ventas con garantía (50.000) = 1.000.
--        31/12/2026  6959 D 1.000 / 4999 H 1.000
--        31/12/2027  nueva estimación 1.200: el PGC revierte la anterior y dota la nueva (no el neto):
--                    4999 D 1.000 / 7954 H 1.000 · 6959 D 1.200 / 4999 H 1.200
--   C) IMPUESTOS. Acta de inspección del Impuesto sobre Sociedades de 2024, que se pagará en 2027: 3.000 (corto plazo).
--        31/12/2026  633 D 3.000 / 5292 H 3.000
--        20/04/2027  paga 3.200: 5292 D 3.000 · 633 D 200 / 572 H 3.200 (lo pagado de más, al mismo gasto)
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
create or replace function public.saldo(e uuid, y int, prefijo text) returns numeric language sql as $$
  select coalesce(sum(debit_balance - credit_balance), 0) from erp.trial_balance(e, y) where account_no like prefijo || '%';
$$;
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
create or replace function public.comprueba() returns void language plpgsql as $$
begin execute 'set constraints all immediate'; execute 'set constraints all deferred'; end $$;
grant execute on function public.falla(text, text), public.saldo(uuid, int, text), public.mov(uuid, int, text),
  public.asiento(uuid, int, int), public.comprueba() to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; lit uuid; gar uuid; imp uuid; r record; n int; w uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Servicios Teide SL', 'services', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  perform erp.create_fiscal_year(e, 2026);
  perform erp.create_fiscal_year(e, 2027);
  perform erp.create_fiscal_year(e, 2028);
  perform erp.setup_taxes(e);
  perform erp.set_control_mode(e, 'strict');
  perform erp.create_posting_account(e, x.no, x.name) from (values
    ('67800001', 'Gastos excepcionales'), ('63300001', 'Ajustes negativos en la imposición sobre beneficios'),
    ('57200001', 'Banco'), ('10000001', 'Capital')) as x(no, name);
  -- capital para que el banco tenga saldo
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-01-02', 'Capital') returning id into w;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (w, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), 50000, 0),
    (w, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '10000001'), 0, 50000);
  perform erp.post_entry(w);

  -- ---------- 1. Dotaciones al 31/12/2026 ----------
  select * into r from erp.create_provision(jsonb_build_object('company_id', e, 'kind', 'liabilities', 'term', 'long',
    'description', 'Demanda de un cliente', 'amount', 12000, 'provision_date', '2026-12-31', 'expense_account_no', '67800001'));
  lit := r.provision_id;
  assert r.code = 'PRV-0001' and public.asiento(e, 2026, r.entry_no) = '67800001 D 12000.00 | 14200001 H 12000.00', public.asiento(e, 2026, r.entry_no);
  select * into r from erp.create_provision(jsonb_build_object('company_id', e, 'kind', 'commercial',
    'description', 'Garantías de ventas (2 % de 50.000)', 'amount', 1000, 'provision_date', '2026-12-31'));
  gar := r.provision_id;
  assert public.asiento(e, 2026, r.entry_no) = '69590001 D 1000.00 | 49990001 H 1000.00', public.asiento(e, 2026, r.entry_no);
  select * into r from erp.create_provision(jsonb_build_object('company_id', e, 'kind', 'taxes', 'term', 'short',
    'description', 'Acta de inspección del IS 2024', 'amount', 3000, 'provision_date', '2026-12-31', 'expense_account_no', '63300001'));
  imp := r.provision_id;
  assert public.asiento(e, 2026, r.entry_no) = '63300001 D 3000.00 | 52920001 H 3000.00', public.asiento(e, 2026, r.entry_no);
  assert public.saldo(e, 2026, '142') = -12000 and public.saldo(e, 2026, '4999') = -1000 and public.saldo(e, 2026, '5292') = -3000;
  raise notice 'OK  · dotaciones 2026: 142 12.000 (678), 4999 1.000 (6959), 5292 3.000 (633)';

  -- …errores
  assert public.falla(format('select * from erp.create_provision(%L)', jsonb_build_object('company_id', e, 'kind', 'liabilities',
           'description', 'X', 'amount', 10, 'provision_date', '2026-12-31', 'expense_account_no', '57200001')), 'expense account by nature');
  assert public.falla(format('select * from erp.create_provision(%L)', jsonb_build_object('company_id', e, 'kind', 'otra',
           'description', 'X', 'amount', 10, 'provision_date', '2026-12-31')), 'Invalid provision type');
  assert public.falla(format('select * from erp.create_provision(%L)', jsonb_build_object('company_id', e, 'kind', 'taxes',
           'description', 'X', 'amount', 0, 'provision_date', '2026-12-31', 'expense_account_no', '63300001')), 'greater than zero');
  raise notice 'OK  · errores: gasto que no es por naturaleza, tipo desconocido e importe cero';

  -- …modo estricto y diario
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-12-31', 'A mano') returning id into w;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (w, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '67800001'), 10, 0),
    (w, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '14200001'), 0, 10);
  assert public.falla(format('select erp.post_entry(%L); select public.comprueba()', w), 'controlled by provisions'), 'estricto: 142 a mano no';
  delete from erp.journal_lines where entry_id = w; delete from erp.journal_entries where id = w;
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', (select entry_id from erp.provision_movements where provision_id = lit),
           '2026-12-31', 'x'), 'belongs to a provision'), 'no se anula desde el diario';
  raise notice 'OK  · modo estricto: la 142 solo la mueve el módulo; su asiento no se anula desde el diario';

  perform erp.close_fiscal_year(e, 2026, true);

  -- ---------- 2. 2027: revisión, aplicación y reclasificación ----------
  select * into r from erp.revise_provision(jsonb_build_object('provision_id', lit, 'review_date', '2027-12-31', 'new_amount', 15000));
  assert r.difference = 3000 and public.asiento(e, 2027, r.entry_no) = '67800001 D 3000.00 | 14200001 H 3000.00', public.asiento(e, 2027, r.entry_no);
  select * into r from erp.revise_provision(jsonb_build_object('provision_id', gar, 'review_date', '2027-12-31', 'new_amount', 1200));
  assert public.asiento(e, 2027, r.entry_no) = '49990001 D 1000.00 | 79540001 H 1000.00 | 69590001 D 1200.00 | 49990001 H 1200.00',
         'garantías: se revierte la anterior y se dota la nueva: ' || public.asiento(e, 2027, r.entry_no);
  select * into r from erp.apply_provision(jsonb_build_object('provision_id', imp, 'application_date', '2027-04-20', 'paid', 3200, 'cash_account_no', '57200001'));
  assert r.difference = 200 and public.asiento(e, 2027, r.entry_no) = '52920001 D 3000.00 | 63300001 D 200.00 | 57200001 H 3200.00',
         public.asiento(e, 2027, r.entry_no);
  assert (select status from erp.provisions where id = imp) = 'applied';
  assert public.falla(format('select * from erp.revise_provision(%L)', jsonb_build_object('provision_id', imp, 'review_date', '2027-12-31', 'new_amount', 1)),
           'is not active'), 'aplicada, ya no se revisa';
  n := erp.reclassify_provision(lit, '2027-12-31');
  assert public.asiento(e, 2027, n) = '14200001 D 15000.00 | 52930001 H 15000.00', public.asiento(e, 2027, n);
  assert public.falla(format('select erp.reclassify_provision(%L, %L)', lit, '2027-12-31'), 'already short-term');
  assert public.falla(format('select * from erp.revise_provision(%L)', jsonb_build_object('provision_id', lit, 'review_date', '2027-12-30', 'new_amount', 1)),
           'already has a movement after'), 'no se mete un movimiento antes del último';
  assert public.mov(e, 2027, '678') = 3000 and public.mov(e, 2027, '7954') = -1000 and public.mov(e, 2027, '6959') = 1200
     and public.mov(e, 2027, '633') = 200, 'gastos e ingresos de 2027';
  raise notice 'OK  · 2027: litigio +3.000 (678) y a corto plazo (5293); garantías 7954 1.000 / 6959 1.200; acta pagada 3.200 (633 200)';

  -- …deshacer: la reclasificación vuelve a la 142, y se rehace
  perform erp.cancel_provision_movement(lit);
  assert (select term || ' ' || provision_account_no from erp.v_provisions where id = lit) = 'long 14200001', 'vuelve al largo plazo';
  perform erp.reclassify_provision(lit, '2027-12-31');
  -- …y la aplicación del acta vuelve a dejarla viva
  perform erp.cancel_provision_movement(imp);
  assert (select status || ' ' || balance from erp.v_provisions where id = imp) = 'active 3000.00', 'aplicación deshecha';
  perform erp.apply_provision(jsonb_build_object('provision_id', imp, 'application_date', '2027-04-20', 'paid', 3200, 'cash_account_no', '57200001'));
  raise notice 'OK  · deshacer el último movimiento (reclasificación, aplicación) y volver a hacerlo';

  perform erp.close_fiscal_year(e, 2027, true);
  assert public.saldo(e, 2027, '142') = 0 and public.saldo(e, 2027, '5293') = -15000 and public.saldo(e, 2027, '4999') = -1200
     and public.saldo(e, 2027, '5292') = 0, 'saldos al cierre de 2027 (con la apertura): ' || public.saldo(e, 2027, '5293');

  -- ---------- 3. 2028: sentencia ----------
  select * into r from erp.apply_provision(jsonb_build_object('provision_id', lit, 'application_date', '2028-03-15', 'paid', 14000, 'cash_account_no', '57200001'));
  assert r.difference = -1000 and public.asiento(e, 2028, r.entry_no) = '52930001 D 15000.00 | 57200001 H 14000.00 | 79530001 H 1000.00',
         public.asiento(e, 2028, r.entry_no);
  assert public.saldo(e, 2028, '5293') = 0, 'la 5293 queda a cero';
  raise notice 'OK  · 2028: sentencia de 14.000 sobre 15.000 provisionados → 1.000 de exceso (7953); la 5293 a cero';

  -- ---------- 4. Invariantes y diario ----------
  perform public.comprueba();
  for n in 2026..2028 loop
    assert not exists (select 1 from erp.integrity_checks(e, n) where status = 'fail'),
           n || ': ' || (select string_agg(code, ', ') from erp.integrity_checks(e, n) where status = 'fail');
  end loop;
  assert (select items from erp.run_audit_checks(e, 2027) where code = 'controlled') = 0, 'los asientos del módulo no son manuales';
  assert (select count(distinct entry_no) from erp.v_general_journal where company_id = e and fiscal_year = 2026 and source = 'provision') = 3;
  raise notice 'OK  · invariantes en verde en los tres años; el diario marca las provisiones';
end $$;

-- ---------- 5. Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa');
begin
  assert (select count(*) from erp.v_provisions where company_id = e) = 3, 'el lector ve las provisiones';
  assert (select jsonb_array_length(movements) from erp.v_provisions where company_id = e and code = 'PRV-0001') = 4, 'con sus movimientos';
  assert public.falla(format('select * from erp.create_provision(%L)', jsonb_build_object('company_id', e, 'kind', 'commercial',
           'description', 'X', 'amount', 10, 'provision_date', '2028-12-31')), 'No permission'), 'pero no dota';
  assert public.falla(format('select erp.provision_post(%L, %L, %L, %L)', e, '2028-12-31', 'x', '[]'), 'permission denied'), 'las ayudas no son públicas';
  raise notice 'OK  · el lector ve, no dota ni usa las ayudas internas';
end $$;

-- ---------- 6. Borrar la empresa ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa'); n int;
begin
  loop n := erp.delete_company_step(e, 5); exit when n = 0; end loop;
  perform public.comprueba();
  assert not exists (select 1 from erp.companies where id = e);
  raise notice 'OK  · una empresa con provisiones se borra entera';
end $$;

\echo '✔ FASE 40 OK · provisiones'
