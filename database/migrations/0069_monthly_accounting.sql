-- =====================================================================
-- 0069 · CONTABILIDAD MES A MES · v0.47.0 (mejoras de uso 7)
-- ---------------------------------------------------------------------
-- Cada ejercicio ya tenía sus 12 periodos abiertos o cerrados, y el motor ya rechazaba un asiento en un periodo cerrado
-- (como la OB52 de SAP). Aquí se añade lo que faltaba para llevar una empresa mes a mes, como en ContaSol:
--   · Fecha de inicio de la contabilidad (companies.start_date) y modo mes a mes (companies.monthly), al crear la
--     empresa (erp.start_accounting). Los meses anteriores al de inicio quedan cerrados.
--   · MES DE TRABAJO (erp.work_month): el primer mes abierto. En el modo mes a mes, solo se contabiliza en él, como la
--     ventana «Permitir registro desde / hasta» de Business Central. El cierre y la apertura del ejercicio no cuentan.
--   · Cerrar el mes (erp.month_close_preview y erp.close_month), con avisos de lo que suele faltar: borradores, la
--     nómina del mes y, al cerrar un trimestre, la liquidación del IVA / IGIC. Diciembre lo cierra el Cierre del
--     ejercicio.
--   · Reabrir el último mes cerrado (erp.reopen_month), solo el administrador.
--   · Las empresas que no lo marcan (las que ya existen, las importadas y las de los casos completos) siguen igual.
-- Re-ejecutable.
-- =====================================================================

-- 1) La empresa: fecha de inicio y modo mes a mes
alter table erp.companies add column if not exists start_date date;
alter table erp.companies add column if not exists monthly boolean not null default false;
comment on column erp.companies.start_date is 'Fecha de inicio de la contabilidad (la elige quien crea la empresa)';
comment on column erp.companies.monthly is 'Contabilidad mes a mes: solo se contabiliza en el mes de trabajo (el primer mes abierto)';

-- Mis empresas (versión de la 0068 con la fecha de inicio y el modo mes a mes)
create or replace view erp.v_my_companies with (security_invoker = true) as
select c.id, c.name, c.vat_registration_no, c.industry, c.tax_territory,
       c.posting_account_digits, c.is_demo, c.created_at,
       erp.my_role(c.id) as my_role,
       c.vat_regime,
       c.data_credit,
       erp.is_data_owner(c.id) as is_data_owner,
       c.control_mode,
       c.case_key,
       c.case_mode,
       c.start_date,
       c.monthly
from erp.companies c;

-- 2) El mes de trabajo: el primer mes abierto de los ejercicios abiertos, desde la fecha de inicio
create or replace function erp.work_period(p_company uuid)
returns erp.accounting_periods language sql stable security definer set search_path = erp, public as $$
  select p.* from erp.accounting_periods p
  join erp.fiscal_years fy on fy.id = p.fiscal_year_id and fy.company_id = p_company and fy.status = 'open'
  join erp.companies c on c.id = p_company
  where p.status = 'open' and p.ending_date >= coalesce(c.start_date, '0001-01-01'::date)
  order by p.starting_date
  limit 1;
$$;
revoke execute on function erp.work_period(uuid) from anon, public, authenticated;

