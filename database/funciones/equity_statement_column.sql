-- =====================================================================
-- erp.equity_statement_column · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0065_grants_integration   →   la vigente es la de 0065_grants_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_statement_column(p_account_no text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when p_account_no ~ '^10' then 'capital'
              when p_account_no ~ '^110' then 'premium'
              when p_account_no ~ '^11' then 'reserves'
              when p_account_no ~ '^129' then 'result'
              when p_account_no ~ '^12' then 'prior_results'
              when p_account_no ~ '^13' then 'grants'
              when p_account_no ~ '^557' then 'interim'
              when p_account_no ~ '^[67]' then 'result'
              when p_account_no ~ '^[89]' then 'grants' end;
$function$
;
