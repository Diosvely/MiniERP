-- =====================================================================
-- erp.closing_equity_target · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0097_closing_ecpn_and_fixes   →   la vigente es la de 0097_closing_ecpn_and_fixes
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.closing_equity_target(p_account_no text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET jit TO 'off'
AS $function$
  select case
    when p_account_no ~ '^(800|802|900|902)' then '133'
    when p_account_no ~ '^(810|812|910|912)' then '1340'
    when p_account_no ~ '^(811|813|911|913)' then '1341'
    when p_account_no ~ '^(82|92)'           then '135'
    when p_account_no ~ '^(84|94)'           then '13' || substr(p_account_no, 3, 1)
    when p_account_no ~ '^83'                then '130'   -- criterio del ERP: la 83 solo la mueve el módulo de subvenciones (130)
  end;
$function$
;
