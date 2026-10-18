-- =====================================================================
-- PRUEBAS FASE 44 · Nóminas (migración 0049) · con su SUPUESTO DE REFERENCIA
-- ---------------------------------------------------------------------
-- Supuesto (calculado a mano desde la norma: art. 147 LGSS, Orden PJC/297/2026 de cotización para 2026,
-- tarifa de primas de AT / EP de la DA 4.ª Ley 42/2006, art. 99 LIRPF y cuentas 640, 642, 465, 476 y 4751 del PGC):
--  Oficina Guanche SL, 2026. Dos empleados de oficina (AT / EP 1,00 %, cuadro II «a»):
--   ANA · indefinida · 2.000 €/mes · 2 pagas extra de 2.000 (junio y diciembre) NO prorrateadas · IRPF 12 %
--     base de cotización = 2.000 + 2.000 × 2 / 12 = 2.333,33
--     trabajadora: CC 4,70 % 109,67 + desempleo 1,55 % 36,17 + FP 0,10 % 2,33 + MEI 0,15 % 3,50 = 151,67
--     empresa:     CC 23,60 % 550,67 + desempleo 5,50 % 128,33 + FOGASA 0,20 % 4,67 + FP 0,60 % 14,00
--                  + MEI 0,75 % 17,50 + AT / EP 1,00 % 23,33 = 738,50
--     enero: IRPF 12 % de 2.000 = 240 · líquido 2.000 − 240 − 151,67 = 1.608,33 · paga devengada 333,33
--       640 D 2.000 | 640 D 333,33 | 642 D 738,50 / 476 H 890,17 | 4751 H 240 | 465 H 1.608,33 | 465 H 333,33
--     junio: se paga la paga de junio (6 × 333,33 = 1.999,98 → el mes de paga devenga 333,35 y cuadra 2.000)
--       IRPF 12 % de 4.000 = 480 · líquido 4.000 − 480 − 151,67 = 3.368,33
--       640 D 2.000 | 640 D 333,35 | 465 D 2.000 | 642 D 738,50 / 476 H 890,17 | 4751 H 480 | 465 H 3.368,33 | 465 H 333,35
--   LUIS · temporal · 1.500 €/mes · 2 pagas PRORRATEADAS (250 al mes) · IRPF 2 %
--     base = 1.750 · trabajador: 82,25 + desempleo 1,60 % 28,00 + 1,75 + 2,63 = 114,63
--     empresa: 413,00 + desempleo 6,70 % 117,25 + 3,50 + 10,50 + 13,13 + AT 17,50 = 574,88
--     IRPF 2 % de 1.750 = 35 · líquido 1.750 − 35 − 114,63 = 1.600,37
--       640 D 1.750 | 642 D 574,88 / 476 H 689,51 | 4751 H 35 | 465 H 1.600,37
--   Pagos de enero: líquido 31/01 465 D 3.208,70 / 572 H · seguros sociales 27/02 476 D 1.579,68 / 572 H
--   DIRECTORA (alta en diciembre, solo el cálculo): 6.000 prorrateada → remuneración 7.000 > base máxima 5.101,20:
--     solidaridad tramo 1: 510,12 × 0,96 % = 4,90 (empresa) / 0,19 % = 0,97 (trabajadora)
--     tramo 2: 1.388,68 × 1,04 % = 14,44 / 0,21 % = 2,92
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
create or replace function public.asiento(e uuid, y int, n int) returns text language sql as $$
  select string_agg(g.account_no || ' ' || case when l.debit > 0 then 'D ' || l.debit else 'H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_entries j join erp.fiscal_years fy on fy.id = j.fiscal_year_id and fy.year = y
  join erp.journal_lines l on l.entry_id = j.id join erp.gl_accounts g on g.id = l.gl_account_id
  where j.company_id = e and j.entry_no = n;
$$;
create or replace function public.comprueba() returns void language plpgsql as $$
begin execute 'set constraints all immediate'; execute 'set constraints all deferred'; end $$;
grant execute on function public.falla(text, text), public.saldo(uuid, int, text), public.asiento(uuid, int, int), public.comprueba() to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; ana uuid; luis uuid; dir uuid; baja uuid; r record; n int; w uuid; c jsonb; enero uuid; junio uuid; m int;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Oficina Guanche SL', 'services', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.set_control_mode(e, 'strict');
  perform erp.create_posting_account(e, x.no, x.name) from (values ('57200001', 'Banco'), ('10000001', 'Capital')) as x(no, name);
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-01-02', 'Capital') returning id into w;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (w, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), 100000, 0),
    (w, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '10000001'), 0, 100000);
  perform erp.post_entry(w);

  -- ---------- 1. Empleados ----------
  ana := erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Ana Ficticia', 'contract_type', 'indefinite', 'hire_date', '2025-03-01',
    'monthly_salary', 2000, 'extra_payments', 2, 'extra_prorated', false, 'irpf_pct', 12));
  luis := erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Luis Ficticio', 'contract_type', 'temporary', 'hire_date', '2026-01-01',
    'end_date', '2026-12-15', 'monthly_salary', 1500, 'extra_payments', 2, 'extra_prorated', true, 'irpf_pct', 2));
  assert (select string_agg(code || ' ' || at_ep_pct, ', ' order by code) from erp.employees where company_id = e) = 'EMP-0001 1.00, EMP-0002 1.00';
  assert public.falla(format('select erp.save_employee(%L)', jsonb_build_object('company_id', e, 'name', 'X', 'hire_date', '2026-01-01',
           'monthly_salary', 0)), 'greater than zero');
  assert public.falla(format('select erp.save_employee(%L)', jsonb_build_object('company_id', e, 'name', ' ', 'hire_date', '2026-01-01',
           'monthly_salary', 10)), 'needs a name');
  raise notice 'OK  · empleados EMP-0001 y EMP-0002 (AT / EP 1,00 %% por defecto); errores de alta';

  -- ---------- 2. Cálculo de enero ----------
  c := erp.payslip_calc(ana, '2026-01-31');
  assert (c->>'ss_base')::numeric = 2333.33 and (c->>'ss_employee')::numeric = 151.67 and (c->>'ss_employer')::numeric = 738.50, c::text;
  assert (c->>'irpf')::numeric = 240 and (c->>'net')::numeric = 1608.33 and (c->>'extra_accrual')::numeric = 333.33 and (c->>'extra_paid')::numeric = 0, c::text;
  assert (select string_agg(x->>'concept' || ' ' || (x->>'employer') || '/' || (x->>'employee'), ', ') from jsonb_array_elements(c->'ss_detail') x)
       = 'common 550.67/109.67, unemployment_indefinite 128.33/36.17, fogasa 4.67/0.00, training 14.00/2.33, mei 17.50/3.50, at_ep 23.33/0',
         (select string_agg(x->>'concept' || ' ' || (x->>'employer') || '/' || (x->>'employee'), ', ') from jsonb_array_elements(c->'ss_detail') x);
  c := erp.payslip_calc(luis, '2026-01-31');
  assert (c->>'salary')::numeric = 1750 and (c->>'ss_base')::numeric = 1750 and (c->>'ss_employee')::numeric = 114.63
     and (c->>'ss_employer')::numeric = 574.88 and (c->>'irpf')::numeric = 35 and (c->>'net')::numeric = 1600.37, c::text;
  assert (select x->>'employer' from jsonb_array_elements(c->'ss_detail') x where x->>'concept' = 'unemployment_temporary') = '117.25', 'desempleo temporal 6,70 %';
  raise notice 'OK  · enero: Ana base 2.333,33, cuotas 151,67 / 738,50, líquido 1.608,33; Luis base 1.750, 114,63 / 574,88, líquido 1.600,37';

  -- ---------- 3. Contabilizar enero y pagarla ----------
  select * into r from erp.run_payroll(jsonb_build_object('company_id', e, 'period', '2026-01-15'));
  enero := r.run_id;
  assert r.employees = 2 and r.gross = 4083.33 and r.net = 3208.70, r::text;
  assert public.asiento(e, 2026, r.entry_no) =
    '64000001 D 2000.00 | 64000001 D 333.33 | 64200001 D 738.50 | 47600001 H 890.17 | 47510001 H 240.00 | 46500001 H 1608.33 | 46500001 H 333.33'
    || ' | 64000001 D 1750.00 | 64200001 D 574.88 | 47600001 H 689.51 | 47510001 H 35.00 | 46500001 H 1600.37', public.asiento(e, 2026, r.entry_no);
  assert (select period from erp.payroll_runs where id = enero) = '2026-01-31', 'el mes se guarda en su último día';
  assert public.falla(format('select * from erp.run_payroll(%L)', jsonb_build_object('company_id', e, 'period', '2026-01-31')), 'already posted');
  n := erp.pay_payroll(jsonb_build_object('run_id', enero, 'what', 'net', 'payment_date', '2026-01-31', 'cash_account_no', '57200001'));
  assert public.asiento(e, 2026, n) = '46500001 D 3208.70 | 57200001 H 3208.70', public.asiento(e, 2026, n);
  assert public.falla(format('select erp.pay_payroll(%L)', jsonb_build_object('run_id', enero, 'what', 'net', 'payment_date', '2026-01-31',
           'cash_account_no', '57200001')), 'already posted');
  assert public.falla(format('select erp.pay_payroll(%L)', jsonb_build_object('run_id', enero, 'what', 'social_security', 'payment_date', '2026-02-27',
           'cash_account_no', '10000001')), 'cash or bank');
  n := erp.pay_payroll(jsonb_build_object('run_id', enero, 'what', 'social_security', 'payment_date', '2026-02-27', 'cash_account_no', '57200001'));
  assert public.asiento(e, 2026, n) = '47600001 D 1579.68 | 57200001 H 1579.68', public.asiento(e, 2026, n);
  assert public.saldo(e, 2026, '476') = 0 and public.saldo(e, 2026, '465') = -333.33 and public.saldo(e, 2026, '4751') = -275,
         'tras pagar: queda la paga de Ana devengada (465) y el IRPF del 111 (4751)';
  raise notice 'OK  · enero contabilizado (12 apuntes), líquido pagado 3.208,70 y seguros sociales 1.579,68; quedan 333,33 en la 465';

  -- …deshacer: primero los seguros sociales, después el líquido; y se vuelven a pagar
  perform erp.cancel_payroll(enero, '2026-02-27');
  assert (select ss_payment_entry_id is null and net_payment_entry_id is not null from erp.payroll_runs where id = enero);
  perform erp.cancel_payroll(enero, '2026-01-31');
  assert (select net_payment_entry_id is null from erp.payroll_runs where id = enero);
  perform erp.pay_payroll(jsonb_build_object('run_id', enero, 'what', 'net', 'payment_date', '2026-01-31', 'cash_account_no', '57200001'));
  perform erp.pay_payroll(jsonb_build_object('run_id', enero, 'what', 'social_security', 'payment_date', '2026-02-27', 'cash_account_no', '57200001'));
  raise notice 'OK  · deshacer los pagos (el último primero) y rehacerlos';

  -- …modo estricto y diario
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-01-31', 'A mano') returning id into w;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (w, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '64000001'), 10, 0),
    (w, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '46500001'), 0, 10);
  assert public.falla(format('select erp.post_entry(%L); select public.comprueba()', w), 'controlled by payroll'), 'estricto: 465 a mano no';
  delete from erp.journal_lines where entry_id = w; delete from erp.journal_entries where id = w;
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', (select entry_id from erp.payroll_runs where id = enero), '2026-01-31', 'x'),
           'belongs to a payroll'), 'no se anula desde el diario';
  raise notice 'OK  · modo estricto: la 465 solo la mueve Nóminas; su asiento no se anula desde el diario';

  -- ---------- 4. Febrero a junio: la paga de junio ----------
  assert public.falla(format('select * from erp.run_payroll(%L)', jsonb_build_object('company_id', e, 'period', '2025-12-31')), 'later payroll'), 'no se contabiliza un mes anterior';
  for m in 2..5 loop
    perform erp.run_payroll(jsonb_build_object('company_id', e, 'period', make_date(2026, m, 1)));
  end loop;
  assert public.saldo(e, 2026, '465') = -3208.70 * 4 - 333.33 * 5, 'cuatro líquidos sin pagar + cinco meses de paga devengada';
  select * into r from erp.run_payroll(jsonb_build_object('company_id', e, 'period', '2026-06-30'));
  junio := r.run_id;
  assert public.asiento(e, 2026, r.entry_no) =
    '64000001 D 2000.00 | 64000001 D 333.35 | 46500001 D 2000.00 | 64200001 D 738.50 | 47600001 H 890.17 | 47510001 H 480.00 | 46500001 H 3368.33 | 46500001 H 333.35'
    || ' | 64000001 D 1750.00 | 64200001 D 574.88 | 47600001 H 689.51 | 47510001 H 35.00 | 46500001 H 1600.37', public.asiento(e, 2026, r.entry_no);
  assert (select extra_paid from erp.payslips where run_id = junio and employee_id = ana) = 2000, 'paga de junio = 2.000';
  assert (select sum(extra_accrual) - sum(extra_paid) from erp.payslips where employee_id = ana) = 0, 'devengado = pagado';
  assert public.saldo(e, 2026, '640') = (2000 + 333.33) * 5 + 2000 + 333.35 + 1750 * 6, '640 = 6 salarios + 6 meses de paga';
  raise notice 'OK  · junio: paga extra de 2.000 (cinco meses de 333,33 + 333,35), IRPF 480, líquido 3.368,33';

  -- …orden de los meses y anulación de la última nómina
  assert public.falla(format('select * from erp.run_payroll(%L)', jsonb_build_object('company_id', e, 'period', '2026-03-31')), 'already posted');
  assert public.falla(format('select erp.cancel_payroll(%L)', (select id from erp.payroll_runs where company_id = e and period = '2026-02-28')),
           'Only the last payroll'), 'solo se anula la última (febrero no tiene pagos que deshacer)';
  perform erp.cancel_payroll(junio);
  assert (select status from erp.payroll_runs where id = junio) = 'cancelled';
  assert public.saldo(e, 2026, '465') = -3208.70 * 4 - 333.33 * 5, 'anulada junio, vuelve todo';
  select * into r from erp.run_payroll(jsonb_build_object('company_id', e, 'period', '2026-06-30'));
  assert (select extra_paid from erp.payslips where run_id = r.run_id and employee_id = ana) = 2000, 'rehecha, la paga sale igual';
  raise notice 'OK  · los meses van en orden; solo se anula la última nómina y se rehace igual';

  -- ---------- 5. Cálculos de diciembre: solidaridad, base mínima y mes incompleto ----------
  dir := erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Directora Ficticia', 'hire_date', '2026-12-01',
    'monthly_salary', 6000, 'extra_prorated', true, 'irpf_pct', 30));
  c := erp.payslip_calc(dir, '2026-12-31');
  assert (c->>'ss_base')::numeric = 5101.20 and jsonb_array_length(c->'warnings') = 0, c::text;
  assert (select string_agg(x->>'concept' || ' ' || (x->>'base') || ' ' || (x->>'employer') || '/' || (x->>'employee'), ', ')
          from jsonb_array_elements(c->'ss_detail') x where x->>'concept' like 'solidarity%')
       = 'solidarity_1 510.12 4.90/0.97, solidarity_2 1388.68 14.44/2.92',
         (select string_agg(x->>'concept' || ' ' || (x->>'base') || ' ' || (x->>'employer') || '/' || (x->>'employee'), ', ')
          from jsonb_array_elements(c->'ss_detail') x where x->>'concept' like 'solidarity%');
  baja := erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Media Jornada Ficticia', 'hire_date', '2026-12-01', 'monthly_salary', 1000));
  assert (select jsonb_agg(x->>'code') from jsonb_array_elements(erp.payslip_calc(baja, '2026-12-31')->'warnings') x) = '["below_min_base"]';
  assert (select jsonb_agg(x->>'code') from jsonb_array_elements(erp.payslip_calc(luis, '2026-12-31')->'warnings') x) = '["partial_month"]',
         'Luis termina el 15/12: el mes no está completo';
  assert public.falla(format('select erp.payslip_calc(%L, %L)', ana, '2027-01-31'), 'no contribution rates for 2027');
  raise notice 'OK  · diciembre: tope de 5.101,20 y solidaridad (4,90 / 0,97 y 14,44 / 2,92); avisos de base mínima y mes incompleto';

  -- ---------- 6. Invariantes y diario ----------
  perform public.comprueba();
  assert not exists (select 1 from erp.integrity_checks(e, 2026) where status = 'fail'),
         (select string_agg(code, ', ') from erp.integrity_checks(e, 2026) where status = 'fail');
  assert (select items from erp.run_audit_checks(e, 2026) where code = 'controlled') = 0, 'los asientos del módulo no son manuales';
  assert (select count(distinct entry_no) from erp.v_general_journal where company_id = e and fiscal_year = 2026 and source = 'payroll') = 10,
         'seis nóminas, la anulada con su contraasiento y dos pagos: ' || (select count(distinct entry_no) from erp.v_general_journal
          where company_id = e and fiscal_year = 2026 and source = 'payroll');
  assert (select count(*) from erp.v_payroll_runs where company_id = e and status = 'posted') = 6;
  raise notice 'OK  · invariantes en verde; el diario marca las nóminas';
