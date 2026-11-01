-- =====================================================================
-- 0081 · Tablero «Tesorería y circulante» (v0.54.0 · ADR 0054)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.54.0.md, 01-11-2026): todas las entradas y salidas de tesorería, periodos
-- medios con los días transcurridos del ejercicio y el «vencido» para la v0.57.0.
--
--   · TIPO DE MÉTRICA «cash»: lo que entra (flow 'in') o sale (flow 'out') de las cuentas 57 desde el inicio del
--     ejercicio hasta la fecha, asiento a asiento (como el EFE, erp.cf_entry_cash), sin la apertura ni el cierre.
--     Un traspaso entre cuentas de tesorería (572 → 570) suma cero en su asiento: no es ni entrada ni salida.
--     entradas − salidas = tesorería a la fecha − tesorería de apertura (la variación de efectivo del EFE).
--   · TIPO DE MÉTRICA «days»: a / b × días transcurridos del ejercicio hasta la fecha (como mucho 365). Al cierre es el
--     periodo medio de la pantalla Ratios (× 365); a mitad de año no se infla.
--   · El tablero y sus 5 tarjetas, con 11 métricas nuevas.
--
-- Se puede ejecutar dos veces.
-- =====================================================================

-- ---------- Catálogo: los tipos nuevos ----------
alter table erp.dash_metrics add column if not exists flow text;
alter table erp.dash_metrics drop constraint if exists dash_metrics_flow_check;
alter table erp.dash_metrics add constraint dash_metrics_flow_check check (flow in ('in', 'out'));
comment on column erp.dash_metrics.flow is 'kind cash: in = entradas en las cuentas 57; out = salidas.';

alter table erp.dash_metrics drop constraint if exists dash_metrics_unit_check;
alter table erp.dash_metrics add constraint dash_metrics_unit_check check (unit in ('eur', 'pct', 'ratio', 'days'));
alter table erp.dash_metrics drop constraint if exists dash_metrics_kind_check;
alter table erp.dash_metrics add constraint dash_metrics_kind_check
  check (kind in ('line', 'group', 'sum', 'diff', 'ratio', 'cash', 'days'));
alter table erp.dash_metrics drop constraint if exists dash_metrics_check;
alter table erp.dash_metrics add constraint dash_metrics_check
  check ((kind = 'line'  and statement is not null and line_code is not null)
      or (kind = 'group' and account_prefix is not null and sign is not null)
      or (kind = 'cash'  and flow is not null)
      or (kind in ('sum', 'diff', 'ratio', 'days') and a is not null and b is not null));

-- ---------- Entradas y salidas de tesorería a varias fechas, en una pasada ----------
-- Lo que mueve cada asiento en las cuentas 57 (la misma regla que erp.cf_entry_cash), sumado por día una vez; después,
-- lo acumulado a cada fecha. Solo los asientos de la empresa y del ejercicio, con la regla de qué cuenta en un informe
-- (también la simulación con los asientos en edición, 0074).
create or replace function erp.cash_moves_at(p_company uuid, p_year integer, p_dates date[])
returns table(at date, cash_in numeric, cash_out numeric)
language sql stable security definer set search_path = erp, public as $$
  with ent as (
    select e.id, e.posting_date
    from erp.journal_entries e
    where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
      and e.company_id = p_company and erp.counts_in_reports(e.status, e.id)
      and e.entry_type = 'normal' and erp.can_report(p_company)
    offset 0
  ), per_entry as (
    select e.posting_date, sum(l.debit - l.credit) as cash
    from ent e
    join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company
    join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
    group by e.id, e.posting_date
  ), per_day as (
    select posting_date, sum(greatest(cash, 0)) as cin, sum(greatest(-cash, 0)) as cout
    from per_entry group by posting_date
  )
  select d.at, coalesce(sum(p.cin), 0), coalesce(sum(p.cout), 0)
  from (select distinct x as at from unnest(p_dates) x) d
  left join per_day p on d.at is null or p.posting_date <= d.at
  group by d.at;
$$;
revoke execute on function erp.cash_moves_at(uuid, integer, date[]) from anon, public;
grant execute on function erp.cash_moves_at(uuid, integer, date[]) to authenticated;

