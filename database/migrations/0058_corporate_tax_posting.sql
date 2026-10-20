-- =====================================================================
-- 0058 · IMPUESTO SOBRE SOCIEDADES (II): los asientos · v0.41.0
-- ---------------------------------------------------------------------
-- Contabilizar el impuesto del ejercicio (erp.corporate_tax_post), a la fecha de cierre y antes de la regularización:
--   · IMPUESTO CORRIENTE (lo que se paga por este año):
--       6300 Impuesto corriente               D  cuota
--       473  HP retenciones y pagos a cuenta    H  lo retenido y pagado a cuenta (cada subcuenta, su saldo)
--       4752 HP acreedora por IS                H  cuota diferencial a ingresar   ─o─   4709 D a devolver
--   · IMPUESTO DIFERIDO (NRV 13.ª: el gasto del año no depende de cuándo se paga):
--       4740 Activos por diferencias temporarias deducibles   D al nacer · H al revertir      (× tipo)
--       4745 Crédito por pérdidas a compensar                 D si se registra · H al compensar
--       6301 Impuesto diferido                                la diferencia, al Debe (gasto) o al Haber (ingreso)
--   Se guarda el cálculo (erp.corporate_tax_returns.result): de ahí salen las bases negativas y las diferencias
--   pendientes de los años siguientes. Deshacer (erp.corporate_tax_cancel) anula los dos asientos con contraasiento,
--   solo si el año siguiente no tiene su impuesto contabilizado y el ejercicio no está cerrado.
-- También: los tipos de las empresas de reducida dimensión de 2025 y 2027-2029 (DT 44.ª LIS: 24 / 22 / 21 / 20 %;
-- PENDIENTE DE VALIDAR POR DIOSVELY), y el impuesto como módulo propio en el diario, el auditor y el borrado.
-- Re-ejecutable.
-- =====================================================================

-- 1) Tipos de la reducida dimensión de otros años (DT 44.ª; la microempresa, solo 2026: avisa en otros años)
insert into erp.corporate_tax_rates (valid_from_year, regime, upto, rate) values
(2025, 'general', null, 25), (2025, 'erd', null, 24), (2025, 'new_entity', null, 15),
(2027, 'erd', null, 22), (2028, 'erd', null, 21), (2029, 'erd', null, 20)
on conflict (valid_from_year, regime, rate) do update set upto = excluded.upto;

-- 2) Los asientos de cada declaración
alter table erp.corporate_tax_returns add column if not exists current_entry_id uuid references erp.journal_entries(id);
alter table erp.corporate_tax_returns add column if not exists deferred_entry_id uuid references erp.journal_entries(id);
alter table erp.corporate_tax_returns add column if not exists posted_at timestamptz;
create index if not exists corporate_tax_returns_current_idx on erp.corporate_tax_returns (current_entry_id);
create index if not exists corporate_tax_returns_deferred_idx on erp.corporate_tax_returns (deferred_entry_id);

