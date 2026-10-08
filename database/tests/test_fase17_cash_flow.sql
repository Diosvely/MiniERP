-- =====================================================================
-- PRUEBAS FASE 17 · Estado de flujos de efectivo, métodos directo e indirecto (migración 0022)
-- Datos inventados: una empresa con préstamo, inmovilizado (compra, amortización y venta con beneficio),
-- ventas y compras a crédito, nómina, intereses, impuesto sobre beneficios, dividendo y ampliación de capital.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
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
-- Sube filas a un lote: [fecha, asiento, tipo, cuenta, debe, haber]
create or replace function public.subir(b uuid, filas jsonb) returns void language sql as $$
  insert into erp.import_lines (batch_id, company_id, row_no, entry_date, entry_ref, entry_type, account_no, account_name,
                                debit, credit, description)
  select b, (select company_id from erp.import_batches where id = b), x.ord,
         (x.v->>0)::date, x.v->>1, x.v->>2, x.v->>3, '', (x.v->>4)::numeric, (x.v->>5)::numeric, 'Prueba ' || (x.v->>1)
  from jsonb_array_elements(filas) with ordinality as x(v, ord);
$$;
create or replace function public.importar(b uuid) returns void language plpgsql as $$
declare m record;
begin
  for m in select * from erp.import_prepare(b) loop
    perform erp.import_post_month(b, m.year, m.month);
  end loop;
  loop exit when (erp.import_finish(b)->>'done')::boolean; end loop;
end $$;
create or replace function public.linea(e uuid, y int, met text, c text) returns numeric language sql as $$
  select amount from erp.cash_flow_statement(e, y, met) where code = c;
