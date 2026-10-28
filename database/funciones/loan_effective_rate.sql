-- =====================================================================
-- erp.loan_effective_rate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_effective_rate(p_pays numeric[], p_net numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET jit TO 'off'
AS $function$
declare lo numeric := 0; hi numeric := 1; m numeric; k int;
begin
  if p_net <= 0 then raise exception 'The amount received must be positive'; end if;
  if (select sum(x) from unnest(p_pays) x) < p_net then raise exception 'The payments are lower than the amount received'; end if;
  if (select sum(x) from unnest(p_pays) x) = p_net then return 0; end if;
  for k in 1..110 loop
    m := round((lo + hi) / 2, 32);
    if erp.loan_present_value(p_pays, m) > p_net then lo := m; else hi := m; end if;
  end loop;
  return round((lo + hi) / 2, 30);
end $function$
;