create or replace function erp.work_month(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare v_co erp.companies; v_p erp.accounting_periods; v_last date;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_co from erp.companies where id = p_company;
  v_p := erp.work_period(p_company);
  if v_p.fiscal_year_id is null then
    return jsonb_build_object('monthly', v_co.monthly, 'start_date', v_co.start_date, 'year', null);
  end if;
  select max(j.posting_date) into v_last from erp.journal_entries j
  where j.company_id = p_company and j.status = 'posted' and j.entry_type = 'normal'
    and j.posting_date between v_p.starting_date and v_p.ending_date;
  return jsonb_build_object('monthly', v_co.monthly, 'start_date', v_co.start_date,
    'year', extract(year from v_p.starting_date)::int, 'month', v_p.period_no,
    'from', greatest(v_p.starting_date, coalesce(v_co.start_date, v_p.starting_date)), 'to', v_p.ending_date,
    'last_entry_date', v_last,
    -- la fecha que proponen los formularios: la del último asiento del mes o, si no hay, el primer día del mes
    'work_date', coalesce(v_last, greatest(v_p.starting_date, coalesce(v_co.start_date, v_p.starting_date))),
    'december', v_p.period_no = 12);
end $$;

-- 3) Empezar la contabilidad: el ejercicio de la fecha de inicio y, en el modo mes a mes, los meses anteriores cerrados
create or replace function erp.start_accounting(p_company uuid, p_start date, p_monthly boolean default true)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare v_fy uuid;
begin
  if not erp.is_admin(p_company) then raise exception 'No permission: only the company admin can set the start date'; end if;
  if p_start is null then raise exception 'The start date is required'; end if;
  if exists (select 1 from erp.journal_entries j where j.company_id = p_company) then
    raise exception 'The company already has entries: the start date can only be set in a new company';
  end if;
  select id into v_fy from erp.fiscal_years where company_id = p_company and year = extract(year from p_start)::int;
  if v_fy is null then v_fy := erp.create_fiscal_year(p_company, extract(year from p_start)::int); end if;
  update erp.companies set start_date = p_start, monthly = coalesce(p_monthly, false) where id = p_company;
  update erp.accounting_periods set status = case when p_monthly and ending_date < date_trunc('month', p_start)::date then 'closed' else 'open' end
  where fiscal_year_id = v_fy;
  return erp.work_month(p_company);
end $$;

-- 4) La regla del motor: en el modo mes a mes, solo se contabiliza en el mes de trabajo
--    (el cierre y la apertura del ejercicio no son asientos normales: no cuentan)
create or replace function erp.tg_entry_work_month()
returns trigger language plpgsql security definer set search_path = erp, public as $$
declare v_p erp.accounting_periods; v_start date;
begin
  if new.status <> 'posted' or new.entry_type <> 'normal' or (tg_op = 'UPDATE' and old.status = 'posted') then return new; end if;
  select c.start_date into v_start from erp.companies c where c.id = new.company_id and c.monthly;
  if not found then return new; end if;
  if new.posting_date < v_start then
    raise exception 'Monthly accounting: the accounting starts on %', to_char(v_start, 'DD/MM/YYYY');
  end if;
  v_p := erp.work_period(new.company_id);
  if v_p.fiscal_year_id is not null and new.posting_date > v_p.ending_date then
    raise exception 'Monthly accounting: the open month is % (% to %); close it before posting on %',
      to_char(v_p.starting_date, 'MM/YYYY'), to_char(v_p.starting_date, 'DD/MM/YYYY'), to_char(v_p.ending_date, 'DD/MM/YYYY'),
      to_char(new.posting_date, 'DD/MM/YYYY');
  end if;
  return new;
end $$;
drop trigger if exists entry_work_month on erp.journal_entries;
create trigger entry_work_month
  before insert or update of status on erp.journal_entries
  for each row execute function erp.tg_entry_work_month();

