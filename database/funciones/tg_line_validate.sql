-- =====================================================================
-- erp.tg_line_validate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0004_journal_entries 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_line_validate()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  v_entry    erp.journal_entries;
  v_account  erp.gl_accounts;
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  -- Importación: el motor ya ha validado empresa, cuentas y número de línea (miles de apuntes por llamada)
  if tg_op = 'INSERT' and coalesce(current_setting('erp.import_engine', true), '') = 'on' then
    return new;
  end if;

  -- 1) El asiento debe estar en borrador (vale para INSERT, UPDATE y DELETE)
  select * into v_entry from erp.journal_entries
  where id = case when tg_op = 'DELETE' then old.entry_id else new.entry_id end;

  if v_entry.status = 'posted' then
    raise exception 'Entry % is posted: its lines cannot be changed', v_entry.entry_no;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  -- 2) La empresa del apunte es siempre la del asiento
  new.company_id := v_entry.company_id;

  -- 3) La cuenta: de la misma empresa, subcuenta y no bloqueada
  select * into v_account from erp.gl_accounts where id = new.gl_account_id;
  if v_account.company_id <> new.company_id then
    raise exception 'Account % does not belong to this company', v_account.account_no;
  end if;
  if v_account.account_type <> 'posting' then
    raise exception 'Account % (%) is a heading account: use a posting account', v_account.account_no, v_account.name;
  end if;
  if v_account.blocked then
    raise exception 'Account % is blocked', v_account.account_no;
  end if;

  -- 4) Número de línea automático si no se indica
  if new.line_no is null then
    select coalesce(max(line_no), 0) + 1 into new.line_no from erp.journal_lines where entry_id = new.entry_id;
  end if;
  return new;
end $function$
;
