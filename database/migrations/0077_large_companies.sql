-- =====================================================================
-- 0077 · Rendimiento con empresas grandes de varios años (v0.52.2)
-- ---------------------------------------------------------------------
-- Después de la 0076, Comprobaciones seguía superando el límite de 8 s de Supabase en empresas grandes importadas de
-- varios años. Reproducido en local con una empresa importada de 6 años (108.000 asientos, 272.000 apuntes):
--
--   · erp.audit_lines (la base de Comprobaciones, que la llama 7 veces): para cada apunte hacía hasta 19 búsquedas
--     (factura, liquidación, nómina, pago…) antes de llegar a «importado», y la seguridad fila a fila se evaluaba en
--     cada fila. Ahora el origen de todos los asientos se calcula de una vez (cada tabla de documentos se lee una vez,
--     filtrada por la empresa) y el permiso se comprueba una sola vez.
--   · La comprobación de cuentas controladas llamaba a erp.entry_controlled_lines asiento por asiento (20 s con
--     18.000 asientos manuales). Ahora va en bloque, con un mapa de las reglas de las cuentas de la empresa.
--   · La clasificación del balance y la PyG, sumas y saldos, el mayor y las funciones de flujos leen primero los
--     asientos del ejercicio (por su índice) y después sus apuntes, en vez de todo el diario de la empresa; y la línea
--     de flujos de cada cuenta se busca una vez por cuenta, no una vez por asiento.
--   · El permiso, una vez por llamada: erp.can_report (nueva) hace lo mismo que la seguridad fila a fila, pero una vez:
--     se aplica a los usuarios de la web (authenticated, anon); el administrador de la base lo ve todo, como antes.
--
-- Mismos resultados (comprobado con el caso completo y con la empresa grande). En local, con la empresa de 6 años:
-- Comprobaciones, de 9,9 s (importada) y 20 s (manual) a 1,2–1,5 s; tablero, de 3 s a 1 s; comprobaciones de
-- integridad, de 3,5 s a 1,6 s. Se puede ejecutar dos veces.
-- =====================================================================

-- v0.52.2 · El permiso de lectura de los informes, UNA vez por llamada (no en cada fila, como la seguridad fila a fila).
-- Igual que la seguridad fila a fila (RLS): se aplica a los usuarios de la web (authenticated y anon); el administrador
-- de la base (SQL Editor, pruebas, tareas programadas) lo ve todo, como antes.
create or replace function erp.can_report(p_company uuid)
returns boolean language sql stable security definer set search_path to 'erp', 'public' as $$
  select coalesce(current_setting('role', true), 'none') not in ('authenticated', 'anon') or erp.can_read(p_company);
$$;
revoke execute on function erp.can_report(uuid) from anon, public;
grant execute on function erp.can_report(uuid) to authenticated;

-- v0.52.2 · erp.audit_lines, rápida con diarios grandes (mismo resultado que antes):
--   · el ORIGEN de cada asiento (factura, liquidación, nómina, importación…) se calcula de una vez para todos los
--     documentos de la empresa (cada tabla se lee una sola vez), en lugar de 19 búsquedas por cada apunte;
--   · el permiso se comprueba UNA vez (erp.can_report) y no en cada fila: es SECURITY DEFINER y filtra por la empresa.
--   La prioridad de los orígenes es la de siempre: si un asiento está en dos documentos, gana el primero de la lista.
create or replace function erp.audit_lines(p_company uuid, p_year integer, p_to_date date default null::date)
 returns table(entry_id uuid, entry_no integer, posting_date date, k uuid, source text, account_no text, account_name text, debit numeric, credit numeric, tax_code text)
 language sql stable security definer
 rows 20000
 set search_path to 'erp', 'public'
as $function$
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
         coalesce(src.s, case when o.import_batch_id is not null then 'import' else 'manual' end),
         g.account_no, g.name, l.debit, l.credit, l.tax_code
  -- primero los asientos del ejercicio (por su índice) y después sus apuntes
  from (select e.* from erp.journal_entries e
        where e.fiscal_year_id = (select fy.id from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year)
          and e.company_id = p_company and e.status = 'posted' and e.entry_type = 'normal'
          and (p_to_date is null or e.posting_date <= p_to_date) and erp.can_report(p_company)
        offset 0) e
  join erp.journal_entries o on o.id = coalesce(e.reversal_of, e.id)
  left join src on src.k = coalesce(e.reversal_of, e.id)
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id;
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
    join erp.journal_lines l on l.entry_id = e.id
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


