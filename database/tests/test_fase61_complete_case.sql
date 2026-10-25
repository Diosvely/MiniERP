-- =====================================================================
-- PRUEBAS FASE 61 · Caso completo «Taller Atlántico SL» (migración 0066 · v0.45.0)
-- ---------------------------------------------------------------------
-- Supuesto de referencia: supuestos-v0.45.0.md, un ejercicio entero (2026) calculado a mano y validado.
--   erp.load_case lo carga con las funciones de cada módulo y erp.case_compare compara, al céntimo:
--   cuenta de resultados (resultado 64.276,28), balance (197.160; banco 129.860), ECPN (75.376,28 y 134.526,28),
--   EFE por los dos métodos (A 64.860 · B −40.000 · C 105.000), Impuesto sobre Sociedades (base 74.619,15, cuota
--   11.192,87) y los modelos 420 (938 · 308 · 658 · 308) y 111 (90 por trimestre).
-- Y una prueba por cada fallo que encontró en el EFE (regla A1):
--   1. la factura de un inmovilizado: el pago, en inversión (directo); sin pagar, no es inversión (indirecto)
--   2. la factura de la notaría a la 113: el pago resta de la financiación
--   3. los intereses devengados (527): con los intereses, no en financiación
--   4. el impuesto que se lleva a reservas (6300 / 113): con el impuesto, no en financiación
--   5. el deterioro de clientes (490): en los ajustes del resultado
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
create or replace function public.empresa(nombre text, territorio text default 'canary_islands') returns uuid language plpgsql as $$
declare e uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values (nombre, 'retail', territorio, auth.uid()) returning id into e;
  return e;
end $$;
-- Una empresa canaria lista para facturar (para las pruebas de cada fallo)
create or replace function public.lista(nombre text) returns uuid language plpgsql as $$
declare e uuid := public.empresa(nombre); c text;
begin
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  foreach c in array array['57200001:Banco', '60000001:Compras', '70000001:Ventas', '11300001:Reservas voluntarias',
                           '21300001:Maquinaria', '10000001:Capital social'] loop
    perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
  end loop;
  perform erp.case_entry(e, '2026-01-02', 'Capital', '[["57200001", 100000, 0], ["10000001", 0, 100000]]');
  return e;
end $$;
create or replace function public.efe(e uuid, met text, c text) returns numeric language sql as $$
  select amount from erp.cash_flow_statement(e, 2026, met) where code = c;
$$;
grant execute on function public.falla(text, text), public.empresa(text, text), public.lista(text), public.efe(uuid, text, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- El caso completo, cargado con cada módulo ----------
do $$
declare e uuid := public.empresa('Taller Atlántico SL'); x jsonb; r record; n int; s text;
begin
  insert into public.ctx values ('caso', e);
  x := erp.load_case(e, 'taller_atlantico');
  assert x->>'case' = 'taller_atlantico' and (select case_key from erp.companies where id = e) = 'taller_atlantico', 'caso cargado: ' || x::text;
  -- todas las cifras del documento, al céntimo
  select count(*), string_agg(kind || ' ' || code || ': ' || expected || ' ≠ ' || actual, ' · ') filter (where not ok)
    into n, s from erp.case_compare(e);
  assert n = (select count(*) from erp.case_expected where case_key = 'taller_atlantico') and n >= 90, 'cifras comparadas: ' || n;
  assert s is null, 'diferencias con el caso: ' || s;
  raise notice 'OK  · caso completo: % cifras de las cuentas anuales, el impuesto y los modelos, iguales al documento', n;
end $$;

do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'caso'); x jsonb; v jsonb;
begin
  -- las cifras clave, una a una
  assert (select amount from erp.financial_statement(e, 2026, 'pyg') where code = 'PC') = 75619.15
     and (select amount from erp.financial_statement(e, 2026, 'pyg') where code = 'PD') = 64276.28, 'resultado antes de impuestos y del ejercicio';
  assert (select amount from erp.financial_statement(e, 2026, 'balance') where code = 'ACT') = 197160
     and (select amount from erp.financial_statement(e, 2026, 'balance') where code = 'PNP') = 197160
     and (select amount from erp.financial_statement(e, 2026, 'balance') where code = 'AC.VI') = 129860, 'balance 197.160 y banco 129.860';
  x := erp.equity_statement(e, 2026);
  assert (x->'part_a'->>'total')::numeric = 75376.28 and (x->>'end')::numeric = 134526.28 and (x->>'ok')::boolean, 'ECPN: ' || x::text;
  -- EFE: directo = indirecto en cada actividad, y ningún asiento mezcla actividades
  x := erp.cash_flow_check(e, 2026);
  assert x->'indirect' = '{"A": 64860.00, "B": -40000.00, "C": 105000.00, "total": 129860.00}'::jsonb, 'indirecto: ' || (x->'indirect')::text;
  assert x->'direct' = x->'indirect' and (x->>'balanced')::boolean, 'directo: ' || (x->'direct')::text;
  assert (x->>'cross_count')::int = 0, 'asientos que mezclan actividades: ' || (x->'cross_entries')::text;
  -- Impuesto sobre Sociedades de entidad de nueva creación (15 %)
  select r.result into v from erp.corporate_tax_returns r where r.company_id = e and r.status = 'posted';
  assert v->>'regime' = 'new_entity' and (v->>'taxable_base')::numeric = 74619.15 and (v->>'quota')::numeric = 11192.87, 'IS: ' || v::text;
  -- el cierre está hecho y el asistente, completo salvo el auditor (la 113 deudora, que se revisa)
  assert (select status from erp.fiscal_years where company_id = e and year = 2026) = 'closed', 'ejercicio cerrado';
  assert (select string_agg(code, ' ' order by step) from erp.closing_checklist(e, 2026) where status in ('pending')) = 'audit_checks',
         'asistente: ' || (select string_agg(code || '=' || status, ' ' order by step) from erp.closing_checklist(e, 2026));
  assert (select string_agg(c.code, ' ') from erp.run_audit_checks(e, 2026) c where c.status in ('warning', 'error')) = 'anomalies', 'auditor: solo la 113 deudora';
  raise notice 'OK  · resultado 64.276,28 · balance 197.160 · ECPN 134.526,28 · EFE A 64.860, B −40.000, C 105.000 por los dos métodos · IS 11.192,87';
