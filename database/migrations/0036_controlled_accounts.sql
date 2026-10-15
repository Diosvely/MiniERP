-- =====================================================================
-- 0036 · CUENTAS CONTROLADAS: modo estricto (SAP / BC) o guiado (ERP españoles) · v0.33.0
-- ---------------------------------------------------------------------
-- En SAP la cuenta de proveedores es una "cuenta asociada" y en Business Central una cuenta sin "registro directo":
-- solo la mueve su módulo (facturas, pagos, liquidación…). En el ERP cubano Versat eran las "cuentas controladas".
-- Los ERP españoles (A3, Sage, ContaPlus) dejan tocarlas a mano y controlan después (cuadres, punteo).
-- Aquí se pueden las dos cosas, con un interruptor por empresa (companies.control_mode):
--   strict  → un ASIENTO MANUAL que mueve una cuenta controlada NO se contabiliza: "regístralo desde Pagos"
--   guided  → se contabiliza, pero la web avisa antes y la pantalla Comprobaciones (0037) lo lista
-- Por defecto en la base de datos: guided (no cambia nada en las empresas que ya existen ni en las importadas);
-- la web crea las empresas nuevas en strict.
--
-- Qué cuenta controla cada módulo, como DATOS (erp.control_rules, por prefijo de cuenta: gana el más largo):
--   400 / 410 / 430 / 440  los dos lados  → Facturas (el cargo o abono de la factura) y Cobros y pagos
--   4009 / 4309            libres (facturas pendientes de recibir / de formalizar: se usan a mano en el cierre)
--   472 / 477              los dos lados  → Facturas y Liquidación
--   4750                   Haber          → Liquidación (el pago a Hacienda, al Debe, sigue siendo manual)
--   4700                   Debe           → Liquidación (el cobro de la devolución, al Haber, sigue siendo manual)
--   No se controlan (todavía): 4751 y 473 (nóminas, pagos fraccionados), 572 (no hay módulo de bancos), 21x (llega
--   con el Inmovilizado), 129 (distribución del resultado, a mano).
-- Nunca se bloquean: apertura, regularización y cierre, contraasientos, asientos importados y los que generan los
-- propios módulos (facturas, pagos, liquidación, prorrata, cierre).
--
-- Cómo se comprueba: un trigger de restricción DIFERIDO (al final de la transacción) sobre los asientos que pasan a
-- contabilizados. Diferido porque los módulos crean primero el asiento y después su documento (la factura, el pago):
-- al final de la transacción ya se sabe si el asiento es manual o de un documento.
-- Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Reglas: qué módulo mueve cada cuenta y por qué lado
-- ---------------------------------------------------------------------
create table if not exists erp.control_rules (
  account_prefix  text primary key,
  modules         text[] not null,          -- vacío = cuenta libre (excepción dentro de un prefijo controlado)
  side            text not null check (side in ('debit', 'credit', 'both')),
  note            text not null,
  note_en         text not null
);
comment on table erp.control_rules is
  'Controlled accounts: which module posts each account (SAP reconciliation accounts, BC accounts without direct posting).';

insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('400',  '{invoices,payments}', 'both', 'Proveedores: la factura recibida los abona y el pago los carga.', 'Suppliers: the received invoice credits them and the payment debits them.'),
('4009', '{}',                  'both', 'Facturas pendientes de recibir: ajuste manual de cierre.', 'Invoices pending receipt: manual closing adjustment.'),
('410',  '{invoices,payments}', 'both', 'Acreedores: la factura recibida los abona y el pago los carga.', 'Creditors: the received invoice credits them and the payment debits them.'),
('430',  '{invoices,payments}', 'both', 'Clientes: la factura emitida los carga y el cobro los abona.', 'Customers: the issued invoice debits them and the collection credits them.'),
('4309', '{}',                  'both', 'Facturas pendientes de formalizar: ajuste manual de cierre.', 'Invoices pending issue: manual closing adjustment.'),
('440',  '{invoices,payments}', 'both', 'Deudores: la factura emitida los carga y el cobro los abona.', 'Debtors: the issued invoice debits them and the collection credits them.'),
('472',  '{invoices,settlement}', 'both', 'IVA / IGIC soportado: lo carga la factura y lo cancela la liquidación.', 'Input VAT / IGIC: posted by the invoice and cleared by the settlement.'),
('477',  '{invoices,settlement}', 'both', 'IVA / IGIC repercutido: lo abona la factura y lo cancela la liquidación.', 'Output VAT / IGIC: posted by the invoice and cleared by the settlement.'),
('4750', '{settlement}',        'credit', 'Hacienda acreedora por IVA / IGIC: la abona la liquidación (el pago, al Debe, es manual).', 'VAT / IGIC payable: credited by the settlement (the payment, debit, is manual).'),
('4700', '{settlement}',        'debit',  'Hacienda deudora por IVA / IGIC: la carga la liquidación (el cobro, al Haber, es manual).', 'VAT / IGIC receivable: debited by the settlement (the refund, credit, is manual).')
on conflict (account_prefix) do update set
  modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

alter table erp.control_rules enable row level security;
drop policy if exists read on erp.control_rules;
create policy read on erp.control_rules for select to authenticated using (true);
revoke all on erp.control_rules from anon, public;
grant select on erp.control_rules to authenticated;

-- Regla de una subcuenta: la del prefijo más largo (4009 gana a 400)
create or replace function erp.control_rule_for(p_account_no text)
returns erp.control_rules language sql stable as $$
  select r.* from erp.control_rules r
  where p_account_no like r.account_prefix || '%'
  order by length(r.account_prefix) desc limit 1;
