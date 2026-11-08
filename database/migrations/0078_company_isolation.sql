-- =====================================================================
-- 0078 · Cada empresa, independiente del tamaño de las demás (v0.52.3)
-- ---------------------------------------------------------------------
-- En Supabase, Comprobaciones de una empresa importada grande seguía tardando 12–20 s con la 0077 (en local, 0,7 s con los mismos
-- datos). Medido allí pieza a pieza: erp.audit_lines tardaba 2,4 s (70 ms en local) y Comprobaciones la usa 7 veces.
-- Reproducido en local con PostgreSQL 17.6 (el de Supabase) y varias empresas grandes en la misma base:
--
--   · erp.audit_lines y varias consultas de los informes recorrían los apuntes y asientos de TODA la base (las demás
--     empresas incluidas): con una empresa sola no se nota; con varias grandes y el disco de Supabase, sí.
--     Ahora: audit_lines lee los apuntes asiento a asiento (por su índice) y el origen «importado» sin cruzar con
--     todos los asientos; las demás consultas filtran también los apuntes por la empresa (journal_lines.company_id).
--   · erp.run_audit_checks comprueba el permiso UNA vez (erp.can_report) en lugar de la seguridad fila a fila en cada
--     consulta (en Supabase, contar los asientos de un ejercicio fila a fila: 929 ms frente a 63 ms en local), y
--     calcula erp.audit_lines una sola vez para todas sus comprobaciones (antes, 7 veces).
--   · Afecta a: Comprobaciones (también la antigüedad de saldos de los terceros), balance y PyG, estado de flujos, ratios, tablero, Inicio y comprobaciones de integridad.
--
-- Mismos resultados (comprobado con Empresa 1 y el caso completo). En local, Empresa 1 con otras dos empresas grandes
-- en la base: Comprobaciones, de 2,5 s a 0,8 s. Se puede ejecutar dos veces.
-- =====================================================================


-- Un apunte con su origen (lo que devuelve erp.audit_lines), para guardarlo en una variable y no recalcularlo
do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'erp' and t.typname = 'audit_line') then
    create type erp.audit_line as (entry_id uuid, entry_no integer, posting_date date, k uuid, source text, account_no text,
                                   account_name text, debit numeric, credit numeric, tax_code text);
  end if;
end $$;

