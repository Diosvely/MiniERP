-- =====================================================================
-- erp.equity_capital_increase · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_capital_increase(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_nom numeric := round(coalesce((p->>'nominal')::numeric, 0), 2); v_prem numeric := round(coalesce((p->>'premium')::numeric, 0), 2);
  v_pct numeric := coalesce((p->>'paid_pct')::numeric, 100);
  v_form text; v_code text; v_paid numeric; a_190 uuid; a_194 uuid; a_1030 uuid; a_100 uuid; a_110 uuid; v_bank uuid; e1 uuid; e2 uuid; e3 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  select legal_form into v_form from erp.companies where id = v_company;
  if erp.equity_bal(v_company, '100', v_date) <= 0 then raise exception 'There is no share capital yet: register the incorporation first'; end if;
  if v_nom <= 0 or v_prem < 0 then raise exception 'Invalid amounts for the capital increase'; end if;
  if v_form = 'sl' and v_pct <> 100 then raise exception 'In an SL the new capital must be fully paid (art. 78 LSC)'; end if;
  if v_pct < 25 or v_pct > 100 then raise exception 'At least 25 %% of the nominal value must be paid (art. 79 LSC)'; end if;
  v_paid := round(v_nom * v_pct / 100, 2) + v_prem;   -- la prima se desembolsa entera
  a_190 := erp.adjust_account(v_company, '190', 'Acciones o participaciones emitidas');
  a_194 := erp.adjust_account(v_company, '194', 'Capital emitido pendiente de inscripción');
  a_100 := erp.adjust_account(v_company, '100', 'Capital social');
  if v_prem > 0 then a_110 := erp.adjust_account(v_company, '110', 'Prima de emisión o asunción'); end if;
  v_bank := erp.equity_bank(v_company, p->>'bank_account_no');
  e1 := erp.equity_entry(v_company, v_date, 'Ampliación de capital · emisión', v_code,
          jsonb_build_array(erp.equity_line(a_190, v_nom + v_prem, 0), erp.equity_line(a_194, 0, v_nom), erp.equity_line(a_110, 0, v_prem)));
  if v_paid < v_nom + v_prem then a_1030 := erp.adjust_account(v_company, '1030', 'Socios por desembolsos no exigidos, capital social'); end if;
  e2 := erp.equity_entry(v_company, v_date, 'Ampliación de capital · suscripción y desembolso', v_code,
          jsonb_build_array(erp.equity_line(v_bank, v_paid, 0), erp.equity_line(a_1030, v_nom + v_prem - v_paid, 0), erp.equity_line(a_190, 0, v_nom + v_prem)));
  e3 := erp.equity_entry(v_company, v_date, 'Ampliación de capital · inscripción en el Registro Mercantil', v_code,
          jsonb_build_array(erp.equity_line(a_194, v_nom, 0), erp.equity_line(a_100, 0, v_nom)));
  return erp.equity_save(v_company, v_code, 'capital_increase', v_date, 'Ampliación de capital', p,
    jsonb_build_object('nominal', v_nom, 'premium', v_prem, 'paid', v_paid, 'uncalled', v_nom + v_prem - v_paid), array[e1, e2, e3]);
end $function$
;
