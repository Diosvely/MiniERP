-- =====================================================================
-- erp.web_usage · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0034_web_usage   →   la vigente es la de 0034_web_usage
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.web_usage(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare
  v_days   int := least(greatest(coalesce(p_days, 30), 7), 90);
  v_today  date := (now() at time zone 'Atlantic/Canary')::date;
  v_from   date := v_today - (v_days - 1);
  v_owners uuid[];
  v_out    jsonb;
begin
  if not erp.is_owner() then raise exception 'Only the application owner can see the web usage'; end if;
  select coalesce(array_agg(user_id), '{}') into v_owners from erp.app_profiles where app_role = 'owner';

  with users as (   -- usuarios que no son el propietario, con su día de alta en hora de Canarias
    select u.is_anonymous, u.last_sign_in_at, (u.created_at at time zone 'Atlantic/Canary')::date as day
    from auth.users u where u.id <> all (v_owners)
  ),
  per_day as (      -- invitados vivos + invitados ya borrados, y registros, por día
    select d::date as day,
           coalesce((select count(*) from users where is_anonymous and users.day = d::date), 0)
             + coalesce((select h.guests from erp.guest_history h where h.day = d::date), 0) as guests,
           (select count(*) from users where not is_anonymous and users.day = d::date) as signups
    from generate_series(v_from, v_today, interval '1 day') d
  )
  select jsonb_build_object(
    'days', v_days,
    'today', v_today,
    'series', (select jsonb_agg(jsonb_build_object('day', day, 'guests', guests, 'signups', signups) order by day) from per_day),
    'guests_today', (select guests from per_day where day = v_today),
    'guests_7d', (select sum(guests) from per_day where day > v_today - 7),
    'guests_period', (select sum(guests) from per_day),
    'guests_total', (select count(*) from users where is_anonymous) + (select coalesce(sum(guests), 0) from erp.guest_history),
    'signups_7d', (select sum(signups) from per_day where day > v_today - 7),
    'signups_period', (select sum(signups) from per_day),
    'users_total', (select count(*) from users where not is_anonymous),
    'active_7d', (select count(*) from users where not is_anonymous and last_sign_in_at > now() - interval '7 days'),
    'companies_period', (select count(*) from erp.companies c
                         where (c.created_at at time zone 'Atlantic/Canary')::date >= v_from and not coalesce(c.created_by = any (v_owners), false)),
    'imports_period', (select count(*) from erp.import_batches b
                       where (b.created_at at time zone 'Atlantic/Canary')::date >= v_from and not coalesce(b.created_by = any (v_owners), false)),
    'ai_calls_period', (select coalesce(sum(a.calls), 0) from erp.ai_usage a
                        where a.used_on >= v_from and a.user_id <> all (v_owners))
  ) into v_out;
  return v_out;
end;
$function$
;