$$;

-- ---------------------------------------------------------------------
-- 2) Modo de control de la empresa
-- ---------------------------------------------------------------------
alter table erp.companies
  add column if not exists control_mode text not null default 'guided' check (control_mode in ('strict', 'guided'));
comment on column erp.companies.control_mode is
  'strict: manual entries cannot post to controlled accounts (SAP / BC) · guided: allowed with warnings (Spanish ERPs).';

create or replace function erp.set_control_mode(p_company uuid, p_mode text)
returns void language plpgsql security definer set search_path = erp, public as $$
begin
  if not erp.is_admin(p_company) then raise exception 'Only the company admin can change the control mode'; end if;
  if p_mode not in ('strict', 'guided') then raise exception 'Invalid control mode: %', p_mode; end if;
  update erp.companies set control_mode = p_mode where id = p_company;
end $$;

create or replace view erp.v_my_companies with (security_invoker = true) as
select c.id, c.name, c.vat_registration_no, c.industry, c.tax_territory,
       c.posting_account_digits, c.is_demo, c.created_at,
       erp.my_role(c.id) as my_role,
       c.vat_regime,
       c.data_credit,
       erp.is_data_owner(c.id) as is_data_owner,
       c.control_mode
from erp.companies c;

-- ---------------------------------------------------------------------
-- 3) ¿Es un asiento manual? (ni de un documento, ni importado, ni de apertura / cierre, ni un contraasiento)
-- ---------------------------------------------------------------------
create or replace function erp.entry_is_manual(p_entry uuid)
returns boolean language sql stable security definer set search_path = erp, public as $$
  -- (un asiento ya anulado tampoco cuenta: su efecto es cero; pasa al deshacer una liquidación o una prorrata)
  select e.entry_type = 'normal' and e.reversal_of is null and e.reversed_by is null and e.import_batch_id is null
     and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
     and not exists (select 1 from erp.tax_settlements s where s.entry_id = e.id)
     and not exists (select 1 from erp.pro_rata p where p.entry_id = e.id)
     and not exists (select 1 from erp.year_closings c where e.id in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id))
     and not exists (select 1 from erp.payments py where py.entry_id = e.id and not py.linked)
  from erp.journal_entries e where e.id = p_entry;
$$;

-- Apuntes de unas líneas (propuestas o de un asiento) que tocan una cuenta controlada por su lado controlado
--   p_lines: [{ "account_no": "41000001", "debit": 100, "credit": 0 }, …]  →  [{ line, account_no, modules, side }]
create or replace function erp.controlled_lines(p_lines jsonb)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('line', x.ord, 'account_no', x.v->>'account_no',
                                               'modules', to_jsonb(r.modules), 'side', r.side) order by x.ord), '[]')
  from jsonb_array_elements(p_lines) with ordinality x(v, ord)
  cross join lateral erp.control_rule_for(x.v->>'account_no') r
  where r.account_prefix is not null and cardinality(r.modules) > 0
    and (r.side = 'both'
         or (r.side = 'debit'  and coalesce((x.v->>'debit')::numeric, 0) > 0)
         or (r.side = 'credit' and coalesce((x.v->>'credit')::numeric, 0) > 0));
$$;

-- Las de un asiento ya grabado
-- (security invoker: la RLS decide qué asientos se ven; el trigger, que es security definer, ve todos)
create or replace function erp.entry_controlled_lines(p_entry uuid)
returns jsonb language sql stable as $$
  select erp.controlled_lines(coalesce(jsonb_agg(jsonb_build_object('account_no', g.account_no, 'debit', l.debit, 'credit', l.credit)
                                                 order by l.line_no), '[]'))
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
  where l.entry_id = p_entry;
$$;

-- ---------------------------------------------------------------------
-- 4) Modo estricto: el asiento manual que mueve una cuenta controlada no se contabiliza
-- ---------------------------------------------------------------------
create or replace function erp.tg_entry_controlled_accounts()
returns trigger language plpgsql security definer set search_path = erp, public as $$
declare
  v_hit jsonb;
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on' then return null; end if;
  -- El asiento puede haberse borrado en la misma transacción; y solo importa el modo estricto
  if not exists (select 1 from erp.journal_entries e join erp.companies c on c.id = e.company_id
                 where e.id = new.id and e.status = 'posted' and c.control_mode = 'strict') then
    return null;
  end if;
  if not erp.entry_is_manual(new.id) then return null; end if;
  v_hit := erp.entry_controlled_lines(new.id);
  if jsonb_array_length(v_hit) > 0 then
    raise exception 'Account % is controlled by %: register it from that screen (or switch the company to guided mode)',
      v_hit->0->>'account_no', (select string_agg(m, ', ') from jsonb_array_elements_text(v_hit->0->'modules') m);
  end if;
  return null;
end $$;

drop trigger if exists entry_controlled_accounts on erp.journal_entries;
create constraint trigger entry_controlled_accounts
  after update of status on erp.journal_entries
  deferrable initially deferred
  for each row when (old.status = 'draft' and new.status = 'posted')
  execute function erp.tg_entry_controlled_accounts();

revoke execute on function erp.set_control_mode(uuid, text), erp.entry_is_manual(uuid), erp.entry_controlled_lines(uuid),
  erp.controlled_lines(jsonb), erp.control_rule_for(text), erp.tg_entry_controlled_accounts() from anon, public;
grant execute on function erp.set_control_mode(uuid, text), erp.controlled_lines(jsonb), erp.control_rule_for(text),
  erp.entry_controlled_lines(uuid) to authenticated;
