-- =====================================================================
-- erp.entry_is_manual · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0036_controlled_accounts 0041_fixed_assets 0043_year_end_adjustments 0045_provisions 0046_asset_impairment 0047_inventory_closing 0049_payroll 0058_corporate_tax_posting 0060_equity_operations 0062_loans   →   la vigente es la de 0062_loans
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.entry_is_manual(p_entry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select e.entry_type = 'normal' and e.reversal_of is null and e.reversed_by is null and e.import_batch_id is null
     and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
     and not exists (select 1 from erp.tax_settlements s where s.entry_id = e.id)
     and not exists (select 1 from erp.pro_rata p where p.entry_id = e.id)
     and not exists (select 1 from erp.year_closings c where e.id in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id))
     and not exists (select 1 from erp.payments py where py.entry_id = e.id and not py.linked)
     and not exists (select 1 from erp.asset_depreciations d where d.entry_id = e.id)
     and not exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = e.id)
     and not exists (select 1 from erp.asset_events ae where ae.entry_id = e.id)   -- v0.37.0
     -- v0.36.0: periodificaciones y deterioros
     and not exists (select 1 from erp.accruals ac where e.id in (ac.entry_id, ac.reversal_entry_id))
     and not exists (select 1 from erp.receivable_impairments ri where e.id in (ri.entry_id, ri.end_entry_id))
     -- v0.37.0: provisiones
     and not exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
     and not exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id)   -- v0.37.0: inventario
     and not exists (select 1 from erp.payroll_runs pr where e.id in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id))   -- v0.38.0
     and not exists (select 1 from erp.corporate_tax_returns ct where e.id in (ct.current_entry_id, ct.deferred_entry_id))   -- v0.41.0
     and not exists (select 1 from erp.equity_operations eo where e.id = any (eo.entry_ids))   -- v0.42.0
     and not exists (select 1 from erp.loan_events le where le.entry_id = e.id)   -- v0.43.0
  from erp.journal_entries e where e.id = p_entry;
$function$
;
