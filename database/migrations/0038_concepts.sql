-- =====================================================================
-- 0038 · CONCEPTOS: el glosario de la web, también en la base de datos · v0.33.0
-- ---------------------------------------------------------------------
-- Primera pieza de la ontología del ERP (concepto → cuentas del PGC → comprobaciones). La usarán el Tutor y el
-- chat (v0.37): un asiento sobre la 41000001 → conceptos «Tercero», «Partida abierta», «Cuenta controlada»…
--
-- La FUENTE sigue siendo frontend/src/glossary.js: la web lo muestra al instante y sin sesión (portada, cabecera).
-- Estas filas se generan desde él (frontend/tests/glossarySql.js) y frontend/tests/glossary.test.js falla si las dos
-- copias se separan. Para cambiar un término: edita glossary.js y añade una migración nueva con sus filas.
--
--   erp.concepts                     → término, definición y ejemplo (es / en), nombre en BC y SAP, cuentas del PGC
--   erp.concepts_for_account(cuenta) → conceptos de una subcuenta (por prefijo; el más largo primero)
--   erp.audit_checks.concept         → el concepto que explica cada comprobación (0037)
-- Re-ejecutable.
-- =====================================================================

create table if not exists erp.concepts (
  key            text primary key,
  sort           int  not null,
  term           text not null,
  definition     text not null,
  example        text,
  term_en        text not null,
  definition_en  text not null,
  example_en     text,
  bc             text not null,     -- nombre en Business Central
  sap            text not null,     -- nombre en SAP
  pgc            text[] not null default '{}'   -- prefijos del PGC con los que se relaciona
);
comment on table erp.concepts is 'Accounting concepts (the app glossary): definitions, BC / SAP names and related PGC accounts.';

