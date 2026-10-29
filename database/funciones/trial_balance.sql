-- =====================================================================
-- erp.trial_balance · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0005_reports 0021_journal_import 0074_report_simulation 0077_large_companies   →   la vigente es la de 0077_large_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.trial_balance(p_company uuid, p_year integer, p_level integer DEFAULT NULL::integer, p_to_date date DEFAULT NULL::date, p_drafts boolean DEFAULT false)
 RETURNS TABLE(account_no text, name text, name_en text, total_debit numeric, total_credit numeric, debit_balance numeric, credit_balance numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_report(p_company) then return; end if;   -- v0.52.2: el permiso, una vez (no en cada fila)
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with mov as (
    select case when p_level is null then a.account_no else left(a.account_no, p_level) end as account_no,
           l.debit, l.credit
    from erp.journal_lines l
    join erp.journal_entries e  on e.id = l.entry_id
    join erp.fiscal_years    fy on fy.id = e.fiscal_year_id
    join erp.gl_accounts     a  on a.id = l.gl_account_id
    where e.company_id = p_company and l.company_id = p_company
      and fy.year = p_year
      and erp.counts_in_reports(e.status, e.id)
      and e.entry_type <> 'closing'            -- sin el asiento de cierre: si no, un año cerrado sale todo a cero
      and (p_to_date is null or e.posting_date <= p_to_date)
  )
  select m.account_no,
         a.name,
         a.name_en,
         sum(m.debit),
         sum(m.credit),
         greatest(sum(m.debit) - sum(m.credit), 0),
         greatest(sum(m.credit) - sum(m.debit), 0)
  from mov m
  left join erp.gl_accounts a on a.company_id = p_company and a.account_no = m.account_no
  group by m.account_no, a.name, a.name_en
  order by m.account_no;
  perform set_config('erp.simulate', v_prev, true);
end $function$
;
