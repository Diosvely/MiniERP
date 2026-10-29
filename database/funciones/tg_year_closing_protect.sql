-- =====================================================================
-- erp.tg_year_closing_protect · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_year_closing_protect()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on'
     or coalesce(current_setting('erp.year_closing_engine', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'Year-end closings are created only with close_fiscal_year()';
end $function$
;
