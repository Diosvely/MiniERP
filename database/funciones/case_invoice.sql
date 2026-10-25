-- =====================================================================
-- erp.case_invoice · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0066_complete_case   →   la vigente es la de 0066_complete_case
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.case_invoice(e uuid, p_type text, p_partner uuid, p_date date, p_doc text, p_desc text, p_lines jsonb, p_withholding text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO 'erp', 'public'
AS $function$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', p_type, 'document_kind', 'invoice',
    'partner_id', p_partner, 'invoice_date', p_date, 'external_document_no', case p_type when 'purchase' then p_doc end,
    'description', p_desc, 'withholding_code', p_withholding, 'lines', p_lines));
$function$
;
