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
rels=$(q "select string_agg(format('(%L, %L)', c.relname, case c.relkind when 'v' then 'vista' else 'tabla' end), ', ' order by c.relname)
          from pg_class c where c.relnamespace = 'erp'::regnamespace and c.relkind in ('r', 'v', 'p')")
fns=$(q "select string_agg(format('(%L, %L)', p.oid::regprocedure::text, md5(replace(p.prosrc, E'\r', ''))), E',\n  ' order by 1)
         from pg_proc p where p.pronamespace = 'erp'::regnamespace")
concepts=$(q "select string_agg(format('(%L)', key), ', ' order by sort) from erp.concepts")
checks=$(q "select string_agg(format('(%L)', code), ', ' order by sort) from erp.audit_checks")
sources=$(q "select string_agg(format('(%L)', key), ', ' order by key) from erp.sources")

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
order by 1, 2;
SQL
echo "✔ ${out}: $(echo "$fns" | wc -l) funciones, $(echo "$rels" | grep -o "'tabla'\|'vista'" | wc -l) tablas y vistas (migraciones hasta ${last})"
