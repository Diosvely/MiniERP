-- =====================================================================
-- erp.create_partner · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0009_partners   →   la vigente es la de 0009_partners
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.create_partner(p_company uuid, p_type text, p_name text, p_vat_no text DEFAULT NULL::text, p_territory text DEFAULT NULL::text, p_account_no text DEFAULT NULL::text, p_email text DEFAULT NULL::text)
 RETURNS TABLE(partner_id uuid, account_no text)
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_digits     smallint;
  v_territory  text;
  v_prefix     text := erp.partner_control_account(p_type);
  v_no         text;
  v_account    erp.gl_accounts;
  v_partner    uuid;
  v_next       bigint;
begin
  if v_prefix is null then
    raise exception 'Invalid partner type: %', p_type;
  end if;
  if not erp.can_write(p_company) then
    raise exception 'No permission to create partners in this company';
  end if;

  select posting_account_digits, tax_territory into v_digits, v_territory
  from erp.companies where id = p_company;

  -- 1) Subcuenta: la indicada o la siguiente libre
  if p_account_no is not null and btrim(p_account_no) <> '' then
    v_no := regexp_replace(p_account_no, '\s', '', 'g');
    if left(v_no, length(v_prefix)) <> v_prefix then
      raise exception 'Account % must start with % for this partner type', v_no, v_prefix;
    end if;
  else
    select coalesce(max(g.account_no::bigint), (v_prefix || repeat('0', v_digits - length(v_prefix)))::bigint) + 1
      into v_next
    from erp.gl_accounts g
    where g.company_id = p_company and g.account_type = 'posting'
      and g.account_no like v_prefix || '%' and length(g.account_no) = v_digits;
    v_no := lpad(v_next::text, v_digits, '0');
    if left(v_no, length(v_prefix)) <> v_prefix then
      raise exception 'No free accounts left under %', v_prefix;
    end if;
  end if;

  select * into v_account from erp.gl_accounts g where g.company_id = p_company and g.account_no = v_no;
  if found then
    if v_account.account_type <> 'posting' then
      raise exception 'Account % is a heading account', v_no;
    end if;
    if exists (select 1 from erp.business_partners where gl_account_id = v_account.id) then
      raise exception 'Account % already belongs to another partner', v_no;
    end if;
  else
    insert into erp.gl_accounts (company_id, account_no, name, account_type, template_account, account_category)
    values (p_company, v_no, btrim(p_name), 'posting', '', '')          -- el trigger valida y rellena la cuenta madre
    returning * into v_account;
  end if;

  -- 2) Tercero (por defecto, del mismo territorio que la empresa)
  insert into erp.business_partners (company_id, partner_type, vat_registration_no, name, tax_territory, gl_account_id, email)
  values (p_company, p_type, p_vat_no, p_name, coalesce(p_territory, v_territory), v_account.id, nullif(btrim(p_email), ''))
  returning id into v_partner;

  -- Si la subcuenta ya existía, toma el nombre del tercero
  update erp.gl_accounts set name = btrim(p_name) where id = v_account.id and name <> btrim(p_name);

  return query select v_partner, v_no;
exception
  when unique_violation then
    raise exception 'A % with tax ID % already exists in this company', p_type, erp.normalize_tax_id(p_vat_no);
end $function$
;
