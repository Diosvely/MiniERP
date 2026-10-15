-- =====================================================================
-- erp.special_tax_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0019_reverse_charge_surcharge   →   la vigente es la de 0019_reverse_charge_surcharge
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.special_tax_account(p_company uuid, p_root text, p_tax_type text, p_marker text, p_value numeric, p_name text, p_name_en text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
declare
  v_digits smallint;
  v_no     text;
  v_status text := 'linked';
  v_id     uuid;
begin
  select posting_account_digits into v_digits from erp.companies where id = p_company;
  v_no := p_root || case p_tax_type when 'VAT' then '0' else '1' end || p_marker
          || lpad(case when p_value = trunc(p_value) then p_value::int::text else (p_value * 10)::int::text end, v_digits - 5, '0');
  select e.account_id into v_id from erp.ensure_tax_account(p_company, v_no, p_name, p_name_en, v_status) e;
  return v_id;
end $function$
;
