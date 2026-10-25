-- =====================================================================
-- PRUEBAS FASE 57 · Financiación: préstamos a coste amortizado y arrendamiento financiero (migración 0062 · v0.43.0)
-- ---------------------------------------------------------------------
-- Supuestos de referencia calculados a mano desde el PGC antes de programar (docs del proyecto: supuestos-v0.43.0.md).
--   F1  Préstamo francés de 100.000 al 6 %, 5 cuotas anuales el 31/12: cuota 23.739,64 (la última, ,63) · alta 572 /
--       5200 17.739,64 + 1700 82.260,36 · cuota 6623 6.000 + 5200 17.739,64 · reclasificación 18.804,02
--   F1b El mismo, recibido el 01/07 y con cuotas el 30/06: intereses devengados al 31/12 con el TIE 2.956,30 (527);
--       la cuota: 527 2.956,30 + 6623 3.043,70 + 5200 17.739,64
--   F2  F1 con una comisión de apertura de 1.000: se reciben 99.000 · TIE 6,3705 % · intereses del primer año
--       6.306,83 · reclasificación 18.543,38 · intereses totales 19.698,19
--   F3  Leasing de una máquina de 50.000: 4 cuotas de 13.500 y opción de compra de 2.500 · tipo implícito 4,9388 % ·
--       alta 213 / 5240 11.030,59 + 1740 38.969,41 · primera cuota: 5240 11.030,59 + intereses 2.469,41
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
create or replace function public.empresa(nombre text) returns uuid language plpgsql as $$
declare e uuid; c text;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values (nombre, 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027); perform erp.create_fiscal_year(e, 2028);
  perform erp.setup_taxes(e);
    foreach c in array array['57200001:Banco', '70500001:Prestación de servicios', '62900001:Otros servicios', '41000001:Acreedores'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  return e;
end $$;
create or replace function public.manual(e uuid, d date, l jsonb) returns void language plpgsql as $$
declare a uuid; x jsonb;
begin
  for x in select * from jsonb_array_elements(l) loop   -- las cuentas que falten (113, 112…), se crean
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = x->>0) then
      perform erp.create_posting_account(e, x->>0, 'Cuenta ' || (x->>0));
    end if;
  end loop;
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = extract(year from d)), d, 'Supuesto') returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
end $$;
create or replace function public.asiento(p_loan uuid, p_kind text, p_n int default null) returns text language sql as $$
  select string_agg(left(g.account_no, 4) || case when l.debit <> 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
  where l.entry_id = (select v.entry_id from erp.loan_events v where v.loan_id = p_loan and v.kind = p_kind and v.status = 'posted'
                        and (p_n is null or v.n = p_n) order by v.seq desc limit 1);
$$;
create or replace function public.saldo(e uuid, pref text, d date) returns numeric language sql as $$
  select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id where j.company_id = e and j.status = 'posted' and j.posting_date <= d and g.account_no like pref || '%';
$$;
create or replace function public.prestamo(e uuid, extra jsonb) returns uuid language sql as $$
  select (erp.loan_create(jsonb_build_object('company_id', e, 'description', 'Préstamo de prueba', 'lender', 'Banco') || extra)->>'loan_id')::uuid $$;
grant execute on function public.falla(text, text), public.empresa(text), public.manual(uuid, date, jsonb), public.asiento(uuid, text, int),
  public.saldo(uuid, text, date), public.prestamo(uuid, jsonb) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- F1 · Préstamo francés sin gastos ----------
do $$
declare e uuid := public.empresa('F1'); l uuid; x jsonb;
begin
  insert into public.ctx values ('f1', e);
  l := public.prestamo(e, '{"principal": 100000, "rate": 6, "periods": 5, "frequency": 1, "start_date": "2026-01-01"}');
  assert (select instalment from erp.loans where id = l) = 23739.64, 'cuota';
  assert (select first_due_date from erp.loans where id = l) = '2026-12-31', 'primer vencimiento: un periodo después';
  assert (select string_agg(payment || '/' || interest || '/' || reduction || '/' || balance, ' ' order by n) from erp.loan_schedule where loan_id = l)
       = '23739.64/6000.00/17739.64/82260.36 23739.64/4935.62/18804.02/63456.34 23739.64/3807.38/19932.26/43524.08 '
         '23739.64/2611.44/21128.20/22395.88 23739.63/1343.75/22395.88/0.00', 'cuadro F1';
  assert (select effective_rate_year from erp.loans where id = l) = 6, 'sin gastos, el TIE es el nominal';
  assert public.asiento(l, 'start') = '5720 D 100000.00 | 5200 H 17739.64 | 1700 H 82260.36', 'alta: ' || public.asiento(l, 'start');
  x := erp.loan_payment(jsonb_build_object('loan_id', l));
  assert x->>'date' = '2026-12-31', 'por defecto, en el vencimiento';
  assert public.asiento(l, 'payment', 1) = '6623 D 6000.00 | 5200 D 17739.64 | 5720 H 23739.64', 'cuota: ' || public.asiento(l, 'payment', 1);
  x := erp.loan_year_end_preview(e, '2026-12-31');
  assert (x->>'accrual_total')::numeric = 0 and (x->>'reclassification_total')::numeric = 18804.02, 'cierre: ' || x::text;
  perform erp.loan_year_end(e, '2026-12-31');
  assert public.asiento(l, 'reclassification') = '1700 D 18804.02 | 5200 H 18804.02', 'reclasificación';
  assert public.saldo(e, '1700', '2026-12-31') = 63456.34 and public.saldo(e, '5200', '2026-12-31') = 18804.02, 'balance de 2026';
  -- repetirlo no cambia nada
  assert (erp.loan_year_end(e, '2026-12-31')->>'entries')::int = 0, 'el cierre no se repite';
  -- se paga entero: la última cuota ajusta el céntimo y la deuda queda a cero
  perform erp.loan_payment(jsonb_build_object('loan_id', l));
  perform erp.loan_year_end(e, '2027-12-31');
  perform erp.loan_payment(jsonb_build_object('loan_id', l));
  assert public.falla(format('select erp.loan_payment(%L)', jsonb_build_object('loan_id', l, 'date', '2029-12-31')), 'fiscal year'), 'sin ejercicio 2029';
  raise notice 'OK  · F1: cuadro francés, cobro, cuota (6623 / 5200) y reclasificación del largo al corto (18.804,02)';
end $$;

-- ---------- F1b · Intereses devengados al cierre ----------
do $$
declare e uuid := public.empresa('F1b'); l uuid; x jsonb;
begin
  insert into public.ctx values ('f1b', e);
  l := public.prestamo(e, '{"principal": 100000, "rate": 6, "periods": 5, "frequency": 1, "start_date": "2026-07-01"}');
  assert (select first_due_date from erp.loans where id = l) = '2027-06-30', 'vence el 30/06';
  assert public.asiento(l, 'start') = '5720 D 100000.00 | 5200 H 17739.64 | 1700 H 82260.36', 'alta F1b';
  x := erp.loan_year_end_preview(e, '2026-12-31')->'loans'->0;
  assert (x->>'accrual')::numeric = 2956.30 and (x->>'days')::int = 180 and (x->>'reclassification')::numeric = 0, 'devengo: ' || x::text;
  perform erp.loan_year_end(e, '2026-12-31');
  assert public.asiento(l, 'accrual') = '6623 D 2956.30 | 5270 H 2956.30', 'devengo: ' || public.asiento(l, 'accrual');
  assert public.asiento(l, 'reclassification') is null, 'nada que reclasificar';
  assert public.falla(format('select erp.loan_payment(%L)', jsonb_build_object('loan_id', l, 'date', '2026-12-30')), 'earlier than the last posting');
  perform erp.loan_payment(jsonb_build_object('loan_id', l));
  assert public.asiento(l, 'payment', 1) = '5270 D 2956.30 | 6623 D 3043.70 | 5200 D 17739.64 | 5720 H 23739.64', 'cuota F1b: ' || public.asiento(l, 'payment', 1);
  assert public.saldo(e, '527', '2027-06-30') = 0, 'la 527 queda a cero';
  assert -public.saldo(e, '6623', '2027-06-30') = 6000, 'intereses del primer año: 6.000';
  -- al cierre de 2027: medio año de la segunda cuota y la reclasificación de la tercera
  x := erp.loan_year_end_preview(e, '2027-12-31')->'loans'->0;
  assert (x->>'accrual')::numeric = round(82260.36 * (power(1.06::numeric, 0.5) - 1), 2) and (x->>'reclassification')::numeric = 18804.02, 'cierre 2027: ' || x::text;
  -- una cuota vencida y sin pagar no deja cerrar
  perform erp.loan_year_end(e, '2027-12-31');
  assert public.falla(format('select erp.loan_year_end(%L, %L)', e, '2028-12-31'), 'is not posted'), 'cuota vencida';
  raise notice 'OK  · F1b: intereses devengados con el TIE (2.956,30 a la 527) y la cuota que los salda';
end $$;

-- ---------- F2 · Comisión de apertura: coste amortizado ----------
do $$
declare e uuid := public.empresa('F2'); l uuid;
begin
  l := public.prestamo(e, '{"principal": 100000, "rate": 6, "periods": 5, "frequency": 1, "start_date": "2026-01-01", "costs": 1000}');
  assert (select net_amount from erp.loans where id = l) = 99000 and (select effective_rate_year from erp.loans where id = l) = 6.370531, 'TIE';
  assert (select string_agg(interest || '/' || reduction || '/' || balance, ' ' order by n) from erp.loan_schedule where loan_id = l)
       = '6306.83/17432.81/81567.19 5196.26/18543.38/63023.81 4014.95/19724.69/43299.12 2758.38/20981.26/22317.86 1421.77/22317.86/0.00', 'cuadro F2';
  assert (select sum(interest) from erp.loan_schedule where loan_id = l) = 19698.19, 'intereses totales = pagos − lo recibido';
  assert public.asiento(l, 'start') = '5720 D 99000.00 | 5200 H 17432.81 | 1700 H 81567.19', 'alta F2: ' || public.asiento(l, 'start');
  assert public.saldo(e, '6', '2026-01-01') = 0, 'la comisión no es gasto del primer día';
  perform erp.loan_payment(jsonb_build_object('loan_id', l));
  assert public.asiento(l, 'payment', 1) = '6623 D 6306.83 | 5200 D 17432.81 | 5720 H 23739.64', 'cuota F2';
  perform erp.loan_year_end(e, '2026-12-31');
  assert public.asiento(l, 'reclassification') = '1700 D 18543.38 | 5200 H 18543.38', 'reclasificación F2';
  raise notice 'OK  · F2: comisión dentro del TIE (6,3705 %%): 99.000 a coste amortizado y 6.306,83 de intereses el primer año';
end $$;

-- ---------- F3 · Arrendamiento financiero ----------
do $$
declare e uuid := public.empresa('F3'); l uuid; x jsonb; c jsonb;
begin
  insert into public.ctx values ('f3', e);
  l := public.prestamo(e, '{"kind": "leasing", "description": "Leasing máquina", "fair_value": 50000, "instalment": 13500,
                              "purchase_option": 2500, "periods": 4, "frequency": 1, "start_date": "2026-01-01",
                              "useful_life_months": 120}');
  assert (select effective_rate_year from erp.loans where id = l) = 4.938818, 'tipo implícito';
  assert (select string_agg(payment || '/' || interest || '/' || reduction || '/' || balance, ' ' order by n) from erp.loan_schedule where loan_id = l)
       = '13500.00/2469.41/11030.59/38969.41 13500.00/1924.63/11575.37/27394.04 13500.00/1352.94/12147.06/15246.98 16000.00/753.02/15246.98/0.00', 'cuadro F3';
  assert public.asiento(l, 'start') = '2130 D 50000.00 | 5240 H 11030.59 | 1740 H 38969.41', 'alta F3: ' || public.asiento(l, 'start');
  x := erp.loan_next_instalment(l);
  assert (x->>'reduction')::numeric = 11030.59 and (x->>'interest_expense')::numeric = 2469.41 and (x->>'short_part')::numeric = 11030.59
     and (x->>'purchase_option')::numeric = 0, 'propuesta de la primera cuota: ' || x::text;
  assert public.falla(format('select erp.loan_payment(%L)', jsonb_build_object('loan_id', l)), 'register the invoice'), 'el leasing va por factura';
  -- al cierre, aunque la cuota esté sin registrar (vence el mismo 31/12), pasa a corto lo de 2027
  x := erp.loan_year_end_preview(e, '2026-12-31')->'loans'->0;
  assert (x->>'reclassification')::numeric = 11575.37 and (x->>'overdue')::boolean, 'reclasificación del leasing: ' || x::text;
  assert public.falla(format('select erp.loan_year_end(%L, %L)', e, '2026-12-31'), 'is not posted'), 'sin la factura de la cuota, no se cierra';
  -- el menor del valor razonable y el valor actual al tipo del contrato (NRV 8.ª)
  c := erp.loan_calc('{"kind": "leasing", "fair_value": 52000, "instalment": 13500, "purchase_option": 2500, "periods": 4, "frequency": 1,
                       "start_date": "2026-01-01", "rate": 5}');
  assert (c->>'net_amount')::numeric = (c->>'present_value')::numeric and (c->>'present_value')::numeric < 52000
     and (c->>'effective_rate_year')::numeric between 4.9999 and 5.0001, 'valor actual menor: ' || (c - 'schedule')::text;
  c := erp.loan_calc('{"kind": "leasing", "fair_value": 48000, "instalment": 13500, "purchase_option": 2500, "periods": 4, "frequency": 1,
                       "start_date": "2026-01-01", "rate": 5}');
  assert (c->>'net_amount')::numeric = 48000 and (c->>'effective_rate_year')::numeric > 5, 'valor razonable menor';
  raise notice 'OK  · F3: leasing por el valor razonable (tipo implícito 4,9388 %%), alta 213 / 5240 + 1740 y propuesta de la cuota';
end $$;

-- ---------- Préstamo mensual y comprobaciones ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'f3'); l uuid; c jsonb;
begin
  -- 30.000 al 4,5 % en 36 cuotas mensuales: la cuota es la de cualquier simulador (892,41) y suma lo que debe
  c := erp.loan_calc('{"principal": 30000, "rate": 4.5, "periods": 36, "frequency": 12, "start_date": "2026-03-15"}');
  assert (c->>'instalment')::numeric = 892.41 and c->>'first_due_date' = '2026-04-14', 'cuota mensual: ' || (c - 'schedule')::text;
  assert (select sum((x->>'reduction')::numeric) from jsonb_array_elements(c->'schedule') x) = 30000, 'la deuda baja a cero';
  assert (select (x->>'due_date')::date from jsonb_array_elements(c->'schedule') x where (x->>'n')::int = 36) = '2029-03-14', 'vencimientos mensuales';
  assert (c->>'short_part')::numeric = (select sum((x->>'reduction')::numeric) from jsonb_array_elements(c->'schedule') x where (x->>'n')::int <= 12), 'a corto: 12 cuotas';
  -- otro prestamista: 171 / 521 / 6624 / 528
  l := public.prestamo(e, '{"principal": 10000, "rate": 3, "periods": 12, "frequency": 12, "start_date": "2026-06-10", "lender_type": "other"}');
  assert (select left(account_no, 4) from erp.gl_accounts where id = (select long_account_id from erp.loans where id = l)) = '1710'
     and (select left(account_no, 4) from erp.gl_accounts where id = (select interest_account_id from erp.loans where id = l)) = '6624'
     and (select left(account_no, 3) from erp.gl_accounts where id = (select accrued_account_id from erp.loans where id = l)) = '528', 'otras deudas';
  assert public.asiento(l, 'start') like '5720 D 10000.00 | 5210 H 10000.00', 'todo a corto: ' || public.asiento(l, 'start');
  assert public.falla($q$select erp.loan_calc('{"principal": 1000, "rate": 5, "periods": 12, "frequency": 3, "start_date": "2026-01-01"}')$q$, 'frequency');
  assert public.falla($q$select erp.loan_calc('{"principal": 1000, "rate": 5, "periods": 12, "frequency": 12, "start_date": "2026-01-01", "costs": 1000}')$q$, 'costs');
  assert public.falla($q$select erp.loan_calc('{"principal": 1000, "rate": 5, "periods": 12, "frequency": 12, "start_date": "2026-01-01", "first_due_date": "2026-03-01"}')$q$, 'first period');
  assert public.falla($q$select erp.loan_calc('{"kind": "leasing", "fair_value": 50000, "instalment": 1000, "periods": 4, "frequency": 1, "start_date": "2026-01-01"}')$q$, 'lower than');
  assert public.falla(format('select erp.loan_create(%L)', jsonb_build_object('company_id', e, 'description', 'x', 'principal', 1000, 'rate', 5,
                        'periods', 2, 'frequency', 1, 'start_date', '2026-01-01', 'long_account_no', '57200001')), 'not valid here'), 'cuenta del préstamo';
  raise notice 'OK  · préstamo mensual, otros prestamistas (171 / 521 / 6624 / 528) y datos no válidos';