CREATE OR REPLACE FUNCTION erp.audit_lines(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(entry_id uuid, entry_no integer, posting_date date, k uuid, source text, account_no text, account_name text, debit numeric, credit numeric, tax_code text)
 LANGUAGE sql
 STABLE SECURITY DEFINER ROWS 20000
 SET search_path TO 'erp', 'public'
AS $function$
  with docs as (
    select i.entry_id as k, 1 as p, 'invoice' as s from erp.invoices i where i.company_id = p_company
    union all select s.entry_id, 2, 'settlement' from erp.tax_settlements s where s.company_id = p_company
    union all select p.entry_id, 3, 'pro_rata' from erp.pro_rata p where p.company_id = p_company
    -- v0.36.0: periodificaciones y deterioros (antes que los cobros: la insolvencia firme también lo es)
    union all select x, 4, 'accrual' from erp.accruals ac, unnest(array[ac.entry_id, ac.reversal_entry_id]) x where ac.company_id = p_company
    union all select x, 5, 'impairment' from erp.receivable_impairments ri, unnest(array[ri.entry_id, ri.end_entry_id]) x where ri.company_id = p_company
    union all select w.entry_id, 5, 'impairment' from erp.receivable_writeoffs w where w.company_id = p_company
    -- v0.37.0: provisiones · v0.36.0: existencias
    union all select pm.entry_id, 6, 'provision' from erp.provision_movements pm where pm.company_id = p_company
    union all select ic.entry_id, 7, 'inventory' from erp.inventory_counts ic where ic.company_id = p_company
    -- v0.41.0: Impuesto sobre Sociedades · v0.42.0: operaciones societarias
    union all select x, 8, 'corporate_tax' from erp.corporate_tax_returns ct, unnest(array[ct.current_entry_id, ct.deferred_entry_id]) x where ct.company_id = p_company
    union all select x, 9, 'equity' from erp.equity_operations eo, unnest(eo.entry_ids) x where eo.company_id = p_company
    -- v0.43.0: préstamos y arrendamiento financiero · v0.44.0: subvenciones
    union all select le.entry_id, 10, 'financing' from erp.loan_events le where le.company_id = p_company
    union all select ge.entry_id, 11, 'grant' from erp.grant_events ge where ge.company_id = p_company
    -- v0.38.0: nóminas y sus pagos
    union all select x, 12, 'payroll' from erp.payroll_runs pr, unnest(array[pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id]) x where pr.company_id = p_company
    union all select x, 13, 'payment' from erp.payments py, unnest(array[py.entry_id, py.cancel_entry_id]) x where py.company_id = p_company and not py.linked
    union all select d.entry_id, 14, 'asset' from erp.asset_depreciations d where d.company_id = p_company
    union all select fa.disposal_entry_id, 14, 'asset' from erp.fixed_assets fa where fa.company_id = p_company
    union all select ae.entry_id, 14, 'asset' from erp.asset_events ae where ae.company_id = p_company
  ), src as (
    select d.k, (array_agg(d.s order by d.p))[1] as s from docs d where d.k is not null group by d.k
  )
  select e.id, e.entry_no, e.posting_date, coalesce(e.reversal_of, e.id),
         coalesce(src.s, case when (case when e.reversal_of is null then e.import_batch_id
                                         else (select o.import_batch_id from erp.journal_entries o where o.id = e.reversal_of) end)
                                   is not null then 'import' else 'manual' end),
         l.account_no, l.name, l.debit, l.credit, l.tax_code
  -- primero los asientos del ejercicio (por su índice) y después los apuntes de cada asiento (por su índice):
  -- v0.52.3 · así no se recorren los apuntes ni los asientos de toda la base, que crecen con las demás empresas
  from (select e.* from erp.journal_entries e
        where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
          and e.company_id = p_company and e.status = 'posted' and e.entry_type = 'normal'
          and (p_to_date is null or e.posting_date <= p_to_date) and erp.can_report(p_company)
        offset 0) e
  left join src on src.k = coalesce(e.reversal_of, e.id)
  cross join lateral (
    select g.account_no, g.name, jl.debit, jl.credit, jl.tax_code
    from erp.journal_lines jl join erp.gl_accounts g on g.id = jl.gl_account_id
    where jl.entry_id = e.id
    offset 0) l
$function$;

CREATE OR REPLACE FUNCTION erp.fs_classified_at(p_company uuid, p_year integer, p_statement text, p_dates date[])
 RETURNS TABLE(at date, account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with ent as (
    -- v0.52.2: primero los asientos del ejercicio (por su índice) y después sus apuntes: así no se recorre el diario
    -- entero de la empresa (con años de historia, la mayor parte es de otros ejercicios)
    select e.id, e.posting_date
    from erp.journal_entries e
    where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
      and e.company_id = p_company and erp.counts_in_reports(e.status, e.id)
      and e.entry_type not in ('closing_pl', 'closing') and erp.can_report(p_company)
    offset 0
  ), mov as (
    select g.account_no, g.name, g.name_en, e.posting_date, sum(l.debit - l.credit) as amt
    from ent e
    join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company   -- v0.52.3: solo los de la empresa
    join erp.gl_accounts g   on g.id = l.gl_account_id
    where (p_statement = 'balance' or left(g.account_no, 1) in ('6', '7'))
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

CREATE OR REPLACE FUNCTION erp.cf_line_flows(p_company uuid, p_year integer)
 RETURNS TABLE(entry_id uuid, account_no text, account_name text, account_name_en text, flow numeric, home_line text, adjust_line text, direct_line text, in_result boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with base as (
    select l.entry_id, g.id as acc_id, g.account_no, g.name, g.name_en, -sum(l.debit - l.credit) as flow
    -- v0.52.2: primero los asientos del ejercicio (por su índice) y después sus apuntes
    from (select e.id from erp.journal_entries e
          where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
            and e.company_id = p_company and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
          offset 0) e
    join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company   -- v0.52.3
    join erp.gl_accounts g on g.id = l.gl_account_id
    where g.account_no not like '57%'
    group by l.entry_id, g.id, g.account_no, g.name, g.name_en
    having sum(l.debit - l.credit) <> 0),
  -- v0.52.2: la línea de flujos de cada cuenta se busca una vez por cuenta, no una vez por asiento
  maps as (
    select d.account_no, m.home_line, m.adjust_line, m.direct_line
    from (select distinct b.account_no from base b) d cross join lateral erp.cf_account_map(d.account_no) m),
  mb as (
    select b.*, m.home_line, m.adjust_line, m.direct_line from base b join maps m on m.account_no = b.account_no),
  -- a) facturas con bases de inversión o de financiación: la proporción de cada línea sobre la cuenta del tercero
  inv as (
    select i.id as invoice_id, i.entry_id, bp.gl_account_id as partner_acc
    from erp.invoices i join erp.business_partners bp on bp.id = i.partner_id
    where i.company_id = p_company and i.entry_id is not null),
  inv_acc as (
    select inv.invoice_id, inv.partner_acc, l.gl_account_id, -sum(l.debit - l.credit) as flow
    from inv join erp.journal_lines l on l.entry_id = inv.entry_id
    group by inv.invoice_id, inv.partner_acc, l.gl_account_id),
  inv_partner as (
    select invoice_id, flow from inv_acc where gl_account_id = partner_acc and flow <> 0),
  inv_group as (
    select a.invoice_id, m.home_line, m.direct_line, min(g.account_no) as account_no, sum(a.flow) as flow
    from inv_acc a join erp.gl_accounts g on g.id = a.gl_account_id
    cross join lateral erp.cf_account_map(g.account_no) m
    where a.gl_account_id <> a.partner_acc and g.account_no not like '57%' and substr(m.home_line, 2, 1) in ('B', 'C')
    group by a.invoice_id, m.home_line, m.direct_line
    having sum(a.flow) <> 0),
  ratio as (
    select g.invoice_id, g.home_line, g.direct_line, -g.flow / p.flow as r
    from inv_group g join inv_partner p on p.invoice_id = g.invoice_id),
  -- los asientos de cada factura: el suyo, sus anulaciones y sus pagos o cobros (lo aplicado, con el signo del asiento;
  -- en un pago que compensa una factura con su abono, el abono va al revés)
  docs as (
    select inv.invoice_id, inv.entry_id, inv.partner_acc, null::numeric as applied
    from inv where inv.invoice_id in (select invoice_id from ratio)
    union all
    select inv.invoice_id, r.id, inv.partner_acc, null
    from inv join erp.journal_entries r on r.reversal_of = inv.entry_id
    where inv.invoice_id in (select invoice_id from ratio)
    union all
    select inv.invoice_id, x.entry_id, inv.partner_acc, pa.amount * sign(pa.total)
    from inv
    join (select a.*, sum(a.amount) over (partition by a.payment_id) as total from erp.payment_applications a) pa on pa.invoice_id = inv.invoice_id
    join erp.payments p on p.id = pa.payment_id
    cross join lateral (select p.entry_id union select p.cancel_entry_id
                        union select r.id from erp.journal_entries r where r.reversal_of = p.entry_id) x(entry_id)
    where inv.invoice_id in (select invoice_id from ratio) and x.entry_id is not null),
  part as (
    -- la parte de la cuenta del tercero que corresponde a la factura en ese asiento
    select d.invoice_id, mb.entry_id, mb.account_no, mb.name, mb.name_en, mb.home_line, mb.adjust_line, mb.direct_line,
           case when d.applied is null then mb.flow else sign(mb.flow) * d.applied end as flow
    from docs d join mb on mb.entry_id = d.entry_id and mb.acc_id = d.partner_acc),
  moved as (
    select p.entry_id, p.account_no, p.name, p.name_en, p.home_line as from_home, p.adjust_line as from_adjust,
           p.direct_line as from_direct, r.home_line, r.direct_line, round(p.flow * r.r, 2) as amount
    from part p join ratio r on r.invoice_id = p.invoice_id),
  -- b) asientos del impuesto sobre beneficios
  tax_entries as (select distinct mb.entry_id from mb where mb.account_no ~ '^63[038]')
  select mb.entry_id, mb.account_no, mb.name, mb.name_en, mb.flow,
         case when mb.account_no like '1%' and mb.entry_id in (select t.entry_id from tax_entries t) then 'IA4d' else mb.home_line end,
         case when mb.account_no like '1%' and mb.entry_id in (select t.entry_id from tax_entries t) then null else mb.adjust_line end,
         case when mb.account_no like '1%' and mb.entry_id in (select t.entry_id from tax_entries t) then 'DA6' else mb.direct_line end,
         left(mb.account_no, 1) in ('6', '7') and mb.home_line <> 'IA4d'
  from mb
  union all   -- lo que se lleva cada base…
  select m.entry_id, m.account_no, m.name, m.name_en, m.amount, m.home_line, null, m.direct_line, false from moved m where m.amount <> 0
  union all   -- …y lo que deja de estar en la cuenta del tercero
  select m.entry_id, m.account_no, m.name, m.name_en, -m.amount, m.from_home, m.from_adjust, m.from_direct, false from moved m where m.amount <> 0;
$function$;

CREATE OR REPLACE FUNCTION erp.cf_entry_cash(p_company uuid, p_year integer)
 RETURNS TABLE(entry_id uuid, cash numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select l.entry_id, sum(l.debit - l.credit)
  -- v0.52.2: primero los asientos del ejercicio (por su índice) y después sus apuntes
  from (select e.id from erp.journal_entries e
        where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
          and e.company_id = p_company and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
        offset 0) e
  join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company   -- v0.52.3
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  group by l.entry_id;
$function$;

CREATE OR REPLACE FUNCTION erp.cf_cash(p_company uuid, p_year integer)
 RETURNS TABLE(opening numeric, closing numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select coalesce(sum(l.debit - l.credit) filter (where e.entry_type = 'opening'), 0),
         coalesce(sum(l.debit - l.credit) filter (where e.entry_type in ('opening', 'normal')), 0)
  -- v0.52.2: primero los asientos del ejercicio (por su índice) y después sus apuntes
  from (select e.id, e.entry_type from erp.journal_entries e
        where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
          and e.company_id = p_company and erp.counts_in_reports(e.status, e.id)
        offset 0) e
  join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company   -- v0.52.3
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%';
$function$;

CREATE OR REPLACE FUNCTION erp.home_kpis(p_company uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  fy        erp.fiscal_years;
  prev      erp.fiscal_years;
  q_start   date := date_trunc('quarter', p_date)::date;
  v_out     jsonb;
begin
  -- Como el resto de informes (EFE, ratios): se comprueba el permiso una vez y se lee sin RLS fila a fila
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;

  select * into fy from erp.fiscal_years
  where company_id = p_company and p_date between starting_date and ending_date;
  if not found then
    return null;   -- la fecha no cae en ningún ejercicio: no hay nada que enseñar
  end if;
  select * into prev from erp.fiscal_years where company_id = p_company and year = fy.year - 1;

  with agg as (   -- saldo por cuenta y mes del ejercicio hasta la fecha, sin regularización ni cierre
    select a.account_no,
           date_trunc('month', e.posting_date)::date as month,
           sum(l.debit - l.credit) as balance,
           sum(case when e.entry_type = 'opening' then l.debit - l.credit else 0 end) as opening,
           count(distinct e.id) as entries
    from erp.journal_entries e
    join erp.journal_lines   l on l.entry_id = e.id and l.company_id = p_company   -- v0.52.3
    join erp.gl_accounts     a on a.id = l.gl_account_id
    where e.company_id = p_company and e.fiscal_year_id = fy.id and e.status = 'posted'
      and e.posting_date <= p_date and e.entry_type not in ('closing_pl', 'closing')
    group by a.account_no, date_trunc('month', e.posting_date)
  ),
  by_account as (
    select account_no, sum(balance) as balance from agg group by account_no
  ),
  cash_moves as (
    select month, sum(balance) as balance from agg where account_no like '57%' group by month
  ),
  cash_by_month as (   -- tesorería a fin de cada mes: suma acumulada (los meses sin movimientos repiten saldo)
    select m::date as month, sum(coalesce(c.balance, 0)) over (order by m) as balance
    from generate_series(fy.starting_date, date_trunc('month', p_date)::date, interval '1 month') m
    left join cash_moves c on c.month = m::date
  )
  select jsonb_build_object(
    'year', fy.year,
    'date', p_date,
    'entries', (select count(*) from erp.journal_entries
                where company_id = p_company and fiscal_year_id = fy.id and status = 'posted' and posting_date <= p_date),
    'cash', (select coalesce(sum(balance), 0) from by_account where account_no like '57%'),
    'cash_start', (select coalesce(sum(opening), 0) from agg where account_no like '57%'),
    'result', (select coalesce(-sum(balance), 0) from by_account where left(account_no, 1) in ('6', '7')),
    'receivable', (select coalesce(sum(balance), 0) from by_account where account_no like '43%'),
    'receivable_accounts', (select count(*) from by_account where account_no like '43%' and balance > 0.005),
    'payable', (select coalesce(-sum(balance), 0) from by_account where account_no like '40%' or account_no like '41%'),
    'payable_accounts', (select count(*) from by_account
                         where (account_no like '40%' or account_no like '41%') and balance < -0.005),
    'cash_months', (select coalesce(jsonb_agg(jsonb_build_object('month', month, 'balance', balance) order by month), '[]')
                    from cash_by_month)
  ) into v_out;

  -- IVA / IGIC del trimestre: repercutido (477) − soportado (472), sin las liquidaciones (asientos que tocan 4750 / 4700)
  with q as (
    select e.id as entry_id, a.account_no, l.debit, l.credit
    from erp.journal_entries e
    join erp.journal_lines   l on l.entry_id = e.id and l.company_id = p_company   -- v0.52.3
    join erp.gl_accounts     a on a.id = l.gl_account_id
    where e.company_id = p_company and e.fiscal_year_id = fy.id and e.status = 'posted'
      and e.posting_date between q_start and p_date and e.entry_type not in ('closing_pl', 'closing')
  )
  select v_out || jsonb_build_object(
    'quarter', extract(quarter from p_date)::int,
    'tax_output', coalesce(sum(output) filter (where not settlement), 0),
    'tax_input', coalesce(sum(input) filter (where not settlement), 0))
  into v_out
  from (select entry_id,
               sum(case when account_no like '477%' then credit - debit else 0 end) as output,
               sum(case when account_no like '472%' then debit - credit else 0 end) as input,
               bool_or(account_no like '4750%' or account_no like '4700%') as settlement
        from q group by entry_id) per_entry;

  -- Resultado del ejercicio anterior completo (para comparar), también sin regularización ni cierre
  if prev.id is not null then
    v_out := v_out || jsonb_build_object('result_prev', (
      select coalesce(sum(l.credit - l.debit), 0)
      from erp.journal_entries e
      join erp.journal_lines   l on l.entry_id = e.id and l.company_id = p_company   -- v0.52.3
      join erp.gl_accounts     a on a.id = l.gl_account_id
      where e.company_id = p_company and e.fiscal_year_id = prev.id and e.status = 'posted'
        and e.entry_type not in ('closing_pl', 'closing') and left(a.account_no, 1) in ('6', '7')));
  end if;

  return v_out;
end $function$;

CREATE OR REPLACE FUNCTION erp.integrity_checks(p_company uuid, p_year integer)
 RETURNS TABLE(code text, sort integer, status text, expected numeric, actual numeric, detail jsonb, title text, title_en text)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare
  v_fy    erp.fiscal_years;
  v_close erp.year_closings;
  v_n     int;
  v_a     numeric;
  v_b     numeric;
  v_c     numeric;
  v_d     numeric;
  v_det   jsonb;
  v_cf    jsonb;
begin
  select * into v_fy from erp.fiscal_years f where f.company_id = p_company and f.year = p_year;
  if not found then return; end if;
  select * into v_close from erp.year_closings y where y.company_id = p_company and y.fiscal_year_id = v_fy.id;

  -- 1) Cada asiento cuadra
  select count(*), coalesce(jsonb_agg(x.entry_no order by x.entry_no) filter (where x.rn <= 20), '[]')
    into v_n, v_det
  from (select e.entry_no, row_number() over (order by e.entry_no) rn
        from erp.journal_entries e join erp.journal_lines l on l.entry_id = e.id
        where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
        group by e.id, e.entry_no having sum(l.debit) <> sum(l.credit)) x;
  code := 'entries_balanced'; sort := 10; status := case when v_n = 0 then 'ok' else 'fail' end;
  expected := 0; actual := v_n; detail := v_det;
  title := 'Cada asiento cuadra (Debe = Haber)'; title_en := 'Every entry balances (debit = credit)';
  return next;

  -- 2) Sumas y saldos
  select coalesce(sum(t.total_debit), 0), coalesce(sum(t.total_credit), 0) into v_a, v_b
  from erp.trial_balance(p_company, p_year) t;
  code := 'trial_balance'; sort := 20; status := case when v_a = v_b then 'ok' else 'fail' end;
  expected := v_a; actual := v_b; detail := null;
  title := 'Sumas y saldos: total Debe = total Haber'; title_en := 'Trial balance: total debits = total credits';
  return next;

  -- 3) Activo = Patrimonio neto + Pasivo
  select coalesce(max(f.amount) filter (where f.code = 'ACT'), 0), coalesce(max(f.amount) filter (where f.code = 'PNP'), 0)
    into v_a, v_b
  from erp.financial_statement(p_company, p_year, 'balance') f;
  code := 'balance_sheet'; sort := 30; status := case when v_a = v_b then 'ok' else 'fail' end;
  expected := v_a; actual := v_b; detail := null;
  title := 'Activo = Patrimonio neto + Pasivo'; title_en := 'Assets = Equity + Liabilities';
  return next;

  -- 4) Tras el cierre, la 129 recibe exactamente el resultado de la PyG
  code := 'result_129'; sort := 40; title := 'La regularización lleva a la 129 el resultado de la PyG';
  title_en := 'The closing of the P&L takes the P&L result to account 129'; detail := null;
  if v_close.id is null or v_close.closing_pl_entry_id is null then
    status := 'n/a'; expected := null; actual := null;
  else
    select coalesce(max(f.amount) filter (where f.code = 'PD'), 0) into v_a from erp.financial_statement(p_company, p_year, 'pyg') f;
    select coalesce(sum(l.credit - l.debit), 0) into v_b
    from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
    where l.entry_id = v_close.closing_pl_entry_id and g.account_no like '129%';
    status := case when v_a = v_b then 'ok' else 'fail' end; expected := v_a; actual := v_b;
  end if;
  return next;

  -- 5) Apertura del año siguiente = cierre de este, cuenta a cuenta (cierre + apertura = 0)
  code := 'opening_closing'; sort := 50; title := 'La apertura del año siguiente es el cierre de este, cuenta a cuenta';
  title_en := 'Next year''s opening equals this year''s closing, account by account';
  if v_close.id is null or v_close.closing_entry_id is null or v_close.opening_entry_id is null then
    status := 'n/a'; expected := null; actual := null; detail := null;
  else
    select count(*), coalesce(jsonb_agg(x.account_no order by x.account_no) filter (where x.rn <= 20), '[]') into v_n, v_det
    from (select g.account_no, row_number() over (order by g.account_no) rn
          from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
          where l.entry_id in (v_close.closing_entry_id, v_close.opening_entry_id)
          group by g.account_no having sum(l.debit - l.credit) <> 0) x;
    status := case when v_n = 0 then 'ok' else 'fail' end; expected := 0; actual := v_n; detail := v_det;
  end if;
  return next;

  -- 6) Asiento + contraasiento = cero, cuenta a cuenta
  select count(*), coalesce(jsonb_agg(x.entry_no order by x.entry_no) filter (where x.rn <= 20), '[]') into v_n, v_det
  from (select o.entry_no, row_number() over (order by o.entry_no) rn
        from erp.journal_entries r
        join erp.journal_entries o on o.id = r.reversal_of
        where r.company_id = p_company and r.fiscal_year_id = v_fy.id and r.status = 'posted'
          and exists (select 1 from erp.journal_lines l where l.entry_id in (r.id, o.id)
                      group by l.gl_account_id having sum(l.debit - l.credit) <> 0)) x;
  code := 'reversals_zero'; sort := 60; status := case when v_n = 0 then 'ok' else 'fail' end;
  expected := 0; actual := v_n; detail := v_det;
  title := 'Un asiento y su contraasiento suman cero'; title_en := 'An entry and its reversal add up to zero';
  return next;

  -- 7) La línea del tercero de cada factura = total − retención (recibida: Haber · emitida: Debe)
  select count(*), coalesce(jsonb_agg(x.invoice_no order by x.invoice_no) filter (where x.rn <= 20), '[]') into v_n, v_det
  from (select i.invoice_no, row_number() over (order by i.invoice_no) rn
        from erp.invoices i
        join erp.business_partners bp on bp.id = i.partner_id
        where i.company_id = p_company and i.fiscal_year_id = v_fy.id
          and (select coalesce(sum(l.debit - l.credit), 0) from erp.journal_lines l
               where l.entry_id = i.entry_id and l.gl_account_id = bp.gl_account_id)
              <> (i.total_amount - i.withholding_amount) * case i.invoice_type when 'sale' then 1 else -1 end) x;
  code := 'invoice_partner'; sort := 70; status := case when v_n = 0 then 'ok' else 'fail' end;
  expected := 0; actual := v_n; detail := v_det;
  title := 'En cada factura, el tercero queda por el total menos la retención';
  title_en := 'In every invoice, the partner is posted at total minus withholding';
  return next;

  -- 8) 472 / 477 de los asientos de las facturas = cuotas del libro registro
  --    477: repercutido de las ventas + recargo de equivalencia + autorrepercusión (ISP, adquisición intracomunitaria)
  --    472: soportado deducible de las compras (con prorrata, solo la parte deducible)
  select coalesce(sum(case when g.account_no like '477%' then l.credit - l.debit else 0 end), 0),
         coalesce(sum(case when g.account_no like '472%' then l.debit - l.credit else 0 end), 0)
    into v_a, v_b
  from erp.invoices i
  join erp.journal_lines l on l.entry_id = i.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id
  where i.company_id = p_company and i.fiscal_year_id = v_fy.id;
  select coalesce(sum(case when r.invoice_type = 'sale' then r.tax_amount + coalesce(r.surcharge_amount, 0)
                           when r.rate_category in ('reverse_charge', 'intra_eu_acquisition') then r.tax_amount
                           else 0 end), 0),
         coalesce(sum(case when r.invoice_type = 'purchase' then r.deductible_amount else 0 end), 0)
    into v_c, v_d
  from erp.v_invoice_register r where r.company_id = p_company and r.fiscal_year = p_year;
  code := 'tax_register'; sort := 80;
  status := case when v_a = v_c and v_b = v_d then 'ok' else 'fail' end;
  expected := v_c + v_d; actual := v_a + v_b;
  detail := jsonb_build_object('ledger_477', v_a, 'register_output', v_c, 'ledger_472', v_b, 'register_input', v_d);
  title := 'Las 472 / 477 de las facturas = las cuotas del libro registro';
  title_en := 'Invoice 472 / 477 postings = the VAT register amounts';
  return next;

  -- 9) Variación de la tesorería = EFE directo = EFE indirecto
  v_cf := erp.cash_flow_check(p_company, p_year);
  v_a := (v_cf->>'cash_change')::numeric;
  v_b := (v_cf->'indirect'->>'total')::numeric;
  v_c := (v_cf->'direct'->>'total')::numeric;
  code := 'cash_flow'; sort := 90; status := case when v_a = v_b and v_a = v_c then 'ok' else 'fail' end;
  expected := v_a; actual := v_b; detail := jsonb_build_object('cash_change', v_a, 'indirect', v_b, 'direct', v_c);
  title := 'Variación de la tesorería (57) = EFE directo = EFE indirecto';
  title_en := 'Change in cash (57) = direct cash flow = indirect cash flow';
  return next;

  -- 10) v0.41.0 · Gasto por impuesto en la contabilidad (630) = el de la declaración contabilizada (corriente + diferido)
  --     Con la regularización, la 129 recibe el resultado antes de impuestos menos ese gasto (invariante 4).
  select (r.result->>'tax_expense')::numeric into v_c from erp.corporate_tax_returns r
  where r.fiscal_year_id = v_fy.id and r.status = 'posted';
  code := 'corporate_tax'; sort := 100;
  if v_c is null then
    status := 'n/a'; expected := null; actual := null; detail := null;
  else
    select coalesce(sum(l.debit - l.credit), 0) into v_a
    from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and l.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
      and e.entry_type not in ('closing_pl', 'closing') and g.account_no like '630%';
    status := case when v_a = v_c then 'ok' else 'fail' end; expected := v_c; actual := v_a;
    detail := jsonb_build_object('ledger_630', v_a, 'return_tax_expense', v_c);
  end if;
  title := 'Gasto por impuesto (630) = el de la declaración del Impuesto sobre Sociedades';
  title_en := 'Income tax expense (630) = the corporate income tax return';
  return next;
