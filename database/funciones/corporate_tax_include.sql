-- =====================================================================
-- erp.corporate_tax_include · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_include(p_adjustment uuid, p_included boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare a erp.corporate_tax_adjustments;
begin
  select * into a from erp.corporate_tax_adjustments where id = p_adjustment;
  if not found then raise exception 'Adjustment not found'; end if;
  perform erp.corporate_tax_draft(a.return_id);
  update erp.corporate_tax_adjustments set included = p_included where id = p_adjustment;
end $function$
;
