-- =====================================================================
-- erp.quality_checks · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0084_quality_dashboard   →   la vigente es la de 0084_quality_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.quality_checks(p_company uuid, p_year integer, p_to date DEFAULT NULL::date, p_drafts boolean DEFAULT false)
 RETURNS TABLE(code text, value numeric, extra numeric, severity text)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare
  v_prev_sim text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
  fy erp.fiscal_years; co erp.companies; v_to date; n numeric; x numeric; has_inv boolean;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into fy from erp.fiscal_years f where f.company_id = p_company and f.year = p_year;
  if fy.id is null then raise exception 'No fiscal year %', p_year; end if;
  select * into co from erp.companies c where c.id = p_company;
  v_to := least(coalesce(p_to, fy.ending_date), fy.ending_date);
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;

  -- 1) Saldos al revés (y cuántos son imposibles: severity error de balance_rules)
  select count(*), count(*) filter (where a.severity = 'error') into n, x
  from erp.balance_anomalies(p_company, p_year, null, v_to, p_drafts) a;
  code := 'anomalies'; value := n; extra := x;
  severity := case when x > 0 then 'error' when n > 0 then 'warning' else 'ok' end; return next;

  -- 2) Asientos en edición (y cuántos tienen un problema: erp.draft_ready, la que puede usar la web)
  select count(*), count(*) filter (where not erp.draft_ready(e.id)) into n, x
  from erp.journal_entries e
  where e.company_id = p_company and e.fiscal_year_id = fy.id and e.status = 'draft' and e.posting_date <= v_to;
  code := 'drafts'; value := n; extra := x;
  severity := case when x > 0 then 'warning' when n > 0 then 'info' else 'ok' end; return next;

  -- 3) Meses sin cerrar: solo en la contabilidad mes a mes (en las demás todos están abiertos por diseño)
  code := 'open_months'; extra := null;
  if co.monthly then
    select count(*) into n from erp.accounting_periods p
    where p.fiscal_year_id = fy.id and p.status = 'open' and p.ending_date < least(v_to, current_date);
    value := n; severity := case when n > 0 then 'warning' else 'ok' end;
  else
    value := null; severity := 'na';
  end if;
  return next;

  -- 4) Liquidaciones pendientes: trimestres terminados (hasta la fecha) sin liquidación contabilizada del impuesto de la
  --    empresa; solo si el impuesto está configurado
  code := 'settlements'; extra := null;
  if exists (select 1 from erp.tax_settlement_setup s where s.company_id = p_company and s.tax_type = erp.company_tax_type(p_company)) then
    select count(*) into n from generate_series(1, 4) q
    where erp.quarter_end(p_year, q) <= v_to and erp.quarter_end(p_year, q) < current_date
      and not exists (select 1 from erp.tax_settlements s where s.company_id = p_company and s.tax_type = erp.company_tax_type(p_company)
                      and s.year = p_year and s.quarter = q and s.status = 'posted');
    value := n; severity := case when n > 0 then 'error' else 'ok' end;
  else
    value := null; severity := 'na';
  end if;
  return next;

  -- 5) a 7) Vencidos y terceros sin conciliar: de la antigüedad de saldos; solo si la empresa tiene facturas en el ERP
  --    (una empresa importada solo trae asientos)
  has_inv := exists (select 1 from erp.invoices i where i.company_id = p_company);
  code := 'overdue_in';
  if has_inv then
    select coalesce(sum(a.d1_30 + a.d31_60 + a.d61_90 + a.d90_plus), 0), coalesce(sum(a.d90_plus), 0) into n, x
    from erp.aging(p_company, 'sale', v_to) a;
    value := n; extra := x; severity := case when x > 0 then 'error' when n > 0 then 'warning' else 'ok' end;
  else value := null; extra := null; severity := 'na'; end if;
  return next;

  code := 'overdue_out';
  if has_inv then
    select coalesce(sum(a.d1_30 + a.d31_60 + a.d61_90 + a.d90_plus), 0), coalesce(sum(a.d90_plus), 0) into n, x
    from erp.aging(p_company, 'purchase', v_to) a;
    value := n; extra := x; severity := case when n > 0 then 'warning' else 'ok' end;
  else value := null; extra := null; severity := 'na'; end if;
  return next;

  code := 'unreconciled'; extra := null;
  if has_inv then
    select count(*) into n from (
      select a.total, a.account_balance from erp.aging(p_company, 'sale', v_to) a
      union all
      select a.total, a.account_balance from erp.aging(p_company, 'purchase', v_to) a) z
    where z.total <> z.account_balance;
    value := n; severity := case when n > 0 then 'warning' else 'ok' end;
  else value := null; severity := 'na'; end if;
  return next;

  perform set_config('erp.simulate', v_prev_sim, true);
end $function$
;
