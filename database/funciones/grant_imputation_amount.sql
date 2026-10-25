-- =====================================================================
-- erp.grant_imputation_amount · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_imputation_amount(p_grant uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare g erp.grants; pos jsonb; a erp.fixed_assets; v_from date; v_dep numeric; v_target numeric; v_tax numeric; v_pending boolean;
begin
  select * into g from erp.grants where id = p_grant;
  pos := erp.grant_position(p_grant);
  if g.kind <> 'capital' or g.status <> 'active' or not (pos->>'unconditional')::boolean then return null; end if;
  select * into a from erp.fixed_assets where id = g.asset_id;
  select starting_date into v_from from erp.fiscal_years where company_id = g.company_id and g.grant_date between starting_date and ending_date;
  select coalesce(sum(d.amount), 0) into v_dep from erp.asset_depreciations d
  where d.asset_id = a.id and d.period_end between v_from and p_date;
  v_pending := a.status = 'active' and erp.asset_depr_at(a.id, p_date) > erp.asset_posted(a.id);
  v_target := least(g.amount, round(g.amount * v_dep / a.cost, 2));
  v_tax := round(v_target * g.tax_rate / 100, 2);
  return jsonb_build_object('amount', greatest(0, v_target - (pos->>'imputed')::numeric),
    'tax', greatest(0, least(v_tax, (pos->>'tax_recognised')::numeric) - (pos->>'tax_reversed')::numeric),
    'depreciation', v_dep, 'cost', a.cost, 'pct', case when a.cost > 0 then round(v_dep / a.cost * 100, 4) end,
    'depreciation_pending', v_pending, 'asset_code', a.code);
end $function$
;
