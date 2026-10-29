-- =====================================================================
-- erp.equity_distribution · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_distribution(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; g jsonb; v_res numeric; e1 uuid;
  v_lines jsonb; a_129 uuid; a_121 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  g := erp.equity_distribution_preview(p);
  if (g->>'result')::numeric = 0 then raise exception 'There is no result to distribute on %: close the previous year first', v_date; end if;
  if not (g->>'ok')::boolean then
    raise exception 'The distribution is not valid: %', (select string_agg(w->>'code', ', ') from jsonb_array_elements(g->'warnings') w where w->>'code' <> 'losses_left');
  end if;
  v_res := (g->>'result')::numeric;
  select g2.id into a_129 from erp.gl_accounts g2 where g2.company_id = v_company and g2.account_type = 'posting' and g2.account_no like '129%'
  order by (select abs(coalesce(sum(l.credit - l.debit), 0)) from erp.journal_lines l where l.gl_account_id = g2.id) desc limit 1;
  if v_res < 0 then
    a_121 := erp.adjust_account(v_company, '121', 'Resultados negativos de ejercicios anteriores');
    v_lines := jsonb_build_array(erp.equity_line(a_121, -v_res, 0), erp.equity_line(a_129, 0, -v_res));
  else
    v_lines := jsonb_build_array(erp.equity_line(a_129, v_res, 0));
    if (g->>'offset_losses')::numeric > 0 then
      v_lines := v_lines || erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '121%' order by account_no limit 1), 0, (g->>'offset_losses')::numeric);
    end if;
    if (g->>'legal_reserve')::numeric > 0 then v_lines := v_lines || erp.equity_line(erp.adjust_account(v_company, '112', 'Reserva legal'), 0, (g->>'legal_reserve')::numeric); end if;
    if (g->>'interim')::numeric > 0 then
      v_lines := v_lines || erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '557%' order by account_no limit 1), 0, (g->>'interim')::numeric);
    end if;
    if (g->>'complementary')::numeric > 0 then v_lines := v_lines || erp.equity_line(erp.adjust_account(v_company, '526', 'Dividendo activo a pagar'), 0, (g->>'complementary')::numeric); end if;
    if (g->>'voluntary')::numeric > 0 then v_lines := v_lines || erp.equity_line(erp.adjust_account(v_company, '113', 'Reservas voluntarias'), 0, (g->>'voluntary')::numeric); end if;
  end if;
  e1 := erp.equity_entry(v_company, v_date, 'Distribución del resultado (acuerdo de la junta)', v_code, v_lines);
  return erp.equity_save(v_company, v_code, 'distribution', v_date, 'Distribución del resultado', p, g, array[e1]);
end $function$
;
