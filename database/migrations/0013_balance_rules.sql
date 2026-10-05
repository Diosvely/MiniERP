-- =====================================================================
-- 0013 · BALANCE RULES · Naturaleza de los saldos y saldos anómalos (bloque I)
-- ---------------------------------------------------------------------
-- Cada cuenta del PGC tiene un saldo "normal":
--   deudor   → activos y gastos (2, 3, 43, 47 deudoras, 57, 6…)
--   acreedor → patrimonio, pasivos e ingresos (1, 40/41, 475/477, 52, 7…)
--   y las CORRECTORAS van al revés: 28/29 amortización y deterioro, 39, 49, 59 · 606/608/609 · 706/708/709
-- Un saldo al revés no siempre es un error, pero un auditor lo revisa y suele RECLASIFICARLO al cierre:
--   572 Bancos acreedor → 5201 (descubierto) · 430 Clientes acreedor → 438 (anticipos de clientes)
--   400 Proveedores deudor → 407 (anticipos a proveedores) · 4750 deudora → 4700 …
--
--   erp.balance_rules            → catálogo global: prefijo PGC → naturaleza, reclasificación y explicación
--   erp.balance_nature(cuenta)   → regla aplicable (la del prefijo más largo)
--   erp.balance_anomalies(...)   → informe de saldos inversos sobre el balance de sumas y saldos
--   gl_accounts.block_inverse_balance → impide contabilizar si la cuenta queda al revés (570 Caja por defecto)
-- =====================================================================

create table erp.balance_rules (
  prefix      text primary key,
  nature      text not null check (nature in ('debit', 'credit', 'mixed')),
  reclass_to  text,          -- cuenta a la que se reclasifica un saldo inverso
  severity    text not null default 'warning' check (severity in ('warning', 'error')),
  note        text,
  note_en     text
);
comment on table erp.balance_rules is 'Normal balance side of each PGC account prefix (longest prefix wins).';

