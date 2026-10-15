-- =====================================================================
-- erp.cf_indirect_detail · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow   →   la vigente es la de 0022_cash_flow
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_indirect_detail(p_company uuid, p_year integer)
 RETURNS TABLE(line_code text, account_no text, account_name text, account_name_en text, amount numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with f as (select * from erp.cf_account_flows(p_company, p_year))
  -- 1. Resultado antes de impuestos: todas las cuentas de la PyG salvo el impuesto sobre beneficios
  select 'IA1', account_no, account_name, account_name_en, flow from f where in_result
  -- 2. Ajustes: se quita del resultado lo que no es de explotación…
  union all
  select adjust_line, account_no, account_name, account_name_en, -flow from f where in_result and adjust_line is not null
  -- …y cada flujo va a su línea (las cuentas de balance, el impuesto y lo que se quitó del resultado)
  union all
  select home_line, account_no, account_name, account_name_en, flow from f
  where not in_result or (home_line <> 'IA1' and adjust_line is not null);
$function$
;
