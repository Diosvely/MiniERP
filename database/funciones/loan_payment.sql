-- =====================================================================
-- erp.loan_payment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_payment(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare l erp.loans; x jsonb; v_date date; a_bank uuid; v_entry uuid;
begin
  select * into l from erp.loans where id = (p->>'loan_id')::uuid;
  if not found then raise exception 'Loan not found'; end if;
  if l.status <> 'active' then raise exception 'The loan is not active (%)', l.status; end if;
  if l.kind = 'leasing' then raise exception 'A finance lease instalment has VAT: register the invoice of the leasing company'; end if;
  x := erp.loan_next_instalment(l.id);
  v_date := coalesce((p->>'date')::date, (x->>'due_date')::date);
  perform erp.loan_check(l.company_id, v_date);
  if v_date < (select max(event_date) from erp.loan_events where loan_id = l.id and status = 'posted') then
    raise exception 'The date is earlier than the last posting of this loan';
  end if;
  a_bank := case when nullif(btrim(p->>'bank_account_no'), '') is not null then erp.equity_bank(l.company_id, p->>'bank_account_no')
                 else coalesce(l.bank_account_id, erp.equity_bank(l.company_id, null)) end;
  v_entry := erp.equity_entry(l.company_id, v_date, 'Préstamo · cuota ' || (x->>'n') || '/' || l.periods || ' · ' || l.description, l.code,
               jsonb_build_array(erp.equity_line(l.accrued_account_id, (x->>'accrued_used')::numeric, 0),
                                 erp.equity_line(l.interest_account_id, (x->>'interest_expense')::numeric, 0),
                                 erp.equity_line(l.short_account_id, (x->>'short_part')::numeric, 0),
                                 erp.equity_line(l.long_account_id, (x->>'long_part')::numeric, 0),
                                 erp.equity_line(a_bank, 0, (x->>'payment')::numeric)));
  insert into erp.loan_events (loan_id, company_id, kind, event_date, n, amount, interest, accrued_used, short_part, long_part, entry_id)
  values (l.id, l.company_id, 'payment', v_date, (x->>'n')::int, (x->>'payment')::numeric, (x->>'interest_expense')::numeric,
          (x->>'accrued_used')::numeric, (x->>'short_part')::numeric, (x->>'long_part')::numeric, v_entry);
  if (x->>'n')::int = l.periods then update erp.loans set status = 'repaid' where id = l.id; end if;
  return x || jsonb_build_object('date', v_date, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $function$
;
