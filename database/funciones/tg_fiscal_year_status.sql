-- =====================================================================
-- erp.tg_fiscal_year_status · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_fiscal_year_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
begin
  if new.status <> old.status and coalesce(current_setting('erp.year_closing_engine', true), '') <> 'on' then
    raise exception 'Use the year-end closing to close or reopen fiscal year %', old.year;
  end if;
  return new;
end $function$
;
