-- =====================================================================
-- 0024 · AI CONTEXT · Contexto para el Analista IA
-- ---------------------------------------------------------------------
-- La IA (Cloudflare Workers AI, modelos open source) INTERPRETA; no calcula ni contabiliza.
-- Esta función le prepara un resumen compacto y ya cuadrado de una empresa y un año:
--   balance y PyG (partidas con importe), estado de flujos (indirecto + cuadre del auditor) y ratios valorados.
-- Solo cifras agregadas: ni el nombre de la empresa, ni terceros, ni conceptos de asientos.
-- Solo el propietario de la aplicación (owner) puede usarla: la IA es para estudiar sus propias empresas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Corrección de los ratios detectada al probar la IA con las empresas reales:
--   con pérdidas (o patrimonio neto negativo) la calidad del resultado y el ROE dividían dos negativos
--   y salía un valor positivo que parecía bueno. Ahora quedan sin valor (—).
-- Este fichero se puede volver a ejecutar entero: todo es create or replace / update.
-- ---------------------------------------------------------------------
update erp.ratio_defs set
  help = 'Euros de caja por cada euro de beneficio. Por debajo de 1, el beneficio se queda en clientes o existencias en vez de llegar al banco. Con pérdidas no se calcula.',
  help_en = 'Euros of cash per euro of profit. Below 1, profit is stuck in receivables or inventory instead of reaching the bank. Not calculated when there is a loss.'
where code = 'CFQ';
update erp.ratio_defs set
  help = 'Lo que gana el socio por cada euro que tiene invertido. Se compara con lo que daría una inversión sin riesgo. Con patrimonio neto negativo no se calcula.',
  help_en = 'What shareholders earn per euro invested. Compare it with a risk-free investment. Not calculated when equity is negative.'
where code = 'ROE';

create or replace function erp.ratio_parts(p_company uuid, p_year int)
returns table (code text, num numeric, den numeric)
language plpgsql stable security definer set search_path = erp, public as $$
declare
  b    jsonb;      -- partidas del balance
  p    jsonb;      -- partidas de la PyG
  cfo  numeric;    -- total A) del estado de flujos
  ac numeric; pc numeric; pnc numeric; pn numeric; act numeric; inv numeric; cash numeric;
  cust numeric; supp numeric; sales numeric; procur numeric; amort numeric; fin numeric; ebit numeric; profit numeric;
begin
  if not exists (select 1 from erp.fiscal_years where company_id = p_company and year = p_year) then return; end if;
  select jsonb_object_agg(a.code, a.amount) into b from erp.fs_amounts(p_company, p_year, 'balance') a;
  select jsonb_object_agg(a.code, a.amount) into p from erp.fs_amounts(p_company, p_year, 'pyg') a;
  select coalesce(sum(d.amount), 0) into cfo from erp.cf_indirect_detail(p_company, p_year) d where d.line_code like 'IA%';

  ac := (b->>'AC')::numeric;      pc := (b->>'PC')::numeric;   pnc := (b->>'PNC')::numeric;
  pn := (b->>'PN')::numeric;      act := (b->>'ACT')::numeric; inv := (b->>'AC.I')::numeric;
  cash := (b->>'AC.VI')::numeric; cust := (b->>'AC.II.1')::numeric; supp := (b->>'PC.IV.1')::numeric;
  -- en la PyG los gastos van en negativo: se cambian de signo para dividir
  sales := (p->>'P1')::numeric;   procur := -(p->>'P4')::numeric;  amort := -(p->>'P8')::numeric;
  fin := -(p->>'P14')::numeric;   ebit := (p->>'PA')::numeric;     profit := (p->>'PD')::numeric;

  return query values
    ('WC', ac - pc, null::numeric), ('CR', ac, pc), ('QR', ac - inv, pc), ('CASH', cash, pc),
    ('DEBT', pnc + pc, pn + pnc + pc), ('AUT', pn, pnc + pc), ('SOLV', act, pnc + pc), ('DQ', pc, pnc + pc),
    ('FINC', fin, sales),
    ('ROA', ebit, act),
    -- con patrimonio neto negativo el ROE no tiene sentido (dos negativos dan un positivo engañoso)
    ('ROE', profit, case when pn > 0 then pn else 0 end), ('OPM', ebit, sales), ('NPM', profit, sales), ('ATO', sales, act),
    ('EBITDA', ebit + amort, null),
    ('DSO', cust * 365, sales), ('DPO', supp * 365, procur), ('DIO', inv * 365, procur),
    ('CFO', cfo, null),
    -- con pérdidas la calidad del resultado no tiene sentido: −caja / −pérdida daría un positivo engañoso
    ('CFQ', cfo, case when profit > 0 then profit else 0 end),
    ('CFD', cfo, pc);
end $$;

-- Valor de un ratio tal como se le enseña a la IA: redondeado como en pantalla (los porcentajes, ya en %)
create or replace function erp.ai_ratio_value(p_value numeric, p_unit text)
returns numeric language sql immutable as $$
  select case p_unit when 'pct' then round(p_value * 100, 1) when 'days' then round(p_value, 0)
                     else round(p_value, 2) end;
$$;

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
                  'unit', case r.unit when 'pct' then 'percent' when 'eur' then 'EUR' else r.unit end,
                  'value', erp.ai_ratio_value(r.value, r.unit), 'previous', erp.ai_ratio_value(r.value_prev, r.unit),
                  'reference_min', erp.ai_ratio_value(r.ref_min, r.unit), 'reference_max', erp.ai_ratio_value(r.ref_max, r.unit),
                  'status', r.status,
                  -- para que la IA no confunda "bajo" con "malo": en estos, quedarse por debajo es menos riesgo
                  'lower_is_safer', r.code in ('DEBT', 'DQ', 'FINC', 'DSO', 'DPO', 'DIO')))
               from erp.financial_ratios(p_company, p_year) r)
  ) into v_out;
  return jsonb_strip_nulls(v_out);
end $$;

revoke execute on function erp.can_use_ai(), erp.ai_context(uuid, int, text), erp.ai_ratio_value(numeric, text) from anon, public;
grant execute on function erp.can_use_ai(), erp.ai_context(uuid, int, text) to authenticated;
