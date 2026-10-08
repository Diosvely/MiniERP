-- =====================================================================
-- PRUEBAS FASE 19 · Contexto del Analista IA (migración 0024)
-- Los mismos datos inventados de las fases 17 y 18. Se comprueba qué recibe la IA y quién puede pedirlo.
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
  select company_id, batch_id into e, b from erp.import_start('IA Prueba SL', 8, 'mainland', 'services', 'template', 'ia.csv');
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
    ["2026-06-01","4","normal","57200000",3000,0],        ["2026-06-01","4","normal","10000000",0,3000],
    ["2026-07-01","5","normal","62900000",1000,0],        ["2026-07-01","5","normal","57200000",0,1000]
  ]');
  perform public.importar(b);

  -- ---------- Quién puede usarlo ----------
  assert erp.can_use_ai(), 'el propietario de la aplicación puede usar la IA';

  -- ---------- Qué recibe la IA ----------
  k := erp.ai_context(e, 2025);
  assert k->>'language' = 'es' and (k->>'year')::int = 2025 and k->>'currency' = 'EUR';
  assert k->'company'->>'industry' = 'services' and k->'company'->>'tax' = 'VAT/IVA' and k->'company'->>'imported_from' = 'template';
  assert not (k->'company' ? 'name') and position('IA Prueba' in k::text) = 0, 'nunca el nombre de la empresa';
  assert position('Prueba 1' in k::text) = 0, 'nunca los conceptos de los asientos';
  assert jsonb_array_length(k->'ratios') = (select count(*) from erp.ratio_defs), 'todos los ratios';
  assert exists (select 1 from jsonb_array_elements(k->'ratios') r
                 where r->>'ratio' = 'Liquidez general' and (r->>'value')::numeric = 12.69 and r->>'status' = 'high'),
         'el ratio redondeado como en pantalla, con su valoración';
  assert exists (select 1 from jsonb_array_elements(k->'ratios') r
                 where r->>'ratio' = 'Rentabilidad financiera (ROE)' and (r->>'value')::numeric = 10.7 and r->>'unit' = 'percent'),
         'los porcentajes ya en %';
  assert exists (select 1 from jsonb_array_elements(k->'ratios') r
                 where r->>'ratio' = 'Endeudamiento' and (r->>'lower_is_safer')::boolean), 'bajo endeudamiento = menos riesgo';
  assert exists (select 1 from jsonb_array_elements(k->'balance_sheet') x
                 where x->>'line' = 'TOTAL ACTIVO' and (x->>'amount')::numeric = 31150), 'balance';
  assert exists (select 1 from jsonb_array_elements(k->'income_statement') x
                 where (x->>'amount')::numeric = 1200 and x->>'line' like 'D)%'), 'resultado del ejercicio';
  assert (k->'cash_flow_check'->>'balanced')::boolean and (k->'cash_flow_check'->>'cash_change')::numeric = 12860, 'cuadre del EFE';
  assert not (k->'cash_flow_check' ? 'cross_entries'), 'sin el detalle de asientos';
  assert jsonb_array_length(k->'cash_flow_indirect') > 0;
  assert not exists (select 1 from jsonb_array_elements(k->'balance_sheet') x where (x->>'amount')::numeric = 0
                     and coalesce((x->>'previous')::numeric, 0) = 0), 'sin partidas vacías';

  -- ---------- Con pérdidas, la calidad del resultado no se calcula (antes daba un positivo engañoso) ----------
  assert (select value from erp.financial_ratios(e, 2026) where code = 'CFO') = -1400, 'caja de explotación negativa';
  assert (select value from erp.financial_ratios(e, 2026) where code = 'CFQ') is null, 'con pérdidas: sin valor';
  assert (select status from erp.financial_ratios(e, 2026) where code = 'CFQ') is null, 'y sin valoración';
  assert not exists (select 1 from jsonb_array_elements(erp.ai_context(e, 2026)->'ratios') r
                     where r->>'ratio' = 'Calidad del resultado' and r ? 'value'), 'la IA no recibe valor';

  -- ---------- En inglés ----------
  k := erp.ai_context(e, 2025, 'en');
  assert k->>'language' = 'en' and exists (select 1 from jsonb_array_elements(k->'ratios') r where r->>'ratio' = 'Current ratio');

  -- ---------- Errores ----------
  assert public.falla(format('select erp.ai_context(%L, 2030)', e), 'does not exist');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
  assert not erp.can_use_ai(), 'otro usuario no';
  assert public.falla(format('select erp.ai_context(%L, 2025)', e), 'only available to the application owner');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
end $$;

\echo '=========== TODAS LAS PRUEBAS DE LA FASE 19 (CONTEXTO DEL ANALISTA IA) PASARON ==========='
