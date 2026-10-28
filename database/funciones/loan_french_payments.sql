-- =====================================================================
-- erp.loan_french_payments · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_french_payments(p_principal numeric, p_rate numeric, p_n integer)
 RETURNS numeric[]
 LANGUAGE plpgsql
 IMMUTABLE
 SET jit TO 'off'
AS $function$
declare v_pay numeric; v_bal numeric := p_principal; v_int numeric; r numeric[] := '{}'; t int;
begin
  v_pay := case when p_rate = 0 then round(p_principal / p_n, 2)
                else round(p_principal * p_rate / (1 - power(1 + p_rate, -p_n)), 2) end;
  for t in 1..p_n loop
    v_int := round(v_bal * p_rate, 2);
    if t = p_n then r := r || (v_bal + v_int); else r := r || v_pay; v_bal := v_bal - (v_pay - v_int); end if;
  end loop;
  return r;
end $function$
;
