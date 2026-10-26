-- =====================================================================
-- 0070 · PANTALLA «ASIENTOS»: una fila por asiento, su origen y su estado · v0.47.0 (mejora de uso 9)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (mejoras-de-uso.md, 9):
--   · erp.entry_source: de dónde viene cada asiento (factura, cobro o pago, liquidación, nómina, inmovilizado…,
--     importado, contraasiento o manual). Es la misma regla que la columna «source» del diario, en una función.
--   · erp.entries_list: una fila por asiento con su fecha, documento, concepto, totales del Debe y del Haber, origen y
--     ESTADO: contabilizado (posted), en edición (draft que se puede contabilizar: ok) o con error (draft que todavía
--     no; dice por qué). El estado del borrador se calcula de sus líneas, no se guarda.
--   · Borradores a medias: erp.save_draft guarda (o rehace) un borrador aunque tenga una sola línea o no cuadre.
--   · erp.delete_draft borra un borrador; erp.post_entries contabiliza varios de una vez (los que se pueden).
-- Re-ejecutable.
-- =====================================================================

-- 1) De dónde viene cada asiento
create or replace function erp.entry_source(e erp.journal_entries)
returns text language sql stable security definer set search_path = erp, public as $$
  select
        CASE
            WHEN e.import_batch_id IS NOT NULL THEN 'import'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.invoices i
              WHERE (i.entry_id = e.id))) THEN 'invoice'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.tax_settlements s
              WHERE ((s.entry_id = e.id) OR (s.entry_id = e.reversal_of)))) THEN 'settlement'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.year_closings c
              WHERE (((COALESCE(e.reversal_of, e.id) = c.closing_pl_entry_id) OR (COALESCE(e.reversal_of, e.id) = c.closing_entry_id)) OR (COALESCE(e.reversal_of, e.id) = c.opening_entry_id)))) THEN 'closing'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.accruals ac
              WHERE ((COALESCE(e.reversal_of, e.id) = ac.entry_id) OR (COALESCE(e.reversal_of, e.id) = ac.reversal_entry_id)))) THEN 'accrual'::text
            WHEN ((EXISTS ( SELECT 1
               FROM erp.receivable_impairments ri
              WHERE ((COALESCE(e.reversal_of, e.id) = ri.entry_id) OR (COALESCE(e.reversal_of, e.id) = ri.end_entry_id)))) OR (EXISTS ( SELECT 1
               FROM erp.receivable_writeoffs w
              WHERE (w.entry_id = COALESCE(e.reversal_of, e.id))))) THEN 'impairment'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.provision_movements pm
              WHERE (pm.entry_id = COALESCE(e.reversal_of, e.id)))) THEN 'provision'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.inventory_counts ic
              WHERE (ic.entry_id = COALESCE(e.reversal_of, e.id)))) THEN 'inventory'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.corporate_tax_returns ct
              WHERE ((COALESCE(e.reversal_of, e.id) = ct.current_entry_id) OR (COALESCE(e.reversal_of, e.id) = ct.deferred_entry_id)))) THEN 'corporate_tax'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.equity_operations eo
              WHERE (COALESCE(e.reversal_of, e.id) = ANY (eo.entry_ids)))) THEN 'equity'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.loan_events le
              WHERE (le.entry_id = COALESCE(e.reversal_of, e.id)))) THEN 'financing'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.grant_events ge
              WHERE (ge.entry_id = COALESCE(e.reversal_of, e.id)))) THEN 'grant'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.payroll_runs pr
              WHERE (((COALESCE(e.reversal_of, e.id) = pr.entry_id) OR (COALESCE(e.reversal_of, e.id) = pr.net_payment_entry_id)) OR (COALESCE(e.reversal_of, e.id) = pr.ss_payment_entry_id)))) THEN 'payroll'::text
            WHEN (EXISTS ( SELECT 1
               FROM erp.payments py
              WHERE ((NOT py.linked) AND ((py.entry_id = e.id) OR (py.cancel_entry_id = e.id))))) THEN 'payment'::text
            WHEN ((EXISTS ( SELECT 1
               FROM erp.asset_depreciations d
              WHERE (d.entry_id = COALESCE(e.reversal_of, e.id)))) OR (EXISTS ( SELECT 1
               FROM erp.fixed_assets fa
              WHERE (fa.disposal_entry_id = COALESCE(e.reversal_of, e.id)))) OR (EXISTS ( SELECT 1
               FROM erp.asset_events ae
              WHERE (ae.entry_id = COALESCE(e.reversal_of, e.id))))) THEN 'asset'::text
            WHEN (e.reversal_of IS NOT NULL) THEN 'reversal'::text
            ELSE 'manual'::text
        END;
