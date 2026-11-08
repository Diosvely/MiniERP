-- =====================================================================
-- 0084 · Tablero «Calidad de la contabilidad» y aviso de saldos al revés en el Balance (v0.57.0 · ADR 0057)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.57.0.md, 01-11-2026): «meses sin cerrar» solo en las empresas mes a mes, las
-- liquidaciones pendientes como error, el aviso del Balance completo (franja, partida y cuenta) y la 400 deudora en
-- Existencias con aviso hasta revisar el criterio (hecho en la 0088, ADR 0061).
--
--   · LISTA DE CONTROL (erp.quality_checks): 7 filas a una fecha, cada una con su valor, su gravedad (ok, info, warning,
--     error o «no aplica») y su pantalla. Salen de lo que ya existe: balance_anomalies, draft_problem, los periodos,
--     las liquidaciones y la antigüedad de saldos. Los textos, en un catálogo (erp.quality_check_defs).
--   · TARJETA «checklist» y dos fuentes nuevas de ranking: anomalies (cuentas con saldo al revés, con su nota) y
--     overdue_customers (clientes con más importe vencido).
--   · erp.fs_line_anomalies: cada cuenta con saldo al revés con la partida del Balance en la que se presenta (para el
--     aviso del propio Balance). El ERP no compensa: avisa.
--
-- Se puede ejecutar dos veces.
-- =====================================================================

-- ---------- Los textos de la lista de control ----------
create table if not exists erp.quality_check_defs (
  code     text primary key,
  sort     int  not null,
  label    text not null,
  label_en text not null,
  help     text not null,
  help_en  text not null,
  unit     text not null check (unit in ('count', 'eur')),
  link     text not null          -- pantalla de la empresa donde se arregla
);
alter table erp.quality_check_defs enable row level security;
drop policy if exists read on erp.quality_check_defs;
create policy read on erp.quality_check_defs for select to authenticated using (true);
revoke all on erp.quality_check_defs from anon, public, authenticated;
grant select on erp.quality_check_defs to authenticated;

insert into erp.quality_check_defs (code, sort, label, label_en, help, help_en, unit, link) values
 ('anomalies', 10, 'Saldos al revés de su naturaleza', 'Balances against their nature',
  'Cuentas con saldo contrario al normal (un proveedor deudor, una caja acreedora…). El ERP no las compensa: las presenta en la otra masa del balance y avisa. «Imposibles» = errores seguros.',
  'Accounts with a balance against their normal side (a supplier with a debit balance, cash with a credit balance…). The ERP does not offset them: it presents them on the other side and warns. «Impossible» = certain errors.',
  'count', 'checks'),
 ('drafts', 20, 'Asientos en edición', 'Draft entries',
  'Borradores del ejercicio hasta la fecha. No cuentan en los informes hasta contabilizarlos; los que tienen un problema (descuadre, mes cerrado, cuenta controlada…) no se pueden contabilizar.',
  'Drafts of the year up to the date. They do not count in reports until posted; those with a problem (unbalanced, closed month, controlled account…) cannot be posted.',
  'count', 'entries'),
 ('open_months', 30, 'Meses sin cerrar', 'Months not closed',
  'En la contabilidad mes a mes: meses ya terminados que siguen abiertos.',
  'In month-by-month accounting: months already over that are still open.',
  'count', 'entries'),
 ('settlements', 40, 'Liquidaciones pendientes', 'Pending tax returns',
  'Trimestres terminados sin la liquidación de IVA / IGIC contabilizada. Tienen plazo y recargo.',
  'Quarters already over without a posted VAT / IGIC return. They have a deadline and surcharges.',
  'count', 'settlement'),
 ('overdue_in', 50, 'Cobros vencidos', 'Overdue receivables',
  'Facturas emitidas pendientes de cobro y ya vencidas a la fecha. Error si alguna pasa de 90 días.',
  'Sales invoices pending and already due at the date. Error if any is over 90 days.',
  'eur', 'payments'),
 ('overdue_out', 60, 'Pagos vencidos', 'Overdue payables',
  'Facturas recibidas pendientes de pago y ya vencidas a la fecha.',
  'Purchase invoices pending and already due at the date.',
  'eur', 'payments'),
 ('unreconciled', 70, 'Terceros sin conciliar', 'Unreconciled partners',
  'Clientes y proveedores cuyo saldo contable no coincide con sus facturas pendientes: un cobro o pago sin vincular, o un apunte manual en su cuenta.',
  'Customers and suppliers whose account balance does not match their pending invoices: an unlinked receipt or payment, or a manual entry on their account.',
  'count', 'payments')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en, help = excluded.help,
  help_en = excluded.help_en, unit = excluded.unit, link = excluded.link;

