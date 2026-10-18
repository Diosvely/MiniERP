-- =====================================================================
-- erp.provision_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.provision_account(p_company uuid, p_kind text, p_term text)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select erp.adjust_account(p_company, erp.provision_prefix(p_kind, p_term), case erp.provision_prefix(p_kind, p_term)
    when '141' then 'Provisión para impuestos' when '142' then 'Provisión para otras responsabilidades'
    when '5292' then 'Provisión a corto plazo para impuestos' when '5293' then 'Provisión a corto plazo para otras responsabilidades'
    else 'Provisión para otras operaciones comerciales' end);
$function$
;
