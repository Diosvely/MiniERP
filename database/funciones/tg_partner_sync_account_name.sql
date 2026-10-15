-- =====================================================================
-- erp.tg_partner_sync_account_name · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0009_partners   →   la vigente es la de 0009_partners
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_partner_sync_account_name()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.gl_account_id is not null and new.name is distinct from old.name then
    update erp.gl_accounts set name = new.name where id = new.gl_account_id;
  end if;
  return new;
end $function$
;
