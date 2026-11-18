#!/usr/bin/env bash
# =====================================================================
# Prueba del diagnóstico de Supabase (v0.60.5, SEG-15)
#   1. Una base nueva con todas las migraciones → el diagnóstico NO devuelve ninguna fila.
#   2. La misma base con una corrección de permisos «a medias» (la de la v0.60.3, SEG-09, sin su revoke y con su
#      política antigua) y una tabla sin RLS → el diagnóstico SÍ las ve.
#   3. El diagnóstico guardado en el repositorio está al día (es el que genera el script ahora).
# Conexión: las variables estándar de PostgreSQL, como test-db.sh. La usa la integración continua.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

saved=$(mktemp)
cp database/diagnostico-supabase.sql "$saved"
bash scripts/generar-diagnostico.sh > /dev/null
if ! diff -q "$saved" database/diagnostico-supabase.sql > /dev/null; then
  cp "$saved" database/diagnostico-supabase.sql
  echo "✗ database/diagnostico-supabase.sql no está al día: ejecuta bash scripts/generar-diagnostico.sh"; exit 1
fi

db="t_diagnostico"
dropdb --if-exists "$db" >/dev/null 2>&1
createdb "$db"
trap 'dropdb --if-exists "$db" >/dev/null 2>&1; rm -f "$saved"' EXIT
{
  psql -q -X -v ON_ERROR_STOP=1 -d "$db" -f database/tests/supabase_stub.sql
  for f in database/migrations/*.sql; do psql -q -X -v ON_ERROR_STOP=1 -d "$db" -f "$f"; done
} > /dev/null 2>&1

rows=$(psql -X -At -v ON_ERROR_STOP=1 -d "$db" -f database/diagnostico-supabase.sql)
[[ -z "$rows" ]] || { echo "✗ base al día, pero el diagnóstico devuelve filas:"; echo "$rows"; exit 1; }
echo "✓ base al día: el diagnóstico no devuelve ninguna fila"

psql -q -X -v ON_ERROR_STOP=1 -d "$db" -c "
  grant insert, update, delete on erp.company_users to authenticated;
  create policy manage on erp.company_users for all to authenticated using (true);
  alter table erp.ai_feedback disable row level security;" > /dev/null
rows=$(psql -X -At -v ON_ERROR_STOP=1 -d "$db" -f database/diagnostico-supabase.sql)
for want in "permisos de authenticated en company_users" "política company_users.manage|sobra" "tabla ai_feedback|sin RLS"; do
  grep -qF "$want" <<< "$rows" || { echo "✗ el diagnóstico no ve: $want"; echo "$rows"; exit 1; }
done
echo "✓ permisos de más, una política que sobra y una tabla sin RLS: el diagnóstico los ve"

# v0.60.8 (SEG-25) · Power BI: un rol de lectura que entra en erp y una vista de bi abierta a la web
psql -q -X -v ON_ERROR_STOP=1 -d "$db" -c "
  grant usage on schema erp to powerbi_reader;
  grant usage on schema bi to authenticated;
  grant select on all tables in schema bi to authenticated;" > /dev/null
rows=$(psql -X -At -v ON_ERROR_STOP=1 -d "$db" -f database/diagnostico-supabase.sql)
for want in "el rol powerbi_reader entra en el esquema erp" "el rol authenticated entra en el esquema bi" "(anon o authenticated)|permiso de más"; do
  grep -qF "$want" <<< "$rows" || { echo "✗ el diagnóstico no ve: $want"; echo "$rows"; exit 1; }
done
echo "✓ Power BI: un rol de lectura en erp y bi abierto a la web, el diagnóstico los ve"

# v0.60.10 (SEG-26) · un rol que salta el RLS y entra en erp
psql -q -X -v ON_ERROR_STOP=1 -d "$db" -c "
  set client_min_messages = warning;
  drop role if exists t_salta_rls;
  create role t_salta_rls nologin bypassrls;
  grant usage on schema erp to t_salta_rls;" > /dev/null
rows=$(psql -X -At -v ON_ERROR_STOP=1 -d "$db" -f database/diagnostico-supabase.sql)
psql -q -X -d "$db" -c "revoke usage on schema erp from t_salta_rls; drop role t_salta_rls;" > /dev/null 2>&1 || true
grep -qF "el rol t_salta_rls salta el RLS y entra en el esquema erp" <<< "$rows" || { echo "✗ el diagnóstico no ve un rol que salta el RLS"; echo "$rows"; exit 1; }
echo "✓ SEG-26: un rol que salta el RLS y entra en erp, el diagnóstico lo ve"

# v0.60.10 · si a la base le falta una función que tiene permisos en el repositorio, el diagnóstico la lista como
# «falta» y no se para con «function … does not exist»
psql -q -X -v ON_ERROR_STOP=1 -d "$db" -c "drop function erp.closing_equity_name(text);" > /dev/null
rows=$(psql -X -At -v ON_ERROR_STOP=1 -d "$db" -f database/diagnostico-supabase.sql) || { echo "✗ el diagnóstico se para si falta una función"; exit 1; }
grep -qF "función|erp.closing_equity_name(text)|falta" <<< "$rows" || { echo "✗ el diagnóstico no lista la función que falta"; echo "$rows"; exit 1; }
echo "✓ una función que falta sale como «falta», sin parar el diagnóstico"
