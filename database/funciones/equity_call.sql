-- =====================================================================
-- erp.equity_call · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_call(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_amt numeric := round(coalesce((p->>'amount')::numeric, 0), 2); v_code text; a_5580 uuid; v_pending numeric; e1 uuid; e2 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  v_pending := -erp.equity_bal(v_company, '1030', v_date);
  if v_amt <= 0 or v_amt > v_pending then raise exception 'The call must be between 0 and the uncalled capital (%)', v_pending; end if;
  a_5580 := erp.adjust_account(v_company, '5580', 'Socios por desembolsos exigidos sobre acciones o participaciones ordinarias');
  e1 := erp.equity_entry(v_company, v_date, 'Dividendo pasivo · se exige a los socios', v_code,
          jsonb_build_array(erp.equity_line(a_5580, v_amt, 0),
            erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '1030%' order by account_no limit 1), 0, v_amt)));
  if coalesce((p->>'paid')::boolean, false) then
    e2 := erp.equity_entry(v_company, v_date, 'Dividendo pasivo · cobro', v_code,
            jsonb_build_array(erp.equity_line(erp.equity_bank(v_company, p->>'bank_account_no'), v_amt, 0), erp.equity_line(a_5580, 0, v_amt)));
  end if;
  return erp.equity_save(v_company, v_code, 'call', v_date, 'Dividendo pasivo', p,
    jsonb_build_object('amount', v_amt, 'paid', e2 is not null, 'uncalled_after', v_pending - v_amt), array[e1, e2]);
end $function$
;
