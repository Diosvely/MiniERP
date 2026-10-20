-- =====================================================================
-- 0057 · IMPUESTO SOBRE SOCIEDADES (I): cálculo, ajustes y bases negativas · v0.41.0
-- ---------------------------------------------------------------------
-- El último paso del cierre de una sociedad, antes de la regularización a la 129 (Ley 27/2014, LIS):
--
--   resultado contable antes de impuestos                     (grupos 6 y 7, sin la 630)
--   ± ajustes extracontables: diferencias PERMANENTES (no revierten: una multa) y TEMPORARIAS (revierten: el gasto se
--     deduce en otro año)                                     (art. 10.3 LIS: la base parte del resultado contable)
--   = base imponible previa
--   − compensación de bases negativas de años anteriores      (art. 26: hasta el 70 % de la base previa; 1 millón siempre)
--   = base imponible × tipo de gravamen = cuota íntegra       (art. 29 y DT 44.ª)
--   − retenciones y pagos fraccionados (473)                  = cuota diferencial: a pagar (4752) o a devolver (4709)
--
-- Ajustes que el ERP PROPONE solo, desde lo que ya sabe (cada uno se puede quitar; los manuales los añade el usuario):
--   · amortización contable por encima del máximo fiscal de la tabla (art. 12.1.a) → temporaria +; revierte cuando la
--     contable queda por debajo del máximo (o al dar de baja el activo)
--   · deterioro del inmovilizado (art. 13.2.a: no deducible) → temporaria +; revierte con la reversión o la baja
--   · deterioro de clientes: el individual, si al cierre no han pasado 6 meses desde el vencimiento (art. 13.1.a); el
--     global, entero (art. 13.1), salvo las empresas de reducida dimensión hasta el 1 % de los deudores (art. 104)
--     → temporaria +; revierte cuando pasa a ser deducible, se revierte o se da de baja
--   · provisiones (art. 14): se proponen todas; las de garantías (comerciales) incluidas por defecto (límite del art.
--     14.9 por experiencia, que el ERP no calcula), las de responsabilidades e impuestos sin incluir (deducibles si
--     nacen de una obligación legal o contractual: art. 14.1.a, a contrario) · PENDIENTE DE VALIDAR POR DIOSVELY
--
-- Tipo de gravamen: lo elige el usuario; el ERP sugiere uno por la cifra de negocios (70x) del año anterior.
--   2026 (pendiente de validar en el BOE por Diosvely): general 25 % · reducida dimensión (INCN < 10 M) 23 % ·
--   microempresa (INCN < 1 M) 19 % hasta 50.000 € y 21 % el resto · nueva creación 15 %.
-- Los asientos (6300 / 473 / 4752 / 4709 y el diferido 4740 / 4745 / 6301) llegan en la 0058.
-- Seguridad: lectura con can_read, cambios con can_write (RLS). Re-ejecutable.
-- =====================================================================

-- 1) Tipos de gravamen por año y régimen (upto: límite superior del tramo; null = el resto)
create table if not exists erp.corporate_tax_rates (
  valid_from_year smallint not null,
  regime          text not null check (regime in ('general', 'erd', 'micro', 'new_entity')),
  upto            numeric(15,2),
  rate            numeric(5,2) not null check (rate >= 0 and rate <= 100),
  primary key (valid_from_year, regime, rate)
);
comment on table erp.corporate_tax_rates is 'Corporate income tax rates by year and regime (LIS art. 29 and DT 44.ª). upto = upper limit of the bracket.';
insert into erp.corporate_tax_rates (valid_from_year, regime, upto, rate) values
(2026, 'general',    null,     25),
(2026, 'erd',        null,     23),
(2026, 'micro',      50000,    19),
(2026, 'micro',      null,     21),
(2026, 'new_entity', null,     15)
on conflict (valid_from_year, regime, rate) do update set upto = excluded.upto;
alter table erp.corporate_tax_rates enable row level security;
drop policy if exists read on erp.corporate_tax_rates;
create policy read on erp.corporate_tax_rates for select to authenticated using (true);
revoke all on erp.corporate_tax_rates from anon, public;
grant select on erp.corporate_tax_rates to authenticated;

