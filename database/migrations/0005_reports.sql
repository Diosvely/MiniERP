-- =====================================================================
-- 0005 · REPORTS · Informes
--   v_general_journal  → libro diario
--   v_general_ledger   → libro mayor (con saldo acumulado · running balance)
--   trial_balance()    → balance de sumas y saldos
--   v_tax_book         → libro registro de IVA / IGIC
-- ---------------------------------------------------------------------
-- Solo cuentan los asientos POSTED. Los borradores no existen para los informes.
-- Las vistas usan security_invoker: cada usuario solo ve lo que le permite RLS.
-- =====================================================================

-- ---------------------------------------------------------------------
-- GENERAL JOURNAL · Libro diario: asientos en orden cronológico, con sus apuntes
-- ---------------------------------------------------------------------
create or replace view erp.v_general_journal with (security_invoker = true) as
select e.company_id,
       fy.year          as fiscal_year,
       e.entry_no,
       e.posting_date,
       e.description    as entry_description,
       e.document_no,
       e.entry_type,
       l.line_no,
       a.account_no,
       a.name           as account_name,
       a.name_en        as account_name_en,
       l.debit,
       l.credit,
       coalesce(l.description, e.description) as description,
       e.id             as entry_id
from erp.journal_entries e
join erp.fiscal_years  fy on fy.id = e.fiscal_year_id
join erp.journal_lines l  on l.entry_id = e.id
join erp.gl_accounts   a  on a.id = l.gl_account_id
where e.status = 'posted';

-- ---------------------------------------------------------------------
-- GENERAL LEDGER · Libro mayor: movimientos de cada subcuenta con saldo acumulado
-- (balance > 0 = deudor / debit balance · balance < 0 = acreedor / credit balance)
-- ---------------------------------------------------------------------
create or replace view erp.v_general_ledger with (security_invoker = true) as
select e.company_id,
       fy.year          as fiscal_year,
       a.account_no,
       a.name           as account_name,
       a.name_en        as account_name_en,
       e.posting_date,
       e.entry_no,
       coalesce(l.description, e.description) as description,
       l.debit,
       l.credit,
       sum(l.debit - l.credit) over (
         partition by l.gl_account_id, e.fiscal_year_id
         order by e.posting_date, e.entry_no, l.line_no
         rows between unbounded preceding and current row
       ) as running_balance
from erp.journal_entries e
join erp.fiscal_years  fy on fy.id = e.fiscal_year_id
join erp.journal_lines l  on l.entry_id = e.id
join erp.gl_accounts   a  on a.id = l.gl_account_id
where e.status = 'posted';

-- ---------------------------------------------------------------------
-- TRIAL BALANCE · Balance de sumas y saldos
--   p_level: 1 = grupo, 2 = subgrupo, 3 = cuenta, null = subcuenta
--   p_to_date: fecha de corte (por defecto, todo el ejercicio)
-- Uso: select * from erp.trial_balance('<company>', 2026, 3);
-- ---------------------------------------------------------------------
create or replace function erp.trial_balance(
  p_company uuid, p_year int, p_level int default null, p_to_date date default null)
returns table (account_no text, name text, name_en text, total_debit numeric, total_credit numeric,
               debit_balance numeric, credit_balance numeric)
language sql stable as $$
  with mov as (
    select case when p_level is null then a.account_no else left(a.account_no, p_level) end as account_no,
           l.debit, l.credit
    from erp.journal_lines l
    join erp.journal_entries e  on e.id = l.entry_id
    join erp.fiscal_years    fy on fy.id = e.fiscal_year_id
    join erp.gl_accounts     a  on a.id = l.gl_account_id
    where e.company_id = p_company
      and fy.year = p_year
      and e.status = 'posted'
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
$$;

-- ---------------------------------------------------------------------
-- TAX BOOK · Libro registro de IVA / IGIC
-- Sale de los apuntes de cuotas (472 input tax / 477 output tax) que llevan tax_code y tax_base.
-- ---------------------------------------------------------------------
create or replace view erp.v_tax_book with (security_invoker = true) as
select e.company_id,
       fy.year        as fiscal_year,
       e.posting_date,
       e.entry_no,
       e.document_no,
       case a.template_account when '472' then 'input' when '477' then 'output' end as tax_class,
       t.tax_type,
       t.rate_pct,
       bp.vat_registration_no,
       bp.name        as partner_name,
       l.tax_base,
       case a.template_account when '472' then l.debit - l.credit else l.credit - l.debit end as tax_amount
from erp.journal_lines l
join erp.journal_entries        e  on e.id = l.entry_id
join erp.fiscal_years           fy on fy.id = e.fiscal_year_id
join erp.gl_accounts            a  on a.id = l.gl_account_id
join erp.tax_codes              t  on t.code = l.tax_code
left join erp.business_partners bp on bp.id = l.partner_id
where e.status = 'posted'
  and a.template_account in ('472', '477');
