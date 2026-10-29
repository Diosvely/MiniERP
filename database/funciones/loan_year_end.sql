-- =====================================================================
-- erp.loan_year_end · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_year_end(p_company uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare pv jsonb; x jsonb; l erp.loans; v_entry uuid; v_amt numeric; v_posted int := 0;
begin
  perform erp.loan_check(p_company, p_date);
  pv := erp.loan_year_end_preview(p_company, p_date);
  for x in select * from jsonb_array_elements(pv->'loans') loop
    select * into l from erp.loans where id = (x->>'loan_id')::uuid;
    if (x->>'overdue')::boolean then
      raise exception 'Instalment of % due on % is not posted: post it first', l.code, x->>'overdue_due_date';
    end if;
    if exists (select 1 from erp.loan_events where loan_id = l.id and status = 'posted' and event_date > p_date) then
      raise exception '% has postings after %', l.code, p_date;
    end if;
    v_amt := (x->>'accrual')::numeric;
    if v_amt > 0 then
      v_entry := erp.equity_entry(p_company, p_date, 'Intereses devengados y no vencidos · ' || l.description, l.code,
                   jsonb_build_array(erp.equity_line(l.interest_account_id, v_amt, 0), erp.equity_line(l.accrued_account_id, 0, v_amt)));
      insert into erp.loan_events (loan_id, company_id, kind, event_date, n, amount, entry_id)
      values (l.id, p_company, 'accrual', p_date, (x->>'accrual_n')::int, v_amt, v_entry);
      v_posted := v_posted + 1;
    end if;
    v_amt := (x->>'reclassification')::numeric;
    if v_amt <> 0 then
      v_entry := erp.equity_entry(p_company, p_date, 'Reclasificación a corto plazo · ' || l.description, l.code,
                   case when v_amt > 0 then jsonb_build_array(erp.equity_line(l.long_account_id, v_amt, 0), erp.equity_line(l.short_account_id, 0, v_amt))
                        else jsonb_build_array(erp.equity_line(l.short_account_id, -v_amt, 0), erp.equity_line(l.long_account_id, 0, -v_amt)) end);
      insert into erp.loan_events (loan_id, company_id, kind, event_date, amount, entry_id)
      values (l.id, p_company, 'reclassification', p_date, v_amt, v_entry);
      v_posted := v_posted + 1;
    end if;
  end loop;
  return pv || jsonb_build_object('entries', v_posted);
end $function$
;
