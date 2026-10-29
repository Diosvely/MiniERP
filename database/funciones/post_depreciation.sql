-- =====================================================================
-- erp.post_depreciation · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0041_fixed_assets 0046_asset_impairment   →   la vigente es la de 0046_asset_impairment
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.post_depreciation(p_company uuid, p_date date)
 RETURNS TABLE(entry_no integer, assets integer, amount numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_fy    uuid;
  v_entry uuid;
  v_no    int;
  v_n     int := 0;
  v_sum   numeric := 0;
  r       record;
  v_line  int := 0;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to register fixed assets in this company'; end if;
  select id into v_fy from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', p_date; end if;

  for r in
    select a.*, erp.asset_depr_at(a.id, p_date) - erp.asset_posted(a.id) as due
    from erp.fixed_assets a
    where a.company_id = p_company and a.status = 'active' and a.start_date <= p_date
      and not exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end >= p_date)
    order by a.code
  loop
    if r.due <= 0 then continue; end if;
    if v_entry is null then
      insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
      values (p_company, v_fy, p_date, 'Amortización del inmovilizado hasta el ' || to_char(p_date, 'DD/MM/YYYY'))
      returning id into v_entry;
    end if;
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
      (v_entry, p_company, v_line + 1, r.expense_account_id, r.due, 0, r.code || ' · ' || r.name),
      (v_entry, p_company, v_line + 2, r.depreciation_account_id, 0, r.due, r.code || ' · ' || r.name);
    v_line := v_line + 2;
    insert into erp.asset_depreciations (asset_id, company_id, period_end, amount, entry_id)
    values (r.id, p_company, p_date, r.due, v_entry);
    v_n := v_n + 1; v_sum := v_sum + r.due;
  end loop;
  if v_entry is null then raise exception 'Nothing to depreciate up to %', p_date; end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.post_entry(v_entry);
  perform set_config('erp.asset_engine', 'off', true);
  entry_no := v_no; assets := v_n; amount := v_sum;
  return next;
end $function$
;
