-- =====================================================================
-- erp.tg_tax_settlement_protect · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0012_tax_settlement   →   la vigente es la de 0012_tax_settlement
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_tax_settlement_protect()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on'
     or coalesce(current_setting('erp.tax_settlement_engine', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'Tax settlements are created only with post_tax_settlement()';
end $function$
;
