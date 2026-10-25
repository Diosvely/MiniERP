-- =====================================================================
-- erp.load_case · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0066_complete_case 0067_case_screen   →   la vigente es la de 0067_case_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.load_case(p_company uuid, p_case text DEFAULT 'taller_atlantico'::text, p_mode text DEFAULT 'full'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'erp', 'public'
AS $function$
declare
  e uuid := p_company; v_case erp.cases; v_co erp.companies; c text; q int;
  prov uuid; maq uuid; notaria uuid; aseso uuid; cli uuid; dud uuid;
  f uuid; f_dud uuid; f_maq uuid; a uuid; g uuid; v_ret uuid; v_pay date; v_due numeric;
  v_sales numeric[] := array[23000, 55000, 20000, 20000];
  v_purchases numeric[] := array[10000, 10000, 10000, 15000];
  v_end date[] := array['2026-03-31', '2026-06-30', '2026-09-30', '2026-12-31']::date[];
begin
  select * into v_case from erp.cases where key = p_case;
  if not found then raise exception 'Unknown case: %', p_case; end if;
  if p_mode is null or p_mode not in ('full', 'until_closing') then raise exception 'Invalid case mode: %', p_mode; end if;
  if not erp.is_admin(e) then raise exception 'No permission: only the company admin can load a case'; end if;
  select * into v_co from erp.companies where id = e;
  if v_co.tax_territory <> v_case.tax_territory then
    raise exception 'This case needs a company in the Canary Islands (IGIC)';
  end if;
  if v_co.legal_form <> v_case.legal_form then raise exception 'This case needs a limited company (SL)'; end if;
  if exists (select 1 from erp.journal_entries j where j.company_id = e) then
    raise exception 'Load the case into a new company: this one already has entries';
  end if;

  -- Preparación: ejercicios, impuestos, retenciones, cuentas y terceros
  perform erp.create_fiscal_year(e, y) from generate_series(2026, 2027) y
  where not exists (select 1 from erp.fiscal_years fy where fy.company_id = e and fy.year = y);
  perform erp.setup_taxes(e);
  perform erp.setup_withholdings(e);
  foreach c in array array['57200001:Banco', '60000001:Compras de mercaderías', '70000001:Ventas de mercaderías',
    '62300001:Asesoría', '62500001:Primas de seguros', '11300001:Reservas voluntarias', '21300001:Maquinaria', '30000001:Mercaderías'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  select partner_id into prov    from erp.create_partner(e, 'vendor',   'Recambios Canarios SL',  'B12345674');
  select partner_id into maq     from erp.create_partner(e, 'vendor',   'Maquinaria Atlántica SL', 'B87654323');
  select partner_id into notaria from erp.create_partner(e, 'creditor', 'Notaría Ejemplo SL',     'A58818501');
  select partner_id into aseso   from erp.create_partner(e, 'creditor', 'Asesoría Martín',        '12345678Z');
  select partner_id into cli     from erp.create_partner(e, 'customer', 'Cliente General SL',     'B11111119');
  select partner_id into dud     from erp.create_partner(e, 'customer', 'Cliente Dudoso SL',      'B76543214');

  -- 1. Constitución (Operaciones societarias)
  perform erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-02', 'capital', 60000, 'bank_account_no', '57200001'));
  perform erp.case_mark(e, 1);
  -- 2. Notaría y registro, a reservas (NRV 9.ª), pagados en el acto (Facturas · Cobros y pagos)
  f := erp.case_invoice(e, 'purchase', notaria, '2026-01-05', 'N-1', 'Notaría y registro de la constitución',
         '[{"account_no": "11300001", "amount": 1000, "tax_code": "IGIC7"}]');
  perform erp.case_payment(e, 'payment', notaria, '2026-01-05', f);
  perform erp.case_mark(e, 2);
  -- 6. La máquina, su ficha y su pago (Facturas · Inmovilizado · Cobros y pagos)
  f_maq := erp.case_invoice(e, 'purchase', maq, '2026-04-01', 'M-1', 'Máquina de diagnosis',
             '[{"account_no": "21300001", "amount": 40000, "tax_code": "IGIC7"}]');
  select asset_id into a from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Máquina de diagnosis',
    'asset_account_no', '21300001', 'cost', 40000, 'useful_life_months', 120, 'start_date', '2026-04-01',
    'acquisition_date', '2026-04-01', 'invoice_id', f_maq));
  perform erp.case_payment(e, 'payment', maq, '2026-04-15', f_maq);
  perform erp.case_mark(e, 6);
  -- 7. Subvención de capital del 40 % de la máquina, cobrada el 30/06 (Subvenciones)
  g := (erp.grant_create(jsonb_build_object('company_id', e, 'kind', 'capital', 'description', 'Subvención para la máquina de diagnosis',
         'grantor', 'Gobierno de Canarias', 'amount', 16000, 'date', '2026-04-15', 'asset_id', a))->>'grant_id')::uuid;
  perform erp.grant_collect(jsonb_build_object('grant_id', g, 'date', '2026-06-30'));
  perform erp.case_mark(e, 7);
  -- 8. Préstamo de 30.000 al 5 %, tres cuotas anuales (Financiación)
  perform erp.loan_create(jsonb_build_object('company_id', e, 'description', 'Préstamo para circulante', 'lender', 'Banco Atlántico',
    'principal', 30000, 'rate', 5, 'periods', 3, 'frequency', 1, 'start_date', '2026-07-01'));
  perform erp.case_mark(e, 8);
  -- 9. Seguro anual, exento, pagado (Nuevo asiento)
  perform erp.case_entry(e, '2026-10-01', 'Seguro anual del taller', '[["62500001", 1200, 0], ["57200001", 0, 1200]]');
  perform erp.case_mark(e, 9);
  -- 3, 4, 5 y 10. Cada trimestre: compras, ventas, asesoría, liquidación del IGIC y retenciones
  for q in 1..4 loop
    f := erp.case_invoice(e, 'purchase', prov, v_end[q] - 45, 'C-' || q, 'Compra de recambios',
           jsonb_build_array(jsonb_build_object('account_no', '60000001', 'amount', v_purchases[q], 'tax_code', 'IGIC7')));
    if q < 4 then perform erp.case_payment(e, 'payment', prov, v_end[q] - 30, f); end if;
    perform erp.case_mark(e, 4);
    f := erp.case_invoice(e, 'sale', cli, v_end[q] - 40, null, 'Venta de recambios',
           jsonb_build_array(jsonb_build_object('account_no', '70000001', 'amount', v_sales[q], 'tax_code', 'IGIC7')));
    if q < 4 then perform erp.case_payment(e, 'collection', cli, v_end[q] - 10, f); end if;
    if q = 1 then   -- la venta dudosa del 15/03, que no se cobra
      f_dud := erp.case_invoice(e, 'sale', dud, '2026-03-15', null, 'Venta de recambios',
                 '[{"account_no": "70000001", "amount": 2000, "tax_code": "IGIC7"}]');
    end if;
    perform erp.case_mark(e, 5);
    f := erp.case_invoice(e, 'purchase', aseso, v_end[q], 'A-' || q, 'Asesoría del trimestre',
           '[{"account_no": "62300001", "amount": 600, "tax_code": "IGIC7"}]', 'IRPF15');
    if q < 4 then perform erp.case_payment(e, 'payment', aseso, v_end[q], f); end if;
    perform erp.case_mark(e, 3);
    perform erp.post_tax_settlement(e, 'IGIC', 2026, q);
    if q < 4 then   -- los modelos 420 y 111 se pagan el día 20 del mes siguiente; los del 4T, en enero
      v_pay := v_end[q] + 20;
      v_due := erp.case_balance(e, '4750', v_pay);
      perform erp.case_entry(e, v_pay, 'Pago del modelo 420 · ' || q || 'T',
        jsonb_build_array(jsonb_build_array('4750', v_due, 0), jsonb_build_array('57200001', 0, v_due)));
      perform erp.case_entry(e, v_pay, 'Pago del modelo 111 · ' || q || 'T', '[["4751", 90, 0], ["57200001", 0, 90]]');
    end if;
    perform erp.case_mark(e, 10);
  end loop;

  -- 11 a 19. El cierre del 31/12/2026 (en el modo «hasta el cierre», lo hace quien estudia)
  if p_mode = 'full' then
    perform erp.post_depreciation(e, '2026-12-31');                    perform erp.case_mark(e, 11);   -- Inmovilizado
    perform erp.grant_year_end(e, '2026-12-31');                       perform erp.case_mark(e, 12);   -- Subvenciones
    perform erp.loan_year_end(e, '2026-12-31');                        perform erp.case_mark(e, 13);   -- Financiación (13 y 14)
    perform erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'prepaid_expense', 'description', 'Seguro anual del taller',
      'pl_account_no', '62500001', 'cutoff_date', '2026-12-31', 'total_amount', 1200, 'coverage_start', '2026-10-01',
      'coverage_months', 12));                                        perform erp.case_mark(e, 15);   -- Ajustes de cierre
    perform erp.impair_receivable(jsonb_build_object('invoice_id', f_dud, 'impair_date', '2026-12-31'));   perform erp.case_mark(e, 16);
    perform erp.post_inventory(jsonb_build_object('company_id', e, 'count_date', '2026-12-31',
      'lines', '[{"account_no": "30000001", "final_value": 8000}]'::jsonb));                               perform erp.case_mark(e, 17);
    v_ret := erp.corporate_tax_prepare(e, 2026);                       -- Impuesto sobre Sociedades
    perform erp.corporate_tax_settings(v_ret, 'new_entity', false);
    perform erp.corporate_tax_calc(e, 2026);
    perform erp.corporate_tax_post(e, 2026);                           perform erp.case_mark(e, 18);
    perform erp.close_fiscal_year(e, 2026, true);                      perform erp.case_mark(e, 19);   -- Cierre del ejercicio
  end if;

  update erp.companies set case_key = p_case, case_mode = p_mode where id = e;
  return jsonb_build_object('company_id', e, 'case', p_case, 'mode', p_mode,
    'entries', (select count(*) from erp.journal_entries j where j.company_id = e and j.status = 'posted'));
end $function$
;
