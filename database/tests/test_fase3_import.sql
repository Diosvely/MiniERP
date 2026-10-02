-- =====================================================================
-- PRUEBAS FASE 3 · importación de subcuentas (migración 0008)
-- Ejecutar en una base limpia: stub + migraciones 0001-0008.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local');

create or replace function public.debe_fallar(p_sql text, p_texto text, p_prueba text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm ilike '%' || p_texto || '%' then
      raise notice 'OK  · %  →  %', p_prueba, sqlerrm;
      return;
    end if;
    raise exception 'FALLO · % · error inesperado: %', p_prueba, sqlerrm;
  end;
  raise exception 'FALLO · % · debía dar error y no lo dio', p_prueba;
end $$;
grant execute on function public.debe_fallar(text, text, text) to authenticated;
create table public.ctx (clave text primary key, valor uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare
  e uuid;
  filas jsonb := '[
    {"account_no": "57200001", "name": "Banco 1",            "name_en": "Bank 1"},
    {"account_no": "4300 0001", "name": "Cliente 1"},
    {"account_no": "47210007", "name": "IGIC soportado 7 %", "name_en": "Input IGIC 7%"},
    {"account_no": "5720001",  "name": "Corta"},
    {"account_no": "99900001", "name": "Sin PGC"},
    {"account_no": "57200001", "name": "Banco repetido"},
    {"account_no": "62900000", "name": ""},
    {"account_no": "12A00000", "name": "Con letra"}
  ]';
  r record;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Agrícola del Sur', 'retail', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');

  -- Vista previa: no guarda nada y clasifica cada fila
  for r in select * from erp.import_posting_accounts(e, filas, true) loop
    raise notice '   línea % · % · % · %', r.line_no, r.account_no, r.status, r.message;
  end loop;
  assert (select count(*) from erp.import_posting_accounts(e, filas, true) where status = 'insert') = 3;
  assert (select count(*) from erp.import_posting_accounts(e, filas, true) where status = 'error') = 5;
  assert (select account_no from erp.import_posting_accounts(e, filas, true) where line_no = 2) = '43000001',
         'debe quitar los espacios del número';
  assert (select count(*) from erp.gl_accounts where company_id = e and account_type = 'posting') = 0,
         'la vista previa no debe guardar nada';
  raise notice 'OK  · vista previa: 3 nuevas y 5 errores (longitud, sin PGC, repetida, sin nombre, letras)';

  -- Con errores, la importación real no guarda nada
  perform public.debe_fallar(format('select * from erp.import_posting_accounts(%L, %L::jsonb, false)', e, filas),
                             'Nothing was saved', 'todo o nada: con errores no importa ninguna');
  assert (select count(*) from erp.gl_accounts where company_id = e and account_type = 'posting') = 0;

  -- Solo las válidas
  perform erp.import_posting_accounts(e, (select jsonb_agg(x) from jsonb_array_elements(filas) with ordinality t(x, n) where n <= 3), false);
  assert (select count(*) from erp.gl_accounts where company_id = e and account_type = 'posting') = 3;
  assert (select template_account from erp.gl_accounts where company_id = e and account_no = '47210007') = '472';
  assert (select account_category from erp.gl_accounts where company_id = e and account_no = '43000001') = 'asset';
  raise notice 'OK  · importa las 3 válidas con su cuenta madre y masa patrimonial';

  -- Reimportar: actualiza nombres, no duplica
  perform erp.import_posting_accounts(e, '[{"account_no":"57200001","name":"Banco Santander","name_en":"Santander Bank"}]', false);
  assert (select name from erp.gl_accounts where company_id = e and account_no = '57200001') = 'Banco Santander';
  assert (select count(*) from erp.gl_accounts where company_id = e and account_type = 'posting') = 3;
  raise notice 'OK  · reimportar actualiza nombres sin duplicar';
end $$;

-- ---------- Un usuario de solo lectura no puede importar ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  assert (select count(*) from erp.import_posting_accounts(e, '[{"account_no":"57000000","name":"Caja"}]', true)) = 1,
         'la vista previa sí puede usarla';
  perform public.debe_fallar(format('select * from erp.import_posting_accounts(%L, %L::jsonb, false)', e,
                                    '[{"account_no":"57000000","name":"Caja"}]'),
                             'No permission', 'un viewer no puede importar');
end $$;

reset role;
drop table public.ctx;
drop function public.debe_fallar(text, text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 3 (IMPORTACIÓN) PASARON ==========='
