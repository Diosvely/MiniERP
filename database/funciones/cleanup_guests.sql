-- =====================================================================
-- erp.cleanup_guests · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0028_guest_cleanup 0034_web_usage   →   la vigente es la de 0034_web_usage
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cleanup_guests(p_days integer DEFAULT 7)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ids uuid[];
  v_deleted integer;
begin
  if p_days is null or p_days < 1 then
    raise exception 'Guest cleanup needs at least 1 day (got %)', p_days;
  end if;

  -- Solo invitados (anónimos) y solo los antiguos: los usuarios registrados no se tocan nunca
  select array_agg(id) into v_ids
  from auth.users
  where is_anonymous and created_at < now() - make_interval(days => p_days);

  if v_ids is null then
    return 0;
  end if;

  -- Antes de borrarlos, cuántos había de cada día (para el panel de uso)
  insert into erp.guest_history (day, guests)
  select (u.created_at at time zone 'Atlantic/Canary')::date, count(*)
  from auth.users u where u.id = any (v_ids)
  group by 1
  on conflict (day) do update set guests = erp.guest_history.guests + excluded.guests;

  -- Sus filas en erp (un invitado solo puede tener el idioma; el resto, por si acaso)
  delete from erp.user_settings where user_id = any (v_ids);
  delete from erp.ai_usage      where user_id = any (v_ids);
  delete from erp.ai_feedback   where user_id = any (v_ids);
  delete from erp.company_users where user_id = any (v_ids);
  delete from erp.app_profiles  where user_id = any (v_ids);

  -- El usuario (en Supabase, sus sesiones e identidades se borran en cascada)
  delete from auth.users where id = any (v_ids) and is_anonymous;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$function$
;
