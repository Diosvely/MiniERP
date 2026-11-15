-- =====================================================================
-- PRUEBAS FASE 80 · La guardiana: «lo de otro, nada», función a función (v0.58.0, paso 284)
-- ---------------------------------------------------------------------
-- Criterio de Diosvely (03-11-2026): cada persona es dueña absoluta de su información y nadie entra en la de otro.
-- La fase 79 prueba las acciones de la web una a una; esta prueba TODAS las funciones del ERP que puede ejecutar una
-- sesión, también las que se añadan en el futuro, sin escribirlas una a una.
--
-- La víctima (v) tiene sus empresas, con datos en casi todas las tablas (el caso «Taller Atlántico SL», completo, y
-- una importación). Tres atacantes llaman a cada función con los identificadores de la víctima: un registrado sin
-- acceso, un invitado de la demo y el propietario de la aplicación (que tampoco entra en lo de otro). Cada llamada se
-- deshace al terminar. Hay fuga si:
--   (a) escribe: cambia algo de las empresas de la víctima (una huella de todas sus filas, antes y después);
--   (b) enseña: la respuesta contiene un identificador de la víctima que el atacante no le ha dado;
--   (c) responde con datos y la respuesta es distinta de la que da con identificadores que no existen (lo que ve de la
--       víctima no puede ser más de lo que vería de una empresa que no existe).
-- Control: la víctima hace las mismas llamadas y ve o cambia lo suyo en más de 100 funciones (si no, las llamadas no
-- estarían llegando al código y la prueba no probaría nada).
-- Además: sin sesión (anon) no se puede ejecutar ninguna función del ERP ni leer ninguna tabla.
-- Si una función nueva tiene un parámetro con un nombre que la prueba no conoce, la prueba falla: hay que decirle qué
-- identificador le corresponde (public.mapa).
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'propietario@test.local'),
  ('00000000-0000-0000-0000-0000000000b1', 'victima@test.local'),
  ('00000000-0000-0000-0000-0000000000a6', 'extrano@test.local');
insert into auth.users (id, email, is_anonymous) values ('00000000-0000-0000-0000-0000000000a8', null, true);
insert into erp.app_profiles (user_id, app_role, max_companies) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner', null),
  ('00000000-0000-0000-0000-0000000000b1', 'member', 3),
  ('00000000-0000-0000-0000-0000000000a6', 'member', 3)
on conflict (user_id) do update set app_role = excluded.app_role;

create or replace procedure public.ser(p_role text, p_sub text, p_anon boolean default false) language plpgsql as $$
begin
  execute format('set role %I', p_role);
  perform set_config('request.jwt.claim.sub', coalesce(p_sub, ''), false);
  perform set_config('request.jwt.claims',
    case when p_sub is null then '' else jsonb_build_object('sub', p_sub, 'is_anonymous', p_anon)::text end, false);
end $$;
grant execute on procedure public.ser(text, text, boolean) to anon, authenticated;

