-- =====================================================================
-- erp.grant_create · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_create(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_kind text := coalesce(p->>'kind', 'capital'); v_date date := (p->>'date')::date;
  v_amt numeric := round(coalesce((p->>'amount')::numeric, 0), 2); v_ref boolean := coalesce((p->>'refundable')::boolean, false);
  v_due date := (p->>'condition_due')::date; v_coll boolean := coalesce((p->>'collected')::boolean, false);
  v_rate numeric := coalesce((p->>'tax_rate')::numeric, 25); v_desc text := nullif(btrim(p->>'description'), '');
  v_asset uuid := nullif(p->>'asset_id', '')::uuid; a erp.fixed_assets; v_code text; v_id uuid; v_tax numeric := 0; v_entry uuid;
  a_eq uuid; a_inc uuid; a_tr uuid; a_res uuid; a_tax uuid; a_def uuid; a_rec uuid; a_debt uuid; a_first uuid;
begin
  perform erp.grant_check(v_company, v_date);
  if v_kind not in ('capital', 'operating') then raise exception 'Invalid grant type: %', v_kind; end if;
  if v_desc is null then raise exception 'The description is required'; end if;
  if v_amt <= 0 then raise exception 'The grant amount must be positive'; end if;
  if v_rate < 0 or v_rate > 100 then raise exception 'The tax rate must be between 0 and 100'; end if;
  if v_kind = 'capital' then
    select * into a from erp.fixed_assets where id = v_asset and company_id = v_company;
    if not found then raise exception 'Choose the fixed asset the capital grant finances (Fixed assets)'; end if;
    if a.status <> 'active' then raise exception 'Asset % is disposed', a.code; end if;
    if v_amt > a.cost then raise exception 'The grant cannot exceed the cost of the asset (%)', a.cost; end if;
  else
    v_asset := null;
  end if;
  if v_ref and v_due is null then raise exception 'A refundable grant needs the date its condition falls due'; end if;
  -- la 4708 de las de capital y la de las de explotación son subcuentas distintas (4708… y 47089…): el cobro es un
  -- flujo de financiación en unas y de explotación en otras (estado de flujos de efectivo, cf_mapping)
  a_rec := case v_kind when 'capital' then erp.adjust_account(v_company, '4708', 'Hacienda Pública, deudora por subvenciones de capital concedidas')
                else erp.adjust_account(v_company, '47089', 'Hacienda Pública, deudora por subvenciones a la explotación concedidas') end;
  if v_kind = 'capital' then
    a_eq  := erp.adjust_account(v_company, '130', 'Subvenciones oficiales de capital');
    a_inc := erp.adjust_account(v_company, '940', 'Ingresos de subvenciones oficiales de capital');
    a_tr  := erp.adjust_account(v_company, '840', 'Transferencia de subvenciones oficiales de capital');
    a_res := erp.adjust_account(v_company, '746', 'Subvenciones de capital transferidas al resultado del ejercicio');
    a_tax := erp.adjust_account(v_company, '8301', 'Impuesto diferido');
    a_def := erp.adjust_account(v_company, '479', 'Pasivos por diferencias temporarias imponibles');
  else
    a_inc := erp.adjust_account(v_company, '740', 'Subvenciones a la explotación');
  end if;
  if v_ref then
    a_debt := case when v_due <= v_date + interval '1 year'
                   then erp.adjust_account(v_company, '522', 'Deudas a corto plazo transformables en subvenciones')
                   else erp.adjust_account(v_company, '172', 'Deudas a largo plazo transformables en subvenciones') end;
  end if;
  select 'SUB-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.grants where company_id = v_company;
  insert into erp.grants (company_id, code, kind, description, grantor, amount, grant_date, refundable, condition_due, tax_rate, asset_id,
                          equity_account_id, income_account_id, transfer_account_id, result_account_id, tax_account_id, deferred_account_id,
                          receivable_account_id, debt_account_id)
  values (v_company, v_code, v_kind, v_desc, coalesce(btrim(p->>'grantor'), ''), v_amt, v_date, v_ref, v_due, v_rate, v_asset,
          a_eq, a_inc, a_tr, a_res, a_tax, a_def, a_rec, a_debt)
  returning id into v_id;
  a_first := case when v_coll then erp.equity_bank(v_company, p->>'bank_account_no') else a_rec end;
  if not v_ref and v_kind = 'capital' then v_tax := round(v_amt * v_rate / 100, 2); end if;
  v_entry := erp.equity_entry(v_company, v_date, 'Subvención concedida' || case when v_ref then ' (reintegrable)' else '' end || ' · ' || v_desc, v_code,
               jsonb_build_array(erp.equity_line(a_first, v_amt, 0), erp.equity_line(coalesce(a_debt, a_inc), 0, v_amt),
                                 erp.equity_line(a_tax, v_tax, 0), erp.equity_line(a_def, 0, v_tax)));
  insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, tax_amount, collected, entry_id)
  values (v_id, v_company, 'concession', v_date, v_amt, v_tax, v_coll, v_entry);
  return jsonb_build_object('grant_id', v_id, 'code', v_code, 'tax', v_tax, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $function$
;
