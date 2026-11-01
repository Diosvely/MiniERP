-- =====================================================================
-- erp.audit_lines_checks · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0079_checks_relevant_lines   →   la vigente es la de 0079_checks_relevant_lines
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.audit_lines_checks(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS SETOF erp.audit_line
 LANGUAGE sql
 STABLE SECURITY DEFINER ROWS 20000
 SET search_path TO 'erp', 'public'
AS $function$
  with docs as (
    select i.entry_id as k, 1 as p, 'invoice' as s from erp.invoices i where i.company_id = p_company
    union all select s.entry_id, 2, 'settlement' from erp.tax_settlements s where s.company_id = p_company
    union all select p.entry_id, 3, 'pro_rata' from erp.pro_rata p where p.company_id = p_company
    -- v0.36.0: periodificaciones y deterioros (antes que los cobros: la insolvencia firme también lo es)
    union all select x, 4, 'accrual' from erp.accruals ac, unnest(array[ac.entry_id, ac.reversal_entry_id]) x where ac.company_id = p_company
    union all select x, 5, 'impairment' from erp.receivable_impairments ri, unnest(array[ri.entry_id, ri.end_entry_id]) x where ri.company_id = p_company
    union all select w.entry_id, 5, 'impairment' from erp.receivable_writeoffs w where w.company_id = p_company
    -- v0.37.0: provisiones · v0.36.0: existencias
    union all select pm.entry_id, 6, 'provision' from erp.provision_movements pm where pm.company_id = p_company
    union all select ic.entry_id, 7, 'inventory' from erp.inventory_counts ic where ic.company_id = p_company
    -- v0.41.0: Impuesto sobre Sociedades · v0.42.0: operaciones societarias
    union all select x, 8, 'corporate_tax' from erp.corporate_tax_returns ct, unnest(array[ct.current_entry_id, ct.deferred_entry_id]) x where ct.company_id = p_company
    union all select x, 9, 'equity' from erp.equity_operations eo, unnest(eo.entry_ids) x where eo.company_id = p_company
    -- v0.43.0: préstamos y arrendamiento financiero · v0.44.0: subvenciones
    union all select le.entry_id, 10, 'financing' from erp.loan_events le where le.company_id = p_company
    union all select ge.entry_id, 11, 'grant' from erp.grant_events ge where ge.company_id = p_company
    -- v0.38.0: nóminas y sus pagos
    union all select x, 12, 'payroll' from erp.payroll_runs pr, unnest(array[pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id]) x where pr.company_id = p_company
    union all select x, 13, 'payment' from erp.payments py, unnest(array[py.entry_id, py.cancel_entry_id]) x where py.company_id = p_company and not py.linked
    union all select d.entry_id, 14, 'asset' from erp.asset_depreciations d where d.company_id = p_company
    union all select fa.disposal_entry_id, 14, 'asset' from erp.fixed_assets fa where fa.company_id = p_company
    union all select ae.entry_id, 14, 'asset' from erp.asset_events ae where ae.company_id = p_company
  ), src as (
    select d.k, (array_agg(d.s order by d.p))[1] as s from docs d where d.k is not null group by d.k
  )
, ents as (
    -- los asientos del ejercicio (por su índice), con su origen
    select e.id, e.entry_no, e.posting_date, coalesce(e.reversal_of, e.id) as k,
           coalesce(src.s, case when (case when e.reversal_of is null then e.import_batch_id
                                           else (select o.import_batch_id from erp.journal_entries o where o.id = e.reversal_of) end)
                                     is not null then 'import' else 'manual' end) as source
    from (select e.* from erp.journal_entries e
          where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
            and e.company_id = p_company and e.status = 'posted' and e.entry_type = 'normal'
            and (p_to_date is null or e.posting_date <= p_to_date) and erp.can_report(p_company)
          offset 0) e
    left join src on src.k = coalesce(e.reversal_of, e.id)
  ), lines as (
    select l.id, l.entry_id, l.gl_account_id, l.debit, l.credit, l.tax_code
    from erp.journal_lines l
    where l.company_id = p_company
      and l.gl_account_id in (select g.id from erp.gl_accounts g where g.company_id = p_company and g.account_no like '47%')
    union
    select l.id, l.entry_id, l.gl_account_id, l.debit, l.credit, l.tax_code
    from erp.journal_lines l
    where l.company_id = p_company and l.tax_code is not null
    union
    select l.id, l.entry_id, l.gl_account_id, l.debit, l.credit, l.tax_code
    from ents e cross join lateral (select jl.* from erp.journal_lines jl where jl.entry_id = e.id offset 0) l
    where e.source = 'manual'
  )
  select e.id, e.entry_no, e.posting_date, e.k, e.source, g.account_no, g.name, l.debit, l.credit, l.tax_code
  from lines l
  join ents e on e.id = l.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id;
$function$
;