end $function$;

CREATE OR REPLACE FUNCTION erp.run_audit_checks(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(code text, sort integer, area text, status text, title text, title_en text, why text, why_en text, fix text, fix_en text, screen text, book numeric, ledger numeric, difference numeric, items integer, details jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_to     date := coalesce(p_to_date, (select f.ending_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year));
  v_type   text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
  r        record;
  v_sev    text;
  v_prefix text;
  v_sign   int;
  v_err    boolean;
  v_book numeric; v_ledger numeric; v_items int; v_det jsonb;
  v_al     erp.audit_line[];   -- v0.52.3: los apuntes del ejercicio con su origen, calculados UNA vez para todas
  v_rules  jsonb;   -- v0.52.2: reglas de las cuentas controladas de la empresa
begin
  -- v0.52.3: el permiso, una vez (erp.can_report, como la seguridad fila a fila) y no en cada fila de cada consulta;
  -- todas las consultas de abajo filtran por la empresa
  if not erp.can_report(p_company) then return; end if;
  if v_type is null or v_to is null then return; end if;
  select array_agg(x) into v_al from erp.audit_lines(p_company, p_year, v_to) x;
  v_al := coalesce(v_al, '{}');     -- empresa o ejercicio que no existe (o no se puede ver)

  for r in select * from erp.audit_checks c order by c.sort loop
    v_book := null; v_ledger := null; v_items := 0; v_det := '[]'; v_sev := r.severity;

    if r.code in ('vat_input', 'vat_output') then
      -- 472 al Debe (soportado) · 477 al Haber (repercutido); sin liquidación ni prorrata
      v_prefix := case r.code when 'vat_input' then '472' else '477' end;
      v_sign   := case r.code when 'vat_input' then 1 else -1 end;
      select coalesce(sum(v_sign * (a.debit - a.credit)) filter (where a.source = 'invoice'), 0),
             coalesce(sum(v_sign * (a.debit - a.credit)), 0)
      into v_book, v_ledger
      from unnest(v_al) a
      where a.account_no like v_prefix || '%' and a.source not in ('settlement', 'pro_rata');
      -- Detalle: asientos manuales o importados (cada uno junto con su contraasiento: si se anularon, no salen)
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(v_sign * (a.debit - a.credit)) as amount
        from unnest(v_al) a
        where a.account_no like v_prefix || '%' and a.source in ('manual', 'import')
        group by a.k, a.source having sum(a.debit - a.credit) <> 0
      ), n as (
        select g.*, e.entry_no, e.posting_date, row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'amount', n.amount)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'tax_quota' then
      -- v0.33.1: apuntes manuales o importados en 472 / 477 con base y tipo, cuya cuota no es base × tipo
      --   (tolerancia de 1 céntimo por redondeo; un asiento ya anulado no cuenta)
      with x as (
        select e.id as entry_id, e.entry_no, e.posting_date,
               case when e.import_batch_id is not null then 'import' else 'manual' end as source,
               g.account_no, l.tax_code, c.rate_pct, l.tax_base,
               abs(l.debit - l.credit) as amount, round(abs(l.tax_base) * c.rate_pct / 100, 2) as expected
        from erp.journal_lines l
        join erp.journal_entries e on e.id = l.entry_id
        join erp.fiscal_years fy on fy.id = e.fiscal_year_id
        join erp.gl_accounts g on g.id = l.gl_account_id
        join erp.tax_codes c on c.code = l.tax_code
        where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
          and l.company_id = p_company and g.company_id = p_company and fy.company_id = p_company   -- v0.52.3
          and e.posting_date <= v_to and e.reversal_of is null
          and not exists (select 1 from erp.journal_entries rv
                          where rv.reversal_of = e.id and rv.status = 'posted' and rv.posting_date <= v_to)
          and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
          and (g.account_no like '472%' or g.account_no like '477%')
          and coalesce(l.tax_base, 0) <> 0
      ), n as (
        select x.*, row_number() over (order by x.posting_date, x.entry_no) as rn
        from x where abs(x.amount - x.expected) > 0.01
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.entry_id, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'tax_code', n.tax_code,
                                                   'rate_pct', n.rate_pct, 'tax_base', n.tax_base,
                                                   'amount', n.amount, 'expected', n.expected)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'withholdings' then
      -- Libro: retenciones practicadas en facturas recibidas (modelos 111 / 115)
      select coalesce(sum(w.withholding_amount), 0) into v_book
      from erp.v_withholding_register w
      where w.company_id = p_company and w.fiscal_year = p_year and w.side = 'withheld' and w.posting_date <= v_to;
      -- v0.38.0: más el IRPF de las nóminas (también va al modelo 111, casillas 01 a 03)
      v_book := v_book + coalesce((select sum(s.irpf) from erp.payslips s
                                   join erp.payroll_runs pr on pr.id = s.run_id
                                   join erp.journal_entries je on je.id = pr.entry_id
                                   join erp.fiscal_years f on f.id = je.fiscal_year_id
                                   where pr.company_id = p_company and pr.status = 'posted' and f.year = p_year and pr.period <= v_to), 0);
      -- Contabilidad: asientos que ABONAN la 4751 (las retenciones). Los que la cargan son el ingreso en Hacienda.
      -- Un contraasiento va con su original (por eso se agrupa por k y el signo es el del original).
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(a.credit - a.debit) as amount,
               (select sum(l.credit - l.debit) from erp.journal_lines l join erp.gl_accounts ga on ga.id = l.gl_account_id
                where l.entry_id = a.k and ga.account_no like '4751%' and ga.account_no not like '47512%') as original
        from unnest(v_al) a
        where a.account_no like '4751%' and a.account_no not like '47512%'   -- v0.42.0: la 47512 (dividendos) va al modelo 123
        group by a.k, a.source
      ), n as (
        select g.*, e.entry_no, e.posting_date,
               row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
        where g.original > 0
      )
      select coalesce(sum(n.amount), 0),
             count(*) filter (where n.source in ('manual', 'import') and n.amount <> 0)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'amount', n.amount)
                                order by n.rn) filter (where n.source in ('manual', 'import') and n.amount <> 0), '[]')
      into v_ledger, v_items, v_det
      from n;

    elsif r.code = 'tax_forms_settlements' then
      -- v0.39.0 · el resultado de cada modelo trimestral (303 / 420, desde el libro registro) frente a su liquidación
      --   contabilizada (desde la contabilidad): un trimestre liquidado aceptando una diferencia
      with q as (
        select g.q, erp.quarter_end(p_year, g.q) as q_end,
               (select b.amount from erp.tax_form_boxes(p_company, p_year, g.q) b where b.box = case v_type when 'VAT' then '46' else '41' end) as form_result,
               (select s.output_tax - s.input_tax from erp.tax_settlements s where s.company_id = p_company and s.tax_type = v_type
                  and s.year = p_year and s.quarter = g.q and s.status = 'posted') as settled
        from generate_series(1, 4) g(q)
        where erp.quarter_end(p_year, g.q) <= v_to
      ), n as (   -- solo los trimestres liquidados (los que faltan por liquidar los avisa el asistente de cierre)
        select q.*, row_number() over (order by q.q) as rn from q
        where q.settled is not null and q.settled <> q.form_result
      )
      select (select coalesce(sum(form_result), 0) from q where settled is not null), (select coalesce(sum(settled), 0) from q), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('quarter', n.q, 'form', case v_type when 'VAT' then '303' else '420' end,
                                                   'form_result', n.form_result, 'settled', n.settled, 'amount', coalesce(n.settled, 0) - n.form_result)
                                order by n.rn), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'form347_missing_vat' then
      -- v0.39.0 · terceros que hay que declarar en el 347 (más de 3.005,06 € en el año) y no tienen NIF
      with n as (select f.*, row_number() over (order by f.partner_name) as rn from erp.form_347(p_company, p_year) f where f.missing_vat_no)
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('partner_id', n.partner_id, 'partner_name', n.partner_name, 'op_key', n.op_key,
                                                   'amount', n.total) order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'sources_review' then
      -- v0.39.0 · fuentes oficiales sin revisar en más de un año (las normas y las instrucciones cambian)
      with n as (select s.*, row_number() over (order by s.checked, s.key) as rn from erp.sources s where s.checked < current_date - interval '1 year')
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('key', n.key, 'name', n.title, 'issuer', n.issuer, 'checked', n.checked) order by n.rn), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'partners' then
      with x as (
        select 'purchase' as t, a.* from erp.aging(p_company, 'purchase', v_to) a
        union all
        select 'sale', a.* from erp.aging(p_company, 'sale', v_to) a
      ), d as (
        select x.*, row_number() over (order by abs(x.account_balance - x.total) desc, x.partner_name) as rn
        from x where x.account_balance <> x.total
      )
      select coalesce(sum(d.total), 0), coalesce(sum(d.account_balance), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('partner_id', d.partner_id, 'partner_name', d.partner_name,
                                                   'account_no', d.partner_account_no, 'invoice_type', d.t,
                                                   'pending', d.total, 'balance', d.account_balance,
                                                   'amount', d.account_balance - d.total)
                                order by d.rn) filter (where d.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from d;

    elsif r.code = 'anomalies' then
      select count(*)::int, bool_or(b.severity = 'error'),
             coalesce(jsonb_agg(jsonb_build_object('account_no', b.account_no, 'account_name', b.name, 'expected', b.expected,
                                                   'amount', b.balance, 'reclass_to', b.reclass_to, 'severity', b.severity,
                                                   'note', b.note, 'note_en', b.note_en)), '[]')
      into v_items, v_err, v_det
      from erp.balance_anomalies(p_company, p_year, null, v_to) b;
      if v_err then v_sev := 'error'; end if;
      v_det := coalesce((select jsonb_agg(j.d) from jsonb_array_elements(v_det) with ordinality j(d, n) where j.n <= 50), '[]');

    elsif r.code = 'tax_territory' then
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, min(a.tax_code) as tax_code, sum(a.debit - a.credit) as amount
        from unnest(v_al) a join erp.tax_codes c on c.code = a.tax_code
        where c.tax_type <> v_type
        group by a.k, a.source
        having count(*) filter (where a.entry_id = a.k) > count(*) filter (where a.entry_id <> a.k)  -- sin anular
      ), n as (
        select g.*, e.entry_no, e.posting_date, row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'tax_code', n.tax_code,
                                                   'amount', n.amount)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'controlled' then
      -- Manuales sin anular que tocan una cuenta controlada; no cuentan los vinculados a un pago (ya están conciliados)
      -- v0.52.2: en bloque (antes, erp.entry_controlled_lines asiento por asiento: 20 s con 18.000 asientos manuales).
      -- Las reglas de las cuentas de la empresa, en un mapa { cuenta: { modules, side } } (una búsqueda por cuenta), y
      -- cada asiento se queda con su primera línea (por su orden) que toca una cuenta controlada por el lado que controla.
      select coalesce(jsonb_object_agg(d.account_no, jsonb_build_object('modules', to_jsonb(x.modules), 'side', x.side)), '{}')
      into v_rules
      from (select g.account_no from erp.gl_accounts g where g.company_id = p_company) d
      cross join lateral erp.control_rule_for(d.account_no) x
      where x.account_prefix is not null and cardinality(x.modules) > 0;

      with m as (
        select distinct a.entry_id, a.entry_no, a.posting_date
        from unnest(v_al) a
        where a.source = 'manual' and a.entry_id = a.k
      ), hit as (
        select distinct on (m.entry_id) m.entry_id, m.entry_no, m.posting_date, g.account_no,
               v_rules -> g.account_no -> 'modules' as modules
        from m
        join erp.journal_lines l on l.entry_id = m.entry_id
        join erp.gl_accounts g on g.id = l.gl_account_id
        where v_rules ? g.account_no
          and (v_rules -> g.account_no ->> 'side' = 'both'
               or (v_rules -> g.account_no ->> 'side' = 'debit'  and coalesce(l.debit, 0) > 0)
               or (v_rules -> g.account_no ->> 'side' = 'credit' and coalesce(l.credit, 0) > 0))
          and not exists (select 1 from erp.journal_entries x
                          where x.reversal_of = m.entry_id and x.status = 'posted' and x.posting_date <= v_to)
          and not exists (select 1 from erp.payments py where py.entry_id = m.entry_id and py.linked)
        order by m.entry_id, l.line_no
      ), n as (
        select hit.*, row_number() over (order by hit.posting_date, hit.entry_no) as rn from hit
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.entry_id, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'account_no', n.account_no, 'modules', n.modules)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'assets_ledger' then
      -- v0.35.0 · cada cuenta de inmovilizado (coste de los activos en uso) y de amortización acumulada (lo amortizado)
      --   frente a su saldo contable a la fecha (sin terrenos 210 / 220, que no tienen ficha amortizable)
      with f as (
        select a.asset_account_id as acc, sum(a.cost) as book from erp.fixed_assets a
        where a.company_id = p_company and (a.status = 'active' or a.disposal_date > v_to) and a.acquisition_date <= v_to
        group by 1
        union all
        select a.depreciation_account_id, -sum(d.amount) from erp.fixed_assets a
        join erp.asset_depreciations d on d.asset_id = a.id and d.period_end <= v_to
        where a.company_id = p_company and (a.status = 'active' or a.disposal_date > v_to)
        group by 1
        union all
        -- v0.37.0 · el deterioro (29x) frente al deterioro neto de las fichas
        select (select jl.gl_account_id from erp.journal_lines jl join erp.gl_accounts g2 on g2.id = jl.gl_account_id
                where jl.entry_id = ev.entry_id and g2.account_no like '29%' limit 1),
               -sum(case ev.kind when 'impairment' then ev.amount else -ev.amount end)
        from erp.asset_events ev join erp.fixed_assets a on a.id = ev.asset_id
        where ev.company_id = p_company and ev.kind in ('impairment', 'reversal') and ev.event_date <= v_to
          and (a.status = 'active' or a.disposal_date > v_to)
        group by 1
      ), l as (
        -- saldo acumulado a la fecha: todos los ejercicios, sin los asientos de cierre ni las aperturas del propio ERP
        -- (repetirían saldos); una apertura IMPORTADA sí cuenta
        select g.id as acc, sum(jl.debit - jl.credit) as ledger
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and jl.company_id = p_company and g.company_id = p_company   -- v0.52.3: solo las cuentas y apuntes de la empresa
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and (left(g.account_no, 2) in ('20', '21', '22', '28') or left(g.account_no, 3) in ('290', '291', '292'))
          and left(g.account_no, 3) not in ('210', '220')
        group by 1
      ), x as (
        select coalesce(f.acc, l.acc) as acc, coalesce(sum(f.book), 0) as book, coalesce(max(l.ledger), 0) as ledger
        from f full join l on l.acc = f.acc group by coalesce(f.acc, l.acc)
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'assets_pending' then
      -- v0.35.0 · activos con amortización pendiente hasta el último fin de mes de la fecha de corte
      -- (último fin de mes: la propia fecha si es fin de mes; si no, el del mes anterior)
      with c as (select (date_trunc('month', v_to + 1) - interval '1 day')::date as cut),
      p as (
        select a.id, a.code, a.name, a.start_date,
               erp.asset_depr_at(a.id, c.cut) - erp.asset_posted(a.id) as pending,
               (select max(d.period_end) from erp.asset_depreciations d where d.asset_id = a.id) as last_period
        from erp.fixed_assets a cross join c
        where a.company_id = p_company and a.status = 'active'
      ), n as (select p.*, row_number() over (order by p.code) as rn from p where p.pending > 0)
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('asset_id', n.id, 'code', n.code, 'name', n.name, 'amount', n.pending,
                                                   'last_period', n.last_period) order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'adjustments_ledger' then
      -- v0.36.0 · 480 / 485 / 4009 / 4309 frente a las periodificaciones vivas y 490 frente a los deterioros vivos, a la fecha
      --   (viva: contabilizada hasta la fecha y aún sin revertir, aplicar ni anular a esa fecha)
      with f as (
        select a.balance_account_id as acc,
               sum(case when a.kind in ('prepaid_expense', 'accrued_income') then a.amount else -a.amount end) as book
        from erp.accruals a
        where a.company_id = p_company and a.cutoff_date <= v_to
          and (a.reversal_date is null or a.reversal_date > v_to)
          and (a.cancel_entry_id is null or (select ce.posting_date from erp.journal_entries ce where ce.id = a.cancel_entry_id) > v_to)
        group by 1
        union all
        select (select g.id from erp.gl_accounts g join erp.journal_lines jl on jl.gl_account_id = g.id
                where jl.entry_id = i.entry_id and g.account_no like '490%' limit 1), -sum(i.amount)
        from erp.receivable_impairments i
        where i.company_id = p_company and i.impair_date <= v_to
          and (i.end_date is null or i.end_date > v_to)
          and (i.cancel_entry_id is null or (select ce.posting_date from erp.journal_entries ce where ce.id = i.cancel_entry_id) > v_to)
        group by 1
      ), l as (
        -- saldo acumulado a la fecha (todos los ejercicios, sin cierres ni aperturas del propio ERP), como assets_ledger
        select g.id as acc, sum(jl.debit - jl.credit) as ledger
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and jl.company_id = p_company and g.company_id = p_company   -- v0.52.3: solo las cuentas y apuntes de la empresa
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and (g.account_no like '480%' or g.account_no like '485%' or g.account_no like '4009%'
               or g.account_no like '4309%' or g.account_no like '490%')
        group by 1
      ), x as (
        select coalesce(f.acc, l.acc) as acc, coalesce(sum(f.book), 0) as book, coalesce(max(l.ledger), 0) as ledger
        from f full join l on l.acc = f.acc group by coalesce(f.acc, l.acc)
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'accruals_unreversed' then
      -- v0.36.0 · periodificaciones de un ejercicio anterior que siguen sin revertir en este
      with fy as (select f.starting_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year),
      n as (
        select a.id, a.code, a.description, a.cutoff_date, a.amount, row_number() over (order by a.code) as rn
        from erp.accruals a cross join fy
        where a.company_id = p_company and a.status = 'active' and a.cutoff_date < fy.starting_date and fy.starting_date <= v_to
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('accrual_id', n.id, 'code', n.code, 'name', n.description,
                                                   'cutoff_date', n.cutoff_date, 'amount', n.amount) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code in ('provisions_ledger', 'inventory_ledger', 'payroll_ledger', 'financing_ledger', 'grants_ledger') then
      -- v0.37.0 · las cuentas de provisiones (141 / 142 / 5292 / 5293 / 499) y de existencias (30-36 / 39) frente a lo
      --   que han contabilizado sus módulos: la diferencia es un asiento manual o un saldo importado sin su ficha
      with lm as (
        select g.id as acc, sum(jl.debit - jl.credit) as amount,
               bool_or(exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
                       or exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id and ic.status = 'posted')
                       -- v0.38.0: la nómina y sus pagos
                       or exists (select 1 from erp.payroll_runs pr where e.id in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id))
                       -- v0.43.0: los préstamos y el leasing (también la factura de la cuota)
                       or exists (select 1 from erp.loan_events le where le.entry_id = e.id and le.status = 'posted')
                       -- v0.44.0: las subvenciones, y la regularización de los grupos 8 y 9 contra la 130 del cierre
                       or exists (select 1 from erp.grant_events ge where ge.entry_id = e.id and ge.status = 'posted')
                       or e.entry_type = 'closing_pl') as module
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and jl.company_id = p_company and g.company_id = p_company   -- v0.52.3: solo las cuentas y apuntes de la empresa
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and case r.code when 'provisions_ledger' then g.account_no ~ '^(141|142|5292|5293|499)'
                          when 'payroll_ledger' then g.account_no ~ '^(465|476)'   -- v0.38.0
                          when 'financing_ledger' then g.account_no ~ '^(170|171|174|520|521|524|527|528)'   -- v0.43.0
                          when 'grants_ledger' then g.account_no ~ '^(13[0-2]|172|522|4708|8|9)'   -- v0.44.0
                          else g.account_no ~ '^3[0-6]|^39' end
          -- un movimiento anulado y su contraasiento se compensan: ninguno de los dos cuenta como del módulo
          and not (e.reversal_of is not null or e.reversed_by is not null)
        group by g.id, e.id
      ), x as (
        select acc, coalesce(sum(amount) filter (where module), 0) as book, sum(amount) as ledger from lm group by acc
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'provisions_review' then
      -- v0.37.0 · al cierre, provisiones vivas sin revisar en el ejercicio (NRV 15.ª: se revisan en cada cierre)
      with fy as (select f.starting_date, f.ending_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year),
      n as (
        select pv.id, pv.code, pv.description, erp.provision_balance(pv.id) as balance,
               (select max(m.movement_date) from erp.provision_movements m where m.provision_id = pv.id) as last_date,
               row_number() over (order by pv.code) as rn
        from erp.provisions pv cross join fy
        where pv.company_id = p_company and pv.status = 'active' and v_to >= fy.ending_date
          and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date < fy.starting_date)
          and not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                          and m.movement_date between fy.starting_date and fy.ending_date)
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('provision_id', n.id, 'code', n.code, 'name', n.description,
                                                   'amount', n.balance, 'last_date', n.last_date) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'impairments_collected' then
      -- v0.36.0 · deterioro individual vivo de una factura que ya no tiene nada pendiente (cobrada o rectificada)
      with n as (
        select i.id, i.code, i.amount, o.invoice_no, o.partner_name, row_number() over (order by i.code) as rn
        from erp.receivable_impairments i
        join erp.open_items(p_company, v_to) o on o.invoice_id = i.invoice_id
        where i.company_id = p_company and i.method = 'individual' and i.status = 'active' and i.impair_date <= v_to
          and o.pending <= 0
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('impairment_id', n.id, 'code', n.code, 'invoice_no', n.invoice_no,
                                                   'partner_name', n.partner_name, 'amount', n.amount) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;
    end if;

    code := r.code; sort := r.sort; area := r.area;
    status := case when coalesce(v_ledger, 0) = coalesce(v_book, 0) and v_items = 0 then 'ok' else v_sev end;
    title := r.title; title_en := r.title_en; why := r.why; why_en := r.why_en; fix := r.fix; fix_en := r.fix_en;
    screen := r.screen; book := v_book; ledger := v_ledger;
    difference := case when v_book is null then null else v_ledger - v_book end;
    items := v_items; details := v_det;
    return next;
  end loop;
end $function$;


CREATE OR REPLACE FUNCTION erp.aging(p_company uuid, p_type text, p_date date DEFAULT NULL::date)
 RETURNS TABLE(partner_id uuid, partner_name text, partner_account_no text, open_invoices integer, not_due numeric, d1_30 numeric, d31_60 numeric, d61_90 numeric, d90_plus numeric, total numeric, account_balance numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with d as (select coalesce(p_date, current_date) as d),
  items as (select * from erp.open_items(p_company, p_date) o where o.invoice_type = p_type and o.pending > 0),
  partners as (
    select bp.id, bp.name, g.account_no, bp.gl_account_id
    from erp.business_partners bp left join erp.gl_accounts g on g.id = bp.gl_account_id
    where bp.company_id = p_company
      and bp.partner_type = any (case p_type when 'purchase' then array['vendor', 'creditor'] else array['customer', 'debtor'] end)
  ),
  balances as (
    select pt.id, coalesce(sum(l.debit - l.credit), 0) * case p_type when 'purchase' then -1 else 1 end as balance
    from partners pt cross join d
    join erp.journal_lines l on l.gl_account_id = pt.gl_account_id
    join erp.journal_entries e on e.id = l.entry_id
    where e.status = 'posted' and e.posting_date <= d.d and e.entry_type <> 'closing'
      and l.company_id = p_company and e.company_id = p_company   -- v0.52.3: solo los apuntes de la empresa
      and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
    group by pt.id
  )
  select pt.id, pt.name, pt.account_no,
         count(i.invoice_id)::int,
         coalesce(sum(i.pending) filter (where i.days_overdue = 0), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue between 1 and 30), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue between 31 and 60), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue between 61 and 90), 0),
         coalesce(sum(i.pending) filter (where i.days_overdue > 90), 0),
         coalesce(sum(i.pending), 0),
         coalesce(b.balance, 0)
  from partners pt
  left join items i on i.partner_id = pt.id
  left join balances b on b.id = pt.id
  group by pt.id, pt.name, pt.account_no, b.balance
  having coalesce(sum(i.pending), 0) <> 0 or coalesce(b.balance, 0) <> 0
  order by coalesce(sum(i.pending), 0) desc, pt.name;
$function$;

notify pgrst, 'reload schema';
