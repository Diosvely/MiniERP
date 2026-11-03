-- =====================================================================
-- PRUEBAS FASE 79 · Matriz de permisos: «lo tuyo, todo; lo de otro, nada» (v0.58.0, pasos 283 y 284)
-- ---------------------------------------------------------------------
-- Plan validado por Diosvely (plan-permisos-y-casos.md, 03-11-2026), tras un comentario en LinkedIn: «que cada rol vea
-- y modifique solo lo previsto, también al importar datos y consultar la IA».
--
-- Paso 283: se midió la matriz de hoy (docs/permisos-medicion.md en el Project). Paso 284: con el criterio de Diosvely
-- («el ERP es para aprender el ciclo completo: cada persona es dueña absoluta de su información y nadie entra en la de
-- otro»), la matriz pasa a ser lo que esta prueba exige (public.esperado):
--   · quien administra su empresa (o su temporal) lo hace todo en ella, también usar la IA;
--   · lo de otro, nada: ni un registrado, ni un invitado, ni el propietario de la app en la empresa de otro usuario;
--   · las demos, solo para ver;
--   · los roles para compartir (los da el propietario en sus empresas): el lector ve; el contable ve y contabiliza, pero
--     cierra y configura quien administra; el titular de los datos, además, usa la IA;
--   · dar y quitar accesos, y limpiar las temporales caducadas: el propietario de la app (los accesos, en sus empresas).
-- Cada actor prueba cada acción sobre empresas ficticias (el caso «Taller Atlántico SL»). Cada intento se deshace al
-- terminar (se lanza una excepción que lo revierte), así que las acciones no se estorban entre sí.
-- La fase 80 (la guardiana) prueba lo de otro con TODAS las funciones.
--
-- Resultados:
--   sí        → lo hace (o lo ve: la consulta devuelve filas)
--   no        → lo impide un permiso (RLS, «Not allowed», «permission denied», «Only…»)
--   no·vacío  → no da error, pero no ve nada (la seguridad fila a fila filtra)
--   sí·regla  → pasa el permiso y la para una regla contable (se apunta el mensaje: hay que mirarlo)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

