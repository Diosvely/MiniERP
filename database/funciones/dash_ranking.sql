-- =====================================================================
-- erp.dash_ranking · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0083_sales_expenses_dashboard 0084_quality_dashboard   →   la vigente es la de 0084_quality_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.dash_ranking(p_company uuid, p_year integer, p_to date, p_source text)
 RETURNS TABLE(key text, label text, amount numeric, note text, note_en text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
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
$function$
;
