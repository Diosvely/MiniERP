-- =====================================================================
-- erp.quality_card · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0084_quality_dashboard   →   la vigente es la de 0084_quality_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.quality_card(p_company uuid, p_year integer, p_to date, p_drafts boolean)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', q.code, 'label', d.label, 'label_en', d.label_en, 'help', d.help, 'help_en', d.help_en,
           'unit', d.unit, 'link', d.link, 'value', q.value, 'extra', q.extra, 'severity', q.severity) order by d.sort), '[]')
  from erp.quality_checks(p_company, p_year, p_to, p_drafts) q
  join erp.quality_check_defs d on d.code = q.code;
$function$
;