-- ---------- Las empresas de la víctima ----------
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000b1');
do $$ declare r record; c uuid; fy uuid; a uuid; begin
  c := (erp.create_case_company('taller_atlantico', 'full')->>'company_id')::uuid;
  insert into public.ctx values ('Z', c);
  -- un borrador (los demás asientos del caso están contabilizados)
  fy := (select id from erp.fiscal_years where company_id = c order by year desc limit 1);
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, fy, (select ending_date from erp.fiscal_years where id = fy), 'Borrador') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '62300001'), 100);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 100);
  insert into public.ctx values ('BORRADOR', a);
  -- lo que el caso completo no trae (tiene 2026 cerrado): en otra empresa del caso, hasta el cierre, una persona en
  -- plantilla con su nómina, una provisión y una insolvencia firme
  c := (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid;
  insert into public.ctx values ('Z2', c);
  perform erp.save_employee(jsonb_build_object('company_id', c, 'name', 'Ana Ficticia', 'hire_date', '2026-01-01',
    'monthly_salary', 2000, 'irpf_pct', 12));
  perform erp.run_payroll(jsonb_build_object('company_id', c, 'period', '2026-12-31'));
  perform erp.create_provision(jsonb_build_object('company_id', c, 'kind', 'commercial', 'description', 'Garantías',
    'amount', 1000, 'provision_date', '2026-12-31'));
  perform erp.write_off_receivable(jsonb_build_object('invoice_id', o.invoice_id, 'writeoff_date', '2026-12-31'))
  from erp.open_items(c, '2026-12-31') o where o.pending > 0 limit 1;
  -- una importación empezada (la víctima es miembro: la importa en permanente)
  select * into r from erp.import_start('Importada', 8, 'mainland', 'services', 'sage', 'diario.csv');
  insert into public.ctx values ('I', r.company_id), ('LOTE', r.batch_id);
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

-- Todas las tablas con filas de una empresa (company_id), y todos los identificadores de la víctima
create table public.tablas as
select c.oid::regclass as t from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'erp' and c.relkind = 'r'
  and exists (select 1 from pg_attribute where attrelid = c.oid and attname = 'company_id' and not attisdropped);

create table public.ids (id uuid primary key, tabla text);
do $$ declare r record; begin
  for r in select t from public.tablas
           where exists (select 1 from pg_attribute where attrelid = t and attname = 'id' and not attisdropped) loop
    execute format('insert into public.ids select id, %L from %s where company_id in (select e from public.ctx where k in (''Z'', ''Z2'', ''I'')) on conflict do nothing',
                   r.t::text, r.t);
  end loop;
  insert into public.ids select e, 'companies' from public.ctx where k in ('Z', 'Z2', 'I') on conflict do nothing;
  insert into public.ids values ('00000000-0000-0000-0000-0000000000b1', 'auth.users') on conflict do nothing;
end $$;

-- Huella de todo lo de la víctima (como superusuario, sin seguridad fila a fila)
create or replace function public.huella() returns text language plpgsql as $$
declare r record; h text := ''; x text;
begin
  for r in select t from public.tablas order by t::text loop
    execute format('select md5(coalesce(string_agg(x::text, ''|'' order by x::text), '''')) from %s x where company_id in (select e from public.ctx where k in (''Z'', ''Z2'', ''I''))', r.t) into x;
    h := h || x;
  end loop;
  select h || md5(coalesce(string_agg(c::text, '|' order by c.id), '')) into h from erp.companies c where id in (select e from public.ctx where k in ('Z', 'Z2', 'I'));
  return md5(h);
end $$;

-- ---------- Qué identificador va en cada parámetro ----------
-- real: uno de la víctima; fantasma: uno que no existe (el mismo en todas las llamadas)
create table public.mapa (param text primary key, tabla text, real uuid, fantasma uuid default gen_random_uuid());
insert into public.mapa (param, tabla) values
  ('p_company', 'companies'), ('p_entry', 'journal_entries'), ('e', 'journal_entries'), ('p_entries', 'journal_entries'),
  ('p_source', 'journal_entries'), ('p_asset', 'fixed_assets'), ('p_batch', 'import_batches'),
  ('p_fy', 'fiscal_years'), ('p_fiscal_year', 'fiscal_years'), ('p_account', 'gl_accounts'),
  ('p_provision', 'provisions'), ('p_partner', 'business_partners'), ('p_accrual', 'accruals'),
  ('p_return', 'corporate_tax_returns'), ('p_loan', 'loans'), ('p_invoice', 'invoices'),
  ('p_impairment', 'receivable_impairments'), ('p_writeoff', 'receivable_writeoffs'), ('p_employee', 'employees'),
  ('p_count', 'inventory_counts'), ('p_settlement', 'tax_settlements'), ('p_payment', 'payments'),
  ('p_operation', 'equity_operations'), ('p_grant', 'grants'), ('p_run', 'payroll_runs'), ('p_user', 'auth.users'),
  ('p_adjustment', 'corporate_tax_adjustments'), ('p_call', 'ai_calls');
-- v0.60.6 (H-079): un justificante de IA de la víctima (erp.ai_refund no debe devolvérselo a otro)
insert into erp.ai_calls (user_id, used_on) values ('00000000-0000-0000-0000-0000000000b1', current_date);
update public.mapa m set real = case
  when m.param = 'p_call' then (select id from erp.ai_calls where user_id = '00000000-0000-0000-0000-0000000000b1' limit 1)
  when m.param = 'p_company' then (select e from public.ctx where k = 'Z')
  when m.param = 'p_batch'   then (select e from public.ctx where k = 'LOTE')
  when m.param in ('p_entry', 'e') then (select e from public.ctx where k = 'BORRADOR')
  else (select id from public.ids i where i.tabla = 'erp.' || m.tabla or i.tabla = m.tabla order by id limit 1) end;
do $$ begin
  assert not exists (select 1 from public.mapa where real is null),
    'la víctima tiene filas en todas las tablas del mapa: ' || (select string_agg(param, ', ') from public.mapa where real is null);
end $$;

-- El valor de un parámetro, como texto SQL
create or replace function public.valor(p_type regtype, p_name text, p_real boolean) returns text language plpgsql as $$
declare id uuid; ids jsonb;
begin
  if p_type = 'uuid'::regtype then
    select case when p_real then real else fantasma end into id from public.mapa where param = p_name;
    if id is null then raise exception 'GUARDIANA: parámetro sin mapa: %', p_name; end if;
    return quote_literal(id) || '::uuid';
  elsif p_type = 'uuid[]'::regtype then
    select case when p_real then real else fantasma end into id from public.mapa where param = p_name;
    if id is null then raise exception 'GUARDIANA: parámetro sin mapa: %', p_name; end if;
    return format('array[%L]::uuid[]', id);
  elsif p_type = 'jsonb'::regtype then
    select jsonb_object_agg(k, case when p_real then real else fantasma end) into ids
    from (values ('company_id', 'p_company'), ('entry_id', 'p_entry'), ('partner_id', 'p_partner'), ('invoice_id', 'p_invoice'),
                 ('gl_account_id', 'p_account'), ('account_id', 'p_account'), ('asset_id', 'p_asset'),
                 ('fiscal_year_id', 'p_fy'), ('payment_id', 'p_payment'), ('loan_id', 'p_loan'),
                 ('employee_id', 'p_employee'), ('grant_id', 'p_grant'), ('provision_id', 'p_provision'),
                 ('batch_id', 'p_batch'), ('run_id', 'p_run'), ('accrual_id', 'p_accrual')) v(k, param)
    join public.mapa using (param);
    return quote_literal((ids || jsonb_build_object('date', '2026-06-30', 'posting_date', '2026-06-30',
      'invoice_date', '2026-06-30', 'year', 2026, 'amount', 100, 'description', 'x', 'lines', '[]'::jsonb))::text) || '::jsonb';
  elsif p_type = 'boolean'::regtype then return 'true';
  elsif p_type = 'date'::regtype then
    return case when p_name in ('p_from', 'p_start') then '''2026-01-01''::date' else '''2026-12-31''::date' end;
  elsif p_type = 'date[]'::regtype then return 'array[''2026-06-30'', ''2026-12-31'']::date[]';
  elsif p_type = 'timestamptz'::regtype then return 'now()';
  elsif p_type = 'integer'::regtype then
    return case p_name when 'p_year' then '2026' when 'p_quarter' then '4' when 'p_month' then '12' when 'p_rows' then '0'
                       when 'p_offset' then '0' when 'p_digits' then '8' else '10' end;
  elsif p_type = 'numeric'::regtype then return '100';
  elsif p_type = 'numeric[]'::regtype then return 'array[100]::numeric[]';
  elsif p_type = 'text[]'::regtype then return 'array[''6'']::text[]';
  elsif p_type = 'text'::regtype then
    return quote_literal(case p_name
      when 'p_tax_type' then 'IGIC' when 'p_statement' then 'balance' when 'p_dashboard' then 'resumen'
      when 'p_code' then 'resumen' when 'p_language' then 'es' when 'p_lang' then 'es' when 'p_mode' then 'until_closing'
      when 'p_case' then 'taller_atlantico' when 'p_source' then 'sage' when 'p_role' then 'viewer'
      when 'p_email' then 'extrano@test.local' when 'p_account_no' then '62300001' when 'p_prefix' then '6'
      when 'p_territory' then 'canary' when 'p_industry' then 'services' when 'p_kind' then 'balance'
      else 'x' end);
  else
    return format('null::%s', p_type);
  end if;
end $$;

-- Las funciones que puede ejecutar una sesión, con su llamada real y la fantasma
create table public.funciones (f regprocedure, nombre text, con_ids boolean, real text, fantasma text, sin_retorno boolean);
do $$
declare p record; args_r text[]; args_f text[]; i int; con boolean;
begin
  for p in select pr.oid, pr.oid::regprocedure as f, pr.proname, pr.pronargs, string_to_array(pr.proargtypes::text, ' ')::oid[] as tipos,
                  coalesce(pr.proargnames, '{}') as nombres, pr.proargmodes, pr.prorettype = 'void'::regtype as v
           from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
           where n.nspname = 'erp' and pr.prokind = 'f' and has_function_privilege('authenticated', pr.oid, 'execute') loop
    args_r := '{}'; args_f := '{}'; con := false;
    for i in 1 .. p.pronargs loop
      declare nm text; j int := 0; k int; begin
        -- el nombre del i-ésimo parámetro de entrada (proargnames incluye también los de salida)
        if p.proargmodes is null then nm := p.nombres[i];
        else
          for k in 1 .. array_length(p.proargmodes, 1) loop
            if p.proargmodes[k] in ('i', 'b', 'v') then j := j + 1; if j = i then nm := p.nombres[k]; exit; end if; end if;
          end loop;
        end if;
        if p.tipos[i] in ('uuid'::regtype, 'uuid[]'::regtype) then con := true; end if;
        args_r := args_r || public.valor(p.tipos[i]::regtype, coalesce(nm, ''), true);
        args_f := args_f || public.valor(p.tipos[i]::regtype, coalesce(nm, ''), false);
      end;
    end loop;
    insert into public.funciones values (p.f, p.proname, con,
      format('erp.%I(%s)', p.proname, array_to_string(args_r, ', ')),
      format('erp.%I(%s)', p.proname, array_to_string(args_f, ', ')), p.v);
  end loop;
end $$;
grant select on public.funciones, public.mapa, public.ids to authenticated;

-- ---------- Una llamada: su resultado (o «error»), si escribió en lo de la víctima, y se deshace ----------
create table public.llamadas (atacante text, f text, tipo text, resultado text, error text, escribe boolean);
create or replace function public.llamar(p_atacante text, p_role text, p_sub text, p_anon boolean, p_f text,
                                          p_sql text, p_void boolean, p_tipo text, p_antes text)
returns void language plpgsql as $$
declare res text; err text; esc boolean;
begin
  begin
    call public.ser(p_role, p_sub, p_anon);
    if p_void then execute 'select ' || p_sql; res := 'ok';
    else execute format('select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb)::text from %s r', p_sql) into res;
    end if;
    reset role;
    esc := public.huella() <> p_antes;
    raise exception 'GUARDIANA:%', jsonb_build_object('r', res, 'w', esc)::text;
  exception when others then
    if sqlerrm like 'GUARDIANA:{%' then
      res := (substr(sqlerrm, 11)::jsonb)->>'r'; esc := ((substr(sqlerrm, 11)::jsonb)->>'w')::boolean;
    else
      err := left(sqlerrm, 200); res := null; esc := false;   -- un error lo deshace todo: no escribe
    end if;
  end;
  insert into public.llamadas values (p_atacante, p_f, p_tipo, res, err, esc);
end $$;

do $$
declare a record; fn record; antes text := public.huella();
begin
  for a in select * from (values
      ('registrado sin acceso', '00000000-0000-0000-0000-0000000000a6', false),
      ('invitado de la demo',   '00000000-0000-0000-0000-0000000000a8', true),
      ('propietario de la app', '00000000-0000-0000-0000-0000000000a1', false),
      ('la víctima (control)',  '00000000-0000-0000-0000-0000000000b1', false)) v(atacante, sub, anon) loop
    for fn in select * from public.funciones order by nombre loop
      perform public.llamar(a.atacante, 'authenticated', a.sub, a.anon, fn.f::text, fn.real, fn.sin_retorno, 'real', antes);
      if fn.con_ids and a.atacante <> 'la víctima (control)' then
        perform public.llamar(a.atacante, 'authenticated', a.sub, a.anon, fn.f::text, fn.fantasma, fn.sin_retorno, 'fantasma', antes);
      end if;
    end loop;
  end loop;
end $$;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

-- ---------- Las fugas ----------
create or replace function public.vacio(p text) returns boolean language sql immutable as $$
  select p is null or p in ('ok', '[]', '[null]', '[false]', '[0]', '[{}]', '[[]]', '[""]', 'null', '{}');
$$;

-- La respuesta real, con los identificadores de la víctima cambiados por los fantasma
create or replace function public.normalizar(p text) returns text language plpgsql as $$
declare m record; x text := p;
begin
  for m in select real, fantasma from public.mapa loop x := replace(x, m.real::text, m.fantasma::text); end loop;
  return x;
end $$;

create table public.fugas as
select * from (
-- (a) escribe en lo de la víctima
select l.atacante, l.f, 'escribe' as fuga, left(coalesce(l.resultado, ''), 160) as detalle
from public.llamadas l where l.tipo = 'real' and l.escribe
union all
-- (b) enseña un identificador de la víctima que no se le ha dado
select l.atacante, l.f, 'enseña ' || i.tabla, i.id::text
from public.llamadas l join public.ids i on l.resultado like '%' || i.id::text || '%'
where l.tipo = 'real' and i.id not in (select real from public.mapa)
union all
-- (c) con datos, responde distinto que con identificadores que no existen
select r.atacante, r.f, 'responde distinto', left(r.resultado, 160)
from public.llamadas r join public.llamadas g on g.atacante = r.atacante and g.f = r.f and g.tipo = 'fantasma'
where r.tipo = 'real' and not public.vacio(r.resultado)
  and coalesce(g.resultado, 'error') is distinct from public.normalizar(r.resultado)
) x where atacante <> 'la víctima (control)';

\pset format unaligned
\pset fieldsep '|'
\pset footer off
\echo '@@FUGAS@@'
select * from public.fugas order by atacante, f, fuga;
\echo '@@FIN@@'
\pset format aligned

do $$
declare n_f int; n_ll int;
begin
  select count(*) into n_f from public.funciones;
  select count(*) into n_ll from public.llamadas;
  -- sin sesión: ninguna función del ERP y ninguna tabla
  assert not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname in ('erp', 'bi') and has_function_privilege('anon', p.oid, 'execute')),
    'sin sesión se puede ejecutar: ' || (select string_agg(p.oid::regprocedure::text, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname in ('erp', 'bi') and has_function_privilege('anon', p.oid, 'execute'));
  assert not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where n.nspname in ('erp', 'bi') and c.relkind in ('r', 'v', 'm') and has_table_privilege('anon', c.oid, 'select')),
    'sin sesión se puede leer una tabla del ERP';
  raise notice 'OK  · sin sesión no se ejecuta ninguna función ni se lee ninguna tabla';
  assert n_f > 200, 'se prueban todas las funciones';
  raise notice 'OK  · % funciones, % llamadas de 3 atacantes contra las empresas de otro usuario (y de la víctima)', n_f, n_ll;
  -- control: con las mismas llamadas, la víctima sí ve o cambia lo suyo en muchas funciones (las llamadas llegan al
  -- código, no se quedan en un error de los valores de prueba)
  assert (select count(*) from public.llamadas where atacante = 'la víctima (control)' and error is null
          and (escribe or not public.vacio(resultado))) > 100, 'la víctima ve o cambia lo suyo';
  raise notice 'OK  · control: la víctima ve o cambia lo suyo en % funciones con las mismas llamadas',
    (select count(*) from public.llamadas where atacante = 'la víctima (control)' and error is null and (escribe or not public.vacio(resultado)));
  assert not exists (select 1 from public.fugas),
    'fugas: ' || (select string_agg(atacante || ' · ' || f || ' · ' || fuga, E'\n') from public.fugas);
  raise notice 'OK  · ninguna fuga: ni escribe, ni enseña, ni responde distinto que ante una empresa que no existe';
  -- y nada ha cambiado de verdad
  assert (select status from erp.journal_entries where id = (select e from public.ctx where k = 'BORRADOR')) = 'draft';
end $$;

-- =====================================================================
-- v0.60.3 · Escrituras directas por la API (hallazgos SEG-09 a SEG-12 del chat de seguridad)
-- La web solo usa funciones, pero la API de Supabase también deja escribir en las tablas que tienen permiso. Ahí las
-- reglas de las funciones no se aplican: lo que protege es la RLS y los disparadores. Lo probamos tabla a tabla.
-- =====================================================================

-- SEG-12 · Ninguna tabla del esquema erp sin RLS (una tabla nueva sin ella sería legible por cualquier sesión)
do $$
begin
  assert not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                     where n.nspname = 'erp' and c.relkind = 'r' and not c.relrowsecurity),
    'tablas sin RLS: ' || (select string_agg(c.relname, ', ') from pg_class c join pg_namespace n on n.oid = c.relnamespace
                           where n.nspname = 'erp' and c.relkind = 'r' and not c.relrowsecurity);
  raise notice 'OK  · todas las tablas del esquema erp tienen RLS';
