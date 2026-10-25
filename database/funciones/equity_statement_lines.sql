-- =====================================================================
-- erp.equity_statement_lines · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0065_grants_integration   →   la vigente es la de 0065_grants_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_statement_lines(p_company uuid, p_year integer)
 RETURNS TABLE(col text, row_code text, account_no text, amount numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with l as (
    select e.id as entry_id, coalesce(e.reversal_of, e.id) as k, e.entry_type, g.account_no, l.credit - l.debit as amount,
           erp.equity_statement_column(g.account_no) as col
    from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
    join erp.fiscal_years f on f.id = e.fiscal_year_id and f.year = p_year
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and e.entry_type not in ('closing', 'closing_pl')
  ), op as (
    select l.*, (select eo.kind from erp.equity_operations eo where l.k = any (eo.entry_ids) limit 1) as eq_kind,
           sum(case when l.account_no ~ '^(526|557)' then l.amount else 0 end) over (partition by l.entry_id) as dividends
    from l
  )
  select col, case when entry_type = 'opening' then 'start'
                   when account_no ~ '^[6789]' then 'recognised'
                   when eq_kind in ('incorporation', 'capital_increase', 'call', 'interim_dividend') then 'owners'
                   when eq_kind = 'distribution' and account_no ~ '^557' then 'owners'
                   else 'other' end, account_no, amount
  from op where col is not null and not (coalesce(eq_kind, '') = 'distribution' and account_no ~ '^129')
  union all   -- el reparto: la 129 se divide entre dividendos (con socios) y reservas (otras variaciones)
  select col, 'owners', account_no, -dividends from op where col is not null and coalesce(eq_kind, '') = 'distribution' and account_no ~ '^129'
  union all
  select col, 'other', account_no, amount + dividends from op where col is not null and coalesce(eq_kind, '') = 'distribution' and account_no ~ '^129'
  union all   -- sin asiento de apertura (primer año en el ERP o el anterior sin cerrar): el saldo final del año anterior
  select erp.equity_statement_column(g.account_no), 'start', g.account_no, l.credit - l.debit
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
  join erp.fiscal_years f on f.id = e.fiscal_year_id and f.year = p_year - 1
  join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and e.entry_type not in ('closing', 'closing_pl') and erp.equity_statement_column(g.account_no) is not null
    and not exists (select 1 from erp.journal_entries o join erp.fiscal_years fo on fo.id = o.fiscal_year_id
                    where o.company_id = p_company and fo.year = p_year and o.entry_type = 'opening' and o.status = 'posted');
$function$
;
