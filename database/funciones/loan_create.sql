-- =====================================================================
-- erp.loan_create · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0062_loans 0063_financing_integration   →   la vigente es la de 0063_financing_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.loan_create(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; c jsonb; v_code text; v_id uuid; v_type text := coalesce(p->>'lender_type', 'bank');
  v_desc text := nullif(btrim(p->>'description'), ''); a_long uuid; a_short uuid; a_int uuid; a_acc uuid; a_bank uuid; a_asset uuid;
  v_short numeric; v_long numeric; v_entry uuid; v_asset uuid; v_asset_code text; v_warn jsonb;
begin
  c := erp.loan_calc(p);
  perform erp.loan_check(v_company, (c->>'start_date')::date);
  if v_desc is null then raise exception 'The description is required'; end if;
  if v_type not in ('bank', 'other') then raise exception 'Invalid lender type: %', v_type; end if;
  -- v0.43.0 (0063): el leasing da de alta también la ficha del activo, con su vida útil
  if c->>'kind' = 'leasing' and coalesce((p->>'useful_life_months')::int, 0) <= 0 then
    raise exception 'The useful life of the leased asset is required (months)';
  end if;
  if c->>'kind' = 'loan' then
    a_long  := erp.loan_account(v_company, p->>'long_account_no', case v_type when 'bank' then '1700' else '1710' end,
                 case v_type when 'bank' then 'Préstamos a largo plazo de entidades de crédito' else 'Deudas a largo plazo' end, '^17[01]');
    a_short := erp.loan_account(v_company, p->>'short_account_no', case v_type when 'bank' then '5200' else '5210' end,
                 case v_type when 'bank' then 'Préstamos a corto plazo de entidades de crédito' else 'Deudas a corto plazo' end, '^52[01]');
    a_bank  := erp.equity_bank(v_company, p->>'bank_account_no');
  else
    a_long  := erp.loan_account(v_company, p->>'long_account_no', '1740', 'Acreedores por arrendamiento financiero a largo plazo', '^174');
    a_short := erp.loan_account(v_company, p->>'short_account_no', '5240', 'Acreedores por arrendamiento financiero a corto plazo', '^524');
    a_asset := erp.loan_account(v_company, p->>'asset_account_no', '213', 'Maquinaria', '^2[01]');
    if nullif(btrim(p->>'bank_account_no'), '') is not null then a_bank := erp.equity_bank(v_company, p->>'bank_account_no'); end if;
  end if;
  a_int := erp.loan_account(v_company, p->>'interest_account_no', case v_type when 'bank' then '6623' else '6624' end,
             case v_type when 'bank' then 'Intereses de deudas con entidades de crédito' else 'Intereses de deudas con otras empresas' end, '^662');
  a_acc := erp.adjust_account(v_company, case v_type when 'bank' then '527' else '528' end,
             case v_type when 'bank' then 'Intereses a corto plazo de deudas con entidades de crédito' else 'Intereses a corto plazo de deudas' end);
  select 'FIN-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.loans where company_id = v_company;
  insert into erp.loans (company_id, code, kind, description, lender, lender_type, start_date, first_due_date, frequency, periods,
                         nominal_rate, principal, costs, net_amount, instalment, purchase_option, fair_value, present_value,
                         effective_rate, effective_rate_year, long_account_id, short_account_id, interest_account_id,
                         accrued_account_id, bank_account_id, asset_account_id, data)
  values (v_company, v_code, c->>'kind', v_desc, coalesce(btrim(p->>'lender'), ''), v_type, (c->>'start_date')::date, (c->>'first_due_date')::date,
          (c->>'frequency')::int, (c->>'periods')::int, (c->>'nominal_rate')::numeric, (c->>'principal')::numeric, (c->>'costs')::numeric,
          (c->>'net_amount')::numeric, (c->>'instalment')::numeric, (c->>'purchase_option')::numeric, (c->>'fair_value')::numeric,
          (c->>'present_value')::numeric, (c->>'effective_rate')::numeric, (c->>'effective_rate_year')::numeric,
          a_long, a_short, a_int, a_acc, a_bank, a_asset, p - 'company_id')
  returning id into v_id;
  insert into erp.loan_schedule (loan_id, company_id, n, due_date, payment, interest, reduction, balance)
  select v_id, v_company, (x->>'n')::int, (x->>'due_date')::date, (x->>'payment')::numeric, (x->>'interest')::numeric,
         (x->>'reduction')::numeric, (x->>'balance')::numeric
  from jsonb_array_elements(c->'schedule') x;
  v_short := (c->>'short_part')::numeric; v_long := (c->>'net_amount')::numeric - v_short;
  v_entry := erp.equity_entry(v_company, (c->>'start_date')::date,
               case c->>'kind' when 'loan' then 'Préstamo · cobro' else 'Arrendamiento financiero · alta del activo' end || ' · ' || v_desc, v_code,
               jsonb_build_array(erp.equity_line(coalesce(a_asset, a_bank), (c->>'net_amount')::numeric, 0),
                                 erp.equity_line(a_short, 0, v_short), erp.equity_line(a_long, 0, v_long)));
  insert into erp.loan_events (loan_id, company_id, kind, event_date, amount, short_part, long_part, entry_id)
  values (v_id, v_company, 'start', (c->>'start_date')::date, (c->>'net_amount')::numeric, v_short, v_long, v_entry);
  if c->>'kind' = 'leasing' then
    select f.asset_id, f.code, f.warnings into v_asset, v_asset_code, v_warn
    from erp.create_fixed_asset(jsonb_build_object('company_id', v_company, 'name', coalesce(nullif(btrim(p->>'asset_name'), ''), v_desc),
           'asset_account_no', (select account_no from erp.gl_accounts where id = a_asset), 'class_code', nullif(p->>'class_code', ''),
           'acquisition_date', c->>'start_date', 'start_date', coalesce(nullif(p->>'asset_start_date', ''), c->>'start_date'),
           'cost', c->>'net_amount', 'residual_value', coalesce((p->>'residual_value')::numeric, 0),
           'useful_life_months', (p->>'useful_life_months')::int)) f;
    update erp.loans set asset_id = v_asset where id = v_id;
  end if;
  return (c - 'schedule') || jsonb_build_object('loan_id', v_id, 'code', v_code,
    'entry_no', (select entry_no from erp.journal_entries where id = v_entry), 'asset_code', v_asset_code, 'asset_warnings', v_warn);
end $function$
;
