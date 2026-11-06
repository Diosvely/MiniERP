-- =====================================================================
-- erp.fs_model_line_set · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0089_balance_models   →   la vigente es la de 0089_balance_models
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_model_line_set(p_model text)
 RETURNS TABLE(code text, parent text, sort integer, label text, label_en text, side text, is_total boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
  select l.code, l.parent, l.sort, l.label, l.label_en, l.side, l.is_total
  from erp.fs_lines l where p_model = 'pymes' and l.statement = 'balance'
  union all
  select l.code, l.parent, l.sort, l.label, l.label_en, l.side, l.is_total
  from erp.fs_model_lines l where p_model <> 'pymes' and l.model = p_model;
$function$
;
