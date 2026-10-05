-- =====================================================================
-- 0014 · REVERSE ENTRY · Anular asientos desde el libro diario (bloque K2)
-- ---------------------------------------------------------------------
-- Un asiento contabilizado no se edita ni se borra: se ANULA con un contraasiento (Debe ↔ Haber)
-- enlazado al original, con fecha y motivo:
--   BC  → "Reverse Transaction" desde el registro de movimientos
--   SAP → FB08 "Anular documento" (motivo de anulación + fecha de contabilización)
--   A3 / Sage → "Anular asiento": genera el contraasiento
-- Excepciones (se corrigen por su propio circuito):
--   asiento de una FACTURA       → rectificativa
--   asiento de una LIQUIDACIÓN   → "Deshacer liquidación"
-- =====================================================================

alter table erp.journal_entries add column reversal_reason text;

drop function erp.reverse_entry(uuid, date);

create or replace function erp.reverse_entry(p_entry uuid, p_posting_date date default null, p_reason text default null)
returns integer language plpgsql as $$
declare
  v_e     erp.journal_entries;
  v_date  date;
  v_fy    uuid;
  v_new   uuid;
  v_no    int;
begin
  select * into v_e from erp.journal_entries where id = p_entry;
  if not found then raise exception 'Entry not found (or no permission)'; end if;
  if not erp.can_write(v_e.company_id) then
    raise exception 'No permission to reverse entries in this company';
  end if;
  if v_e.status <> 'posted' then
    raise exception 'Only posted entries can be reversed; a draft can simply be deleted';
  end if;
  if v_e.reversed_by is not null then raise exception 'Entry % is already reversed', v_e.entry_no; end if;
  if v_e.reversal_of is not null then raise exception 'A reversal entry cannot be reversed'; end if;
  if coalesce(current_setting('erp.tax_settlement_engine', true), '') <> 'on'
     and exists (select 1 from erp.tax_settlements s where s.entry_id = p_entry) then
    raise exception 'This entry belongs to a tax settlement: use "Undo settlement" instead';
  end if;

  v_date := coalesce(p_posting_date, v_e.posting_date);
  if v_date < v_e.posting_date then
    raise exception 'The reversal date cannot be earlier than the original entry (%)', v_e.posting_date;
  end if;
  select id into v_fy from erp.fiscal_years
  where company_id = v_e.company_id and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no, entry_type,
                                   reversal_of, reversal_reason)
  values (v_e.company_id, v_fy, v_date,
          'Anulación del asiento ' || v_e.entry_no || ': ' || v_e.description
            || coalesce(' · ' || nullif(btrim(p_reason), ''), ''),
          v_e.document_no, v_e.entry_type, v_e.id, nullif(btrim(p_reason), ''))
  returning id into v_new;

  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description,
                                 partner_id, tax_code, tax_base)
  select v_new, company_id, line_no, gl_account_id, credit, debit, description,
         partner_id, tax_code, -tax_base
  from erp.journal_lines where entry_id = v_e.id;

  v_no := erp.post_entry(v_new);
  update erp.journal_entries set reversed_by = v_new where id = v_e.id;
  return v_no;
end $$;

revoke execute on function erp.reverse_entry(uuid, date, text) from anon, public;
grant execute on function erp.reverse_entry(uuid, date, text) to authenticated;

-- ---------------------------------------------------------------------
-- Libro diario con la información de anulación y el origen del asiento
-- (columnas nuevas al final: create or replace view solo permite añadir por detrás)
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
       e.id             as entry_id,
       ro.entry_no      as reversal_of_no,     -- este asiento ANULA al nº …
       rb.entry_no      as reversed_by_no,     -- este asiento está ANULADO por el nº …
       case when exists (select 1 from erp.invoices i where i.entry_id = e.id) then 'invoice'
            when exists (select 1 from erp.tax_settlements s where s.entry_id = e.id or s.entry_id = e.reversal_of) then 'settlement'
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
