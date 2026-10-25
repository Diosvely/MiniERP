-- =====================================================================
-- 0067 · PANTALLA «CASOS»: operaciones del caso, dos modos de carga y empresa del caso · v0.46.0
-- ---------------------------------------------------------------------
-- Diseño validado (diseno-v0.46.0.md):
--   · erp.case_steps: las 19 operaciones del caso, con su fecha, su asiento, por qué se hace así y en qué pantalla
--     (en español y en inglés). Las del cierre (11 a 19) dicen también su paso del asistente de cierre.
--   · Dos modos de carga:
--       full           las 19 operaciones, con el cierre hecho;
--       until_closing  las operaciones 1 a 10 (el año, con el IGIC del 4T liquidado); las del cierre las hace quien
--                      estudia, con el asistente de cierre.
--   · erp.case_entries: qué asientos hizo cada operación al cargar el caso (para ir de la operación a su asiento).
--   · erp.create_case_company: crea la empresa del caso (con el límite de empresas de siempre) y lo carga.
--   · erp.case_progress: cada operación, hecha o pendiente, con sus asientos.
--   · erp.case_compare: ahora con estado: ok, diferencia o pendiente (cifras que dependen del cierre mientras no
--     está contabilizado el Impuesto sobre Sociedades).
-- Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Las operaciones de cada caso
-- ---------------------------------------------------------------------
create table if not exists erp.case_steps (
  case_key       text not null references erp.cases (key) on delete cascade,
  n              int  not null,
  phase          text not null check (phase in ('year', 'closing')),
  date_label     text not null,
  date_label_en  text not null,
  title          text not null,
  title_en       text not null,
  entry          text not null,
  why            text not null,
  why_en         text not null,
  screen         text not null,
  checklist_code text,
  primary key (case_key, n)
);
comment on table erp.case_steps is 'Operaciones de cada caso completo: fecha, asiento, por qué y en qué pantalla';
alter table erp.case_steps enable row level security;
drop policy if exists read on erp.case_steps;
create policy read on erp.case_steps for select to authenticated using (true);
revoke all on erp.case_steps from anon, public;
grant select on erp.case_steps to authenticated;

delete from erp.case_steps where case_key = 'taller_atlantico';
insert into erp.case_steps (case_key, n, phase, date_label, date_label_en, title, title_en, entry, why, why_en, screen, checklist_code) values
('taller_atlantico', 1, 'year', '02/01', '02/01', 'Constitución: capital de 60.000 €, desembolsado por el banco', 'Incorporation: €60,000 share capital, paid in through the bank',
 '190 / 194 · 572 / 190 · 194 / 100 (60.000)',
 'Una SL se constituye con el capital totalmente desembolsado (art. 78 LSC). La 194 recoge el capital hasta que se inscribe en el Registro Mercantil; entonces pasa a la 100.',
 'An SL is incorporated with its capital fully paid (art. 78 LSC). Account 194 holds the capital until it is registered; then it moves to 100.',
 'equity', null),
('taller_atlantico', 2, 'year', '05/01', '05/01', 'Notaría y registro: 1.000 € + IGIC 70, a reservas, pagados', 'Notary and registry: €1,000 + IGIC 70, charged to reserves, paid',
 '113 D 1.000 · 472 D 70 / 410 H 1.070 · 410 / 572',
 'Los gastos de constitución no son gasto del año: van contra reservas (NRV 9.ª, apdo. 4). Fiscalmente son deducibles (LIS art. 11.3), lo que da un ajuste negativo en el Impuesto sobre Sociedades.',
 'Incorporation costs are not an expense of the year: they are charged to reserves (NRV 9, section 4). They are tax-deductible (LIS art. 11.3), which gives a negative adjustment in corporate tax.',
 'invoices', null),