-- ---------- Las métricas a varias fechas, con los tipos nuevos ----------
create or replace function erp.dash_metric_values(p_company uuid, p_year integer, p_dates date[])
returns table(at date, v jsonb) language plpgsql stable set jit to 'off' as $$
#variable_conflict use_column
declare
  bal jsonb; pyg jsonb; grp jsonb; csh jsonb; vals jsonb; m erp.dash_metrics; x numeric; va numeric; vb numeric; d date;
  v_start date; v_end date; days int;
begin
  select fy.starting_date, fy.ending_date into v_start, v_end from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year;
  -- { fecha: { partida: importe } } del Balance y de la PyG, y { fecha: { cuenta: saldo } } de la PyG (los grupos)
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into bal
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'balance', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into pyg
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'pyg', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into grp
  from (select c.at, jsonb_object_agg(c.account_no, c.balance) m from erp.fs_classified_at(p_company, p_year, 'pyg', p_dates) c group by c.at) z;
  -- 0081: { fecha: { in, out } } de la tesorería, solo si alguna métrica la usa
  csh := '{}';
  if exists (select 1 from erp.dash_metrics where kind = 'cash') then
    select coalesce(jsonb_object_agg(coalesce(c.at::text, '-'), jsonb_build_object('in', c.cash_in, 'out', c.cash_out)), '{}') into csh
    from erp.cash_moves_at(p_company, p_year, p_dates) c;
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