-- Un asiento del impuesto: p_lines = [{ account_id, debit, credit }] (las de importe cero no se graban)
create or replace function erp.corporate_tax_entry(p_company uuid, p_date date, p_desc text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v_entry uuid;
begin
  if not exists (select 1 from jsonb_array_elements(p_lines) l where coalesce((l->>'debit')::numeric, 0) + coalesce((l->>'credit')::numeric, 0) > 0) then
    return null;
  end if;
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (p_company, erp.adjust_fiscal_year(p_company, p_date), p_date, left(p_desc, 250), 'IS ' || extract(year from p_date))
  returning id into v_entry;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select v_entry, p_company, row_number() over (), (l->>'account_id')::uuid, coalesce((l->>'debit')::numeric, 0), coalesce((l->>'credit')::numeric, 0)
  from jsonb_array_elements(p_lines) l where coalesce((l->>'debit')::numeric, 0) + coalesce((l->>'credit')::numeric, 0) > 0;
  perform erp.adjust_finish(v_entry);
  return v_entry;
end $$;

-- Contabilizar
create or replace function erp.corporate_tax_post(p_company uuid, p_year int)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_fy erp.fiscal_years; v_ret uuid; g jsonb; v_cur jsonb := '[]'; v_def jsonb := '[]'; a record;
  v_quota numeric; v_diff numeric; v_dtax numeric; v_e1 uuid; v_e2 uuid; v_d numeric;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post the corporate tax of this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', p_year; end if;
  if exists (select 1 from erp.year_closings c where c.company_id = p_company and c.fiscal_year_id = v_fy.id and c.status = 'posted') then
    raise exception 'The year % is already closed (regularization posted): the corporate tax goes before it', p_year;
  end if;
  v_ret := erp.corporate_tax_prepare(p_company, p_year);
  g := erp.corporate_tax_calc(p_company, p_year);
  v_quota := (g->>'current_tax')::numeric; v_diff := (g->>'differential')::numeric; v_dtax := (g->>'deferred_tax')::numeric;

  -- impuesto corriente
  v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '6300', 'Impuesto corriente'), 'debit', v_quota, 'credit', 0);
  for a in select gl.id, sum(l.debit - l.credit) as bal
           from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts gl on gl.id = l.gl_account_id
           where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
             and e.entry_type not in ('closing_pl', 'closing') and gl.account_no like '473%'
           group by gl.id having sum(l.debit - l.credit) <> 0 loop
    v_cur := v_cur || jsonb_build_object('account_id', a.id, 'debit', greatest(-a.bal, 0), 'credit', greatest(a.bal, 0));
  end loop;
  if v_diff > 0 then
    v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '4752', 'Hacienda Pública, acreedora por impuesto sobre sociedades'), 'debit', 0, 'credit', v_diff);
  elsif v_diff < 0 then
    v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '4709', 'Hacienda Pública, deudora por devolución de impuestos'), 'debit', -v_diff, 'credit', 0);
  end if;
  v_e1 := erp.corporate_tax_entry(p_company, v_fy.ending_date, 'Impuesto sobre Sociedades ' || p_year || ' · impuesto corriente', v_cur);

  -- impuesto diferido
  v_d := round((g->>'temporary_increase')::numeric * (g->>'deferred_rate')::numeric / 100, 2) - round((g->>'temporary_decrease')::numeric * (g->>'deferred_rate')::numeric / 100, 2);
  if v_d <> 0 then
    v_def := v_def || jsonb_build_object('account_id', erp.adjust_account(p_company, '4740', 'Activos por diferencias temporarias deducibles'),
                                         'debit', greatest(v_d, 0), 'credit', greatest(-v_d, 0));
  end if;
  if (g->>'loss_credit')::numeric > 0 or (g->>'loss_credit_used')::numeric > 0 then
    v_def := v_def || jsonb_build_object('account_id', erp.adjust_account(p_company, '4745', 'Crédito por pérdidas a compensar del ejercicio'),
                                         'debit', (g->>'loss_credit')::numeric, 'credit', (g->>'loss_credit_used')::numeric);
  end if;
  if v_dtax <> 0 then
    v_def := v_def || jsonb_build_object('account_id', erp.adjust_account(p_company, '6301', 'Impuesto diferido'),
                                         'debit', greatest(v_dtax, 0), 'credit', greatest(-v_dtax, 0));
  end if;
  v_e2 := erp.corporate_tax_entry(p_company, v_fy.ending_date, 'Impuesto sobre Sociedades ' || p_year || ' · impuesto diferido', v_def);

  update erp.corporate_tax_returns set status = 'posted', result = g - 'status' - 'return_id', current_entry_id = v_e1,
    deferred_entry_id = v_e2, posted_at = now() where id = v_ret;
  return g || jsonb_build_object('status', 'posted', 'return_id', v_ret,
    'current_entry_no', (select entry_no from erp.journal_entries where id = v_e1),
    'deferred_entry_no', (select entry_no from erp.journal_entries where id = v_e2));
end $$;