insert into erp.balance_rules (prefix, nature, reclass_to, severity, note, note_en) values
-- Grupo 1 · Financiación básica: acreedor salvo excepciones
('1',    'credit', null, 'warning', 'Patrimonio neto y pasivo a largo plazo: saldo acreedor.', 'Equity and long-term liabilities: credit balance.'),
('1030', 'debit',  null, 'warning', 'Socios por desembolsos no exigidos: saldo deudor (resta del capital).', 'Uncalled capital: debit balance (reduces capital).'),
('1040', 'debit',  null, 'warning', 'Socios por aportaciones no dinerarias pendientes: saldo deudor.', 'Pending non-cash contributions: debit balance.'),
('108',  'debit',  null, 'warning', 'Acciones propias: saldo deudor (resta del patrimonio).', 'Treasury shares: debit balance (reduces equity).'),
('109',  'debit',  null, 'warning', 'Acciones propias para reducción de capital: saldo deudor.', 'Treasury shares for capital reduction: debit balance.'),
('121',  'debit',  null, 'warning', 'Resultados negativos de ejercicios anteriores: saldo deudor.', 'Prior years losses: debit balance.'),
('129',  'mixed',  null, 'warning', 'Resultado del ejercicio: acreedor si hay beneficio, deudor si hay pérdida.', 'Profit or loss for the year: credit if profit, debit if loss.'),
('133',  'mixed',  null, 'warning', null, null),
('134',  'mixed',  null, 'warning', null, null),
('137',  'mixed',  null, 'warning', null, null),
('190',  'debit',  null, 'warning', null, null),
('192',  'debit',  null, 'warning', null, null),
('195',  'debit',  null, 'warning', null, null),
('197',  'debit',  null, 'warning', null, null),
-- Grupo 2 · Activo no corriente: deudor; amortizaciones y deterioros acreedores
('2',    'debit',  null, 'warning', 'Inmovilizado: saldo deudor.', 'Non-current assets: debit balance.'),
('28',   'credit', null, 'error',   'Amortización acumulada (correctora): saldo acreedor; nunca puede ser deudora.', 'Accumulated depreciation (contra account): credit balance; never debit.'),
('29',   'credit', null, 'error',   'Deterioro de valor (correctora): saldo acreedor.', 'Impairment (contra account): credit balance.'),
-- Grupo 3 · Existencias
('3',    'debit',  null, 'error',   'Existencias: saldo deudor; un inventario no puede ser negativo.', 'Inventories: debit balance; stock cannot be negative.'),
('39',   'credit', null, 'warning', 'Deterioro de existencias (correctora): saldo acreedor.', 'Inventory impairment (contra account): credit balance.'),
-- Grupo 4 · Acreedores y deudores comerciales
('40',   'credit', null,  'warning', 'Proveedores: saldo acreedor (lo que debemos).', 'Vendors: credit balance (what we owe).'),
('400',  'credit', '407', 'warning', 'Proveedor con saldo deudor: anticipo, pago duplicado o factura sin registrar. Al cierre se reclasifica a 407.', 'Vendor with a debit balance: advance, duplicate payment or missing invoice. Reclassify to 407 at year end.'),
('406',  'debit',  null,  'warning', 'Envases y embalajes a devolver a proveedores: saldo deudor.', 'Returnable packaging to vendors: debit balance.'),
('407',  'debit',  '400', 'warning', 'Anticipos a proveedores: saldo deudor.', 'Advances to vendors: debit balance.'),
('41',   'credit', null,  'warning', 'Acreedores varios: saldo acreedor.', 'Creditors: credit balance.'),
('410',  'credit', '440', 'warning', 'Acreedor con saldo deudor: anticipo o pago duplicado. Se presenta como deudor (440).', 'Creditor with a debit balance: advance or duplicate payment. Present as a debtor (440).'),
('43',   'debit',  null,  'warning', 'Clientes: saldo deudor (lo que nos deben).', 'Customers: debit balance (what they owe us).'),
('430',  'debit',  '438', 'warning', 'Cliente con saldo acreedor: anticipo, cobro duplicado o abono pendiente. Al cierre se reclasifica a 438.', 'Customer with a credit balance: advance, duplicate receipt or pending credit memo. Reclassify to 438 at year end.'),
('437',  'credit', null,  'warning', 'Envases y embalajes a devolver por clientes: saldo acreedor.', 'Returnable packaging from customers: credit balance.'),
('438',  'credit', '430', 'warning', 'Anticipos de clientes: saldo acreedor.', 'Advances from customers: credit balance.'),
('44',   'debit',  null,  'warning', 'Deudores varios: saldo deudor.', 'Other debtors: debit balance.'),
('46',   'credit', null,  'warning', 'Personal: remuneraciones pendientes de pago, saldo acreedor.', 'Personnel: wages payable, credit balance.'),
('460',  'debit',  null,  'warning', 'Anticipos de remuneraciones: saldo deudor.', 'Salary advances: debit balance.'),
('47',   'credit', null,  'warning', 'Administraciones públicas acreedoras: saldo acreedor.', 'Payables to public administrations: credit balance.'),
('470',  'debit',  null,  'warning', 'Hacienda Pública deudora: saldo deudor.', 'Tax receivables: debit balance.'),
('4700', 'debit',  '4750', 'warning', 'HP deudora por IVA/IGIC con saldo acreedor: revisar la liquidación.', 'VAT/IGIC receivable with a credit balance: review the settlement.'),
('471',  'debit',  null,  'warning', 'Seguridad Social deudora: saldo deudor.', 'Social Security receivable: debit balance.'),
('472',  'debit',  null,  'warning', 'IVA/IGIC soportado: saldo deudor hasta la liquidación (después, cero).', 'Input VAT/IGIC: debit balance until settled (then zero).'),
('473',  'debit',  null,  'warning', 'Retenciones y pagos a cuenta: saldo deudor.', 'Withholdings and payments on account: debit balance.'),
('474',  'debit',  null,  'warning', 'Activos por impuesto diferido: saldo deudor.', 'Deferred tax assets: debit balance.'),
('4750', 'credit', '4700', 'warning', 'HP acreedora por IVA/IGIC con saldo deudor: pago de más o liquidación pendiente.', 'VAT/IGIC payable with a debit balance: overpayment or pending settlement.'),
('477',  'credit', null,  'warning', 'IVA/IGIC repercutido: saldo acreedor hasta la liquidación (después, cero).', 'Output VAT/IGIC: credit balance until settled (then zero).'),
('48',   'mixed',  null,  'warning', null, null),
('480',  'debit',  null,  'warning', 'Gastos anticipados: saldo deudor.', 'Prepaid expenses: debit balance.'),
('485',  'credit', null,  'warning', 'Ingresos anticipados: saldo acreedor.', 'Deferred income: credit balance.'),
('49',   'credit', null,  'warning', 'Deterioros y provisiones a corto plazo (correctoras): saldo acreedor.', 'Short-term impairment and provisions: credit balance.'),
-- Grupo 5 · Cuentas financieras
('5',    'credit', null,   'warning', 'Deudas a corto plazo: saldo acreedor.', 'Short-term debts: credit balance.'),
('5201', 'credit', '572',  'warning', 'Crédito dispuesto: saldo acreedor.', 'Credit line drawn: credit balance.'),
('53',   'debit',  null,   'warning', 'Inversiones financieras en empresas del grupo: saldo deudor.', 'Group investments: debit balance.'),
('54',   'debit',  null,   'warning', 'Otras inversiones financieras a corto plazo: saldo deudor.', 'Other short-term investments: debit balance.'),
('55',   'mixed',  null,   'warning', 'Otras cuentas no bancarias (socios, partidas pendientes): saldo deudor o acreedor.', 'Other non-bank accounts (partners, suspense): debit or credit balance.'),
('565',  'debit',  null,   'warning', 'Fianzas constituidas a corto plazo: saldo deudor.', 'Short-term deposits given: debit balance.'),
('566',  'debit',  null,   'warning', 'Depósitos constituidos a corto plazo: saldo deudor.', 'Short-term deposits made: debit balance.'),
('57',   'debit',  null,   'warning', 'Tesorería: saldo deudor.', 'Cash and banks: debit balance.'),
('570',  'debit',  null,   'error',   'Caja con saldo acreedor: es imposible tener dinero negativo en caja; falta un cobro o sobra un pago.', 'Cash with a credit balance is impossible: a receipt is missing or a payment is wrong.'),
('571',  'debit',  null,   'error',   'Caja con saldo acreedor: imposible.', 'Cash with a credit balance: impossible.'),
('572',  'debit',  '5201', 'warning', 'Banco con saldo acreedor: descubierto o póliza de crédito. Al cierre se reclasifica a 5201 (deuda con entidades de crédito).', 'Bank with a credit balance: overdraft or credit line. Reclassify to 5201 at year end.'),
('58',   'mixed',  null,   'warning', null, null),
('59',   'credit', null,   'warning', 'Deterioros de inversiones financieras (correctoras): saldo acreedor.', 'Impairment of financial investments: credit balance.'),
-- Grupo 6 · Compras y gastos: deudor; devoluciones, descuentos y rappels acreedores
('6',    'debit',  null, 'warning', 'Gastos: saldo deudor.', 'Expenses: debit balance.'),
('606',  'credit', null, 'warning', 'Descuentos sobre compras por pronto pago: saldo acreedor.', 'Early payment discounts on purchases: credit balance.'),
('608',  'credit', null, 'warning', 'Devoluciones de compras: saldo acreedor.', 'Purchase returns: credit balance.'),
('609',  'credit', null, 'warning', 'Rappels por compras: saldo acreedor.', 'Volume discounts on purchases: credit balance.'),
('61',   'mixed',  null, 'warning', 'Variación de existencias: deudora o acreedora según aumente o disminuya el stock.', 'Change in inventories: debit or credit depending on stock movement.'),
('71',   'mixed',  null, 'warning', 'Variación de existencias: deudora o acreedora.', 'Change in inventories: debit or credit.'),
-- Grupo 7 · Ventas e ingresos: acreedor; devoluciones, descuentos y rappels deudores
('7',    'credit', null, 'warning', 'Ingresos: saldo acreedor.', 'Income: credit balance.'),
('706',  'debit',  null, 'warning', 'Descuentos sobre ventas por pronto pago: saldo deudor.', 'Early payment discounts on sales: debit balance.'),
('708',  'debit',  null, 'warning', 'Devoluciones de ventas: saldo deudor.', 'Sales returns: debit balance.'),
('709',  'debit',  null, 'warning', 'Rappels sobre ventas: saldo deudor.', 'Volume discounts on sales: debit balance.');

