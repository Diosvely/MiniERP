-- =====================================================================
-- erp.loan_rows · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_rows(p_pays numeric[], p_net numeric, p_rate numeric)
 RETURNS TABLE(n integer, payment numeric, interest numeric, reduction numeric, balance numeric)
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare v_bal numeric := p_net; t int; k int := array_length(p_pays, 1);
begin
  for t in 1..k loop
    n := t; payment := p_pays[t];
    interest := case when t = k then p_pays[t] - v_bal else round(v_bal * p_rate, 2) end;
    reduction := payment - interest;
    v_bal := v_bal - reduction; balance := v_bal;
    return next;
  end loop;
end $function$
;