end $$;

-- Una escritura directa: cuántas filas cambia (o el error), y se deshace siempre
create table public.escrituras (atacante text, tabla text, op text, filas int, error text);
create or replace function public.escribir(p_atacante text, p_sub text, p_anon boolean, p_tabla text, p_op text,
                                           p_sql text, p_fila jsonb default null)
returns void language plpgsql as $$
declare n int; err text;
begin
  begin
    call public.ser('authenticated', p_sub, p_anon);
    if p_fila is null then execute p_sql; else execute p_sql using p_fila; end if;
    get diagnostics n = row_count;
    raise exception 'ESCRITURA:%', n;
  exception when others then
    if sqlerrm like 'ESCRITURA:%' then n := substr(sqlerrm, 11)::int;
    else n := 0; err := left(sqlerrm, 200);
    end if;
  end;
  insert into public.escrituras values (p_atacante, p_tabla, p_op, n, err);
end $$;

-- SEG-12 · Cada tabla con permiso de escritura para una sesión: los tres atacantes intentan insertar, cambiar y borrar
-- filas de las empresas de la víctima. Tiene que dar error o cero filas. Control: la víctima sí cambia lo suyo.
do $$
declare a record; t record; v text := '(select e from public.ctx where k in (''Z'', ''Z2'', ''I''))'; fila jsonb;
begin
  for a in select * from (values
      ('registrado sin acceso', '00000000-0000-0000-0000-0000000000a6', false),
      ('invitado de la demo',   '00000000-0000-0000-0000-0000000000a8', true),
      ('propietario de la app', '00000000-0000-0000-0000-0000000000a1', false),
      ('la víctima (control)',  '00000000-0000-0000-0000-0000000000b1', false)) x(atacante, sub, anon) loop
    for t in select x.t from public.tablas x order by x.t::text loop
      if has_table_privilege('authenticated', t.t, 'UPDATE') then
        perform public.escribir(a.atacante, a.sub, a.anon, t.t::text, 'update',
          format('update %s set company_id = company_id where company_id in %s', t.t, v));
      end if;
      if has_table_privilege('authenticated', t.t, 'DELETE') and a.atacante <> 'la víctima (control)' then
        perform public.escribir(a.atacante, a.sub, a.anon, t.t::text, 'delete',
          format('delete from %s where company_id in %s', t.t, v));
      end if;
      if has_table_privilege('authenticated', t.t, 'INSERT') and a.atacante <> 'la víctima (control)' then
        -- una fila de la víctima, copiada con otro identificador: insertarla en su empresa no puede funcionar
        execute format('select to_jsonb(x) from %s x where company_id in %s limit 1', t.t, v) into fila;
        if fila is not null then
          if fila ? 'id' then fila := fila || jsonb_build_object('id', gen_random_uuid()); end if;
          perform public.escribir(a.atacante, a.sub, a.anon, t.t::text, 'insert',
            format('insert into %s select * from jsonb_populate_record(null::%s, $1)', t.t, t.t), fila);
        end if;
      end if;
    end loop;
    -- la propia empresa (erp.companies no tiene company_id: es su id)
    perform public.escribir(a.atacante, a.sub, a.anon, 'erp.companies', 'update',
      format('update erp.companies set name = name where id in %s', v));
    if a.atacante <> 'la víctima (control)' then
      perform public.escribir(a.atacante, a.sub, a.anon, 'erp.companies', 'delete',
        format('delete from erp.companies where id in %s', v));
    end if;
  end loop;
