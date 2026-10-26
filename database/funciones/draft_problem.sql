-- =====================================================================
-- erp.draft_problem · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0070_entries_screen   →   la vigente es la de 0070_entries_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.draft_problem(p_entry uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare e erp.journal_entries; v_co erp.companies; v_n int; v_d numeric; v_c numeric; v_fy erp.fiscal_years; v_per erp.accounting_periods; v_wp erp.accounting_periods;
begin
  select * into e from erp.journal_entries where id = p_entry;
  if e.status <> 'draft' then return null; end if;
  select * into v_co from erp.companies where id = e.company_id;
  select count(*) filter (where debit <> 0 or credit <> 0), coalesce(sum(debit), 0), coalesce(sum(credit), 0)
    into v_n, v_d, v_c from erp.journal_lines where entry_id = p_entry;
  if v_n = 0 then return 'empty'; end if;
  if v_n < 2 then return 'one_line'; end if;
  if v_d <> v_c then return 'unbalanced'; end if;
  select * into v_fy from erp.fiscal_years where id = e.fiscal_year_id;
  if v_fy.id is null then return 'no_year'; end if;
  if v_fy.status <> 'open' then return 'year_closed'; end if;
  select * into v_per from erp.accounting_periods where fiscal_year_id = v_fy.id and e.posting_date between starting_date and ending_date;
  if v_per.status <> 'open' then return 'period_closed'; end if;
  if v_co.monthly then
    if e.posting_date < v_co.start_date then return 'before_start'; end if;
    v_wp := erp.work_period(e.company_id);
    if v_wp.fiscal_year_id is not null and e.posting_date > v_wp.ending_date then return 'after_month'; end if;
  end if;
  if v_co.control_mode = 'strict' and jsonb_array_length(coalesce(erp.entry_controlled_lines(p_entry), '[]'::jsonb)) > 0 then
    return 'controlled';
  end if;
  return null;
end $function$
;
