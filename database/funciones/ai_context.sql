-- =====================================================================
-- erp.ai_context · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0024_ai_context 0027_members   →   la vigente es la de 0027_members
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ai_context(p_company uuid, p_year integer, p_language text DEFAULT 'es'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  en      boolean := p_language = 'en';
  v_out   jsonb;
begin
  if not erp.ai_allowed(p_company) then raise exception 'The AI analyst is not enabled for you in this company'; end if;
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if not exists (select 1 from erp.fiscal_years where company_id = p_company and year = p_year) then
    raise exception 'Fiscal year % does not exist', p_year;
  end if;

  select jsonb_build_object(
    'language', case when en then 'en' else 'es' end,
    'year', p_year,
    'previous_year', p_year - 1,
    'currency', 'EUR',
    'company', (select jsonb_build_object(
                  'industry', c.industry, 'tax_territory', c.tax_territory,
                  'tax', case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT/IVA' end,
                  'imported_from', (select b.source from erp.import_batches b where b.company_id = c.id
                                    order by b.created_at desc limit 1))
                from erp.companies c where c.id = p_company),
    -- Estados financieros (modelo PYMES): partidas hasta el segundo nivel con importe en alguno de los dos años
    'balance_sheet', (select jsonb_agg(jsonb_build_object('line', case when en then s.label_en else s.label end,
                         'amount', s.amount, 'previous', s.amount_prev) order by s.sort)
                      from erp.financial_statement(p_company, p_year, 'balance') s
                      where s.level <= 2 and (s.amount <> 0 or s.amount_prev <> 0)),
    'income_statement', (select jsonb_agg(jsonb_build_object('line', case when en then s.label_en else s.label end,
                            'amount', s.amount, 'previous', s.amount_prev) order by s.sort)
                         from erp.financial_statement(p_company, p_year, 'pyg') s
                         where s.amount <> 0 or s.amount_prev <> 0),
    -- Flujos de efectivo: método indirecto y el cuadre con el directo
    'cash_flow_indirect', (select jsonb_agg(jsonb_build_object('line', case when en then s.label_en else s.label end,
                              'amount', s.amount, 'previous', s.amount_prev) order by s.sort)
                           from erp.cash_flow_statement(p_company, p_year, 'indirect') s
                           where s.level <= 2 and (s.amount <> 0 or s.amount_prev <> 0)),
    'cash_flow_check', (select k - 'cross_entries' - 'year' from erp.cash_flow_check(p_company, p_year) k),
    -- Ratios con su zona de referencia y su valoración (ok / low / high)
    'ratios', (select jsonb_agg(jsonb_build_object(
                  'group', r.grp, 'ratio', case when en then r.label_en else r.label end,
                  'formula', case when en then r.formula_en else r.formula end,
                  'unit', case r.unit when 'pct' then 'percent' when 'eur' then 'EUR' else r.unit end,
                  'value', erp.ai_ratio_value(r.value, r.unit), 'previous', erp.ai_ratio_value(r.value_prev, r.unit),
                  'reference_min', erp.ai_ratio_value(r.ref_min, r.unit), 'reference_max', erp.ai_ratio_value(r.ref_max, r.unit),
                  'status', r.status,
                  -- para que la IA no confunda "bajo" con "malo": en estos, quedarse por debajo es menos riesgo
                  'lower_is_safer', r.code in ('DEBT', 'DQ', 'FINC', 'DSO', 'DPO', 'DIO')))
               from erp.financial_ratios(p_company, p_year) r)
  ) into v_out;
  return jsonb_strip_nulls(v_out);
end $function$
;