-- ---------- Actores ----------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'propietario@test.local'),
  ('00000000-0000-0000-0000-0000000000a2', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000a3', 'contable@test.local'),
  ('00000000-0000-0000-0000-0000000000a4', 'lector@test.local'),
  ('00000000-0000-0000-0000-0000000000a5', 'titular@test.local'),
  ('00000000-0000-0000-0000-0000000000a6', 'extrano@test.local'),
  ('00000000-0000-0000-0000-0000000000a7', 'temporal@test.local'),
  ('00000000-0000-0000-0000-0000000000a8', null),                       -- invitado (sesión anónima de Supabase)
  ('00000000-0000-0000-0000-0000000000a9', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null)
on conflict (user_id) do update set app_role = 'owner';
insert into erp.app_profiles (user_id, app_role, max_companies)
select id, 'member', 3 from auth.users
where id not in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a7')   -- a7: registrado sin perfil
on conflict (user_id) do nothing;

create table public.ctx (k text primary key, e uuid);
create table public.matriz (orden serial, actor text, empresa text, grupo text, accion text, resultado text, detalle text);
grant all on public.ctx, public.matriz to anon, authenticated, powerbi_reader;
grant usage, select on sequence public.matriz_orden_seq to anon, authenticated, powerbi_reader;
grant usage on schema public to powerbi_reader;

-- Ponerse en la piel de un actor: rol de PostgreSQL y token (sub e is_anonymous), como hace Supabase
create or replace procedure public.ser(p_role text, p_sub text, p_anon boolean default false) language plpgsql as $$
begin
  execute format('set role %I', p_role);
  perform set_config('request.jwt.claim.sub', coalesce(p_sub, ''), false);
  perform set_config('request.jwt.claims',
    case when p_sub is null then '' else jsonb_build_object('sub', p_sub, 'is_anonymous', p_anon)::text end, false);
end $$;

-- Un intento: se ejecuta, se apunta el resultado y se deshace (la excepción revierte todo lo que hizo)
create or replace function public.medir(p_actor text, p_empresa text, p_grupo text, p_accion text, p_sql text, p_lectura boolean)
returns void language plpgsql as $$
declare n bigint; r text; d text;
begin
  begin
    if p_lectura then
      execute p_sql into n;
      raise exception 'MEDIR:%', case when coalesce(n, 0) > 0 then 'sí' else 'no·vacío' end;
    else
      execute p_sql;
      raise exception 'MEDIR:sí';
    end if;
  exception when others then
    if sqlerrm like 'MEDIR:%' then
      r := substr(sqlerrm, 7); d := null;
    -- mensajes de permiso del ERP: «Not allowed», «No permission…», «Only the company admin…», «not found (or no
    -- permission)», «Guest visitors can only…», «The AI is not enabled for you…», y los de PostgreSQL (RLS, privilegios)
    elsif sqlerrm ~* '(not allowed|permission denied|row-level security|no permission|only the (company admin|application owner|owner)|only .* can |guest visitors|not enabled for you|access denied|not a member)' then
      r := 'no'; d := left(sqlerrm, 160);
    else
      r := 'sí·regla'; d := left(sqlerrm, 160);
    end if;
  end;
  insert into public.matriz (actor, empresa, grupo, accion, resultado, detalle) values (p_actor, p_empresa, p_grupo, p_accion, r, d);
end $$;
grant execute on function public.medir(text, text, text, text, text, boolean) to anon, authenticated, powerbi_reader;

-- ---------- Empresas ficticias ----------
-- X: la del propietario, con un administrador, un contable, un lector y un titular de los datos
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000a1');
do $$ begin
  insert into public.ctx values ('X', (erp.create_case_company('taller_atlantico', 'full')->>'company_id')::uuid);
  insert into public.ctx values ('D', (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid);
  perform erp.grant_company_access((select e from public.ctx where k = 'X'), 'admin@test.local', 'admin');
  perform erp.grant_company_access((select e from public.ctx where k = 'X'), 'contable@test.local', 'accountant');
  perform erp.grant_company_access((select e from public.ctx where k = 'X'), 'lector@test.local', 'viewer');
  perform erp.grant_company_access((select e from public.ctx where k = 'X'), 'titular@test.local', 'accountant', true);
end $$;
-- Z: la de otro usuario (el administrador de X tiene la suya), donde el propietario no tiene ningún rol
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000a2');
do $$ begin
  insert into public.ctx values ('Z', (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid);
end $$;
-- T: una empresa temporal (importación) de un registrado, con su lote de importación
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000a7');
do $$ declare r record; begin
  select * into r from erp.import_start('Importada', 8, 'mainland', 'services', 'sage', 'diario.csv');
  insert into public.ctx values ('T', r.company_id), ('LOTE', r.batch_id);
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset
-- D pasa a ser una empresa demo (la ven los invitados)
update erp.companies set is_demo = true where id = (select e from public.ctx where k = 'D');

-- En X, Z y D: un borrador cuadrado y un asiento contabilizado, para contabilizar y anular (los crea quien administra
-- cada empresa; en X, de 2027, porque 2026 está cerrado)
create or replace procedure public.fixtures(p_key text, p_year int) language plpgsql as $$
declare c uuid := (select e from public.ctx where k = p_key); fy uuid; a uuid;
begin
  fy := (select id from erp.fiscal_years where company_id = c and year = p_year);
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, fy, make_date(p_year, 12, 15), 'Borrador') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '62300001'), 100);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 100);
  insert into public.ctx values ('BORRADOR_' || p_key, a);
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, fy, make_date(p_year, 12, 16), 'Contabilizado') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '62300001'), 50);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 50);
  perform erp.post_entry(a);
  insert into public.ctx values ('CONTABILIZADO_' || p_key, a);
end $$;
grant execute on procedure public.fixtures(text, int) to authenticated;
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000a1');
call public.fixtures('X', 2027);
call public.fixtures('D', 2026);
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000a2');
call public.fixtures('Z', 2026);
reset role;