('taller_atlantico', 3, 'year', 'Cada trimestre', 'Every quarter', 'Asesoría: 600 € + IGIC 42 − retención del 15 % (90); se pagan las tres primeras', 'Accounting advice: €600 + IGIC 42 − 15 % withholding (90); the first three are paid',
 '623 D 600 · 472 D 42 / 4751 H 90 · 410 H 552',
 'A un profesional se le retiene el 15 % del IRPF (LIRPF, art. 101), que la empresa ingresa con el modelo 111. La factura de diciembre queda sin pagar.',
 'A 15 % income-tax withholding is applied to a professional (LIRPF, art. 101), which the company pays with form 111. The December invoice is left unpaid.',
 'invoices', null),
('taller_atlantico', 4, 'year', 'Cada trimestre', 'Every quarter', 'Compras de recambios: 10.000 € por trimestre y 15.000 en el 4T; se pagan todas menos la del 4T', 'Purchases of spare parts: €10,000 a quarter and 15,000 in Q4; all paid except Q4',
 '600 · 472 / 400 · 400 / 572',
 'Las mercaderías se compran a la 600 y el IGIC soportado (7 %) se deduce en el modelo 420. Las existencias se ajustan en el cierre, no con cada compra.',
 'Goods are purchased to 600 and the input IGIC (7 %) is deducted in form 420. Inventory is adjusted at year end, not with each purchase.',
 'invoices', null),
('taller_atlantico', 5, 'year', 'Cada trimestre', 'Every quarter', 'Ventas: 120.000 € en el año; se cobran todas menos la del 4T y una dudosa de 2.000 (15/03)', 'Sales: €120,000 in the year; all collected except Q4 and a doubtful one of 2,000 (15/03)',
 '430 / 700 · 477 · 572 / 430',
 'Cada venta lleva su IGIC repercutido (477). La venta dudosa se queda sin cobrar: en el cierre se deteriora.',
 'Each sale carries its output IGIC (477). The doubtful sale is not collected: it is impaired at year end.',
 'invoices', null),
('taller_atlantico', 6, 'year', '01/04', '01/04', 'Máquina de 40.000 € + IGIC 2.800, 10 años de vida útil; se paga el 15/04', 'Machine of €40,000 + IGIC 2,800, 10-year useful life; paid on 15/04',
 '213 D 40.000 · 472 D 2.800 / 400 H 42.800 · 400 / 572',
 'Se registra por su precio de adquisición (NRV 2.ª) y se le abre su ficha de Inmovilizado para amortizarla. En el EFE, el pago es una inversión (40.000) y su IGIC, explotación.',
 'It is recorded at its acquisition cost (NRV 2) and gets a fixed-asset card to be depreciated. In the cash flow statement the payment is an investment (40,000) and its IGIC, operating.',
 'assets', null),
('taller_atlantico', 7, 'year', '15/04', '15/04', 'Subvención de capital de 16.000 € (el 40 % de la máquina), cobrada el 30/06', 'Capital grant of €16,000 (40 % of the machine), collected on 30/06',
 '4708 / 940 16.000 · 8301 / 479 4.000 · 572 / 4708',
 'No es un ingreso del año: va al patrimonio neto (grupo 9), neta del impuesto que se pagará cuando pase a resultados (NRV 18.ª y 13.ª, al 25 %).',
 'It is not income of the year: it goes to equity (group 9), net of the tax to be paid when it is transferred to profit (NRV 18 and 13, at 25 %).',
 'grants', null),
('taller_atlantico', 8, 'year', '01/07', '01/07', 'Préstamo bancario de 30.000 € al 5 %, en 3 cuotas anuales', 'Bank loan of €30,000 at 5 %, in 3 yearly instalments',
 '572 D 30.000 / 5200 H 9.516,26 · 1700 H 20.483,74',
 'Se valora a coste amortizado (NRV 9.ª). Lo que vence en los próximos 12 meses es deuda a corto plazo (5200) y el resto, a largo (1700).',
 'It is measured at amortised cost (NRV 9). What falls due in the next 12 months is short-term debt (5200) and the rest, long-term (1700).',
 'financing', null),
('taller_atlantico', 9, 'year', '01/10', '01/10', 'Seguro anual: 1.200 € (exento de IGIC), pagado', 'Yearly insurance: €1,200 (IGIC-exempt), paid',
 '625 D 1.200 / 572 H 1.200',
 'Se paga el año entero por adelantado; en el cierre, la parte de 2027 se periodifica.',
 'The whole year is paid in advance; at year end the 2027 part is deferred.',
 'entry', null),