end $$;

do $$
declare n int;
begin
  select count(*) into n from public.escrituras where atacante <> 'la víctima (control)';
  assert n > 100, 'se prueban las escrituras directas en muchas tablas';
  assert not exists (select 1 from public.escrituras where atacante <> 'la víctima (control)' and filas > 0),
    'escrituras directas en lo de otro: ' || (select string_agg(atacante || ' · ' || op || ' ' || tabla || ' (' || filas || ')', E'\n')
                                              from public.escrituras where atacante <> 'la víctima (control)' and filas > 0);
  -- control: con la misma consulta, la víctima sí cambia filas suyas (la prueba llega a las tablas)
  assert (select count(*) from public.escrituras where atacante = 'la víctima (control)' and filas > 0) >= 5,
    'control: la víctima cambia lo suyo: ' || (select string_agg(tabla || ' ' || coalesce(error, filas::text), E'\n')
                                               from public.escrituras where atacante = 'la víctima (control)');
  raise notice 'OK  · % escrituras directas de 3 atacantes en las tablas de la víctima: ninguna cambia nada (control: la víctima cambia lo suyo en % tablas)',
    n, (select count(*) from public.escrituras where atacante = 'la víctima (control)' and filas > 0);
end $$;

-- SEG-09 (regresión, regla A1) · Un administrador de su empresa no puede dar, cambiar ni quitar accesos escribiendo
-- directamente en erp.company_users: solo el propietario de la app, con sus funciones, en sus empresas
create or replace function public.falla(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end $$;
grant execute on function public.falla(text) to authenticated;

call public.ser('authenticated', '00000000-0000-0000-0000-0000000000a6');
do $$
declare c uuid; e text;
begin
  insert into erp.companies (name, industry, tax_territory) values ('Del registrado', 'services', 'mainland') returning id into c;
  insert into public.ctx values ('PROPIA', c);
  assert erp.my_role(c) = 'admin', 'es administrador de su empresa';
  e := public.falla(format('insert into erp.company_users (company_id, user_id, role) values (%L, %L, ''viewer'')',
                           c, '00000000-0000-0000-0000-0000000000b1'));
  assert e like '%permission denied%', 'SEG-09: dar acceso escribiendo en la tabla: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.company_users set role = ''viewer'' where company_id = %L', c));
  assert e like '%permission denied%', 'SEG-09: cambiar un rol escribiendo en la tabla: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('delete from erp.company_users where company_id = %L', c));
  assert e like '%permission denied%', 'SEG-09: quitar un acceso escribiendo en la tabla: ' || coalesce(e, 'lo dejó hacer');
  raise notice 'OK  · SEG-09: un administrador no da, cambia ni quita accesos escribiendo en erp.company_users';

  -- SEG-10 (a) · no puede cambiar quién creó su empresa (el límite de empresas lo cuenta)
  e := public.falla(format('update erp.companies set created_by = gen_random_uuid() where id = %L', c));
  assert e like '%creator of a company cannot be changed%', 'SEG-10: cambiar created_by: ' || coalesce(e, 'lo dejó hacer');
  raise notice 'OK  · SEG-10: el creador de una empresa no se cambia';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

