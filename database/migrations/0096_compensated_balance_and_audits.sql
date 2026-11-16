-- =====================================================================
-- 0096 · v0.60.7 · El Balance compensado, el menú «Auditorías» y la caja en su sitio (ADR 0064)
-- ---------------------------------------------------------------------
-- Aprobado por Diosvely (15 y 16-11-2026) para el vídeo 03. No cambia ningún asiento ni ningún saldo: solo cómo se
-- presentan.
--   AF-19 · la caja (570, 571) y la 576 no pasan nunca al pasivo. El PGC solo lleva al pasivo corriente el descubierto
--           bancario (cuentas 572-575: «los descubiertos bancarios […] figurarán en todo caso en el pasivo corriente del
--           balance»). Una caja acreedora es un error de registro, no una deuda con un banco: se presenta restando en
--           Tesorería / Efectivo, con su ⚠ (erp.balance_rules ya la marca como error). Decisión de Diosvely: opción 1.
--           Los tres modelos (PYMES, abreviado y normal).
--   BALANCE COMPENSADO (solo lectura) · erp.fs_compensated: el Balance del ERP (sin compensar) al lado del que saldría
--           si se compensaran las subcuentas de un mismo subgrupo, con la diferencia. erp.fs_compensated_ratios: los
--           ratios de liquidez de los dos. Sirve para enseñar qué esconde la compensación (principio de no compensación,
--           PGC, Marco Conceptual, apartado 3.º); el ERP sigue sin compensar.
--   MENÚ «AUDITORÍAS» · cada tablero lleva su grupo (erp.dashboards.area): «tablero» (gestión) o «auditoria». Calidad
--           de la contabilidad pasa a auditorías y se añade «Saldos al revés», con un tipo de tarjeta nuevo
--           (reverse_cards): una tarjeta por cuenta con saldo al revés y dónde la pone el Balance en cada modelo.
-- Pruebas: fase 82 (AF-19), fase 78 (el ⚠ de la caja, ahora en el activo) y fase 84 (lo nuevo).
-- Se puede ejecutar dos veces.
-- =====================================================================

-- ---------- AF-19 · La caja y la 576, siempre en el activo ----------
-- PYMES (RD 1515/2007): VI. Efectivo y otros activos líquidos equivalentes
insert into erp.fs_mapping (statement, prefix, debit_line, credit_line) values
  ('balance', '570', 'AC.VI', 'AC.VI'),
  ('balance', '571', 'AC.VI', 'AC.VI'),
  ('balance', '576', 'AC.VI', 'AC.VI')
on conflict (statement, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- Normal (RD 1514/2007): VII. 1. Tesorería (570, 571) y 2. Otros activos líquidos equivalentes (576)
insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line) values
  ('normal', '570', 'AC.VII.1', 'AC.VII.1'),
  ('normal', '571', 'AC.VII.1', 'AC.VII.1'),
  ('normal', '576', 'AC.VII.2', 'AC.VII.2')
