-- =====================================================================
-- erp.pct_text · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0051_tax_forms   →   la vigente es la de 0051_tax_forms
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.pct_text(p numeric, p_lang text DEFAULT 'es'::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_lang when 'en' then trim_scale(p)::text else replace(trim_scale(p)::text, '.', ',') end;
$function$
;
