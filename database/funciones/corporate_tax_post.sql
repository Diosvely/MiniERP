-- =====================================================================
-- erp.corporate_tax_post · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0058_corporate_tax_posting 0061_equity_integration   →   la vigente es la de 0061_equity_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_post(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_fy erp.fiscal_years; v_ret uuid; g jsonb; v_cur jsonb := '[]'; v_def jsonb := '[]'; a record;
  v_quota numeric; v_diff numeric; v_dtax numeric; v_e1 uuid; v_e2 uuid; v_d numeric;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post the corporate tax of this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', p_year; end if;
  if exists (select 1 from erp.year_closings c where c.company_id = p_company and c.fiscal_year_id = v_fy.id and c.status = 'posted') then
    raise exception 'The year % is already closed (regularization posted): the corporate tax goes before it', p_year;
  end if;
  v_ret := erp.corporate_tax_prepare(p_company, p_year);
  g := erp.corporate_tax_calc(p_company, p_year);
  v_quota := (g->>'current_tax')::numeric; v_diff := (g->>'differential')::numeric; v_dtax := (g->>'deferred_tax')::numeric;

  -- impuesto corriente
  v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '6300', 'Impuesto corriente'), 'debit', v_quota, 'credit', 0);
  -- v0.42.0 · el ahorro de impuesto de los gastos cargados a reservas, a reservas (113 H)
  if coalesce((g->>'equity_tax_effect')::numeric, 0) > 0 then
    v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '113', 'Reservas voluntarias'), 'debit', 0, 'credit', (g->>'equity_tax_effect')::numeric);
  end if;
  for a in select gl.id, sum(l.debit - l.credit) as bal
           from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts gl on gl.id = l.gl_account_id
           where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
             and e.entry_type not in ('closing_pl', 'closing') and gl.account_no like '473%'
           group by gl.id having sum(l.debit - l.credit) <> 0 loop
    v_cur := v_cur || jsonb_build_object('account_id', a.id, 'debit', greatest(-a.bal, 0), 'credit', greatest(a.bal, 0));
  end loop;
  if v_diff > 0 then
    v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '4752', 'Hacienda Pública, acreedora por impuesto sobre sociedades'), 'debit', 0, 'credit', v_diff);
  elsif v_diff < 0 then
    v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '4709', 'Hacienda Pública, deudora por devolución de impuestos'), 'debit', -v_diff, 'credit', 0);
  end if;
  v_e1 := erp.corporate_tax_entry(p_company, v_fy.ending_date, 'Impuesto sobre Sociedades ' || p_year || ' · impuesto corriente', v_cur);

  -- impuesto diferido
  v_d := round((g->>'temporary_increase')::numeric * (g->>'deferred_rate')::numeric / 100, 2) - round((g->>'temporary_decrease')::numeric * (g->>'deferred_rate')::numeric / 100, 2);
  if v_d <> 0 then
    v_def := v_def || jsonb_build_object('account_id', erp.adjust_account(p_company, '4740', 'Activos por diferencias temporarias deducibles'),
                                         'debit', greatest(v_d, 0), 'credit', greatest(-v_d, 0));
  end if;
  if (g->>'loss_credit')::numeric > 0 or (g->>'loss_credit_used')::numeric > 0 then
    v_def := v_def || jsonb_build_object('account_id', erp.adjust_account(p_company, '4745', 'Crédito por pérdidas a compensar del ejercicio'),
                                         'debit', (g->>'loss_credit')::numeric, 'credit', (g->>'loss_credit_used')::numeric);
  end if;
  if v_dtax <> 0 then
    v_def := v_def || jsonb_build_object('account_id', erp.adjust_account(p_company, '6301', 'Impuesto diferido'),
                                         'debit', greatest(v_dtax, 0), 'credit', greatest(-v_dtax, 0));
  end if;
  v_e2 := erp.corporate_tax_entry(p_company, v_fy.ending_date, 'Impuesto sobre Sociedades ' || p_year || ' · impuesto diferido', v_def);

  update erp.corporate_tax_returns set status = 'posted', result = g - 'status' - 'return_id', current_entry_id = v_e1,
    deferred_entry_id = v_e2, posted_at = now() where id = v_ret;
  return g || jsonb_build_object('status', 'posted', 'return_id', v_ret,
    'current_entry_no', (select entry_no from erp.journal_entries where id = v_e1),
    'deferred_entry_no', (select entry_no from erp.journal_entries where id = v_e2));
end $function$
;
