-- =====================================================================
-- erp.create_provision · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0045_provisions   →   la vigente es la de 0045_provisions
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.create_provision(p jsonb)
 RETURNS TABLE(provision_id uuid, code text, entry_no integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_kind    text := p->>'kind';
  v_term    text := case when p->>'kind' = 'commercial' then 'short' else coalesce(p->>'term', 'long') end;
  v_date    date := (p->>'provision_date')::date;
  v_amount  numeric := round((p->>'amount')::numeric, 2);
  v_desc    text := btrim(coalesce(p->>'description', ''));
  v_exp     erp.gl_accounts;
  v_prov    erp.provisions;
  v_code    text;
  v_entry   uuid;
  v_no      int;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register provisions in this company'; end if;
  if v_kind is null or v_kind not in ('taxes', 'liabilities', 'commercial') then raise exception 'Invalid provision type: %', v_kind; end if;
  if v_term not in ('long', 'short') then raise exception 'Invalid provision term: %', v_term; end if;
  if v_desc = '' then raise exception 'The provision needs a description'; end if;
  if v_date is null then raise exception 'The provision date is required'; end if;
  if v_amount is null or v_amount <= 0 then raise exception 'The amount must be greater than zero'; end if;

  if v_kind = 'commercial' then
    v_entry := erp.adjust_account(v_company, '6959', 'Dotación a la provisión para otras operaciones comerciales');
    select * into v_exp from erp.gl_accounts where id = v_entry;   -- (la función, fuera del where: crea la cuenta)
  else
    select * into v_exp from erp.gl_accounts
    where company_id = v_company and account_no = p->>'expense_account_no' and account_type = 'posting';
    if not found or left(v_exp.account_no, 1) <> '6' or left(v_exp.account_no, 2) in ('68', '69') then
      raise exception 'Choose the expense account by nature (group 6, not 68 or 69)';
    end if;
  end if;

  select 'PRV-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.provisions x where x.company_id = v_company;
  insert into erp.provisions (company_id, code, kind, term, description, provision_account_id, expense_account_id, excess_account_id)
  values (v_company, v_code, v_kind, v_term, v_desc, erp.provision_account(v_company, v_kind, v_term), v_exp.id,
          erp.adjust_account(v_company, case v_kind when 'taxes' then '7952' when 'liabilities' then '7953' else '7954' end,
            case v_kind when 'taxes' then 'Exceso de provisión para impuestos' when 'liabilities' then 'Exceso de provisión para otras responsabilidades'
                        else 'Exceso de provisión por operaciones comerciales' end))
  returning * into v_prov;
  v_entry := erp.provision_post(v_company, v_date, 'Provisión ' || v_code || ' · ' || v_desc, jsonb_build_array(
    jsonb_build_object('account_id', v_exp.id, 'debit', v_amount, 'text', 'Dotación'),
    jsonb_build_object('account_id', v_prov.provision_account_id, 'credit', v_amount, 'text', 'Dotación')));
  v_no := erp.provision_add_movement(v_prov, 'allocation', v_date, 0, v_amount, v_entry);
  provision_id := v_prov.id; code := v_code; entry_no := v_no;
  return next;
end $function$
;