-- Deshacer: contraasientos de los dos asientos y la declaración vuelve a borrador
create or replace function erp.corporate_tax_cancel(p_company uuid, p_year int)
returns void language plpgsql security definer set search_path = erp, public as $$
declare v_fy erp.fiscal_years; r erp.corporate_tax_returns;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to change the corporate tax of this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  select * into r from erp.corporate_tax_returns where fiscal_year_id = v_fy.id;
  if r.status is distinct from 'posted' then raise exception 'The corporate tax of % is not posted', p_year; end if;
  if v_fy.status = 'closed' or exists (select 1 from erp.year_closings c where c.company_id = p_company and c.fiscal_year_id = v_fy.id and c.status = 'posted') then
    raise exception 'The year % is closed: reopen it first', p_year;
  end if;
  if exists (select 1 from erp.corporate_tax_returns x join erp.fiscal_years f on f.id = x.fiscal_year_id
             where x.company_id = p_company and x.status = 'posted' and f.year > p_year) then
    raise exception 'A later corporate tax is posted: undo it first (it uses this one)';
  end if;
  if r.current_entry_id is not null then perform erp.adjust_reverse(r.current_entry_id, v_fy.ending_date, 'Deshacer el Impuesto sobre Sociedades'); end if;
  if r.deferred_entry_id is not null then perform erp.adjust_reverse(r.deferred_entry_id, v_fy.ending_date, 'Deshacer el Impuesto sobre Sociedades'); end if;
  update erp.corporate_tax_returns set status = 'draft', result = null, current_entry_id = null, deferred_entry_id = null, posted_at = null
  where id = r.id;
end $$;

revoke execute on function erp.corporate_tax_entry(uuid, date, text, jsonb) from anon, public, authenticated;
revoke execute on function erp.corporate_tax_post(uuid, int), erp.corporate_tax_cancel(uuid, int) from anon, public;
grant execute on function erp.corporate_tax_post(uuid, int), erp.corporate_tax_cancel(uuid, int) to authenticated;

-- 3) El impuesto, módulo propio: no se anula desde el diario, no es un asiento manual, tiene su origen en el diario y
--    en el auditor, y se borra con la empresa (versiones de la 0049; cambia solo lo marcado «v0.41.0»)
CREATE OR REPLACE FUNCTION erp.tg_entry_adjust_reverse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.adjust_engine', true), '') <> 'on' then
    if exists (select 1 from erp.accruals where new.reversal_of in (entry_id, reversal_entry_id)) then
      raise exception 'This entry belongs to an accrual: undo it from Year-end adjustments';
    end if;
    if exists (select 1 from erp.receivable_impairments where new.reversal_of in (entry_id, end_entry_id))
       or exists (select 1 from erp.receivable_writeoffs where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a receivable impairment: undo it from Year-end adjustments';
    end if;
    -- v0.37.0: provisiones
    if exists (select 1 from erp.provision_movements where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a provision: undo it from Year-end adjustments';
    end if;
    -- v0.37.0: inventario del cierre
    if exists (select 1 from erp.inventory_counts where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to an inventory count: undo it from Year-end adjustments';
    end if;
    -- v0.41.0: Impuesto sobre Sociedades
    if exists (select 1 from erp.corporate_tax_returns where new.reversal_of in (current_entry_id, deferred_entry_id)) then
      raise exception 'This entry belongs to the corporate income tax: undo it from Corporate tax';
    end if;
    -- v0.38.0: nóminas y sus pagos
    if exists (select 1 from erp.payroll_runs where new.reversal_of in (entry_id, net_payment_entry_id, ss_payment_entry_id)) then
      raise exception 'This entry belongs to a payroll: undo it from Payroll';
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION erp.entry_is_manual(p_entry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select e.entry_type = 'normal' and e.reversal_of is null and e.reversed_by is null and e.import_batch_id is null
     and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
     and not exists (select 1 from erp.tax_settlements s where s.entry_id = e.id)
     and not exists (select 1 from erp.pro_rata p where p.entry_id = e.id)
     and not exists (select 1 from erp.year_closings c where e.id in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id))
     and not exists (select 1 from erp.payments py where py.entry_id = e.id and not py.linked)
     and not exists (select 1 from erp.asset_depreciations d where d.entry_id = e.id)
     and not exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = e.id)
     and not exists (select 1 from erp.asset_events ae where ae.entry_id = e.id)   -- v0.37.0
     -- v0.36.0: periodificaciones y deterioros
     and not exists (select 1 from erp.accruals ac where e.id in (ac.entry_id, ac.reversal_entry_id))
     and not exists (select 1 from erp.receivable_impairments ri where e.id in (ri.entry_id, ri.end_entry_id))
     -- v0.37.0: provisiones
     and not exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
     and not exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id)   -- v0.37.0: inventario
     and not exists (select 1 from erp.payroll_runs pr where e.id in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id))   -- v0.38.0
     and not exists (select 1 from erp.corporate_tax_returns ct where e.id in (ct.current_entry_id, ct.deferred_entry_id))   -- v0.41.0
  from erp.journal_entries e where e.id = p_entry;
