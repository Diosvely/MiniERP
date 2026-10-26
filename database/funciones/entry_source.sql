-- =====================================================================
-- erp.entry_source · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0070_entries_screen   →   la vigente es la de 0070_entries_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.entry_source(e erp.journal_entries)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select
        CASE
            WHEN e.import_batch_id IS NOT NULL THEN 'import'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.invoices i
              WHERE (i.entry_id = e.id))) THEN 'invoice'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.tax_settlements s
              WHERE ((s.entry_id = e.id) OR (s.entry_id = e.reversal_of)))) THEN 'settlement'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.year_closings c
              WHERE (((COALESCE(e.reversal_of, e.id) = c.closing_pl_entry_id) OR (COALESCE(e.reversal_of, e.id) = c.closing_entry_id)) OR (COALESCE(e.reversal_of, e.id) = c.opening_entry_id)))) THEN 'closing'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.accruals ac
              WHERE ((COALESCE(e.reversal_of, e.id) = ac.entry_id) OR (COALESCE(e.reversal_of, e.id) = ac.reversal_entry_id)))) THEN 'accrual'::text
            WHEN ((EXISTS ( SELECT 1
               FROM erp.receivable_impairments ri
              WHERE ((COALESCE(e.reversal_of, e.id) = ri.entry_id) OR (COALESCE(e.reversal_of, e.id) = ri.end_entry_id)))) OR (EXISTS ( SELECT 1
               FROM erp.receivable_writeoffs w
              WHERE (w.entry_id = COALESCE(e.reversal_of, e.id))))) THEN 'impairment'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.provision_movements pm
              WHERE (pm.entry_id = COALESCE(e.reversal_of, e.id)))) THEN 'provision'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.inventory_counts ic
              WHERE (ic.entry_id = COALESCE(e.reversal_of, e.id)))) THEN 'inventory'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.corporate_tax_returns ct
              WHERE ((COALESCE(e.reversal_of, e.id) = ct.current_entry_id) OR (COALESCE(e.reversal_of, e.id) = ct.deferred_entry_id)))) THEN 'corporate_tax'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.equity_operations eo
              WHERE (COALESCE(e.reversal_of, e.id) = ANY (eo.entry_ids)))) THEN 'equity'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.loan_events le
              WHERE (le.entry_id = COALESCE(e.reversal_of, e.id)))) THEN 'financing'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.grant_events ge
              WHERE (ge.entry_id = COALESCE(e.reversal_of, e.id)))) THEN 'grant'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.payroll_runs pr
              WHERE (((COALESCE(e.reversal_of, e.id) = pr.entry_id) OR (COALESCE(e.reversal_of, e.id) = pr.net_payment_entry_id)) OR (COALESCE(e.reversal_of, e.id) = pr.ss_payment_entry_id)))) THEN 'payroll'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.payments py
              WHERE ((NOT py.linked) AND ((py.entry_id = e.id) OR (py.cancel_entry_id = e.id))))) THEN 'payment'::text
            WHEN ((EXISTS ( SELECT 1
               FROM erp.asset_depreciations d
              WHERE (d.entry_id = COALESCE(e.reversal_of, e.id)))) OR (EXISTS ( SELECT 1
               FROM erp.fixed_assets fa
              WHERE (fa.disposal_entry_id = COALESCE(e.reversal_of, e.id)))) OR (EXISTS ( SELECT 1
               FROM erp.asset_events ae
              WHERE (ae.entry_id = COALESCE(e.reversal_of, e.id))))) THEN 'asset'::text
            WHEN (e.reversal_of IS NOT NULL) THEN 'reversal'::text
            ELSE 'manual'::text
        END;
$function$
;
