-- =====================================================================
-- erp.tg_entry_adjust_reverse · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments 0045_provisions 0047_inventory_closing 0049_payroll 0058_corporate_tax_posting   →   la vigente es la de 0058_corporate_tax_posting
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_adjust_reverse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.adjust_engine', true), '') <> 'on' then
    if exists (select 1 from erp.accruals where new.reversal_of in (entry_id, reversal_entry_id)) then
      raise exception 'This entry belongs to an accrual: undo it from Year-end adjustments';
    end if;
    if exists (select 1 from erp.receivable_impairments where new.reversal_of in (entry_id, end_entry_id))
       or exists (select 1 from erp.receivable_writeoffs where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a receivable impairment: undo it from Year-end adjustments';
    end if;
    -- v0.37.0: provisiones
    if exists (select 1 from erp.provision_movements where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a provision: undo it from Year-end adjustments';
    end if;
    -- v0.37.0: inventario del cierre
    if exists (select 1 from erp.inventory_counts where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to an inventory count: undo it from Year-end adjustments';
    end if;
    -- v0.41.0: Impuesto sobre Sociedades
    if exists (select 1 from erp.corporate_tax_returns where new.reversal_of in (current_entry_id, deferred_entry_id)) then
      raise exception 'This entry belongs to the corporate income tax: undo it from Corporate tax';
    end if;
    -- v0.38.0: nóminas y sus pagos
    if exists (select 1 from erp.payroll_runs where new.reversal_of in (entry_id, net_payment_entry_id, ss_payment_entry_id)) then
      raise exception 'This entry belongs to a payroll: undo it from Payroll';
    end if;
  end if;
  return new;
end $function$
;
