-- =====================================================================
-- erp.withholding_setup_core · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0018_withholding_exempt   →   la vigente es la de 0018_withholding_exempt
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.withholding_setup_core(p_company uuid)
 RETURNS TABLE(withholding_code text, account_role text, account_no text, status text)
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_digits smallint;
  w        erp.withholding_codes;
  v_pay    uuid;
  v_rec    uuid;
  v_st     text;
  v_no     text;
begin
  select posting_account_digits into v_digits from erp.companies where id = p_company;
  for w in select * from erp.withholding_codes where valid_to is null or valid_to >= current_date order by code loop
    if exists (select 1 from erp.withholding_setup s where s.company_id = p_company and s.withholding_code = w.code) then
      withholding_code := w.code; account_role := null; account_no := null; status := 'existing';
      return next;
      continue;
    end if;
    v_no := rpad('4751', v_digits - 1, '0') || case w.form when '115' then '5' else '1' end;
    v_st := 'linked';
    select e.status, e.account_id into v_st, v_pay
    from erp.ensure_tax_account(p_company, v_no,
           'HP acreedora por retenciones practicadas (mod. ' || w.form || ')',
           'Withholdings payable (form ' || w.form || ')', v_st) e;
    withholding_code := w.code; account_role := 'payable'; account_no := v_no; status := v_st;
    return next;

    v_no := rpad('473', v_digits - 1, '0') || '1';
    v_st := 'linked';
    select e.status, e.account_id into v_st, v_rec
    from erp.ensure_tax_account(p_company, v_no, 'HP retenciones y pagos a cuenta', 'Withholdings and payments on account', v_st) e;
    withholding_code := w.code; account_role := 'receivable'; account_no := v_no; status := v_st;
    return next;

    insert into erp.withholding_setup (company_id, withholding_code, payable_account_id, receivable_account_id)
    values (p_company, w.code, v_pay, v_rec);
  end loop;
end $function$
;
