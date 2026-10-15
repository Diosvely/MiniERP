-- =====================================================================
-- erp.invoice_pending · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0035_payments   →   la vigente es la de 0035_payments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.invoice_pending(p_invoice uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select pending from erp.open_items((select company_id from erp.invoices where id = p_invoice), '9999-12-31')
  where invoice_id = p_invoice;
$function$
;
