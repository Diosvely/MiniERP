-- =====================================================================
-- 0075 · Tableros: catálogo de métricas, tableros y tarjetas (v0.52.0 · ADR 0052)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.52.0.md): «las reglas en la base de datos y el tablero en la web».
--
--   · CATÁLOGO: tres tablas de solo lectura para la web. Una métrica, un tablero o una tarjeta son filas: un tablero
--     nuevo no exige tocar el código de la web (y más adelante la IA podrá proponerlos a partir del catálogo).
--   · LAS MÉTRICAS NO REPITEN REGLAS: una métrica es una partida del Balance o de la PyG (erp.fs_amounts), la suma de
--     un grupo de cuentas de la PyG (erp.fs_classified_accounts) o una suma, resta o cociente de otras métricas.
--     Así cuadran al céntimo con el Balance y la PyG, también en la simulación con los asientos en edición (0074).
--   · erp.dashboard_data(empresa, tablero, año, hasta, p_drafts): todo lo que dibuja la web en una sola llamada:
--     cada cifra a la fecha y a la misma fecha del año anterior, y las series a cada fin de mes de los dos ejercicios.
--   · Primer tablero: «Resumen de dirección».
--
-- Se puede ejecutar dos veces.
-- =====================================================================

-- ---------- Catálogo ----------
create table if not exists erp.dash_metrics (
  code           text primary key,
  sort           int  not null,                 -- orden de cálculo: una métrica usa solo métricas de orden menor
  label          text not null,
  label_en       text not null,
  unit           text not null check (unit in ('eur', 'pct', 'ratio')),
  kind           text not null check (kind in ('line', 'group', 'sum', 'diff', 'ratio')),
  statement      text check (statement in ('balance', 'pyg')),   -- kind line: la partida
  line_code      text,
  account_prefix text,                          -- kind group: el grupo de cuentas de la PyG (6, 7…)
  sign           int  check (sign in (1, -1)),  -- kind group: 1 = saldo deudor positivo (gastos); -1 = acreedor (ingresos)
  a              text references erp.dash_metrics(code),   -- kind sum, diff, ratio: a + b, a − b, a / b
  b              text references erp.dash_metrics(code),
  ratio_code     text references erp.ratio_defs(code),     -- zona de referencia: la del ratio del ERP
  link           text,                          -- pantalla de la empresa que la explica (pyg, balance, ratios…)
  help           text,
  help_en        text,
  check ((kind = 'line'  and statement is not null and line_code is not null)
      or (kind = 'group' and account_prefix is not null and sign is not null)
      or (kind in ('sum', 'diff', 'ratio') and a is not null and b is not null))
);

-- índices de las claves foráneas (la prueba de rendimiento lo exige a todas)
create index if not exists dash_metrics_a on erp.dash_metrics (a);
create index if not exists dash_metrics_b on erp.dash_metrics (b);
create index if not exists dash_metrics_ratio on erp.dash_metrics (ratio_code);

create table if not exists erp.dashboards (
  code           text primary key,
  sort           int  not null,
  label          text not null,
  label_en       text not null,
  description    text,
  description_en text
);

create table if not exists erp.dash_widgets (
  dashboard      text not null references erp.dashboards(code) on delete cascade,
  sort           int  not null,
  kind           text not null check (kind in ('kpis', 'bars', 'lines', 'table')),
  size           text not null default 'full' check (size in ('full', 'half')),
  mode           text not null default 'end' check (mode in ('end', 'month')),   -- series: a fin de mes o lo de cada mes
  label          text not null,
  label_en       text not null,
  help           text,
  help_en        text,
  metrics        text[] not null,
  primary key (dashboard, sort)
);

