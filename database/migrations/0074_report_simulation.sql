-- =====================================================================
-- 0074 · Simulación con los asientos en edición (v0.51.0 · ADR 0051)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.51.0.md): en los informes se puede marcar «Incluir los asientos en edición
-- (simulación)» para ver qué efecto tendrían los borradores antes de contabilizarlos. Es para aprender.
--
--   · UNA SOLA REGLA, `erp.counts_in_reports`: un asiento cuenta en los informes si está contabilizado o, solo en
--     simulación, si es un borrador SIN PROBLEMAS (`erp.draft_problem` = null: el estado «en edición» de la pantalla
--     «Asientos»). Los «con error» (no cuadran, mes cerrado…) no entran nunca: descuadrarían el balance.
--   · Las funciones de base de los informes (clasificación del balance y la PyG, sumas y saldos, mayor y flujos) usan
--     esa regla en lugar de «solo contabilizados».
--   · La simulación la enciende SOLO la web, con el parámetro nuevo `p_drafts` (por defecto false) de las funciones
--     que llama: Balance, PyG, Sumas y saldos, Mayor, Estado de flujos y Ratios. Lo encienden para su propia consulta
--     (un ajuste `erp.simulate` local a la transacción) y lo dejan como estaba al terminar.
--   · Nada más lo enciende: el cierre del ejercicio y del mes, las liquidaciones, los modelos, el impuesto sobre
--     sociedades, las comprobaciones de integridad, el contexto de la IA, el caso completo y el puente a Power BI
--     llaman a las mismas funciones sin el parámetro y siguen viendo solo lo contabilizado.
--   · El Libro diario no cambia: es el libro legal y solo lleva lo contabilizado.
--
-- Se puede ejecutar dos veces (las firmas antiguas se borran con «if exists»).
-- =====================================================================

-- ---------- La regla ----------
create or replace function erp.simulating()
returns boolean language sql stable as $$
  select coalesce(nullif(current_setting('erp.simulate', true), ''), 'off') = 'on';
$$;
comment on function erp.simulating() is
  'true solo dentro de un informe pedido con p_drafts = true (simulación con los asientos en edición).';

-- Un borrador «en edición» (sin problemas) de una empresa que el usuario puede leer. `erp.draft_problem` no está
-- abierta a la web (dice cosas de cualquier asiento): esta la envuelve y solo contesta de las empresas propias.
create or replace function erp.draft_ready(p_entry uuid)
returns boolean language sql stable security definer set search_path to 'erp', 'public' as $$
  select exists (select 1 from erp.journal_entries e
                 where e.id = p_entry and e.status = 'draft' and erp.can_read(e.company_id))
     and erp.draft_problem(p_entry) is null;
$$;

create or replace function erp.counts_in_reports(p_status text, p_entry uuid)
returns boolean language sql stable as $$
  select p_status = 'posted'
      or (p_status = 'draft' and erp.simulating() and erp.draft_ready(p_entry));
$$;
comment on function erp.counts_in_reports(text, uuid) is
  'Un asiento cuenta en los informes si está contabilizado o, en simulación, si es un borrador sin problemas («en edición»).';

-- Cuántos asientos en edición entrarían en la simulación (la franja de aviso de la web)
create or replace function erp.report_drafts(p_company uuid, p_year integer, p_to_date date default null)
returns integer language sql stable as $$
  select count(*)::int
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  where e.company_id = p_company and e.status = 'draft'
    and (p_to_date is null or e.posting_date <= p_to_date)
    and erp.draft_ready(e.id);
$$;

