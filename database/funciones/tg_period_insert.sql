-- =====================================================================
-- erp.tg_period_insert · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0095_equity_and_company_rules   →   la vigente es la de 0095_equity_and_company_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_period_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare v_year int;
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;   -- funciones de la base y administrador
  select year into v_year from erp.fiscal_years where id = new.fiscal_year_id;
  if new.starting_date is distinct from make_date(v_year, new.period_no, 1)
     or new.ending_date is distinct from (make_date(v_year, new.period_no, 1) + interval '1 month - 1 day')::date
     or new.status <> 'open' then
    raise exception 'A month of the fiscal year is created open and with its own dates: use erp.create_fiscal_year';
  end if;
  return new;
end $function$
;
