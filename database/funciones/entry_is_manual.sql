-- =====================================================================
-- erp.entry_is_manual · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0036_controlled_accounts   →   la vigente es la de 0036_controlled_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.entry_is_manual(p_entry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  -- (un asiento ya anulado tampoco cuenta: su efecto es cero; pasa al deshacer una liquidación o una prorrata)
  select e.entry_type = 'normal' and e.reversal_of is null and e.reversed_by is null and e.import_batch_id is null
     and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
     and not exists (select 1 from erp.tax_settlements s where s.entry_id = e.id)
     and not exists (select 1 from erp.pro_rata p where p.entry_id = e.id)
     and not exists (select 1 from erp.year_closings c where e.id in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id))
     and not exists (select 1 from erp.payments py where py.entry_id = e.id and not py.linked)
  from erp.journal_entries e where e.id = p_entry;
$function$
;