-- ---------- Métricas ----------
insert into erp.dash_metrics (code, sort, label, label_en, unit, kind, statement, line_code, account_prefix, sign, flow, a, b, ratio_code, link, help, help_en) values
 ('CUST',     400, 'Clientes pendientes de cobro', 'Trade receivables', 'eur', 'line', 'balance', 'AC.II.1', null, null, null, null, null, null, 'payments',
  'Lo que deben los clientes a la fecha, menos su deterioro (partida «Clientes» del Balance).',
  'What customers owe at the date, less impairment (Trade receivables line of the balance sheet).'),
 ('SUPP',     410, 'Proveedores pendientes de pago', 'Trade payables', 'eur', 'line', 'balance', 'PC.IV.1', null, null, null, null, null, null, 'payments',
  'Lo que se debe a los proveedores a la fecha (partida «Proveedores» del Balance).',
  'What is owed to suppliers at the date (Suppliers line of the balance sheet).'),
 ('INV',      420, 'Existencias', 'Inventories', 'eur', 'line', 'balance', 'AC.I', null, null, null, null, null, null, 'balance', null, null),
 ('CASH_IN',  430, 'Entradas de tesorería', 'Cash inflows', 'eur', 'cash', null, null, null, null, 'in', null, null, null, 'cashflow',
  'Todo lo que entra en bancos y caja (cuentas 57): cobros, préstamos recibidos, aportaciones… Sin los traspasos entre cuentas de tesorería.',
  'Everything that comes into bank and cash (accounts 57): receipts, loans received, contributions… Without transfers between cash accounts.'),
 ('CASH_OUT', 440, 'Salidas de tesorería', 'Cash outflows', 'eur', 'cash', null, null, null, null, 'out', null, null, null, 'cashflow',
  'Todo lo que sale de bancos y caja (cuentas 57): pagos a proveedores, nóminas, impuestos, cuotas de préstamos… Sin los traspasos.',
  'Everything that leaves bank and cash (accounts 57): payments to suppliers, payroll, taxes, loan instalments… Without transfers.'),
 ('CASH_NET', 450, 'Variación de la tesorería', 'Change in cash', 'eur', 'diff', null, null, null, null, null, 'CASH_IN', 'CASH_OUT', null, 'cashflow',
  'Entradas − salidas: lo que ha subido o bajado la tesorería en el ejercicio (la variación de efectivo del EFE).',
  'Inflows − outflows: how much cash has gone up or down in the year (the change in cash of the cash flow statement).'),
 ('QA',       460, 'Activo corriente sin existencias', 'Quick assets', 'eur', 'diff', null, null, null, null, null, 'CA', 'INV', null, 'balance', null, null),
 ('QR',       470, 'Prueba ácida', 'Quick ratio', 'ratio', 'ratio', null, null, null, null, null, 'QA', 'CL', 'QR', 'ratios',
  '(Activo corriente − existencias) / pasivo corriente: si se pagan las deudas a corto sin vender el almacén.',
  '(Current assets − inventories) / current liabilities.'),
 ('CASHR',    480, 'Disponibilidad', 'Cash ratio', 'ratio', 'ratio', null, null, null, null, null, 'CASH', 'CL', 'CASH', 'ratios',
  'Tesorería / pasivo corriente: qué parte de las deudas a corto se podría pagar hoy.', 'Cash / current liabilities.'),
 ('DSO',      490, 'Periodo medio de cobro', 'Days sales outstanding', 'days', 'days', null, null, null, null, null, 'CUST', 'SALES', 'DSO', 'ratios',
  'Clientes / ventas × días transcurridos del ejercicio: cuántos días se tarda en cobrar.',
  'Receivables / revenue × days elapsed in the year: how many days it takes to collect.'),
 ('DPO',      500, 'Periodo medio de pago', 'Days payable outstanding', 'days', 'days', null, null, null, null, null, 'SUPP', 'PROC', 'DPO', 'ratios',
  'Proveedores / aprovisionamientos × días transcurridos del ejercicio: cuántos días se tarda en pagar.',
  'Payables / procurements × days elapsed in the year: how many days it takes to pay.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en, unit = excluded.unit,
  kind = excluded.kind, statement = excluded.statement, line_code = excluded.line_code, account_prefix = excluded.account_prefix,
  sign = excluded.sign, flow = excluded.flow, a = excluded.a, b = excluded.b, ratio_code = excluded.ratio_code, link = excluded.link,
  help = excluded.help, help_en = excluded.help_en;

-- ---------- El tablero ----------
insert into erp.dashboards (code, sort, label, label_en, description, description_en) values
 ('tesoreria', 30, 'Tesorería y circulante', 'Cash and working capital',
  'Cuánto dinero hay, cuánto deben los clientes, cuánto se debe a los proveedores y si llega para el corto plazo.',
  'How much cash there is, what customers owe, what is owed to suppliers and whether it covers the short term.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en,
  description = excluded.description, description_en = excluded.description_en;

delete from erp.dash_widgets where dashboard = 'tesoreria';
insert into erp.dash_widgets (dashboard, sort, kind, size, mode, label, label_en, help, help_en, metrics) values
 ('tesoreria', 10, 'kpis',  'full', 'end',   'Cifras clave', 'Key figures', null, null, array['CASH', 'CUST', 'SUPP', 'WC']),
 ('tesoreria', 20, 'bars',  'full', 'month', 'Entradas y salidas de tesorería de cada mes', 'Cash inflows and outflows by month',
  'Lo que entró y salió de bancos y caja cada mes, sin los traspasos entre cuentas. Por actividades, en el estado de flujos.',
  'What came into and left bank and cash each month, without transfers. By activity, in the cash flow statement.',
  array['CASH_IN', 'CASH_OUT']),
 ('tesoreria', 30, 'lines', 'half', 'end',   'Tesorería a fin de mes', 'Cash at month end',
  'El saldo de las cuentas 57 a cada fin de mes, frente al año anterior.', 'Accounts 57 at each month end, against last year.',
  array['CASH']),
 ('tesoreria', 40, 'lines', 'half', 'end',   'Fondo de maniobra a fin de mes', 'Working capital at month end',
  'Activo corriente − pasivo corriente a cada fin de mes, frente al año anterior.', 'Current assets − current liabilities at each month end.',
  array['WC']),
 ('tesoreria', 50, 'table', 'full', 'end',   'Liquidez y plazos', 'Liquidity and terms',
  'Con la zona de referencia de los Ratios. Los periodos medios, con los días transcurridos del ejercicio.',
  'With the reference range of the Ratios screen. Average periods use the days elapsed in the year.',
  array['CR', 'QR', 'CASHR', 'DSO', 'DPO']);

notify pgrst, 'reload schema';
