-- =====================================================================
-- erp.synthetic_step · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0087_synthetic_batches   →   la vigente es la de 0087_synthetic_batches
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.synthetic_step(p_company uuid, p_max integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'erp', 'public'
AS $function$
declare
  e uuid := p_company; co erp.companies; x erp.synthetic_plan; r record;
  v_tax text; v_gen text; v_sale_acc text; v_prof text;
  d date; v_id uuid; v_res uuid; v_inv uuid; v_loan uuid; v_last date; v_done int; v_total int;
begin
  if not erp.is_admin(e) then raise exception 'No permission: only the company admin can generate a synthetic company'; end if;
  -- una tanda a la vez por empresa (si hay dos pestañas, la segunda espera y sigue donde acabó la primera)
  select * into co from erp.companies where id = e for update;
  if co.synthetic_seed is null then raise exception 'This is not a synthetic company'; end if;
  v_prof := co.synthetic_profile;
  v_tax := case when v_prof in ('workshop', 'incidents') then 'IGIC' else 'VAT' end;
  v_gen := case when v_prof in ('workshop', 'incidents') then 'IGIC7' else 'VAT21' end;
  v_sale_acc := case v_prof when 'services' then '70500001' else '70000001' end;
  select id into v_loan from erp.loans where company_id = e order by created_at limit 1;

  for x in select * from erp.synthetic_plan p where p.company_id = e and not p.done order by p.seq limit greatest(coalesce(p_max, 40), 1) loop
    d := x.d; v_res := null;
    -- la factura a la que se refiere un cobro o un pago
    if x.k in ('collect', 'pay') then
      select p.result into v_inv from erp.synthetic_plan p
      where p.company_id = e and p.ref = x.ref and p.k in ('sale', 'purchase', 'rent', 'advisor');
    end if;
    case x.k
    when 'sale' then
      v_res := erp.case_invoice(e, 'sale', (x.data->>'pid')::uuid, d, null, 'Venta',
        jsonb_build_array(jsonb_build_object('account_no', v_sale_acc, 'amount', (x.data->>'amount')::numeric, 'tax_code', x.data->>'code')));
    when 'purchase' then
      v_res := erp.case_invoice(e, 'purchase', (x.data->>'pid')::uuid, d, x.ref,
        case when x.data->>'acc' = '60000001' then 'Compra de mercaderías' else 'Gasto del mes' end,
        jsonb_build_array(jsonb_build_object('account_no', x.data->>'acc', 'amount', (x.data->>'amount')::numeric, 'tax_code', x.data->>'code')));
    when 'rent' then
      v_res := erp.case_invoice(e, 'purchase', (x.data->>'pid')::uuid, d, x.ref, 'Alquiler del local',
        jsonb_build_array(jsonb_build_object('account_no', '62100001', 'amount', 1200, 'tax_code', v_gen)), 'IRPF19');
    when 'advisor' then
      v_res := erp.case_invoice(e, 'purchase', (x.data->>'pid')::uuid, d, x.ref, 'Asesoría del mes',
        jsonb_build_array(jsonb_build_object('account_no', '62300001', 'amount', (x.data->>'amount')::numeric, 'tax_code', v_gen)), 'IRPF15');
    when 'collect' then
      perform erp.case_payment(e, 'collection', (select partner_id from erp.invoices where id = v_inv), d, v_inv);
    when 'pay' then
      perform erp.case_payment(e, 'payment', (select partner_id from erp.invoices where id = v_inv), d, v_inv);
    when 'asset' then
      v_id := erp.case_invoice(e, 'purchase', (x.data->>'pid')::uuid, d, 'INV-1',
        case when v_prof = 'services' then 'Equipos informáticos' else 'Máquina para el taller' end,
        jsonb_build_array(jsonb_build_object('account_no', case when v_prof = 'services' then '21700001' else '21300001' end,
                                             'amount', (x.data->>'amount')::numeric, 'tax_code', v_gen)));
      perform erp.create_fixed_asset(jsonb_build_object('company_id', e,
        'name', case when v_prof = 'services' then 'Equipos informáticos' else 'Máquina para el taller' end,
        'asset_account_no', case when v_prof = 'services' then '21700001' else '21300001' end,
        'cost', (x.data->>'amount')::numeric, 'useful_life_months', case when v_prof = 'services' then 48 else 120 end,
        'start_date', d, 'acquisition_date', d, 'invoice_id', v_id));
      perform erp.case_payment(e, 'payment', (x.data->>'pid')::uuid, d, v_id);
      v_res := v_id;
    when 'loan' then
      perform erp.loan_create(jsonb_build_object('company_id', e, 'description', 'Préstamo para circulante', 'lender', 'Banco Ficticio',
        'principal', (x.data->>'amount')::numeric, 'rate', 5, 'periods', 36, 'frequency', 12, 'start_date', d,
        'bank_account_no', '57200001'));
      select id into v_loan from erp.loans where company_id = e order by created_at limit 1;
      v_res := v_loan;
    when 'loan_pay' then
      perform erp.loan_payment(jsonb_build_object('loan_id', v_loan, 'date', d, 'bank_account_no', '57200001'));
    when 'payroll' then
      select run_id into v_res from erp.run_payroll(jsonb_build_object('company_id', e, 'period', d));
      perform erp.pay_payroll(jsonb_build_object('run_id', v_res, 'what', 'net', 'payment_date', d, 'cash_account_no', '57200001'));
    when 'pay_ss' then
      perform erp.pay_payroll(jsonb_build_object('run_id',
        (select p.result from erp.synthetic_plan p where p.company_id = e and p.k = 'payroll' and p.data->>'m' = x.data->>'m'),
        'what', 'social_security', 'payment_date', d, 'cash_account_no', '57200001'));
    when 'quarter' then
      begin
        perform erp.post_depreciation(e, d);
      exception when others then if sqlerrm not like 'Nothing to depreciate%' then raise; end if;
      end;
      -- incidencias: el 2T se queda sin liquidar
      if not (v_prof = 'incidents' and (x.data->>'q')::int = 2) then
        perform erp.post_tax_settlement(e, v_tax, 2026, (x.data->>'q')::int);
      end if;
    when 'pay_taxes' then
      -- el resultado de la liquidación (4750) y las retenciones del trimestre (4751: modelo 111 y modelo 115), cada
      -- subcuenta con su pago
      for r in select g.account_no, erp.case_balance(e, g.account_no, d) as due from erp.gl_accounts g
               where g.company_id = e and g.account_type = 'posting' and (g.account_no like '4750%' or g.account_no like '4751%')
               order by g.account_no loop
        if r.due > 0 then
          perform erp.case_entry(e, d, case when r.account_no like '4750%' then 'Pago de la liquidación del '
                                            else 'Pago de las retenciones del ' end || (x.data->>'q') || 'T',
            jsonb_build_array(jsonb_build_array(r.account_no, r.due, 0), jsonb_build_array('57200001', 0, r.due)));
        end if;
      end loop;
    when 'bad_sale' then
      perform erp.case_invoice(e, 'sale', (x.data->>'pid')::uuid, d, null, 'Venta que no se cobra',
        jsonb_build_array(jsonb_build_object('account_no', v_sale_acc, 'amount', 2500, 'tax_code', v_gen)));
    when 'double_pay' then
      perform erp.case_entry(e, d, 'Pago duplicado a un proveedor',
        jsonb_build_array(jsonb_build_array((select account_no from erp.v_partners where id = (x.data->>'pid')::uuid), 1500, 0),
                          jsonb_build_array('57200001', 0, 1500)));
    when 'bad_draft' then
      insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
      values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), d, 'Borrador descuadrado')
      returning id into v_id;
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
        (v_id, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '62900001'), 100, 0),
        (v_id, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), 0, 70);
    end case;
    update erp.synthetic_plan set done = true, result = v_res where company_id = e and seq = x.seq;
    v_last := d;
  end loop;

  select count(*) filter (where done)::int, count(*)::int into v_done, v_total from erp.synthetic_plan where company_id = e;
  return jsonb_build_object('company_id', e, 'done', v_done, 'total', v_total, 'left', v_total - v_done, 'date', v_last,
    'entries', (select count(*) from erp.journal_entries j where j.company_id = e),
    'fingerprint', case when v_done = v_total then erp.company_fingerprint(e) end);
end $function$
;
