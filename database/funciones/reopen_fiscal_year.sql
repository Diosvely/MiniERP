-- =====================================================================
-- erp.reopen_fiscal_year · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.reopen_fiscal_year(p_company uuid, p_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_c    erp.year_closings;
  v_fy   erp.fiscal_years;
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can reopen the fiscal year';
  end if;
  perform pg_advisory_xact_lock(hashtext('closing/' || p_company));
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  select * into v_c from erp.year_closings where fiscal_year_id = v_fy.id and status = 'posted';
  if v_c.id is null then
    raise exception 'Fiscal year % is not closed', p_year;
  end if;
  if exists (select 1 from erp.fiscal_years where company_id = p_company and year = p_year + 1 and status = 'closed') then
    raise exception 'Reopen fiscal year % first', p_year + 1;
  end if;

  perform set_config('erp.year_closing_engine', 'on', true);
  update erp.fiscal_years set status = 'open' where id = v_fy.id;
  if v_c.opening_entry_id is not null then perform erp.reverse_entry(v_c.opening_entry_id, null, 'Reapertura del ejercicio ' || p_year); end if;
  if v_c.closing_entry_id is not null then perform erp.reverse_entry(v_c.closing_entry_id, null, 'Reapertura del ejercicio ' || p_year); end if;
  if v_c.closing_pl_entry_id is not null then perform erp.reverse_entry(v_c.closing_pl_entry_id, null, 'Reapertura del ejercicio ' || p_year); end if;
  update erp.year_closings set status = 'cancelled' where id = v_c.id;
  perform set_config('erp.year_closing_engine', 'off', true);
end $function$
;
