-- =====================================================================
-- 0082 · Tablero «Impuestos» (v0.55.0 · ADR 0055)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.55.0.md, 01-11-2026): el impuesto del territorio de la empresa, el estado de
-- cada liquidación en la v0.57.0 y la lista de cuentas de impuesto en una función compartida.
--
--   · UNA SOLA REGLA PARA LAS CUENTAS DE IMPUESTO: erp.tax_accounts(empresa, tipo) es la lista que estaba dentro de
--     erp.tax_settlement_calc. La liquidación la usa tal cual (calcula lo mismo) y el tablero también: no pueden decir
--     cosas distintas.
--   · TIPO DE MÉTRICA «tax» (flow 'output' | 'input'): devengado o deducible desde el 1 de enero hasta la fecha, del
--     impuesto del territorio (IGIC en Canarias, IVA en el resto), sin los asientos de liquidación ni los del cierre,
--     apertura incluida (erp.is_settlement_entry), como la liquidación. Lo de un trimestre = la liquidación de ese
--     trimestre.
--   · TIPO DE MÉTRICA «move» (account_prefix y flow 'debit' | 'credit'): lo cargado o abonado en una cuenta en el año,
--     sin la apertura ni el cierre. Abonos de la 4751 = retenciones practicadas; cargos de la 473 = soportadas.
--   · SERIES POR TRIMESTRE (mode 'quarter'): lo de cada trimestre natural = acumulado a fin de trimestre − al anterior.
--   · erp.dashboard_data devuelve también el impuesto de la empresa (tax_type: VAT o IGIC).
--
-- Se puede ejecutar dos veces.
-- =====================================================================

-- ---------- Las cuentas de impuesto de un tipo: la regla de la liquidación, en un solo sitio ----------
create or replace function erp.tax_accounts(p_company uuid, p_tax_type text)
returns table(id uuid, side text) language sql stable as $$
    select distinct s.output_account_id as id, 'output' as side from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.output_account_id is not null
    union
    select distinct s.input_account_id, 'input' from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.input_account_id is not null
    union   -- recargo de equivalencia repercutido: también se ingresa con el modelo 303
    select distinct s.surcharge_account_id, 'output' from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.surcharge_account_id is not null
    union   -- v0.33.1: las 472 / 477 que NO están configuradas para ningún tipo cuentan en el impuesto del territorio.
            -- Antes un apunte en una 47700001 sin configurar quedaba fuera del cuadre del 303 / 420.
    select g.id, case when g.account_no like '472%' then 'input' else 'output' end
      from erp.gl_accounts g
      where g.company_id = p_company and g.account_type = 'posting'
        and (g.account_no like '472%' or g.account_no like '477%')
        and p_tax_type = (select case tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end
                          from erp.companies where id = p_company)
        and not exists (select 1 from erp.tax_setup s
                        where s.company_id = p_company and g.id in (s.input_account_id, s.output_account_id, s.surcharge_account_id))
$$;
revoke execute on function erp.tax_accounts(uuid, text) from anon, public;
grant execute on function erp.tax_accounts(uuid, text) to authenticated;

