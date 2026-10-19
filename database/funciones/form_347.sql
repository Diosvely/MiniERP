-- =====================================================================
-- erp.form_347 · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0052_forms_347_349   →   la vigente es la de 0052_forms_347_349
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.form_347(p_company uuid, p_year integer)
 RETURNS TABLE(partner_id uuid, partner_name text, vat_registration_no text, op_key text, q1 numeric, q2 numeric, q3 numeric, q4 numeric, total numeric, missing_vat_no boolean)
 LANGUAGE sql
 STABLE
AS $function$
  with x as (
    select i.partner_id, case i.invoice_type when 'purchase' then 'A' else 'B' end as op_key,
           extract(quarter from i.posting_date)::int as q,
           -- importe total de la operación: base + impuesto repercutido + recargo (en la ISP el proveedor no repercute)
           sum(t.tax_base + case when c.rate_category in ('reverse_charge', 'intra_eu_acquisition') then 0 else t.tax_amount end
               + t.surcharge_amount) as amount
    from erp.invoices i
    join erp.invoice_tax_lines t on t.invoice_id = i.id
    join erp.tax_codes c on c.code = t.tax_code
    join erp.business_partners bp on bp.id = i.partner_id
    where i.company_id = p_company and i.posting_date between make_date(p_year, 1, 1) and make_date(p_year, 12, 31)
      and i.withholding_amount = 0                                   -- con retención: van en el 190 / 180
      and bp.tax_territory in ('mainland', 'canary_islands', 'ceuta_melilla')
      and c.rate_category not in ('intra_eu', 'intra_eu_acquisition', 'export')
    group by 1, 2, 3
  )
  select x.partner_id, bp.name, bp.vat_registration_no, x.op_key,
         coalesce(sum(x.amount) filter (where x.q = 1), 0), coalesce(sum(x.amount) filter (where x.q = 2), 0),
         coalesce(sum(x.amount) filter (where x.q = 3), 0), coalesce(sum(x.amount) filter (where x.q = 4), 0),
         sum(x.amount), bp.vat_registration_no is null or btrim(bp.vat_registration_no) = ''
  from x join erp.business_partners bp on bp.id = x.partner_id
  group by x.partner_id, bp.name, bp.vat_registration_no, x.op_key
  having abs(sum(x.amount)) > 3005.06                                -- «superior a 3.005,06 €» (art. 33.1)
  order by x.op_key desc, bp.name;
$function$
;
