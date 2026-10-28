-- =====================================================================
-- erp.loan_present_value · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_present_value(p_pays numeric[], p_rate numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET jit TO 'off'
AS $function$
declare v numeric := 1; d numeric := round(1 / (1 + p_rate), 30); s numeric := 0; x numeric;
begin
  foreach x in array p_pays loop
    v := round(v * d, 30);
    s := s + x * v;
  end loop;
  return s;
end $function$
;
