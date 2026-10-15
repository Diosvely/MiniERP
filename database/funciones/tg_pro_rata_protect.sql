-- =====================================================================
-- erp.tg_pro_rata_protect · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0020_pro_rata   →   la vigente es la de 0020_pro_rata
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_pro_rata_protect()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on'
     or coalesce(current_setting('erp.pro_rata_engine', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'The pro rata is changed only with set_pro_rata() and its regularization';
end $function$
;
