-- =====================================================================
-- erp.grant_year_end_preview · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_year_end_preview(p_company uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare r jsonb := '[]'; g erp.grants; v jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  for g in select * from erp.grants where company_id = p_company and kind = 'capital' and status = 'active' and grant_date <= p_date order by code loop
    v := erp.grant_imputation_amount(g.id, p_date);
    r := r || jsonb_build_object('grant_id', g.id, 'code', g.code, 'description', g.description, 'amount', g.amount,
      'unconditional', v is not null, 'imputation', coalesce((v->>'amount')::numeric, 0), 'tax', coalesce((v->>'tax')::numeric, 0),
      'pct', v->'pct', 'asset_code', v->>'asset_code', 'depreciation_pending', coalesce((v->>'depreciation_pending')::boolean, false),
      'imputed', (erp.grant_position(g.id)->>'imputed')::numeric);
  end loop;
  return jsonb_build_object('date', p_date, 'grants', r,
    'imputation_total', (select coalesce(sum((x->>'imputation')::numeric), 0) from jsonb_array_elements(r) x),
    'tax_total', (select coalesce(sum((x->>'tax')::numeric), 0) from jsonb_array_elements(r) x),
    'depreciation_pending', (select count(*) from jsonb_array_elements(r) x where (x->>'depreciation_pending')::boolean));
end $function$
;
