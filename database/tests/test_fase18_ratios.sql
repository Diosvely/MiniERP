-- =====================================================================
-- PRUEBAS FASE 18 · Ratios financieros (migración 0023)
-- Los mismos datos inventados de la fase 17. Cada ratio esperado se calcula a mano con el balance de 2025:
--   ACTIVO 31.150 = inmovilizado 6.400 (213 7.000 − 2813 600) + IVA soportado 1.890 + bancos 22.860
--   PN 11.200 (capital 10.000 + resultado 1.200) · PNC 18.000 (préstamo) · PC 1.950 (477, 476, 4751, 4752)
--   PyG: ventas 5.000 · resultado de explotación 1.900 · gastos financieros 300 · resultado 1.200 · amortización 800
--   Flujo de explotación (fase 17): 1.360
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
create or replace function public.ratio(e uuid, y int, c text) returns numeric language sql as $$
  select round(value, 4) from erp.financial_ratios(e, y) where code = c;
$$;
create or replace function public.valoracion(e uuid, y int, c text) returns text language sql as $$
  select status from erp.financial_ratios(e, y) where code = c;
$$;
grant execute on function public.falla(text, text), public.subir(uuid, jsonb), public.importar(uuid),
  public.ratio(uuid, int, text), public.valoracion(uuid, int, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; b uuid; k jsonb;
begin
  select company_id, batch_id into e, b from erp.import_start('Ratios Prueba SL', 8, 'mainland', 'services', 'template', 'ratios.csv');
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

  -- ---------- Liquidez ----------
  assert public.ratio(e, 2025, 'WC') = 22800, 'fondo de maniobra = 24.750 − 1.950';
  assert public.valoracion(e, 2025, 'WC') = 'ok';
  assert public.ratio(e, 2025, 'CR') = 12.6923, 'liquidez general = 24.750 / 1.950';
  assert public.valoracion(e, 2025, 'CR') = 'high', 'demasiado dinero parado';
  assert public.ratio(e, 2025, 'QR') = 12.6923, 'prueba ácida: sin existencias';
  assert public.ratio(e, 2025, 'CASH') = 11.7231, 'disponibilidad = 22.860 / 1.950';

  -- ---------- Solvencia y endeudamiento ----------
  assert public.ratio(e, 2025, 'DEBT') = 0.6404, 'endeudamiento = 19.950 / 31.150';
  assert public.valoracion(e, 2025, 'DEBT') = 'high';
  assert public.ratio(e, 2025, 'AUT') = 0.5614 and public.valoracion(e, 2025, 'AUT') = 'low', 'autonomía = 11.200 / 19.950';
  assert public.ratio(e, 2025, 'SOLV') = 1.5614 and public.valoracion(e, 2025, 'SOLV') = 'ok', 'garantía = 31.150 / 19.950';
  assert public.ratio(e, 2025, 'DQ') = 0.0977 and public.valoracion(e, 2025, 'DQ') = 'ok', 'calidad de la deuda = 1.950 / 19.950';
  assert public.ratio(e, 2025, 'FINC') = 0.06 and public.valoracion(e, 2025, 'FINC') = 'high', 'gastos financieros = 300 / 5.000';

  -- ---------- Rentabilidad ----------
  assert public.ratio(e, 2025, 'ROA') = 0.0610, 'ROA = 1.900 / 31.150';
  assert public.ratio(e, 2025, 'ROE') = 0.1071, 'ROE = 1.200 / 11.200';
  assert public.ratio(e, 2025, 'OPM') = 0.38 and public.ratio(e, 2025, 'NPM') = 0.24, 'márgenes';
  assert public.ratio(e, 2025, 'ATO') = 0.1605, 'rotación = 5.000 / 31.150';
  assert public.ratio(e, 2025, 'EBITDA') = 2700, 'EBITDA = 1.900 + 800';
  assert public.valoracion(e, 2025, 'ROA') is null, 'sin zona de referencia: sin valoración';

  -- ---------- Actividad ----------
  assert public.ratio(e, 2025, 'DSO') = 0, 'todo cobrado';
  assert public.ratio(e, 2025, 'DPO') is null and public.ratio(e, 2025, 'DIO') is null, 'sin aprovisionamientos no hay periodo de pago';

  -- ---------- Flujos de caja ----------
  assert public.ratio(e, 2025, 'CFO') = 1360, 'flujo de explotación del EFE';
  assert public.ratio(e, 2025, 'CFQ') = 1.1333, 'calidad del resultado = 1.360 / 1.200';
  assert public.ratio(e, 2025, 'CFD') = 0.6974, 'cobertura = 1.360 / 1.950';

  -- ---------- Año anterior, numerador y denominador ----------
  assert (select value_prev from erp.financial_ratios(e, 2025) where code = 'CR') is null, '2024 no existe';
  assert (select value_prev from erp.financial_ratios(e, 2026) where code = 'EBITDA') = 2700, 'columna del año anterior';
  assert (select num = 24750 and den = 1950 from erp.financial_ratios(e, 2025) where code = 'CR'), 'se ve de dónde sale';
  assert (select count(*) from erp.financial_ratios(e, 2025)) = (select count(*) from erp.ratio_defs), 'todos los ratios';

  -- ---------- Seguridad ----------
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
  assert public.falla(format('select * from erp.financial_ratios(%L, 2025)', e), 'not allowed');
  assert public.falla(format('select * from erp.ratio_parts(%L, 2025)', e), 'permission denied');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
end $$;

\echo '=========== TODAS LAS PRUEBAS DE LA FASE 18 (RATIOS FINANCIEROS) PASARON ==========='