-- 2) La declaración de cada ejercicio y sus ajustes
create table if not exists erp.corporate_tax_returns (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references erp.companies(id) on delete cascade,
  fiscal_year_id        uuid not null references erp.fiscal_years(id) on delete cascade,
  regime                text not null check (regime in ('general', 'erd', 'micro', 'new_entity')),
  recognize_loss_credit boolean not null default false,     -- registrar el crédito fiscal por bases negativas (4745)
  status                text not null default 'draft' check (status in ('draft', 'posted')),
  result                jsonb,                               -- el cálculo al contabilizar (0058)
  created_at            timestamptz not null default now(),
  unique (fiscal_year_id)
);
comment on table erp.corporate_tax_returns is 'Corporate income tax of each fiscal year (BC: no standard module; SAP: tax provision).';
create index if not exists corporate_tax_returns_company_idx on erp.corporate_tax_returns (company_id);

create table if not exists erp.corporate_tax_adjustments (
  id         uuid primary key default gen_random_uuid(),
  return_id  uuid not null references erp.corporate_tax_returns(id) on delete cascade,
  company_id uuid not null references erp.companies(id) on delete cascade,
  origin     text not null check (origin in ('depreciation', 'asset_impairment', 'receivable_impairment', 'provision', 'manual')),
  source_id  uuid,                                          -- activo, deterioro o provisión de donde sale
  kind       text not null check (kind in ('permanent', 'temporary')),
  direction  text not null check (direction in ('increase', 'decrease')),
  concept    text not null check (length(btrim(concept)) > 0),
  amount     numeric(15,2) not null check (amount > 0),
  article    text,
  included   boolean not null default true,
  auto       boolean not null default false,
  created_at timestamptz not null default now(),
  check (auto = (origin <> 'manual')),
  check (origin <> 'manual' or source_id is null)
);
comment on table erp.corporate_tax_adjustments is 'Book-to-tax adjustments (permanent / temporary differences) of a corporate tax return.';
create unique index if not exists corporate_tax_adj_auto_uq on erp.corporate_tax_adjustments (return_id, origin, source_id, direction) where auto;
create index if not exists corporate_tax_adj_company_idx on erp.corporate_tax_adjustments (company_id);
create index if not exists corporate_tax_adj_return_idx on erp.corporate_tax_adjustments (return_id);

alter table erp.corporate_tax_returns enable row level security;
alter table erp.corporate_tax_adjustments enable row level security;
drop policy if exists read on erp.corporate_tax_returns;
drop policy if exists read on erp.corporate_tax_adjustments;
create policy read on erp.corporate_tax_returns for select to authenticated using (erp.can_read(company_id));
create policy read on erp.corporate_tax_adjustments for select to authenticated using (erp.can_read(company_id));
revoke all on erp.corporate_tax_returns, erp.corporate_tax_adjustments from anon, public;
grant select on erp.corporate_tax_returns, erp.corporate_tax_adjustments to authenticated;

-- 3) Piezas del cálculo
-- Cifra de negocios (INCN) del ejercicio: saldo acreedor de la 70x (ventas − devoluciones − rappels − descuentos)
create or replace function erp.net_turnover(p_company uuid, p_fy uuid)
returns numeric language sql stable as $$
  select coalesce(sum(l.credit - l.debit), 0)
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and e.fiscal_year_id = p_fy and e.status = 'posted'
    and e.entry_type not in ('closing_pl', 'closing') and g.account_no like '70%';
$$;

-- Resultado contable antes de impuestos: ingresos − gastos (grupos 6 y 7) sin el gasto por impuesto (630, 633, 638)
create or replace function erp.pre_tax_result(p_company uuid, p_fy uuid)
returns numeric language sql stable as $$
  select coalesce(sum(l.credit - l.debit), 0)
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and e.fiscal_year_id = p_fy and e.status = 'posted'
    and e.entry_type not in ('closing_pl', 'closing')
    and left(g.account_no, 1) in ('6', '7') and left(g.account_no, 3) not in ('630', '633', '638');
