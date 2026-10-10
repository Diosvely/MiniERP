#!/usr/bin/env bash
# =====================================================================
# Pruebas de la base de datos: cada test_*.sql en una base NUEVA
#   1. supabase_stub.sql (lo mínimo de Supabase: auth.uid(), roles anon / authenticated…)
#   2. todas las migraciones en orden
#   3. el test
# Cada test necesita una base limpia: todos insertan los mismos usuarios de prueba.
# Uso:  scripts/test-db.sh               → todas las pruebas
#       scripts/test-db.sh fase20        → solo las que contengan "fase20" en el nombre
# Conexión: las variables estándar de PostgreSQL (PGHOST, PGPORT, PGUSER, PGPASSWORD).
# La usan la integración continua (.github/workflows/ci.yml) y tú en local.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

filter="${1:-}"
passed=0
failed=()

for t in $(ls database/tests/test_*.sql | sort -V); do
  name="$(basename "$t" .sql)"
  [[ -n "$filter" && "$name" != *"$filter"* ]] && continue
  db="t_${name}"
  dropdb --if-exists "$db" >/dev/null 2>&1
  createdb "$db"
  {
    psql -q -X -v ON_ERROR_STOP=1 -d "$db" -f database/tests/supabase_stub.sql
    for f in database/migrations/*.sql; do psql -q -X -v ON_ERROR_STOP=1 -d "$db" -f "$f"; done
    psql -q -X -v ON_ERROR_STOP=1 -d "$db" -f "$t"
  } > "/tmp/${name}.log" 2>&1 && ok=1 || ok=0
  dropdb --if-exists "$db" >/dev/null 2>&1
  if [[ $ok == 1 ]]; then
    passed=$((passed + 1)); echo "✓ $name"
  else
    failed+=("$name"); echo "✗ $name"; grep -E "ERROR|FAIL|assert" "/tmp/${name}.log" | head -5 | sed 's/^/    /'
  fi
done

echo
echo "Pruebas superadas: $passed · fallidas: ${#failed[@]}"
[[ ${#failed[@]} -eq 0 ]] || { echo "Fallan: ${failed[*]}"; exit 1; }
