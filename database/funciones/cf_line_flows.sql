-- =====================================================================
-- erp.cf_line_flows · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0066_complete_case 0074_report_simulation 0076_performance 0077_large_companies   →   la vigente es la de 0077_large_companies
-- =====================================================================

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
$function$
;