-- La liquidación, con la lista de cuentas de erp.tax_accounts (el resto, igual que en la 0039)
CREATE OR REPLACE FUNCTION erp.tax_settlement_calc(p_company uuid, p_tax_type text, p_year integer, p_quarter integer, p_refund boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare
  v_start    date := erp.quarter_start(p_year, p_quarter);
  v_end      date := erp.quarter_end(p_year, p_quarter);
  v_set      erp.tax_settlement_setup;
  v_out      numeric;
  v_in       numeric;
  v_reg_out  numeric;
  v_reg_in   numeric;
  v_carry    numeric;
  v_applied  numeric := 0;
  v_result   numeric;
  v_final    numeric;
  v_outcome  text;
  v_boxes    jsonb;
  v_lines    jsonb;
  v_done     erp.tax_settlements;
begin
  if p_quarter not between 1 and 4 then
    raise exception 'Invalid quarter: %', p_quarter;
  end if;
  select * into v_set from erp.tax_settlement_setup where company_id = p_company and tax_type = p_tax_type;
  if not found then
    raise exception '% is not set up for this company (Taxes tab)', p_tax_type;
  end if;
  select * into v_done from erp.tax_settlements
  where company_id = p_company and tax_type = p_tax_type and year = p_year and quarter = p_quarter and status = 'posted';

  -- 1) Movimiento del trimestre en las cuentas de impuesto (lo que dice la CONTABILIDAD)
  -- v0.55.0 (0082): la lista de cuentas de impuesto, en erp.tax_accounts (la usa también el tablero de Impuestos)
  with acc as (
    select a.id, a.side from erp.tax_accounts(p_company, p_tax_type) a
  ), mov as (
    select acc.id, acc.side, g.account_no, g.name,
           coalesce(sum(l.debit - l.credit), 0) as balance   -- saldo deudor (+) / acreedor (−) del trimestre
    from acc
    join erp.gl_accounts g on g.id = acc.id
    left join erp.journal_lines l on l.gl_account_id = acc.id
      and exists (select 1 from erp.journal_entries e where e.id = l.entry_id and e.status = 'posted'
                  and e.posting_date between v_start and v_end and not erp.is_settlement_entry(e.id))
    group by acc.id, acc.side, g.account_no, g.name
  )
  select coalesce(sum(-balance) filter (where side = 'output'), 0),
         coalesce(sum(balance)  filter (where side = 'input'), 0),
         coalesce(jsonb_agg(jsonb_build_object('account_no', account_no, 'account_name', name,
                    -- se salda: un saldo deudor se cierra al Haber y uno acreedor al Debe
                    'debit', case when balance < 0 then -balance else 0 end,
                    'credit', case when balance > 0 then balance else 0 end) order by account_no)
                  filter (where balance <> 0), '[]'::jsonb)
    into v_out, v_in, v_lines
  from mov;

  -- 2) Casillas del borrador por tipo, desde el LIBRO REGISTRO de facturas
  select coalesce(jsonb_agg(jsonb_build_object('side', b.side, 'kind', b.kind, 'tax_code', b.tax_code, 'rate_pct', b.rate_pct,
                    'tax_base', b.base, 'tax_amount', b.amount) order by b.side desc, b.kind desc, b.rate_pct desc), '[]'::jsonb),
         coalesce(sum(b.amount) filter (where b.side = 'output'), 0),
         coalesce(sum(b.amount) filter (where b.side = 'input'), 0)
    into v_boxes, v_reg_out, v_reg_in
  from (
    select x.side, x.kind, x.tax_code, x.rate_pct, sum(x.base) as base, sum(x.amount) as amount
    from (
      -- cuota de cada factura: emitidas → devengada · recibidas → deducible (si lo es)
      --   (en compras, solo la parte deducible: prorrata; lo no deducible del recargo de equivalencia no cuenta)
      select case r.invoice_type when 'sale' then 'output' else 'input' end as side, 'tax' as kind,
             r.tax_code, r.rate_pct, r.tax_base as base,
             case r.invoice_type when 'sale' then r.tax_amount else r.deductible_amount end as amount
      from erp.v_invoice_register r
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and (r.invoice_type = 'sale' or r.deductible_amount <> 0 or r.tax_amount = 0)
      union all
      -- inversión del sujeto pasivo y adquisiciones intracomunitarias: la empresa también DEVENGA la cuota
      select 'output', 'reverse_charge', r.tax_code, r.rate_pct, r.tax_base, r.tax_amount
      from erp.v_invoice_register r
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and r.invoice_type = 'purchase' and r.rate_category in ('reverse_charge', 'intra_eu_acquisition')
      union all
      -- recargo de equivalencia repercutido a clientes minoristas
      select 'output', 'surcharge', r.tax_code, c.equivalence_surcharge_pct, r.tax_base, r.surcharge_amount
      from erp.v_invoice_register r
      join erp.tax_codes c on c.code = r.tax_code
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and r.invoice_type = 'sale' and r.surcharge_amount <> 0
      union all
      -- regularización anual de la prorrata (4T): ajuste del IVA deducido al porcentaje definitivo
      select 'input', 'pro_rata', null, pr.definitive_pct, null, pr.regularization_amount
      from erp.pro_rata pr
      join erp.journal_entries je on je.id = pr.entry_id
      where pr.company_id = p_company and pr.tax_type = p_tax_type and je.posting_date between v_start and v_end
    ) x
    group by 1, 2, 3, 4
  ) b;

  -- 3) Cuotas a compensar de periodos anteriores
  select coalesce(sum(case when outcome = 'carry_forward' then -final_result else 0 end), 0)
         - coalesce(sum(carry_applied), 0)
    into v_carry
  from erp.tax_settlements
  where company_id = p_company and tax_type = p_tax_type and status = 'posted'
    and (year, quarter) < (p_year, p_quarter);

  v_result := v_out - v_in;
  if v_result > 0 and v_carry > 0 then
    v_applied := least(v_result, v_carry);
  end if;
  v_final := v_result - v_applied;
  v_outcome := case when v_final > 0 then 'payable'
                    when v_final = 0 then 'zero'
                    when p_quarter = 4 and p_refund then 'refund'
                    else 'carry_forward' end;

  -- 4) Líneas de compensación y resultado
  if v_applied > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.receivable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.receivable_account_id), 'debit', 0, 'credit', v_applied);
  end if;
  if v_final > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.payable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.payable_account_id), 'debit', 0, 'credit', v_final);
  elsif v_final < 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.receivable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.receivable_account_id), 'debit', -v_final, 'credit', 0);
  end if;

  return jsonb_build_object(
    'tax_type', p_tax_type, 'year', p_year, 'quarter', p_quarter,
    'form', case p_tax_type when 'VAT' then '303' else '420' end,
    'period_start', v_start, 'period_end', v_end,
    'boxes', v_boxes,
    'output_tax', v_out, 'input_tax', v_in,
    'register_output', v_reg_out, 'register_input', v_reg_in,
    -- Cuadre auditor: el libro registro debe coincidir con la contabilidad
    'difference', (v_out - v_in) - (v_reg_out - v_reg_in),
    'result', v_result, 'carry_available', v_carry, 'carry_applied', v_applied,
    'final_result', v_final, 'outcome', v_outcome,
    'can_refund', p_quarter = 4 and v_final < 0,
    'lines', v_lines,
    'settled', v_done.id is not null, 'settlement_id', v_done.id);
