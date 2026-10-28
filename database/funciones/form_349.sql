-- =====================================================================
-- erp.form_349 · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0052_forms_347_349   →   la vigente es la de 0052_forms_347_349
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.form_349(p_company uuid, p_year integer, p_quarter integer)
 RETURNS TABLE(section text, partner_id uuid, partner_name text, vat_registration_no text, op_key text, amount numeric, corrected_period text, previously_declared numeric)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare v_type text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
        v_from date := erp.quarter_start(p_year, p_quarter); v_to date := erp.quarter_end(p_year, p_quarter);
begin
  if p_quarter not between 1 and 4 then raise exception 'Invalid quarter: %', p_quarter; end if;
  if v_type = 'IGIC' then return; end if;   -- Canarias no forma parte del territorio de aplicación del IVA de la UE
  return query
  with l as (
    select x.*, o.posting_date as original_date
    from erp.intra_eu_lines(p_company) x
    left join erp.invoices o on o.id = x.corrected_invoice_id
  ), ops as (   -- las del trimestre (y las rectificativas de facturas del mismo trimestre)
    select l.partner_id, l.op_key, sum(l.amount) as amount
    from l where l.posting_date between v_from and v_to
      and (l.corrected_invoice_id is null or l.original_date between v_from and v_to)
    group by 1, 2
  ), rect as (  -- rectificativas de facturas de un trimestre anterior
    select l.partner_id, l.op_key, extract(year from l.original_date)::int as y, extract(quarter from l.original_date)::int as q,
           sum(l.amount) as correction
    from l where l.posting_date between v_from and v_to and l.corrected_invoice_id is not null
      and l.original_date < v_from
    group by 1, 2, 3, 4
  )
  select 'operation', o.partner_id, bp.name, bp.vat_registration_no, o.op_key, o.amount, null::text, null::numeric
  from ops o join erp.business_partners bp on bp.id = o.partner_id where o.amount <> 0
  union all
  select 'rectification', r.partner_id, bp.name, bp.vat_registration_no, r.op_key,
         d.declared + r.correction, r.q || 'T ' || r.y, d.declared
  from rect r join erp.business_partners bp on bp.id = r.partner_id
  cross join lateral (
    select coalesce(sum(l.amount), 0) as declared from l
    where l.partner_id = r.partner_id and l.op_key = r.op_key
      and l.posting_date between erp.quarter_start(r.y, r.q) and erp.quarter_end(r.y, r.q)
      and (l.corrected_invoice_id is null or l.original_date between erp.quarter_start(r.y, r.q) and erp.quarter_end(r.y, r.q))
  ) d
  order by 1, 3, 5;
end $function$
;
