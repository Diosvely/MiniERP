-- =====================================================================
-- erp.ai_refund · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0095_equity_and_company_rules 0097_closing_ecpn_and_fixes   →   la vigente es la de 0097_closing_ecpn_and_fixes
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ai_refund(p_call uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_day date;
begin
  if auth.uid() is null or erp.is_anonymous() then return false; end if;
  -- v0.60.8 (SEG-23): como mucho 3 devoluciones por usuario y día
  if (select count(*) from erp.ai_calls where user_id = auth.uid() and used_on = current_date and refunded_at is not null) >= 3 then
    return false;
  end if;
  update erp.ai_calls set refunded_at = now()
  where id = p_call and user_id = auth.uid() and refunded_at is null and created_at > now() - interval '15 minutes'
  returning used_on into v_day;
  if not found then return false; end if;
  update erp.ai_usage set calls = greatest(calls - 1, 0) where user_id = auth.uid() and used_on = v_day;
  return true;
end $function$
;