insert into erp.concepts (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc) values
('debit', 10, 'Debe', 'Lado izquierdo de una cuenta. Aumentan por el Debe lo que tienes (caja, bancos, clientes) y los gastos.', 'Cobras 100 € en el banco: 572 al Debe.', 'Debit', 'Left side of an account. Assets (cash, bank, customers) and expenses increase on the debit side.', 'You collect €100 in the bank: 572 debit.', 'Debit Amount', 'Debit (S)', '{}'),
('credit', 20, 'Haber', 'Lado derecho de una cuenta. Aumentan por el Haber lo que debes (proveedores, préstamos), el capital y los ingresos.', 'Vendes por 100 €: 700 al Haber.', 'Credit', 'Right side of an account. Liabilities (suppliers, loans), equity and income increase on the credit side.', 'You sell for €100: 700 credit.', 'Credit Amount', 'Credit (H)', '{}'),
('doubleEntry', 30, 'Partida doble', 'Todo hecho económico mueve al menos dos cuentas, y la suma del Debe es siempre igual a la del Haber.', null, 'Double entry', 'Every transaction moves at least two accounts, and total debits always equal total credits.', null, 'Double-entry', 'Double-entry', '{}'),
('entry', 40, 'Asiento', 'Anotación de un hecho económico en la contabilidad: una fecha, un concepto y varias líneas (apuntes) que cuadran.', null, 'Journal entry', 'Record of a transaction in the books: a date, a description and several lines that balance.', null, 'G/L Entries (Document)', 'Accounting document (BKPF)', '{}'),
('draft', 50, 'Borrador', 'Asiento guardado pero no contabilizado: se puede cambiar o borrar y no cuenta en los informes.', null, 'Draft', 'An entry saved but not posted: it can be changed or deleted and does not count in the reports.', null, 'General Journal line', 'Parked document', '{}'),
('posting', 60, 'Contabilizar', 'Dar por definitivo un asiento: recibe su número correlativo, entra en los libros y ya no se puede cambiar.', null, 'Post', 'Make an entry final: it gets its sequential number, goes into the books and can no longer be changed.', null, 'Post', 'Post', '{}'),
('reversal', 70, 'Contraasiento', 'Asiento igual que otro pero con el Debe y el Haber cambiados: lo anula sin borrarlo, dejando rastro.', null, 'Reversal entry', 'An entry identical to another with debit and credit swapped: it cancels it without deleting it, leaving a trail.', null, 'Reverse Transaction', 'Reverse document (FB08)', '{}'),
('subaccount', 80, 'Subcuenta', 'Cuenta de último nivel donde se apunta, con todos sus dígitos. Cuelga de una cuenta del PGC.', '57200001 (un banco) cuelga de la 572 (Bancos).', 'Posting account', 'Last-level account where amounts are posted, with all its digits. It belongs to a chart-of-accounts account.', '57200001 (a bank) belongs to 572 (Banks).', 'G/L Account (Posting)', 'G/L account (SKB1)', '{}'),
('chart', 90, 'Plan General Contable (PGC)', 'Norma española (RD 1514/2007) que fija las cuentas, su numeración y cómo se valoran las operaciones.', null, 'Spanish GAAP (PGC)', 'Spanish standard (RD 1514/2007) that sets the accounts, their numbering and how transactions are measured.', null, 'Chart of Accounts', 'Chart of accounts (SKA1)', '{}'),
('partner', 100, 'Tercero', 'Cliente, proveedor, acreedor o deudor. Cada uno tiene su subcuenta (430, 400, 410, 440) y su NIF.', null, 'Business partner', 'Customer, supplier, creditor or debtor. Each has its own account (430, 400, 410, 440) and tax ID.', null, 'Customer / Vendor', 'Business Partner', '{400,410,430,440}'),
('fiscalYear', 110, 'Ejercicio', 'Periodo de 12 meses al que se refieren las cuentas anuales. Se abre, se lleva y se cierra.', null, 'Fiscal year', 'The 12-month period the annual accounts refer to. It is opened, kept and closed.', null, 'Accounting Period (year)', 'Fiscal year', '{}'),
('closing', 120, 'Cierre del ejercicio', 'Regularización (gastos e ingresos a la 129), asiento de cierre (todo a cero) y apertura del ejercicio siguiente.', null, 'Year-end closing', 'Closing the P&L into account 129, the closing entry (all to zero) and the opening entry of the next year.', null, 'Close Income Statement', 'Balance carryforward (FAGLGVTR)', '{129}'),
('journal', 130, 'Libro diario', 'Todos los asientos por orden de fecha y número. Es obligatorio (Código de Comercio, art. 28).', null, 'General journal', 'All entries in date and number order. It is a legal book in Spain.', null, 'G/L Register', 'Journal', '{}'),
('ledger', 140, 'Libro mayor', 'Los movimientos de una sola cuenta con su saldo acumulado.', null, 'General ledger', 'The movements of a single account with its running balance.', null, 'G/L Account Statement', 'Line items (FBL3N)', '{}'),
('trialBalance', 150, 'Balance de sumas y saldos', 'Por cada cuenta, la suma del Debe, la del Haber y su saldo. Si la contabilidad cuadra, los totales coinciden.', null, 'Trial balance', 'For each account, total debits, total credits and the balance. If the books balance, the totals match.', null, 'Trial Balance', 'Balance list (S_ALR_87012277)', '{}'),
('inverseBalance', 160, 'Saldo anómalo', 'Saldo contrario a la naturaleza de la cuenta: una caja acreedora o un cliente con saldo acreedor. Suele ser un error o una reclasificación pendiente.', null, 'Inverse balance', 'A balance against the nature of the account: cash in credit or a customer in credit. Usually an error or a pending reclassification.', null, '—', '—', '{}'),
('balance', 170, 'Balance de situación', 'Foto del patrimonio en una fecha: lo que la empresa tiene (activo) y cómo se financia (patrimonio neto y pasivo).', null, 'Balance sheet', 'A snapshot at a date: what the company owns (assets) and how it is financed (equity and liabilities).', null, 'Balance Sheet', 'Balance sheet', '{}'),
('pyg', 180, 'Cuenta de pérdidas y ganancias', 'Ingresos menos gastos de un periodo: el resultado (beneficio o pérdida).', null, 'Income statement', 'Income minus expenses for a period: the result (profit or loss).', null, 'Income Statement', 'P&L statement', '{}'),
('equity', 190, 'Patrimonio neto', 'Lo que es de los socios: capital, reservas y resultados. Activo menos pasivo.', null, 'Equity', 'What belongs to the owners: capital, reserves and results. Assets minus liabilities.', null, 'Equity', 'Equity', '{10,11,12}'),
('cashflow', 200, 'Estado de flujos de efectivo (EFE)', 'De dónde viene y a dónde va la caja: actividades de explotación, inversión y financiación.', 'Método directo (cobros y pagos) o indirecto (desde el resultado).', 'Cash flow statement', 'Where cash comes from and where it goes: operating, investing and financing activities.', 'Direct method (receipts and payments) or indirect (from the result).', 'Cash Flow Statement', 'Cash flow statement', '{}'),
('ratio', 210, 'Ratio', 'Cociente entre dos partidas que resume la salud de la empresa: liquidez, endeudamiento, rentabilidad.', 'Liquidez = activo corriente / pasivo corriente.', 'Ratio', 'A quotient of two items that summarises the company’s health: liquidity, leverage, profitability.', 'Current ratio = current assets / current liabilities.', 'KPI / Analysis View', 'KPI', '{}'),
('workingCapital', 220, 'Fondo de maniobra', 'Activo corriente menos pasivo corriente: el colchón para pagar las deudas a corto plazo.', null, 'Working capital', 'Current assets minus current liabilities: the cushion to pay short-term debts.', null, 'Working Capital', 'Working capital', '{}'),
('depreciation', 230, 'Amortización', 'Reparto del coste de un inmovilizado a lo largo de su vida útil: gasto (68x) contra amortización acumulada (28x).', null, 'Depreciation', 'Spreading a fixed asset’s cost over its useful life: expense (68x) against accumulated depreciation (28x).', null, 'Depreciation', 'Depreciation (AFAB)', '{28,68}'),
('vat', 240, 'IVA', 'Impuesto sobre el Valor Añadido, en la Península y Baleares. La empresa lo cobra en sus ventas y lo paga en sus compras; ingresa la diferencia.', 'Tipos: 21 %, 10 %, 4 %.', 'VAT (IVA)', 'Value Added Tax, in mainland Spain and the Balearics. The company charges it on sales and pays it on purchases, paying over the difference.', 'Rates: 21%, 10%, 4%.', 'VAT', 'Tax code (MWSKZ)', '{472,477}'),
('igic', 250, 'IGIC', 'Impuesto General Indirecto Canario: el equivalente del IVA en Canarias, con tipos propios.', 'Tipo general 7 %; se declara en el modelo 420.', 'IGIC', 'Canary Islands General Indirect Tax: the Canary Islands’ equivalent of VAT, with its own rates.', 'Standard rate 7%; filed on form 420.', 'VAT (local)', 'Tax code', '{472,477}'),
('inputTax', 260, 'IVA / IGIC soportado (472)', 'El impuesto que te cobran tus proveedores. Es un derecho frente a Hacienda: se resta en la liquidación.', null, 'Input VAT / IGIC (472)', 'The tax your suppliers charge you. It is a claim on the tax office: it is deducted in the settlement.', null, 'Purchase VAT', 'Input tax', '{472}'),
('outputTax', 270, 'IVA / IGIC repercutido (477)', 'El impuesto que cobras a tus clientes. Es una deuda con Hacienda hasta que lo liquidas.', null, 'Output VAT / IGIC (477)', 'The tax you charge your customers. It is a debt to the tax office until you settle it.', null, 'Sales VAT', 'Output tax', '{477}'),
('taxBase', 280, 'Base imponible', 'Importe sobre el que se calcula el impuesto: el precio sin IVA ni IGIC.', 'Base 1.000 € × 21 % = 210 € de IVA.', 'Tax base', 'The amount the tax is calculated on: the price before VAT or IGIC.', 'Base €1,000 × 21% = €210 VAT.', 'VAT Base', 'Tax base', '{}'),
('invoice', 290, 'Factura', 'Documento de una compra o venta con sus bases, tipos y cuotas. Al registrarla, el ERP genera el asiento y el libro registro.', null, 'Invoice', 'Document of a purchase or sale with its bases, rates and taxes. When registered, the ERP creates the entry and the tax register line.', null, 'Posted Purchase / Sales Invoice', 'FB60 / FB70', '{}'),
('creditMemo', 300, 'Factura rectificativa', 'Factura que corrige otra (devolución, descuento, error). Nunca se modifica la original.', null, 'Credit memo', 'An invoice that corrects another (return, discount, error). The original is never changed.', null, 'Credit Memo', 'Credit memo', '{}'),
('settlement', 310, 'Liquidación de IVA / IGIC', 'Cada trimestre: repercutido menos soportado. Si sale positivo se paga; si es negativo, se compensa o se pide la devolución en el 4T.', 'Modelos 303 (IVA) y 420 (IGIC).', 'VAT / IGIC settlement', 'Every quarter: output minus input tax. If positive it is paid; if negative it is carried forward or refunded in Q4.', 'Forms 303 (VAT) and 420 (IGIC).', 'Calc. and Post VAT Settlement', 'RFUMSV00', '{4700,4750}'),
('prorata', 320, 'Prorrata', 'Porcentaje del IVA soportado que se puede deducir cuando la empresa hace a la vez operaciones con y sin derecho a deducción.', null, 'Pro rata', 'The share of input VAT that can be deducted when the company has both taxable and exempt sales.', null, 'VAT % Non-deductible', 'Non-deductible input tax', '{472,634,639}'),
('reverseCharge', 330, 'Inversión del sujeto pasivo (ISP)', 'El comprador, no el vendedor, se repercute y se soporta el impuesto a la vez (autorrepercusión).', 'Compras intracomunitarias, obras con subcontratas.', 'Reverse charge', 'The buyer, not the seller, accounts for the tax, charging and deducting it at the same time.', 'Intra-EU purchases, subcontracted construction.', 'Reverse Charge VAT', 'Reverse charge', '{472,477}'),
('surcharge', 340, 'Recargo de equivalencia', 'Régimen de los minoristas personas físicas: su proveedor les cobra un recargo extra y ellos no presentan liquidación de IVA.', null, 'Equivalence surcharge', 'Regime for sole-trader retailers: their supplier charges an extra surcharge and they do not file VAT returns.', null, 'Equivalence surcharge', '—', '{477}'),
('withholding', 350, 'Retención de IRPF', 'Parte de la factura de un profesional o de un alquiler que el pagador ingresa en Hacienda por cuenta del perceptor (4751).', 'Modelos 111 (profesionales) y 115 (alquileres).', 'Income tax withholding', 'Part of a professional’s or landlord’s invoice that the payer pays to the tax office on their behalf (4751).', 'Forms 111 (professionals) and 115 (rents).', 'IRPF withholding', 'Withholding tax', '{4751,473}'),
('openItem', 360, 'Partida abierta', 'Factura que aún no está pagada o cobrada del todo. Un pago se aplica contra ella (la «liquida») y el resto queda pendiente.', 'Factura de 1.060 € con un pago de 500 €: quedan 560 € pendientes.', 'Open item', 'An invoice not yet fully paid or collected. A payment is applied to it and the rest stays open.', 'Invoice of €1,060 with a €500 payment: €560 stays open.', 'Open Vendor / Customer Ledger Entries', 'Open items (FBL1N / FBL5N)', '{400,410,430,440}'),
('aging', 370, 'Antigüedad de saldos', 'Lo pendiente de cada tercero repartido por días de vencido: sin vencer, 1–30, 31–60, 61–90 y más de 90.', 'Más de 90 días vencida: riesgo de impago y posible deterioro (490 / 694).', 'Aging', 'What each partner owes, split by days overdue: not due, 1–30, 31–60, 61–90 and over 90.', 'Over 90 days overdue: risk of non-payment and possible impairment (490 / 694).', 'Aged Accounts Payable / Receivable', 'Due date analysis (S_ALR_87012078)', '{400,410,430,440}'),
('controlledAccount', 380, 'Cuenta controlada', 'Cuenta que solo mueve su módulo (facturas, pagos, liquidación), no un asiento manual. Así la contabilidad y los documentos siempre cuadran.', 'La 410 la abona la factura recibida y la carga su pago.', 'Controlled account', 'An account posted only by its module (invoices, payments, settlement), not by a manual entry. That way the books and the documents always match.', 'Account 410 is credited by the received invoice and debited by its payment.', 'Direct Posting = No', 'Reconciliation account', '{400,410,430,440,472,477}'),
('controlMode', 390, 'Modo estricto o guiado', 'Estricto (como SAP o Business Central): un asiento manual sobre una cuenta controlada no se contabiliza. Guiado (como los ERP españoles): se contabiliza, avisa y queda en Comprobaciones.', null, 'Strict or guided mode', 'Strict (like SAP or Business Central): a manual entry on a controlled account is not posted. Guided (like Spanish ERPs): it is posted, with a warning, and listed in Checks.', null, 'Direct Posting', 'Reconciliation account', '{}'),
('auditCheck', 400, 'Comprobación (control posterior)', 'Cuadre que hace un auditor después de contabilizar: el IVA de la contabilidad frente al libro registro, cada tercero frente a sus facturas, los saldos al revés…', 'La 472 dice 231 € y el libro registro 210 €: sobra un asiento manual de 21 €.', 'Check (detective control)', 'A reconciliation an auditor makes after posting: VAT in the books against the VAT register, each partner against its invoices, balances on the wrong side…', 'Account 472 shows €231 and the VAT register €210: there is a €21 manual entry too many.', 'Reconciliation reports', 'Reconciliation reports', '{}'),
('accrual', 410, 'Devengo', 'Los ingresos y gastos se anotan cuando ocurren, no cuando se cobran o se pagan.', null, 'Accrual', 'Income and expenses are recorded when they occur, not when they are collected or paid.', null, 'Accrual', 'Accrual', '{}')
on conflict (key) do update set
  sort = excluded.sort, term = excluded.term, definition = excluded.definition, example = excluded.example,
  term_en = excluded.term_en, definition_en = excluded.definition_en, example_en = excluded.example_en,
  bc = excluded.bc, sap = excluded.sap, pgc = excluded.pgc;

