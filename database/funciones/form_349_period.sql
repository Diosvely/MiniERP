-- =====================================================================
-- erp.form_349_period · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0052_forms_347_349   →   la vigente es la de 0052_forms_347_349
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.form_349_period(p_company uuid, p_year integer, p_quarter integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select case when exists (
    select 1 from erp.intra_eu_lines(p_company) x
    where x.op_key in ('E', 'S')
      and x.posting_date between erp.quarter_start(p_year, p_quarter) - interval '12 months' and erp.quarter_end(p_year, p_quarter)
    group by date_trunc('quarter', x.posting_date)
    having sum(x.amount) > 50000) then 'monthly' else 'quarterly' end;
$function$
;
