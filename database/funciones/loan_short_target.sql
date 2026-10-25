-- =====================================================================
-- erp.loan_short_target · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_short_target(p_loan uuid, p_date date)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select coalesce(sum(s.reduction), 0) from erp.loan_schedule s
  where s.loan_id = p_loan and s.n > (erp.loan_position(p_loan)->>'paid')::int and s.due_date <= p_date + interval '1 year';
$function$
;