-- SEG-09 (control) · el propietario de la app sí da y quita accesos en SU empresa, con las funciones
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000a1');
do $$
declare c uuid;
begin
  insert into erp.companies (name, industry, tax_territory) values ('Del propietario', 'services', 'mainland') returning id into c;
  insert into public.ctx values ('DUENO', c);
  perform erp.grant_company_access(c, 'extrano@test.local', 'viewer');
  assert erp.can_read(c) and (select count(*) from erp.company_users where company_id = c) = 2, 'control: el propietario da acceso';
  perform erp.revoke_company_access(c, '00000000-0000-0000-0000-0000000000a6');
  assert (select count(*) from erp.company_users where company_id = c) = 1, 'control: el propietario quita el acceso';
  raise notice 'OK  · control: el propietario da y quita accesos en su empresa con las funciones';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

-- SEG-10 (b) · una sintética nunca es demo, tampoco con una escritura directa del propietario de la app
update erp.companies set synthetic_seed = 4817, synthetic_profile = 'workshop', synthetic_months = 1
where id = (select e from public.ctx where k = 'DUENO');
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000a1');
do $$
declare c uuid := (select e from public.ctx where k = 'DUENO'); e text;
begin
  e := public.falla(format('update erp.companies set is_demo = true where id = %L', c));
  assert e like '%synthetic company cannot be published as demo%', 'SEG-10: sintética como demo: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.companies set synthetic_seed = 1 where id = %L', c));
  assert e like '%seed of a synthetic company cannot be changed%', 'SEG-10: cambiar la semilla: ' || coalesce(e, 'lo dejó hacer');
  raise notice 'OK  · SEG-10: una sintética no se publica como demo ni cambia de semilla con una escritura directa';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