('taller_atlantico', 10, 'year', 'Cada trimestre', 'Every quarter', 'Liquidaciones del IGIC (modelo 420) y retenciones (111): se pagan las tres primeras', 'IGIC returns (form 420) and withholdings (111): the first three are paid',
 '477 / 472 · 4750 · 4750 / 572 · 4751 / 572',
 'Cada trimestre se compensa el IGIC repercutido con el soportado y la diferencia se ingresa (938 · 308 · 658 · 308). Lo del 4T se paga en enero: queda en el balance.',
 'Each quarter output IGIC is offset against input IGIC and the difference is paid (938 · 308 · 658 · 308). Q4 is paid in January: it stays on the balance sheet.',
 'settlement', null),
('taller_atlantico', 11, 'closing', '31/12', '31/12', 'Amortización de la máquina: 40.000 / 10 × 9 / 12 = 3.000', 'Depreciation of the machine: 40,000 / 10 × 9 / 12 = 3,000',
 '681 D 3.000 / 2813 H 3.000',
 'Se amortiza desde que entra en funcionamiento (01/04): nueve meses del año.',
 'It is depreciated from when it is put into use (01/04): nine months of the year.',
 'assets', 'depreciation'),
('taller_atlantico', 12, 'closing', '31/12', '31/12', 'Imputación de la subvención: 16.000 × 3.000 / 40.000 = 1.200', 'Transfer of the grant to profit: 16,000 × 3,000 / 40,000 = 1,200',
 '840 / 746 1.200 · 479 / 8301 300',
 'La subvención pasa a resultados al ritmo de la amortización de la máquina (correlación de ingresos y gastos, NRV 18.ª).',
 'The grant is transferred to profit at the pace of the machine''s depreciation (matching of income and expenses, NRV 18).',
 'grants', 'grants'),
('taller_atlantico', 13, 'closing', '31/12', '31/12', 'Intereses devengados del préstamo: 30.000 × (1,05^0,5 − 1) = 740,85', 'Accrued loan interest: 30,000 × (1.05^0.5 − 1) = 740.85',
 '6623 D 740,85 / 527 H 740,85',
 'Seis meses de intereses que aún no se han pagado: son gasto de 2026 (devengo).',
 'Six months of interest not yet paid: they are an expense of 2026 (accruals).',
 'financing', 'financing'),
('taller_atlantico', 14, 'closing', '31/12', '31/12', 'Reclasificación a corto plazo: no hay (la 1.ª cuota ya está a corto)', 'Reclassification to short term: none (the 1st instalment is already short-term)',
 '—',
 'Solo pasa a corto lo que vence hasta el 31/12/2027: la cuota de junio de 2027, que ya se registró a corto.',
 'Only what falls due by 31/12/2027 moves to short term: the June 2027 instalment, already recorded as short-term.',
 'financing', 'financing'),
('taller_atlantico', 15, 'closing', '31/12', '31/12', 'Seguro pagado por adelantado: 9 de los 12 meses son de 2027 (900)', 'Prepaid insurance: 9 of the 12 months belong to 2027 (900)',
 '480 D 900 / 625 H 900',
 'Principio de devengo: el gasto de 2027 no puede estar en la cuenta de resultados de 2026.',
 'Accrual principle: the 2027 expense cannot be in the 2026 income statement.',
 'adjustments', 'accruals'),
('taller_atlantico', 16, 'closing', '31/12', '31/12', 'Deterioro del cliente dudoso: 2.000 + IGIC 140, más de 6 meses sin cobrar', 'Impairment of the doubtful customer: 2,000 + IGIC 140, unpaid for more than 6 months',
 '694 D 2.140 / 490 H 2.140',
 'Pasados seis meses del vencimiento, el deterioro es además deducible (LIS art. 13.1). Se deteriora el total, con el IGIC.',
 'After six months past due, the impairment is also tax-deductible (LIS art. 13.1). The whole amount, including IGIC, is impaired.',
 'adjustments', 'bad_debts'),
