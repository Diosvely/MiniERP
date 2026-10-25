-- =====================================================================
-- erp.loan_year_end_preview · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_year_end_preview(p_company uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare r jsonb := '[]'; l erp.loans; a jsonb; pos jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  for l in select * from erp.loans where company_id = p_company and status = 'active' and start_date <= p_date order by code loop
    a := erp.loan_accrual_amount(l.id, p_date); pos := erp.loan_position(l.id);
    r := r || jsonb_build_object('loan_id', l.id, 'code', l.code, 'kind', l.kind, 'description', l.description,
      'accrual', coalesce((a->>'amount')::numeric, 0), 'accrual_n', a->'n', 'fraction', a->'fraction', 'days', a->'days',
      'overdue', coalesce((a->>'overdue')::boolean, false), 'overdue_due_date', case when (a->>'overdue')::boolean then a->'due_date' end,
      'short_now', (pos->>'short')::numeric, 'short_target', erp.loan_short_target(l.id, p_date),
      'reclassification', erp.loan_short_target(l.id, p_date) - (pos->>'short')::numeric,
      'outstanding', (pos->>'short')::numeric + (pos->>'long')::numeric, 'accrued', (pos->>'accrued')::numeric);
  end loop;
  return jsonb_build_object('date', p_date, 'loans', r,
    'accrual_total', (select coalesce(sum((x->>'accrual')::numeric), 0) from jsonb_array_elements(r) x),
    'reclassification_total', (select coalesce(sum((x->>'reclassification')::numeric), 0) from jsonb_array_elements(r) x),
    'overdue', (select count(*) from jsonb_array_elements(r) x where (x->>'overdue')::boolean));
end $function$
;
