-- =====================================================================
-- erp.home_kpis · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0031_home_kpis   →   la vigente es la de 0031_home_kpis
-- =====================================================================

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
    join erp.journal_lines   l on l.entry_id = e.id
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
    join erp.journal_lines   l on l.entry_id = e.id
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
      join erp.journal_lines   l on l.entry_id = e.id
      join erp.gl_accounts     a on a.id = l.gl_account_id
      where e.company_id = p_company and e.fiscal_year_id = prev.id and e.status = 'posted'
        and e.entry_type not in ('closing_pl', 'closing') and left(a.account_no, 1) in ('6', '7')));
  end if;

  return v_out;
end $function$
;
