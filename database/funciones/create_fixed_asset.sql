-- =====================================================================
-- erp.create_fixed_asset · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets   →   la vigente es la de 0041_fixed_assets
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.create_fixed_asset(p jsonb)
 RETURNS TABLE(asset_id uuid, code text, warnings jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_acc     erp.gl_accounts;
  v_class   erp.depreciation_classes;
  v_life    int := (p->>'useful_life_months')::int;
  v_start   date := (p->>'start_date')::date;
  v_acq     date := coalesce((p->>'acquisition_date')::date, (p->>'start_date')::date);
  v_cost    numeric := round((p->>'cost')::numeric, 2);
  v_res     numeric := round(coalesce((p->>'residual_value')::numeric, 0), 2);
  v_code    text;
  v_id      uuid;
  v_warn    jsonb := '[]';
  v_pct     numeric;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register fixed assets in this company'; end if;
  if coalesce(btrim(p->>'name'), '') = '' then raise exception 'The asset needs a name'; end if;
  select * into v_acc from erp.gl_accounts
  where company_id = v_company and account_no = p->>'asset_account_no' and account_type = 'posting';
  if not found or left(v_acc.account_no, 2) not in ('20', '21', '22') then
    raise exception 'Choose the asset account (20x, 21x or 22x)';
  end if;
  if left(v_acc.account_no, 3) in ('210', '220') then
    raise exception 'Land is not depreciated (NRV 2.ª): account % cannot be a depreciable asset', v_acc.account_no;
  end if;
  if v_cost is null or v_cost <= 0 then raise exception 'The cost must be greater than zero'; end if;
  if v_res < 0 or v_res >= v_cost then raise exception 'The residual value must be between zero and the cost'; end if;
  if v_life is null or v_life <= 0 then raise exception 'The useful life must be at least one month'; end if;
  if v_start is null then raise exception 'The start date (when the asset is ready for use) is required'; end if;
  if v_start < v_acq then raise exception 'The start date cannot be earlier than the acquisition date'; end if;
  if p->>'invoice_id' is not null and not exists (select 1 from erp.invoices i where i.id = (p->>'invoice_id')::uuid
       and i.company_id = v_company and i.invoice_type = 'purchase') then
    raise exception 'The invoice must be a received invoice of this company';
  end if;

  -- Coeficiente fiscal (LIS art. 12.1.a): el contable puede ser distinto; si supera el máximo o queda por debajo del
  -- mínimo (1 / período máximo), la diferencia se ajusta en el Impuesto sobre Sociedades
  if p->>'class_code' is not null then
    select * into v_class from erp.depreciation_classes where depreciation_classes.code = p->>'class_code';
    if not found then raise exception 'Unknown depreciation class: %', p->>'class_code'; end if;
    v_pct := round(1200.0 / v_life, 2);
    if v_pct > v_class.max_pct then
      v_warn := v_warn || jsonb_build_object('code', 'above_tax_max', 'rate', v_pct, 'max', v_class.max_pct);
    end if;
    if v_life > v_class.max_years * 12 then
      v_warn := v_warn || jsonb_build_object('code', 'below_tax_min', 'years', round(v_life / 12.0, 1), 'max_years', v_class.max_years);
    end if;
  end if;

  select 'INM-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.fixed_assets where company_id = v_company;
  insert into erp.fixed_assets (company_id, code, name, class_code, asset_account_id, depreciation_account_id, expense_account_id,
                                acquisition_date, start_date, cost, residual_value, useful_life_months, invoice_id)
  values (v_company, v_code, btrim(p->>'name'), p->>'class_code', v_acc.id,
          erp.asset_account_pair(v_company, v_acc.account_no, 'depreciation'), erp.asset_account_pair(v_company, v_acc.account_no, 'expense'),
          v_acq, v_start, v_cost, v_res, v_life, (p->>'invoice_id')::uuid)
  returning id into v_id;
  asset_id := v_id; code := v_code; warnings := v_warn;
  return next;
end $function$
;
