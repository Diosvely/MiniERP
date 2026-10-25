-- =====================================================================
-- 0068 · PANTALLA «CASOS» (II): lo que necesita la web · v0.46.0
-- ---------------------------------------------------------------------
--   · erp.v_my_companies: también el caso cargado (case_key) y cómo (case_mode), para que la empresa del caso tenga su
--     pantalla «Caso» en Informes.
--   · erp.case_compare: también el nombre de cada partida (el del balance, la cuenta de resultados o el EFE) en
--     español y en inglés; las del ECPN, el impuesto y los modelos los pone la web.
-- Re-ejecutable.
-- =====================================================================

-- 1) Mis empresas (versión de la 0036 con el caso)
create or replace view erp.v_my_companies with (security_invoker = true) as
select c.id, c.name, c.vat_registration_no, c.industry, c.tax_territory,
       c.posting_account_digits, c.is_demo, c.created_at,
       erp.my_role(c.id) as my_role,
       c.vat_regime,
       c.data_credit,
       erp.is_data_owner(c.id) as is_data_owner,
       c.control_mode,
       c.case_key,
       c.case_mode
from erp.companies c;

-- 2) Comparar con el caso (versión de la 0067 con el nombre de cada partida)
drop function if exists erp.case_compare(uuid, text);
create or replace function erp.case_compare(p_company uuid, p_case text default null)
returns table (kind text, code text, label text, label_en text, expected numeric, actual numeric, difference numeric, ok boolean,
               status text, sort int)
language plpgsql stable set search_path = erp, public as $$
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
end $$;

revoke execute on function erp.case_compare(uuid, text) from anon, public;
grant execute on function erp.case_compare(uuid, text) to authenticated;
