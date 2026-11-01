-- =====================================================================
-- 0083 · Tablero «Ventas y gastos» (v0.56.0 · ADR 0056)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.56.0.md, 01-11-2026): el volumen sin impuestos desde los asientos, las
-- inversiones (grupo 2) en el ranking de proveedores y los 10 primeros con el «Resto».
--
--   · TIPO DE TARJETA «ranking» (fuente y cuántos enseña): los terceros o los subgrupos ordenados por importe, con el
--     año anterior a la misma fecha, el «Resto» y lo que no tiene tercero.
--   · DESDE LA CONTABILIDAD, POR SUBCUENTA: las empresas importadas no tienen facturas, pero sí una subcuenta por tercero.
--       - customers: lo abonado en las cuentas de la cifra de negocios (700 a 709, las de la partida 1 de la PyG) en
--         los asientos que mueven la subcuenta del cliente (43, 44). Sin impuestos; una rectificativa resta; un cobro no
--         cuenta (no toca la 70). Su total, con «Sin cliente», es la cifra de negocios.
--       - suppliers: lo cargado en los grupos 6 y 2 en los asientos que mueven la subcuenta del proveedor (40, 41).
--       - expense_groups: los subgrupos del grupo 6 de la PyG (60 Compras, 62 Servicios exteriores…), con el nombre del
--         PGC. Su total es el grupo 6.
--     Un asiento con varios terceros se reparte en proporción a lo que mueve cada uno. Sin apertura ni cierre, y con la
--     regla de qué cuenta en un informe (simulación incluida).
--
-- Se puede ejecutar dos veces.
-- =====================================================================

-- ---------- Catálogo: la tarjeta de ranking ----------
alter table erp.dash_widgets add column if not exists source text;
alter table erp.dash_widgets add column if not exists top_n int not null default 10;
comment on column erp.dash_widgets.source is 'kind ranking: customers, suppliers o expense_groups.';
comment on column erp.dash_widgets.top_n is 'kind ranking: cuántos enseña (el resto, en una fila «Resto»).';
alter table erp.dash_widgets drop constraint if exists dash_widgets_kind_check;
alter table erp.dash_widgets add constraint dash_widgets_kind_check check (kind in ('kpis', 'bars', 'lines', 'table', 'ranking'));
alter table erp.dash_widgets drop constraint if exists dash_widgets_source_check;
alter table erp.dash_widgets add constraint dash_widgets_source_check
  check ((kind = 'ranking') = (source is not null)
         and (source is null or source in ('customers', 'suppliers', 'expense_groups'))
         and top_n between 1 and 50);

-- ---------- El importe de cada tercero o subgrupo, a una fecha ----------
--   key null = sin tercero («Sin cliente», «Sin proveedor»)
create or replace function erp.dash_ranking(p_company uuid, p_year integer, p_to date, p_source text)
returns table(key text, label text, amount numeric)
language sql stable security definer set search_path = erp, public as $$
  with ent as (
    select e.id
    from erp.journal_entries e
    where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
      and e.company_id = p_company and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
      and (p_to is null or e.posting_date <= p_to)
      and p_source in ('customers', 'suppliers') and erp.can_report(p_company)
    offset 0
  ), lin as (
    select l.entry_id, g.account_no, g.name, l.debit - l.credit as net
    from ent e
    join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company
    join erp.gl_accounts g on g.id = l.gl_account_id
  ), party as (
    -- lo que mueve cada tercero en el asiento (para repartir si hay varios)
    select entry_id, account_no, name, abs(sum(net)) as w
    from lin
    where case p_source when 'customers' then left(account_no, 2) in ('43', '44') else left(account_no, 2) in ('40', '41') end
    group by entry_id, account_no, name
    having sum(net) <> 0
  ), amt as (
    -- ventas: abonos − cargos de las cuentas de la cifra de negocios · compras: cargos − abonos de los grupos 6 y 2
    select entry_id,
           sum(case p_source when 'customers' then -net else net end) as a
    from lin
    where case p_source when 'customers' then left(account_no, 3) in ('700', '701', '702', '703', '704', '705', '706', '708', '709')
                        else left(account_no, 1) in ('6', '2') end
    group by entry_id
    having sum(net) <> 0
  ), alloc as (
    select p.account_no as key, p.name as label, a.a * p.w / sum(p.w) over (partition by p.entry_id) as v
    from amt a join party p on p.entry_id = a.entry_id
    union all
    select null, null, a.a from amt a where not exists (select 1 from party p where p.entry_id = a.entry_id)
  )
  select key, max(label), round(sum(v), 2) from alloc group by key having round(sum(v), 2) <> 0
  union all
  -- gastos por naturaleza: los subgrupos del grupo 6 de la PyG, con el nombre del PGC
  select s.key, coalesce(sg.name, s.key), s.amount
  from (select left(c.account_no, 2) as key, sum(c.balance) as amount
        from erp.fs_classified_at(p_company, p_year, 'pyg', array[p_to]) c
        where p_source = 'expense_groups' and c.account_no like '6%'
        group by left(c.account_no, 2) having sum(c.balance) <> 0) s
  left join erp.pgc_subgroups sg on sg.subgroup = s.key;
