#!/usr/bin/env bash
# =====================================================================
# DIAGNÓSTICO DE SUPABASE: ¿le falta algo a TU base de datos frente al repositorio?
# Genera database/diagnostico-supabase.sql, una consulta de SOLO LECTURA que se pega en el SQL Editor de Supabase y
# devuelve una fila por cada diferencia (ninguna fila = todo al día):
#   · tabla / vista     → falta en el esquema erp
#   · función           → falta, o su cuerpo no es el del repositorio (se ignoran los saltos de línea de Windows),
#                         o sobra (una versión antigua con otros argumentos que ya no existe en el repositorio)
#   · concepto          → término del glosario que no está en erp.concepts
#   · comprobación      → comprobación del auditor que no está en erp.audit_checks
#   · fuente            → fuente oficial que no está en erp.sources
#   · seguridad (v0.60.5, SEG-15): tabla sin RLS; política que falta, es distinta o sobra; permiso de más o de menos
#     de anon / authenticated sobre una tabla (select, insert, update, delete) o una función (execute); v0.60.10 (SEG-26):
#     un rol que salta el RLS (superusuario o bypassrls) y entra en erp, salvo los del sistema
# Nació en la v0.40.0, cuando una migración antigua sin aplicar (0039, 0040, 0042) hizo fallar la 0054.
# Se GENERA (no se edita a mano) y se regenera al cerrar cada versión:   bash scripts/generar-diagnostico.sh
# Conexión: las variables estándar de PostgreSQL (PGHOST, PGPORT, PGUSER, PGPASSWORD), como test-db.sh.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

