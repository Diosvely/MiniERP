-- =====================================================================
-- erp.tg_import_lines_caps · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_import_lines_caps()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_s   erp.temp_settings;
  v_c   uuid;
  v_n   int;
  v_cap jsonb;
begin
  select * into v_s from erp.temp_settings;
  for v_c in select distinct n.company_id from new_rows n join erp.companies c on c.id = n.company_id where c.temporary loop
    select count(*) into v_n from erp.import_lines where company_id = v_c;
    if v_n > v_s.max_lines_per_import then
      raise exception 'Too many lines for a temporary import: % (maximum %)', v_n, v_s.max_lines_per_import;
    end if;
    v_cap := erp.temp_capacity();
    if (v_cap->>'lines')::int > v_s.max_total_lines then
      raise exception 'Temporary companies are full right now: try again later';
    end if;
  end loop;
  return null;
end $function$
;
