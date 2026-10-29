-- =====================================================================
-- erp.case_payment · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0066_complete_case   →   la vigente es la de 0066_complete_case
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.case_payment(e uuid, p_type text, p_partner uuid, p_date date, p_invoice uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
begin
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', p_type, 'partner_id', p_partner,
    'payment_date', p_date, 'cash_account_no', '57200001',
    'applications', jsonb_build_array(jsonb_build_object('invoice_id', p_invoice,
      'amount', (select i.total_amount - coalesce(i.withholding_amount, 0) from erp.invoices i where i.id = p_invoice)))));
end $function$
;