('taller_atlantico', 17, 'closing', '31/12', '31/12', 'Existencias finales: inventario de 8.000 € (inicial 0)', 'Closing inventory: count of €8,000 (opening 0)',
 '300 D 8.000 / 610 H 8.000',
 'La variación de existencias corrige las compras: el consumo del año es 45.000 − 8.000 = 37.000.',
 'The change in inventory corrects purchases: the cost of goods used is 45,000 − 8,000 = 37,000.',
 'adjustments', 'inventory'),
('taller_atlantico', 18, 'closing', '31/12', '31/12', 'Impuesto sobre Sociedades: entidad de nueva creación (15 %)', 'Corporate tax: newly created entity (15 %)',
 '6300 D 11.342,87 / 4752 H 11.192,87 · 113 H 150',
 'Base imponible = 75.619,15 − 1.000 de la notaría (LIS art. 11.3) = 74.619,15; cuota al 15 % (art. 29.1): 11.192,87. El ahorro de la notaría (150) va a reservas.',
 'Taxable base = 75,619.15 − 1,000 notary costs (LIS art. 11.3) = 74,619.15; tax at 15 % (art. 29.1): 11,192.87. The saving on the notary costs (150) goes to reserves.',
 'corporate_tax', 'corporate_tax'),
('taller_atlantico', 19, 'closing', '31/12', '31/12', 'Cierre: regularización (6 / 7 → 129; 8 / 9 → 130), cierre y apertura de 2027', 'Closing: closing of P&L (6 / 7 → 129; 8 / 9 → 130), closing and opening of 2027',
 '129 · 130 · asiento de cierre · apertura',
 'El resultado del año (64.276,28) pasa a la 129 y los grupos 8 y 9 a la 130; el balance se abre en 2027.',
 'The profit of the year (64,276.28) goes to 129 and groups 8 and 9 to 130; the balance sheet is opened in 2027.',
 'closing', 'close');

-- ---------------------------------------------------------------------
-- 2) Qué asientos hizo cada operación, y el modo en que se cargó el caso
-- ---------------------------------------------------------------------
create table if not exists erp.case_entries (
  company_id uuid not null references erp.companies (id) on delete cascade,
  n          int  not null,
  entry_id   uuid not null references erp.journal_entries (id) on delete cascade,
  primary key (company_id, entry_id)
);
create index if not exists case_entries_entry_idx on erp.case_entries (entry_id);
comment on table erp.case_entries is 'Asientos que hizo cada operación al cargar un caso completo';
alter table erp.case_entries enable row level security;
drop policy if exists read on erp.case_entries;
create policy read on erp.case_entries for select to authenticated using (erp.can_read(company_id));
revoke all on erp.case_entries from anon, public;
grant select on erp.case_entries to authenticated;

alter table erp.companies add column if not exists case_mode text check (case_mode in ('full', 'until_closing'));
comment on column erp.companies.case_mode is 'Cómo se cargó el caso: completo o hasta el cierre';

-- Apunta los asientos nuevos de la empresa a una operación (solo su administrador, al cargar el caso)
create or replace function erp.case_mark(e uuid, p_n int)
returns void language plpgsql security definer set search_path = erp, public as $$
begin
  if not erp.is_admin(e) then raise exception 'No permission: only the company admin can load a case'; end if;
  insert into erp.case_entries (company_id, n, entry_id)
  select e, p_n, j.id from erp.journal_entries j
  where j.company_id = e and not exists (select 1 from erp.case_entries c where c.company_id = e and c.entry_id = j.id);
end $$;
revoke execute on function erp.case_mark(uuid, int) from anon, public;
grant execute on function erp.case_mark(uuid, int) to authenticated;

alter table erp.cases add column if not exists company_name text;
update erp.cases set company_name = 'Taller Atlántico SL' where key = 'taller_atlantico';

