-- =====================================================================
-- erp.loan_accrual_amount · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_accrual_amount(p_loan uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  l erp.loans; v_paid int; s erp.loan_schedule; v_from date; v_bal numeric; f numeric; v_total numeric; v_done numeric;
begin
  select * into l from erp.loans where id = p_loan;
  v_paid := (erp.loan_position(p_loan)->>'paid')::int;
  select * into s from erp.loan_schedule where loan_id = p_loan and n = v_paid + 1;
  if not found or l.start_date > p_date then return null; end if;
  if s.due_date <= p_date then
    return jsonb_build_object('n', s.n, 'amount', 0, 'overdue', true, 'due_date', s.due_date);
  end if;
  if v_paid = 0 then v_from := l.start_date; v_bal := l.net_amount;
  else
    select due_date + 1, balance into v_from, v_bal from erp.loan_schedule where loan_id = p_loan and n = v_paid;
  end if;
  f := least(1, greatest(0, erp.loan_days360(v_from, p_date + 1)::numeric / (360 / l.frequency)));
  v_total := least(s.interest, round(v_bal * (power(1 + l.effective_rate, f) - 1), 2));
  select coalesce(sum(amount), 0) into v_done from erp.loan_events where loan_id = p_loan and kind = 'accrual' and n = s.n and status = 'posted';
  return jsonb_build_object('n', s.n, 'amount', greatest(0, v_total - v_done), 'fraction', round(f, 6), 'days', erp.loan_days360(v_from, p_date + 1),
                            'overdue', false, 'due_date', s.due_date);
end $function$
;