$$;

-- Régimen sugerido: por la cifra de negocios del año anterior (art. 101: reducida dimensión si < 10 M; microempresa,
-- DT 44.ª, si < 1 M). Sin año anterior, la del propio ejercicio. Nueva creación no se puede deducir: lo elige el usuario.
create or replace function erp.corporate_tax_regime_hint(p_company uuid, p_year int)
returns jsonb language plpgsql stable as $$
declare v_fy erp.fiscal_years; v_prev erp.fiscal_years; v_basis numeric; v_by int;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  select * into v_prev from erp.fiscal_years where company_id = p_company and year = p_year - 1;
  if found then v_basis := erp.net_turnover(p_company, v_prev.id); v_by := p_year - 1;
  else v_basis := erp.net_turnover(p_company, v_fy.id); v_by := p_year; end if;
  return jsonb_build_object('turnover', v_basis, 'basis_year', v_by,
    'suggested', case when v_basis < 1000000 then 'micro' when v_basis < 10000000 then 'erd' else 'general' end,
    'is_erd', v_basis < 10000000, 'is_micro', v_basis < 1000000);
end $$;

-- Cuota íntegra por tramos y tipo marginal (el que se usa para el impuesto diferido)
create or replace function erp.corporate_tax_quota(p_year int, p_regime text, p_base numeric)
returns jsonb language plpgsql stable as $$
declare r record; v_from int; v_prev numeric := 0; v_quota numeric := 0; v_marginal numeric; v_rows jsonb := '[]';
begin
  select max(valid_from_year) into v_from from erp.corporate_tax_rates where valid_from_year <= p_year and regime = p_regime;
  if v_from is null then raise exception 'No corporate tax rates for % (%): add them to erp.corporate_tax_rates', p_year, p_regime; end if;
  for r in select upto, rate from erp.corporate_tax_rates where valid_from_year = v_from and regime = p_regime
           order by upto nulls last loop
    if v_marginal is null or p_base > v_prev then v_marginal := r.rate; end if;
    if p_base > v_prev then
      v_quota := v_quota + round((least(p_base, coalesce(r.upto, p_base)) - v_prev) * r.rate / 100, 2);
      v_rows := v_rows || jsonb_build_object('from', v_prev, 'upto', r.upto, 'rate', r.rate,
                                             'base', least(p_base, coalesce(r.upto, p_base)) - v_prev);
    end if;
    v_prev := coalesce(r.upto, v_prev);
  end loop;
  return jsonb_build_object('quota', v_quota, 'marginal_rate', v_marginal, 'brackets', v_rows, 'rates_year', v_from);
end $$;

-- Lo que queda por revertir de una diferencia temporaria (declaraciones contabilizadas de años anteriores)
create or replace function erp.corporate_tax_pending(p_company uuid, p_origin text, p_source uuid, p_year int)
returns numeric language sql stable as $$
  select coalesce(sum(case a.direction when 'increase' then a.amount else -a.amount end), 0)
  from erp.corporate_tax_adjustments a
  join erp.corporate_tax_returns r on r.id = a.return_id and r.status = 'posted'
  join erp.fiscal_years fy on fy.id = r.fiscal_year_id
  where a.company_id = p_company and a.origin = p_origin and a.source_id = p_source and a.included
    and a.kind = 'temporary' and fy.year < p_year;
$$;

