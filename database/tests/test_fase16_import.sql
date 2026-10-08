-- =====================================================================
-- PRUEBAS FASE 16 · Importación de diarios (migración 0021)
-- Datos inventados con la forma de un diario de Sage (con aperturas y cierres) y de Dynamics BC (sin ellos)
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
-- Sube filas a un lote: [fecha, asiento, tipo, cuenta, nombre, debe, haber]
create or replace function public.subir(b uuid, filas jsonb) returns void language sql as $$
  insert into erp.import_lines (batch_id, company_id, row_no, entry_date, entry_ref, entry_type, account_no, account_name,
                                debit, credit, description)
  select b, (select company_id from erp.import_batches where id = b),
         coalesce((select max(row_no) from erp.import_lines where batch_id = b), 0) + x.ord,
         (x.v->>0)::date, x.v->>1, x.v->>2, x.v->>3, x.v->>4, (x.v->>5)::numeric, (x.v->>6)::numeric, 'Prueba'
  from jsonb_array_elements(filas) with ordinality as x(v, ord);
$$;
-- Importa todo un lote: preparar, todos los meses y terminar
create or replace function public.importar(b uuid) returns jsonb language plpgsql as $$
declare m record; r jsonb; v_out jsonb := '[]';
begin
  for m in select * from erp.import_prepare(b) loop
    perform erp.import_post_month(b, m.year, m.month);
  end loop;
  loop
    r := erp.import_finish(b);
    exit when (r->>'done')::boolean;
    v_out := v_out || r;
  end loop;
  return v_out;
end $$;
create or replace function public.partida(e uuid, y int, st text, c text) returns numeric language sql as $$
  select amount from erp.financial_statement(e, y, st) where code = c;
$$;
grant execute on function public.falla(text, text), public.subir(uuid, jsonb), public.importar(uuid),
  public.partida(uuid, int, text, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- 1) Diario tipo Sage: dos años con apertura, regularización y cierre ----------