$$;
revoke execute on function erp.entry_source(erp.journal_entries) from anon, public, authenticated;

-- 2) ¿Por qué no se puede contabilizar todavía un borrador? (null = se puede)
--    empty · one_line · unbalanced · no_year · year_closed · period_closed · before_start · after_month · controlled
create or replace function erp.draft_problem(p_entry uuid)
returns text language plpgsql stable security definer set search_path = erp, public as $$
declare e erp.journal_entries; v_co erp.companies; v_n int; v_d numeric; v_c numeric; v_fy erp.fiscal_years; v_per erp.accounting_periods; v_wp erp.accounting_periods;
begin
  select * into e from erp.journal_entries where id = p_entry;
  if e.status <> 'draft' then return null; end if;
  select * into v_co from erp.companies where id = e.company_id;
  select count(*) filter (where debit <> 0 or credit <> 0), coalesce(sum(debit), 0), coalesce(sum(credit), 0)
    into v_n, v_d, v_c from erp.journal_lines where entry_id = p_entry;
  if v_n = 0 then return 'empty'; end if;
  if v_n < 2 then return 'one_line'; end if;
  if v_d <> v_c then return 'unbalanced'; end if;
  select * into v_fy from erp.fiscal_years where id = e.fiscal_year_id;
  if v_fy.id is null then return 'no_year'; end if;
  if v_fy.status <> 'open' then return 'year_closed'; end if;
  select * into v_per from erp.accounting_periods where fiscal_year_id = v_fy.id and e.posting_date between starting_date and ending_date;
  if v_per.status <> 'open' then return 'period_closed'; end if;
  if v_co.monthly then
    if e.posting_date < v_co.start_date then return 'before_start'; end if;
    v_wp := erp.work_period(e.company_id);
    if v_wp.fiscal_year_id is not null and e.posting_date > v_wp.ending_date then return 'after_month'; end if;
  end if;
  if v_co.control_mode = 'strict' and jsonb_array_length(coalesce(erp.entry_controlled_lines(p_entry), '[]'::jsonb)) > 0 then
    return 'controlled';
  end if;
  return null;
end $$;
revoke execute on function erp.draft_problem(uuid) from anon, public, authenticated;

-- 3) La lista: una fila por asiento, de la más reciente a la más antigua
--    p_from / p_to: el filtro de fechas (null = sin límite) · p_limit / p_offset: por páginas («Todos»)
create or replace function erp.entries_list(p_company uuid, p_from date default null, p_to date default null,
                                            p_limit int default 500, p_offset int default 0)
returns table (entry_id uuid, fiscal_year int, entry_no int, posting_date date, document_no text, description text,
               entry_type text, status text, total_debit numeric, total_credit numeric, lines int, source text,
               state text, problem text, reversal_of_no int, reversed_by_no int, total_count bigint)
language plpgsql stable security definer set search_path = erp, public as $$
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  return query
  with e as (
    select j.*, count(*) over () as n
    from erp.journal_entries j
    where j.company_id = p_company
      and (p_from is null or j.posting_date >= p_from) and (p_to is null or j.posting_date <= p_to)
    order by j.posting_date desc, j.entry_no desc nulls first, j.created_at desc
    limit greatest(coalesce(p_limit, 500), 1) offset greatest(coalesce(p_offset, 0), 0))
  select e.id, fy.year::int, e.entry_no, e.posting_date, e.document_no, e.description, e.entry_type, e.status,
         coalesce(t.d, 0), coalesce(t.c, 0), coalesce(t.n, 0)::int, (select erp.entry_source(j2) from erp.journal_entries j2 where j2.id = e.id),
         case when e.status = 'posted' then 'posted' when p.problem is null then 'ok' else 'error' end, p.problem,
         ro.entry_no, rb.entry_no, e.n
  from e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id
  left join lateral (select sum(l.debit) d, sum(l.credit) c, count(*) n from erp.journal_lines l where l.entry_id = e.id) t on true
  left join lateral (select case when e.status = 'draft' then erp.draft_problem(e.id) end as problem) p on true
  left join erp.journal_entries ro on ro.id = e.reversal_of
  left join erp.journal_entries rb on rb.id = e.reversed_by
  order by e.posting_date desc, e.entry_no desc nulls first, e.created_at desc;