-- 4) Ajustes que propone el ERP para un ejercicio
create or replace function erp.corporate_tax_proposals(p_company uuid, p_year int)
returns table (origin text, source_id uuid, kind text, direction text, concept text, amount numeric, article text, included boolean)
language plpgsql stable as $$
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
      concept := format('Amortización por encima del máximo fiscal · %s %s (contable %s; máximo fiscal %s, %s %%)',
                        a.code, a.name, v_acc, v_fm, a.max_pct);
      amount := v_acc - v_fm; article := 'LIS art. 12.1.a'; included := true; return next;
    elsif v_pend > 0 and (v_disposed or v_fm - v_acc >= 0.01) then
      origin := 'depreciation'; source_id := a.id; kind := 'temporary'; direction := 'decrease';
      concept := case when v_disposed then format('Reversión al dar de baja · %s %s', a.code, a.name)
                      else format('Reversión: amortización por debajo del máximo fiscal · %s %s (contable %s; máximo %s)', a.code, a.name, v_acc, v_fm) end;
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
        concept := case when v_erd then format('Deterioro global %s por encima del 1 %% de los deudores (%s)', i.code, round(v_debtors * 0.01, 2))
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
end $$;

-- 5) Bases negativas pendientes de años anteriores (FIFO: primero las más antiguas)
create or replace function erp.corporate_tax_loss_carryforwards(p_company uuid, p_year int)
returns table (origin_year int, generated numeric, used numeric, pending numeric, credit_rate numeric)
language sql stable as $$
  with gen as (
    select fy.year::int as y, (r.result->>'loss_generated')::numeric as amount,
           case when (r.result->>'loss_credit')::numeric > 0 then (r.result->>'deferred_rate')::numeric end as rate
    from erp.corporate_tax_returns r join erp.fiscal_years fy on fy.id = r.fiscal_year_id
    where r.company_id = p_company and r.status = 'posted' and fy.year < p_year and (r.result->>'loss_generated')::numeric > 0),
  usage as (
    select (u->>'origin_year')::int as y, sum((u->>'amount')::numeric) as amount
    from erp.corporate_tax_returns r join erp.fiscal_years fy on fy.id = r.fiscal_year_id,
         jsonb_array_elements(coalesce(r.result->'loss_usage', '[]')) u
    where r.company_id = p_company and r.status = 'posted' and fy.year < p_year
    group by 1)
  select g.y, g.amount, coalesce(u.amount, 0), g.amount - coalesce(u.amount, 0), g.rate
  from gen g left join usage u on u.y = g.y
  where g.amount - coalesce(u.amount, 0) > 0
  order by g.y;
$$;

