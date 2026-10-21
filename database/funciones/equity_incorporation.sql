-- =====================================================================
-- erp.equity_incorporation · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_incorporation(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_cap numeric := round(coalesce((p->>'capital')::numeric, 0), 2); v_pct numeric := coalesce((p->>'paid_pct')::numeric, 100);
  v_form text; v_code text; v_paid numeric; a_190 uuid; a_194 uuid; a_1030 uuid; a_100 uuid; v_bank uuid; e1 uuid; e2 uuid; e3 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  select legal_form into v_form from erp.companies where id = v_company;
  if exists (select 1 from erp.equity_operations where company_id = v_company and status = 'posted' and kind = 'incorporation')
     or erp.equity_bal(v_company, '100', v_date) <> 0 then
    raise exception 'The company already has share capital: use a capital increase';
  end if;
  if v_form = 'sa' and v_cap < 60000 then raise exception 'The share capital of an SA must be at least 60,000 (art. 4.3 LSC)'; end if;
  if v_cap < 1 then raise exception 'The share capital must be at least 1 euro (art. 4.1 LSC)'; end if;
  if v_form = 'sl' and v_pct <> 100 then raise exception 'In an SL the capital must be fully paid at incorporation (art. 78 LSC)'; end if;
  if v_pct < 25 or v_pct > 100 then raise exception 'At least 25 %% of the capital must be paid at incorporation (art. 79 LSC)'; end if;
  v_paid := round(v_cap * v_pct / 100, 2);
  a_190 := erp.adjust_account(v_company, '190', 'Acciones o participaciones emitidas');
  a_194 := erp.adjust_account(v_company, '194', 'Capital emitido pendiente de inscripción');
  a_100 := erp.adjust_account(v_company, '100', 'Capital social');
  v_bank := erp.equity_bank(v_company, p->>'bank_account_no');
  e1 := erp.equity_entry(v_company, v_date, 'Constitución · emisión del capital', v_code,
          jsonb_build_array(erp.equity_line(a_190, v_cap, 0), erp.equity_line(a_194, 0, v_cap)));
  if v_paid < v_cap then a_1030 := erp.adjust_account(v_company, '1030', 'Socios por desembolsos no exigidos, capital social'); end if;
  e2 := erp.equity_entry(v_company, v_date, 'Constitución · suscripción y desembolso', v_code,
          jsonb_build_array(erp.equity_line(v_bank, v_paid, 0), erp.equity_line(a_1030, v_cap - v_paid, 0), erp.equity_line(a_190, 0, v_cap)));
  e3 := erp.equity_entry(v_company, v_date, 'Constitución · inscripción en el Registro Mercantil', v_code,
          jsonb_build_array(erp.equity_line(a_194, v_cap, 0), erp.equity_line(a_100, 0, v_cap)));
  return erp.equity_save(v_company, v_code, 'incorporation', v_date, 'Constitución', p,
    jsonb_build_object('capital', v_cap, 'paid', v_paid, 'uncalled', v_cap - v_paid), array[e1, e2, e3]);
end $function$
;