end $$;

-- ---------- Las condiciones para cargar un caso ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'caso'); p uuid := public.empresa('Península SL', 'mainland'); n uuid := public.empresa('Nueva SL');
begin
  assert public.falla(format('select erp.load_case(%L)', e), 'already has entries'), 'dos veces, no';
  assert public.falla(format('select erp.load_case(%L)', p), 'Canary Islands'), 'solo en Canarias (IGIC)';
  assert public.falla(format('select erp.load_case(%L, %L)', n, 'otro'), 'Unknown case'), 'caso desconocido';
  update erp.companies set legal_form = 'sa' where id = n;
  assert public.falla(format('select erp.load_case(%L)', n), 'limited company'), 'solo una SL';
  update erp.companies set legal_form = 'sl' where id = n;
  insert into public.ctx values ('nueva', n);
  assert (select count(*) from erp.cases where key = 'taller_atlantico') = 1, 'catálogo';
  raise notice 'OK  · cargar un caso: solo en una empresa nueva, canaria y SL, y un caso que exista';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare n uuid := (select c.e from public.ctx c where c.k = 'nueva');
begin
  assert public.falla(format('select erp.load_case(%L)', n), 'No permission'), 'otro usuario no carga el caso';
  assert public.falla(format('select * from erp.case_compare(%L, %L)', n, 'taller_atlantico'), 'Not allowed'), 'ni lo compara';
  raise notice 'OK  · otro usuario no puede cargar ni comparar el caso en una empresa ajena';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- 1. Facturas de inmovilizado en el EFE ----------
do $$
declare e uuid := public.lista('Inmovilizado SL'); p uuid; f uuid; x jsonb;
begin
  select partner_id into p from erp.create_partner(e, 'vendor', 'Maquinaria SL', 'B12345674');
  f := erp.case_invoice(e, 'purchase', p, '2026-04-01', 'M-1', 'Máquina', '[{"account_no": "21300001", "amount": 40000, "tax_code": "IGIC7"}]');
  -- sin pagar: no hay inversión (antes, el indirecto daba −40.000 en inversión y +40.000 en explotación)
  assert public.efe(e, 'indirect', 'IB') = 0 and public.efe(e, 'indirect', 'IA') = 0, 'sin pagar: IB ' || public.efe(e, 'indirect', 'IB');
  assert (erp.cash_flow_check(e, 2026)->>'cross_count')::int = 0, 'la factura ya no mezcla actividades';
  -- la mitad pagada: 20.000 de inversión; el IGIC de esa mitad (1.400), en explotación
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', 'payment', 'partner_id', p, 'payment_date', '2026-04-15',
    'cash_account_no', '57200001', 'applications', jsonb_build_array(jsonb_build_object('invoice_id', f, 'amount', 21400))));
  assert public.efe(e, 'direct', 'DB1') = -20000 and public.efe(e, 'direct', 'DA2') = -1400,
         'pago parcial (directo): DB1 ' || public.efe(e, 'direct', 'DB1') || ' · DA2 ' || public.efe(e, 'direct', 'DA2');
  assert public.efe(e, 'indirect', 'IB') = -20000 and public.efe(e, 'indirect', 'IA') = -1400, 'pago parcial (indirecto)';
  -- anular el pago lo deja como estaba
  perform erp.cancel_payment((select id from erp.payments where company_id = e), '2026-04-20');
  assert public.efe(e, 'direct', 'DB') = 0 and public.efe(e, 'direct', 'DA') = 0 and public.efe(e, 'indirect', 'IB') = 0, 'pago anulado';
  x := erp.cash_flow_check(e, 2026);
  assert x->'direct' = x->'indirect' and (x->>'balanced')::boolean, 'directo = indirecto: ' || x::text;
  raise notice 'OK  · factura de una máquina: sin pagar no es inversión; pagada la mitad, 20.000 en inversión y 1.400 de IGIC en explotación';
