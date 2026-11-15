-- =====================================================================
-- erp.tg_fiscal_year_rules · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0095_equity_and_company_rules   →   la vigente es la de 0095_equity_and_company_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_fiscal_year_rules()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;   -- funciones de la base y administrador
  if tg_op = 'INSERT' then
    if new.status <> 'open' or new.starting_date is distinct from make_date(new.year, 1, 1)
       or new.ending_date is distinct from make_date(new.year, 12, 31) then
      raise exception 'A fiscal year is created open, from 1 January to 31 December: use erp.create_fiscal_year';
    end if;
  elsif new.company_id is distinct from old.company_id or new.year is distinct from old.year
        or new.starting_date is distinct from old.starting_date or new.ending_date is distinct from old.ending_date then
    raise exception 'The year and the dates of a fiscal year cannot be changed';
  end if;
  return new;
end $function$
;