-- SEG-11 (regresión) · un apunte no puede llevar un tercero de otra empresa (aunque las dos sean de la víctima)
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000b1');
do $$
declare a uuid := (select e from public.ctx where k = 'BORRADOR'); z uuid := (select e from public.ctx where k = 'Z');
        z2 uuid := (select e from public.ctx where k = 'Z2'); cta uuid; e text;
begin
  cta := (select id from erp.gl_accounts where company_id = z and account_no = '62300001');
  e := public.falla(format('insert into erp.journal_lines (entry_id, gl_account_id, debit, partner_id) values (%L, %L, 10, %L)',
                           a, cta, (select id from erp.business_partners where company_id = z2 limit 1)));
  assert e like '%partner does not belong to this company%', 'SEG-11: tercero de otra empresa: ' || coalesce(e, 'lo dejó hacer');
  -- control: con un tercero de su empresa, sí
  e := public.falla(format('insert into erp.journal_lines (entry_id, gl_account_id, debit, partner_id) values (%L, %L, 10, %L)',
                           a, cta, (select id from erp.business_partners where company_id = z limit 1)));
  assert e is null, 'control: tercero de la misma empresa: ' || coalesce(e, '');
  delete from erp.journal_lines where entry_id = a and debit = 10;
  raise notice 'OK  · SEG-11: el tercero de un apunte es de su misma empresa';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

-- ---------- v0.60.5 · SEG-13, SEG-14, SEG-18 y SEG-19 (regresión) ----------
-- La víctima escribe directamente en SU empresa (Z2, el caso hasta antes del cierre: 2026 abierto)
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000b1');
do $$
declare z uuid := (select e from public.ctx where k = 'Z2'); z1 uuid := (select e from public.ctx where k = 'Z');
        fy uuid; d date; gasto uuid; banco uuid; p uuid; d2 uuid; d3 uuid; d4 uuid; n int; e text; t uuid;
