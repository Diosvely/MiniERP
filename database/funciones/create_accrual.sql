-- =====================================================================
-- erp.create_accrual · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.create_accrual(p jsonb)
 RETURNS TABLE(accrual_id uuid, code text, entry_no integer, amount numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_kind    text := p->>'kind';
  v_date    date := (p->>'cutoff_date')::date;
  v_prefix  text;
  v_pl      erp.gl_accounts;
  v_bal     erp.gl_accounts;
  v_total   numeric := round((p->>'total_amount')::numeric, 2);
  v_start   date := (p->>'coverage_start')::date;
  v_months  int := (p->>'coverage_months')::int;
  v_amount  numeric;
  v_inv     erp.invoices;
  v_code    text;
  v_entry   uuid;
  v_no      int;
  v_id      uuid;
  v_desc    text := btrim(coalesce(p->>'description', ''));
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register accruals in this company'; end if;
  v_prefix := case v_kind when 'prepaid_expense' then '480' when 'deferred_income' then '485'
                          when 'accrued_expense' then '4009' when 'accrued_income' then '4309' end;
  if v_prefix is null then raise exception 'Invalid accrual type: %', v_kind; end if;
  if v_desc = '' then raise exception 'The accrual needs a description'; end if;
  if v_date is null then raise exception 'The cut-off date is required'; end if;

  select * into v_pl from erp.gl_accounts
  where company_id = v_company and account_no = p->>'pl_account_no' and account_type = 'posting';
  if not found or left(v_pl.account_no, 1) <> (case when v_kind like '%expense' then '6' else '7' end) then
    raise exception 'Choose the % account (group %)', case when v_kind like '%expense' then 'expense' else 'income' end,
      case when v_kind like '%expense' then '6' else '7' end;
  end if;

  if p->>'balance_account_no' is not null then
    select * into v_bal from erp.gl_accounts
    where company_id = v_company and account_no = p->>'balance_account_no' and account_type = 'posting';
    if not found or v_bal.account_no not like v_prefix || '%' then raise exception 'The balance account must be a % subaccount', v_prefix; end if;
  else
    v_id := erp.adjust_account(v_company, v_prefix, case v_prefix
      when '480' then 'Gastos anticipados' when '485' then 'Ingresos anticipados'
      when '4009' then 'Proveedores, facturas pendientes de recibir o de formalizar'
      else 'Clientes, facturas pendientes de formalizar' end);
    select * into v_bal from erp.gl_accounts where id = v_id;   -- (la función, fuera del where: crea la cuenta)
  end if;

  if p->>'invoice_id' is not null then
    select * into v_inv from erp.invoices i where i.id = (p->>'invoice_id')::uuid and i.company_id = v_company;
    if not found then raise exception 'The invoice must belong to this company'; end if;
  end if;

  -- Importe: dado, o calculado por meses desde el total
  if v_total is not null then
    if v_total <= 0 then raise exception 'The total amount must be greater than zero'; end if;
    if v_start is null or v_months is null or v_months <= 0 then
      raise exception 'To calculate the accrual give the start date and the months the amount covers';
    end if;
    v_amount := case when v_kind in ('prepaid_expense', 'deferred_income')
                     then v_total - erp.accrual_elapsed(v_total, v_start, v_months, v_date)
                     else erp.accrual_elapsed(v_total, v_start, v_months, v_date) end;
    if v_amount <= 0 then
      raise exception 'Nothing to accrue at %: the period % the cut-off date', v_date,
        case when v_kind in ('prepaid_expense', 'deferred_income') then 'ends before' else 'starts after' end;
    end if;
  else
    v_amount := round((p->>'amount')::numeric, 2);
    v_start := null; v_months := null;
    if v_amount is null or v_amount <= 0 then raise exception 'The amount must be greater than zero'; end if;
  end if;

  select 'PER-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.accruals a where a.company_id = v_company;
  v_entry := case
    when v_kind in ('prepaid_expense', 'accrued_income')
      then erp.adjust_post(v_company, v_date, 'Periodificación ' || v_code || ' · ' || v_desc, v_inv.invoice_no, v_bal.id, v_pl.id, v_amount)
    else erp.adjust_post(v_company, v_date, 'Periodificación ' || v_code || ' · ' || v_desc, v_inv.invoice_no, v_pl.id, v_bal.id, v_amount) end;
  insert into erp.accruals (company_id, code, kind, description, pl_account_id, balance_account_id, cutoff_date, amount,
                            total_amount, coverage_start, coverage_months, invoice_id, entry_id)
  values (v_company, v_code, v_kind, v_desc, v_pl.id, v_bal.id, v_date, v_amount,
          v_total, v_start, v_months, v_inv.id, v_entry)
  returning id into v_id;
  v_no := erp.adjust_finish(v_entry);
  accrual_id := v_id; code := v_code; entry_no := v_no; amount := v_amount;
  return next;
end $function$
;
