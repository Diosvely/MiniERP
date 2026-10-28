-- =====================================================================
-- erp.loan_next_instalment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_next_instalment(p_loan uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare l erp.loans; pos jsonb; s erp.loan_schedule; v_acc numeric; v_short numeric;
begin
  select * into l from erp.loans where id = p_loan;
  if not found then raise exception 'Loan not found'; end if;
  if not erp.can_read(l.company_id) then raise exception 'No permission to read this company'; end if;
  pos := erp.loan_position(p_loan);
  select * into s from erp.loan_schedule where loan_id = p_loan and n = (pos->>'paid')::int + 1;
  if not found then return null; end if;
  v_acc := least(s.interest, (pos->>'accrued')::numeric);
  v_short := least(s.reduction, greatest(0, (pos->>'short')::numeric));
  return jsonb_build_object('loan_id', p_loan, 'code', l.code, 'kind', l.kind, 'n', s.n, 'periods', l.periods, 'due_date', s.due_date,
    'payment', s.payment, 'interest', s.interest, 'interest_expense', s.interest - v_acc, 'accrued_used', v_acc,
    'reduction', s.reduction, 'short_part', v_short, 'long_part', s.reduction - v_short,
    'purchase_option', case when s.n = l.periods then l.purchase_option else 0 end,
    'short_account_no', (select account_no from erp.gl_accounts where id = l.short_account_id),
    'long_account_no', (select account_no from erp.gl_accounts where id = l.long_account_id),
    'interest_account_no', (select account_no from erp.gl_accounts where id = l.interest_account_id),
    'accrued_account_no', (select account_no from erp.gl_accounts where id = l.accrued_account_id));
end $function$
;