-- ---------- Las funciones de base usan la regla ----------
create or replace function erp.fs_classified_accounts(p_company uuid, p_year integer, p_statement text, p_to_date date default null::date)
 returns table(account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
 language sql stable
as $function$
  with acc as (
    select g.account_no, g.name, g.name_en, sum(l.debit - l.credit) as bal
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and erp.counts_in_reports(e.status, e.id)
                              and e.entry_type not in ('closing_pl', 'closing')
    join erp.fiscal_years fy   on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g     on g.id = l.gl_account_id
    where e.company_id = p_company
      and (p_to_date is null or e.posting_date <= p_to_date)
      and (p_statement = 'balance' or left(g.account_no, 1) in ('6', '7'))
    group by g.account_no, g.name, g.name_en
    having sum(l.debit - l.credit) <> 0
  )
  select a.account_no, a.name, a.name_en, a.bal,
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

create or replace function erp.cf_entry_cash(p_company uuid, p_year integer)
 returns table(entry_id uuid, cash numeric)
 language sql stable security definer
 set search_path to 'erp', 'public'
as $function$
  select l.entry_id, sum(l.debit - l.credit)
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  where e.company_id = p_company and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
  group by l.entry_id;
$function$;

create or replace function erp.cf_cash(p_company uuid, p_year integer)
 returns table(opening numeric, closing numeric)
 language sql stable security definer
 set search_path to 'erp', 'public'
as $function$
  select coalesce(sum(l.debit - l.credit) filter (where e.entry_type = 'opening'), 0),
         coalesce(sum(l.debit - l.credit) filter (where e.entry_type in ('opening', 'normal')), 0)
  from erp.journal_lines l
  join erp.journal_entries e on e.id = l.entry_id and erp.counts_in_reports(e.status, e.id)
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  where e.company_id = p_company;
$function$;

create or replace function erp.cf_line_flows(p_company uuid, p_year integer)
 returns table(entry_id uuid, account_no text, account_name text, account_name_en text, flow numeric, home_line text, adjust_line text, direct_line text, in_result boolean)
 language sql stable security definer
 set search_path to 'erp', 'public'
as $function$
  with base as (
    select l.entry_id, g.id as acc_id, g.account_no, g.name, g.name_en, -sum(l.debit - l.credit) as flow
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
    join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and g.account_no not like '57%'
    group by l.entry_id, g.id, g.account_no, g.name, g.name_en
    having sum(l.debit - l.credit) <> 0),
  mb as (
    select b.*, m.home_line, m.adjust_line, m.direct_line from base b cross join lateral erp.cf_account_map(b.account_no) m),
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

-- ---------- Las funciones que llama la web: parámetro nuevo p_drafts ----------
-- Patrón de todas: si p_drafts, se enciende la simulación para esta consulta y al terminar se deja como estaba.
-- Con p_drafts = false no se toca nada: así una llamada interna dentro de un informe simulado sigue simulada.
drop function if exists erp.trial_balance(uuid, integer, integer, date);
create or replace function erp.trial_balance(p_company uuid, p_year integer, p_level integer default null::integer,
                                             p_to_date date default null::date, p_drafts boolean default false)
 returns table(account_no text, name text, name_en text, total_debit numeric, total_credit numeric, debit_balance numeric, credit_balance numeric)
 language plpgsql stable
as $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with mov as (
    select case when p_level is null then a.account_no else left(a.account_no, p_level) end as account_no,
           l.debit, l.credit
    from erp.journal_lines l
    join erp.journal_entries e  on e.id = l.entry_id
    join erp.fiscal_years    fy on fy.id = e.fiscal_year_id
    join erp.gl_accounts     a  on a.id = l.gl_account_id
    where e.company_id = p_company
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

drop function if exists erp.balance_anomalies(uuid, integer, integer, date);
create or replace function erp.balance_anomalies(p_company uuid, p_year integer, p_level integer default null::integer,
                                                 p_to_date date default null::date, p_drafts boolean default false)
 returns table(account_no text, name text, name_en text, expected text, balance numeric, reclass_to text, severity text, note text, note_en text)
 language sql stable
as $function$
  select tb.account_no, tb.name, tb.name_en, r.nature,
         tb.debit_balance - tb.credit_balance,
         r.reclass_to, r.severity, r.note, r.note_en
  from erp.trial_balance(p_company, p_year, p_level, p_to_date, p_drafts) tb
  cross join lateral erp.balance_nature(tb.account_no) r
  -- a nivel de grupo (1) o subgrupo (2) se mezclan cuentas de distinta naturaleza: no se analiza
  where (p_level is null or p_level >= 3)
    and ((r.nature = 'debit'  and tb.credit_balance > 0)
      or (r.nature = 'credit' and tb.debit_balance  > 0))
  order by case r.severity when 'error' then 0 else 1 end, tb.account_no;
$function$;

drop function if exists erp.general_ledger(uuid, integer, text, date);
create or replace function erp.general_ledger(p_company uuid, p_year integer, p_account text, p_to_date date default null::date,
                                              p_drafts boolean default false)
 returns table(posting_date date, entry_no integer, document_no text, description text, debit numeric, credit numeric, running_balance numeric)
 language plpgsql stable
as $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
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
  where l.gl_account_id = (select a.id from erp.gl_accounts a
                           where a.company_id = p_company and a.account_no = p_account)
    and e.fiscal_year_id = (select fy.id from erp.fiscal_years fy
                            where fy.company_id = p_company and fy.year = p_year)
    and erp.counts_in_reports(e.status, e.id)
    and (p_to_date is null or e.posting_date <= p_to_date)
  order by e.posting_date, e.entry_no nulls last, e.created_at, l.line_no;
  perform set_config('erp.simulate', v_prev, true);
end $function$;

drop function if exists erp.financial_statement(uuid, integer, text, date);
create or replace function erp.financial_statement(p_company uuid, p_year integer, p_statement text, p_to_date date default null::date,
                                                   p_drafts boolean default false)
 returns table(code text, parent text, sort integer, level integer, label text, label_en text, is_total boolean, amount numeric, amount_prev numeric)
 language plpgsql stable
as $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with recursive depth(code, level) as (
    select l.code, 0 from erp.fs_lines l where l.statement = p_statement and l.parent is null
    union all
    select c.code, d.level + 1 from depth d join erp.fs_lines c on c.statement = p_statement and c.parent = d.code
  )
  select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total,
         coalesce(n.amount, 0), coalesce(prev.amount, 0)
  from erp.fs_lines l
  join depth d on d.code = l.code
  left join erp.fs_amounts(p_company, p_year, p_statement, p_to_date) n on n.code = l.code
  -- Ejercicio anterior: el Balance, a su cierre (null = completo); la PyG, hasta la misma fecha del año anterior
  left join erp.fs_amounts(p_company, p_year - 1, p_statement,
                           case when p_statement = 'balance' then null
                                else (p_to_date - interval '1 year')::date end) prev on prev.code = l.code
  where l.statement = p_statement
  order by l.sort;
  perform set_config('erp.simulate', v_prev, true);
end $function$;

drop function if exists erp.fs_line_accounts(uuid, integer, text, text, date);
create or replace function erp.fs_line_accounts(p_company uuid, p_year integer, p_statement text, p_code text,
                                                p_to_date date default null::date, p_drafts boolean default false)
 returns table(account_no text, account_name text, account_name_en text, line_code text, amount numeric)
 language plpgsql stable
as $function$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with recursive below(code) as (
    select p_code
    union all
    select l.code from erp.fs_lines l join below b on l.parent = b.code where l.statement = p_statement
  )
  select c.account_no, c.account_name, c.account_name_en, c.line_code, c.amount
  from erp.fs_classified_accounts(p_company, p_year, p_statement, p_to_date) c
  where c.line_code in (select b.code from below b)
  order by c.account_no;
  perform set_config('erp.simulate', v_prev, true);
end $function$;

drop function if exists erp.cash_flow_statement(uuid, integer, text);
create or replace function erp.cash_flow_statement(p_company uuid, p_year integer, p_method text, p_drafts boolean default false)
 returns table(code text, parent text, sort integer, level integer, label text, label_en text, is_total boolean, amount numeric, amount_prev numeric)
 language plpgsql stable security definer
 set search_path to 'erp', 'public'
as $function$
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_method not in ('indirect', 'direct') then raise exception 'Unknown cash flow method: %', p_method; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with recursive depth(code, level) as (
    select l.code, 0 from erp.cf_lines l where l.method = p_method and l.parent is null
    union all
    select c.code, d.level + 1 from depth d join erp.cf_lines c on c.method = p_method and c.parent = d.code
  ), up(code, ancestor) as (
    select l.code, l.code from erp.cf_lines l where l.method = p_method
    union all
    select up.code, p.parent from up join erp.cf_lines p on p.method = p_method and p.code = up.ancestor
    where p.parent is not null
  ), det as (
    select x.line_code, sum(x.amount) as amount, 0 as y from erp.cf_detail(p_company, p_year, p_method) x group by 1
    union all
    select x.line_code, sum(x.amount), 1 from erp.cf_detail(p_company, p_year - 1, p_method) x group by 1
  ), tot as (
    select up.ancestor as code,
           coalesce(sum(d.amount) filter (where d.y = 0), 0) as amount,
           coalesce(sum(d.amount) filter (where d.y = 1), 0) as amount_prev
    from up left join det d on d.line_code = up.code
    group by up.ancestor)
  select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total, t.amount, t.amount_prev
  from erp.cf_lines l
  join depth d on d.code = l.code
  join tot t on t.code = l.code
  where l.method = p_method
  order by l.sort;
  perform set_config('erp.simulate', v_prev, true);
end $function$;

drop function if exists erp.cash_flow_check(uuid, integer);
create or replace function erp.cash_flow_check(p_company uuid, p_year integer, p_drafts boolean default false)
 returns jsonb
 language plpgsql stable security definer
 set search_path to 'erp', 'public'
as $function$
declare
  v_prev   text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
  v_cash   record;
  v_ind    jsonb;
  v_dir    jsonb;
  v_cross  jsonb;
  v_ctot   jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  select * into v_cash from erp.cf_cash(p_company, p_year);
  -- totales por actividad: la segunda letra del código (IA3b → A, DB1 → B)
  select jsonb_object_agg(a, s) into v_ind
  from (select substr(line_code, 2, 1) a, sum(amount) s from erp.cf_indirect_detail(p_company, p_year) group by 1) x;
  select jsonb_object_agg(a, s) into v_dir
  from (select substr(line_code, 2, 1) a, sum(amount) s from erp.cf_direct_detail(p_company, p_year) group by 1) x;

  -- Asientos sin dinero (la 57 no varía) con cuentas de actividades distintas
  with per_act as (
    select f.entry_id as id, substr(f.home_line, 2, 1) as act, sum(f.flow) as amount
    from erp.cf_line_flows(p_company, p_year) f
    where f.entry_id not in (select ce.entry_id from erp.cf_entry_cash(p_company, p_year) ce where ce.cash <> 0)
    group by 1, 2
    having sum(f.flow) <> 0)
  select coalesce(jsonb_agg(jsonb_build_object('entry_no', e.entry_no, 'date', e.posting_date,
                    'description', e.description, 'activities', x.acts) order by e.entry_no), '[]'),
         jsonb_build_object('A', coalesce(sum((x.acts->>'A')::numeric), 0), 'B', coalesce(sum((x.acts->>'B')::numeric), 0),
                            'C', coalesce(sum((x.acts->>'C')::numeric), 0))
    into v_cross, v_ctot
  from (select id, jsonb_object_agg(act, amount) as acts from per_act group by id) x
  join erp.journal_entries e on e.id = x.id;
  perform set_config('erp.simulate', v_prev, true);

  return jsonb_build_object(
    'year', p_year,
    'cash_opening', v_cash.opening, 'cash_closing', v_cash.closing, 'cash_change', v_cash.closing - v_cash.opening,
    'indirect', jsonb_build_object('A', coalesce((v_ind->>'A')::numeric, 0), 'B', coalesce((v_ind->>'B')::numeric, 0),
                                   'C', coalesce((v_ind->>'C')::numeric, 0),
                                   'total', coalesce((select sum(value::numeric) from jsonb_each_text(v_ind)), 0)),
    'direct', jsonb_build_object('A', coalesce((v_dir->>'A')::numeric, 0), 'B', coalesce((v_dir->>'B')::numeric, 0),
                                 'C', coalesce((v_dir->>'C')::numeric, 0),
                                 'total', coalesce((select sum(value::numeric) from jsonb_each_text(v_dir)), 0)),
    'balanced', coalesce((select sum(value::numeric) from jsonb_each_text(v_ind)), 0) = v_cash.closing - v_cash.opening
            and coalesce((select sum(value::numeric) from jsonb_each_text(v_dir)), 0) = v_cash.closing - v_cash.opening,
    'cross_entries', (select coalesce(jsonb_agg(x), '[]') from (select x from jsonb_array_elements(v_cross) x limit 20) s),
    'cross_count', jsonb_array_length(v_cross),
    -- lo que esos asientos explican: indirecto − directo en cada actividad
    'cross_total', v_ctot);
end $function$;

drop function if exists erp.cf_line_accounts(uuid, integer, text, text);
create or replace function erp.cf_line_accounts(p_company uuid, p_year integer, p_method text, p_code text, p_drafts boolean default false)
 returns table(account_no text, account_name text, account_name_en text, amount numeric)
 language plpgsql stable security definer
 set search_path to 'erp', 'public'
as $function$
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_method not in ('indirect', 'direct') then raise exception 'Unknown cash flow method: %', p_method; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with recursive below(code) as (
    select p_code
    union all
    select l.code from erp.cf_lines l join below b on l.parent = b.code where l.method = p_method
  )
  select x.account_no, x.account_name, x.account_name_en, sum(x.amount)
  from erp.cf_detail(p_company, p_year, p_method) x
  where x.line_code in (select code from below)
  group by 1, 2, 3
  having sum(x.amount) <> 0
  order by 1;
  perform set_config('erp.simulate', v_prev, true);
end $function$;

drop function if exists erp.financial_ratios(uuid, integer);
create or replace function erp.financial_ratios(p_company uuid, p_year integer, p_drafts boolean default false)
 returns table(code text, grp text, sort integer, label text, label_en text, formula text, formula_en text, unit text, ref_min numeric, ref_max numeric, help text, help_en text, num numeric, den numeric, value numeric, value_prev numeric, status text)
 language plpgsql stable security definer
 set search_path to 'erp', 'public'
as $function$
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with cur as (select * from erp.ratio_parts(p_company, p_year)),
       prev as (select * from erp.ratio_parts(p_company, p_year - 1)),
       v as (
         select d.code,
                c.num, c.den,
                case when c.den is null then c.num when c.den <> 0 then round(c.num / c.den, 4) end as value,
                case when pr.den is null then pr.num when pr.den <> 0 then round(pr.num / pr.den, 4) end as value_prev
         from erp.ratio_defs d
         left join cur c on c.code = d.code
         left join prev pr on pr.code = d.code)
  select d.code, d.grp, d.sort, d.label, d.label_en, d.formula, d.formula_en, d.unit, d.ref_min, d.ref_max,
         d.help, d.help_en, v.num, v.den, v.value, v.value_prev,
         case when v.value is null or (d.ref_min is null and d.ref_max is null) then null
              when v.value < d.ref_min then 'low'
              when v.value > d.ref_max then 'high'
              else 'ok' end
  from erp.ratio_defs d
  join v on v.code = d.code
  order by array_position(array['liquidity', 'solvency', 'profitability', 'activity', 'cash'], d.grp), d.sort;
  perform set_config('erp.simulate', v_prev, true);
end $function$;

-- ---------- Permisos (los de siempre, con las firmas nuevas) ----------
revoke execute on function erp.simulating(), erp.draft_ready(uuid), erp.counts_in_reports(text, uuid), erp.report_drafts(uuid, integer, date),
  erp.trial_balance(uuid, integer, integer, date, boolean), erp.balance_anomalies(uuid, integer, integer, date, boolean),
  erp.general_ledger(uuid, integer, text, date, boolean), erp.financial_statement(uuid, integer, text, date, boolean),
  erp.fs_line_accounts(uuid, integer, text, text, date, boolean), erp.cash_flow_statement(uuid, integer, text, boolean),
  erp.cash_flow_check(uuid, integer, boolean), erp.cf_line_accounts(uuid, integer, text, text, boolean),
  erp.financial_ratios(uuid, integer, boolean)
  from anon, public;
grant execute on function erp.simulating(), erp.draft_ready(uuid), erp.counts_in_reports(text, uuid), erp.report_drafts(uuid, integer, date),
  erp.trial_balance(uuid, integer, integer, date, boolean), erp.balance_anomalies(uuid, integer, integer, date, boolean),
  erp.general_ledger(uuid, integer, text, date, boolean), erp.financial_statement(uuid, integer, text, date, boolean),
  erp.fs_line_accounts(uuid, integer, text, text, date, boolean), erp.cash_flow_statement(uuid, integer, text, boolean),
  erp.cash_flow_check(uuid, integer, boolean), erp.cf_line_accounts(uuid, integer, text, text, boolean),
  erp.financial_ratios(uuid, integer, boolean)
  to authenticated;

-- La API de Supabase (PostgREST) relee las funciones
notify pgrst, 'reload schema';
