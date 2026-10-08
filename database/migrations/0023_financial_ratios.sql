-- =====================================================================
-- 0023 · FINANCIAL RATIOS · Ratios financieros (Modo auditor, parte 3)
-- ---------------------------------------------------------------------
-- Los ratios que un auditor o un analista calcula en Excel / Power BI, sacados del balance, la PyG (0016)
-- y el estado de flujos de efectivo (0022) del propio ERP:
--   liquidez · solvencia y endeudamiento · rentabilidad · actividad (periodos medios) · flujos de caja
-- Cada ratio guarda su fórmula, su interpretación y su zona de referencia (las de los manuales españoles:
-- Amat, Rivero, Garrido…). La referencia es ORIENTATIVA: depende del sector, y así se explica en pantalla.
-- Se calculan con los saldos de cierre (no con medias) para que cada ratio se pueda comprobar a mano con el balance.
-- =====================================================================

create table erp.ratio_defs (
  code        text primary key,
  grp         text not null check (grp in ('liquidity', 'solvency', 'profitability', 'activity', 'cash')),
  sort        int  not null,
  label       text not null,
  label_en    text not null,
  formula     text not null,
  formula_en  text not null,
  unit        text not null check (unit in ('ratio', 'pct', 'days', 'eur')),
  ref_min     numeric,              -- zona de referencia (orientativa); null = sin límite
  ref_max     numeric,
  help        text not null,
  help_en     text not null
);

insert into erp.ratio_defs (code, grp, sort, label, label_en, formula, formula_en, unit, ref_min, ref_max, help, help_en) values
-- ---------- LIQUIDEZ: ¿puede pagar lo que vence en menos de un año? ----------
('WC', 'liquidity', 10, 'Fondo de maniobra', 'Working capital',
 'Activo corriente − Pasivo corriente', 'Current assets − Current liabilities', 'eur', 0, null,
 'Parte del activo corriente financiada con recursos a largo plazo. Si es negativo, parte del inmovilizado se financia con deudas a corto: riesgo de no poder pagar (salvo negocios que cobran al contado y pagan a plazo, como la gran distribución).',
 'Part of current assets financed with long-term funds. If negative, fixed assets are partly financed with short-term debt: risk of not being able to pay (except businesses that collect cash and pay later, like large retailers).'),
('CR', 'liquidity', 20, 'Liquidez general', 'Current ratio',
 'Activo corriente / Pasivo corriente', 'Current assets / Current liabilities', 'ratio', 1.5, 2,
 'Euros de activo corriente por cada euro de deuda a corto. Por debajo de 1,5 puede haber tensiones de pago; muy por encima de 2, recursos ociosos (existencias o tesorería sin rendimiento).',
 'Euros of current assets per euro of short-term debt. Below 1.5 there may be payment stress; well above 2, idle resources (stock or cash earning nothing).'),
('QR', 'liquidity', 30, 'Prueba ácida', 'Quick ratio (acid test)',
 '(Activo corriente − Existencias) / Pasivo corriente', '(Current assets − Inventories) / Current liabilities', 'ratio', 0.75, 1,
 'Como la liquidez general pero sin las existencias, que son lo más lento de convertir en dinero.',
 'Like the current ratio but without inventories, the slowest asset to turn into cash.'),
('CASH', 'liquidity', 40, 'Disponibilidad (tesorería inmediata)', 'Cash ratio',
 'Efectivo / Pasivo corriente', 'Cash / Current liabilities', 'ratio', 0.1, 0.3,
 'Qué parte de la deuda a corto se podría pagar hoy con lo que hay en caja y bancos.',
 'Share of short-term debt that could be paid today with cash in hand and at banks.'),
-- ---------- SOLVENCIA Y ENDEUDAMIENTO: ¿cómo se financia y puede devolver lo que debe? ----------
('DEBT', 'solvency', 10, 'Endeudamiento', 'Debt ratio',
 'Pasivo (no corriente + corriente) / Patrimonio neto y pasivo', 'Liabilities / Total equity and liabilities', 'ratio', 0.4, 0.6,
 'Parte del activo financiada con deudas. Por encima de 0,6 la empresa pierde autonomía y es más arriesgada para bancos y proveedores.',
 'Share of assets financed with debt. Above 0.6 the company loses independence and is riskier for banks and suppliers.'),
