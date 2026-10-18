-- =====================================================================
-- erp.impair_receivables_global · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0043_year_end_adjustments   →   la vigente es la de 0043_year_end_adjustments
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.impair_receivables_global(p jsonb)
 RETURNS TABLE(impairment_id uuid, code text, entry_no integer, amount numeric, warnings jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_date    date := (p->>'impair_date')::date;
  v_rates   jsonb := coalesce(p->'rates', '{}');
  v_details jsonb;
  v_basis   numeric;
  v_amt     numeric;
  v_warn    jsonb;
  v_code    text;
  v_entry   uuid;
  v_id      uuid;
  v_no      int;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register impairments in this company'; end if;
  if v_date is null then raise exception 'The impairment date is required'; end if;
  if exists (select 1 from jsonb_each_text(v_rates) r where r.value::numeric < 0 or r.value::numeric > 100) then
    raise exception 'The percentages must be between 0 and 100';
  end if;
  if exists (select 1 from erp.receivable_impairments i where i.company_id = v_company and i.method = 'global' and i.status = 'active') then
    raise exception 'There is already a global impairment: reverse it first (it is re-estimated each year)';
  end if;
  select jsonb_agg(to_jsonb(c)), sum(c.basis), sum(c.amount) into v_details, v_basis, v_amt
  from erp.global_impairment_calc(v_company, v_date, v_rates) c;
  if coalesce(v_amt, 0) <= 0 then raise exception 'Nothing to impair at % with these percentages', v_date; end if;

  -- LIS art. 13.1: la estimación global no es deducible; art. 104: salvo empresas de reducida dimensión, hasta el 1 %
  v_warn := jsonb_build_array(jsonb_build_object('code', 'global_not_deductible', 'erd_limit', round(v_basis * 0.01, 2)));

  select 'DET-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.receivable_impairments i where i.company_id = v_company;
  v_entry := erp.adjust_post(v_company, v_date, 'Deterioro global ' || v_code || ' de clientes al ' || to_char(v_date, 'DD/MM/YYYY'), null,
    erp.adjust_account(v_company, '694', 'Pérdidas por deterioro de créditos por operaciones comerciales'),
    erp.adjust_account(v_company, '490', 'Deterioro de valor de créditos por operaciones comerciales'), v_amt);
  insert into erp.receivable_impairments (company_id, code, method, impair_date, basis, amount, details, warnings, entry_id)
  values (v_company, v_code, 'global', v_date, v_basis, v_amt, v_details, v_warn, v_entry)
  returning id into v_id;
  v_no := erp.adjust_finish(v_entry);
  impairment_id := v_id; code := v_code; entry_no := v_no; amount := v_amt; warnings := v_warn;
  return next;
end $function$
;
