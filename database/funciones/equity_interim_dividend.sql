-- =====================================================================
-- erp.equity_interim_dividend · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_interim_dividend(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; g jsonb; e1 uuid; v_amt numeric;
begin
  v_code := erp.equity_start(v_company, v_date);
  g := erp.equity_interim_preview(p);
  v_amt := (g->>'amount')::numeric;
  if v_amt <= 0 then raise exception 'Invalid amount'; end if;
  if not (g->>'ok')::boolean then
    raise exception 'The interim dividend is not valid: % (art. 277 LSC)', (select string_agg(w->>'code', ', ') from jsonb_array_elements(g->'warnings') w);
  end if;
  e1 := erp.equity_entry(v_company, v_date, 'Dividendo a cuenta (acuerdo del órgano de administración)', v_code,
          jsonb_build_array(erp.equity_line(erp.adjust_account(v_company, '557', 'Dividendo activo a cuenta'), v_amt, 0),
                            erp.equity_line(erp.adjust_account(v_company, '526', 'Dividendo activo a pagar'), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'interim_dividend', v_date, 'Dividendo a cuenta', p, g, array[e1]);
end $function$
;