-- ---------- Las acciones (sobre una empresa: %1$s = su id) ----------
create table public.acciones (orden int, grupo text, accion text, sql text, lectura boolean);
insert into public.acciones values
 (10, 'Ver',        'ver la empresa',                     'select count(*) from erp.companies where id = %1$L', true),
 (11, 'Ver',        'diario',                             'select count(*) from erp.v_general_journal where company_id = %1$L', true),
 (12, 'Ver',        'facturas',                           'select count(*) from erp.v_invoices where company_id = %1$L', true),
 (13, 'Ver',        'balance',                            'select count(*) from erp.financial_statement(%1$L, 2026, ''balance'') where amount <> 0', true),
 (14, 'Ver',        'tablero',                            'select count(*) from jsonb_array_elements(erp.dashboard_data(%1$L, ''resumen'', 2026) -> ''widgets'')', true),
 (15, 'Ver',        'comprobaciones',                     'select count(*) from erp.run_audit_checks(%1$L, 2027, ''2027-01-31'')', true),
 (16, 'Ver',        'quién tiene acceso',                 'select count(*) from erp.company_access(%1$L)', true),
 (20, 'Escribir',   'crear un borrador',                  'insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (%1$L, (select id from erp.fiscal_years where company_id = %1$L and year = 2027), ''2027-01-20'', ''x'')', false),
 (21, 'Escribir',   'contabilizar un borrador',           'select erp.post_entry((select e from public.ctx where k = ''BORRADOR_%2$s''))', false),
 (22, 'Escribir',   'anular un asiento',                  'select erp.reverse_entry((select e from public.ctx where k = ''CONTABILIZADO_%2$s''))', false),
 (23, 'Escribir',   'crear una subcuenta',                'select erp.create_posting_account(%1$L, ''62900099'', ''Prueba'')', false),
 (24, 'Escribir',   'registrar una factura',              'select erp.post_invoice(jsonb_build_object(''company_id'', %1$L::uuid, ''invoice_type'', ''purchase'', ''document_kind'', ''invoice'', ''partner_id'', (select id from erp.business_partners where company_id = %1$L and name = ''Asesoría Martín''), ''external_document_no'', ''M-1'', ''invoice_date'', ''2027-01-22'', ''description'', ''Prueba'', ''lines'', ''[{"account_no":"62300001","amount":100,"tax_code":"IGIC7"}]''::jsonb))', false),
 (25, 'Escribir',   'liquidar el 1T',                     'select erp.post_tax_settlement(%1$L, ''IGIC'', 2027, 1)', false),
 (30, 'Cerrar',     'cerrar el ejercicio',                'select erp.close_fiscal_year(%1$L, 2027, true)', false),
 (31, 'Cerrar',     'reabrir el mes',                     'select erp.reopen_month(%1$L)', false),
 (40, 'Configurar', 'modo de control',                    'select erp.set_control_mode(%1$L, ''guided'')', false),
 (41, 'Configurar', 'forma jurídica',                     'select erp.set_legal_form(%1$L, ''sa'')', false),
 (50, 'Accesos',    'dar acceso a otro',                  'select erp.grant_company_access(%1$L, ''otro@test.local'', ''viewer'')', false),
 (51, 'Accesos',    'quitar un acceso',                   'select erp.revoke_company_access(%1$L, ''00000000-0000-0000-0000-0000000000a4'')', false),
 (52, 'Accesos',    'borrar la empresa',                  'select erp.delete_company(%1$L)', false),
 (60, 'IA',         'Analista: datos para la IA',         'select count(*) from (select erp.ai_context(%1$L, 2026) as v) x where v is not null and v::text not in (''{}'', ''null'', ''[]'')', true),
 (61, 'IA',         'Analista: gastar una consulta',      'select erp.ai_consume(%1$L)', false),
 (62, 'IA',         'Tutor: datos para la IA',            'select count(*) from (select erp.entry_tutor_context(%1$L) as v) x where v is not null and v::text not in (''{}'', ''null'', ''[]'')', true);

