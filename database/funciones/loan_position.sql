-- =====================================================================
-- erp.loan_position · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_position(p_loan uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select jsonb_build_object(
    'short', coalesce(sum(case kind when 'start' then short_part when 'reclassification' then amount when 'payment' then -short_part else 0 end), 0),
    'long',  coalesce(sum(case kind when 'start' then long_part when 'reclassification' then -amount when 'payment' then -long_part else 0 end), 0),
    'accrued', coalesce(sum(case kind when 'accrual' then amount when 'payment' then -accrued_used else 0 end), 0),
    'paid', coalesce(max(n) filter (where kind = 'payment'), 0))
  from erp.loan_events where loan_id = p_loan and status = 'posted';
$function$
;
