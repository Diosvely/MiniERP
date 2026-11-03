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
  ('p_adjustment', 'corporate_tax_adjustments');
update public.mapa m set real = case
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

\echo 'FASE 80 OK'
