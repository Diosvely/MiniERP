-- =====================================================================
-- erp.tg_line_set_partner · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0009_partners   →   la vigente es la de 0009_partners
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_line_set_partner()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.partner_id is null then
    select id into new.partner_id from erp.business_partners where gl_account_id = new.gl_account_id;
  end if;
  return new;
end $function$
;