end $$;

-- ---------- 7. Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa');
begin
  assert (select count(*) from erp.employees where company_id = e) = 4, 'el lector ve los empleados';
  assert (select net from erp.v_payroll_runs where company_id = e and period = '2026-01-31') = 3208.70, 'y las nóminas';
  assert (select count(*) from erp.payslips where company_id = e) = 14;
  assert public.falla(format('select * from erp.run_payroll(%L)', jsonb_build_object('company_id', e, 'period', '2026-07-31')), 'No permission'), 'pero no la hace';
  assert public.falla(format('select erp.save_employee(%L)', jsonb_build_object('company_id', e, 'name', 'X', 'hire_date', '2026-01-01',
           'monthly_salary', 10)), 'No permission'), 'ni da de alta';
  assert (select count(*) from erp.ss_rates where year = 2026) = 9, 'los tipos son públicos para los usuarios';
  raise notice 'OK  · el lector ve, no contabiliza ni da de alta';
end $$;

-- ---------- 8. Borrar la empresa ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa'); n int;
begin
  loop n := erp.delete_company_step(e, 5); exit when n = 0; end loop;
  perform public.comprueba();
  assert not exists (select 1 from erp.companies where id = e) and not exists (select 1 from erp.employees where company_id = e);
  raise notice 'OK  · una empresa con nóminas se borra entera';
end $$;

\echo '✔ FASE 44 OK · nóminas'