$function$
;

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
       e.id             as entry_id,
       ro.entry_no      as reversal_of_no,
       rb.entry_no      as reversed_by_no,
       case when exists (select 1 from erp.invoices i where i.entry_id = e.id) then 'invoice'
            when exists (select 1 from erp.tax_settlements s where s.entry_id = e.id or s.entry_id = e.reversal_of) then 'settlement'
            when exists (select 1 from erp.year_closings c
                         where coalesce(e.reversal_of, e.id) in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id)) then 'closing'
            -- v0.36.0: periodificaciones y deterioros (la insolvencia firme también es un «cobro»: va antes)
            when exists (select 1 from erp.accruals ac where coalesce(e.reversal_of, e.id) in (ac.entry_id, ac.reversal_entry_id)) then 'accrual'
            when exists (select 1 from erp.receivable_impairments ri where coalesce(e.reversal_of, e.id) in (ri.entry_id, ri.end_entry_id))
              or exists (select 1 from erp.receivable_writeoffs w where w.entry_id = coalesce(e.reversal_of, e.id)) then 'impairment'
            -- v0.37.0: provisiones
            when exists (select 1 from erp.provision_movements pm where pm.entry_id = coalesce(e.reversal_of, e.id)) then 'provision'
            when exists (select 1 from erp.inventory_counts ic where ic.entry_id = coalesce(e.reversal_of, e.id)) then 'inventory'
            -- v0.41.0: Impuesto sobre Sociedades
            when exists (select 1 from erp.corporate_tax_returns ct
                         where coalesce(e.reversal_of, e.id) in (ct.current_entry_id, ct.deferred_entry_id)) then 'corporate_tax'
            -- v0.38.0: nóminas y sus pagos
            when exists (select 1 from erp.payroll_runs pr
                         where coalesce(e.reversal_of, e.id) in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id)) then 'payroll'
            when exists (select 1 from erp.payments py where not py.linked and (py.entry_id = e.id or py.cancel_entry_id = e.id)) then 'payment'
            when exists (select 1 from erp.asset_depreciations d where d.entry_id = coalesce(e.reversal_of, e.id))
              or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = coalesce(e.reversal_of, e.id))
              or exists (select 1 from erp.asset_events ae where ae.entry_id = coalesce(e.reversal_of, e.id)) then 'asset'
            when e.reversal_of is not null then 'reversal'
            else 'manual' end as source,
       e.reversal_reason
from erp.journal_entries e
join erp.fiscal_years  fy on fy.id = e.fiscal_year_id
join erp.journal_lines l  on l.entry_id = e.id
join erp.gl_accounts   a  on a.id = l.gl_account_id
left join erp.journal_entries ro on ro.id = e.reversal_of
left join erp.journal_entries rb on rb.id = e.reversed_by
where e.status = 'posted';

