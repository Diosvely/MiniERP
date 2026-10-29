-- =====================================================================
-- erp.tax_settlement_calc · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0012_tax_settlement 0019_reverse_charge_surcharge 0020_pro_rata 0039_review_fixes   →   la vigente es la de 0039_review_fixes
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tax_settlement_calc(p_company uuid, p_tax_type text, p_year integer, p_quarter integer, p_refund boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare
  v_start    date := erp.quarter_start(p_year, p_quarter);
  v_end      date := erp.quarter_end(p_year, p_quarter);
  v_set      erp.tax_settlement_setup;
  v_out      numeric;
  v_in       numeric;
  v_reg_out  numeric;
  v_reg_in   numeric;
  v_carry    numeric;
  v_applied  numeric := 0;
  v_result   numeric;
  v_final    numeric;
  v_outcome  text;
  v_boxes    jsonb;
  v_lines    jsonb;
  v_done     erp.tax_settlements;
begin
  if p_quarter not between 1 and 4 then
    raise exception 'Invalid quarter: %', p_quarter;
  end if;
  select * into v_set from erp.tax_settlement_setup where company_id = p_company and tax_type = p_tax_type;
  if not found then
    raise exception '% is not set up for this company (Taxes tab)', p_tax_type;
  end if;
  select * into v_done from erp.tax_settlements
  where company_id = p_company and tax_type = p_tax_type and year = p_year and quarter = p_quarter and status = 'posted';

  -- 1) Movimiento del trimestre en las cuentas de impuesto (lo que dice la CONTABILIDAD)
  with acc as (
    select distinct s.output_account_id as id, 'output' as side from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.output_account_id is not null
    union
    select distinct s.input_account_id, 'input' from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.input_account_id is not null
    union   -- recargo de equivalencia repercutido: también se ingresa con el modelo 303
    select distinct s.surcharge_account_id, 'output' from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.surcharge_account_id is not null
    union   -- v0.33.1: las 472 / 477 que NO están configuradas para ningún tipo cuentan en el impuesto del territorio.
            -- Antes un apunte en una 47700001 sin configurar quedaba fuera del cuadre del 303 / 420.
    select g.id, case when g.account_no like '472%' then 'input' else 'output' end
      from erp.gl_accounts g
      where g.company_id = p_company and g.account_type = 'posting'
        and (g.account_no like '472%' or g.account_no like '477%')
        and p_tax_type = (select case tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end
                          from erp.companies where id = p_company)
        and not exists (select 1 from erp.tax_setup s
                        where s.company_id = p_company and g.id in (s.input_account_id, s.output_account_id, s.surcharge_account_id))
  ), mov as (
    select acc.id, acc.side, g.account_no, g.name,
           coalesce(sum(l.debit - l.credit), 0) as balance   -- saldo deudor (+) / acreedor (−) del trimestre
    from acc
    join erp.gl_accounts g on g.id = acc.id
    left join erp.journal_lines l on l.gl_account_id = acc.id
      and exists (select 1 from erp.journal_entries e where e.id = l.entry_id and e.status = 'posted'
                  and e.posting_date between v_start and v_end and not erp.is_settlement_entry(e.id))
    group by acc.id, acc.side, g.account_no, g.name
  )
  select coalesce(sum(-balance) filter (where side = 'output'), 0),
         coalesce(sum(balance)  filter (where side = 'input'), 0),
         coalesce(jsonb_agg(jsonb_build_object('account_no', account_no, 'account_name', name,
                    -- se salda: un saldo deudor se cierra al Haber y uno acreedor al Debe
                    'debit', case when balance < 0 then -balance else 0 end,
                    'credit', case when balance > 0 then balance else 0 end) order by account_no)
                  filter (where balance <> 0), '[]'::jsonb)
    into v_out, v_in, v_lines
  from mov;

  -- 2) Casillas del borrador por tipo, desde el LIBRO REGISTRO de facturas
  select coalesce(jsonb_agg(jsonb_build_object('side', b.side, 'kind', b.kind, 'tax_code', b.tax_code, 'rate_pct', b.rate_pct,
                    'tax_base', b.base, 'tax_amount', b.amount) order by b.side desc, b.kind desc, b.rate_pct desc), '[]'::jsonb),
         coalesce(sum(b.amount) filter (where b.side = 'output'), 0),
         coalesce(sum(b.amount) filter (where b.side = 'input'), 0)
    into v_boxes, v_reg_out, v_reg_in
  from (
    select x.side, x.kind, x.tax_code, x.rate_pct, sum(x.base) as base, sum(x.amount) as amount
    from (
      -- cuota de cada factura: emitidas → devengada · recibidas → deducible (si lo es)
      --   (en compras, solo la parte deducible: prorrata; lo no deducible del recargo de equivalencia no cuenta)
      select case r.invoice_type when 'sale' then 'output' else 'input' end as side, 'tax' as kind,
             r.tax_code, r.rate_pct, r.tax_base as base,
             case r.invoice_type when 'sale' then r.tax_amount else r.deductible_amount end as amount
      from erp.v_invoice_register r
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and (r.invoice_type = 'sale' or r.deductible_amount <> 0 or r.tax_amount = 0)
      union all
      -- inversión del sujeto pasivo y adquisiciones intracomunitarias: la empresa también DEVENGA la cuota
      select 'output', 'reverse_charge', r.tax_code, r.rate_pct, r.tax_base, r.tax_amount
      from erp.v_invoice_register r
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and r.invoice_type = 'purchase' and r.rate_category in ('reverse_charge', 'intra_eu_acquisition')
      union all
      -- recargo de equivalencia repercutido a clientes minoristas
      select 'output', 'surcharge', r.tax_code, c.equivalence_surcharge_pct, r.tax_base, r.surcharge_amount
      from erp.v_invoice_register r
      join erp.tax_codes c on c.code = r.tax_code
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and r.invoice_type = 'sale' and r.surcharge_amount <> 0
      union all
      -- regularización anual de la prorrata (4T): ajuste del IVA deducido al porcentaje definitivo
      select 'input', 'pro_rata', null, pr.definitive_pct, null, pr.regularization_amount
      from erp.pro_rata pr
      join erp.journal_entries je on je.id = pr.entry_id
      where pr.company_id = p_company and pr.tax_type = p_tax_type and je.posting_date between v_start and v_end
    ) x
    group by 1, 2, 3, 4
  ) b;

  -- 3) Cuotas a compensar de periodos anteriores
  select coalesce(sum(case when outcome = 'carry_forward' then -final_result else 0 end), 0)
         - coalesce(sum(carry_applied), 0)
    into v_carry
  from erp.tax_settlements
  where company_id = p_company and tax_type = p_tax_type and status = 'posted'
    and (year, quarter) < (p_year, p_quarter);

  v_result := v_out - v_in;
  if v_result > 0 and v_carry > 0 then
    v_applied := least(v_result, v_carry);
  end if;
  v_final := v_result - v_applied;
  v_outcome := case when v_final > 0 then 'payable'
                    when v_final = 0 then 'zero'
                    when p_quarter = 4 and p_refund then 'refund'
                    else 'carry_forward' end;

  -- 4) Líneas de compensación y resultado
  if v_applied > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.receivable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.receivable_account_id), 'debit', 0, 'credit', v_applied);
  end if;
  if v_final > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.payable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.payable_account_id), 'debit', 0, 'credit', v_final);
  elsif v_final < 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.receivable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.receivable_account_id), 'debit', -v_final, 'credit', 0);
  end if;

  return jsonb_build_object(
    'tax_type', p_tax_type, 'year', p_year, 'quarter', p_quarter,
    'form', case p_tax_type when 'VAT' then '303' else '420' end,
    'period_start', v_start, 'period_end', v_end,
    'boxes', v_boxes,
    'output_tax', v_out, 'input_tax', v_in,
    'register_output', v_reg_out, 'register_input', v_reg_in,
    -- Cuadre auditor: el libro registro debe coincidir con la contabilidad
    'difference', (v_out - v_in) - (v_reg_out - v_reg_in),
    'result', v_result, 'carry_available', v_carry, 'carry_applied', v_applied,
    'final_result', v_final, 'outcome', v_outcome,
    'can_refund', p_quarter = 4 and v_final < 0,
    'lines', v_lines,
    'settled', v_done.id is not null, 'settlement_id', v_done.id);
end $function$
;