end $function$;

-- ---------- El impuesto de la empresa (el del territorio) ----------
create or replace function erp.company_tax_type(p_company uuid)
returns text language sql stable as $$
  select case tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies where id = p_company;
$$;
revoke execute on function erp.company_tax_type(uuid) from anon, public;
grant execute on function erp.company_tax_type(uuid) to authenticated;

-- ---------- Devengado y deducible a varias fechas, en una pasada ----------
-- Primero los apuntes de las cuentas de impuesto (pocos, por su índice), después sus asientos: así no se recorre el
-- diario entero, y la comprobación de «¿es un asiento de liquidación o del cierre?» se hace solo en esos asientos.
create or replace function erp.tax_moves_at(p_company uuid, p_year integer, p_dates date[])
returns table(at date, output_tax numeric, input_tax numeric)
language sql stable security definer set search_path = erp, public as $$
  with acc as (
    select a.id, a.side from erp.tax_accounts(p_company, erp.company_tax_type(p_company)) a where erp.can_report(p_company)
  ), lin as (
    select l.entry_id, acc.side, sum(l.debit - l.credit) as amt
    from acc join erp.journal_lines l on l.gl_account_id = acc.id and l.company_id = p_company
    group by l.entry_id, acc.side
  ), ent as (
    select e.id, e.posting_date
    from erp.journal_entries e
    where e.id in (select entry_id from lin)
      and e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
      and erp.counts_in_reports(e.status, e.id) and not erp.is_settlement_entry(e.id)
  ), per_day as (
    select e.posting_date, sum(-l.amt) filter (where l.side = 'output') as o, sum(l.amt) filter (where l.side = 'input') as i
    from ent e join lin l on l.entry_id = e.id
    group by e.posting_date
  )
  select d.at, coalesce(sum(p.o), 0), coalesce(sum(p.i), 0)
  from (select distinct x as at from unnest(p_dates) x) d
  left join per_day p on d.at is null or p.posting_date <= d.at
  group by d.at;
