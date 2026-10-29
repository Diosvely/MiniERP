-- =====================================================================
-- 0076 · Rendimiento: «La consulta ha tardado demasiado» en Comprobaciones y en Caso (v0.52.1)
-- ---------------------------------------------------------------------
-- En Supabase, con empresas grandes en la base (aunque sean de otros), Comprobaciones y Caso superaban el límite de
-- 8 s de Supabase (statement timeout). Dos causas, reproducidas con una empresa de 150.000 asientos al lado del caso:
--
--   1. CONSULTAS QUE RECORRÍAN TODA LA BASE. erp.audit_lines buscaba el documento de cada apunte (factura, pago,
--      nómina, importación…) con «= coalesce(e.reversal_of, e.id)». Con la seguridad fila a fila (RLS), PostgreSQL no
--      usa el índice para una condición así y recorría la tabla entera, de todas las empresas, por cada apunte. Ahora
--      la clave se calcula aparte y cada búsqueda va por su índice. Las
--      funciones de flujos (cf_entry_cash, cf_cash, cf_line_flows) empezaban por las cuentas 57 de todas las empresas
--      y sus apuntes. Ahora el origen se busca por su clave y los apuntes se filtran por la empresa
--      (journal_lines.company_id, con su índice). Mismo resultado.
--   2. JIT DE POSTGRESQL. Con consultas de coste estimado alto, PostgreSQL compila «al vuelo» (JIT) cada consulta de
--      cada función, y en estas pantallas la compilación tardaba más que la propia consulta (2,5 s frente a 0,08 s).
--      Se apaga para las llamadas de la web (roles authenticated y anon) y para las funciones plpgsql del ERP.
--
-- Comprobaciones: de 5 s a 0,1 s · Caso: de 1,2 s a 0,27 s (en la prueba local). Se puede ejecutar dos veces.
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.audit_lines(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(entry_id uuid, entry_no integer, posting_date date, k uuid, source text, account_no text, account_name text, debit numeric, credit numeric, tax_code text)
 LANGUAGE sql
 STABLE
AS $function$
  select e.id, e.entry_no, e.posting_date, kk.k,
         case when exists (select 1 from erp.invoices i where i.entry_id = kk.k) then 'invoice'
              when exists (select 1 from erp.tax_settlements s where s.entry_id = kk.k) then 'settlement'
              when exists (select 1 from erp.pro_rata p where p.entry_id = kk.k) then 'pro_rata'
              -- v0.36.0: periodificaciones y deterioros (antes que los cobros: la insolvencia firme también lo es)
              when exists (select 1 from erp.accruals ac where kk.k in (ac.entry_id, ac.reversal_entry_id)) then 'accrual'
              when exists (select 1 from erp.receivable_impairments ri where kk.k in (ri.entry_id, ri.end_entry_id))
                or exists (select 1 from erp.receivable_writeoffs w where w.entry_id = kk.k) then 'impairment'
              -- v0.37.0: provisiones
              when exists (select 1 from erp.provision_movements pm where pm.entry_id = kk.k) then 'provision'
              when exists (select 1 from erp.inventory_counts ic where ic.entry_id = kk.k) then 'inventory'
              -- v0.41.0: Impuesto sobre Sociedades
              when exists (select 1 from erp.corporate_tax_returns ct
                           where kk.k in (ct.current_entry_id, ct.deferred_entry_id)) then 'corporate_tax'
              -- v0.42.0: operaciones societarias
              when exists (select 1 from erp.equity_operations eo where kk.k = any (eo.entry_ids)) then 'equity'
              -- v0.43.0: préstamos y arrendamiento financiero
              when exists (select 1 from erp.loan_events le where le.entry_id = kk.k) then 'financing'
              -- v0.44.0: subvenciones
              when exists (select 1 from erp.grant_events ge where ge.entry_id = kk.k) then 'grant'
              -- v0.38.0: nóminas y sus pagos
              when exists (select 1 from erp.payroll_runs pr
                           where kk.k in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id)) then 'payroll'
              when exists (select 1 from erp.payments py where not py.linked
                           and kk.k in (py.entry_id, py.cancel_entry_id)) then 'payment'
              when exists (select 1 from erp.asset_depreciations d where d.entry_id = kk.k)
                or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = kk.k)
                or exists (select 1 from erp.asset_events ae where ae.entry_id = kk.k) then 'asset'
              -- v0.52.1: el origen (importado) se busca por su clave; antes se cruzaba con TODOS los asientos de la base
              when (select o.import_batch_id from erp.journal_entries o where o.id = kk.k) is not null then 'import'
              else 'manual' end,
         g.account_no, g.name, l.debit, l.credit, l.tax_code
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id
  -- v0.52.1: la clave del documento (el asiento o el que anula), calculada aparte («offset 0»): así cada búsqueda de
  -- abajo usa el índice de su tabla en vez de recorrerla entera con la seguridad fila a fila
  cross join lateral (select coalesce(e.reversal_of, e.id) as k offset 0) kk
  join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company
  join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
    and (p_to_date is null or e.posting_date <= p_to_date);
$function$
;

CREATE OR REPLACE FUNCTION erp.cf_entry_cash(p_company uuid, p_year integer)
 RETURNS TABLE(entry_id uuid, cash numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select l.entry_id, sum(l.debit - l.credit)
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  join erp.journal_lines l on l.entry_id = e.id and l.company_id = p_company
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  where e.company_id = p_company and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
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
  from erp.journal_lines l
  join erp.journal_entries e on e.id = l.entry_id and erp.counts_in_reports(e.status, e.id)
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  where e.company_id = p_company and l.company_id = p_company;
$function$;

CREATE OR REPLACE FUNCTION erp.cf_line_flows(p_company uuid, p_year integer)
 RETURNS TABLE(entry_id uuid, account_no text, account_name text, account_name_en text, flow numeric, home_line text, adjust_line text, direct_line text, in_result boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with base as (
    select l.entry_id, g.id as acc_id, g.account_no, g.name, g.name_en, -sum(l.debit - l.credit) as flow
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and erp.counts_in_reports(e.status, e.id) and e.entry_type = 'normal'
    join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and l.company_id = p_company and g.account_no not like '57%'
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

-- ---------- JIT apagado para la web y las funciones del ERP ----------
alter role authenticated set jit = off;
alter role anon set jit = off;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
           where n.nspname = 'erp' and l.lanname = 'plpgsql' and p.prokind = 'f'
             and not coalesce('jit=off' = any (p.proconfig), false)
  loop
    execute format('alter function %s set jit = off', f.sig);
  end loop;
end $$;

notify pgrst, 'reload schema';
