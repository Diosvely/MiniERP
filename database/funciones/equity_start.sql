-- =====================================================================
-- erp.equity_start · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_start(p_company uuid, p_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_fy erp.fiscal_years; v_code text;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post equity operations in this company'; end if;
  if p_date is null then raise exception 'The date is required'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date;
  if not found then raise exception 'No fiscal year for date %: create it first', p_date; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', v_fy.year; end if;
  perform pg_advisory_xact_lock(hashtext('equity/' || p_company));
  select 'SOC-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.equity_operations where company_id = p_company;
  return v_code;
end $function$
;
