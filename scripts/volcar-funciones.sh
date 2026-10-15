#!/usr/bin/env bash
# =====================================================================
# VOLCADO DE FUNCIONES: la versión ACTUAL de cada función del esquema erp, una por fichero, para estudiarla
# sin rastrear migraciones (post_invoice se ha redefinido en 4 migraciones, tax_settlement_calc en 4…).
#   1. base de datos nueva: supabase_stub.sql + todas las migraciones en orden
#   2. database/funciones/<nombre>.sql  ← pg_get_functiondef (con los comentarios del cuerpo, tal cual)
#      con una cabecera: en qué migraciones se define (la última es la vigente)
#   3. database/funciones/README.md     ← índice
# Los ficheros se GENERAN: no se editan a mano. Se regeneran al cerrar cada versión:
#   scripts/volcar-funciones.sh
# Conexión: las variables estándar de PostgreSQL (PGHOST, PGPORT, PGUSER, PGPASSWORD), como test-db.sh.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

db="volcado_funciones"
out="database/funciones"
dropdb --if-exists "$db" >/dev/null 2>&1
createdb "$db"
trap 'dropdb --if-exists "$db" >/dev/null 2>&1' EXIT
{
  psql -q -X -v ON_ERROR_STOP=1 -d "$db" -f database/tests/supabase_stub.sql
  for f in database/migrations/*.sql; do psql -q -X -v ON_ERROR_STOP=1 -d "$db" -f "$f"; done
} > /dev/null 2>&1

rm -rf "$out"
mkdir -p "$out"
q="select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'erp' group by p.proname order by p.proname"
index=""
total=0
for name in $(psql -X -At -d "$db" -c "$q"); do
  migs=$(grep -l -E "function erp\.${name}\(" database/migrations/*.sql | xargs -n1 basename | sed 's/\.sql$//' | tr '\n' ' ' | sed 's/ $//')
  n=$(echo "$migs" | wc -w)
  last=${migs##* }
  kind=$(psql -X -At -d "$db" -c "select case when bool_or(p.prorettype = 'trigger'::regtype) then 'trigger'
           when bool_or(p.prosecdef) then 'security definer' else 'invoker' end
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'erp' and p.proname = '$name'")
  {
    echo "-- ====================================================================="
    echo "-- erp.${name} · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)"
    echo "-- Definida en: ${migs:-?}   →   la vigente es la de ${last:-?}"
    echo "-- ====================================================================="
    echo
    psql -X -At -d "$db" -c "select string_agg(pg_get_functiondef(p.oid) || ';', E'\n\n' order by p.oid)
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'erp' and p.proname = '$name'"
  } > "$out/${name}.sql"
  index+="| [\`${name}\`](${name}.sql) | ${n} | ${last:-?} | ${kind} |"$'\n'
  total=$((total + 1))
done

{
  echo "# Funciones del esquema erp (versión vigente)"
  echo
  echo "Generado por \`scripts/volcar-funciones.sh\` con las migraciones \`0001\` … \`$(ls database/migrations | tail -1 | cut -c1-4)\`."
  echo "No se edita a mano: el código fuente son las migraciones. Esto es para **estudiar** cada función en su forma"
  echo "actual sin rastrear sus redefiniciones."
  echo
  echo "- **Versiones:** en cuántas migraciones se ha definido. Más de una = la regla ha cambiado; la historia está en"
  echo "  los ADR y en el CHANGELOG."
  echo "- **Tipo:** *invoker* (se ejecuta con los permisos de quien llama: manda la RLS), *security definer* (con los del"
  echo "  dueño: comprueba ella misma los permisos) o *trigger*."
  echo
  echo "$total funciones."
  echo
  echo "| Función | Versiones | Vigente en | Tipo |"
  echo "|---|---|---|---|"
  printf "%s" "$index"
} > "$out/README.md"

echo "✓ $total funciones en $out/"
