-- =====================================================================
-- erp.ratio_parts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0023_financial_ratios 0024_ai_context   →   la vigente es la de 0024_ai_context
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.ratio_parts(p_company uuid, p_year integer)
 RETURNS TABLE(code text, num numeric, den numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
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
end $function$
;