end $$;

-- ---------- Deshacer, módulo propio e invariantes ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'f1b'); l uuid := (select id from erp.loans where company_id = e); x uuid; n int;
begin
  -- el último movimiento es la reclasificación de 2027; luego el devengo, luego la cuota
  assert (erp.loan_cancel(l)->>'kind') = 'reclassification', 'primero la reclasificación';
  assert (erp.loan_cancel(l)->>'kind') = 'accrual', 'luego el devengo';
  x := (select entry_id from erp.loan_events where loan_id = l and kind = 'payment' and status = 'posted');
  assert public.falla(format('select erp.reverse_entry(%L, %L, %L)', x, '2027-12-31', 'x'), 'loan or finance lease'), 'no se anula desde el diario';
  assert (select distinct source from erp.v_general_journal where entry_id = x) = 'financing', 'origen en el diario';
  assert (select count(distinct source) from erp.audit_lines(e, 2027) where entry_id = x and source = 'financing') = 1, 'origen en el auditor';
  perform erp.loan_cancel(l);   -- la cuota: vuelve la 527
  assert public.saldo(e, '527', '2027-12-31') = 2956.30, 'la cuota deshecha devuelve el devengo';
  perform erp.loan_cancel(l); perform erp.loan_cancel(l);   -- el devengo de 2026 y el alta
  assert (select status from erp.loans where id = l) = 'cancelled' and public.saldo(e, '5', '2027-12-31') = 0 and public.saldo(e, '1', '2027-12-31') = 0, 'anulado';
  assert public.falla(format('select erp.loan_cancel(%L)', l), 'already cancelled');
  -- un préstamo pagado entero vuelve a vivo al deshacer la última cuota
  e := (select c.e from public.ctx c where c.k = 'f1'); l := (select id from erp.loans where company_id = e);
  assert (select status from erp.loans where id = l) = 'active', 'F1 sigue vivo (faltan cuotas)';
  execute 'set constraints all immediate'; execute 'set constraints all deferred';
  select count(*) into n from erp.integrity_checks(e, 2027) where status = 'fail';
  assert n = 0, (select string_agg(code, ', ') from erp.integrity_checks(e, 2027) where status = 'fail');
  raise notice 'OK  · deshacer del último al primero; módulo propio en el diario y el auditor; invariantes en verde';