-- ---------- Medir ----------
--   actor, rol de PostgreSQL, usuario, anónimo, empresas que prueba
create table public.actores (orden int, actor text, rol text, sub text, anon boolean, empresas text[]);
insert into public.actores values
 (1, 'sin sesión',               'anon',          null,                                    false, array['X', 'D']),
 (2, 'invitado de la demo',      'authenticated', '00000000-0000-0000-0000-0000000000a8',  true,  array['D', 'X']),
 (3, 'registrado sin acceso',    'authenticated', '00000000-0000-0000-0000-0000000000a6',  false, array['X', 'D', 'T']),
 (4, 'solo lectura',             'authenticated', '00000000-0000-0000-0000-0000000000a4',  false, array['X']),
 (5, 'contable',                 'authenticated', '00000000-0000-0000-0000-0000000000a3',  false, array['X']),
 (6, 'titular de los datos',     'authenticated', '00000000-0000-0000-0000-0000000000a5',  false, array['X']),
 (7, 'administrador',            'authenticated', '00000000-0000-0000-0000-0000000000a2',  false, array['X']),
 (8, 'propietario (su empresa)', 'authenticated', '00000000-0000-0000-0000-0000000000a1',  false, array['X']),
 (9, 'propietario (empresa ajena)', 'authenticated', '00000000-0000-0000-0000-0000000000a1', false, array['Z']),
 (10, 'dueño de la temporal',    'authenticated', '00000000-0000-0000-0000-0000000000a7',  false, array['T']);

do $$
declare a record; ac record; emp text; c uuid;
begin
  for a in select * from public.actores order by orden loop
    foreach emp in array a.empresas loop
      c := (select e from public.ctx where k = emp);
      for ac in select * from public.acciones order by orden loop
        call public.ser(a.rol, a.sub, a.anon);
        perform public.medir(a.actor, emp, ac.grupo, ac.accion, format(ac.sql, c, emp), ac.lectura);
        reset role;
      end loop;
    end loop;
  end loop;
end $$;

-- Importar: empezar una importación propia (crea una empresa temporal) y preparar la de la temporal T
do $$
declare a record;
begin
  for a in select * from public.actores where orden in (1, 2, 3, 4, 8, 10) order by orden loop
    call public.ser(a.rol, a.sub, a.anon);
    perform public.medir(a.actor, '—', 'Importar', 'empezar una importación propia',
      'select erp.import_start(''Mía'', 8, ''mainland'', ''services'', ''sage'')', false);
    perform public.medir(a.actor, 'T', 'Importar', 'preparar la importación de la temporal T',
      format('select erp.import_prepare(%L)', (select e from public.ctx where k = 'LOTE')), false);
    perform public.medir(a.actor, '—', 'Casos', 'cargar el caso Taller Atlántico',
      'select erp.create_case_company(''taller_atlantico'', ''until_closing'')', false);
    perform public.medir(a.actor, '—', 'Mantenimiento', 'limpiar empresas temporales caducadas',
      'select erp.temp_cleanup(0)', false);
    reset role;
  end loop;
end $$;

-- Power BI: solo el esquema bi
do $$ begin
  call public.ser('powerbi_reader', null);
  perform public.medir('Power BI', 'X', 'Ver', 'esquema erp (empresas)', 'select count(*) from erp.companies', true);
  perform public.medir('Power BI', '—', 'Ver', 'esquema bi (empresas demo)', 'select count(*) from bi.dim_empresa', true);
  reset role;
end $$;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