('AUT', 'solvency', 20, 'Autonomía', 'Equity to debt',
 'Patrimonio neto / Pasivo', 'Equity / Liabilities', 'ratio', 0.7, 1.5,
 'Euros de fondos propios por cada euro de deuda. Es la otra cara del endeudamiento.',
 'Euros of equity per euro of debt. The other side of the debt ratio.'),
('SOLV', 'solvency', 30, 'Garantía (solvencia total)', 'Solvency ratio',
 'Activo total / Pasivo', 'Total assets / Liabilities', 'ratio', 1.5, null,
 'Si se vendiera todo el activo, cuántas veces se cubrirían las deudas. Por debajo de 1 hay quiebra técnica (patrimonio neto negativo).',
 'If all assets were sold, how many times debts would be covered. Below 1 means technical bankruptcy (negative equity).'),
('DQ', 'solvency', 40, 'Calidad de la deuda', 'Debt quality',
 'Pasivo corriente / Pasivo', 'Current liabilities / Liabilities', 'ratio', null, 0.5,
 'Qué parte de la deuda vence en menos de un año. Cuanto más bajo, mejor: la deuda a largo da tiempo para generar el dinero.',
 'Share of debt due within a year. Lower is better: long-term debt gives time to generate the cash.'),
('FINC', 'solvency', 50, 'Gastos financieros sobre ventas', 'Finance costs to sales',
 'Gastos financieros / Cifra de negocios', 'Finance costs / Revenue', 'pct', null, 0.04,
 'Cuánto de cada euro vendido se va en intereses. Por encima del 4-5 % la deuda empieza a ser una carga pesada.',
 'How much of each euro sold goes on interest. Above 4-5 % debt starts to be a heavy burden.'),
-- ---------- RENTABILIDAD: ¿gana dinero con lo que tiene? ----------
('ROA', 'profitability', 10, 'Rentabilidad económica (ROA)', 'Return on assets (ROA)',
 'Resultado de explotación / Activo total', 'Operating profit / Total assets', 'pct', null, null,
 'Lo que rinde el activo, sin importar cómo se financia. Si es mayor que el coste de la deuda, endeudarse aumenta la rentabilidad del socio (apalancamiento positivo).',
 'Return on assets regardless of financing. If higher than the cost of debt, borrowing increases the shareholders'' return (positive leverage).'),
('ROE', 'profitability', 20, 'Rentabilidad financiera (ROE)', 'Return on equity (ROE)',
 'Resultado del ejercicio / Patrimonio neto', 'Profit for the year / Equity', 'pct', null, null,
 'Lo que gana el socio por cada euro que tiene invertido. Se compara con lo que daría una inversión sin riesgo.',
 'What shareholders earn per euro invested. Compare it with a risk-free investment.'),
('OPM', 'profitability', 30, 'Margen de explotación', 'Operating margin',
 'Resultado de explotación / Cifra de negocios', 'Operating profit / Revenue', 'pct', null, null,
 'Céntimos de beneficio del negocio por cada euro vendido, antes de intereses e impuestos.',
 'Cents of business profit per euro sold, before interest and taxes.'),
('NPM', 'profitability', 40, 'Margen neto', 'Net margin',
 'Resultado del ejercicio / Cifra de negocios', 'Profit for the year / Revenue', 'pct', null, null,
 'Céntimos que quedan para el socio por cada euro vendido.', 'Cents left for shareholders per euro sold.'),
('ATO', 'profitability', 50, 'Rotación del activo', 'Asset turnover',
 'Cifra de negocios / Activo total', 'Revenue / Total assets', 'ratio', null, null,
 'Euros vendidos por cada euro de activo. ROA ≈ margen × rotación: se gana vendiendo caro o vendiendo mucho.',
 'Euros sold per euro of assets. ROA ≈ margin × turnover: profit comes from high prices or high volume.'),
('EBITDA', 'profitability', 60, 'EBITDA', 'EBITDA',
 'Resultado de explotación + Amortizaciones', 'Operating profit + Depreciation and amortisation', 'eur', null, null,
 'Resultado del negocio antes de amortizaciones: una aproximación a lo que genera la explotación. No es caja (no recoge los cobros y pagos pendientes): compárelo con el flujo de explotación.',
 'Business profit before depreciation: an approximation of what operations generate. It is not cash (it ignores pending receipts and payments): compare it with operating cash flow.'),