$$;
grant execute on function public.falla(text, text), public.subir(uuid, jsonb), public.importar(uuid),
  public.linea(uuid, int, text, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; b uuid; k jsonb;
begin
  select company_id, batch_id into e, b from erp.import_start('Flujos Prueba SL', 8, 'mainland', 'services', 'template', 'efe.csv');
  perform public.subir(b, '[
    ["2025-01-01","1","opening","57200000",10000,0],      ["2025-01-01","1","opening","10000000",0,10000],
    ["2025-01-10","2","normal","57200000",20000,0],       ["2025-01-10","2","normal","17000000",0,20000],
    ["2025-02-01","3","normal","21300000",8000,0],        ["2025-02-01","3","normal","47200000",1680,0],
    ["2025-02-01","3","normal","52300000",0,9680],
    ["2025-02-28","4","normal","52300000",9680,0],        ["2025-02-28","4","normal","57200000",0,9680],
    ["2025-03-01","5","normal","43000000",6050,0],        ["2025-03-01","5","normal","70500000",0,5000],
    ["2025-03-01","5","normal","47700000",0,1050],
    ["2025-03-31","6","normal","57200000",6050,0],        ["2025-03-31","6","normal","43000000",0,6050],
    ["2025-04-01","7","normal","62900000",1000,0],        ["2025-04-01","7","normal","47200000",210,0],
    ["2025-04-01","7","normal","41000000",0,1210],
    ["2025-04-30","8","normal","41000000",1210,0],        ["2025-04-30","8","normal","57200000",0,1210],
    ["2025-05-31","9","normal","64000000",2000,0],        ["2025-05-31","9","normal","47600000",0,300],
    ["2025-05-31","9","normal","47510000",0,200],         ["2025-05-31","9","normal","57200000",0,1500],
    ["2025-06-30","10","normal","66230000",300,0],        ["2025-06-30","10","normal","57200000",0,300],
    ["2025-06-30","11","normal","17000000",2000,0],       ["2025-06-30","11","normal","57200000",0,2000],
    ["2025-09-30","12","normal","57200000",1500,0],       ["2025-09-30","12","normal","28130000",200,0],
    ["2025-09-30","12","normal","21300000",0,1000],       ["2025-09-30","12","normal","77100000",0,700],
    ["2025-12-31","13","normal","68100000",800,0],        ["2025-12-31","13","normal","28130000",0,800],
    ["2025-12-31","14","normal","63000000",400,0],        ["2025-12-31","14","normal","47520000",0,400],
    ["2026-01-20","1","normal","47520000",400,0],         ["2026-01-20","1","normal","57200000",0,400],
    ["2026-03-01","2","normal","12900000",1200,0],        ["2026-03-01","2","normal","11300000",0,700],
    ["2026-03-01","2","normal","52600000",0,500],
    ["2026-03-15","3","normal","52600000",500,0],         ["2026-03-15","3","normal","57200000",0,500],
    ["2026-06-01","4","normal","57200000",3000,0],        ["2026-06-01","4","normal","10000000",0,3000]
  ]');
  perform public.importar(b);
  assert (select count(*) from erp.year_closings where company_id = e and year = 2025) = 1, 'se cierra 2025';

  -- ---------- 2025 · método INDIRECTO ----------
  -- 1. Resultado antes de impuestos = 5.000 − 1.000 − 2.000 − 300 − 800 + 700 = 1.600 (sin la 630)
  assert public.linea(e, 2025, 'indirect', 'IA1') = 1600, 'resultado antes de impuestos';
  assert public.linea(e, 2025, 'indirect', 'IA2a') = 800, 'amortización (+)';
  assert public.linea(e, 2025, 'indirect', 'IA2e') = -700, 'beneficio por venta de inmovilizado (−)';
  assert public.linea(e, 2025, 'indirect', 'IA2h') = 300, 'gastos financieros (+)';
  assert public.linea(e, 2025, 'indirect', 'IA3b') = -1890, 'IVA soportado pendiente (deudores)';
  assert public.linea(e, 2025, 'indirect', 'IA3d') = 1550, 'IVA repercutido y retenciones pendientes (acreedores)';
  assert public.linea(e, 2025, 'indirect', 'IA4a') = -300, 'intereses pagados';
  assert public.linea(e, 2025, 'indirect', 'IA4d') = 0, 'impuesto devengado y no pagado: sin flujo';
  assert public.linea(e, 2025, 'indirect', 'IA') = 1360, 'A) explotación';
  assert public.linea(e, 2025, 'indirect', 'IB2') = -6500, 'inmovilizado material: compra 8.000 − venta 1.500';
  assert public.linea(e, 2025, 'indirect', 'IB5') = 0, 'proveedor de inmovilizado pagado en el año';
  assert public.linea(e, 2025, 'indirect', 'IC2') = 18000, 'préstamo 20.000 − devolución 2.000';
  assert public.linea(e, 2025, 'indirect', 'IE') = 12860, 'E) aumento neto';

  -- ---------- 2025 · método DIRECTO ----------
  assert public.linea(e, 2025, 'direct', 'DA1') = 6050, 'cobros de clientes';
  assert public.linea(e, 2025, 'direct', 'DA2') = -1210, 'pagos a proveedores';
  assert public.linea(e, 2025, 'direct', 'DA3') = -2000, 'nómina (bruto)';
  assert public.linea(e, 2025, 'direct', 'DA4') = 500, 'retenciones y SS que se quedan pendientes';
  assert public.linea(e, 2025, 'direct', 'DA5') = -300, 'intereses';
  assert public.linea(e, 2025, 'direct', 'DB1') = -9680, 'pago del inmovilizado (con su IVA)';
  assert public.linea(e, 2025, 'direct', 'DB2') = 1500, 'cobro por la venta: un solo cobro neto';
  assert public.linea(e, 2025, 'direct', 'DC2') = 20000, 'préstamo recibido';
  assert public.linea(e, 2025, 'direct', 'DC3') = -2000, 'préstamo devuelto';
  assert public.linea(e, 2025, 'direct', 'DE') = 12860, 'E) aumento neto';

  -- ---------- 2025 · cuadre del auditor ----------
  k := erp.cash_flow_check(e, 2025);
  assert (k->>'balanced')::boolean, 'directo = indirecto = variación de la 57';
  assert (k->>'cash_opening')::numeric = 10000 and (k->>'cash_closing')::numeric = 22860 and (k->>'cash_change')::numeric = 12860;
  assert (k->'indirect'->>'A')::numeric = 1360 and (k->'direct'->>'A')::numeric = 3040;
  assert (k->'indirect'->>'B')::numeric = -6500 and (k->'direct'->>'B')::numeric = -8180;
  -- La diferencia por actividades la explica UN asiento sin dinero: el IVA de la compra del inmovilizado
  assert (k->>'cross_count')::int = 1, 'un asiento cruzado';
  assert (k->'cross_entries'->0->'activities'->>'A')::numeric = -1680 and (k->'cross_entries'->0->'activities'->>'B')::numeric = 1680;
  assert (k->'cross_total'->>'A')::numeric = (k->'indirect'->>'A')::numeric - (k->'direct'->>'A')::numeric;

  -- ---------- 2026 · con la apertura que generó el cierre ----------
  k := erp.cash_flow_check(e, 2026);
  assert (k->>'balanced')::boolean and (k->>'cash_opening')::numeric = 22860 and (k->>'cash_change')::numeric = 2100, '2026 cuadra';
  assert public.linea(e, 2026, 'indirect', 'IA4d') = -400, 'pago del impuesto sobre beneficios';
  assert public.linea(e, 2026, 'direct', 'DA6') = -400;
  assert public.linea(e, 2026, 'direct', 'DC4') = -500, 'pago del dividendo';
  assert public.linea(e, 2026, 'direct', 'DC1') = 3000, 'ampliación de capital';
  assert public.linea(e, 2026, 'indirect', 'IC') = 2500 and public.linea(e, 2026, 'direct', 'DC') = 2500, 'financiación igual por los dos';
  assert (select amount_prev from erp.cash_flow_statement(e, 2026, 'indirect') where code = 'IE') = 12860, 'columna del año anterior';

  -- ---------- Drill-down ----------
  assert (select sum(amount) from erp.cf_line_accounts(e, 2025, 'indirect', 'IA2')) = 400, 'ajustes = 800 − 700 + 300';
  assert (select count(*) from erp.cf_line_accounts(e, 2025, 'indirect', 'IB2')) = 4, '213, 2813, 681 y 771';
  assert (select amount from erp.cf_line_accounts(e, 2025, 'direct', 'DB') where account_no = '52300000') = -9680;
  assert (select sum(amount) from erp.cf_line_accounts(e, 2025, 'direct', 'DE')) = 12860;

  -- ---------- Seguridad ----------
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
  assert public.falla(format('select erp.cash_flow_check(%L, 2025)', e), 'not allowed');
  assert public.falla(format($q$select * from erp.cash_flow_statement(%L, 2025, 'direct')$q$, e), 'not allowed');
  assert public.falla(format($q$select * from erp.cf_line_accounts(%L, 2025, 'direct', 'DA')$q$, e), 'not allowed');
  assert public.falla(format('select * from erp.cf_direct_detail(%L, 2025)', e), 'permission denied');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
  assert public.falla(format($q$select * from erp.cash_flow_statement(%L, 2025, 'otro')$q$, e), 'unknown cash flow method');
end $$;

\echo '=========== TODAS LAS PRUEBAS DE LA FASE 17 (FLUJOS DE EFECTIVO) PASARON ==========='