begin
  select y.id, per.ending_date into fy, d
  from erp.fiscal_years y join erp.accounting_periods per on per.fiscal_year_id = y.id
  where y.company_id = z and y.status = 'open' and per.status = 'open' order by y.year desc, per.period_no limit 1;
  gasto := (select id from erp.gl_accounts where company_id = z and account_no = '62300001');
  banco := (select id from erp.gl_accounts where company_id = z and account_no = '57200001');
  -- un asiento contabilizado (con erp.post_entry) y dos borradores
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (z, fy, d, 'SEG contabilizado') returning id into p;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (p, gasto, 50);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (p, banco, 50);
  perform erp.post_entry(p);
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (z, fy, d, 'SEG borrador 2') returning id into d2;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (d2, gasto, 30);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (d2, banco, 30);
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (z, fy, d, 'SEG borrador 3') returning id into d3;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (d3, gasto, 999);

  -- SEG-13 · una línea no cambia de asiento: ni de un contabilizado a un borrador, ni entre borradores
  e := public.falla(format('update erp.journal_lines set entry_id = %L where entry_id = %L and credit = 50', d2, p));
  assert e like '%cannot be moved to another entry%', 'SEG-13: mover la línea de un contabilizado: ' || coalesce(e, 'lo dejó hacer');
  assert (select count(*) from erp.journal_lines where entry_id = p) = 2, 'SEG-13: el contabilizado conserva sus dos líneas';
  e := public.falla(format('update erp.journal_lines set entry_id = %L where entry_id = %L and debit = 30', d3, d2));
  assert e like '%cannot be moved to another entry%', 'SEG-13: mover una línea entre borradores: ' || coalesce(e, 'lo dejó hacer');
  -- control: editar el importe de un borrador sigue funcionando
  e := public.falla(format('update erp.journal_lines set debit = 35 where entry_id = %L and debit = 30', d2));
  assert e is null, 'control: editar un borrador: ' || coalesce(e, '');
  update erp.journal_lines set credit = 35 where entry_id = d2 and credit = 30;
  raise notice 'OK  · SEG-13: una línea no se mueve de un asiento a otro';

  -- SEG-14 · solo se contabiliza lo que erp.post_entry aceptaría
  e := public.falla(format('update erp.journal_entries set status = %L, entry_no = 999 where id = %L', 'posted', d3));
  assert e like '%at least 2 lines%', 'SEG-14: una sola línea: ' || coalesce(e, 'lo dejó hacer');
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (d3, banco, 1);
  e := public.falla(format('update erp.journal_entries set status = %L, entry_no = 999 where id = %L', 'posted', d3));
  assert e like '%Unbalanced entry%', 'SEG-14: descuadrado: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.journal_entries set status = %L, entry_no = 999 where id = %L', 'posted', d2));
  assert e like '%must be the next one%', 'SEG-14: número a elección: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, status, entry_no) values (%L, %L, %L, %L, %L, 9999)',
                           z, fy, d, 'SEG directo', 'posted'));
  assert e like '%starts as a draft%', 'SEG-14: crear un asiento ya contabilizado: ' || coalesce(e, 'lo dejó hacer');
  -- control: erp.post_entry del mismo borrador cuadrado funciona y pone el número siguiente
  n := erp.post_entry(d2);
  assert n = (select max(entry_no) from erp.journal_entries where fiscal_year_id = fy), 'control: post_entry pone el número siguiente';
  raise notice 'OK  · SEG-14: solo se contabiliza con las condiciones de erp.post_entry (número %)', n;

  -- SEG-18 · la subcuenta de un tercero: de su empresa, de detalle y de su tipo
  t := (select id from erp.business_partners where company_id = z and partner_type = 'customer' limit 1);
  e := public.falla(format('update erp.business_partners set gl_account_id = %L where id = %L',
                           (select id from erp.gl_accounts where company_id = z1 and account_no like '430%%' and account_type = 'posting' limit 1), t));
  assert e like '%does not belong to this company%', 'SEG-18: subcuenta de otra empresa: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.business_partners set gl_account_id = %L where id = %L', banco, t));
  assert e like '%does not match the partner type%', 'SEG-18: el banco como subcuenta de un cliente: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.business_partners set partner_type = %L where id = %L', 'vendor', t));
  assert e like '%does not match the partner type%', 'SEG-18: cliente a proveedor sin cambiar su 430: ' || coalesce(e, 'lo dejó hacer');
  -- control: cambiar el nombre del tercero sigue funcionando
  e := public.falla(format('update erp.business_partners set email = %L where id = %L', 'cliente@ficticio.test', t));
  assert e is null, 'control: cambiar el correo del tercero: ' || coalesce(e, '');
  raise notice 'OK  · SEG-18: la subcuenta de un tercero es de su empresa y de su tipo';

  -- SEG-19 · tope de tamaño de las opiniones sobre la IA (1.000 caracteres de texto del usuario)
  e := public.falla(format('insert into erp.ai_feedback (company_id, kind, prompt, answer, verdict) values (%L, %L, %L, %L, %L)',
                           z, 'tutor', repeat('x', 1001), '{}', 'correct'));
  assert e like '%ai_feedback_sizes%', 'SEG-19: pregunta de 1.001 caracteres: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('insert into erp.ai_feedback (company_id, kind, prompt, answer, verdict, comment) values (%L, %L, %L, %L, %L, %L)',
                           z, 'tutor', 'Compra de material', '{}', 'wrong', repeat('x', 1001)));
  assert e like '%ai_feedback_sizes%', 'SEG-19: comentario de 1.001 caracteres: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('insert into erp.ai_feedback (company_id, kind, prompt, answer, verdict) values (%L, %L, %L, %L, %L)',
                           z, 'tutor', 'Compra', jsonb_build_object('x', repeat('y', 40000)), 'correct'));
  assert e like '%ai_feedback_sizes%', 'SEG-19: respuesta de más de 32 KB: ' || coalesce(e, 'lo dejó hacer');
  -- control: una opinión normal se guarda
  e := public.falla(format('insert into erp.ai_feedback (company_id, kind, prompt, answer, verdict, comment) values (%L, %L, %L, %L, %L, %L)',
                           z, 'tutor', repeat('x', 1000), '{"lines": []}', 'partial', 'Falta el IGIC'));
  assert e is null, 'control: una opinión normal: ' || coalesce(e, '');
  raise notice 'OK  · SEG-19: las opiniones sobre la IA tienen tope de tamaño';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

