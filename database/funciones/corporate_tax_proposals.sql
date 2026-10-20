-- =====================================================================
-- erp.corporate_tax_proposals · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax 0059_corporate_tax_integration   →   la vigente es la de 0059_corporate_tax_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_proposals(p_company uuid, p_year integer)
 RETURNS TABLE(origin text, source_id uuid, kind text, direction text, concept text, amount numeric, article text, included boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_fy erp.fiscal_years; v_erd boolean; v_debtors numeric;
  a record; v_acc numeric; v_fm numeric; v_m numeric; v_pend numeric; v_inc numeric; v_dec numeric; v_disposed boolean;
  i record; p record;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  v_erd := (erp.corporate_tax_regime_hint(p_company, p_year)->>'is_erd')::boolean;

  -- a) Amortización contable frente al máximo fiscal (art. 12.1.a). Meses de uso con la misma regla que la contable
  --    (el primer mes, por días); el máximo, sobre el coste.
  for a in select f.*, c.max_pct, c.code as class from erp.fixed_assets f join erp.depreciation_classes c on c.code = f.class_code
           where f.company_id = p_company and f.start_date <= v_fy.ending_date loop
    select coalesce(sum(d.amount), 0) into v_acc from erp.asset_depreciations d
    where d.asset_id = a.id and d.period_end between v_fy.starting_date and v_fy.ending_date;
    v_disposed := a.status = 'disposed' and a.disposal_date between v_fy.starting_date and v_fy.ending_date;
    v_m := erp.asset_months_at(1200, a.start_date, least(v_fy.ending_date, coalesce(a.disposal_date, v_fy.ending_date)))
         - case when a.start_date < v_fy.starting_date then erp.asset_months_at(1200, a.start_date, v_fy.starting_date - 1) else 0 end;
    v_fm := round(erp.asset_cost_at(a.id, v_fy.ending_date) * a.max_pct / 100 * greatest(v_m, 0) / 12, 2);
    v_pend := erp.corporate_tax_pending(p_company, 'depreciation', a.id, p_year);
    if v_acc - v_fm >= 0.01 then
      origin := 'depreciation'; source_id := a.id; kind := 'temporary'; direction := 'increase';
      concept := format('Amortización por encima del máximo fiscal · %s %s (máximo de la tabla: %s %%)', a.code, a.name, trim_scale(a.max_pct));
      amount := v_acc - v_fm; article := 'LIS art. 12.1.a'; included := true; return next;
    elsif v_pend > 0 and (v_disposed or v_fm - v_acc >= 0.01) then
      origin := 'depreciation'; source_id := a.id; kind := 'temporary'; direction := 'decrease';
      concept := case when v_disposed then format('Reversión al dar de baja · %s %s', a.code, a.name)
                      else format('Reversión: amortización contable por debajo del máximo fiscal · %s %s', a.code, a.name) end;
      amount := case when v_disposed then v_pend else least(v_pend, v_fm - v_acc) end;
      article := 'LIS art. 12.1.a'; included := true; return next;
    end if;
  end loop;

  -- b) Deterioro del inmovilizado: no deducible (art. 13.2.a); revierte con su reversión o con la baja
  for a in select f.* from erp.fixed_assets f where f.company_id = p_company
           and exists (select 1 from erp.asset_events e where e.asset_id = f.id and e.kind in ('impairment', 'reversal')) loop
    select coalesce(sum(e.amount) filter (where e.kind = 'impairment'), 0), coalesce(sum(e.amount) filter (where e.kind = 'reversal'), 0)
      into v_inc, v_dec
    from erp.asset_events e where e.asset_id = a.id and e.event_date between v_fy.starting_date and v_fy.ending_date;
    v_pend := erp.corporate_tax_pending(p_company, 'asset_impairment', a.id, p_year);
    v_disposed := a.status = 'disposed' and a.disposal_date between v_fy.starting_date and v_fy.ending_date;
    if v_inc > 0 then
      origin := 'asset_impairment'; source_id := a.id; kind := 'temporary'; direction := 'increase';
      concept := format('Deterioro del inmovilizado · %s %s', a.code, a.name); amount := v_inc;
      article := 'LIS art. 13.2.a'; included := true; return next;
    end if;
    v_dec := least(v_pend + v_inc, case when v_disposed then v_pend + v_inc else v_dec end);
    if v_dec > 0 then
      origin := 'asset_impairment'; source_id := a.id; kind := 'temporary'; direction := 'decrease';
      concept := format('Reversión del deterioro%s · %s %s', case when v_disposed then ' (baja)' else '' end, a.code, a.name);
      amount := v_dec; article := 'LIS art. 13.2.a'; included := true; return next;
    end if;
  end loop;

  -- c) Deterioro de clientes (art. 13.1 y 104)
  select coalesce(sum(o.pending), 0) into v_debtors from erp.open_items(p_company, v_fy.ending_date) o where o.invoice_type = 'sale';
  for i in select ri.*, inv.due_date, inv.invoice_no from erp.receivable_impairments ri left join erp.invoices inv on inv.id = ri.invoice_id
           where ri.company_id = p_company and ri.status <> 'cancelled' loop
    if i.impair_date between v_fy.starting_date and v_fy.ending_date then
      -- deterioro y fin en el mismo año: el gasto (694) y el ingreso (794) se compensan, no hay ajuste
      continue when i.end_date is not null and i.end_date <= v_fy.ending_date;
      if i.method = 'individual' and v_fy.ending_date < (i.due_date + interval '6 months')::date then
        origin := 'receivable_impairment'; source_id := i.id; kind := 'temporary'; direction := 'increase';
        concept := format('Deterioro %s · factura %s: no han pasado 6 meses desde el vencimiento (%s)', i.code, i.invoice_no,
                          to_char(i.due_date, 'DD/MM/YYYY'));
        amount := i.amount; article := 'LIS art. 13.1.a'; included := true; return next;
      elsif i.method = 'global' and greatest(0, i.amount - case when v_erd then round(v_debtors * 0.01, 2) else 0 end) > 0 then
        origin := 'receivable_impairment'; source_id := i.id; kind := 'temporary'; direction := 'increase';
        concept := case when v_erd then format('Deterioro global %s por encima del 1 %% de los deudores', i.code)
                        else format('Deterioro global %s: no deducible', i.code) end;
        amount := i.amount - case when v_erd then round(v_debtors * 0.01, 2) else 0 end;
        article := case when v_erd then 'LIS art. 13.1 y 104' else 'LIS art. 13.1' end; included := true; return next;
      end if;
    elsif i.impair_date < v_fy.starting_date then
      v_pend := erp.corporate_tax_pending(p_company, 'receivable_impairment', i.id, p_year);
      if v_pend > 0 and ((i.end_date is not null and i.end_date between v_fy.starting_date and v_fy.ending_date)
                         or (i.status = 'active' and i.method = 'individual' and v_fy.ending_date >= (i.due_date + interval '6 months')::date)) then
        origin := 'receivable_impairment'; source_id := i.id; kind := 'temporary'; direction := 'decrease';
        concept := case when i.end_date is not null then format('Reversión: el deterioro %s se ha revertido o aplicado', i.code)
                        else format('Reversión: el deterioro %s ya es deducible (6 meses desde el vencimiento)', i.code) end;
        amount := v_pend; article := 'LIS art. 13.1'; included := true; return next;
      end if;
    end if;
  end loop;

  -- d) Provisiones (art. 14): dotaciones del año y, si ya se ajustaron antes, su reversión
  for p in select pr.*, coalesce(sum(greatest(0, m.balance_after - m.balance_before)) filter (where m.kind in ('allocation', 'revision')), 0) as inc,
                  coalesce(sum(greatest(0, m.balance_before - m.balance_after)) filter (where m.kind in ('revision', 'application')), 0) as dec
           from erp.provisions pr
           left join erp.provision_movements m on m.provision_id = pr.id and m.movement_date between v_fy.starting_date and v_fy.ending_date
           where pr.company_id = p_company and pr.status <> 'cancelled'
           group by pr.id loop
    if p.inc > 0 then
      origin := 'provision'; source_id := p.id; kind := 'temporary'; direction := 'increase';
      concept := format('Provisión %s · %s', p.code, p.description); amount := p.inc;
      article := case p.kind when 'commercial' then 'LIS art. 14.9 (garantías: límite por experiencia)'
                             when 'taxes' then 'LIS art. 14 y 15 (deducible salvo el propio IS y las sanciones)'
                             else 'LIS art. 14.1 (deducible si nace de una obligación legal o contractual)' end;
      included := p.kind = 'commercial'; return next;
    end if;
    v_pend := erp.corporate_tax_pending(p_company, 'provision', p.id, p_year);
    if p.dec > 0 and v_pend > 0 then
      origin := 'provision'; source_id := p.id; kind := 'temporary'; direction := 'decrease';
      concept := format('Reversión de la provisión %s (aplicada o revisada a la baja)', p.code); amount := least(v_pend, p.dec);
      article := 'LIS art. 14'; included := true; return next;
    end if;
  end loop;
end $function$
;
