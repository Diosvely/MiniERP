-- =====================================================================
-- erp.post_entry · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0004_journal_entries   →   la vigente es la de 0004_journal_entries
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.post_entry(p_entry uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_e       erp.journal_entries;
  v_debit   numeric(15,2);
  v_credit  numeric(15,2);
  v_lines   int;
  v_period  erp.accounting_periods;
  v_fy      erp.fiscal_years;
  v_no      int;
begin
  select * into v_e from erp.journal_entries where id = p_entry for update;
  if not found then
    raise exception 'Entry not found (or no permission)';
  end if;
  if v_e.status <> 'draft' then
    raise exception 'Entry is already posted with number %', v_e.entry_no;
  end if;

  select coalesce(sum(debit), 0), coalesce(sum(credit), 0), count(*)
  into v_debit, v_credit, v_lines
  from erp.journal_lines where entry_id = p_entry;

  if v_lines < 2 then
    raise exception 'An entry needs at least 2 lines (it has %)', v_lines;
  end if;
  if v_debit <> v_credit then
    raise exception 'Unbalanced entry: debit % ≠ credit % (difference %)', v_debit, v_credit, v_debit - v_credit;
  end if;

  -- Bloqueo por ejercicio: si dos usuarios contabilizan a la vez, uno espera → sin huecos ni duplicados
  perform pg_advisory_xact_lock(hashtext(v_e.fiscal_year_id::text));
  select * into v_fy from erp.fiscal_years where id = v_e.fiscal_year_id;
  if v_fy.status <> 'open' then
    raise exception 'Fiscal year % is closed', v_fy.year;
  end if;

  select * into v_period from erp.accounting_periods
  where fiscal_year_id = v_e.fiscal_year_id and v_e.posting_date between starting_date and ending_date;
  if v_period.status <> 'open' then
    raise exception 'Period % of % is closed', v_period.period_no, v_fy.year;
  end if;

  select coalesce(max(entry_no), 0) + 1 into v_no
  from erp.journal_entries where fiscal_year_id = v_e.fiscal_year_id;

  update erp.journal_entries
  set status = 'posted', entry_no = v_no, posted_at = now()
  where id = p_entry;

  return v_no;
end $function$
;
