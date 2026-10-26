-- =====================================================================
-- erp.temp_cleanup · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.temp_cleanup(p_rows integer DEFAULT 50000)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_c     uuid;
  v_done  int := 0;
  v_left  int;
  v_rows  int := least(greatest(p_rows, 0), 50000);
begin
  for v_c in select id from erp.companies where temporary and erp.temp_expired(expires_at, last_seen_at) order by expires_at loop
    exit when v_rows <= 0;
    loop
      v_left := erp.purge_company_step(v_c, least(5000, v_rows));
      v_rows := v_rows - 5000;
      exit when v_left = 0 or v_rows <= 0;
    end loop;
    if v_left = 0 then v_done := v_done + 1; end if;
  end loop;
  return v_done;
end $function$
;