-- 6) El cálculo completo (solo lee). Con declaración en borrador, usa su régimen y sus ajustes; sin ella, los propuestos
--    y el régimen sugerido. p_regime / p_recognize, si llegan, mandan (para probar sin guardar).
create or replace function erp.corporate_tax_calc(p_company uuid, p_year int, p_regime text default null, p_recognize boolean default null)
returns jsonb language plpgsql stable as $$
declare
  v_fy erp.fiscal_years; v_ret erp.corporate_tax_returns; v_hint jsonb; v_regime text; v_recognize boolean;
  v_adj jsonb; v_result numeric; v_perm numeric; v_tinc numeric; v_tdec numeric; v_prev numeric;
  v_limit numeric; v_avail numeric; v_comp numeric := 0; v_usage jsonb := '[]'; v_left numeric; b record;
  v_base numeric; v_q jsonb; v_quota numeric; v_rate numeric; v_wh numeric; v_diff numeric;
  v_loss numeric; v_credit numeric; v_credit_used numeric := 0; v_def numeric; v_warn jsonb := '[]';
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  select * into v_ret from erp.corporate_tax_returns where fiscal_year_id = v_fy.id;
  if v_ret.status = 'posted' then return v_ret.result || jsonb_build_object('status', 'posted', 'return_id', v_ret.id); end if;
  v_hint := erp.corporate_tax_regime_hint(p_company, p_year);
  v_regime := coalesce(p_regime, v_ret.regime, v_hint->>'suggested');
  v_recognize := coalesce(p_recognize, v_ret.recognize_loss_credit, false);

  -- ajustes: los de la declaración (borrador) o los propuestos
  if v_ret.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'origin', a.origin, 'source_id', a.source_id, 'kind', a.kind,
             'direction', a.direction, 'concept', a.concept, 'amount', a.amount, 'article', a.article, 'included', a.included,
             'auto', a.auto) order by a.auto desc, a.origin, a.created_at), '[]') into v_adj
    from erp.corporate_tax_adjustments a where a.return_id = v_ret.id;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id', null, 'origin', x.origin, 'source_id', x.source_id, 'kind', x.kind,
             'direction', x.direction, 'concept', x.concept, 'amount', x.amount, 'article', x.article, 'included', x.included,
             'auto', true)), '[]') into v_adj
    from erp.corporate_tax_proposals(p_company, p_year) x;
  end if;

  v_result := erp.pre_tax_result(p_company, v_fy.id);
  select coalesce(sum(case x->>'direction' when 'increase' then 1 else -1 end * (x->>'amount')::numeric) filter (where x->>'kind' = 'permanent'), 0),
         coalesce(sum((x->>'amount')::numeric) filter (where x->>'kind' = 'temporary' and x->>'direction' = 'increase'), 0),
         coalesce(sum((x->>'amount')::numeric) filter (where x->>'kind' = 'temporary' and x->>'direction' = 'decrease'), 0)
    into v_perm, v_tinc, v_tdec
  from jsonb_array_elements(v_adj) x where (x->>'included')::boolean;
  v_prev := v_result + v_perm + v_tinc - v_tdec;

  -- compensación de bases negativas (art. 26.1): hasta el 70 % de la base previa, y en todo caso 1 millón
  select coalesce(sum(pending), 0) into v_avail from erp.corporate_tax_loss_carryforwards(p_company, p_year);
  v_limit := case when v_prev > 0 then greatest(round(v_prev * 0.70, 2), least(v_prev, 1000000)) else 0 end;
  v_left := least(v_avail, v_limit, greatest(v_prev, 0));
  for b in select * from erp.corporate_tax_loss_carryforwards(p_company, p_year) loop
    exit when v_left <= 0;
    v_usage := v_usage || jsonb_build_object('origin_year', b.origin_year, 'amount', least(b.pending, v_left));
    if b.credit_rate is not null then v_credit_used := v_credit_used + round(least(b.pending, v_left) * b.credit_rate / 100, 2); end if;
    v_comp := v_comp + least(b.pending, v_left);
    v_left := v_left - least(b.pending, v_left);
  end loop;
  v_base := v_prev - v_comp;

  v_q := erp.corporate_tax_quota(p_year, v_regime, greatest(v_base, 0));
  v_quota := (v_q->>'quota')::numeric;
  v_rate := (v_q->>'marginal_rate')::numeric;
  -- retenciones y pagos fraccionados: saldo deudor de la 473 al cierre
  select coalesce(sum(l.debit - l.credit), 0) into v_wh
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
    and e.entry_type not in ('closing_pl', 'closing') and g.account_no like '473%';
  v_diff := v_quota - v_wh;

  -- impuesto diferido (NRV 13.ª): diferencias temporarias × tipo; bases negativas, solo si se registra el crédito
  v_loss := greatest(-v_prev, 0);
  v_credit := case when v_recognize then round(v_loss * v_rate / 100, 2) else 0 end;
  v_def := round(v_tdec * v_rate / 100, 2) - round(v_tinc * v_rate / 100, 2) - v_credit + v_credit_used;

  if v_regime <> v_hint->>'suggested' and not (v_regime = 'new_entity')
     and not (v_regime = 'erd' and v_hint->>'suggested' = 'micro') then
    v_warn := v_warn || jsonb_build_object('code', 'regime_mismatch', 'suggested', v_hint->>'suggested', 'turnover', v_hint->'turnover');
  end if;
  if v_regime in ('micro', 'erd') and not (v_hint->>'is_erd')::boolean then
    v_warn := v_warn || jsonb_build_object('code', 'regime_not_allowed', 'turnover', v_hint->'turnover');
  end if;
  if v_wh < 0 then v_warn := v_warn || jsonb_build_object('code', 'withholdings_credit_balance', 'amount', v_wh); end if;
  if v_loss > 0 and not v_recognize then v_warn := v_warn || jsonb_build_object('code', 'loss_credit_not_recognized', 'amount', v_loss); end if;

  return jsonb_build_object(
    'status', coalesce(v_ret.status, 'none'), 'return_id', v_ret.id, 'year', p_year, 'regime', v_regime,
    'recognize_loss_credit', v_recognize, 'hint', v_hint,
    'pre_tax_result', v_result, 'adjustments', v_adj,
    'permanent', v_perm, 'temporary_increase', v_tinc, 'temporary_decrease', v_tdec,
    'base_before_losses', v_prev, 'losses_available', v_avail, 'losses_limit', v_limit,
    'losses_compensated', v_comp, 'loss_usage', v_usage, 'taxable_base', v_base,
    'quota', v_quota, 'brackets', v_q->'brackets', 'rates_year', v_q->'rates_year',
    'withholdings', v_wh, 'differential', v_diff,
    'outcome', case when v_diff > 0 then 'pay' when v_diff < 0 then 'refund' else 'zero' end,
    'deferred_rate', v_rate, 'loss_generated', v_loss, 'loss_credit', v_credit, 'loss_credit_used', v_credit_used,
    'current_tax', v_quota, 'deferred_tax', v_def, 'tax_expense', v_quota + v_def,
    'net_result', v_result - v_quota - v_def, 'warnings', v_warn);
