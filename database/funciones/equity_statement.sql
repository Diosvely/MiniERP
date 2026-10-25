-- =====================================================================
-- erp.equity_statement · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0065_grants_integration   →   la vigente es la de 0065_grants_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_statement(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare v_fy erp.fiscal_years; a jsonb; b jsonb; v_rec numeric; v_end numeric; v_bal numeric;
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'Fiscal year % does not exist', p_year; end if;

  -- Parte A: ingresos y gastos reconocidos (el efecto impositivo se separa por el movimiento de la subvención que lo
  -- originó: la concesión, en B; la imputación a resultados, en C)
  with l as (
    select g.account_no, l.credit - l.debit as amount,
           (select v.kind from erp.grant_events v where v.entry_id = coalesce(e.reversal_of, e.id) limit 1) as gk
    from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
    join erp.fiscal_years f on f.id = e.fiscal_year_id and f.year = p_year
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and e.entry_type not in ('closing', 'closing_pl', 'opening') and g.account_no ~ '^[6789]'
  )
  select jsonb_build_object(
    'result', coalesce(sum(amount) filter (where account_no ~ '^[67]'), 0),
    'b_grants', coalesce(sum(amount) filter (where account_no ~ '^94'), 0),
    'b_tax', coalesce(sum(amount) filter (where account_no ~ '^83' and (gk in ('concession', 'unconditional') or (gk is null and amount < 0))), 0),
    'b_other', coalesce(sum(amount) filter (where account_no ~ '^[89]' and account_no !~ '^(94|84|83)'), 0),
    'c_grants', coalesce(sum(amount) filter (where account_no ~ '^84'), 0),
    'c_tax', coalesce(sum(amount) filter (where account_no ~ '^83' and (gk in ('imputation', 'disposal') or (gk is null and amount > 0))), 0))
  into a from l;
  a := a || jsonb_build_object(
    'b_total', (a->>'b_grants')::numeric + (a->>'b_tax')::numeric + (a->>'b_other')::numeric,
    'c_total', (a->>'c_grants')::numeric + (a->>'c_tax')::numeric);
  a := a || jsonb_build_object('total', (a->>'result')::numeric + (a->>'b_total')::numeric + (a->>'c_total')::numeric);

  -- Parte B: estado total, por columnas
  select coalesce(jsonb_object_agg(r, cols), '{}') into b from (
    select row_code as r, jsonb_object_agg(col, amt) as cols
    from (select row_code, col, sum(amount) as amt from erp.equity_statement_lines(p_company, p_year) group by 1, 2) x
    group by row_code) y;
  v_rec := coalesce((select sum(amount) from erp.equity_statement_lines(p_company, p_year) where row_code = 'recognised'), 0);
  v_end := coalesce((select sum(amount) from erp.equity_statement_lines(p_company, p_year)), 0);
  select coalesce(sum(amount), 0) into v_bal from erp.fs_classified_accounts(p_company, p_year, 'balance', v_fy.ending_date) where line_code like 'PN.%';   -- el patrimonio neto (no PNC ni PC)
  return jsonb_build_object('year', p_year, 'part_a', a, 'part_b', b,
    'columns', (select coalesce(jsonb_agg(c order by o), '[]') from unnest(array['capital', 'premium', 'reserves', 'prior_results', 'result', 'interim', 'grants']) with ordinality u(c, o)
                where exists (select 1 from erp.equity_statement_lines(p_company, p_year) s where s.col = u.c and s.amount <> 0)),
    'start', coalesce((select sum(amount) from erp.equity_statement_lines(p_company, p_year) where row_code = 'start'), 0),
    'end', v_end, 'balance_net_worth', v_bal, 'ok', v_end = v_bal and v_rec = (a->>'total')::numeric);
end $function$
;
