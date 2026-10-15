-- =====================================================================
-- erp.controlled_lines · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0036_controlled_accounts   →   la vigente es la de 0036_controlled_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.controlled_lines(p_lines jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('line', x.ord, 'account_no', x.v->>'account_no',
                                               'modules', to_jsonb(r.modules), 'side', r.side) order by x.ord), '[]')
  from jsonb_array_elements(p_lines) with ordinality x(v, ord)
  cross join lateral erp.control_rule_for(x.v->>'account_no') r
  where r.account_prefix is not null and cardinality(r.modules) > 0
    and (r.side = 'both'
         or (r.side = 'debit'  and coalesce((x.v->>'debit')::numeric, 0) > 0)
         or (r.side = 'credit' and coalesce((x.v->>'credit')::numeric, 0) > 0));
$function$
;
