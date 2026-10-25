-- =====================================================================
-- erp.loan_status · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_status(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('loan_id', l.id, 'code', l.code, 'kind', l.kind, 'description', l.description,
      'lender', l.lender, 'status', l.status, 'start_date', l.start_date, 'periods', l.periods, 'frequency', l.frequency,
      'instalment', l.instalment, 'net_amount', l.net_amount, 'effective_rate_year', l.effective_rate_year,
      'paid', (pos->>'paid')::int, 'short', (pos->>'short')::numeric, 'long', (pos->>'long')::numeric, 'accrued', (pos->>'accrued')::numeric,
      'next', erp.loan_next_instalment(l.id)) order by l.code)
    from erp.loans l cross join lateral (select erp.loan_position(l.id) pos) z
    where l.company_id = p_company and l.status <> 'cancelled'), '[]');
end $function$
;