do $$
declare e uuid; b uuid; p jsonb; r jsonb;
begin
  select company_id, batch_id into e, b from erp.import_start('Sage Prueba SL', 8, 'mainland', 'services', 'sage', 'sage.xlsx');
  assert (select posting_account_digits from erp.companies where id = e) = 8;
  perform public.subir(b, '[
    ["2025-01-01","1","opening","57200000","BANCO****",10000,0],
    ["2025-01-01","1","opening","10000000","CAPITAL SOCIAL",0,10000],
    ["2025-03-10","7","normal","43000001","Nombre cuenta 43000001",1210,0],
    ["2025-03-10","7","normal","70000000","VENTAS",0,1000],
    ["2025-03-10","7","normal","47700000","IVA REPERCUTIDO",0,210],
    ["2025-04-02","8","normal","62900000","OTROS SERVICIOS",300,0],
    ["2025-04-02","8","normal","57200000","BANCO****",0,300],
    ["2025-05-05","9","normal","62900000","OTROS SERVICIOS",-50,0],
    ["2025-05-05","9","normal","57200000","BANCO****",0,-50],
    ["2025-05-06","10","normal","57200000","BANCO****",0,0],
    ["2025-12-31","40","closing_pl","70000000","VENTAS",1000,0],
    ["2025-12-31","40","closing_pl","62900000","OTROS SERVICIOS",0,250],
    ["2025-12-31","40","closing_pl","12900000","RESULTADO",0,750],
    ["2025-12-31","41","closing","10000000","CAPITAL SOCIAL",10000,0],
    ["2025-12-31","41","closing","12900000","RESULTADO",750,0],
    ["2025-12-31","41","closing","47700000","IVA REPERCUTIDO",210,0],
    ["2025-12-31","41","closing","57200000","BANCO****",0,9750],
    ["2025-12-31","41","closing","43000001","Nombre cuenta 43000001",0,1210],
    ["2026-01-01","1","opening","57200000","BANCO****",9750,0],
    ["2026-01-01","1","opening","43000001","Nombre cuenta 43000001",1210,0],
    ["2026-01-01","1","opening","10000000","CAPITAL SOCIAL",0,10000],
    ["2026-01-01","1","opening","12900000","RESULTADO",0,750],
    ["2026-01-01","1","opening","47700000","IVA REPERCUTIDO",0,210],
    ["2026-02-01","2","normal","57200000","BANCO****",1210,0],
    ["2026-02-01","2","normal","43000001","Nombre cuenta 43000001",0,1210]
  ]');

  p := erp.import_preview(b);
  assert (p->>'can_import')::boolean, p->>'errors';
  assert (p->>'negative_rows')::int = 2 and (p->>'zero_rows')::int = 1;
  assert (p->'accounts'->>'new')::int = 7;
  assert jsonb_array_length(p->'years') = 2;
  assert jsonb_array_length(p->'continuity'->0->'differences') = 0, 'la apertura de 2026 coincide con el cierre de 2025';
  raise notice 'OK  · vista previa: 2 años, 2 negativos, 1 fila a cero, 7 cuentas nuevas y apertura = cierre anterior';

  r := public.importar(b);
  assert r = '[{"done": false, "year": 2025, "result": 750.00, "closed_with": "file"}]'::jsonb, r::text;
  assert (select status from erp.fiscal_years where company_id = e and year = 2025) = 'closed';
  assert (select status from erp.import_batches where id = b) = 'posted';
  assert not exists (select 1 from erp.import_lines where batch_id = b), 'filas temporales borradas';
  raise notice 'OK  · importado: 2025 cerrado con los asientos del fichero, resultado 750';

  -- El negativo de Sage pasa al otro lado; el apunte a cero no se importa; los nombres ocultos toman el del PGC
  assert (select string_agg(g.account_no || ' ' || l.debit || '/' || l.credit, ' | ' order by l.line_no)
          from erp.journal_entries j join erp.journal_lines l on l.entry_id = j.id join erp.gl_accounts g on g.id = l.gl_account_id
          where j.company_id = e and j.source_ref = '9') = '62900000 0.00/50.00 | 57200000 50.00/0.00';
  assert not exists (select 1 from erp.journal_entries where company_id = e and source_ref = '10'), 'asiento solo con ceros';
  assert (select name from erp.gl_accounts where company_id = e and account_no = '57200000') like 'Bancos%57200000';
  assert (select name from erp.gl_accounts where company_id = e and account_no = '70000000') = 'VENTAS';
  raise notice 'OK  · negativo de Sage al lado contrario, ceros fuera y nombres ocultos con el del PGC';

  -- Informes iguales que con asientos registrados a mano
  assert public.partida(e, 2025, 'pyg', 'PD') = 750;
  assert public.partida(e, 2025, 'balance', 'ACT') = public.partida(e, 2025, 'balance', 'PNP');
  assert public.partida(e, 2026, 'balance', 'ACT') = 10960, 'banco 9.750 + cliente 1.210';
  assert (select amount_prev from erp.financial_statement(e, 2026, 'balance') where code = 'ACT') = 10960;
  assert (select count(*) from erp.v_general_journal where company_id = e and fiscal_year = 2025 and source = 'closing') > 0;
  raise notice 'OK  · balance y PyG de los dos años, columna del año anterior y asientos del cierre reconocidos';

  -- Una empresa importada no admite un segundo lote
  assert public.falla(format($q$select erp.import_prepare(%L)$q$, b), 'already posted');
end $$;