end $$;

-- 7) Preparar la declaración (borrador): crea o pone al día los ajustes propuestos, sin tocar los que el usuario ha
--    quitado (included) ni los manuales
create or replace function erp.corporate_tax_prepare(p_company uuid, p_year int)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v_fy erp.fiscal_years; v_ret erp.corporate_tax_returns;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to prepare the corporate tax of this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', p_year; end if;
  select * into v_ret from erp.corporate_tax_returns where fiscal_year_id = v_fy.id;
  if v_ret.status = 'posted' then raise exception 'The corporate tax of % is already posted: cancel it first', p_year; end if;
  if v_ret.id is null then
    insert into erp.corporate_tax_returns (company_id, fiscal_year_id, regime)
    values (p_company, v_fy.id, erp.corporate_tax_regime_hint(p_company, p_year)->>'suggested') returning * into v_ret;
  end if;
  -- quitar los propuestos que ya no salen; poner al día los demás; añadir los nuevos
  delete from erp.corporate_tax_adjustments a where a.return_id = v_ret.id and a.auto
    and not exists (select 1 from erp.corporate_tax_proposals(p_company, p_year) x
                    where x.origin = a.origin and x.source_id = a.source_id and x.direction = a.direction);
  update erp.corporate_tax_adjustments a set kind = x.kind, concept = x.concept, amount = x.amount, article = x.article
  from erp.corporate_tax_proposals(p_company, p_year) x
  where a.return_id = v_ret.id and a.auto and x.origin = a.origin and x.source_id = a.source_id and x.direction = a.direction;
  insert into erp.corporate_tax_adjustments (return_id, company_id, origin, source_id, kind, direction, concept, amount, article, included, auto)
  select v_ret.id, p_company, x.origin, x.source_id, x.kind, x.direction, x.concept, x.amount, x.article, x.included, true
  from erp.corporate_tax_proposals(p_company, p_year) x
  where not exists (select 1 from erp.corporate_tax_adjustments a where a.return_id = v_ret.id and a.auto
                    and a.origin = x.origin and a.source_id = x.source_id and a.direction = x.direction);
  return v_ret.id;
end $$;

-- 8) Cambios del usuario en el borrador
create or replace function erp.corporate_tax_draft(p_return uuid)
returns erp.corporate_tax_returns language plpgsql security definer set search_path = erp, public as $$
declare r erp.corporate_tax_returns;
begin
  select * into r from erp.corporate_tax_returns where id = p_return;
  if not found then raise exception 'Corporate tax return not found'; end if;
  if not erp.can_write(r.company_id) then raise exception 'No permission to change the corporate tax of this company'; end if;
  if r.status <> 'draft' then raise exception 'The corporate tax is already posted: cancel it first'; end if;
  return r;
