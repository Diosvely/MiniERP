-- =====================================================================
-- erp.grant_check · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_check(p_company uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v_fy erp.fiscal_years;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post grants in this company'; end if;
  if p_date is null then raise exception 'The date is required'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date;
  if not found then raise exception 'No fiscal year for date %: create it first', p_date; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', v_fy.year; end if;
  perform pg_advisory_xact_lock(hashtext('grants/' || p_company));
end $function$
;
