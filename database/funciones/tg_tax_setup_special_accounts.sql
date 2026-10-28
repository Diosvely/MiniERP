-- =====================================================================
-- erp.tg_tax_setup_special_accounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0019_reverse_charge_surcharge   →   la vigente es la de 0019_reverse_charge_surcharge
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_tax_setup_special_accounts()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  c     erp.tax_codes;
  v_tax text;
  v_r   text;
begin
  select * into c from erp.tax_codes where code = new.tax_code;
  v_tax := case c.tax_type when 'VAT' then 'IVA' else 'IGIC' end;
  v_r := erp.tax_rate_text(c.rate_pct) || '%';
  if tg_op = 'INSERT' and c.rate_category = 'intra_eu_acquisition' then
    new.input_account_id  := erp.special_tax_account(new.company_id, '472', c.tax_type, '8', c.rate_pct,
      v_tax || ' soportado adq. intracomunitaria ' || v_r, 'Input VAT intra-EU acquisition ' || v_r);
    new.output_account_id := erp.special_tax_account(new.company_id, '477', c.tax_type, '8', c.rate_pct,
      v_tax || ' repercutido adq. intracomunitaria ' || v_r, 'Output VAT intra-EU acquisition ' || v_r);
  elsif tg_op = 'INSERT' and c.rate_category = 'reverse_charge' then
    new.input_account_id  := erp.special_tax_account(new.company_id, '472', c.tax_type, '9', c.rate_pct,
      v_tax || ' soportado ISP ' || v_r, 'Input ' || c.tax_type || ' reverse charge ' || v_r);
    new.output_account_id := erp.special_tax_account(new.company_id, '477', c.tax_type, '9', c.rate_pct,
      v_tax || ' repercutido ISP ' || v_r, 'Output ' || c.tax_type || ' reverse charge ' || v_r);
  end if;
  if c.equivalence_surcharge_pct is not null and new.surcharge_account_id is null and not new.blocked then
    new.surcharge_account_id := erp.special_tax_account(new.company_id, '477', 'VAT', '7', c.equivalence_surcharge_pct,
      'Recargo de equivalencia repercutido ' || erp.tax_rate_text(c.equivalence_surcharge_pct) || '%',
      'Equivalence surcharge ' || trim(trailing '.' from trim(trailing '0' from c.equivalence_surcharge_pct::text)) || '%');
  end if;
  return new;
end $function$
;
