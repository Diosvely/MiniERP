-- =====================================================================
-- erp.start_accounting · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0069_monthly_accounting   →   la vigente es la de 0069_monthly_accounting
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.start_accounting(p_company uuid, p_start date, p_monthly boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_fy uuid;
begin
  if not erp.is_admin(p_company) then raise exception 'No permission: only the company admin can set the start date'; end if;
  if p_start is null then raise exception 'The start date is required'; end if;
  if exists (select 1 from erp.journal_entries j where j.company_id = p_company) then
    raise exception 'The company already has entries: the start date can only be set in a new company';
  end if;
  select id into v_fy from erp.fiscal_years where company_id = p_company and year = extract(year from p_start)::int;
  if v_fy is null then v_fy := erp.create_fiscal_year(p_company, extract(year from p_start)::int); end if;
  update erp.companies set start_date = p_start, monthly = coalesce(p_monthly, false) where id = p_company;
  update erp.accounting_periods set status = case when p_monthly and ending_date < date_trunc('month', p_start)::date then 'closed' else 'open' end
  where fiscal_year_id = v_fy;
  return erp.work_month(p_company);
end $function$
;