-- ---------- v0.60.6 · SEG-21, SEG-22 y H-079 (regresión) ----------
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000b1');
do $$
declare z uuid := (select e from public.ctx where k = 'Z2'); z1 uuid := (select e from public.ctx where k = 'Z');
        fy uuid; e text; c uuid; antes int;
begin
  -- SEG-21 · los ajustes de la empresa, con sus reglas
  e := public.falla(format('update erp.companies set tax_territory = %L where id = %L', 'canary', z));
  assert e like '%tax territory cannot be changed%', 'SEG-21: territorio: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.companies set posting_account_digits = 10 where id = %L', z));
  assert e like '%digits of the posting accounts%', 'SEG-21: dígitos: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.companies set legal_form = case legal_form when %L then %L else %L end where id = %L', 'sa', 'sl', 'sa', z1));
  assert e like '%equity operations%', 'SEG-21: forma jurídica con operaciones societarias: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.companies set start_date = %L where id = %L', '2026-02-01', z));
  assert e like '%already has entries%', 'SEG-21: fecha de inicio con asientos: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.companies set case_key = %L where id = %L', 'otro_caso', z));
  assert e like '%practice case%', 'SEG-21: caso de práctica: ' || coalesce(e, 'lo dejó hacer');
  -- control: cambiar el nombre sigue funcionando
  e := public.falla(format('update erp.companies set name = name where id = %L', z));
  assert e is null, 'control: el nombre: ' || coalesce(e, '');
  raise notice 'OK  · SEG-21: los ajustes de la empresa solo cambian con sus reglas';

  -- SEG-22 · los meses y los ejercicios
  select id into fy from erp.fiscal_years where company_id = z order by year desc limit 1;
  e := public.falla(format('update erp.accounting_periods set status = %L where fiscal_year_id = %L and period_no = 12', 'closed', fy));
  assert e like '%permission denied%', 'SEG-22: cerrar un mes directo: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('delete from erp.accounting_periods where fiscal_year_id = %L and period_no = 3', fy));
  assert e like '%permission denied%', 'SEG-22: borrar un mes: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('update erp.fiscal_years set ending_date = ending_date + 365 where id = %L', fy));
  assert e like '%cannot be changed%', 'SEG-22: alargar el ejercicio: ' || coalesce(e, 'lo dejó hacer');
  e := public.falla(format('insert into erp.fiscal_years (company_id, year, starting_date, ending_date, status) values (%L, 2031, %L, %L, %L)',
                           z, '2031-02-01', '2032-01-31', 'open'));
  assert e like '%1 January to 31 December%', 'SEG-22: ejercicio que no es el año natural: ' || coalesce(e, 'lo dejó hacer');
  -- control: erp.create_fiscal_year sigue funcionando (con sus 12 meses)
  e := public.falla(format('select erp.create_fiscal_year(%L, 2032)', z));
  assert e is null, 'control: create_fiscal_year: ' || coalesce(e, '');
  assert (select count(*) from erp.accounting_periods p join erp.fiscal_years y on y.id = p.fiscal_year_id where y.company_id = z and y.year = 2032) = 12;
  raise notice 'OK  · SEG-22: los meses y los ejercicios solo cambian con sus funciones';

  -- H-079 · la consulta de IA se devuelve una vez, solo a su usuario
  c := (erp.ai_consume(z)->>'call_id')::uuid;
  antes := (select calls from erp.ai_usage where user_id = auth.uid() and used_on = current_date);
  assert erp.ai_refund(c), 'H-079: devuelve la consulta';
  assert (select calls from erp.ai_usage where user_id = auth.uid() and used_on = current_date) = antes - 1, 'H-079: una menos';
  assert not erp.ai_refund(c), 'H-079: solo una vez';
  e := public.falla('select * from erp.ai_calls');
  assert e like '%permission denied%', 'H-079: nadie lee los justificantes: ' || coalesce(e, 'los pudo leer');
  raise notice 'OK  · H-079: la consulta de IA se devuelve una vez si el modelo falla';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

-- SEG-22 · con un mes que falta (solo lo puede borrar el administrador de la base), no se contabiliza en sus fechas
delete from erp.accounting_periods where period_no = 3
  and fiscal_year_id = (select id from erp.fiscal_years where company_id = (select e from public.ctx where k = 'Z2') and year = 2032);
call public.ser('authenticated', '00000000-0000-0000-0000-0000000000b1');
do $$
declare z uuid := (select e from public.ctx where k = 'Z2'); fy uuid; d uuid; e text;
begin
  select id into fy from erp.fiscal_years where company_id = z and year = 2032;
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (z, fy, '2032-03-15', 'SEG-22 sin mes') returning id into d;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (d, (select id from erp.gl_accounts where company_id = z and account_no = '62300001'), 10);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (d, (select id from erp.gl_accounts where company_id = z and account_no = '57200001'), 10);
  e := public.falla(format('update erp.journal_entries set status = %L, entry_no = 1 where id = %L', 'posted', d));
  assert e like '%no accounting period%', 'SEG-22: fecha sin mes: ' || coalesce(e, 'lo dejó hacer');
  raise notice 'OK  · SEG-22: no se contabiliza en una fecha sin mes';
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
select set_config('request.jwt.claims', '', false) \gset

\echo 'FASE 80 OK'
