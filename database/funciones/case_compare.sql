-- =====================================================================
-- erp.case_compare · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0066_complete_case 0067_case_screen 0068_case_labels   →   la vigente es la de 0068_case_labels
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.case_compare(p_company uuid, p_case text DEFAULT NULL::text)
 RETURNS TABLE(kind text, code text, label text, label_en text, expected numeric, actual numeric, difference numeric, ok boolean, status text, sort integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
declare v_case erp.cases; v_ecpn jsonb; v_cit jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_case from erp.cases where key = coalesce(p_case, (select case_key from erp.companies where id = p_company));
  if not found then raise exception 'No case loaded in this company'; end if;
  v_ecpn := erp.equity_statement(p_company, v_case.year);
  select r.result into v_cit from erp.corporate_tax_returns r join erp.fiscal_years fy on fy.id = r.fiscal_year_id
  where r.company_id = p_company and fy.year = v_case.year and r.status = 'posted';
  return query
  with act as (
    select 'pyg' as k, s.code as c, s.label as l, s.label_en as le, s.amount as v from erp.financial_statement(p_company, v_case.year, 'pyg') s
    union all select 'balance', s.code, s.label, s.label_en, s.amount from erp.financial_statement(p_company, v_case.year, 'balance') s
    union all select 'cf_indirect', s.code, s.label, s.label_en, s.amount from erp.cash_flow_statement(p_company, v_case.year, 'indirect') s
    union all select 'cf_direct', s.code, s.label, s.label_en, s.amount from erp.cash_flow_statement(p_company, v_case.year, 'direct') s
    union all select 'tax_form', q || '.' || b.box, null, null, b.amount from generate_series(1, 4) q, erp.tax_form_boxes(p_company, v_case.year, q) b
    union all select 'withholding', q || '.' || w.form, null, null, sum(w.amount) from generate_series(1, 4) q, erp.withholding_summary(p_company, v_case.year, q) w
              where w.side = 'withheld' group by 1, 2)
  select y.kind, y.code, y.label, y.label_en, y.expected, y.actual, y.actual - y.expected, y.actual = y.expected,
         case when y.actual = y.expected then 'ok' when v_cit is null then 'pending' else 'diff' end, y.sort
  from (
    select x.kind, x.code, x.amount as expected, x.sort,
           (select max(a.l) from act a where a.k = x.kind and a.c = x.code) as label,
           (select max(a.le) from act a where a.k = x.kind and a.c = x.code) as label_en,
           coalesce(case x.kind when 'ecpn' then (v_ecpn #>> string_to_array(x.code, '.'))::numeric
                                when 'cit' then (v_cit ->> x.code)::numeric
                                else (select sum(a.v) from act a where a.k = x.kind and a.c = x.code) end, 0) as actual
    from erp.case_expected x where x.case_key = v_case.key) y
  order by y.sort;
end $function$
;