-- ---------- 2) Diario tipo Dynamics BC: sin aperturas ni cierres, regularización propia y céntimos ----------
do $$
declare e uuid; b uuid; p jsonb; r jsonb;
begin
  select company_id, batch_id into e, b from erp.import_start('BC Prueba SL', 9, 'mainland', 'services', 'dynamics', 'gl.csv');
  perform public.subir(b, '[
    ["2024-01-01","100","normal","572000001","",5000,0],
    ["2024-01-01","100","normal","100000000","",0,5000],
    ["2024-06-30","101","normal","570000000","",0,600],
    ["2024-06-30","101","normal","622000000","",600.01,0],
    ["2024-12-31","102","normal","430000000","",800,0],
    ["2024-12-31","102","normal","700000000","",0,800],
    ["2024-12-31","900","closing_pl","700000000","",800,0],
    ["2024-12-31","900","closing_pl","622000000","",0,600.01],
    ["2024-12-31","900","closing_pl","129000000","",0,199.99],
    ["2025-03-01","103","normal","572000001","",800,0],
    ["2025-03-01","103","normal","430000000","",0,800]
  ]');
  p := erp.import_preview(b);
  assert (p->>'rounded_entries')::int = 1 and (p->>'unbalanced_entries')::int = 0, 'un asiento descuadrado por un céntimo';
  r := public.importar(b);
  assert r->0->>'closed_with' = 'assistant', 'sin aperturas en el fichero: cierra nuestro asistente';
  assert (r->0->>'result')::numeric = 200.00, 'incluye el céntimo de redondeo (778)';
  assert exists (select 1 from erp.gl_accounts where company_id = e and account_no = '778000009'), 'cuenta de redondeo (el Debe superaba al Haber en 0,01)';
  assert exists (select 1 from erp.journal_entries j join erp.fiscal_years f on f.id = j.fiscal_year_id
                 where j.company_id = e and f.year = 2025 and j.entry_type = 'opening'), 'apertura de 2025 generada';
  assert public.partida(e, 2024, 'pyg', 'PD') = 200.00, 'la regularización de BC no cuenta en la PyG';
  assert public.partida(e, 2025, 'balance', 'ACT') = public.partida(e, 2024, 'balance', 'ACT');
  -- La caja acreedora no impide importar: queda señalada como saldo anómalo
  assert exists (select 1 from erp.balance_anomalies(e, 2024, null, '2024-12-30') where account_no = '570000000');
  raise notice 'OK  · tipo BC: redondeo a 778, regularización fuera de la PyG, cierre y apertura generados, caja acreedora señalada';
end $$;

-- ---------- 3) Errores y permisos ----------
do $$
declare e uuid; b uuid; p jsonb;
begin
  select company_id, batch_id into e, b from erp.import_start('Errores SL', 8, 'mainland', 'services', 'template', 'x.csv');
  perform public.subir(b, '[
    ["2025-02-01","1","normal","5720000","",100,0],
    ["2025-02-01","1","normal","99000000","",0,100],
    ["2025-02-02","2","normal","57200000","",100,0],
    ["2025-02-02","2","normal","70000000","",0,90]
  ]');
  p := erp.import_preview(b);
  assert not (p->>'can_import')::boolean;
  assert p->'errors' @> '[{"code":"wrong_length"},{"code":"no_pgc"},{"code":"unbalanced"}]', p->>'errors';
  assert public.falla(format('select erp.import_prepare(%L)', b), 'cannot be imported');
  raise notice 'OK  · errores: cuenta de otra longitud, cuenta sin PGC y asiento descuadrado en 10 € → no se importa';

  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
  assert public.falla(format('select erp.import_preview(%L)', b), 'no permission');
  assert public.falla(format($q$select public.subir(%L, '[["2025-01-01","1","normal","57200000","",1,0]]')$q$, b), 'row-level security');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
  raise notice 'OK  · otro usuario no ve ni sube filas al lote';
end $$;

reset role;
drop function public.falla(text, text);
drop function public.subir(uuid, jsonb);
drop function public.importar(uuid);
drop function public.partida(uuid, int, text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 16 (IMPORTACIÓN DE DIARIOS) PASARON ==========='