-- ---------------------------------------------------------------------
-- 3) Cargar un caso (versión de la 0066 con el modo de carga y los asientos de cada operación)
-- ---------------------------------------------------------------------
drop function if exists erp.load_case(uuid, text);
create or replace function erp.load_case(p_company uuid, p_case text default 'taller_atlantico', p_mode text default 'full')
returns jsonb language plpgsql set search_path = erp, public as $$
declare
  e uuid := p_company; v_case erp.cases; v_co erp.companies; c text; q int;
  prov uuid; maq uuid; notaria uuid; aseso uuid; cli uuid; dud uuid;
  f uuid; f_dud uuid; f_maq uuid; a uuid; g uuid; v_ret uuid; v_pay date; v_due numeric;
  v_sales numeric[] := array[23000, 55000, 20000, 20000];
  v_purchases numeric[] := array[10000, 10000, 10000, 15000];
  v_end date[] := array['2026-03-31', '2026-06-30', '2026-09-30', '2026-12-31']::date[];
begin
  select * into v_case from erp.cases where key = p_case;
  if not found then raise exception 'Unknown case: %', p_case; end if;
  if p_mode is null or p_mode not in ('full', 'until_closing') then raise exception 'Invalid case mode: %', p_mode; end if;
  if not erp.is_admin(e) then raise exception 'No permission: only the company admin can load a case'; end if;
  select * into v_co from erp.companies where id = e;
  if v_co.tax_territory <> v_case.tax_territory then
    raise exception 'This case needs a company in the Canary Islands (IGIC)';
  end if;
  if v_co.legal_form <> v_case.legal_form then raise exception 'This case needs a limited company (SL)'; end if;
  if exists (select 1 from erp.journal_entries j where j.company_id = e) then
    raise exception 'Load the case into a new company: this one already has entries';
  end if;

  -- Preparación: ejercicios, impuestos, retenciones, cuentas y terceros
  perform erp.create_fiscal_year(e, y) from generate_series(2026, 2027) y
  where not exists (select 1 from erp.fiscal_years fy where fy.company_id = e and fy.year = y);
  perform erp.setup_taxes(e);
  perform erp.setup_withholdings(e);
  foreach c in array array['57200001:Banco', '60000001:Compras de mercaderías', '70000001:Ventas de mercaderías',
    '62300001:Asesoría', '62500001:Primas de seguros', '11300001:Reservas voluntarias', '21300001:Maquinaria', '30000001:Mercaderías'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  select partner_id into prov    from erp.create_partner(e, 'vendor',   'Recambios Canarios SL',  'B12345674');
  select partner_id into maq     from erp.create_partner(e, 'vendor',   'Maquinaria Atlántica SL', 'B87654323');
  select partner_id into notaria from erp.create_partner(e, 'creditor', 'Notaría Ejemplo SL',     'A58818501');
  select partner_id into aseso   from erp.create_partner(e, 'creditor', 'Asesoría Martín',        '12345678Z');
  select partner_id into cli     from erp.create_partner(e, 'customer', 'Cliente General SL',     'B11111119');
  select partner_id into dud     from erp.create_partner(e, 'customer', 'Cliente Dudoso SL',      'B76543214');

  -- 1. Constitución (Operaciones societarias)
  perform erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-02', 'capital', 60000, 'bank_account_no', '57200001'));
  perform erp.case_mark(e, 1);
  -- 2. Notaría y registro, a reservas (NRV 9.ª), pagados en el acto (Facturas · Cobros y pagos)
  f := erp.case_invoice(e, 'purchase', notaria, '2026-01-05', 'N-1', 'Notaría y registro de la constitución',
         '[{"account_no": "11300001", "amount": 1000, "tax_code": "IGIC7"}]');
  perform erp.case_payment(e, 'payment', notaria, '2026-01-05', f);
  perform erp.case_mark(e, 2);
  -- 6. La máquina, su ficha y su pago (Facturas · Inmovilizado · Cobros y pagos)
  f_maq := erp.case_invoice(e, 'purchase', maq, '2026-04-01', 'M-1', 'Máquina de diagnosis',
             '[{"account_no": "21300001", "amount": 40000, "tax_code": "IGIC7"}]');
  select asset_id into a from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Máquina de diagnosis',
    'asset_account_no', '21300001', 'cost', 40000, 'useful_life_months', 120, 'start_date', '2026-04-01',
    'acquisition_date', '2026-04-01', 'invoice_id', f_maq));
  perform erp.case_payment(e, 'payment', maq, '2026-04-15', f_maq);
  perform erp.case_mark(e, 6);
  -- 7. Subvención de capital del 40 % de la máquina, cobrada el 30/06 (Subvenciones)
  g := (erp.grant_create(jsonb_build_object('company_id', e, 'kind', 'capital', 'description', 'Subvención para la máquina de diagnosis',
         'grantor', 'Gobierno de Canarias', 'amount', 16000, 'date', '2026-04-15', 'asset_id', a))->>'grant_id')::uuid;
  perform erp.grant_collect(jsonb_build_object('grant_id', g, 'date', '2026-06-30'));
  perform erp.case_mark(e, 7);
  -- 8. Préstamo de 30.000 al 5 %, tres cuotas anuales (Financiación)
  perform erp.loan_create(jsonb_build_object('company_id', e, 'description', 'Préstamo para circulante', 'lender', 'Banco Atlántico',
    'principal', 30000, 'rate', 5, 'periods', 3, 'frequency', 1, 'start_date', '2026-07-01'));
  perform erp.case_mark(e, 8);
  -- 9. Seguro anual, exento, pagado (Nuevo asiento)
  perform erp.case_entry(e, '2026-10-01', 'Seguro anual del taller', '[["62500001", 1200, 0], ["57200001", 0, 1200]]');
  perform erp.case_mark(e, 9);
  -- 3, 4, 5 y 10. Cada trimestre: compras, ventas, asesoría, liquidación del IGIC y retenciones
  for q in 1..4 loop
    f := erp.case_invoice(e, 'purchase', prov, v_end[q] - 45, 'C-' || q, 'Compra de recambios',
           jsonb_build_array(jsonb_build_object('account_no', '60000001', 'amount', v_purchases[q], 'tax_code', 'IGIC7')));
    if q < 4 then perform erp.case_payment(e, 'payment', prov, v_end[q] - 30, f); end if;
    perform erp.case_mark(e, 4);
    f := erp.case_invoice(e, 'sale', cli, v_end[q] - 40, null, 'Venta de recambios',
           jsonb_build_array(jsonb_build_object('account_no', '70000001', 'amount', v_sales[q], 'tax_code', 'IGIC7')));
    if q < 4 then perform erp.case_payment(e, 'collection', cli, v_end[q] - 10, f); end if;
    if q = 1 then   -- la venta dudosa del 15/03, que no se cobra
      f_dud := erp.case_invoice(e, 'sale', dud, '2026-03-15', null, 'Venta de recambios',
                 '[{"account_no": "70000001", "amount": 2000, "tax_code": "IGIC7"}]');
    end if;
    perform erp.case_mark(e, 5);
    f := erp.case_invoice(e, 'purchase', aseso, v_end[q], 'A-' || q, 'Asesoría del trimestre',
           '[{"account_no": "62300001", "amount": 600, "tax_code": "IGIC7"}]', 'IRPF15');
    if q < 4 then perform erp.case_payment(e, 'payment', aseso, v_end[q], f); end if;
    perform erp.case_mark(e, 3);
    perform erp.post_tax_settlement(e, 'IGIC', 2026, q);
    if q < 4 then   -- los modelos 420 y 111 se pagan el día 20 del mes siguiente; los del 4T, en enero
      v_pay := v_end[q] + 20;
      v_due := erp.case_balance(e, '4750', v_pay);
      perform erp.case_entry(e, v_pay, 'Pago del modelo 420 · ' || q || 'T',
        jsonb_build_array(jsonb_build_array('4750', v_due, 0), jsonb_build_array('57200001', 0, v_due)));
      perform erp.case_entry(e, v_pay, 'Pago del modelo 111 · ' || q || 'T', '[["4751", 90, 0], ["57200001", 0, 90]]');
    end if;
    perform erp.case_mark(e, 10);
  end loop;

  -- 11 a 19. El cierre del 31/12/2026 (en el modo «hasta el cierre», lo hace quien estudia)
  if p_mode = 'full' then
    perform erp.post_depreciation(e, '2026-12-31');                    perform erp.case_mark(e, 11);   -- Inmovilizado
    perform erp.grant_year_end(e, '2026-12-31');                       perform erp.case_mark(e, 12);   -- Subvenciones
    perform erp.loan_year_end(e, '2026-12-31');                        perform erp.case_mark(e, 13);   -- Financiación (13 y 14)
    perform erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'prepaid_expense', 'description', 'Seguro anual del taller',
      'pl_account_no', '62500001', 'cutoff_date', '2026-12-31', 'total_amount', 1200, 'coverage_start', '2026-10-01',
      'coverage_months', 12));                                        perform erp.case_mark(e, 15);   -- Ajustes de cierre
    perform erp.impair_receivable(jsonb_build_object('invoice_id', f_dud, 'impair_date', '2026-12-31'));   perform erp.case_mark(e, 16);
    perform erp.post_inventory(jsonb_build_object('company_id', e, 'count_date', '2026-12-31',
      'lines', '[{"account_no": "30000001", "final_value": 8000}]'::jsonb));                               perform erp.case_mark(e, 17);
    v_ret := erp.corporate_tax_prepare(e, 2026);                       -- Impuesto sobre Sociedades
    perform erp.corporate_tax_settings(v_ret, 'new_entity', false);
    perform erp.corporate_tax_calc(e, 2026);
    perform erp.corporate_tax_post(e, 2026);                           perform erp.case_mark(e, 18);
    perform erp.close_fiscal_year(e, 2026, true);                      perform erp.case_mark(e, 19);   -- Cierre del ejercicio
  end if;

  update erp.companies set case_key = p_case, case_mode = p_mode where id = e;
  return jsonb_build_object('company_id', e, 'case', p_case, 'mode', p_mode,
    'entries', (select count(*) from erp.journal_entries j where j.company_id = e and j.status = 'posted'));
