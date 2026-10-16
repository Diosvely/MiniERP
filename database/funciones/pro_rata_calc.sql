-- =====================================================================
-- erp.pro_rata_calc · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0020_pro_rata 0042_assets_integration   →   la vigente es la de 0042_assets_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.pro_rata_calc(p_company uuid, p_tax_type text, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_pr       erp.pro_rata;
  v_with     numeric;     -- operaciones con derecho a deducir
  v_total    numeric;     -- todas las operaciones (con derecho + exentas sin derecho)
  v_def      numeric;
  v_input    numeric;     -- cuotas soportadas del año
  v_deducted numeric;     -- deducido con la provisional
  v_should   numeric;
  v_adj      numeric;
  v_acc472   uuid;
  v_settled  boolean;
begin
  select * into v_pr from erp.pro_rata where company_id = p_company and tax_type = p_tax_type and year = p_year;
  if not found then
    raise exception 'The company has no % pro rata in %', p_tax_type, p_year;
  end if;

  -- Numerador y denominador: bases de las facturas EMITIDAS del año (sin IVA)
  select coalesce(sum(r.tax_base) filter (where r.rate_category <> 'exempt'), 0), coalesce(sum(r.tax_base), 0)
    into v_with, v_total
  from erp.v_invoice_register r
  where r.company_id = p_company and r.tax_type = p_tax_type and r.fiscal_year = p_year and r.invoice_type = 'sale'
    and r.rate_category <> 'retail_surcharge';

  -- v0.35.0 · art. 104.Tres.2.º LIVA: las entregas de bienes de inversión no se computan en ningún término
  -- (las ventas de inmovilizado se facturan a su cuenta 20x / 21x / 22x)
  select v_with - coalesce(sum(l.amount * l.sign) filter (where c.rate_category <> 'exempt'), 0),
         v_total - coalesce(sum(l.amount * l.sign), 0)
    into v_with, v_total
  from erp.invoice_lines l
  join erp.invoices i on i.id = l.invoice_id
  join erp.fiscal_years fy on fy.id = i.fiscal_year_id
  join erp.gl_accounts g on g.id = l.gl_account_id
  join erp.tax_codes c on c.code = l.tax_code
  where i.company_id = p_company and i.invoice_type = 'sale' and fy.year = p_year and c.tax_type = p_tax_type
    and left(g.account_no, 2) in ('20', '21', '22');
  v_def := case when v_total <= 0 then 100 else least(100, ceil(v_with / v_total * 100)) end;

  -- Cuotas soportadas del año y lo que se dedujo con la provisional
  select coalesce(sum(r.tax_amount), 0), coalesce(sum(r.deductible_amount), 0)
    into v_input, v_deducted
  from erp.v_invoice_register r
  where r.company_id = p_company and r.tax_type = p_tax_type and r.fiscal_year = p_year and r.invoice_type = 'purchase'
    and r.tax_amount <> 0 and r.surcharge_amount = 0 and (r.deductible or r.deductible_amount <> r.tax_amount);
  v_should := round(v_input * v_def / 100, 2);
  v_adj := coalesce(v_pr.regularization_amount, v_should - v_deducted);

  select s.input_account_id into v_acc472
  from erp.tax_setup s join erp.tax_codes c on c.code = s.tax_code
  where s.company_id = p_company and c.tax_type = p_tax_type and c.rate_category = 'standard' and s.input_account_id is not null
  limit 1;

  select exists (select 1 from erp.tax_settlements t where t.company_id = p_company and t.tax_type = p_tax_type
                 and t.year = p_year and t.quarter = 4 and t.status = 'posted') into v_settled;

  return jsonb_build_object(
    'tax_type', p_tax_type, 'year', p_year,
    'provisional_pct', v_pr.provisional_pct,
    'operations_with_right', v_with, 'operations_total', v_total,
    'definitive_pct', coalesce(v_pr.definitive_pct, v_def),
    'input_tax', v_input, 'deducted', v_deducted, 'should_deduct', v_should,
    'adjustment', v_adj,
    'lines', case when v_adj > 0 then jsonb_build_array(
                   jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_acc472), 'debit', v_adj, 'credit', 0),
                   jsonb_build_object('account_no', rpad('6391', (select posting_account_digits from erp.companies where id = p_company) - 1, '0')
                                        || case p_tax_type when 'VAT' then '1' else '2' end, 'debit', 0, 'credit', v_adj))
                  when v_adj < 0 then jsonb_build_array(
                   jsonb_build_object('account_no', rpad('6341', (select posting_account_digits from erp.companies where id = p_company) - 1, '0')
                                        || case p_tax_type when 'VAT' then '1' else '2' end, 'debit', -v_adj, 'credit', 0),
                   jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_acc472), 'debit', 0, 'credit', -v_adj))
                  else '[]'::jsonb end,
    'regularized', v_pr.entry_id is not null or v_pr.regularized_at is not null,
    'entry_no', (select entry_no from erp.journal_entries where id = v_pr.entry_id),
    'q4_settled', v_settled,
    'next_year_pct', (select provisional_pct from erp.pro_rata where company_id = p_company and tax_type = p_tax_type and year = p_year + 1));
end $function$
;