end $$;

create or replace function erp.corporate_tax_settings(p_return uuid, p_regime text, p_recognize boolean)
returns void language plpgsql security definer set search_path = erp, public as $$
begin
  perform erp.corporate_tax_draft(p_return);
  update erp.corporate_tax_returns set regime = p_regime, recognize_loss_credit = coalesce(p_recognize, false) where id = p_return;
end $$;

create or replace function erp.corporate_tax_include(p_adjustment uuid, p_included boolean)
returns void language plpgsql security definer set search_path = erp, public as $$
declare a erp.corporate_tax_adjustments;
begin
  select * into a from erp.corporate_tax_adjustments where id = p_adjustment;
  if not found then raise exception 'Adjustment not found'; end if;
  perform erp.corporate_tax_draft(a.return_id);
  update erp.corporate_tax_adjustments set included = p_included where id = p_adjustment;
end $$;

-- Ajuste manual: { return_id, id?, kind, direction, concept, amount, article? } · con delete = true, se borra
create or replace function erp.corporate_tax_manual(p jsonb)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare r erp.corporate_tax_returns; v_id uuid := nullif(p->>'id', '')::uuid; a erp.corporate_tax_adjustments;
begin
  if v_id is not null then
    select * into a from erp.corporate_tax_adjustments where id = v_id;
    if not found or a.auto then raise exception 'Only manual adjustments can be edited'; end if;
    r := erp.corporate_tax_draft(a.return_id);
    if coalesce((p->>'delete')::boolean, false) then delete from erp.corporate_tax_adjustments where id = v_id; return null; end if;
    update erp.corporate_tax_adjustments set kind = p->>'kind', direction = p->>'direction', concept = btrim(p->>'concept'),
      amount = (p->>'amount')::numeric, article = nullif(btrim(p->>'article'), '') where id = v_id;
    return v_id;
  end if;
  r := erp.corporate_tax_draft((p->>'return_id')::uuid);
  insert into erp.corporate_tax_adjustments (return_id, company_id, origin, kind, direction, concept, amount, article, included, auto)
  values (r.id, r.company_id, 'manual', p->>'kind', p->>'direction', btrim(p->>'concept'), (p->>'amount')::numeric,
          nullif(btrim(p->>'article'), ''), true, false)
  returning id into v_id;
  return v_id;
end $$;

-- Las funciones que escriben son security definer y comprueban can_write: no hay escritura directa en las tablas

revoke execute on function erp.net_turnover(uuid, uuid), erp.pre_tax_result(uuid, uuid), erp.corporate_tax_regime_hint(uuid, int),
  erp.corporate_tax_quota(int, text, numeric), erp.corporate_tax_pending(uuid, text, uuid, int), erp.corporate_tax_proposals(uuid, int),
  erp.corporate_tax_loss_carryforwards(uuid, int), erp.corporate_tax_calc(uuid, int, text, boolean), erp.corporate_tax_prepare(uuid, int),
  erp.corporate_tax_draft(uuid), erp.corporate_tax_settings(uuid, text, boolean), erp.corporate_tax_include(uuid, boolean),
  erp.corporate_tax_manual(jsonb) from anon, public;
grant execute on function erp.net_turnover(uuid, uuid), erp.pre_tax_result(uuid, uuid), erp.corporate_tax_regime_hint(uuid, int),
  erp.corporate_tax_quota(int, text, numeric), erp.corporate_tax_pending(uuid, text, uuid, int), erp.corporate_tax_proposals(uuid, int),
  erp.corporate_tax_loss_carryforwards(uuid, int), erp.corporate_tax_calc(uuid, int, text, boolean), erp.corporate_tax_prepare(uuid, int),
  erp.corporate_tax_draft(uuid), erp.corporate_tax_settings(uuid, text, boolean), erp.corporate_tax_include(uuid, boolean),
  erp.corporate_tax_manual(jsonb) to authenticated;