on conflict (model, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- Abreviado: derivado del normal, como en la 0089 (así no puede contradecirlo)
insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line)
select 'abreviado', prefix, erp.fs_abridged_line(debit_line), erp.fs_abridged_line(credit_line)
from erp.fs_model_mapping where model = 'normal' and prefix in ('570', '571', '576')
on conflict (model, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- ---------- El Balance compensado (solo lectura) ----------
-- Cada partida del modelo con dos importes:
--   amount       el Balance del ERP: cada subcuenta en su lado según su propio saldo (sin compensar);
--   amount_comp  el que saldría compensando: se suman las subcuentas del mismo subgrupo (dos dígitos) que van a la
--                misma pareja de partidas (deudora / acreedora) y el neto va a un solo lado según su signo.
-- Ejemplo: Banco Sur 53.618,40 y Banco Norte −11.680,50 → compensado, 41.937,90 de tesorería y ninguna deuda.
create or replace function erp.fs_compensated(p_company uuid, p_year integer, p_to_date date default null,
                                              p_drafts boolean default false, p_model text default 'pymes')
returns table(code text, parent text, sort integer, level integer, label text, label_en text, is_total boolean,
              amount numeric, amount_comp numeric)
language plpgsql stable set jit = off as $$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  perform erp.fs_check_model('balance', p_model);
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with recursive lines as (select * from erp.fs_model_line_set(p_model)),
  depth(code, level) as (
    select l.code, 0 from lines l where l.parent is null
    union all
    select c.code, d.level + 1 from depth d join lines c on c.parent = d.code
  ),
  up(code, ancestor) as (
    select l.code, l.code from lines l
    union all
    select up.code, p.parent from up join lines p on p.code = up.ancestor where p.parent is not null
  ),
  acc as (select a.account_no, a.balance
          from erp.fs_classified_at(p_company, p_year, 'balance', array[p_to_date]) a),
  pair as (
    select a.account_no, a.balance, m.dl, m.cl
    from acc a
    cross join lateral (
      select x.dl, x.cl from (
        select fm.prefix, fm.debit_line as dl, fm.credit_line as cl from erp.fs_mapping fm
        where p_model = 'pymes' and fm.statement = 'balance' and a.account_no like fm.prefix || '%'
        union all
        select fm.prefix, fm.debit_line, fm.credit_line from erp.fs_model_mapping fm
        where p_model <> 'pymes' and fm.model = p_model and a.account_no like fm.prefix || '%') x
      order by length(x.prefix) desc limit 1) m
  ),
  net as (
    select case when sum(balance) >= 0 then dl else cl end as line, sum(balance) as bal
    from pair group by left(account_no, 2), dl, cl
    having sum(balance) <> 0
  ),
  comp as (
    select n.line as line_code, sum(n.bal * case l.side when 'debit' then 1 else -1 end) as amount
    from net n join lines l on l.code = n.line group by n.line
  ),
  unc as (
    select c.line_code, sum(c.amount) as amount
    from erp.fs_model_classified_at(p_company, p_year, p_model, array[p_to_date]) c group by c.line_code
  ),
  tot as (
    select up.ancestor as code, coalesce(sum(u.amount), 0) as amount, coalesce(sum(k.amount), 0) as amount_comp
    from up
    left join unc u on u.line_code = up.code
    left join comp k on k.line_code = up.code
    group by up.ancestor
  )
  select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total, t.amount, t.amount_comp
  from lines l join depth d on d.code = l.code join tot t on t.code = l.code
  order by l.sort;
  perform set_config('erp.simulate', v_prev, true);
end $$;

-- Los ratios de liquidez y endeudamiento de los dos Balances (las mismas fórmulas que erp.financial_ratios):
--   LIQ liquidez general = AC / PC · QR prueba ácida = (AC − existencias) / PC · CASH tesorería inmediata = efectivo / PC
--   DEBT endeudamiento = (PNC + PC) / total activo · WC fondo de maniobra = AC − PC · HIDDEN lo escondido = total activo
--   sin compensar − compensado
create or replace function erp.fs_compensated_ratios(p_company uuid, p_year integer, p_to_date date default null,
                                                     p_drafts boolean default false, p_model text default 'pymes')
returns table(code text, amount numeric, amount_comp numeric)
language sql stable set jit = off as $$
  with b as (select * from erp.fs_compensated(p_company, p_year, p_to_date, p_drafts, p_model)),
  v as (
    select
      sum(b.amount)      filter (where b.code = 'AC')  as ac,  sum(b.amount_comp) filter (where b.code = 'AC')  as ac_c,
      sum(b.amount)      filter (where b.code = 'PC')  as pc,  sum(b.amount_comp) filter (where b.code = 'PC')  as pc_c,
      sum(b.amount)      filter (where b.code = 'PNC') as pnc, sum(b.amount_comp) filter (where b.code = 'PNC') as pnc_c,
      sum(b.amount)      filter (where b.code = 'ACT') as act, sum(b.amount_comp) filter (where b.code = 'ACT') as act_c,
      sum(b.amount)      filter (where b.code = case when p_model = 'pymes' then 'AC.I' else 'AC.II' end) as inv,
      sum(b.amount_comp) filter (where b.code = case when p_model = 'pymes' then 'AC.I' else 'AC.II' end) as inv_c,
      sum(b.amount)      filter (where b.code = case when p_model = 'pymes' then 'AC.VI' else 'AC.VII' end) as cash,
      sum(b.amount_comp) filter (where b.code = case when p_model = 'pymes' then 'AC.VI' else 'AC.VII' end) as cash_c
    from b)
  select x.code, x.a, x.c from v cross join lateral (values
    ('LIQ',    round(v.ac / nullif(v.pc, 0), 4),               round(v.ac_c / nullif(v.pc_c, 0), 4)),
    ('QR',     round((v.ac - v.inv) / nullif(v.pc, 0), 4),     round((v.ac_c - v.inv_c) / nullif(v.pc_c, 0), 4)),
    ('CASH',   round(v.cash / nullif(v.pc, 0), 4),             round(v.cash_c / nullif(v.pc_c, 0), 4)),
    ('DEBT',   round((v.pnc + v.pc) / nullif(v.act, 0), 4),    round((v.pnc_c + v.pc_c) / nullif(v.act_c, 0), 4)),
    ('WC',     v.ac - v.pc,                                     v.ac_c - v.pc_c),
    ('HIDDEN', v.act - v.act_c,                                 0::numeric)) x(code, a, c);
$$;

revoke execute on function erp.fs_compensated(uuid, integer, date, boolean, text),
                           erp.fs_compensated_ratios(uuid, integer, date, boolean, text) from anon, public;
grant execute on function erp.fs_compensated(uuid, integer, date, boolean, text),
                          erp.fs_compensated_ratios(uuid, integer, date, boolean, text) to authenticated;

-- ---------- El menú «Auditorías»: el grupo de cada tablero ----------
alter table erp.dashboards add column if not exists area text not null default 'tablero';
alter table erp.dashboards drop constraint if exists dashboards_area_check;
alter table erp.dashboards add constraint dashboards_area_check check (area in ('tablero', 'auditoria'));
update erp.dashboards set area = 'auditoria' where code = 'calidad';

-- ---------- El tablero «Saldos al revés» ----------
alter table erp.dash_widgets drop constraint if exists dash_widgets_kind_check;
alter table erp.dash_widgets add constraint dash_widgets_kind_check
  check (kind in ('kpis', 'bars', 'lines', 'table', 'ranking', 'checklist', 'reverse_cards'));

insert into erp.dashboards (code, sort, label, label_en, description, description_en, area) values
 ('saldos_reves', 70, 'Saldos al revés', 'Balances against their nature',
  'Una tarjeta por cada subcuenta con el saldo contrario a su naturaleza: si es imposible o hay que revisarla, dónde la pone el Balance y qué preguntaría un auditor. El ERP no compensa: avisa.',
  'One card per account with a balance against its nature: whether it is impossible or needs review, where the balance sheet puts it and what an auditor would ask. The ERP does not offset: it warns.',
  'auditoria')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en,
  description = excluded.description, description_en = excluded.description_en, area = excluded.area;

delete from erp.dash_widgets where dashboard = 'saldos_reves';
insert into erp.dash_widgets (dashboard, sort, kind, size, mode, source, top_n, label, label_en, help, help_en, metrics) values
 ('saldos_reves', 10, 'reverse_cards', 'full', 'end', null, 10, 'Cuentas con saldo al revés', 'Accounts against their nature',
  '«Imposible»: un saldo que no puede existir (una caja en negativo, una amortización deudora…); es un error seguro. «Revisar»: puede ser real (un descubierto, un anticipo) o un error. La pregunta es la de un auditor; la respuesta está en el Mayor.',
  '«Impossible»: a balance that cannot exist (negative cash, a debit accumulated depreciation…); it is a certain error. «Review»: it may be real (an overdraft, an advance) or an error. The question is an auditor''s; the answer is in the ledger.',
  '{}');

-- Las tarjetas: cada cuenta con saldo al revés y la partida en la que la presenta el Balance en cada modelo
create or replace function erp.reverse_cards(p_company uuid, p_year integer, p_to date default null, p_drafts boolean default false)
returns jsonb language plpgsql stable set jit = off as $$
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off'); r jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  with an as (select * from erp.balance_anomalies(p_company, p_year, null, p_to, p_drafts)),
  cls as (
    select m.code as model, c.account_no, c.line_code, s.label, s.label_en
    from erp.fs_models m
    cross join lateral erp.fs_model_classified_at(p_company, p_year, m.code, array[p_to]) c
    join erp.fs_model_line_set(m.code) s on s.code = c.line_code
    where c.account_no in (select account_no from an))
  select coalesce(jsonb_agg(jsonb_build_object(
           'account_no', a.account_no, 'name', a.name, 'name_en', a.name_en, 'expected', a.expected,
           'balance', a.balance, 'severity', a.severity, 'note', a.note, 'note_en', a.note_en,
           'lines', (select jsonb_object_agg(k.model, jsonb_build_object('code', k.line_code, 'label', k.label, 'label_en', k.label_en))
                     from cls k where k.account_no = a.account_no))
         order by case a.severity when 'error' then 0 else 1 end, a.account_no), '[]')
  into r from an a;
  perform set_config('erp.simulate', v_prev, true);
  return r;
end $$;
revoke execute on function erp.reverse_cards(uuid, integer, date, boolean) from anon, public;
grant execute on function erp.reverse_cards(uuid, integer, date, boolean) to authenticated;

-- erp.dashboard_data: copia de la versión de la 0084 con la clave nueva «cards» (tarjetas reverse_cards)
create or replace function erp.dashboard_data(p_company uuid, p_dashboard text, p_year integer, p_to_date date default null,
                                              p_drafts boolean default false)
 returns jsonb
 language plpgsql
 stable
 set jit to 'off'
as $function$
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
  --   kind reverse_cards (0096): las tarjetas de erp.reverse_cards
  select coalesce(jsonb_agg(jsonb_build_object(
           'sort', w.sort, 'kind', w.kind, 'size', w.size, 'mode', w.mode, 'label', w.label, 'label_en', w.label_en,
           'help', w.help, 'help_en', w.help_en,
           -- 0083: la tarjeta de ranking (los terceros o subgrupos, con el resto y el total)
           'source', w.source, 'top_n', w.top_n,
           'checklist', case when w.kind = 'checklist' then erp.quality_card(p_company, p_year, v_to, p_drafts) end,   -- 0084
           'cards', case when w.kind = 'reverse_cards' then erp.reverse_cards(p_company, p_year, v_to, p_drafts) end,   -- 0096
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
    'area', d.area,                                  -- 0096: tablero o auditoría
    'year', p_year, 'to', v_to, 'prev_to', case when fy0.id is not null then v_prev_to end, 'has_prev', fy0.id is not null,
    'simulation', p_drafts, 'months', to_jsonb(ends), 'months_prev', to_jsonb(ends0), 'widgets', widgets,
    'tax_type', erp.company_tax_type(p_company));   -- 0082: VAT o IGIC, para los títulos
end $function$;
