-- =====================================================================
-- erp.equity_loss_offset · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations 0095_equity_and_company_rules   →   la vigente es la de 0095_equity_and_company_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_loss_offset(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date; v_code text; v_amt numeric; v_losses numeric;
  v_bal numeric; v_others numeric; e1 uuid; v_res text := coalesce(nullif(p->>'reserve', ''), '113'); v_name text;
begin
  v_code := erp.equity_start(v_company, v_date);
  if v_res not in ('113', '110', '115', '119', '112') then raise exception 'Reserve % cannot offset losses', v_res; end if;
  v_amt := round(coalesce((p->>'amount')::numeric, 0), 2);
  v_losses := -erp.equity_bal(v_company, '121', v_date); v_bal := erp.equity_bal(v_company, v_res, v_date);
  if v_amt <= 0 or v_amt > v_losses then raise exception 'The amount must be between 0 and the pending losses (%)', v_losses; end if;
  if v_amt > v_bal then raise exception 'Not enough balance in reserve % (balance %)', v_res, v_bal; end if;
  if v_res = '112' then
    -- art. 274.2 LSC: la reserva legal (hasta el 20 %) solo compensa pérdidas si no hay otras reservas disponibles
    select coalesce(sum(greatest(erp.equity_bal(v_company, r, v_date), 0)), 0) into v_others
    from unnest(array['110', '113', '115', '119']) r;
    if v_others > 0 then
      raise exception 'Use the other available reserves first (% available; art. 274.2 LSC)', v_others;
    end if;
  end if;
  v_name := case v_res when '113' then 'reservas voluntarias' when '110' then 'la prima de emisión' when '115' then 'reservas por pérdidas y ganancias actuariales'
                       when '119' then 'diferencias por ajuste del capital a euros' else 'la reserva legal' end;
  e1 := erp.equity_entry(v_company, v_date, 'Compensación de pérdidas con ' || v_name, v_code,
          jsonb_build_array(erp.equity_line((select g.id from erp.gl_accounts g where g.company_id = v_company and g.account_type = 'posting' and g.account_no like v_res || '%'
                                             order by (select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l where l.gl_account_id = g.id) desc limit 1), v_amt, 0),
            erp.equity_line((select id from erp.gl_accounts where company_id = v_company and account_type = 'posting' and account_no like '121%' order by account_no limit 1), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'loss_offset', v_date, 'Compensación de pérdidas', p,
    jsonb_build_object('amount', v_amt, 'reserve', v_res, 'losses_after', v_losses - v_amt), array[e1]);
end $function$
;