-- ---------- La lista de control a una fecha ----------
--   severity: ok · info (hay algo, pero es normal: borradores sin problema) · warning · error · na (no aplica)
create or replace function erp.quality_checks(p_company uuid, p_year integer, p_to date default null, p_drafts boolean default false)
returns table(code text, value numeric, extra numeric, severity text)
language plpgsql stable set jit to 'off' as $$
#variable_conflict use_column
declare
  v_prev_sim text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
  fy erp.fiscal_years; co erp.companies; v_to date; n numeric; x numeric; has_inv boolean;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into fy from erp.fiscal_years f where f.company_id = p_company and f.year = p_year;
  if fy.id is null then raise exception 'No fiscal year %', p_year; end if;
  select * into co from erp.companies c where c.id = p_company;
  v_to := least(coalesce(p_to, fy.ending_date), fy.ending_date);
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;

  -- 1) Saldos al revés (y cuántos son imposibles: severity error de balance_rules)
  select count(*), count(*) filter (where a.severity = 'error') into n, x
  from erp.balance_anomalies(p_company, p_year, null, v_to, p_drafts) a;
  code := 'anomalies'; value := n; extra := x;
  severity := case when x > 0 then 'error' when n > 0 then 'warning' else 'ok' end; return next;

  -- 2) Asientos en edición (y cuántos tienen un problema: erp.draft_ready, la que puede usar la web)
  select count(*), count(*) filter (where not erp.draft_ready(e.id)) into n, x
  from erp.journal_entries e
  where e.company_id = p_company and e.fiscal_year_id = fy.id and e.status = 'draft' and e.posting_date <= v_to;
  code := 'drafts'; value := n; extra := x;
  severity := case when x > 0 then 'warning' when n > 0 then 'info' else 'ok' end; return next;

  -- 3) Meses sin cerrar: solo en la contabilidad mes a mes (en las demás todos están abiertos por diseño)
  code := 'open_months'; extra := null;
  if co.monthly then
    select count(*) into n from erp.accounting_periods p
    where p.fiscal_year_id = fy.id and p.status = 'open' and p.ending_date < least(v_to, current_date);
    value := n; severity := case when n > 0 then 'warning' else 'ok' end;
  else
    value := null; severity := 'na';
  end if;
  return next;

  -- 4) Liquidaciones pendientes: trimestres terminados (hasta la fecha) sin liquidación contabilizada del impuesto de la
  --    empresa; solo si el impuesto está configurado
  code := 'settlements'; extra := null;
  if exists (select 1 from erp.tax_settlement_setup s where s.company_id = p_company and s.tax_type = erp.company_tax_type(p_company)) then
    select count(*) into n from generate_series(1, 4) q
    where erp.quarter_end(p_year, q) <= v_to and erp.quarter_end(p_year, q) < current_date
      and not exists (select 1 from erp.tax_settlements s where s.company_id = p_company and s.tax_type = erp.company_tax_type(p_company)
                      and s.year = p_year and s.quarter = q and s.status = 'posted');
    value := n; severity := case when n > 0 then 'error' else 'ok' end;
  else
    value := null; severity := 'na';
  end if;
  return next;

  -- 5) a 7) Vencidos y terceros sin conciliar: de la antigüedad de saldos; solo si la empresa tiene facturas en el ERP
  --    (una empresa importada solo trae asientos)
  has_inv := exists (select 1 from erp.invoices i where i.company_id = p_company);
  code := 'overdue_in';
  if has_inv then
    select coalesce(sum(a.d1_30 + a.d31_60 + a.d61_90 + a.d90_plus), 0), coalesce(sum(a.d90_plus), 0) into n, x
    from erp.aging(p_company, 'sale', v_to) a;
    value := n; extra := x; severity := case when x > 0 then 'error' when n > 0 then 'warning' else 'ok' end;
  else value := null; extra := null; severity := 'na'; end if;
  return next;

  code := 'overdue_out';
  if has_inv then
    select coalesce(sum(a.d1_30 + a.d31_60 + a.d61_90 + a.d90_plus), 0), coalesce(sum(a.d90_plus), 0) into n, x
    from erp.aging(p_company, 'purchase', v_to) a;
    value := n; extra := x; severity := case when n > 0 then 'warning' else 'ok' end;
  else value := null; extra := null; severity := 'na'; end if;
  return next;

  code := 'unreconciled'; extra := null;
  if has_inv then
    select count(*) into n from (
      select a.total, a.account_balance from erp.aging(p_company, 'sale', v_to) a
      union all
      select a.total, a.account_balance from erp.aging(p_company, 'purchase', v_to) a) z
    where z.total <> z.account_balance;
    value := n; severity := case when n > 0 then 'warning' else 'ok' end;
  else value := null; severity := 'na'; end if;
  return next;

  perform set_config('erp.simulate', v_prev_sim, true);
