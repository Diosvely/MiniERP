-- =====================================================================
-- erp.tax_form_lines · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0051_tax_forms   →   la vigente es la de 0051_tax_forms
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tax_form_lines(p_company uuid, p_tax_type text, p_from date, p_to date)
 RETURNS TABLE(kind text, rate numeric, base numeric, quota numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with t as (   -- cada línea de impuesto de las facturas del periodo
    select r.*, i.id as inv_id
    from erp.v_invoice_register r join erp.invoices i on i.id = r.invoice_id
    where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between p_from and p_to
  ),
  cls as (      -- clase de cada línea de la factura: inversión · servicio · bienes (por su cuenta y su importe)
    select l.invoice_id, l.tax_code,
           case when g.account_no ~ '^2[12]' and l.amount >= 3005.06 then 'inv'
                when g.account_no ~ '^62' then 'serv' else 'cur' end as cl,
           sum(l.amount * l.sign) as amt
    from erp.invoice_lines l join erp.gl_accounts g on g.id = l.gl_account_id
    where l.company_id = p_company and l.invoice_id in (select inv_id from t)
    group by 1, 2, 3
  ),
  split as (    -- la base de cada clase y su parte de la cuota (la última clase se lleva el redondeo)
    select t.*, c.cl, c.amt,
           case when t.tax_base = 0 then 0 else round(t.tax_amount * c.amt / t.tax_base, 2) end as q,
           case when t.tax_base = 0 then 0 else round(t.deductible_amount * c.amt / t.tax_base, 2) end as dq,
           row_number() over (partition by t.invoice_id, t.tax_code order by c.cl desc) as rn,
           count(*) over (partition by t.invoice_id, t.tax_code) as n,
           sum(case when t.tax_base = 0 then 0 else round(t.tax_amount * c.amt / t.tax_base, 2) end)
             over (partition by t.invoice_id, t.tax_code) as q_sum,
           sum(case when t.tax_base = 0 then 0 else round(t.deductible_amount * c.amt / t.tax_base, 2) end)
             over (partition by t.invoice_id, t.tax_code) as dq_sum
    from t join cls c on c.invoice_id = t.invoice_id and c.tax_code = t.tax_code
  ),
  s as (
    select split.*, q + case when rn = 1 then tax_amount - q_sum else 0 end as quota_c,
                    dq + case when rn = 1 then deductible_amount - dq_sum else 0 end as ded_c
    from split
  )
  -- VENTAS
  select case when t.document_kind = 'credit_memo' then 'out_mod' else 'out_rate' end, t.rate_pct, t.tax_base, t.tax_amount
  from t where t.invoice_type = 'sale'
    and t.rate_category not in ('intra_eu', 'export', 'not_subject', 'exempt', 'retail_surcharge')
  union all
  select case when t.document_kind = 'credit_memo' then 'out_re_mod' else 'out_re' end, c.equivalence_surcharge_pct, t.tax_base, t.surcharge_amount
  from t join erp.tax_codes c on c.code = t.tax_code where t.invoice_type = 'sale' and t.surcharge_amount <> 0
  union all
  select case t.rate_category when 'intra_eu' then 'info_eu' when 'export' then 'info_exp' when 'not_subject' then 'info_ns'
                              when 'exempt' then 'info_exempt' else 'info_re_retail' end, t.rate_pct, t.tax_base, 0
  from t where t.invoice_type = 'sale' and t.rate_category in ('intra_eu', 'export', 'not_subject', 'exempt', 'retail_surcharge')
  union all
  -- entregas de bienes de inversión (venta de un activo: la línea a la cuenta 2x), para el volumen de operaciones
  select 'asset_sale', null, sum(l.amount * l.sign), 0
  from erp.invoice_lines l join erp.gl_accounts g on g.id = l.gl_account_id join t on t.inv_id = l.invoice_id and t.tax_code = l.tax_code
  where t.invoice_type = 'sale' and g.account_no like '2%'
  group by l.invoice_id, l.tax_code
  union all
  -- COMPRAS: la cuota que DEVENGA la empresa (adquisición intracomunitaria e inversión del sujeto pasivo)
  select case when s.document_kind = 'credit_memo' then 'out_mod'
              when s.rate_category = 'reverse_charge' then 'out_isp'
              when s.cl = 'serv' then 'out_aib_serv' else 'out_aib_goods' end, s.rate_pct, s.amt, s.quota_c
  from s where s.invoice_type = 'purchase' and s.rate_category in ('intra_eu_acquisition', 'reverse_charge')
  union all
  -- COMPRAS: la cuota DEDUCIBLE (tras la prorrata), con su base en la misma proporción
  select case when s.document_kind = 'credit_memo' then 'in_mod'
              when s.rate_category = 'intra_eu_acquisition' then case s.cl when 'inv' then 'in_aib_inv' when 'serv' then 'in_aib_serv' else 'in_aib_cur' end
              else case s.cl when 'inv' then 'in_inv' else 'in_cur' end end,
         s.rate_pct,
         case when s.quota_c = 0 then s.amt else round(s.amt * s.ded_c / s.quota_c, 2) end, s.ded_c
  from s where s.invoice_type = 'purchase' and s.ded_c <> 0
  union all
  -- regularización de la prorrata (4T)
  select 'pro_rata', pr.definitive_pct, null, pr.regularization_amount
  from erp.pro_rata pr join erp.journal_entries je on je.id = pr.entry_id
  where pr.company_id = p_company and pr.tax_type = p_tax_type and je.posting_date between p_from and p_to;
$function$
;
