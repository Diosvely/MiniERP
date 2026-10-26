-- =====================================================================
-- erp.tg_entry_work_month · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0069_monthly_accounting   →   la vigente es la de 0069_monthly_accounting
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_work_month()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v_p erp.accounting_periods; v_start date;
begin
  if new.status <> 'posted' or new.entry_type <> 'normal' or (tg_op = 'UPDATE' and old.status = 'posted') then return new; end if;
  select c.start_date into v_start from erp.companies c where c.id = new.company_id and c.monthly;
  if not found then return new; end if;
  if new.posting_date < v_start then
    raise exception 'Monthly accounting: the accounting starts on %', to_char(v_start, 'DD/MM/YYYY');
  end if;
  v_p := erp.work_period(new.company_id);
  if v_p.fiscal_year_id is not null and new.posting_date > v_p.ending_date then
    raise exception 'Monthly accounting: the open month is % (% to %); close it before posting on %',
      to_char(v_p.starting_date, 'MM/YYYY'), to_char(v_p.starting_date, 'DD/MM/YYYY'), to_char(v_p.ending_date, 'DD/MM/YYYY'),
      to_char(new.posting_date, 'DD/MM/YYYY');
  end if;
  return new;
end $function$
;