-- ---------- ACTIVIDAD: ¿cuánto tarda en cobrar, pagar y vender? ----------
('DSO', 'activity', 10, 'Periodo medio de cobro', 'Days sales outstanding',
 'Clientes / Cifra de negocios × 365', 'Trade receivables / Revenue × 365', 'days', null, 60,
 'Días que tarda en cobrar. Los clientes incluyen el IVA / IGIC y la cifra de negocios no, así que sale algo alto. La Ley 15/2010 fija 60 días como plazo máximo entre empresas.',
 'Days to collect. Receivables include VAT / IGIC and revenue does not, so it is slightly overstated. Spanish Law 15/2010 sets 60 days as the maximum between businesses.'),
('DPO', 'activity', 20, 'Periodo medio de pago', 'Days payables outstanding',
 'Proveedores / Aprovisionamientos × 365', 'Suppliers / Procurements × 365', 'days', null, 60,
 'Días que tarda en pagar a los proveedores de mercaderías y materias (cuenta 400 frente a los aprovisionamientos de la PyG). Es el dato de la memoria sobre aplazamientos de pago (máximo legal 60 días). Los acreedores por servicios (410) no entran.',
 'Days to pay suppliers of goods and materials (account 400 against procurements in the P&L). It is the payment-terms disclosure in the notes (legal maximum 60 days). Service creditors (410) are not included.'),
('DIO', 'activity', 30, 'Días de existencias', 'Days inventory outstanding',
 'Existencias / Aprovisionamientos × 365', 'Inventories / Procurements × 365', 'days', null, null,
 'Días que la mercancía está en el almacén. Junto con el cobro y el pago da el ciclo de caja: existencias + cobro − pago.',
 'Days stock sits in the warehouse. With collection and payment days it gives the cash cycle: inventory + collection − payment.'),
-- ---------- FLUJOS DE CAJA: ¿el beneficio se convierte en dinero? ----------
('CFO', 'cash', 10, 'Flujo de explotación', 'Operating cash flow',
 'Total A) del estado de flujos de efectivo', 'Total A) of the cash flow statement', 'eur', 0, null,
 'Dinero que genera el negocio en el año. Si es negativo varios años seguidos, la empresa vive de los bancos o de los socios.',
 'Cash generated by the business in the year. If negative for several years, the company lives on banks or shareholders.'),
('CFQ', 'cash', 20, 'Calidad del resultado', 'Quality of earnings',
 'Flujo de explotación / Resultado del ejercicio', 'Operating cash flow / Profit for the year', 'ratio', 1, null,
 'Euros de caja por cada euro de beneficio. Por debajo de 1, el beneficio se queda en clientes o existencias en vez de llegar al banco.',
 'Euros of cash per euro of profit. Below 1, profit is stuck in receivables or inventory instead of reaching the bank.'),
('CFD', 'cash', 30, 'Cobertura de la deuda a corto con caja', 'Operating cash flow to current liabilities',
 'Flujo de explotación / Pasivo corriente', 'Operating cash flow / Current liabilities', 'ratio', null, null,
 'Qué parte de la deuda a corto se pagaría con el dinero que genera el negocio en un año.',
 'Share of short-term debt that a year of operating cash would pay.');

alter table erp.ratio_defs enable row level security;
create policy read on erp.ratio_defs for select to authenticated using (true);
revoke all on erp.ratio_defs from anon, public;
grant select on erp.ratio_defs to authenticated;

-- ---------------------------------------------------------------------
-- Numerador y denominador de cada ratio en un año (interna: sin RLS fila a fila, no se expone)
-- ---------------------------------------------------------------------
create or replace function erp.ratio_parts(p_company uuid, p_year int)
returns table (code text, num numeric, den numeric)
language plpgsql stable security definer set search_path = erp, public as $$
declare
  b    jsonb;      -- partidas del balance
  p    jsonb;      -- partidas de la PyG
  cfo  numeric;    -- total A) del estado de flujos
  ac numeric; pc numeric; pnc numeric; pn numeric; act numeric; inv numeric; cash numeric;
  cust numeric; supp numeric; sales numeric; procur numeric; amort numeric; fin numeric; ebit numeric; profit numeric;