$$;
revoke execute on function erp.tax_moves_at(uuid, integer, date[]) from anon, public;
grant execute on function erp.tax_moves_at(uuid, integer, date[]) to authenticated;

-- ---------- Cargos y abonos de unas cuentas a varias fechas (sin apertura ni cierre) ----------
create or replace function erp.account_moves_at(p_company uuid, p_year integer, p_dates date[], p_prefixes text[])
returns table(at date, prefix text, debit numeric, credit numeric)
language sql stable security definer set search_path = erp, public as $$
  with acc as (
    select g.id, p.prefix
    from erp.gl_accounts g join unnest(p_prefixes) p(prefix) on g.account_no like p.prefix || '%'
    where g.company_id = p_company and erp.can_report(p_company)
  ), per_day as (
    select a.prefix, e.posting_date, sum(l.debit) as dr, sum(l.credit) as cr
    from acc a
    join erp.journal_lines l on l.gl_account_id = a.id and l.company_id = p_company
    join erp.journal_entries e on e.id = l.entry_id
    where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
      and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
    group by a.prefix, e.posting_date
  )
  select d.at, p.prefix, coalesce(sum(m.dr), 0), coalesce(sum(m.cr), 0)
  from (select distinct x as at from unnest(p_dates) x) d
  cross join unnest(p_prefixes) p(prefix)
  left join per_day m on m.prefix = p.prefix and (d.at is null or m.posting_date <= d.at)
  group by d.at, p.prefix;
$$;
revoke execute on function erp.account_moves_at(uuid, integer, date[], text[]) from anon, public;
grant execute on function erp.account_moves_at(uuid, integer, date[], text[]) to authenticated;

-- ---------- Catálogo: los tipos nuevos ----------
alter table erp.dash_metrics drop constraint if exists dash_metrics_flow_check;
alter table erp.dash_metrics add constraint dash_metrics_flow_check check (flow in ('in', 'out', 'output', 'input', 'debit', 'credit'));
comment on column erp.dash_metrics.flow is
  'kind cash: in / out (entradas o salidas de las 57). kind tax: output / input (devengado o deducible). '
  'kind move: debit / credit (cargos o abonos de account_prefix).';
alter table erp.dash_metrics drop constraint if exists dash_metrics_kind_check;
alter table erp.dash_metrics add constraint dash_metrics_kind_check
  check (kind in ('line', 'group', 'sum', 'diff', 'ratio', 'cash', 'days', 'tax', 'move'));
alter table erp.dash_metrics drop constraint if exists dash_metrics_check;
alter table erp.dash_metrics add constraint dash_metrics_check
  check ((kind = 'line'  and statement is not null and line_code is not null)
      or (kind = 'group' and account_prefix is not null and sign is not null)
      -- «flow in (…)» con flow vacío da NULL y una restricción con NULL se da por buena: hace falta «is not null»
      or (kind = 'cash'  and flow is not null and flow in ('in', 'out'))
      or (kind = 'tax'   and flow is not null and flow in ('output', 'input'))
      or (kind = 'move'  and account_prefix is not null and flow is not null and flow in ('debit', 'credit'))
      or (kind in ('sum', 'diff', 'ratio', 'days') and a is not null and b is not null));
alter table erp.dash_widgets drop constraint if exists dash_widgets_mode_check;
alter table erp.dash_widgets add constraint dash_widgets_mode_check check (mode in ('end', 'month', 'quarter'));
alter table erp.dash_widgets drop constraint if exists dash_widgets_quarter_kind;
alter table erp.dash_widgets add constraint dash_widgets_quarter_kind check (mode <> 'quarter' or kind = 'bars');

