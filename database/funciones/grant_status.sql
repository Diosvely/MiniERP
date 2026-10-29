-- =====================================================================
-- erp.grant_status · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_status(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('grant_id', g.id, 'code', g.code, 'kind', g.kind, 'description', g.description,
      'grantor', g.grantor, 'amount', g.amount, 'grant_date', g.grant_date, 'refundable', g.refundable, 'condition_due', g.condition_due,
      'tax_rate', g.tax_rate, 'status', g.status, 'asset_code', (select code from erp.fixed_assets where id = g.asset_id),
      'asset_name', (select name from erp.fixed_assets where id = g.asset_id),
      'unconditional', (pos->>'unconditional')::boolean, 'collected', (pos->>'collected')::boolean,
      'imputed', (pos->>'imputed')::numeric, 'pending', g.amount - (pos->>'imputed')::numeric,
      'deferred_tax', (pos->>'tax_recognised')::numeric - (pos->>'tax_reversed')::numeric) order by g.code)
    from erp.grants g cross join lateral (select erp.grant_position(g.id) pos) z
    where g.company_id = p_company and g.status <> 'cancelled'), '[]');
end $function$
;
