-- =====================================================================
-- erp.tg_entry_validate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0004_journal_entries   →   la vigente es la de 0004_journal_entries
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_fy erp.fiscal_years;
begin
  if tg_op = 'UPDATE' and old.status = 'posted' then
    -- Único cambio permitido sobre un asiento contabilizado: marcarlo como anulado.
    if (to_jsonb(new) - 'reversed_by') <> (to_jsonb(old) - 'reversed_by')
       or old.reversed_by is not null then
      raise exception 'Entry % is posted and cannot be changed. Reverse it instead.', old.entry_no;
    end if;
    return new;
  end if;

  select * into v_fy from erp.fiscal_years where id = new.fiscal_year_id;
  if v_fy.company_id <> new.company_id then
    raise exception 'The fiscal year does not belong to the company of the entry';
  end if;
  if new.posting_date not between v_fy.starting_date and v_fy.ending_date then
    raise exception 'Posting date % is outside fiscal year %', new.posting_date, v_fy.year;
  end if;
  return new;
end $function$
;
