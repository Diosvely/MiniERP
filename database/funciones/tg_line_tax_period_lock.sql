-- =====================================================================
-- erp.tg_line_tax_period_lock · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0012_tax_settlement 0017_year_closing 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_line_tax_period_lock()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_entry  erp.journal_entries;
  v_type   text;
  v_q      erp.tax_settlements;
begin
  if coalesce(current_setting('erp.tax_settlement_engine', true), '') = 'on'
     or coalesce(current_setting('erp.year_closing_engine', true), '') = 'on'
     or coalesce(current_setting('erp.import_engine', true), '') = 'on'
     or coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return new;
  end if;
  select * into v_entry from erp.journal_entries where id = new.entry_id;
  select c.tax_type into v_type
  from erp.tax_setup s join erp.tax_codes c on c.code = s.tax_code
  where s.company_id = v_entry.company_id and new.gl_account_id in (s.input_account_id, s.output_account_id)
  limit 1;
  if v_type is null then
    return new;
  end if;
  select * into v_q from erp.tax_settlements
  where company_id = v_entry.company_id and tax_type = v_type and status = 'posted'
    and v_entry.posting_date <= period_end
  order by period_end desc limit 1;
  if found then
    raise exception '% quarter %T % is already settled: post this with a later date (or cancel the settlement)',
      v_type, v_q.quarter, v_q.year;
  end if;
  return new;
end $function$
;
