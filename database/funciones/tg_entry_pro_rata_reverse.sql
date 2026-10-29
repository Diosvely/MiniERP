-- =====================================================================
-- erp.tg_entry_pro_rata_reverse · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0020_pro_rata   →   la vigente es la de 0020_pro_rata
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_pro_rata_reverse()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.pro_rata_engine', true), '') <> 'on'
     and exists (select 1 from erp.pro_rata where entry_id = new.reversal_of) then
    raise exception 'This entry is a pro rata regularization: undo it from the Pro rata screen';
  end if;
  return new;
end $function$
;