end $$;

-- ---------------------------------------------------------------------
-- 4) Crear la empresa del caso y cargarlo (desde Inicio): el límite de empresas es el de siempre
-- ---------------------------------------------------------------------
create or replace function erp.create_case_company(p_case text default 'taller_atlantico', p_mode text default 'full')
returns jsonb language plpgsql set search_path = erp, public as $$
declare v_case erp.cases; v_name text; v_n int := 1; e uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to load a case'; end if;
  select * into v_case from erp.cases where key = p_case;
  if not found then raise exception 'Unknown case: %', p_case; end if;
  if p_mode is null or p_mode not in ('full', 'until_closing') then raise exception 'Invalid case mode: %', p_mode; end if;
  v_name := v_case.company_name;
  while exists (select 1 from erp.companies c join erp.company_users u on u.company_id = c.id and u.user_id = auth.uid()
                where c.name = v_name) loop
    v_n := v_n + 1; v_name := v_case.company_name || ' (' || v_n || ')';
  end loop;
  insert into erp.companies (name, industry, tax_territory, legal_form, control_mode, created_by)
  values (v_name, 'retail', v_case.tax_territory, v_case.legal_form, 'strict', auth.uid()) returning id into e;
  return erp.load_case(e, p_case, p_mode) || jsonb_build_object('name', v_name);
