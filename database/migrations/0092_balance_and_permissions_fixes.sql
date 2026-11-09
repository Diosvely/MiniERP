-- =====================================================================
-- 0092 · v0.60.3 · Correcciones: correctoras del activo en el Balance y escrituras directas por la API
-- ---------------------------------------------------------------------
-- Hallazgos de los chats del proyecto, aprobados por Diosvely (09-11-2026):
--   AF-05 (auditoría fiscal) · cinco cuentas correctoras del activo con saldo acreedor (437, 5393, 5394, 5395 y 549)
--         salían en el pasivo. El BOE las pone entre paréntesis en su partida del activo: restan ahí, con cualquier
--         saldo, igual que la (406) resta en Proveedores. RD 1514/2007 y RD 1515/2007, tercera parte, modelos de
--         balance (columna «Núm. cuentas»). Se corrige en los tres modelos a la vez (PYMES, abreviado y normal).
--         El modelo abreviado queda validado frente al BOE (AF-04, ADR 0062).
--   SEG-09 (seguridad) · los accesos a una empresa solo se cambian con las funciones del propietario de la aplicación
--         (erp.grant_company_access / erp.revoke_company_access). Se quita la escritura directa en erp.company_users.
--   SEG-10 · con una escritura directa no se puede cambiar quién creó la empresa (el límite de empresas lo cuenta), ni
--         la semilla de una sintética, ni publicar como demo una sintética.
--   SEG-11 · un apunte solo puede llevar un tercero de su misma empresa.
-- La prueba guardiana (fase 80) exige además RLS en todas las tablas y prueba las escrituras directas (SEG-12).
-- =====================================================================

-- ---------- AF-05 · Correctoras del activo: restan en su partida del activo con cualquier saldo ----------
-- Normal: Clientes (437), Inversiones en empresas del grupo a corto · Instrumentos de patrimonio (5393, 5394) e
-- Inversiones financieras a corto · Instrumentos de patrimonio (5395, 549)
insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line) values
  ('normal', '437',  'AC.III.1', 'AC.III.1'),
  ('normal', '5393', 'AC.IV.1',  'AC.IV.1'),
  ('normal', '5394', 'AC.IV.1',  'AC.IV.1'),
  ('normal', '5395', 'AC.V.1',   'AC.V.1'),
  ('normal', '549',  'AC.V.1',   'AC.V.1')
on conflict (model, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- Abreviado: derivado del normal, como en la 0089 (así no puede contradecirlo)
insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line)
select 'abreviado', prefix, erp.fs_abridged_line(debit_line), erp.fs_abridged_line(credit_line)
from erp.fs_model_mapping where model = 'normal' and prefix in ('437', '5393', '5394', '5395', '549')
on conflict (model, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- PYMES (RD 1515/2007): 1. Clientes (437), III. Inversiones en empresas del grupo a corto (5393, 5394) y
-- IV. Inversiones financieras a corto (5395, 549)
insert into erp.fs_mapping (statement, prefix, debit_line, credit_line) values
  ('balance', '437',  'AC.II.1', 'AC.II.1'),
  ('balance', '5393', 'AC.III',  'AC.III'),
  ('balance', '5394', 'AC.III',  'AC.III'),
  ('balance', '5395', 'AC.IV',   'AC.IV'),
  ('balance', '549',  'AC.IV',   'AC.IV')
on conflict (statement, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- ---------- SEG-09 · Los accesos, solo con las funciones (security definer) ----------
-- Quedan: grant_company_access, revoke_company_access, el alta del administrador (tg_company_add_admin) y las limpiezas
-- de invitados, que son security definer y no dependen de estos permisos. La lectura (política «read») no cambia.
drop policy if exists manage on erp.company_users;
revoke insert, update, delete on erp.company_users from authenticated;

-- ---------- SEG-10 · Columnas protegidas de la empresa ----------
create or replace function erp.tg_company_rules()
returns trigger language plpgsql security definer set search_path = erp, public set jit = off as $$
declare
  v_max     int;
  v_created int;
  v_cap     jsonb;
  v_s       erp.temp_settings;
begin
  if auth.uid() is null then
    return new;
  end if;

  if erp.is_anonymous() then
    raise exception 'Guest visitors can only view the demo companies: sign up to create your own';
  end if;

  -- v0.49.0 · Empresas temporales: las fechas las pone la base de datos y nadie la convierte en permanente
  if tg_op = 'UPDATE' then
    if new.temporary is distinct from old.temporary or new.expires_at is distinct from old.expires_at then
      raise exception 'A temporary company cannot be made permanent or extended';
    end if;
    -- v0.60.3 (SEG-10) · quién la creó cuenta para el límite de empresas: no se cambia
    if new.created_by is distinct from old.created_by then
      raise exception 'The creator of a company cannot be changed';
    end if;
    -- v0.60.3 (SEG-10) · la semilla de una sintética es su identidad (su huella): no se cambia una vez puesta
    if old.synthetic_seed is not null and (new.synthetic_seed is distinct from old.synthetic_seed
        or new.synthetic_profile is distinct from old.synthetic_profile
        or new.synthetic_months is distinct from old.synthetic_months) then
      raise exception 'The seed of a synthetic company cannot be changed';
    end if;
  elsif new.temporary then
    select * into v_s from erp.temp_settings;
    if exists (select 1 from erp.companies where created_by = auth.uid() and temporary
               and not erp.temp_expired(expires_at, last_seen_at)) then
      raise exception 'You already have a temporary company: delete it or wait until it expires';
    end if;
    v_cap := erp.temp_capacity();
    if (v_cap->>'full')::boolean then
      raise exception 'Temporary companies are full right now: try again later';
    end if;
    new.expires_at := now() + make_interval(hours => v_s.max_hours);
    new.last_seen_at := now();
    new.is_demo := false;
  else
    new.expires_at := null;
    new.last_seen_at := null;
  end if;

  -- Límite de empresas (las temporales no cuentan)
  if tg_op = 'INSERT' and not new.temporary then
    select max_companies into v_max from erp.my_profile();
    select companies_created into v_created from erp.my_profile();
    if v_max is not null and v_created >= v_max then
      raise exception 'Company limit reached: your account can create % compan%', v_max,
        case when v_max = 1 then 'y' else 'ies' end;
    end if;
  end if;

  if (tg_op = 'INSERT' and new.is_demo)
     or (tg_op = 'UPDATE' and new.is_demo is distinct from old.is_demo) then
    -- el propietario de la aplicación, o el titular de los datos de ESTA empresa (0027); nunca una temporal
    if new.temporary or not (erp.is_owner() or (tg_op = 'UPDATE' and erp.is_data_owner(new.id))) then
      raise exception 'Only the application owner or the data owner can publish a company as demo';
    end if;
    -- v0.60.3 (SEG-10) · una sintética nunca es demo (la misma regla que erp.set_company_demo, 0086)
    if new.is_demo and new.synthetic_seed is not null then
      raise exception 'A synthetic company cannot be published as demo';
    end if;
  end if;

  return new;
end $$;

-- ---------- SEG-11 · El tercero de un apunte, de la misma empresa ----------
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
