-- =====================================================================
-- erp.year_closing_preview · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0017_year_closing 0042_assets_integration 0044_adjustments_integration 0046_asset_impairment 0048_closing_integration 0059_corporate_tax_integration 0061_equity_integration 0065_grants_integration   →   la vigente es la de 0065_grants_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.year_closing_preview(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_fy       erp.fiscal_years;
  v_prev     erp.fiscal_years;
  v_next     erp.fiscal_years;
  v_done     erp.year_closings;
  v_checks   jsonb := '[]';
  v_n        int;
  v_txt      text;
  v_result   numeric;
  v_res_no   text := erp.result_account_no(p_company);
  v_pl       jsonb;
  v_close    jsonb;
  v_reg      jsonb;   -- v0.44.0: regularización de los grupos 8 y 9 (cuenta, saldo y su 13x)
begin
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then
    raise exception 'Fiscal year % does not exist', p_year;
  end if;
  select * into v_prev from erp.fiscal_years where company_id = p_company and year = p_year - 1;
  select * into v_next from erp.fiscal_years where company_id = p_company and year = p_year + 1;
  select * into v_done from erp.year_closings where fiscal_year_id = v_fy.id and status = 'posted';

  -- 1) COMPROBACIONES · error = impide cerrar · warning = hay que aceptarlo · info = solo informa
  if v_prev.id is not null and v_prev.status = 'open'
     and exists (select 1 from erp.journal_entries where fiscal_year_id = v_prev.id and status = 'posted') then
    v_checks := v_checks || jsonb_build_object('code', 'previous_year_open', 'severity', 'error', 'detail', p_year - 1);
  end if;

  select count(*) into v_n from erp.journal_entries where fiscal_year_id = v_fy.id and status = 'draft';
  if v_n > 0 then
    v_checks := v_checks || jsonb_build_object('code', 'draft_entries', 'severity', 'error', 'detail', v_n);
  end if;

  -- Trimestres de IVA / IGIC sin liquidar (después del cierre ya no se podrán contabilizar)
  select string_agg(x.tax || ' ' || x.q || 'T', ', ' order by x.tax, x.q) into v_txt
  from (select case s.tax_type when 'VAT' then 'IVA' else 'IGIC' end as tax, q
        from erp.tax_settlement_setup s cross join generate_series(1, 4) q
        where s.company_id = p_company
          and not exists (select 1 from erp.tax_settlements t
                          where t.company_id = p_company and t.tax_type = s.tax_type
                            and t.year = p_year and t.quarter = q and t.status = 'posted')) x;
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'unsettled_quarters', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- Saldos anómalos graves (p. ej. caja acreedora): se arrastrarían al año siguiente
  select string_agg(a.account_no, ', ' order by a.account_no) into v_txt
  from erp.balance_anomalies(p_company, p_year) a where a.severity = 'error';
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'anomalies', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.35.0 · Inmovilizado sin amortizar hasta el final del ejercicio (la amortización es un gasto del año: NRV 2.ª)
  select string_agg(a.code, ', ' order by a.code) into v_txt
  from erp.fixed_assets a
  where a.company_id = p_company and a.status = 'active' and a.start_date <= v_fy.ending_date
    and erp.asset_depr_at(a.id, v_fy.ending_date) > erp.asset_posted(a.id);
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'assets_not_depreciated', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.36.0 · Periodificaciones de un ejercicio anterior sin revertir (el gasto o el ingreso se quedaría en el balance)
  select string_agg(a.code, ', ' order by a.code) into v_txt
  from erp.accruals a
  where a.company_id = p_company and a.status = 'active' and a.cutoff_date < v_fy.starting_date;
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'accruals_unreversed', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.37.0 · Inventario sin contabilizar (hay existencias o compras de aprovisionamientos) y provisiones sin revisar
  if not exists (select 1 from erp.inventory_counts c where c.fiscal_year_id = v_fy.id and c.status = 'posted')
     -- (solo si la empresa tiene cuentas de existencias: una de servicios con alguna compra suelta no tiene almacén)
     and exists (select 1 from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting' and g.account_no ~ '^3[0-6]') then
    v_checks := v_checks || jsonb_build_object('code', 'inventory_not_counted', 'severity', 'warning', 'detail', p_year);
  end if;
  select string_agg(pv.code, ', ' order by pv.code) into v_txt
  from erp.provisions pv
  where pv.company_id = p_company and pv.status = 'active'
    and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date < v_fy.starting_date)
    and not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                    and m.movement_date between v_fy.starting_date and v_fy.ending_date);
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'provisions_not_reviewed', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.41.0 · Impuesto sobre Sociedades: va antes de la regularización (en modo estricto, sin él no se cierra)
  if v_fy.status = 'open' and erp.pre_tax_result(p_company, v_fy.id) <> 0
     and not exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then
    v_checks := v_checks || jsonb_build_object('code', 'corporate_tax_missing',
      'severity', case when (select control_mode from erp.companies where id = p_company) = 'strict' then 'error' else 'warning' end,
      'detail', p_year);
  end if;
  -- …y después de contabilizarlo, la 473 (retenciones y pagos a cuenta) tiene que quedar a cero
  if v_fy.status = 'open' and exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then
    select string_agg(g.account_no, ', ') into v_txt from (
      select g.account_no from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
      where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted' and e.entry_type not in ('closing_pl', 'closing')
        and g.account_no like '473%' group by g.account_no having sum(l.debit - l.credit) <> 0) g;
    if v_txt is not null then
      v_checks := v_checks || jsonb_build_object('code', 'withholdings_left', 'severity', 'warning', 'detail', v_txt);
    end if;
  end if;

  -- v0.42.0 · el resultado del año anterior sigue en la 129: la junta aún no lo ha repartido (Operaciones societarias)
  if v_fy.status = 'open' and erp.equity_bal(p_company, '129', v_fy.ending_date) <> 0 then
    v_checks := v_checks || jsonb_build_object('code', 'result_not_distributed', 'severity', 'warning',
      'detail', erp.equity_bal(p_company, '129', v_fy.ending_date));
  end if;

  -- v0.44.0 · subvenciones de capital sin imputar este año (Subvenciones): la parte del año iría al año siguiente
  if v_fy.status = 'open' and exists (select 1 from erp.grants g where g.company_id = p_company and g.kind = 'capital' and g.status = 'active') then
    declare gy jsonb := erp.grant_year_end_preview(p_company, v_fy.ending_date);
    begin
      if (gy->>'imputation_total')::numeric > 0 or (gy->>'tax_total')::numeric > 0 then
        v_checks := v_checks || jsonb_build_object('code', 'grants_not_imputed', 'severity', 'warning', 'detail', gy->>'imputation_total');
      end if;
    end;
  end if;

  if not exists (select 1 from erp.gl_accounts where company_id = p_company and account_no = v_res_no) then
    v_checks := v_checks || jsonb_build_object('code', 'result_account_created', 'severity', 'info', 'detail', v_res_no);
  end if;
  if v_next.id is null then
    v_checks := v_checks || jsonb_build_object('code', 'next_year_created', 'severity', 'info', 'detail', p_year + 1);
  elsif v_next.status = 'closed' then
    v_checks := v_checks || jsonb_build_object('code', 'next_year_closed', 'severity', 'error', 'detail', p_year + 1);
  end if;

  -- 2) REGULARIZACIÓN: cada cuenta de gastos e ingresos se salda al lado contrario; la diferencia, a la 129
  select -coalesce(sum(b.balance), 0),
         coalesce(jsonb_agg(jsonb_build_object('account_no', b.account_no, 'account_name', b.account_name,
                    'debit', greatest(-b.balance, 0), 'credit', greatest(b.balance, 0)) order by b.account_no), '[]')
    into v_result, v_pl
  from erp.year_account_balances(v_fy.id) b
  where left(b.account_no, 1) in ('6', '7');
  if v_result <> 0 then
    v_pl := v_pl || jsonb_build_object('account_no', v_res_no, 'account_name', 'Resultado del ejercicio',
                      'debit', greatest(-v_result, 0), 'credit', greatest(v_result, 0));
  end if;

  -- 2b) v0.44.0 · REGULARIZACIÓN DE LOS GRUPOS 8 Y 9: cada cuenta se salda contra su 13x (94x / 84x → 13 del mismo
  --     tercer dígito; 83x, el efecto impositivo, → 130). La subcuenta 13x: la primera que haya o, si no, se crea al cerrar
  select coalesce(jsonb_agg(jsonb_build_object('account_no', r.account_no, 'account_name', r.account_name, 'balance', r.balance,
                    'target', coalesce((select min(g.account_no) from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting'
                                         and g.account_no like r.tp || '%'),
                                       (select rpad(r.tp, posting_account_digits - 1, '0') || '1' from erp.companies where id = p_company)))
                  order by r.account_no), '[]')
    into v_reg
  from (select b.account_no, b.account_name, b.balance,
               case when b.account_no like '83%' then '130' else '13' || substr(b.account_no, 3, 1) end as tp
        from erp.year_account_balances(v_fy.id) b where left(b.account_no, 1) in ('8', '9')) r;
  v_pl := v_pl
    || (select coalesce(jsonb_agg(jsonb_build_object('account_no', x->>'account_no', 'account_name', x->>'account_name',
                  'debit', greatest(-(x->>'balance')::numeric, 0), 'credit', greatest((x->>'balance')::numeric, 0)) order by x->>'account_no'), '[]')
        from jsonb_array_elements(v_reg) x)
    || (select coalesce(jsonb_agg(jsonb_build_object('account_no', t.target, 'account_name', 'Subvenciones, donaciones y legados',
                  'debit', greatest(t.bal, 0), 'credit', greatest(-t.bal, 0)) order by t.target), '[]')
        from (select x->>'target' as target, sum((x->>'balance')::numeric) as bal from jsonb_array_elements(v_reg) x group by 1) t where t.bal <> 0);

  -- 3) CIERRE: saldos de balance (grupos 1 a 5) después de la regularización, saldados al lado contrario
  select coalesce(jsonb_agg(jsonb_build_object('account_no', c.account_no, 'account_name', c.account_name,
                    'debit', greatest(-c.balance, 0), 'credit', greatest(c.balance, 0)) order by c.account_no), '[]')
    into v_close
  from (
    select b.account_no, b.account_name,
           b.balance + case when b.account_no = v_res_no then -v_result else 0 end
                     + coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_reg) x where x->>'target' = b.account_no), 0) as balance
    from erp.year_account_balances(v_fy.id) b
    where left(b.account_no, 1) between '1' and '5'
    union all   -- la 129 aún sin movimientos
    select v_res_no, 'Resultado del ejercicio', -v_result
    where v_result <> 0
      and not exists (select 1 from erp.year_account_balances(v_fy.id) b where b.account_no = v_res_no)
    union all   -- v0.44.0: la 13x aún sin movimientos
    select t.target, 'Subvenciones, donaciones y legados', t.bal
    from (select x->>'target' as target, sum((x->>'balance')::numeric) as bal from jsonb_array_elements(v_reg) x group by 1) t
    where t.bal <> 0 and not exists (select 1 from erp.year_account_balances(v_fy.id) b where b.account_no = t.target)
  ) c
  where c.balance <> 0;

  return jsonb_build_object(
    'year', p_year, 'status', v_fy.status,
    'closing_date', v_fy.ending_date, 'opening_date', v_fy.ending_date + 1,
    'checks', v_checks,
    'can_close', v_fy.status = 'open' and not exists (select 1 from jsonb_array_elements(v_checks) c where c->>'severity' = 'error'),
    'has_warnings', exists (select 1 from jsonb_array_elements(v_checks) c where c->>'severity' = 'warning'),
    'result', coalesce(v_done.result, v_result),
    'result_account_no', v_res_no,
    'closing_pl_lines', v_pl,
    'closing_lines', v_close,
    'closed', v_done.id is not null,
    'closing_id', v_done.id,
    'entries', case when v_done.id is null then null else jsonb_build_object(
       'closing_pl', (select entry_no from erp.journal_entries where id = v_done.closing_pl_entry_id),
       'closing',    (select entry_no from erp.journal_entries where id = v_done.closing_entry_id),
       'opening',    (select entry_no from erp.journal_entries where id = v_done.opening_entry_id)) end,
    'can_reopen', v_done.id is not null and coalesce(v_next.status, 'open') = 'open');
end $function$
;