-- ---------- La matriz, para el documento ----------
\pset format unaligned
\pset fieldsep '|'
\pset footer off
-- ---------- Lo que se exige ----------
--   sí → lo hace (vale «sí·regla»: el permiso pasa y la para una regla contable)
--   no → no lo hace o no ve nada («no» o «no·vacío»)
--   —  → no aplica (en la temporal recién empezada aún no hay asientos que contabilizar o anular)
create or replace function public.esperado(p_actor text, p_empresa text, p_grupo text, p_accion text)
returns text language sql immutable as $$
  select case
    when p_actor = 'Power BI' then case when p_accion like 'esquema bi%' then 'sí' else 'no' end
    -- accesos y limpieza: el propietario de la app (los accesos, solo en sus empresas)
    when p_grupo = 'Accesos' and p_accion <> 'borrar la empresa' or p_accion = 'quién tiene acceso' then
      case when (p_actor, p_empresa) = ('propietario (su empresa)', 'X') then 'sí' else 'no' end
    when p_grupo = 'Mantenimiento' then case when p_actor like 'propietario%' then 'sí' else 'no' end
    -- empezar lo propio: cualquiera con cuenta (un invitado o sin sesión, no)
    when p_grupo in ('Importar', 'Casos') and p_empresa = '—' then
      case when p_actor in ('sin sesión', 'invitado de la demo') then 'no' else 'sí' end
    -- lo tuyo, todo
    when (p_actor, p_empresa) in (('administrador', 'X'), ('propietario (su empresa)', 'X'), ('dueño de la temporal', 'T')) then
      case when p_empresa = 'T' and p_accion in ('contabilizar un borrador', 'anular un asiento', 'diario', 'facturas', 'balance')
           then '—' else 'sí' end
    -- las demos, solo para ver
    when p_empresa = 'D' and p_actor in ('invitado de la demo', 'registrado sin acceso') then
      case when p_grupo = 'Ver' then 'sí' else 'no' end
    -- los roles para compartir
    when p_empresa = 'X' and p_actor = 'solo lectura' then case when p_grupo = 'Ver' then 'sí' else 'no' end
    when p_empresa = 'X' and p_actor in ('contable', 'titular de los datos') then
      case when p_grupo in ('Ver', 'Escribir') then 'sí'
           when p_grupo = 'IA' and p_actor = 'titular de los datos' then 'sí'
           else 'no' end
    -- lo de otro, nada
    else 'no' end;
$$;

\echo '@@MATRIZ@@'
select actor, empresa, grupo, accion, resultado, public.esperado(actor, empresa, grupo, accion) as esperado, coalesce(detalle, '')
from public.matriz order by orden;
\echo '@@FIN@@'

do $$
begin
  assert (select count(*) from public.matriz) > 200, 'la matriz se ha medido';
  -- Medir no cambia nada: el borrador sigue en edición y la empresa X sigue existiendo con sus accesos
  assert (select status from erp.journal_entries where id = (select e from public.ctx where k = 'BORRADOR_X')) = 'draft';
  assert (select count(*) from erp.company_users where company_id = (select e from public.ctx where k = 'X')) = 5;
  raise notice 'OK  · % intentos medidos (y deshechos)', (select count(*) from public.matriz);
  assert not exists (select 1 from public.matriz m, public.esperado(m.actor, m.empresa, m.grupo, m.accion) x
                     where (x = 'sí' and m.resultado not in ('sí', 'sí·regla')) or (x = 'no' and m.resultado not in ('no', 'no·vacío'))),
    E'distinto de lo que se exige:\n' || (select string_agg(m.actor || ' · ' || m.empresa || ' · ' || m.accion || ': ' || m.resultado
      || ' (se exige ' || x || ') ' || coalesce(m.detalle, ''), E'\n')
      from public.matriz m, public.esperado(m.actor, m.empresa, m.grupo, m.accion) x
      where (x = 'sí' and m.resultado not in ('sí', 'sí·regla')) or (x = 'no' and m.resultado not in ('no', 'no·vacío')));
  raise notice 'OK  · lo tuyo, todo: quien administra su empresa (o su temporal) lo hace todo, también la IA';
  raise notice 'OK  · lo de otro, nada: ni un registrado, ni un invitado, ni el propietario en la empresa de otro';
  raise notice 'OK  · las demos, solo para ver; los roles para compartir, lo suyo';
  -- regresiones del paso 284 (cada una fallaba antes de la migración 0085)
  assert (select resultado from public.matriz where actor = 'administrador' and accion = 'Analista: datos para la IA') = 'sí';
  assert (select resultado from public.matriz where actor = 'dueño de la temporal' and accion = 'Analista: gastar una consulta') = 'sí';
  assert (select resultado from public.matriz where actor = 'invitado de la demo' and accion like 'limpiar%') = 'no';
  assert (select resultado from public.matriz where actor = 'propietario (empresa ajena)' and accion = 'dar acceso a otro') = 'no';
  raise notice 'OK  · regresiones: la IA de quien administra y de la temporal; limpiar y dar accesos en lo de otro';
end $$;

\echo 'FASE 79 OK'