db="diagnostico_supabase"
out="database/diagnostico-supabase.sql"
dropdb --if-exists "$db" >/dev/null 2>&1
createdb "$db"
trap 'dropdb --if-exists "$db" >/dev/null 2>&1' EXIT
{
  psql -q -X -v ON_ERROR_STOP=1 -d "$db" -f database/tests/supabase_stub.sql
  for f in database/migrations/*.sql; do psql -q -X -v ON_ERROR_STOP=1 -d "$db" -f "$f"; done
} > /dev/null 2>&1

q() { psql -X -At -d "$db" -c "$1"; }
last=$(ls database/migrations | tail -1 | cut -c1-4)
rels=$(q "select string_agg(format('(%L, %L)', c.relname, case c.relkind when 'v' then 'vista' else 'tabla' end), ', ' order by c.relname collate \"C\")
          from pg_class c where c.relnamespace = 'erp'::regnamespace and c.relkind in ('r', 'v', 'p')")
fns=$(q "select string_agg(format('(%L, %L)', p.oid::regprocedure::text, md5(replace(p.prosrc, E'\r', ''))), E',\n  ' order by p.oid::regprocedure::text collate \"C\")
         from pg_proc p where p.pronamespace = 'erp'::regnamespace")
concepts=$(q "select string_agg(format('(%L)', key), ', ' order by sort) from erp.concepts")
checks=$(q "select string_agg(format('(%L)', code), ', ' order by sort) from erp.audit_checks")
sources=$(q "select string_agg(format('(%L)', key), ', ' order by key collate \"C\") from erp.sources")
# v0.60.5 (SEG-15) · seguridad de la base: RLS, políticas y permisos
rls=$(q "select string_agg(format('(%L)', c.relname), ', ' order by c.relname collate \"C\")
         from pg_class c where c.relnamespace = 'erp'::regnamespace and c.relkind in ('r', 'p') and c.relrowsecurity")
pols=$(q "select string_agg(format('(%L, %L, %L, %L)', tablename, policyname, cmd,
                 md5(array_to_string(roles, ',') || '|' || coalesce(qual, '') || '|' || coalesce(with_check, ''))), E',\n  ' order by tablename collate \"C\", policyname collate \"C\")
          from pg_policies where schemaname = 'erp'")
tgr=$(q "select string_agg(format('(%L, %L, %L)', c.relname, r.rol, x.privs), E',\n  ' order by c.relname collate \"C\", r.rol)
         from pg_class c cross join (values ('anon'), ('authenticated')) r(rol)
         cross join lateral (select concat_ws(',',
             case when has_table_privilege(r.rol, c.oid, 'select') then 'select' end,
             case when has_table_privilege(r.rol, c.oid, 'insert') then 'insert' end,
             case when has_table_privilege(r.rol, c.oid, 'update') then 'update' end,
             case when has_table_privilege(r.rol, c.oid, 'delete') then 'delete' end) privs) x
         where c.relnamespace = 'erp'::regnamespace and c.relkind in ('r', 'v', 'p')")
fgr=$(q "select string_agg(format('(%L, %L)', p.oid::regprocedure::text, r.rol), E',\n  ' order by p.oid::regprocedure::text collate \"C\", r.rol)
         from pg_proc p cross join (values ('anon'), ('authenticated')) r(rol)
         where p.pronamespace = 'erp'::regnamespace and has_function_privilege(r.rol, p.oid, 'execute')")
# v0.60.8 (SEG-25) · el puente de Power BI: las vistas y funciones del esquema bi (las lee solo powerbi_reader)
bis=$(q "select coalesce(string_agg(format('(%L, %L)', x.name, x.kind), ', ' order by x.name collate \"C\"), '(null, null)') from (
           select c.relname as name, 'vista' as kind from pg_class c
           where to_regnamespace('bi') is not null and c.relnamespace = to_regnamespace('bi') and c.relkind in ('v', 'r', 'm')
           union all
           select p.oid::regprocedure::text, 'función' from pg_proc p
           where to_regnamespace('bi') is not null and p.pronamespace = to_regnamespace('bi')) x")

cat > "$out" <<SQL
-- =====================================================================
-- DIAGNÓSTICO DE SUPABASE · migraciones 0001 … ${last} (GENERADO por scripts/generar-diagnostico.sh: no editar)
-- ---------------------------------------------------------------------
-- Pégalo en el SQL Editor de Supabase y pulsa Run. SOLO LEE: no cambia nada.
-- Devuelve una fila por cada diferencia con el repositorio. Ninguna fila («No rows returned») = todo al día.
-- Si sale algo, NO repitas migraciones antiguas (cambian funciones que otras posteriores ya modificaron):
-- pide una reparación con solo lo que falta, en su versión vigente (como reparacion-paso204.sql en la v0.40.0).
-- =====================================================================
with
r(name, kind) as (values ${rels}),
f(sig, hash) as (values
  ${fns}),
c(key) as (values ${concepts}),
k(code) as (values ${checks}),
s(key) as (values ${sources}),
rls(name) as (values ${rls}),
pol(tbl, name, cmd, hash) as (values
  ${pols}),
tg(tbl, rol, privs) as (values
  ${tgr}),
fg(sig, rol) as (values
  ${fgr}),
bi(name, kind) as (values ${bis}),
mine as (select p.oid::regprocedure::text sig, md5(replace(p.prosrc, E'\\r', '')) hash from pg_proc p where p.pronamespace = 'erp'::regnamespace),
rel as (select c.relname from pg_class c where c.relnamespace = 'erp'::regnamespace and c.relkind in ('r', 'v', 'p'))
select r.kind as tipo, r.name as nombre, 'falta' as problema from r where r.name not in (select relname from rel)
union all
select 'función', f.sig, case when m.sig is null then 'falta' else 'distinta' end
from f left join mine m on m.sig = f.sig where m.hash is distinct from f.hash
union all
select 'función', m.sig, 'sobra (versión antigua)' from mine m where m.sig not in (select sig from f)
union all
select 'concepto', c.key, 'falta' from c
where to_regclass('erp.concepts') is not null and not exists (select 1 from erp.concepts x where x.key = c.key)
union all
select 'comprobación', k.code, 'falta' from k
where to_regclass('erp.audit_checks') is not null and not exists (select 1 from erp.audit_checks x where x.code = k.code)
union all
select 'fuente', s.key, 'falta' from s
where to_regclass('erp.sources') is not null and not exists (select 1 from erp.sources x where x.key = s.key)
-- v0.60.5 (SEG-15) · seguridad
union all
select 'seguridad', 'tabla ' || rls.name, 'sin RLS' from rls
join pg_class c on c.relname = rls.name and c.relnamespace = 'erp'::regnamespace where not c.relrowsecurity
union all
select 'seguridad', 'política ' || p.tbl || '.' || p.name || ' (' || p.cmd || ')',
       case when x.policyname is null then 'falta' else 'distinta' end
from pol p left join pg_policies x on x.schemaname = 'erp' and x.tablename = p.tbl and x.policyname = p.name
where x.policyname is null or p.cmd <> x.cmd
   or p.hash <> md5(array_to_string(x.roles, ',') || '|' || coalesce(x.qual, '') || '|' || coalesce(x.with_check, ''))
union all
select 'seguridad', 'política ' || x.tablename || '.' || x.policyname, 'sobra'
from pg_policies x where x.schemaname = 'erp' and not exists (select 1 from pol p where p.tbl = x.tablename and p.name = x.policyname)
union all
select 'seguridad', 'permisos de ' || tg.rol || ' en ' || tg.tbl,
       'tiene «' || coalesce(nullif(now_.privs, ''), 'nada') || '» y debe tener «' || coalesce(nullif(tg.privs, ''), 'nada') || '»'
from tg join pg_class c on c.relname = tg.tbl and c.relnamespace = 'erp'::regnamespace
cross join lateral (select concat_ws(',',
    case when has_table_privilege(tg.rol, c.oid, 'select') then 'select' end,
    case when has_table_privilege(tg.rol, c.oid, 'insert') then 'insert' end,
    case when has_table_privilege(tg.rol, c.oid, 'update') then 'update' end,
    case when has_table_privilege(tg.rol, c.oid, 'delete') then 'delete' end) privs) now_
where now_.privs <> tg.privs
union all
select 'seguridad', 'ejecutar ' || m.sig || ' (' || r.rol || ')', 'permiso de más'
from mine m cross join (values ('anon'), ('authenticated')) r(rol)
where has_function_privilege(r.rol, m.sig::regprocedure, 'execute')
  and not exists (select 1 from fg where fg.sig = m.sig and fg.rol = r.rol)
union all
select 'seguridad', 'ejecutar ' || fg.sig || ' (' || fg.rol || ')', 'permiso de menos'
from fg join mine m on m.sig = fg.sig
where not has_function_privilege(fg.rol, fg.sig::regprocedure, 'execute')
-- v0.60.8 (SEG-25) · nadie más entra en erp, nadie de la web entra en bi, y powerbi_reader solo lee bi
union all
select 'seguridad', 'el rol ' || r.rolname || ' entra en el esquema erp', 'no debe (solo authenticated y los roles del sistema)'
from pg_roles r
where has_schema_privilege(r.oid, 'erp', 'usage') and not r.rolsuper and not r.rolbypassrls
  and r.rolname not in ('authenticated', 'service_role', 'postgres', 'supabase_admin', 'dashboard_user')
  and r.rolname not like 'pg\\_%' and r.rolname not like 'supabase\\_%'
  and r.oid <> (select nspowner from pg_namespace where nspname = 'erp')
-- v0.60.10 (SEG-26) · un rol que salta el RLS (superusuario o bypassrls) y entra en erp: solo los del sistema
union all
select 'seguridad', 'el rol ' || r.rolname || ' salta el RLS y entra en el esquema erp', 'no debe (solo los roles del sistema)'
from pg_roles r
where (r.rolsuper or (r.rolbypassrls and has_schema_privilege(r.oid, 'erp', 'usage')))
  and r.rolname not in ('service_role', 'postgres', 'supabase_admin', 'dashboard_user') and r.rolname <> current_user
  and r.rolname not like 'pg\\_%' and r.rolname not like 'supabase\\_%'
union all
select 'seguridad', 'el rol ' || w.rol || ' entra en el esquema bi', 'no debe (solo powerbi_reader)'
from (values ('anon'), ('authenticated')) w(rol)
where to_regnamespace('bi') is not null and has_schema_privilege(w.rol, 'bi', 'usage')
union all
select 'seguridad', 'el esquema bi abierto a public', 'no debe'
from pg_namespace n cross join lateral aclexplode(n.nspacl) a
where n.nspname = 'bi' and a.grantee = 0 and a.privilege_type = 'USAGE'
union all
select 'seguridad', 'powerbi_reader: ' || x.what, 'no debe'
from pg_roles r cross join lateral (values
    ('superusuario', r.rolsuper), ('salta el RLS', r.rolbypassrls), ('crea roles', r.rolcreaterole),
    ('es miembro de otro rol', exists (select 1 from pg_auth_members m where m.member = r.oid))) x(what, bad)
where r.rolname = 'powerbi_reader' and x.bad
union all
select 'seguridad', 'bi: ' || bi.kind || ' ' || bi.name, 'falta, o powerbi_reader no la puede leer'
from bi
where bi.name is not null and exists (select 1 from pg_roles where rolname = 'powerbi_reader')
  and not case bi.kind
        when 'vista' then to_regclass('bi.' || quote_ident(bi.name)) is not null
                          and has_table_privilege('powerbi_reader', to_regclass('bi.' || quote_ident(bi.name)), 'select')
        else to_regprocedure(bi.name) is not null and has_function_privilege('powerbi_reader', to_regprocedure(bi.name), 'execute') end
union all
select 'seguridad', 'bi: ' || o.kind || ' ' || o.name || ' (anon o authenticated)', 'permiso de más'
from (select c.relname as name, 'vista' as kind, c.oid as id, true as rel from pg_class c
      where to_regnamespace('bi') is not null and c.relnamespace = to_regnamespace('bi') and c.relkind in ('v', 'r', 'm')
      union all
      select p.oid::regprocedure::text, 'función', p.oid, false from pg_proc p
      where to_regnamespace('bi') is not null and p.pronamespace = to_regnamespace('bi')) o
where case when o.rel then has_table_privilege('anon', o.id, 'select') or has_table_privilege('authenticated', o.id, 'select')
           else has_function_privilege('anon', o.id, 'execute') or has_function_privilege('authenticated', o.id, 'execute') end
order by 1, 2;
SQL
echo "✔ ${out}: $(echo "$fns" | wc -l) funciones, $(echo "$rels" | grep -o "'tabla'\|'vista'" | wc -l) tablas y vistas (migraciones hasta ${last})"