-- 5) Cerrar el mes: antes, lo que suele faltar
create or replace function erp.month_close_preview(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare v_p erp.accounting_periods; v_w jsonb := '[]'::jsonb; v_n int; v_q int; v_tax text;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  v_p := erp.work_period(p_company);
  if v_p.fiscal_year_id is null then raise exception 'There is no open month'; end if;
  -- borradores del mes: no se podrán contabilizar con el mes cerrado
  select count(*) into v_n from erp.journal_entries j
  where j.company_id = p_company and j.status = 'draft' and j.posting_date between v_p.starting_date and v_p.ending_date;
  if v_n > 0 then v_w := v_w || jsonb_build_object('code', 'drafts', 'count', v_n); end if;
  -- la nómina del mes, si hay empleados de alta
  if exists (select 1 from erp.employees m where m.company_id = p_company and m.hire_date <= v_p.ending_date
             and (m.end_date is null or m.end_date >= v_p.starting_date))
     and not exists (select 1 from erp.payroll_runs r where r.company_id = p_company and r.period = v_p.ending_date and r.status = 'posted') then
    v_w := v_w || jsonb_build_object('code', 'payroll');
  end if;
  -- al cerrar un trimestre, su liquidación del IVA / IGIC
  if v_p.period_no in (3, 6, 9, 12) then
    v_q := v_p.period_no / 3;
    select case when tax_territory = 'canary_islands' then 'IGIC' else 'VAT' end into v_tax from erp.companies where id = p_company;
    if exists (select 1 from erp.tax_setup s where s.company_id = p_company)
       and not exists (select 1 from erp.tax_settlements t where t.company_id = p_company and t.year = extract(year from v_p.starting_date)
                       and t.quarter = v_q and t.status = 'posted') then
      v_w := v_w || jsonb_build_object('code', 'settlement', 'quarter', v_q, 'tax', v_tax);
    end if;
  end if;
  return jsonb_build_object('year', extract(year from v_p.starting_date)::int, 'month', v_p.period_no,
    'from', v_p.starting_date, 'to', v_p.ending_date, 'december', v_p.period_no = 12,
    'entries', (select count(*) from erp.journal_entries j where j.company_id = p_company and j.status = 'posted'
                and j.posting_date between v_p.starting_date and v_p.ending_date),
    'warnings', v_w);
end $$;

create or replace function erp.close_month(p_company uuid, p_accept_warnings boolean default false)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare v_p erp.accounting_periods; v_prev jsonb;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to close months in this company'; end if;
  if not exists (select 1 from erp.companies where id = p_company and monthly) then
    raise exception 'This company does not use monthly accounting';
  end if;
  perform pg_advisory_xact_lock(hashtext('month/' || p_company));
  v_p := erp.work_period(p_company);
  if v_p.fiscal_year_id is null then raise exception 'There is no open month'; end if;
  if v_p.period_no = 12 then raise exception 'December is closed with the year-end closing'; end if;
  v_prev := erp.month_close_preview(p_company);
  if jsonb_array_length(v_prev->'warnings') > 0 and not coalesce(p_accept_warnings, false) then
    raise exception 'Review and accept the warnings before closing the month';
  end if;
  update erp.accounting_periods set status = 'closed' where fiscal_year_id = v_p.fiscal_year_id and period_no = v_p.period_no;
  return jsonb_build_object('closed', jsonb_build_object('year', extract(year from v_p.starting_date)::int, 'month', v_p.period_no),
                            'warnings', v_prev->'warnings', 'work_month', erp.work_month(p_company));
end $$;

-- 6) Reabrir el último mes cerrado (el anterior al mes de trabajo, del mismo ejercicio)
create or replace function erp.reopen_month(p_company uuid)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare v_p erp.accounting_periods; v_prev erp.accounting_periods; v_start date;
begin
  if not erp.is_admin(p_company) then raise exception 'No permission: only the company admin can reopen a month'; end if;
  if not exists (select 1 from erp.companies where id = p_company and monthly) then
    raise exception 'This company does not use monthly accounting';
  end if;
  perform pg_advisory_xact_lock(hashtext('month/' || p_company));
  v_p := erp.work_period(p_company);
  if v_p.fiscal_year_id is null then raise exception 'There is no open month'; end if;
  select start_date into v_start from erp.companies where id = p_company;
  select * into v_prev from erp.accounting_periods
  where fiscal_year_id = v_p.fiscal_year_id and period_no = v_p.period_no - 1 and ending_date >= coalesce(v_start, '0001-01-01'::date);
  if v_prev.fiscal_year_id is null then
    if v_p.period_no = 1 and exists (select 1 from erp.fiscal_years fy where fy.company_id = p_company
                                     and fy.year = extract(year from v_p.starting_date)::int - 1 and fy.status = 'closed') then
      raise exception 'The previous month belongs to a closed fiscal year: reopen the fiscal year first';
    end if;
    raise exception 'There is no closed month to reopen';
  end if;
  update erp.accounting_periods set status = 'open' where fiscal_year_id = v_prev.fiscal_year_id and period_no = v_prev.period_no;
  return erp.work_month(p_company);
end $$;

revoke execute on function erp.work_month(uuid), erp.start_accounting(uuid, date, boolean), erp.month_close_preview(uuid),
  erp.close_month(uuid, boolean), erp.reopen_month(uuid) from anon, public;
grant execute on function erp.work_month(uuid), erp.start_accounting(uuid, date, boolean), erp.month_close_preview(uuid),
  erp.close_month(uuid, boolean), erp.reopen_month(uuid) to authenticated;
revoke execute on function erp.tg_entry_work_month() from anon, public, authenticated;
