-- =====================================================================
-- erp.provision_balance · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.provision_balance(p_provision uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce((select m.balance_after from erp.provision_movements m where m.provision_id = p_provision
                   order by m.seq desc limit 1), 0);
$function$
;