end $$;

-- ---------------------------------------------------------------------
-- 5) Cada operación del caso en la empresa: hecha o pendiente, con sus asientos
--    Las del cierre, si el caso se cargó «hasta el cierre», según el paso del asistente de cierre.
-- ---------------------------------------------------------------------
create or replace function erp.case_progress(p_company uuid)
returns table (n int, phase text, date_label text, date_label_en text, title text, title_en text, entry text,
               why text, why_en text, screen text, checklist_code text, status text, entries jsonb)
language plpgsql stable set search_path = erp, public as $$
declare v_case erp.cases; v_cl jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_case from erp.cases where key = (select case_key from erp.companies where id = p_company);
  if not found then raise exception 'No case loaded in this company'; end if;
  select jsonb_object_agg(k.code, k.status) into v_cl from erp.closing_checklist(p_company, v_case.year) k;
  return query
  select s.n, s.phase, s.date_label, s.date_label_en, s.title, s.title_en, s.entry, s.why, s.why_en, s.screen, s.checklist_code,
         case when exists (select 1 from erp.case_entries ce where ce.company_id = p_company and ce.n = s.n) then 'done'
              when s.n = 14 and exists (select 1 from erp.case_entries ce where ce.company_id = p_company and ce.n = 13) then 'done'
              when s.checklist_code is not null and v_cl->>s.checklist_code in ('done', 'na') then 'done'
              else 'pending' end,
         coalesce((select jsonb_agg(jsonb_build_object('entry_id', j.id, 'year', fy.year, 'entry_no', j.entry_no, 'date', j.posting_date,
                                                       'description', j.description) order by j.posting_date, j.entry_no)
                   from erp.case_entries ce join erp.journal_entries j on j.id = ce.entry_id
                   join erp.fiscal_years fy on fy.id = j.fiscal_year_id
                   where ce.company_id = p_company and ce.n = s.n), '[]'::jsonb)
  from erp.case_steps s where s.case_key = v_case.key
  order by s.n;
