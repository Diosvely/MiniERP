-- =====================================================================
-- erp.partner_control_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0009_partners   →   la vigente es la de 0009_partners
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.partner_control_account(p_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_type when 'customer' then '430' when 'vendor' then '400'
                     when 'creditor' then '410' when 'debtor' then '440' end;
$function$
;