alter table erp.balance_rules enable row level security;
create policy read on erp.balance_rules for select to authenticated using (true);
revoke all on erp.balance_rules from anon, public;
grant select on erp.balance_rules to authenticated;

-- Regla aplicable a una cuenta: la del prefijo más largo
create or replace function erp.balance_nature(p_account_no text)
returns erp.balance_rules language sql stable as $$
  select r.* from erp.balance_rules r
  where p_account_no like r.prefix || '%'
  order by length(r.prefix) desc
  limit 1;
$$;

-- ---------------------------------------------------------------------
-- INFORME DE SALDOS ANÓMALOS (inversos a su naturaleza)
--   mismo nivel y fecha que el balance de sumas y saldos
-- ---------------------------------------------------------------------
create or replace function erp.balance_anomalies(
  p_company uuid, p_year int, p_level int default null, p_to_date date default null)
returns table (account_no text, name text, name_en text, expected text, balance numeric,
               reclass_to text, severity text, note text, note_en text)
language sql stable as $$
  select tb.account_no, tb.name, tb.name_en, r.nature,
         tb.debit_balance - tb.credit_balance,
         r.reclass_to, r.severity, r.note, r.note_en
  from erp.trial_balance(p_company, p_year, p_level, p_to_date) tb
  cross join lateral erp.balance_nature(tb.account_no) r
  -- a nivel de grupo (1) o subgrupo (2) se mezclan cuentas de distinta naturaleza: no se analiza
  where (p_level is null or p_level >= 3)
    and ((r.nature = 'debit'  and tb.credit_balance > 0)
      or (r.nature = 'credit' and tb.debit_balance  > 0))
  order by case r.severity when 'error' then 0 else 1 end, tb.account_no;