end $$;
revoke execute on function erp.quality_checks(uuid, integer, date, boolean) from anon, public;
grant execute on function erp.quality_checks(uuid, integer, date, boolean) to authenticated;

-- La tarjeta: cada fila con sus textos y su pantalla
create or replace function erp.quality_card(p_company uuid, p_year integer, p_to date, p_drafts boolean)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', q.code, 'label', d.label, 'label_en', d.label_en, 'help', d.help, 'help_en', d.help_en,
           'unit', d.unit, 'link', d.link, 'value', q.value, 'extra', q.extra, 'severity', q.severity) order by d.sort), '[]')
  from erp.quality_checks(p_company, p_year, p_to, p_drafts) q
  join erp.quality_check_defs d on d.code = q.code;
$$;
revoke execute on function erp.quality_card(uuid, integer, date, boolean) from anon, public;
grant execute on function erp.quality_card(uuid, integer, date, boolean) to authenticated;

-- ---------- El aviso del Balance: cada cuenta con saldo al revés y su partida ----------
create or replace function erp.fs_line_anomalies(p_company uuid, p_year integer, p_to date default null, p_drafts boolean default false)
returns table(line_code text, account_no text, name text, name_en text, balance numeric, expected text, severity text, note text, note_en text)
language plpgsql stable set jit to 'off' as $$
#variable_conflict use_column
declare v_prev_sim text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  select c.line_code, a.account_no, a.name, a.name_en, a.balance, a.expected, a.severity, a.note, a.note_en
  from erp.balance_anomalies(p_company, p_year, null, p_to, p_drafts) a
  join erp.fs_classified_accounts(p_company, p_year, 'balance', p_to) c on c.account_no = a.account_no
  order by c.line_code, a.account_no;
  perform set_config('erp.simulate', v_prev_sim, true);
end $$;
revoke execute on function erp.fs_line_anomalies(uuid, integer, date, boolean) from anon, public;
grant execute on function erp.fs_line_anomalies(uuid, integer, date, boolean) to authenticated;

-- ---------- Catálogo: la lista de control y las dos fuentes de ranking nuevas ----------
alter table erp.dash_widgets drop constraint if exists dash_widgets_kind_check;
alter table erp.dash_widgets add constraint dash_widgets_kind_check check (kind in ('kpis', 'bars', 'lines', 'table', 'ranking', 'checklist'));
alter table erp.dash_widgets drop constraint if exists dash_widgets_source_check;
alter table erp.dash_widgets add constraint dash_widgets_source_check
  check ((kind = 'ranking') = (source is not null)
         and (source is null or source in ('customers', 'suppliers', 'expense_groups', 'anomalies', 'overdue_customers'))
         and top_n between 1 and 50);

-- ---------- El ranking, con la nota de cada fila (0084: cuentas con saldo al revés y clientes con vencido) ----------
-- Cambian las columnas que devuelve (se añade la nota): hay que borrarla y crearla de nuevo
drop function if exists erp.dash_ranking(uuid, integer, date, text);
create or replace function erp.dash_ranking(p_company uuid, p_year integer, p_to date, p_source text)
returns table(key text, label text, amount numeric, note text, note_en text)
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
  select key, max(label), round(sum(v), 2), null::text, null::text from alloc group by key having round(sum(v), 2) <> 0
  union all
  -- gastos por naturaleza: los subgrupos del grupo 6 de la PyG, con el nombre del PGC
  select s.key, coalesce(sg.name, s.key), s.amount, null::text, null::text
  from (select left(c.account_no, 2) as key, sum(c.balance) as amount
        from erp.fs_classified_at(p_company, p_year, 'pyg', array[p_to]) c
        where p_source = 'expense_groups' and c.account_no like '6%'
        group by left(c.account_no, 2) having sum(c.balance) <> 0) s
  left join erp.pgc_subgroups sg on sg.subgroup = s.key
  union all
  -- 0084 · cuentas con saldo al revés: el importe en valor absoluto y la nota de balance_rules (qué suele ser)
  select a.account_no, a.name, abs(a.balance), a.note, a.note_en
  from erp.balance_anomalies(p_company, p_year, null, p_to, erp.simulating()) a
  where p_source = 'anomalies' and erp.can_report(p_company)
  union all
  -- 0084 · clientes con importe vencido a la fecha (de la antigüedad de saldos)
  select a.partner_account_no, a.partner_name, a.d1_30 + a.d31_60 + a.d61_90 + a.d90_plus,
         -- (sin el importe en el texto: el formato de los números depende del servidor; el importe va en la fila)
         case when a.d90_plus > 0 then 'Tiene facturas vencidas hace más de 90 días.' end,
         case when a.d90_plus > 0 then 'Has invoices more than 90 days overdue.' end
  from erp.aging(p_company, 'sale', p_to) a
  where p_source = 'overdue_customers' and erp.can_report(p_company) and a.d1_30 + a.d31_60 + a.d61_90 + a.d90_plus > 0;