-- ---------- Las métricas a varias fechas, con los tipos nuevos ----------
create or replace function erp.dash_metric_values(p_company uuid, p_year integer, p_dates date[])
returns table(at date, v jsonb) language plpgsql stable set jit to 'off' as $$
#variable_conflict use_column
declare
  bal jsonb; pyg jsonb; grp jsonb; csh jsonb; tax jsonb; mov jsonb; vals jsonb; m erp.dash_metrics;
  x numeric; va numeric; vb numeric; d date; v_start date; v_end date; days int; prefixes text[];
begin
  select fy.starting_date, fy.ending_date into v_start, v_end from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year;
  -- { fecha: { partida: importe } } del Balance y de la PyG, y { fecha: { cuenta: saldo } } de la PyG (los grupos)
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into bal
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'balance', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into pyg
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'pyg', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into grp
  from (select c.at, jsonb_object_agg(c.account_no, c.balance) m from erp.fs_classified_at(p_company, p_year, 'pyg', p_dates) c group by c.at) z;
  -- 0081: { fecha: { in, out } } de la tesorería; 0082: { fecha: { output, input } } del impuesto y
  -- { fecha: { prefijo: { debit, credit } } } de las cuentas. Cada uno, solo si alguna métrica lo usa.
  csh := '{}'; tax := '{}'; mov := '{}';
  if exists (select 1 from erp.dash_metrics where kind = 'cash') then
    select coalesce(jsonb_object_agg(coalesce(c.at::text, '-'), jsonb_build_object('in', c.cash_in, 'out', c.cash_out)), '{}') into csh
    from erp.cash_moves_at(p_company, p_year, p_dates) c;
  end if;
  if exists (select 1 from erp.dash_metrics where kind = 'tax') then
    select coalesce(jsonb_object_agg(coalesce(t.at::text, '-'), jsonb_build_object('output', t.output_tax, 'input', t.input_tax)), '{}') into tax
    from erp.tax_moves_at(p_company, p_year, p_dates) t;
  end if;
  select array_agg(distinct account_prefix) into prefixes from erp.dash_metrics where kind = 'move';
  if prefixes is not null then
    select coalesce(jsonb_object_agg(z.at, z.m), '{}') into mov
    from (select coalesce(a.at::text, '-') as at, jsonb_object_agg(a.prefix, jsonb_build_object('debit', a.debit, 'credit', a.credit)) m
          from erp.account_moves_at(p_company, p_year, p_dates, prefixes) a group by a.at) z;
  end if;

  foreach d in array (select array_agg(distinct x) from unnest(p_dates) x) loop
    vals := '{}';
    -- 0081: días transcurridos del ejercicio hasta la fecha (como mucho 365: al cierre, el × 365 de Ratios)
    days := least(coalesce(least(d, v_end), v_end) - v_start + 1, 365);
    for m in select * from erp.dash_metrics order by sort loop
      if m.kind = 'line' then
        -- 0080: con signo (-1 = el gasto en positivo)
        x := coalesce(m.sign, 1)
             * coalesce(((case m.statement when 'balance' then bal else pyg end) -> coalesce(d::text, '-') ->> m.line_code)::numeric, 0);
      elsif m.kind = 'group' then
        select m.sign * coalesce(sum(e.value::numeric), 0) into x
        from jsonb_each_text(coalesce(grp -> coalesce(d::text, '-'), '{}')) e where e.key like m.account_prefix || '%';
      elsif m.kind = 'cash' then
        x := coalesce((csh -> coalesce(d::text, '-') ->> m.flow)::numeric, 0);
      elsif m.kind = 'tax' then
        x := coalesce((tax -> coalesce(d::text, '-') ->> m.flow)::numeric, 0);
      elsif m.kind = 'move' then
        x := coalesce((mov -> coalesce(d::text, '-') -> m.account_prefix ->> m.flow)::numeric, 0);
      else
        va := (vals ->> m.a)::numeric; vb := (vals ->> m.b)::numeric;
        x := case m.kind when 'sum' then va + vb when 'diff' then va - vb
                         when 'days' then case when vb is null or vb = 0 or days <= 0 then null else round(va * days / vb, 4) end
                         else case when vb is null or vb = 0 then null else round(va / vb, 4) end end;
      end if;
      vals := vals || jsonb_build_object(m.code, x);
    end loop;
    at := d; v := vals; return next;
  end loop;
