-- =====================================================================
-- erp.closing_checklist · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0047_inventory_closing 0048_closing_integration 0059_corporate_tax_integration 0063_financing_integration 0065_grants_integration   →   la vigente es la de 0065_grants_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.closing_checklist(p_company uuid, p_year integer)
 RETURNS TABLE(step integer, code text, status text, detail jsonb, screen text)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare
  v_fy    erp.fiscal_years;
  v_type  text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
  v_n     int;
  v_m     int;
  v_txt   text;
begin
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found or not erp.can_read(p_company) then return; end if;

  -- 1) Liquidaciones de IVA / IGIC de los cuatro trimestres
  select count(*) into v_n from erp.tax_settlements s
  where s.company_id = p_company and s.year = p_year and s.status = 'posted' and s.tax_type = v_type;
  select count(*) into v_m from erp.invoices i where i.company_id = p_company and i.fiscal_year_id = v_fy.id;
  step := 1; code := 'settlements'; screen := 'settlement';
  status := case when v_n >= 4 then 'done' when v_m = 0 and v_n = 0 then 'na' else 'pending' end;
  detail := jsonb_build_object('settled', v_n, 'tax', v_type); return next;

  -- 2) Periodificaciones del año anterior revertidas
  select count(*) into v_n from erp.accruals a where a.company_id = p_company and a.status = 'active' and a.cutoff_date < v_fy.starting_date;
  step := 2; code := 'accruals_reversed'; screen := 'adjustments';
  status := case when v_n = 0 then 'done' else 'pending' end; detail := jsonb_build_object('pending', v_n); return next;

  -- 3) Amortización del inmovilizado hasta el 31/12
  select count(*), count(*) filter (where erp.asset_depr_at(a.id, v_fy.ending_date) > erp.asset_posted(a.id)) into v_m, v_n
  from erp.fixed_assets a where a.company_id = p_company and a.status = 'active' and a.start_date <= v_fy.ending_date;
  step := 3; code := 'depreciation'; screen := 'assets';
  status := case when v_m = 0 then 'na' when v_n = 0 then 'done' else 'pending' end;
  detail := jsonb_build_object('assets', v_m, 'pending', v_n); return next;

  -- 4) Deterioro del inmovilizado: el valor recuperable lo estima la empresa
  step := 4; code := 'asset_impairment'; screen := 'assets';
  status := case when v_m = 0 then 'na' else 'review' end;
  detail := jsonb_build_object('impaired', (select count(distinct ev.asset_id) from erp.asset_events ev join erp.fixed_assets a on a.id = ev.asset_id
                                            where ev.company_id = p_company and ev.kind = 'impairment' and a.status = 'active')); return next;

  -- 5) Periodificaciones del cierre (las de este año)
  select count(*) into v_n from erp.accruals a where a.company_id = p_company and a.status <> 'cancelled'
    and a.cutoff_date between v_fy.starting_date and v_fy.ending_date;
  step := 5; code := 'accruals'; screen := 'adjustments';
  status := case when v_n > 0 then 'done' else 'review' end; detail := jsonb_build_object('accruals', v_n); return next;

  -- 6) Deterioro de clientes: vencidas hace más de 6 meses sin deterioro, y deterioros de facturas ya cobradas
  select count(*) into v_n from erp.open_items(p_company, v_fy.ending_date) o
  where o.invoice_type = 'sale' and o.pending > 0 and o.due_date + interval '6 months' <= v_fy.ending_date
    and not exists (select 1 from erp.receivable_impairments i where i.invoice_id = o.invoice_id and i.status = 'active');
  select count(*) into v_m from erp.receivable_impairments i join erp.open_items(p_company, v_fy.ending_date) o on o.invoice_id = i.invoice_id
  where i.company_id = p_company and i.status = 'active' and i.method = 'individual' and o.pending <= 0;
  step := 6; code := 'bad_debts'; screen := 'adjustments';
  status := case when v_m > 0 then 'pending' when v_n > 0 then 'review' else 'done' end;
  detail := jsonb_build_object('overdue_6m', v_n, 'collected', v_m); return next;

  -- 7) Provisiones revisadas este año
  select count(*), count(*) filter (where not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                                                      and m.movement_date between v_fy.starting_date and v_fy.ending_date))
  into v_m, v_n from erp.provisions pv where pv.company_id = p_company and pv.status = 'active'
    and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date <= v_fy.ending_date);
  step := 7; code := 'provisions'; screen := 'adjustments';
  status := case when v_m = 0 then 'review' when v_n = 0 then 'done' else 'pending' end;
  detail := jsonb_build_object('active', v_m, 'not_reviewed', v_n); return next;

  -- 8) Inventario del cierre (si hay existencias o compras de aprovisionamientos)
  select count(*) into v_n from erp.inventory_counts c where c.fiscal_year_id = v_fy.id and c.status = 'posted';
  -- v0.37.0 (0048): con cuentas de existencias, falta; sin ellas pero con compras de aprovisionamientos, revisar
  select count(*) into v_m from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting' and g.account_no ~ '^3[0-6]';
  step := 8; code := 'inventory'; screen := 'adjustments';
  status := case when v_n > 0 then 'done' when v_m > 0 then 'pending'
                 when exists (select 1 from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id
                              join erp.gl_accounts g on g.id = l.gl_account_id
                              where e.fiscal_year_id = v_fy.id and e.status = 'posted' and g.account_no ~ '^60[0-2]') then 'review'
                 else 'na' end;
  detail := jsonb_build_object('posted', v_n > 0); return next;

  -- 9) v0.43.0 · Financiación: intereses devengados y reclasificación a corto de los préstamos vivos (y ninguna cuota
  --    vencida sin contabilizar)
  select count(*) into v_m from erp.loans l where l.company_id = p_company and l.status = 'active' and l.start_date <= v_fy.ending_date;
  step := 9; code := 'financing'; screen := 'financing';
  if v_m = 0 then
    status := 'na'; detail := jsonb_build_object('loans', 0);
  else
    declare pv jsonb := erp.loan_year_end_preview(p_company, v_fy.ending_date);
    begin
      status := case when (pv->>'overdue')::int > 0 or (pv->>'accrual_total')::numeric <> 0 or (pv->>'reclassification_total')::numeric <> 0
                     then 'pending' else 'done' end;
      detail := jsonb_build_object('loans', v_m, 'accrual', pv->'accrual_total', 'reclassification', pv->'reclassification_total', 'overdue', pv->'overdue');
    end;
  end if;
  return next;

  -- 10) v0.44.0 · Subvenciones: la imputación del año de las de capital (después de la amortización, paso 3)
  select count(*) into v_m from erp.grants g where g.company_id = p_company and g.kind = 'capital' and g.status = 'active' and g.grant_date <= v_fy.ending_date;
  step := 10; code := 'grants'; screen := 'grants';
  if v_m = 0 then
    status := 'na'; detail := jsonb_build_object('grants', 0);
  else
    declare gy jsonb := erp.grant_year_end_preview(p_company, v_fy.ending_date);
    begin
      status := case when (gy->>'imputation_total')::numeric > 0 or (gy->>'tax_total')::numeric > 0 or (gy->>'depreciation_pending')::int > 0 then 'pending' else 'done' end;
      detail := jsonb_build_object('grants', v_m, 'imputation', gy->'imputation_total', 'depreciation_pending', gy->'depreciation_pending');
    end;
  end if;
  return next;

  -- 11) Comprobaciones del auditor sin avisos ni errores
  select count(*), string_agg(c.code, ', ' order by c.sort) into v_n, v_txt
  from erp.run_audit_checks(p_company, p_year, v_fy.ending_date) c where c.status in ('warning', 'error');
  step := 11; code := 'audit_checks'; screen := 'checks';
  status := case when v_n = 0 then 'done' else 'pending' end; detail := jsonb_build_object('open', v_n, 'codes', v_txt); return next;

  -- 12) v0.41.0 · Impuesto sobre Sociedades (antes de la regularización)
  step := 12; code := 'corporate_tax'; screen := 'corporate_tax';
  status := case when exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then 'done'
                 when erp.pre_tax_result(p_company, v_fy.id) = 0 then 'na' else 'pending' end;
  detail := jsonb_build_object('pre_tax_result', erp.pre_tax_result(p_company, v_fy.id)); return next;

  -- 13) Cierre del ejercicio (regularización, cierre y apertura)
  step := 13; code := 'close'; screen := 'closing';
  status := case when v_fy.status = 'closed' then 'done' else 'pending' end;
  detail := jsonb_build_object('fiscal_year_status', v_fy.status); return next;
end $function$
;
