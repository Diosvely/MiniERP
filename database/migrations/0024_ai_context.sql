-- =====================================================================
-- 0024 · AI CONTEXT · Contexto para el Analista IA
-- ---------------------------------------------------------------------
-- La IA (Cloudflare Workers AI, modelos open source) INTERPRETA; no calcula ni contabiliza.
-- Esta función le prepara un resumen compacto y ya cuadrado de una empresa y un año:
--   balance y PyG (partidas con importe), estado de flujos (indirecto + cuadre del auditor) y ratios valorados.
-- Solo cifras agregadas: ni el nombre de la empresa, ni terceros, ni conceptos de asientos.
-- Solo el propietario de la aplicación (owner) puede usarla: la IA es para estudiar sus propias empresas.
-- =====================================================================

-- ¿Puede el usuario conectado usar el Analista IA? (la web lo usa para mostrar u ocultar el botón)
create or replace function erp.can_use_ai()
returns boolean language sql stable as $$
  select erp.is_owner();
$$;

create or replace function erp.ai_context(p_company uuid, p_year int, p_language text default 'es')
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare
  en      boolean := p_language = 'en';
  v_out   jsonb;
begin
  if not erp.is_owner() then raise exception 'The AI analyst is only available to the application owner'; end if;
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
                  'unit', r.unit, 'value', r.value, 'previous', r.value_prev,
                  'reference_min', r.ref_min, 'reference_max', r.ref_max, 'status', r.status))
               from erp.financial_ratios(p_company, p_year) r)
  ) into v_out;
  return jsonb_strip_nulls(v_out);
end $$;

revoke execute on function erp.can_use_ai(), erp.ai_context(uuid, int, text) from anon, public;
grant execute on function erp.can_use_ai(), erp.ai_context(uuid, int, text) to authenticated;