$$;
revoke execute on function erp.dash_ranking(uuid, integer, date, text) from anon, public;
grant execute on function erp.dash_ranking(uuid, integer, date, text) to authenticated;

-- ---------- La tarjeta entera: los N primeros, el resto, lo que no tiene tercero y el total ----------
--   base: sobre qué se calcula el %: el total del ranking (clientes y proveedores) o las ventas (gastos por naturaleza)
create or replace function erp.dash_ranking_card(p_company uuid, p_year integer, p_to date, p_prev_to date, p_has_prev boolean,
                                                 p_source text, p_top int, p_sales numeric, p_sales_prev numeric)
returns jsonb language sql stable as $$
  with cur as (select * from erp.dash_ranking(p_company, p_year, p_to, p_source)),
       prv as (select * from erp.dash_ranking(p_company, p_year - 1, p_prev_to, p_source) where p_has_prev),
       ranked as (select c.*, row_number() over (order by c.amount desc, c.key) as n from cur c where c.key is not null),
       top as (select r.*, (select p.amount from prv p where p.key = r.key) as prev from ranked r where r.n <= p_top)
  select jsonb_build_object(
    'source', p_source,
    'base', case p_source when 'expense_groups' then 'sales' else 'total' end,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'label', label, 'value', amount, 'prev', prev) order by n) from top), '[]'),
    'rest', jsonb_build_object(
      'count', (select count(*) from ranked where n > p_top),
      'value', (select coalesce(sum(amount), 0) from ranked where n > p_top),
      'prev', case when p_has_prev then (select coalesce(sum(p.amount), 0) from prv p
                                         where p.key is not null and p.key not in (select key from top)) end),
    'none', jsonb_build_object(
      'value', (select coalesce(sum(amount), 0) from cur where key is null),
      'prev', case when p_has_prev then (select coalesce(sum(amount), 0) from prv where key is null) end),
    'total', jsonb_build_object(
      'value', (select coalesce(sum(amount), 0) from cur),
      'prev', case when p_has_prev then (select coalesce(sum(amount), 0) from prv) end),
    'sales', jsonb_build_object('value', p_sales, 'prev', p_sales_prev));
$$;
revoke execute on function erp.dash_ranking_card(uuid, integer, date, date, boolean, text, int, numeric, numeric) from anon, public;
grant execute on function erp.dash_ranking_card(uuid, integer, date, date, boolean, text, int, numeric, numeric) to authenticated;

-- ---------- El tablero con las tarjetas de ranking (lo demás, igual que en la 0082) ----------
create or replace function erp.dashboard_data(p_company uuid, p_dashboard text, p_year integer,
                                              p_to_date date default null, p_drafts boolean default false)
