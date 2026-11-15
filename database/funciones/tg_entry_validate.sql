-- =====================================================================
-- erp.tg_entry_validate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0004_journal_entries 0094_integrity_hardening 0095_equity_and_company_rules   →   la vigente es la de 0095_equity_and_company_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_fy      erp.fiscal_years;
  v_period  erp.accounting_periods;
  v_debit   numeric(15,2);
  v_credit  numeric(15,2);
  v_lines   int;
  v_next    int;
begin
  if tg_op = 'UPDATE' and old.status = 'posted' then
    -- Único cambio permitido sobre un asiento contabilizado: marcarlo como anulado.
    if (to_jsonb(new) - 'reversed_by') <> (to_jsonb(old) - 'reversed_by')
       or old.reversed_by is not null then
      raise exception 'Entry % is posted and cannot be changed. Reverse it instead.', old.entry_no;
    end if;
    return new;
  end if;

  select * into v_fy from erp.fiscal_years where id = new.fiscal_year_id;
  if v_fy.company_id <> new.company_id then
    raise exception 'The fiscal year does not belong to the company of the entry';
  end if;
  if new.posting_date not between v_fy.starting_date and v_fy.ending_date then
    raise exception 'Posting date % is outside fiscal year %', new.posting_date, v_fy.year;
  end if;

  -- v0.60.5 (SEG-14) · De borrador a contabilizado: las mismas condiciones que erp.post_entry
  if new.status = 'posted'
     and (tg_op = 'INSERT' or old.status = 'draft')
     and coalesce(current_setting('erp.import_engine', true), '') <> 'on'
     and coalesce(current_setting('erp.deleting_company', true), '') <> 'on' then
    if tg_op = 'INSERT' then
      -- Un asiento nuevo no tiene líneas todavía: nace en borrador y se contabiliza después
      raise exception 'A new entry starts as a draft: post it with erp.post_entry';
    end if;
    select coalesce(sum(debit), 0), coalesce(sum(credit), 0), count(*)
    into v_debit, v_credit, v_lines
    from erp.journal_lines where entry_id = new.id;
    if v_lines < 2 then
      raise exception 'An entry needs at least 2 lines (it has %)', v_lines;
    end if;
    if v_debit <> v_credit then
      raise exception 'Unbalanced entry: debit % ≠ credit % (difference %)', v_debit, v_credit, v_debit - v_credit;
    end if;
    if v_fy.status <> 'open' then
      raise exception 'Fiscal year % is closed', v_fy.year;
    end if;
    select * into v_period from erp.accounting_periods
    where fiscal_year_id = new.fiscal_year_id and new.posting_date between starting_date and ending_date;
    -- v0.60.6 (SEG-22) · sin mes para esa fecha, tampoco
    if not found then
      raise exception 'There is no accounting period for %', new.posting_date;
    end if;
    if v_period.status <> 'open' then
      raise exception 'Period % of % is closed', v_period.period_no, v_fy.year;
    end if;
    select coalesce(max(entry_no), 0) + 1 into v_next
    from erp.journal_entries where fiscal_year_id = new.fiscal_year_id and id <> new.id;
    if new.entry_no is distinct from v_next then
      raise exception 'The entry number must be the next one in the fiscal year (%): post it with erp.post_entry', v_next;
    end if;
  end if;
  return new;
end $function$
;