alter table erp.concepts enable row level security;
drop policy if exists read on erp.concepts;
create policy read on erp.concepts for select to authenticated using (true);
revoke all on erp.concepts from anon, public;
grant select on erp.concepts to authenticated;

-- Conceptos de una subcuenta: los que tienen un prefijo del PGC que la empieza (el más largo primero)
create or replace function erp.concepts_for_account(p_account_no text)
returns setof erp.concepts language sql stable as $$
  select c.* from erp.concepts c
  where exists (select 1 from unnest(c.pgc) p where p_account_no like p || '%')
  order by (select max(length(p)) from unnest(c.pgc) p where p_account_no like p || '%') desc, c.sort;
$$;
revoke execute on function erp.concepts_for_account(text) from anon, public;
grant execute on function erp.concepts_for_account(text) to authenticated;

-- Cada comprobación del auditor, con el concepto que la explica (el ⓘ de la pantalla Comprobaciones)
alter table erp.audit_checks add column if not exists concept text references erp.concepts(key);
create index if not exists audit_checks_concept_idx on erp.audit_checks (concept);   -- toda clave foránea, con índice (0029)
update erp.audit_checks a set concept = v.concept
from (values ('vat_input', 'inputTax'), ('vat_output', 'outputTax'), ('withholdings', 'withholding'),
             ('partners', 'openItem'), ('anomalies', 'inverseBalance'), ('tax_territory', 'igic'),
             ('controlled', 'controlledAccount')) as v(code, concept)
where a.code = v.code;
