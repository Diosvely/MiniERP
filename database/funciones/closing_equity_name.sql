-- =====================================================================
-- erp.closing_equity_name · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0097_closing_ecpn_and_fixes   →   la vigente es la de 0097_closing_ecpn_and_fixes
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.closing_equity_name(p_account_no text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET jit TO 'off'
AS $function$
  select coalesce(
    case when p_account_no like '133%' then 'Ajustes por valoración en activos financieros a valor razonable con cambios en el patrimonio neto' end,
    (select a.name from erp.pgc_accounts a where p_account_no like a.account || '%' order by length(a.account) desc limit 1),
    'Subvenciones, donaciones y legados');
$function$
;