CREATE OR REPLACE FUNCTION erp.trial_balance(p_company uuid, p_year integer, p_level integer DEFAULT NULL::integer, p_to_date date DEFAULT NULL::date, p_drafts boolean DEFAULT false)
 RETURNS TABLE(account_no text, name text, name_en text, total_debit numeric, total_credit numeric, debit_balance numeric, credit_balance numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_report(p_company) then return; end if;   -- v0.52.2: el permiso, una vez (no en cada fila)
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with mov as (
    select case when p_level is null then a.account_no else left(a.account_no, p_level) end as account_no,
           l.debit, l.credit
    from erp.journal_lines l
    join erp.journal_entries e  on e.id = l.entry_id
    join erp.fiscal_years    fy on fy.id = e.fiscal_year_id
    join erp.gl_accounts     a  on a.id = l.gl_account_id
    where e.company_id = p_company and l.company_id = p_company
      and fy.year = p_year
      and erp.counts_in_reports(e.status, e.id)
      and e.entry_type <> 'closing'            -- sin el asiento de cierre: si no, un año cerrado sale todo a cero
      and (p_to_date is null or e.posting_date <= p_to_date)
  )
  select m.account_no,
         a.name,
         a.name_en,
         sum(m.debit),
         sum(m.credit),
         greatest(sum(m.debit) - sum(m.credit), 0),
         greatest(sum(m.credit) - sum(m.debit), 0)
  from mov m
  left join erp.gl_accounts a on a.company_id = p_company and a.account_no = m.account_no
  group by m.account_no, a.name, a.name_en
  order by m.account_no;
  perform set_config('erp.simulate', v_prev, true);
end $function$;

CREATE OR REPLACE FUNCTION erp.general_ledger(p_company uuid, p_year integer, p_account text, p_to_date date DEFAULT NULL::date, p_drafts boolean DEFAULT false)
 RETURNS TABLE(posting_date date, entry_no integer, document_no text, description text, debit numeric, credit numeric, running_balance numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_report(p_company) then return; end if;   -- v0.52.2: el permiso, una vez (no en cada fila)
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  select e.posting_date,
         e.entry_no,
         e.document_no,
         coalesce(l.description, e.description),
         l.debit,
         l.credit,
         sum(l.debit - l.credit) over (order by e.posting_date, e.entry_no nulls last, e.created_at, l.line_no
                                       rows between unbounded preceding and current row)
  from erp.journal_lines   l
  join erp.journal_entries e on e.id = l.entry_id
  where l.company_id = p_company and l.gl_account_id = (select a.id from erp.gl_accounts a
                           where a.company_id = p_company and a.account_no = p_account)
    and e.fiscal_year_id = (select fy.id from erp.fiscal_years fy
                            where fy.company_id = p_company and fy.year = p_year)
    and erp.counts_in_reports(e.status, e.id)
    and (p_to_date is null or e.posting_date <= p_to_date)
  order by e.posting_date, e.entry_no nulls last, e.created_at, l.line_no;
  perform set_config('erp.simulate', v_prev, true);
end $function$;

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
  join erp.journal_lines l on l.entry_id = e.id
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
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%';
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
    join erp.journal_lines l on l.entry_id = e.id
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

CREATE OR REPLACE FUNCTION erp.run_audit_checks(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(code text, sort integer, area text, status text, title text, title_en text, why text, why_en text, fix text, fix_en text, screen text, book numeric, ledger numeric, difference numeric, items integer, details jsonb)
 LANGUAGE plpgsql
 STABLE
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
  v_rules  jsonb;   -- v0.52.2: reglas de las cuentas controladas de la empresa
begin
  if v_type is null or v_to is null then return; end if;     -- empresa o ejercicio que no existe (o no se puede ver)

  for r in select * from erp.audit_checks c order by c.sort loop
    v_book := null; v_ledger := null; v_items := 0; v_det := '[]'; v_sev := r.severity;

    if r.code in ('vat_input', 'vat_output') then
      -- 472 al Debe (soportado) · 477 al Haber (repercutido); sin liquidación ni prorrata
      v_prefix := case r.code when 'vat_input' then '472' else '477' end;
      v_sign   := case r.code when 'vat_input' then 1 else -1 end;
      select coalesce(sum(v_sign * (a.debit - a.credit)) filter (where a.source = 'invoice'), 0),
             coalesce(sum(v_sign * (a.debit - a.credit)), 0)
      into v_book, v_ledger
      from erp.audit_lines(p_company, p_year, v_to) a
      where a.account_no like v_prefix || '%' and a.source not in ('settlement', 'pro_rata');
      -- Detalle: asientos manuales o importados (cada uno junto con su contraasiento: si se anularon, no salen)
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(v_sign * (a.debit - a.credit)) as amount
        from erp.audit_lines(p_company, p_year, v_to) a
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
        from erp.audit_lines(p_company, p_year, v_to) a
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
        from erp.audit_lines(p_company, p_year, v_to) a join erp.tax_codes c on c.code = a.tax_code
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
        from erp.audit_lines(p_company, p_year, v_to) a
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

notify pgrst, 'reload schema';