end $$;

-- ---------- El tablero, con las series por trimestre ----------
-- Lo de cada trimestre natural = acumulado a su fin de mes 3, 6, 9 o 12 − el del trimestre anterior. Con «hasta» a mitad
-- de trimestre, ese trimestre llega hasta la fecha (el acumulado a «hasta»); los siguientes, sin dato.
create or replace function erp.dash_quarters(p_months date[], p_series jsonb, p_cur jsonb, p_to date, p_code text)
returns jsonb language sql immutable as $$
  with q as (
    select extract(quarter from e)::int as qn, e, (p_series -> (n::int - 1)) as v
    from unnest(p_months) with ordinality m(e, n)
  ), acum as (
    select qn,
           -- el acumulado a fin de trimestre: el de su último mes si tiene dato o, si «hasta» cae dentro, el de «hasta»
           case when (array_agg(v order by e desc))[1] is not null and (array_agg(v order by e desc))[1] <> 'null'::jsonb then
                  ((array_agg(v order by e desc))[1] ->> p_code)::numeric
                when p_to is not null and p_cur is not null and p_to between date_trunc('quarter', max(e))::date and max(e) then
                  (p_cur ->> p_code)::numeric
           end as a
    from q group by qn
  ), d as (
    select qn, a, a - coalesce(lag(a) over (order by qn), 0) as v from acum
  )
  select coalesce(jsonb_agg(case when a is null then null else to_jsonb(v) end order by qn), '[]') from d;