end $$;

-- ---------------------------------------------------------------------
-- 6) Comparar con el caso (versión de la 0066 con el estado de cada cifra)
--    pending: no coincide, pero el Impuesto sobre Sociedades del año aún no está contabilizado (falta el cierre)
-- ---------------------------------------------------------------------
drop function if exists erp.case_compare(uuid, text);
create or replace function erp.case_compare(p_company uuid, p_case text default null)
returns table (kind text, code text, expected numeric, actual numeric, difference numeric, ok boolean, status text, sort int)
language plpgsql stable set search_path = erp, public as $$
declare v_case erp.cases; v_ecpn jsonb; v_cit jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_case from erp.cases where key = coalesce(p_case, (select case_key from erp.companies where id = p_company));
  if not found then raise exception 'No case loaded in this company'; end if;
  v_ecpn := erp.equity_statement(p_company, v_case.year);
  select r.result into v_cit from erp.corporate_tax_returns r join erp.fiscal_years fy on fy.id = r.fiscal_year_id
  where r.company_id = p_company and fy.year = v_case.year and r.status = 'posted';
  return query
  with act as (
    select 'pyg' as k, s.code as c, s.amount as v from erp.financial_statement(p_company, v_case.year, 'pyg') s
    union all select 'balance', s.code, s.amount from erp.financial_statement(p_company, v_case.year, 'balance') s
    union all select 'cf_indirect', s.code, s.amount from erp.cash_flow_statement(p_company, v_case.year, 'indirect') s
    union all select 'cf_direct', s.code, s.amount from erp.cash_flow_statement(p_company, v_case.year, 'direct') s
    union all select 'tax_form', q || '.' || b.box, b.amount from generate_series(1, 4) q, erp.tax_form_boxes(p_company, v_case.year, q) b
    union all select 'withholding', q || '.' || w.form, sum(w.amount) from generate_series(1, 4) q, erp.withholding_summary(p_company, v_case.year, q) w
              where w.side = 'withheld' group by 1, 2)
  select y.kind, y.code, y.expected, y.actual, y.actual - y.expected, y.actual = y.expected,
         case when y.actual = y.expected then 'ok' when v_cit is null then 'pending' else 'diff' end, y.sort
  from (
    select x.kind, x.code, x.amount as expected, x.sort,
           coalesce(case x.kind when 'ecpn' then (v_ecpn #>> string_to_array(x.code, '.'))::numeric
                                when 'cit' then (v_cit ->> x.code)::numeric
                                else (select sum(a.v) from act a where a.k = x.kind and a.c = x.code) end, 0) as actual
    from erp.case_expected x where x.case_key = v_case.key) y
  order by y.sort;
end $$;

revoke execute on function erp.load_case(uuid, text, text), erp.create_case_company(text, text), erp.case_progress(uuid),
  erp.case_compare(uuid, text) from anon, public;
grant execute on function erp.load_case(uuid, text, text), erp.create_case_company(text, text), erp.case_progress(uuid),
  erp.case_compare(uuid, text) to authenticated;
