-- =====================================================================
-- 0094 · v0.60.5 · Nadie toca los asientos por la puerta de atrás
-- ---------------------------------------------------------------------
-- Hallazgos del chat de seguridad, aprobados por Diosvely (14-11-2026). La web nunca hace nada de esto: son escrituras
-- directas por la API (PATCH / POST a /rest/v1/...) de quien ya puede escribir en su propia empresa.
--   SEG-13 · una línea no se puede mover de un asiento a otro (antes, mover la línea de un asiento contabilizado a un
--            borrador dejaba el contabilizado con una línea y descuadrado). Se bloquea siempre, también entre borradores.
--   SEG-14 · un asiento solo pasa a contabilizado si cumple lo mismo que exige erp.post_entry: al menos dos líneas,
--            Debe = Haber, ejercicio y período abiertos y el número siguiente del ejercicio. Antes, un UPDATE directo
--            contabilizaba un asiento descuadrado, en un mes cerrado y con el número que se quisiera.
--   SEG-18 · la subcuenta de un tercero tiene que ser de su misma empresa, de detalle y de la cuenta colectiva de su
--            tipo (430 clientes, 400 proveedores, 410 acreedores, 440 deudores).
--   SEG-19 · las opiniones sobre la IA tienen tope de tamaño: lo que escribe el usuario (la pregunta y el comentario),
--            1.000 caracteres, para todos; la respuesta guardada, 32 KB; el modelo, 100 caracteres.
-- Pruebas de regresión: fase 80 (guardiana de permisos).
-- =====================================================================

-- ---------- SEG-13 · Una línea no cambia de asiento ----------
-- Copia de la versión de la 0092 con un punto nuevo (0) antes de mirar el asiento.
create or replace function erp.tg_line_validate()
returns trigger language plpgsql set jit = off as $$
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

  -- 0) v0.60.5 (SEG-13) · una línea no se mueve de un asiento a otro: se borra y se crea de nuevo
  if tg_op = 'UPDATE' and new.entry_id is distinct from old.entry_id then
    raise exception 'A line cannot be moved to another entry: delete it and add it again';
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

  -- 4) v0.60.3 (SEG-11) · el tercero, también de la misma empresa
  if new.partner_id is not null and not exists (select 1 from erp.business_partners b
                                                where b.id = new.partner_id and b.company_id = new.company_id) then
    raise exception 'The partner does not belong to this company';
  end if;

  -- 5) Número de línea automático si no se indica
  if new.line_no is null then
    select coalesce(max(line_no), 0) + 1 into new.line_no from erp.journal_lines where entry_id = new.entry_id;
  end if;
  return new;
end $$;

-- ---------- SEG-14 · Solo se contabiliza lo que erp.post_entry aceptaría ----------
-- Copia de la versión de la 0004 con el bloque nuevo «De borrador a contabilizado». El motor de importación
-- (erp.import_engine, que no se puede poner desde la API) ya valida por su cuenta y sigue igual.
create or replace function erp.tg_entry_validate()
returns trigger language plpgsql set jit = off as $$
declare
  v_fy      erp.fiscal_years;
  v_period  erp.accounting_periods;
  v_debit   numeric(15,2);
  v_credit  numeric(15,2);
  v_lines   int;
  v_next    int;
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

  -- v0.60.5 (SEG-14) · De borrador a contabilizado: las mismas condiciones que erp.post_entry
  if new.status = 'posted'
     and (tg_op = 'INSERT' or old.status = 'draft')
     and coalesce(current_setting('erp.import_engine', true), '') <> 'on'
     and coalesce(current_setting('erp.deleting_company', true), '') <> 'on' then
    if tg_op = 'INSERT' then
      -- Un asiento nuevo no tiene líneas todavía: nace en borrador y se contabiliza después
      raise exception 'A new entry starts as a draft: post it with erp.post_entry';
    end if;
    select coalesce(sum(debit), 0), coalesce(sum(credit), 0), count(*)
    into v_debit, v_credit, v_lines
    from erp.journal_lines where entry_id = new.id;
    if v_lines < 2 then
      raise exception 'An entry needs at least 2 lines (it has %)', v_lines;
    end if;
    if v_debit <> v_credit then
      raise exception 'Unbalanced entry: debit % ≠ credit % (difference %)', v_debit, v_credit, v_debit - v_credit;
    end if;
    if v_fy.status <> 'open' then
      raise exception 'Fiscal year % is closed', v_fy.year;
    end if;
    select * into v_period from erp.accounting_periods
    where fiscal_year_id = new.fiscal_year_id and new.posting_date between starting_date and ending_date;
    if v_period.status <> 'open' then
      raise exception 'Period % of % is closed', v_period.period_no, v_fy.year;
    end if;
    select coalesce(max(entry_no), 0) + 1 into v_next
    from erp.journal_entries where fiscal_year_id = new.fiscal_year_id and id <> new.id;
    if new.entry_no is distinct from v_next then
      raise exception 'The entry number must be the next one in the fiscal year (%): post it with erp.post_entry', v_next;
    end if;
  end if;
  return new;
end $$;

-- ---------- SEG-18 · La subcuenta de un tercero: de su empresa, de detalle y de su tipo ----------
-- No es security definer: lee erp.gl_accounts con la sesión del usuario. Si la subcuenta es de una empresa privada
-- de otro, no la encuentra y también da error.
create or replace function erp.tg_partner_account()
returns trigger language plpgsql set jit = off as $$
declare
  v_account erp.gl_accounts;
  v_prefix  text;
begin
  if new.gl_account_id is null
     or coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return new;
  end if;
  select * into v_account from erp.gl_accounts where id = new.gl_account_id;
  if not found or v_account.company_id <> new.company_id then
    raise exception 'The account does not belong to this company';
  end if;
  v_prefix := erp.partner_control_account(new.partner_type);
  if v_account.account_type <> 'posting' or v_account.account_no not like v_prefix || '%' then
    raise exception 'The account % does not match the partner type (it must be a %… posting account)',
      v_account.account_no, v_prefix;
  end if;
  return new;
end $$;

drop trigger if exists partner_account on erp.business_partners;
create trigger partner_account
  before insert or update of gl_account_id, partner_type, company_id on erp.business_partners
  for each row execute function erp.tg_partner_account();
-- Una función de disparador no se llama desde la API (la guardiana de la fase 80 lo comprueba)
revoke execute on function erp.tg_partner_account() from anon, public, authenticated;

-- ---------- SEG-19 · Tope de tamaño en las opiniones sobre la IA ----------
-- «not valid»: no revisa las filas antiguas (no se rompe la migración si alguna era más larga); sí las nuevas.
alter table erp.ai_feedback drop constraint if exists ai_feedback_comment_check;
alter table erp.ai_feedback drop constraint if exists ai_feedback_sizes;
alter table erp.ai_feedback add constraint ai_feedback_sizes check (
  length(coalesce(prompt, '')) <= 1000
  and length(coalesce(comment, '')) <= 1000
  and length(coalesce(model, '')) <= 100
  and pg_column_size(answer) <= 32768
) not valid;
