-- =====================================================================
-- erp.tf_row · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0051_tax_forms   →   la vigente es la de 0051_tax_forms
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tf_row(p_sort integer, p_section text, p_box text, p_concept text, p_concept_en text, p_kind text, p_amount numeric)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select jsonb_build_object('sort', p_sort, 'section', p_section, 'box', p_box, 'concept', p_concept, 'concept_en', p_concept_en,
                            'kind', p_kind, 'amount', coalesce(p_amount, 0));
$function$
;
