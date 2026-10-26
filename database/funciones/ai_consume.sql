-- =====================================================================
-- erp.ai_consume · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0027_members 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ai_consume(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_limit int;
  v_used  int;
begin
  if not erp.ai_allowed(p_company) then raise exception 'The AI is not enabled for you in this company'; end if;
  insert into erp.ai_usage (user_id, used_on, calls) values (auth.uid(), current_date, 1)
  on conflict (user_id, used_on) do update set calls = erp.ai_usage.calls + 1
  returning calls into v_used;
  if erp.is_owner() then
    return jsonb_build_object('used', v_used, 'limit', null, 'remaining', null);
  end if;
  v_limit := erp.ai_daily_limit();
  if v_used > v_limit then
    raise exception 'Daily AI limit reached (% per day)', v_limit;
  end if;
  return jsonb_build_object('used', v_used, 'limit', v_limit, 'remaining', v_limit - v_used);
end $function$
;