end $$;

-- ---------- 2. La notaría de la constitución (113) ----------
do $$
declare e uuid := public.lista('Notaría SL'); p uuid; f uuid;
begin
  select partner_id into p from erp.create_partner(e, 'creditor', 'Notaría SL', 'B12345674');
  f := erp.case_invoice(e, 'purchase', p, '2026-01-05', 'N-1', 'Notaría', '[{"account_no": "11300001", "amount": 1000, "tax_code": "IGIC7"}]');
  perform erp.case_payment(e, 'payment', p, '2026-01-05', f);
  assert public.efe(e, 'direct', 'DC1') = 99000 and public.efe(e, 'direct', 'DA2') = -70,
         'directo: DC1 ' || public.efe(e, 'direct', 'DC1') || ' · DA2 ' || public.efe(e, 'direct', 'DA2');
  assert public.efe(e, 'indirect', 'IC1') = 99000 and public.efe(e, 'indirect', 'IA') = -70, 'indirecto: IC1 ' || public.efe(e, 'indirect', 'IC1');
  raise notice 'OK  · notaría de la constitución: los 1.000 restan de la financiación (99.000) y el IGIC (70) va a explotación';
end $$;

-- ---------- 3. Intereses devengados y no pagados (527) ----------
do $$
declare e uuid := public.lista('Intereses SL');
begin
  perform erp.loan_create(jsonb_build_object('company_id', e, 'description', 'Préstamo', 'lender', 'Banco',
    'principal', 30000, 'rate', 5, 'periods', 3, 'frequency', 1, 'start_date', '2026-07-01'));
  perform erp.loan_year_end(e, '2026-12-31');
  assert public.efe(e, 'indirect', 'IC2') = 30000, 'financiación: solo el préstamo, ' || public.efe(e, 'indirect', 'IC2');
  assert public.efe(e, 'indirect', 'IA2h') = 740.85 and public.efe(e, 'indirect', 'IA4a') = 0 and public.efe(e, 'indirect', 'IA') = 0,
         'intereses sin pagar: IA4a ' || public.efe(e, 'indirect', 'IA4a');
  raise notice 'OK  · intereses devengados (740,85 a la 527): ajuste de gastos financieros sin pago; la financiación es solo el préstamo';
end $$;

-- ---------- 4. El impuesto llevado a reservas (6300 / 113) ----------
do $$
declare e uuid := public.lista('Impuesto SL');
begin
  perform erp.create_posting_account(e, '63000001', 'Impuesto corriente');
  perform erp.create_posting_account(e, '47520001', 'HP acreedora por IS');
  perform erp.case_entry(e, '2026-12-31', 'Impuesto', '[["63000001", 1000, 0], ["47520001", 0, 850], ["11300001", 0, 150]]');
  assert public.efe(e, 'indirect', 'IC1') = 100000 and public.efe(e, 'indirect', 'IA4d') = 0,
         'IC1 ' || public.efe(e, 'indirect', 'IC1') || ' · IA4d ' || public.efe(e, 'indirect', 'IA4d');
  assert (erp.cash_flow_check(e, 2026)->>'cross_count')::int = 0, 'el asiento del impuesto no mezcla actividades';
  raise notice 'OK  · impuesto que va a reservas (150): con el impuesto sobre beneficios, no como financiación';
end $$;

-- ---------- 5. Deterioro de clientes (490) ----------
do $$
declare e uuid := public.lista('Deterioro SL'); c uuid; f uuid;
begin
  select partner_id into c from erp.create_partner(e, 'customer', 'Cliente SL', 'B11111119');
  f := erp.case_invoice(e, 'sale', c, '2026-03-15', null, 'Venta', '[{"account_no": "70000001", "amount": 2000, "tax_code": "IGIC7"}]');
  perform erp.impair_receivable(jsonb_build_object('invoice_id', f, 'impair_date', '2026-12-31'));
  assert public.efe(e, 'indirect', 'IA2b') = 2140 and public.efe(e, 'indirect', 'IA3b') = -2140,
         'IA2b ' || public.efe(e, 'indirect', 'IA2b') || ' · IA3b ' || public.efe(e, 'indirect', 'IA3b');
  raise notice 'OK  · deterioro de un cliente (2.140): en los ajustes del resultado (A-2 b); los deudores, por su importe bruto';
end $$;

reset role;