$$;

-- ---------------------------------------------------------------------
-- BLOQUEO OPCIONAL: cuentas que nunca pueden quedar al revés (por defecto, la caja 570/571)
-- ---------------------------------------------------------------------
alter table erp.gl_accounts add column block_inverse_balance boolean not null default false;
comment on column erp.gl_accounts.block_inverse_balance is
  'If true, an entry cannot be posted when it leaves this account with a balance opposite to its nature.';

update erp.gl_accounts set block_inverse_balance = true
where account_type = 'posting' and left(account_no, 3) in ('570', '571');

create or replace function erp.tg_gl_account_block_default()
returns trigger language plpgsql as $$
begin
  if new.account_type = 'posting' and left(new.account_no, 3) in ('570', '571') then
    new.block_inverse_balance := true;
  end if;
  return new;
end $$;

create trigger gl_account_block_default before insert on erp.gl_accounts
  for each row execute function erp.tg_gl_account_block_default();

-- Al contabilizar, comprobar las cuentas bloqueadas que mueve el asiento
create or replace function erp.tg_entry_check_inverse()
returns trigger language plpgsql as $$
declare
  r record;
begin
  for r in
    select g.account_no, g.name, n.nature,
           (select coalesce(sum(l2.debit - l2.credit), 0)
              from erp.journal_lines l2
              join erp.journal_entries e2 on e2.id = l2.entry_id
             where l2.gl_account_id = g.id and e2.status = 'posted'
               and e2.fiscal_year_id = new.fiscal_year_id and e2.posting_date <= new.posting_date) as bal
    from (select distinct gl_account_id from erp.journal_lines where entry_id = new.id) x
    join erp.gl_accounts g on g.id = x.gl_account_id and g.block_inverse_balance
    cross join lateral erp.balance_nature(g.account_no) n
  loop
    if (r.nature = 'debit' and r.bal < 0) or (r.nature = 'credit' and r.bal > 0) then
      raise exception 'Account % (%) would have a % balance of % on %: it is blocked for inverse balances',
        r.account_no, r.name, case when r.bal < 0 then 'credit' else 'debit' end, abs(r.bal), new.posting_date;
    end if;
  end loop;
  return new;
end $$;

create trigger entry_check_inverse
  after update of status on erp.journal_entries
  for each row when (old.status = 'draft' and new.status = 'posted')
  execute function erp.tg_entry_check_inverse();

revoke execute on function erp.balance_nature(text), erp.balance_anomalies(uuid, int, int, date) from anon, public;
grant execute on function erp.balance_nature(text), erp.balance_anomalies(uuid, int, int, date) to authenticated;
