-- =====================================================================
-- erp.equity_reserves_to_capital · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_reserves_to_capital(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid; v_date date := (p->>'date')::date;
  v_amt numeric := round(coalesce((p->>'amount')::numeric, 0), 2); v_src text := coalesce(p->>'source', '113'); v_code text; v_acc uuid; e1 uuid;
begin
  v_code := erp.equity_start(v_company, v_date);
  if v_src not in ('113', '110') then raise exception 'Invalid source: 113 (voluntary reserves) or 110 (share premium)'; end if;
  if erp.equity_bal(v_company, '100', v_date) <= 0 then raise exception 'There is no share capital yet: register the incorporation first'; end if;
  if v_amt <= 0 then raise exception 'Invalid amount'; end if;
  if erp.equity_bal(v_company, v_src, v_date) < v_amt then
    raise exception 'Not enough % to convert into capital (balance %)', case v_src when '113' then 'voluntary reserves' else 'share premium' end, erp.equity_bal(v_company, v_src, v_date);
  end if;
  select g.id into v_acc from erp.gl_accounts g where g.company_id = v_company and g.account_type = 'posting' and g.account_no like v_src || '%'
  order by (select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l where l.gl_account_id = g.id) desc limit 1;
  e1 := erp.equity_entry(v_company, v_date, 'Ampliación de capital con cargo a ' || case v_src when '113' then 'reservas' else 'la prima de emisión' end, v_code,
          jsonb_build_array(erp.equity_line(v_acc, v_amt, 0), erp.equity_line(erp.adjust_account(v_company, '100', 'Capital social'), 0, v_amt)));
  return erp.equity_save(v_company, v_code, 'reserves_to_capital', v_date, 'Ampliación de capital con cargo a reservas', p,
    jsonb_build_object('amount', v_amt, 'source', v_src), array[e1]);
end $function$
;
