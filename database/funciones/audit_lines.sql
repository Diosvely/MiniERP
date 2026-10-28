-- =====================================================================
-- erp.audit_lines · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0037_audit_checks 0041_fixed_assets 0043_year_end_adjustments 0045_provisions 0046_asset_impairment 0047_inventory_closing 0049_payroll 0058_corporate_tax_posting 0060_equity_operations 0062_loans 0064_grants 0076_performance   →   la vigente es la de 0076_performance
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.audit_lines(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(entry_id uuid, entry_no integer, posting_date date, k uuid, source text, account_no text, account_name text, debit numeric, credit numeric, tax_code text)
 LANGUAGE sql
 STABLE
AS $function$
  select e.id, e.entry_no, e.posting_date, kk.k,
         case when exists (select 1 from erp.invoices i where i.entry_id = kk.k) then 'invoice'
              when exists (select 1 from erp.tax_settlements s where s.entry_id = kk.k) then 'settlement'
              when exists (select 1 from erp.pro_rata p where p.entry_id = kk.k) then 'pro_rata'
              -- v0.36.0: periodificaciones y deterioros (antes que los cobros: la insolvencia firme también lo es)
              when exists (select 1 from erp.accruals ac where kk.k in (ac.entry_id, ac.reversal_entry_id)) then 'accrual'
              when exists (select 1 from erp.receivable_impairments ri where kk.k in (ri.entry_id, ri.end_entry_id))
                or exists (select 1 from erp.receivable_writeoffs w where w.entry_id = kk.k) then 'impairment'
              -- v0.37.0: provisiones
              when exists (select 1 from erp.provision_movements pm where pm.entry_id = kk.k) then 'provision'
              when exists (select 1 from erp.inventory_counts ic where ic.entry_id = kk.k) then 'inventory'
              -- v0.41.0: Impuesto sobre Sociedades
              when exists (select 1 from erp.corporate_tax_returns ct
                           where kk.k in (ct.current_entry_id, ct.deferred_entry_id)) then 'corporate_tax'
              -- v0.42.0: operaciones societarias
              when exists (select 1 from erp.equity_operations eo where kk.k = any (eo.entry_ids)) then 'equity'
              -- v0.43.0: préstamos y arrendamiento financiero
              when exists (select 1 from erp.loan_events le where le.entry_id = kk.k) then 'financing'
              -- v0.44.0: subvenciones
              when exists (select 1 from erp.grant_events ge where ge.entry_id = kk.k) then 'grant'
              -- v0.38.0: nóminas y sus pagos
              when exists (select 1 from erp.payroll_runs pr
                           where kk.k in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id)) then 'payroll'
              when exists (select 1 from erp.payments py where not py.linked
                           and kk.k in (py.entry_id, py.cancel_entry_id)) then 'payment'
              when exists (select 1 from erp.asset_depreciations d where d.entry_id = kk.k)
                or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = kk.k)
                or exists (select 1 from erp.asset_events ae where ae.entry_id = kk.k) then 'asset'
              -- v0.52.1: el origen (importado) se busca por su clave; antes se cruzaba con TODOS los asientos de la base
              when (select o.import_batch_id from erp.journal_entries o where o.id = kk.k) is not null then 'import'
              else 'manual' end,
         g.account_no, g.name, l.debit, l.credit, l.tax_code
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id
  -- v0.52.1: la clave del documento (el asiento o el que anula), calculada aparte («offset 0»): así cada búsqueda de
  -- abajo usa el índice de su tabla en vez de recorrerla entera con la seguridad fila a fila
  cross join lateral (select coalesce(e.reversal_of, e.id) as k offset 0) kk
  join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company
  join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
    and (p_to_date is null or e.posting_date <= p_to_date);
$function$
;