$$;

create or replace function erp.dash_ranking_card(p_company uuid, p_year integer, p_to date, p_prev_to date, p_has_prev boolean,
                                                 p_source text, p_top int, p_sales numeric, p_sales_prev numeric)
returns jsonb language sql stable as $$
  with cur as (select * from erp.dash_ranking(p_company, p_year, p_to, p_source)),
       prv as (select * from erp.dash_ranking(p_company, p_year - 1, p_prev_to, p_source) where p_has_prev),
       ranked as (select c.*, row_number() over (order by c.amount desc, c.key) as n from cur c where c.key is not null),
       top as (select r.*, (select p.amount from prv p where p.key = r.key) as prev from ranked r where r.n <= p_top)
  select jsonb_build_object(
    'source', p_source,
    'base', case p_source when 'expense_groups' then 'sales' when 'anomalies' then 'none' else 'total' end,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('key', key, 'label', label, 'value', amount, 'prev', prev, 'note', note, 'note_en', note_en) order by n) from top), '[]'),
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

revoke execute on function erp.dash_ranking(uuid, integer, date, text) from anon, public;
grant execute on function erp.dash_ranking(uuid, integer, date, text) to authenticated;

-- ---------- El tablero con la lista de control (lo demás, igual que en la 0083) ----------
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
  --   kind checklist (0084): la lista de control de erp.quality_card
  select coalesce(jsonb_agg(jsonb_build_object(
           'sort', w.sort, 'kind', w.kind, 'size', w.size, 'mode', w.mode, 'label', w.label, 'label_en', w.label_en,
           'help', w.help, 'help_en', w.help_en,
           -- 0083: la tarjeta de ranking (los terceros o subgrupos, con el resto y el total)
           'source', w.source, 'top_n', w.top_n,
           'checklist', case when w.kind = 'checklist' then erp.quality_card(p_company, p_year, v_to, p_drafts) end,   -- 0084
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
 ('calidad', 60, 'Calidad de la contabilidad', 'Accounting quality',
  '¿Me puedo fiar de esta contabilidad a esta fecha y qué falta por hacer? La versión ligera de Comprobaciones: cada fila lleva a la pantalla donde se arregla.',
  'Can I trust these books at this date and what is left to do? The light version of Checks: each row leads to the screen where it is fixed.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en,
  description = excluded.description, description_en = excluded.description_en;

delete from erp.dash_widgets where dashboard = 'calidad';
insert into erp.dash_widgets (dashboard, sort, kind, size, mode, source, top_n, label, label_en, help, help_en, metrics) values
 ('calidad', 10, 'checklist', 'full', 'end', null, 10, 'Lista de control', 'Checklist',
  'A la fecha elegida. Para el análisis completo, Comprobaciones.', 'At the chosen date. For the full analysis, Checks.', '{}'),
 ('calidad', 20, 'ranking',   'half', 'end', 'anomalies', 10, 'Cuentas con saldo al revés', 'Accounts against their nature',
  'Las de más importe, con lo que suele significar. El ERP no las compensa: revisa su libro mayor.',
  'The largest ones, with what it usually means. The ERP does not offset them: check their ledger.', '{}'),
 ('calidad', 30, 'ranking',   'half', 'end', 'overdue_customers', 10, 'Clientes con más importe vencido', 'Customers with most overdue',
  'Facturas emitidas pendientes y vencidas a la fecha (de la antigüedad de saldos).',
  'Sales invoices pending and overdue at the date (from the ageing report).', '{}');

notify pgrst, 'reload schema';