begin
  if not exists (select 1 from erp.fiscal_years where company_id = p_company and year = p_year) then return; end if;
  select jsonb_object_agg(a.code, a.amount) into b from erp.fs_amounts(p_company, p_year, 'balance') a;
  select jsonb_object_agg(a.code, a.amount) into p from erp.fs_amounts(p_company, p_year, 'pyg') a;
  select coalesce(sum(d.amount), 0) into cfo from erp.cf_indirect_detail(p_company, p_year) d where d.line_code like 'IA%';

  ac := (b->>'AC')::numeric;      pc := (b->>'PC')::numeric;   pnc := (b->>'PNC')::numeric;
  pn := (b->>'PN')::numeric;      act := (b->>'ACT')::numeric; inv := (b->>'AC.I')::numeric;
  cash := (b->>'AC.VI')::numeric; cust := (b->>'AC.II.1')::numeric; supp := (b->>'PC.IV.1')::numeric;
  -- en la PyG los gastos van en negativo: se cambian de signo para dividir
  sales := (p->>'P1')::numeric;   procur := -(p->>'P4')::numeric;  amort := -(p->>'P8')::numeric;
  fin := -(p->>'P14')::numeric;   ebit := (p->>'PA')::numeric;     profit := (p->>'PD')::numeric;

  return query values
    ('WC', ac - pc, null::numeric), ('CR', ac, pc), ('QR', ac - inv, pc), ('CASH', cash, pc),
    ('DEBT', pnc + pc, pn + pnc + pc), ('AUT', pn, pnc + pc), ('SOLV', act, pnc + pc), ('DQ', pc, pnc + pc),
    ('FINC', fin, sales),
    ('ROA', ebit, act), ('ROE', profit, pn), ('OPM', ebit, sales), ('NPM', profit, sales), ('ATO', sales, act),
    ('EBITDA', ebit + amort, null),
    ('DSO', cust * 365, sales), ('DPO', supp * 365, procur), ('DIO', inv * 365, procur),
    ('CFO', cfo, null), ('CFQ', cfo, profit), ('CFD', cfo, pc);
end $$;

-- ---------------------------------------------------------------------
-- RATIOS de una empresa en un año, con el año anterior y la valoración frente a la zona de referencia
--   status: ok · low · high · null (sin referencia o sin dato)
--   Sin denominador (división por cero) el ratio no tiene sentido: value = null
-- ---------------------------------------------------------------------
create or replace function erp.financial_ratios(p_company uuid, p_year int)
returns table (code text, grp text, sort int, label text, label_en text, formula text, formula_en text, unit text,
               ref_min numeric, ref_max numeric, help text, help_en text,
               num numeric, den numeric, value numeric, value_prev numeric, status text)
language plpgsql stable security definer set search_path = erp, public as $$
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  return query
  with cur as (select * from erp.ratio_parts(p_company, p_year)),
       prev as (select * from erp.ratio_parts(p_company, p_year - 1)),
       v as (
         select d.code,
                c.num, c.den,
                case when c.den is null then c.num when c.den <> 0 then round(c.num / c.den, 4) end as value,
                case when pr.den is null then pr.num when pr.den <> 0 then round(pr.num / pr.den, 4) end as value_prev
         from erp.ratio_defs d
         left join cur c on c.code = d.code
         left join prev pr on pr.code = d.code)
  select d.code, d.grp, d.sort, d.label, d.label_en, d.formula, d.formula_en, d.unit, d.ref_min, d.ref_max,
         d.help, d.help_en, v.num, v.den, v.value, v.value_prev,
         case when v.value is null or (d.ref_min is null and d.ref_max is null) then null
              when v.value < d.ref_min then 'low'
              when v.value > d.ref_max then 'high'
              else 'ok' end
  from erp.ratio_defs d
  join v on v.code = d.code
  order by array_position(array['liquidity', 'solvency', 'profitability', 'activity', 'cash'], d.grp), d.sort;
end $$;

revoke execute on function erp.ratio_parts(uuid, int), erp.financial_ratios(uuid, int) from anon, public;
grant execute on function erp.financial_ratios(uuid, int) to authenticated;