returns jsonb language plpgsql stable set jit to 'off' as $$
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
  --   mode month: lo de cada mes = acumulado del mes − acumulado del mes anterior
  --   mode quarter (0082): lo de cada trimestre, con erp.dash_quarters
  --   kind ranking (0083): las filas de erp.dash_ranking_card; sus métricas, vacías
  select coalesce(jsonb_agg(jsonb_build_object(
           'sort', w.sort, 'kind', w.kind, 'size', w.size, 'mode', w.mode, 'label', w.label, 'label_en', w.label_en,
           'help', w.help, 'help_en', w.help_en,
           -- 0083: la tarjeta de ranking (los terceros o subgrupos, con el resto y el total)
           'source', w.source, 'top_n', w.top_n,
           'ranking', case when w.kind = 'ranking' then
                        erp.dash_ranking_card(p_company, p_year, v_to, v_prev_to, fy0.id is not null, w.source, w.top_n,
                                              (cur ->> 'SALES')::numeric, (prev ->> 'SALES')::numeric) end,
           'items', (select coalesce(jsonb_agg(jsonb_build_object(
               'code', m.code, 'label', m.label, 'label_en', m.label_en, 'unit', m.unit, 'link', m.link,
               'help', m.help, 'help_en', m.help_en, 'ref_min', r.ref_min, 'ref_max', r.ref_max,
               'value', cur -> m.code, 'prev', prev -> m.code,
               'series', case when w.kind in ('bars', 'lines') and w.mode = 'quarter' then
                                erp.dash_quarters(ends, s_cur, cur, v_to, m.code)
                              when w.kind in ('bars', 'lines') then (
                  select jsonb_agg(case when s.v is null or s.v = 'null'::jsonb then null
                                        when w.mode = 'month' then to_jsonb((s.v ->> m.code)::numeric
                                             - case when s.n = 1 then 0 else coalesce((s_cur -> (s.n::int - 2) ->> m.code)::numeric, 0) end)
                                        else s.v -> m.code end order by s.n)
                  from jsonb_array_elements(s_cur) with ordinality s(v, n)) end,
               'series_prev', case when w.kind in ('bars', 'lines') and fy0.id is not null and w.mode = 'quarter' then
                                erp.dash_quarters(ends0, s_prev, null, null, m.code)
                              when w.kind in ('bars', 'lines') and fy0.id is not null then (
                  select jsonb_agg(case when w.mode = 'month' then to_jsonb((s.v ->> m.code)::numeric
                                             - case when s.n = 1 then 0 else coalesce((s_prev -> (s.n::int - 2) ->> m.code)::numeric, 0) end)
                                        else s.v -> m.code end order by s.n)
                  from jsonb_array_elements(s_prev) with ordinality s(v, n)) end)
               order by k.n)
             , '[]') from unnest(w.metrics) with ordinality k(code, n)
             join erp.dash_metrics m on m.code = k.code
             left join erp.ratio_defs r on r.code = m.ratio_code))
         order by w.sort), '[]')
    into widgets
  from erp.dash_widgets w where w.dashboard = p_dashboard;

  perform set_config('erp.simulate', v_prev_sim, true);
  return jsonb_build_object(
    'code', d.code, 'label', d.label, 'label_en', d.label_en, 'description', d.description, 'description_en', d.description_en,
    'year', p_year, 'to', v_to, 'prev_to', case when fy0.id is not null then v_prev_to end, 'has_prev', fy0.id is not null,
    'simulation', p_drafts, 'months', to_jsonb(ends), 'months_prev', to_jsonb(ends0), 'widgets', widgets,
    'tax_type', erp.company_tax_type(p_company));   -- 0082: VAT o IGIC, para los títulos
end $$;

-- ---------- El tablero ----------
insert into erp.dashboards (code, sort, label, label_en, description, description_en) values
 ('ventas', 50, 'Ventas y gastos', 'Sales and expenses',
  'Cuánto se vende y cómo va frente al año pasado, a quién se vende y a quién se compra más, y en qué se va el dinero.',
  'How much is sold and how it compares with last year, who the main customers and suppliers are, and where the money goes.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en,
  description = excluded.description, description_en = excluded.description_en;

delete from erp.dash_widgets where dashboard = 'ventas';
insert into erp.dash_widgets (dashboard, sort, kind, size, mode, source, top_n, label, label_en, help, help_en, metrics) values
 ('ventas', 10, 'kpis',    'full', 'end',   null, 10, 'Cifras clave', 'Key figures', null, null, array['SALES', 'PROC', 'STAFF', 'OPEX']),
 ('ventas', 20, 'lines',   'full', 'end',   null, 10, 'Ventas acumuladas a lo largo del año', 'Cumulative sales over the year',
  'La cifra de negocios a cada fin de mes, frente al año anterior.', 'Revenue at each month end, against last year.', array['SALES']),
 ('ventas', 30, 'bars',    'full', 'month', null, 10, 'Ventas y gastos de cada mes', 'Sales and expenses by month',
  'La cifra de negocios y todo el grupo 6 de cada mes, sin regularización ni cierre.',
  'Revenue and all of group 6 each month, without closing entries.', array['SALES', 'EXPENSES']),
 ('ventas', 40, 'ranking', 'half', 'end',   'customers', 10, 'Los 10 clientes con más ventas', 'Top 10 customers by sales',
  'Ventas sin impuestos de cada cliente (lo abonado en las cuentas 700 a 709 en sus asientos). «Sin cliente»: ventas que no pasan por la cuenta de un cliente.',
  'Sales before tax by customer (credits to accounts 700 to 709 in their entries). «No customer»: sales not posted to a customer account.', '{}'),
 ('ventas', 50, 'ranking', 'half', 'end',   'suppliers', 10, 'Los 10 proveedores con más compras', 'Top 10 suppliers by purchases',
  'Compras, gastos e inversiones sin impuestos de cada proveedor o acreedor (lo cargado en los grupos 6 y 2 en sus asientos).',
  'Purchases, expenses and investments before tax by supplier (debits to groups 6 and 2 in their entries).', '{}'),
 ('ventas', 60, 'ranking', 'full', 'end',   'expense_groups', 10, 'Gastos por naturaleza', 'Expenses by nature',
  'Los subgrupos del grupo 6 de la PyG, con su peso sobre la cifra de negocios.',
  'The subgroups of group 6 of the income statement, with their weight on revenue.', '{}');

notify pgrst, 'reload schema';
