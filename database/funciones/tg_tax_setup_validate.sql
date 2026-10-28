-- =====================================================================
-- erp.tg_tax_setup_validate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0010_tax_setup 0019_reverse_charge_surcharge   →   la vigente es la de 0019_reverse_charge_surcharge
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_tax_setup_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_rate numeric;
begin
  select rate_pct into v_rate from erp.tax_codes where code = new.tax_code;
  perform erp.check_tax_account(new.company_id, new.input_account_id,  '472', 'input tax');
  perform erp.check_tax_account(new.company_id, new.output_account_id, '477', 'output tax');
  perform erp.check_tax_account(new.company_id, new.surcharge_account_id, '477', 'equivalence surcharge');
  if v_rate > 0 and not new.blocked and (new.input_account_id is null or new.output_account_id is null) then
    raise exception 'Tax code % needs an input (472) and an output (477) account', new.tax_code;
  end if;
  return new;
end $function$
;