CREATE OR REPLACE FUNCTION erp.audit_lines(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(entry_id uuid, entry_no integer, posting_date date, k uuid, source text, account_no text, account_name text, debit numeric, credit numeric, tax_code text)
 LANGUAGE sql
 STABLE
AS $function$
  select e.id, e.entry_no, e.posting_date, coalesce(e.reversal_of, e.id),
         case when exists (select 1 from erp.invoices i where i.entry_id = coalesce(e.reversal_of, e.id)) then 'invoice'
              when exists (select 1 from erp.tax_settlements s where s.entry_id = coalesce(e.reversal_of, e.id)) then 'settlement'
              when exists (select 1 from erp.pro_rata p where p.entry_id = coalesce(e.reversal_of, e.id)) then 'pro_rata'
              -- v0.36.0: periodificaciones y deterioros (antes que los cobros: la insolvencia firme también lo es)
              when exists (select 1 from erp.accruals ac where coalesce(e.reversal_of, e.id) in (ac.entry_id, ac.reversal_entry_id)) then 'accrual'
              when exists (select 1 from erp.receivable_impairments ri where coalesce(e.reversal_of, e.id) in (ri.entry_id, ri.end_entry_id))
                or exists (select 1 from erp.receivable_writeoffs w where w.entry_id = coalesce(e.reversal_of, e.id)) then 'impairment'
              -- v0.37.0: provisiones
              when exists (select 1 from erp.provision_movements pm where pm.entry_id = coalesce(e.reversal_of, e.id)) then 'provision'
              when exists (select 1 from erp.inventory_counts ic where ic.entry_id = coalesce(e.reversal_of, e.id)) then 'inventory'
              -- v0.41.0: Impuesto sobre Sociedades
              when exists (select 1 from erp.corporate_tax_returns ct
                           where coalesce(e.reversal_of, e.id) in (ct.current_entry_id, ct.deferred_entry_id)) then 'corporate_tax'
              -- v0.38.0: nóminas y sus pagos
              when exists (select 1 from erp.payroll_runs pr
                           where coalesce(e.reversal_of, e.id) in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id)) then 'payroll'
              when exists (select 1 from erp.payments py where not py.linked
                           and coalesce(e.reversal_of, e.id) in (py.entry_id, py.cancel_entry_id)) then 'payment'
              when exists (select 1 from erp.asset_depreciations d where d.entry_id = coalesce(e.reversal_of, e.id))
                or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = coalesce(e.reversal_of, e.id))
                or exists (select 1 from erp.asset_events ae where ae.entry_id = coalesce(e.reversal_of, e.id)) then 'asset'
              when o.import_batch_id is not null then 'import'
              else 'manual' end,
         g.account_no, g.name, l.debit, l.credit, l.tax_code
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id
  join erp.journal_entries o on o.id = coalesce(e.reversal_of, e.id)
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
    and (p_to_date is null or e.posting_date <= p_to_date);
$function$
;

CREATE OR REPLACE FUNCTION erp.delete_company_step(p_company uuid, p_batch integer DEFAULT 5000)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_ids  uuid[];
  v_left int;
begin
  if not exists (select 1 from erp.company_users
                 where company_id = p_company and user_id = auth.uid() and role = 'admin') then
    raise exception 'Only the company admin can delete it';
  end if;
  perform set_config('erp.deleting_company', 'on', true);   -- solo dura esta transacción

  -- Documentos que apuntan a asientos (en la primera tanda; en las siguientes ya no hay nada)
  delete from erp.corporate_tax_returns  where company_id = p_company;   -- v0.41.0 (sus ajustes, en cascada)
  delete from erp.payroll_runs           where company_id = p_company;   -- v0.38.0 (las nóminas de cada empleado, en cascada)
  delete from erp.employees              where company_id = p_company;   -- v0.38.0
  delete from erp.inventory_counts       where company_id = p_company;   -- v0.37.0 (sus líneas, en cascada)
  delete from erp.provision_movements    where company_id = p_company;   -- v0.37.0
  delete from erp.provisions             where company_id = p_company;   -- v0.37.0
  delete from erp.receivable_writeoffs   where company_id = p_company;   -- v0.36.0 (antes que los pagos)
  delete from erp.receivable_impairments where company_id = p_company;   -- v0.36.0
  delete from erp.accruals               where company_id = p_company;   -- v0.36.0
  delete from erp.asset_depreciations where company_id = p_company;
  delete from erp.fixed_assets    where company_id = p_company;
  delete from erp.payments        where company_id = p_company;   -- sus aplicaciones, en cascada
  delete from erp.year_closings   where company_id = p_company;
  delete from erp.pro_rata        where company_id = p_company;
  delete from erp.tax_settlements where company_id = p_company;
  delete from erp.invoices        where company_id = p_company;   -- sus líneas, en cascada

  -- Tanda de asientos (los más recientes primero) + su pareja de anulación
  with b as (
    select id, reversal_of, reversed_by from erp.journal_entries
    where company_id = p_company
    order by posting_date desc, entry_no desc nulls first
    limit greatest(p_batch, 1)
  )
  select array_agg(distinct x) into v_ids
  from (select id from b
        union all select reversal_of from b where reversal_of is not null
        union all select reversed_by from b where reversed_by is not null) s(x);

  if v_ids is not null then
    delete from erp.journal_lines   where entry_id = any (v_ids);
    delete from erp.journal_entries where id = any (v_ids);
  end if;

  select count(*)::int into v_left from erp.journal_entries where company_id = p_company;
  if v_left = 0 then
    delete from erp.import_lines where company_id = p_company;
    delete from erp.companies    where id = p_company;
  end if;

  perform set_config('erp.deleting_company', 'off', true);
  return v_left;
end $function$
;
