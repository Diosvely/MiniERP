-- =====================================================================
-- erp.corporate_tax_settings · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_settings(p_return uuid, p_regime text, p_recognize boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
begin
  perform erp.corporate_tax_draft(p_return);
  update erp.corporate_tax_returns set regime = p_regime, recognize_loss_credit = coalesce(p_recognize, false) where id = p_return;
end $function$
;
