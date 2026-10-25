-- =====================================================================
-- erp.grant_position · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_position(p_grant uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select jsonb_build_object(
    'unconditional', coalesce(bool_or(v.kind = 'unconditional'), false) or (not g.refundable and coalesce(bool_or(v.kind = 'concession'), false)),
    'collected', coalesce(bool_or(v.kind = 'collection' or (v.kind = 'concession' and v.collected)), false),
    'imputed', coalesce(sum(v.amount) filter (where v.kind in ('imputation', 'disposal')), 0),
    'tax_reversed', coalesce(sum(v.tax_amount) filter (where v.kind in ('imputation', 'disposal')), 0),
    'tax_recognised', coalesce(sum(v.tax_amount) filter (where v.kind in ('concession', 'unconditional')), 0),
    'last_date', max(v.event_date), 'events', count(v.id))
  from erp.grants g left join erp.grant_events v on v.grant_id = g.id and v.status = 'posted'
  where g.id = p_grant group by g.refundable;
$function$
;