$$;

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
  select coalesce(jsonb_agg(jsonb_build_object(
           'sort', w.sort, 'kind', w.kind, 'size', w.size, 'mode', w.mode, 'label', w.label, 'label_en', w.label_en,
           'help', w.help, 'help_en', w.help_en,
           'items', (select jsonb_agg(jsonb_build_object(
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
    'simulation', p_drafts, 'months', to_jsonb(ends), 'months_prev', to_jsonb(ends0), 'widgets', widgets,
    'tax_type', erp.company_tax_type(p_company));   -- 0082: VAT o IGIC, para los títulos
end $$;

-- ---------- Métricas ----------
insert into erp.dash_metrics (code, sort, label, label_en, unit, kind, statement, line_code, account_prefix, sign, flow, a, b, ratio_code, link, help, help_en) values
 ('TAX_OUT',  600, 'Cuotas devengadas', 'Output tax', 'eur', 'tax', null, null, null, null, 'output', null, null, null, 'settlement',
  'IVA / IGIC repercutido (y autorrepercutido) desde el 1 de enero: el saldo acreedor de las cuentas de repercutido, sin las liquidaciones ni el cierre.',
  'Output VAT / IGIC since 1 January: the credit balance of the output tax accounts, without settlements or closing entries.'),
 ('TAX_IN',   610, 'Cuotas deducibles', 'Input tax', 'eur', 'tax', null, null, null, null, 'input', null, null, null, 'settlement',
  'IVA / IGIC soportado deducible desde el 1 de enero: el saldo deudor de las cuentas de soportado, sin las liquidaciones ni el cierre.',
  'Deductible input VAT / IGIC since 1 January: the debit balance of the input tax accounts, without settlements or closing entries.'),
 ('TAX_RES',  620, 'Resultado de las liquidaciones', 'Tax result', 'eur', 'diff', null, null, null, null, null, 'TAX_OUT', 'TAX_IN', null, 'settlement',
  'Devengadas − deducibles: a ingresar si es positivo, a compensar o devolver si es negativo (antes de compensar trimestres anteriores).',
  'Output − input: payable if positive, to carry forward or refund if negative (before offsetting previous quarters).'),
 ('WHT_OUT',  630, 'Retenciones practicadas', 'Withholdings made', 'eur', 'move', null, null, '4751', null, 'credit', null, null, null, 'withholdings',
  'Lo retenido a profesionales, arrendadores, empleados y socios (abonos de la 4751), a ingresar con los modelos 111, 115 y 123.',
  'What was withheld from professionals, landlords, employees and shareholders (credits to 4751), paid with forms 111, 115 and 123.'),
 ('WHT_IN',   640, 'Retenciones soportadas', 'Withholdings suffered', 'eur', 'move', null, null, '473', null, 'debit', null, null, null, 'withholdings',
  'Lo que han retenido a la empresa (cargos de la 473): un pago a cuenta del Impuesto sobre Sociedades.',
  'What was withheld from the company (debits to 473): a payment on account of corporate income tax.'),
 ('TAX_RATE', 650, 'Tipo medio repercutido', 'Average output tax rate', 'pct', 'ratio', null, null, null, null, null, 'TAX_OUT', 'SALES', null, 'settlement',
  'Cuotas devengadas / cifra de negocios. Incluye las autorrepercusiones (inversión del sujeto pasivo, adquisiciones intracomunitarias), que no son ventas.',
  'Output tax / revenue. It includes self-assessed tax (reverse charge, intra-EU acquisitions), which is not sales.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en, unit = excluded.unit,
  kind = excluded.kind, statement = excluded.statement, line_code = excluded.line_code, account_prefix = excluded.account_prefix,
  sign = excluded.sign, flow = excluded.flow, a = excluded.a, b = excluded.b, ratio_code = excluded.ratio_code, link = excluded.link,
  help = excluded.help, help_en = excluded.help_en;

-- ---------- El tablero ----------
insert into erp.dashboards (code, sort, label, label_en, description, description_en) values
 ('impuestos', 40, 'Impuestos', 'Taxes',
  'El IVA / IGIC devengado y deducible de cada trimestre (lo mismo que la liquidación), lo que toca ingresar o compensar y las retenciones.',
  'Output and input VAT / IGIC by quarter (the same as the tax return), what is payable or to carry forward, and withholdings.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en,
  description = excluded.description, description_en = excluded.description_en;

delete from erp.dash_widgets where dashboard = 'impuestos';
insert into erp.dash_widgets (dashboard, sort, kind, size, mode, label, label_en, help, help_en, metrics) values
 ('impuestos', 10, 'kpis',  'full', 'end',     'Cifras clave', 'Key figures', null, null, array['TAX_OUT', 'TAX_IN', 'TAX_RES', 'WHT_OUT']),
 ('impuestos', 20, 'bars',  'full', 'quarter', 'Devengado y deducible de cada trimestre', 'Output and input tax by quarter',
  'Lo mismo que cada liquidación: el movimiento de las cuentas de impuesto del trimestre, sin la liquidación ni el cierre.',
  'The same as each tax return: the movement of the tax accounts in the quarter, without the settlement or closing entries.',
  array['TAX_OUT', 'TAX_IN']),
 ('impuestos', 30, 'bars',  'half', 'quarter', 'Resultado de cada trimestre', 'Result by quarter',
  'Positivo, a ingresar; negativo, a compensar (o a devolver en el 4T). Antes de compensar trimestres anteriores.',
  'Positive, payable; negative, to carry forward (or refund in Q4). Before offsetting previous quarters.', array['TAX_RES']),
 ('impuestos', 40, 'bars',  'half', 'quarter', 'Retenciones de cada trimestre', 'Withholdings by quarter',
  'Practicadas (a ingresar con los modelos 111, 115 y 123) y soportadas (a cuenta del Impuesto sobre Sociedades).',
  'Made (paid with forms 111, 115 and 123) and suffered (on account of corporate income tax).', array['WHT_OUT', 'WHT_IN']),
 ('impuestos', 50, 'table', 'full', 'end',     'Resumen del año', 'Year summary',
  'Del 1 de enero a la fecha, frente al año anterior a la misma fecha.', 'From 1 January to the date, against the previous year.',
  array['TAX_OUT', 'TAX_IN', 'TAX_RES', 'WHT_OUT', 'WHT_IN', 'TAX_RATE']);

notify pgrst, 'reload schema';