alter table erp.dash_metrics enable row level security;
alter table erp.dashboards   enable row level security;
alter table erp.dash_widgets enable row level security;
drop policy if exists read on erp.dash_metrics;
drop policy if exists read on erp.dashboards;
drop policy if exists read on erp.dash_widgets;
create policy read on erp.dash_metrics for select to authenticated using (true);
create policy read on erp.dashboards   for select to authenticated using (true);
create policy read on erp.dash_widgets for select to authenticated using (true);
revoke all on erp.dash_metrics, erp.dashboards, erp.dash_widgets from anon, public, authenticated;
grant select on erp.dash_metrics, erp.dashboards, erp.dash_widgets to authenticated;

-- ---------- Métricas ----------
insert into erp.dash_metrics (code, sort, label, label_en, unit, kind, statement, line_code, account_prefix, sign, a, b, ratio_code, link, help, help_en) values
 ('SALES',    10, 'Cifra de negocios', 'Revenue', 'eur', 'line', 'pyg', 'P1', null, null, null, null, null, 'pyg',
  'Ventas y prestaciones de servicios del ejercicio hasta la fecha (partida 1 de la PyG).',
  'Sales and services of the year to date (line 1 of the income statement).'),
 ('RESULT',   20, 'Resultado del ejercicio', 'Profit for the year', 'eur', 'line', 'pyg', 'PD', null, null, null, null, null, 'pyg',
  'Beneficio (o pérdida) del ejercicio hasta la fecha, después de impuestos.',
  'Profit (or loss) of the year to date, after tax.'),
 ('INCOME',   30, 'Ingresos', 'Income', 'eur', 'group', null, null, '7', -1, null, null, null, 'pyg',
  'Todo lo del grupo 7 (ventas, subvenciones, ingresos financieros…).', 'Everything in group 7 (sales, grants, finance income…).'),
 ('EXPENSES', 40, 'Gastos', 'Expenses', 'eur', 'group', null, null, '6', 1, null, null, null, 'pyg',
  'Todo lo del grupo 6 (compras, personal, amortizaciones, impuesto…).', 'Everything in group 6 (purchases, staff, depreciation, tax…).'),
 ('CASH',     50, 'Tesorería', 'Cash', 'eur', 'line', 'balance', 'AC.VI', null, null, null, null, null, 'balance',
  'Efectivo y otros activos líquidos equivalentes (cuentas 57) a la fecha.', 'Cash and cash equivalents (accounts 57) at the date.'),
 ('CA',       60, 'Activo corriente', 'Current assets', 'eur', 'line', 'balance', 'AC', null, null, null, null, null, 'balance', null, null),
 ('CL',       70, 'Pasivo corriente', 'Current liabilities', 'eur', 'line', 'balance', 'PC', null, null, null, null, null, 'balance', null, null),
 ('NCL',      80, 'Pasivo no corriente', 'Non-current liabilities', 'eur', 'line', 'balance', 'PNC', null, null, null, null, null, 'balance', null, null),
 ('TOTAL',    90, 'Patrimonio neto y pasivo', 'Total equity and liabilities', 'eur', 'line', 'balance', 'PNP', null, null, null, null, null, 'balance', null, null),
 ('LIAB',    100, 'Pasivo', 'Liabilities', 'eur', 'sum', null, null, null, null, 'NCL', 'CL', null, 'balance', null, null),
 ('WC',      110, 'Fondo de maniobra', 'Working capital', 'eur', 'diff', null, null, null, null, 'CA', 'CL', 'WC', 'ratios',
  'Activo corriente − pasivo corriente: lo que queda del corto plazo para trabajar.', 'Current assets − current liabilities.'),
 ('CR',      120, 'Liquidez general', 'Current ratio', 'ratio', 'ratio', null, null, null, null, 'CA', 'CL', 'CR', 'ratios',
  'Activo corriente / pasivo corriente: cuántas veces se cubren las deudas a corto.', 'Current assets / current liabilities.'),
 ('DEBT',    130, 'Endeudamiento', 'Debt ratio', 'ratio', 'ratio', null, null, null, null, 'LIAB', 'TOTAL', 'DEBT', 'ratios',
  'Pasivo / (patrimonio neto + pasivo): qué parte se financia con deudas.', 'Liabilities / (equity + liabilities).'),
 ('NPM',     140, 'Margen neto', 'Net margin', 'pct', 'ratio', null, null, null, null, 'RESULT', 'SALES', 'NPM', 'ratios',
  'Resultado / cifra de negocios: lo que queda de cada euro vendido.', 'Profit / revenue: what is left of each euro sold.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en, unit = excluded.unit,
  kind = excluded.kind, statement = excluded.statement, line_code = excluded.line_code, account_prefix = excluded.account_prefix,
  sign = excluded.sign, a = excluded.a, b = excluded.b, ratio_code = excluded.ratio_code, link = excluded.link,
  help = excluded.help, help_en = excluded.help_en;

-- ---------- El tablero «Resumen de dirección» ----------
insert into erp.dashboards (code, sort, label, label_en, description, description_en) values
 ('resumen', 10, 'Resumen de dirección', 'Management summary',
  'Las cifras que mira primero la dirección: ventas, resultado, tesorería y salud financiera, frente al año anterior.',
  'The figures management looks at first: sales, profit, cash and financial health, against the previous year.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en,
  description = excluded.description, description_en = excluded.description_en;

delete from erp.dash_widgets where dashboard = 'resumen';
insert into erp.dash_widgets (dashboard, sort, kind, size, mode, label, label_en, help, help_en, metrics) values
 ('resumen', 10, 'kpis',  'full', 'end',   'Cifras clave', 'Key figures', null, null, array['SALES', 'RESULT', 'CASH', 'WC']),
 ('resumen', 20, 'bars',  'full', 'month', 'Ingresos y gastos de cada mes', 'Income and expenses by month',
  'Lo que entra y sale en el resultado cada mes (grupos 7 y 6), sin regularización ni cierre.',
  'What goes in and out of profit each month (groups 7 and 6), without closing entries.', array['INCOME', 'EXPENSES']),
 ('resumen', 30, 'lines', 'half', 'end',   'Resultado acumulado', 'Cumulative profit',
  'El resultado del ejercicio a cada fin de mes, frente al año anterior.', 'Profit of the year at each month end, against last year.',
  array['RESULT']),
 ('resumen', 40, 'lines', 'half', 'end',   'Tesorería a fin de mes', 'Cash at month end',
  'El saldo de las cuentas 57 a cada fin de mes, frente al año anterior.', 'Accounts 57 at each month end, against last year.',
  array['CASH']),
 ('resumen', 50, 'table', 'full', 'end',   'Salud financiera', 'Financial health',
  'Con la zona de referencia de los Ratios.', 'With the reference range of the Ratios screen.', array['CR', 'DEBT', 'NPM']);

-- ---------- Cálculo ----------
-- LA MISMA REGLA, PARA VARIAS FECHAS EN UNA PASADA. Un tablero necesita el balance y la PyG a 26 fechas (cada fin de
-- mes de dos ejercicios y la fecha elegida); llamar 26 veces a erp.fs_classified_accounts recorre el diario 26 veces
-- (18 s con 60.000 asientos). erp.fs_classified_at suma el diario UNA vez por cuenta y día y saca el saldo a cada
-- fecha. erp.fs_classified_accounts y erp.fs_amounts pasan a ser el caso de una sola fecha: la regla sigue en un sitio.
--   p_dates: las fechas de corte (null = el ejercicio entero)
create or replace function erp.fs_classified_at(p_company uuid, p_year integer, p_statement text, p_dates date[])
 returns table(at date, account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
 language sql stable
as $function$
  with mov as (
    select g.account_no, g.name, g.name_en, e.posting_date, sum(l.debit - l.credit) as amt
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and erp.counts_in_reports(e.status, e.id)
                              and e.entry_type not in ('closing_pl', 'closing')
    join erp.fiscal_years fy   on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g     on g.id = l.gl_account_id
    where e.company_id = p_company
      and (p_statement = 'balance' or left(g.account_no, 1) in ('6', '7'))
    group by g.account_no, g.name, g.name_en, e.posting_date
  ), acc as (
    select d.at, m.account_no, m.name, m.name_en, sum(m.amt) as bal
    from (select distinct x as at from unnest(p_dates) x) d
    join mov m on d.at is null or m.posting_date <= d.at
    group by d.at, m.account_no, m.name, m.name_en
    having sum(m.amt) <> 0
  )
  select a.at, a.account_no, a.name, a.name_en, a.bal,
         m.line,
         a.bal * case fl.side when 'debit' then 1 else -1 end
  from acc a
  cross join lateral (
    select case when a.bal >= 0 then fm.debit_line else fm.credit_line end as line
    from erp.fs_mapping fm
    where fm.statement = p_statement and a.account_no like fm.prefix || '%'
    order by length(fm.prefix) desc limit 1) m
  join erp.fs_lines fl on fl.statement = p_statement and fl.code = m.line;
$function$;

-- Cada partida (con sus totales) a cada fecha
create or replace function erp.fs_amounts_at(p_company uuid, p_year integer, p_statement text, p_dates date[])
 returns table(at date, code text, amount numeric)
 language sql stable
as $function$
  with recursive up(code, ancestor) as (
    select l.code, l.code from erp.fs_lines l where l.statement = p_statement
    union all
    select up.code, p.parent
    from up join erp.fs_lines p on p.statement = p_statement and p.code = up.ancestor
    where p.parent is not null
  ), detail as (
    select c.at, c.line_code, sum(c.amount) as amount
    from erp.fs_classified_at(p_company, p_year, p_statement, p_dates) c
    group by c.at, c.line_code
  ), dates as (select distinct x as at from unnest(p_dates) x)
  select dt.at, up.ancestor, coalesce(sum(d.amount), 0)
  from dates dt cross join up
  left join detail d on d.line_code = up.code and d.at is not distinct from dt.at
  group by dt.at, up.ancestor;
$function$;

-- Las de siempre, ahora el caso de una fecha (misma firma, mismo resultado)
create or replace function erp.fs_classified_accounts(p_company uuid, p_year integer, p_statement text, p_to_date date default null::date)
 returns table(account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
 language sql stable
as $function$
  select c.account_no, c.account_name, c.account_name_en, c.balance, c.line_code, c.amount
  from erp.fs_classified_at(p_company, p_year, p_statement, array[p_to_date]) c;
$function$;

create or replace function erp.fs_amounts(p_company uuid, p_year integer, p_statement text, p_to_date date default null::date)
 returns table(code text, amount numeric)
 language sql stable
as $function$
  select a.code, a.amount from erp.fs_amounts_at(p_company, p_year, p_statement, array[p_to_date]) a;
$function$;

-- Todas las métricas de una empresa a varias fechas del ejercicio → una fila por fecha con { código: valor }
-- (null si no se puede calcular: ÷ 0). La llama erp.dashboard_data, que comprueba antes que se puede leer la empresa.
create or replace function erp.dash_metric_values(p_company uuid, p_year integer, p_dates date[])
returns table(at date, v jsonb) language plpgsql stable as $$
#variable_conflict use_column
declare
  bal jsonb; pyg jsonb; grp jsonb; vals jsonb; m erp.dash_metrics; x numeric; va numeric; vb numeric; d date;
begin
  -- { fecha: { partida: importe } } del Balance y de la PyG, y { fecha: { cuenta: saldo } } de la PyG (los grupos)
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into bal
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'balance', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into pyg
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'pyg', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into grp
  from (select c.at, jsonb_object_agg(c.account_no, c.balance) m from erp.fs_classified_at(p_company, p_year, 'pyg', p_dates) c group by c.at) z;

  foreach d in array (select array_agg(distinct x) from unnest(p_dates) x) loop
    vals := '{}';
    for m in select * from erp.dash_metrics order by sort loop
      if m.kind = 'line' then
        x := coalesce(((case m.statement when 'balance' then bal else pyg end) -> coalesce(d::text, '-') ->> m.line_code)::numeric, 0);
      elsif m.kind = 'group' then
        select m.sign * coalesce(sum(e.value::numeric), 0) into x
        from jsonb_each_text(coalesce(grp -> coalesce(d::text, '-'), '{}')) e where e.key like m.account_prefix || '%';
      else
        va := (vals ->> m.a)::numeric; vb := (vals ->> m.b)::numeric;
        x := case m.kind when 'sum' then va + vb when 'diff' then va - vb
                         else case when vb is null or vb = 0 then null else round(va / vb, 4) end end;
      end if;
      vals := vals || jsonb_build_object(m.code, x);
    end loop;
    at := d; v := vals; return next;
  end loop;
end $$;

-- Los fines de mes de un ejercicio (12 en un ejercicio natural)
create or replace function erp.dash_month_ends(p_start date, p_end date)
returns date[] language sql immutable as $$
  select coalesce(array_agg(d order by d), '{}')
  from (select (date_trunc('month', g) + interval '1 month - 1 day')::date as d
        from generate_series(date_trunc('month', p_start), date_trunc('month', p_end), interval '1 month') g) x;
$$;

-- TODO lo que dibuja la web de un tablero, en una llamada
--   p_to_date: «hasta» (null = el ejercicio entero) · p_drafts: simulación con los asientos en edición (0074)
create or replace function erp.dashboard_data(p_company uuid, p_dashboard text, p_year integer,
                                              p_to_date date default null, p_drafts boolean default false)
returns jsonb language plpgsql stable as $$
declare
  v_prev_sim text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
  d erp.dashboards; fy erp.fiscal_years; fy0 erp.fiscal_years;
  v_to date; v_prev_to date; ends date[]; ends0 date[] := '{}';
  cur jsonb; prev jsonb; s_cur jsonb := '[]'; s_prev jsonb := '[]'; widgets jsonb; e date; i int;
  need_series boolean; vals jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into d from erp.dashboards where code = p_dashboard;
  if d.code is null then raise exception 'Unknown dashboard: %', p_dashboard; end if;
  select * into fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if fy.id is null then raise exception 'No fiscal year %', p_year; end if;
  select * into fy0 from erp.fiscal_years where company_id = p_company and year = p_year - 1;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;

  v_to := least(coalesce(p_to_date, fy.ending_date), fy.ending_date);
  v_prev_to := (v_to - interval '1 year')::date;            -- la misma fecha del año anterior (29/02 → 28/02)
  -- Las series, solo si el tablero tiene gráficos: cada fin de mes hasta la fecha (este año) y el año anterior entero.
  -- Todas las fechas de un ejercicio se calculan juntas (una pasada por el diario).
  need_series := exists (select 1 from erp.dash_widgets w where w.dashboard = p_dashboard and w.kind in ('bars', 'lines'));
  ends := erp.dash_month_ends(fy.starting_date, fy.ending_date);
  if fy0.id is not null then ends0 := erp.dash_month_ends(fy0.starting_date, fy0.ending_date); end if;
  select jsonb_object_agg(x.at::text, x.v) into vals
  from erp.dash_metric_values(p_company, p_year,
         array[v_to] || case when need_series then array(select e2 from unnest(ends) e2 where e2 <= v_to) else '{}'::date[] end) x;
  cur := vals -> v_to::text;
  if need_series then
    foreach e in array ends loop s_cur := s_cur || jsonb_build_array(vals -> e::text); end loop;   -- después de «hasta»: null
  end if;
  if fy0.id is not null then
    select jsonb_object_agg(x.at::text, x.v) into vals
    from erp.dash_metric_values(p_company, p_year - 1, array[v_prev_to] || case when need_series then ends0 else '{}'::date[] end) x;
    prev := vals -> v_prev_to::text;
    if need_series then
      foreach e in array ends0 loop s_prev := s_prev || jsonb_build_array(vals -> e::text); end loop;
    end if;
  end if;

  -- Cada tarjeta con sus métricas: valor, año anterior, zona de referencia y las series ya preparadas
  -- (mode month: lo de cada mes = acumulado del mes − acumulado del mes anterior)
  select coalesce(jsonb_agg(jsonb_build_object(
           'sort', w.sort, 'kind', w.kind, 'size', w.size, 'mode', w.mode, 'label', w.label, 'label_en', w.label_en,
           'help', w.help, 'help_en', w.help_en,
           'items', (select jsonb_agg(jsonb_build_object(
               'code', m.code, 'label', m.label, 'label_en', m.label_en, 'unit', m.unit, 'link', m.link,
               'help', m.help, 'help_en', m.help_en, 'ref_min', r.ref_min, 'ref_max', r.ref_max,
               'value', cur -> m.code, 'prev', prev -> m.code,
               'series', case when w.kind in ('bars', 'lines') then (
                  select jsonb_agg(case when s.v is null or s.v = 'null'::jsonb then null
                                        when w.mode = 'month' then to_jsonb((s.v ->> m.code)::numeric
                                             - case when s.n = 1 then 0 else coalesce((s_cur -> (s.n::int - 2) ->> m.code)::numeric, 0) end)
                                        else s.v -> m.code end order by s.n)
                  from jsonb_array_elements(s_cur) with ordinality s(v, n)) end,
               'series_prev', case when w.kind in ('bars', 'lines') and fy0.id is not null then (
                  select jsonb_agg(case when w.mode = 'month' then to_jsonb((s.v ->> m.code)::numeric
                                             - case when s.n = 1 then 0 else coalesce((s_prev -> (s.n::int - 2) ->> m.code)::numeric, 0) end)
                                        else s.v -> m.code end order by s.n)
                  from jsonb_array_elements(s_prev) with ordinality s(v, n)) end)
               order by k.n)
             from unnest(w.metrics) with ordinality k(code, n)
             join erp.dash_metrics m on m.code = k.code
             left join erp.ratio_defs r on r.code = m.ratio_code))
         order by w.sort), '[]')
    into widgets
  from erp.dash_widgets w where w.dashboard = p_dashboard;

  perform set_config('erp.simulate', v_prev_sim, true);
  return jsonb_build_object(
    'code', d.code, 'label', d.label, 'label_en', d.label_en, 'description', d.description, 'description_en', d.description_en,
    'year', p_year, 'to', v_to, 'prev_to', case when fy0.id is not null then v_prev_to end, 'has_prev', fy0.id is not null,
    'simulation', p_drafts, 'months', to_jsonb(ends), 'months_prev', to_jsonb(ends0), 'widgets', widgets);
end $$;

revoke execute on function erp.dash_metric_values(uuid, integer, date[]), erp.dash_month_ends(date, date),
  erp.fs_classified_at(uuid, integer, text, date[]), erp.fs_amounts_at(uuid, integer, text, date[]),
  erp.dashboard_data(uuid, text, integer, date, boolean) from anon, public;
grant execute on function erp.dash_month_ends(date, date), erp.dashboard_data(uuid, text, integer, date, boolean) to authenticated;
-- dash_metric_values la usa dashboard_data con los permisos del usuario (RLS): también hace falta poder ejecutarla
grant execute on function erp.dash_metric_values(uuid, integer, date[]), erp.fs_classified_at(uuid, integer, text, date[]),
  erp.fs_amounts_at(uuid, integer, text, date[]) to authenticated;

notify pgrst, 'reload schema';
