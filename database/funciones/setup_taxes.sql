-- =====================================================================
-- erp.setup_taxes · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0010_tax_setup   →   la vigente es la de 0010_tax_setup
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.setup_taxes(p_company uuid, p_tax_type text DEFAULT NULL::text)
 RETURNS TABLE(tax_code text, account_role text, account_no text, status text)
 LANGUAGE plpgsql
AS $function$
declare
  v_type    text;
  v_digits  smallint;
  v_territory text;
  v_tax     text;      -- 'IVA' / 'IGIC' para los nombres
  v_mid     text;      -- 0 = IVA, 1 = IGIC (4.º dígito de la subcuenta)
  t         erp.tax_codes;
  v_suffix  text;
  v_in      uuid;
  v_out     uuid;
  v_status  text;
  v_no      text;
  v_pay     uuid;
  v_rec     uuid;
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can configure taxes';
  end if;
  select posting_account_digits, tax_territory into v_digits, v_territory from erp.companies where id = p_company;
  v_type := coalesce(p_tax_type, case v_territory when 'canary_islands' then 'IGIC' else 'VAT' end);
  if v_type not in ('VAT', 'IGIC') then
    raise exception 'Invalid tax type: %', v_type;
  end if;
  v_tax := case v_type when 'VAT' then 'IVA' else 'IGIC' end;
  v_mid := case v_type when 'VAT' then '0' else '1' end;

  -- 1) Un registro por tipo vigente hoy
  for t in
    select * from erp.tax_codes c
    where c.tax_type = v_type and c.valid_from <= current_date
      and (c.valid_to is null or c.valid_to >= current_date)
    order by c.rate_pct
  loop
    if exists (select 1 from erp.tax_setup s where s.company_id = p_company and s.tax_code = t.code) then
      tax_code := t.code; account_role := null; account_no := null; status := 'existing';
      return next;
      continue;
    end if;

    v_in := null; v_out := null;
    if t.rate_pct > 0 then
      v_suffix := lpad(case when t.rate_pct = trunc(t.rate_pct) then t.rate_pct::int::text
                            else (t.rate_pct * 10)::int::text end, v_digits - 4, '0');

      v_no := '472' || v_mid || v_suffix;
      v_status := 'linked';
      select e.status, e.account_id into v_status, v_in
      from erp.ensure_tax_account(p_company, v_no,
             v_tax || ' soportado ' || erp.tax_rate_text(t.rate_pct) || '%',
             'Input ' || v_type || ' ' || trim(trailing '.' from trim(trailing '0' from t.rate_pct::text)) || '%',
             v_status) e;
      tax_code := t.code; account_role := 'input'; account_no := v_no; status := v_status;
      return next;

      v_no := '477' || v_mid || v_suffix;
      v_status := 'linked';
      select e.status, e.account_id into v_status, v_out
      from erp.ensure_tax_account(p_company, v_no,
             v_tax || ' repercutido ' || erp.tax_rate_text(t.rate_pct) || '%',
             'Output ' || v_type || ' ' || trim(trailing '.' from trim(trailing '0' from t.rate_pct::text)) || '%',
             v_status) e;
      tax_code := t.code; account_role := 'output'; account_no := v_no; status := v_status;
      return next;
    else
      tax_code := t.code; account_role := null; account_no := null; status := 'no_tax_amount';
      return next;
    end if;

    insert into erp.tax_setup (company_id, tax_code, input_account_id, output_account_id)
    values (p_company, t.code, v_in, v_out);
  end loop;

  -- 2) Cuentas de la liquidación
  if not exists (select 1 from erp.tax_settlement_setup s where s.company_id = p_company and s.tax_type = v_type) then
    v_no := '4750' || lpad(case v_type when 'VAT' then '1' else '2' end, v_digits - 4, '0');
    v_status := 'linked';
    select e.status, e.account_id into v_status, v_pay
    from erp.ensure_tax_account(p_company, v_no,
           case v_type when 'VAT' then 'Hacienda Pública, acreedora por IVA' else 'Hacienda Canaria, acreedora por IGIC' end,
           case v_type when 'VAT' then 'VAT payable' else 'IGIC payable (Canary Tax Agency)' end, v_status) e;
    tax_code := v_type; account_role := 'payable'; account_no := v_no; status := v_status;
    return next;

    v_no := '4700' || lpad(case v_type when 'VAT' then '1' else '2' end, v_digits - 4, '0');
    v_status := 'linked';
    select e.status, e.account_id into v_status, v_rec
    from erp.ensure_tax_account(p_company, v_no,
           case v_type when 'VAT' then 'Hacienda Pública, deudora por IVA' else 'Hacienda Canaria, deudora por IGIC' end,
           case v_type when 'VAT' then 'VAT receivable' else 'IGIC receivable (Canary Tax Agency)' end, v_status) e;
    tax_code := v_type; account_role := 'receivable'; account_no := v_no; status := v_status;
    return next;

    insert into erp.tax_settlement_setup (company_id, tax_type, payable_account_id, receivable_account_id)
    values (p_company, v_type, v_pay, v_rec);
  else
    tax_code := v_type; account_role := 'settlement'; account_no := null; status := 'existing';
    return next;
  end if;
end $function$
;
