-- =====================================================================
-- erp.provision_prefix · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.provision_prefix(p_kind text, p_term text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_kind when 'taxes' then case p_term when 'long' then '141' else '5292' end
                     when 'liabilities' then case p_term when 'long' then '142' else '5293' end
                     else '4999' end;
$function$
;