end $$;

reset role;
do $$
begin
  assert not erp.entry_is_manual((select entry_id from erp.loan_events order by seq limit 1)), 'no es un asiento manual';
end $$;
set role authenticated;

-- ---------- Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'f3'); l uuid;
begin
  assert (select count(*) from erp.loans) = 0 and (select count(*) from erp.loan_schedule) = 0 and (select count(*) from erp.loan_events) = 0, 'otro usuario no ve los préstamos';
  assert public.falla(format('select erp.loan_status(%L)', e), 'No permission');
  assert public.falla(format('select erp.loan_year_end(%L, %L)', e, '2026-12-31'), 'No permission');
  assert public.falla(format('select erp.loan_create(%L)', jsonb_build_object('company_id', e, 'description', 'x', 'principal', 1000, 'rate', 5,
                        'periods', 2, 'frequency', 1, 'start_date', '2026-01-01')), 'No permission');
  assert public.falla($q$select erp.loan_position(gen_random_uuid())$q$, 'permission denied'), 'las ayudas no son públicas';
  raise notice 'OK  · otro usuario no ve ni registra préstamos de una empresa ajena';
end $$;

\echo '✔ FASE 57 OK · Financiación: préstamos a coste amortizado y arrendamiento financiero (supuestos F1, F1b, F2 y F3)'