end $$;

-- 4) Guardar un borrador, aunque esté a medias (una línea, sin cuadrar): nuevo o rehecho
--    p = { company_id, entry_id? (para seguir uno), posting_date, description, document_no?,
--          lines: [{ gl_account_id, debit, credit, description? }] }
create or replace function erp.save_draft(p jsonb)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v_company uuid := (p->>'company_id')::uuid; v_id uuid := (p->>'entry_id')::uuid; v_date date := (p->>'posting_date')::date;
        v_fy uuid; e erp.journal_entries;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to save entries in this company'; end if;
  if v_date is null then raise exception 'The posting date is required'; end if;
  select id into v_fy from erp.fiscal_years where company_id = v_company and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;
  if v_id is not null then
    select * into e from erp.journal_entries where id = v_id and company_id = v_company;
    if not found then raise exception 'Entry not found'; end if;
    if e.status <> 'draft' then raise exception 'Entry % is posted and cannot be changed', e.entry_no; end if;
    delete from erp.journal_lines where entry_id = v_id;
    update erp.journal_entries set fiscal_year_id = v_fy, posting_date = v_date, description = coalesce(nullif(btrim(p->>'description'), ''), 'Borrador'),
      document_no = nullif(btrim(p->>'document_no'), '') where id = v_id;
  else
    insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
    values (v_company, v_fy, v_date, coalesce(nullif(btrim(p->>'description'), ''), 'Borrador'), nullif(btrim(p->>'document_no'), ''))
    returning id into v_id;
  end if;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
  select v_id, v_company, x.ord, (x.l->>'gl_account_id')::uuid, round(coalesce((x.l->>'debit')::numeric, 0), 2),
         round(coalesce((x.l->>'credit')::numeric, 0), 2), nullif(btrim(x.l->>'description'), '')
  from jsonb_array_elements(coalesce(p->'lines', '[]'::jsonb)) with ordinality as x(l, ord)
  where (x.l->>'gl_account_id') is not null and (coalesce((x.l->>'debit')::numeric, 0) <> 0 or coalesce((x.l->>'credit')::numeric, 0) <> 0);
  return v_id;
end $$;

-- 5) Borrar un borrador
create or replace function erp.delete_draft(p_entry uuid)
returns void language plpgsql security definer set search_path = erp, public as $$
declare e erp.journal_entries;
begin
  select * into e from erp.journal_entries where id = p_entry;
  if not found or not erp.can_write(e.company_id) then raise exception 'No permission to delete entries in this company'; end if;
  if e.status <> 'draft' then raise exception 'Entry % is posted and cannot be deleted. Reverse it instead.', e.entry_no; end if;
  delete from erp.journal_lines where entry_id = p_entry;
  delete from erp.journal_entries where id = p_entry;
end $$;

-- 6) Contabilizar varios borradores de una vez, por fecha; los que no se pueden, se quedan y se dice por qué
create or replace function erp.post_entries(p_company uuid, p_entries uuid[])
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare r record; v_no int; v_ok jsonb := '[]'::jsonb; v_ko jsonb := '[]'::jsonb;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post entries in this company'; end if;
  for r in select j.id, j.posting_date from erp.journal_entries j
           where j.company_id = p_company and j.id = any (p_entries) and j.status = 'draft'
           order by j.posting_date, j.created_at loop
    -- lo que se sabe antes (también la cuenta controlada, que el motor comprueba al final de la transacción)
    if erp.draft_problem(r.id) is not null then
      v_ko := v_ko || jsonb_build_object('entry_id', r.id, 'problem', erp.draft_problem(r.id));
      continue;
    end if;
    begin
      v_no := erp.post_entry(r.id);
      v_ok := v_ok || jsonb_build_object('entry_id', r.id, 'entry_no', v_no);
    exception when others then
      v_ko := v_ko || jsonb_build_object('entry_id', r.id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('posted', v_ok, 'failed', v_ko);
end $$;

revoke execute on function erp.entries_list(uuid, date, date, int, int), erp.save_draft(jsonb), erp.delete_draft(uuid),
  erp.post_entries(uuid, uuid[]) from anon, public;
grant execute on function erp.entries_list(uuid, date, date, int, int), erp.save_draft(jsonb), erp.delete_draft(uuid),
  erp.post_entries(uuid, uuid[]) to authenticated;
