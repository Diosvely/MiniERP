-- =====================================================================
-- 0016 · FINANCIAL STATEMENTS · Balance de situación y Cuenta de Pérdidas y Ganancias
-- ---------------------------------------------------------------------
-- Basado en los modelos de cuentas anuales para PYMES del PGC (RD 1515/2007). Proyecto de estudio.
--
--   erp.fs_lines    → estructura de cada estado: partidas, subtotales y su jerarquía (ES/EN)
--   erp.fs_mapping  → prefijo de cuenta → partida, con DOS destinos según el saldo:
--                     saldo deudor → partida de activo · saldo acreedor → partida de pasivo
--                     (ej. 572 Bancos: deudor → Efectivo · acreedor → Deudas con entidades de crédito)
--   erp.financial_statement(empresa, año, 'balance' | 'pyg', fecha)  → importes del año y del anterior
--   erp.fs_line_accounts(empresa, año, estado, partida, fecha)        → cuentas que forman una partida
--
-- REGLAS:
--   · Se clasifica cada SUBCUENTA por su propio saldo (sin compensar): un cliente con saldo acreedor
--     va al pasivo aunque los demás clientes sean deudores. Así lo exige el PGC (no compensación).
--   · Los grupos 6 y 7 aún sin regularizar se suman en "VII. Resultado del ejercicio": el balance cuadra
--     en cualquier fecha, igual que el balance provisional de BC o de A3.
--   · Los estados SOLO leen apuntes contabilizados y el plan de cuentas: valen igual para asientos manuales,
--     facturas, liquidaciones o diarios IMPORTADOS de otro ERP.
-- =====================================================================

create table erp.fs_lines (
  statement   text not null check (statement in ('balance', 'pyg')),
  code        text not null,
  parent      text,                       -- partida en la que se suma
  sort        int  not null,
  label       text not null,
  label_en    text not null,
  side        text not null check (side in ('debit', 'credit')),   -- signo: activo/gasto (debit) · PN, pasivo, PyG (credit)
  is_total    boolean not null default false,                       -- fila de total o subtotal (se pinta en negrita)
  primary key (statement, code)
);

create table erp.fs_mapping (
  statement    text not null check (statement in ('balance', 'pyg')),
  prefix       text not null,
  debit_line   text not null,   -- partida si la subcuenta tiene saldo DEUDOR
  credit_line  text not null,   -- partida si la subcuenta tiene saldo ACREEDOR
  primary key (statement, prefix)
);

-- ---------------------------------------------------------------------
-- BALANCE · estructura (modelo PYMES)
-- ---------------------------------------------------------------------
insert into erp.fs_lines (statement, code, parent, sort, label, label_en, side, is_total) values
('balance', 'ACT',       null,      100, 'TOTAL ACTIVO', 'TOTAL ASSETS', 'debit', true),
('balance', 'ANC',       'ACT',     110, 'A) ACTIVO NO CORRIENTE', 'A) NON-CURRENT ASSETS', 'debit', true),
('balance', 'ANC.I',     'ANC',     111, 'I. Inmovilizado intangible', 'I. Intangible assets', 'debit', false),
('balance', 'ANC.II',    'ANC',     112, 'II. Inmovilizado material', 'II. Property, plant and equipment', 'debit', false),
('balance', 'ANC.III',   'ANC',     113, 'III. Inversiones inmobiliarias', 'III. Investment property', 'debit', false),
('balance', 'ANC.IV',    'ANC',     114, 'IV. Inversiones en empresas del grupo y asociadas a largo plazo', 'IV. Long-term investments in group companies and associates', 'debit', false),
('balance', 'ANC.V',     'ANC',     115, 'V. Inversiones financieras a largo plazo', 'V. Long-term financial investments', 'debit', false),
('balance', 'ANC.VI',    'ANC',     116, 'VI. Activos por impuesto diferido', 'VI. Deferred tax assets', 'debit', false),
('balance', 'AC',        'ACT',     120, 'B) ACTIVO CORRIENTE', 'B) CURRENT ASSETS', 'debit', true),
('balance', 'AC.I',      'AC',      121, 'I. Existencias', 'I. Inventories', 'debit', false),
('balance', 'AC.II',     'AC',      122, 'II. Deudores comerciales y otras cuentas a cobrar', 'II. Trade and other receivables', 'debit', false),
('balance', 'AC.II.1',   'AC.II',   123, '1. Clientes por ventas y prestaciones de servicios', '1. Trade receivables', 'debit', false),
('balance', 'AC.II.2',   'AC.II',   124, '2. Accionistas (socios) por desembolsos exigidos', '2. Called-up capital not paid', 'debit', false),
('balance', 'AC.II.3',   'AC.II',   125, '3. Otros deudores', '3. Other receivables', 'debit', false),
('balance', 'AC.III',    'AC',      126, 'III. Inversiones en empresas del grupo y asociadas a corto plazo', 'III. Short-term investments in group companies and associates', 'debit', false),
('balance', 'AC.IV',     'AC',      127, 'IV. Inversiones financieras a corto plazo', 'IV. Short-term financial investments', 'debit', false),
('balance', 'AC.V',      'AC',      128, 'V. Periodificaciones a corto plazo', 'V. Short-term prepayments', 'debit', false),
('balance', 'AC.VI',     'AC',      129, 'VI. Efectivo y otros activos líquidos equivalentes', 'VI. Cash and cash equivalents', 'debit', false),

('balance', 'PNP',       null,      200, 'TOTAL PATRIMONIO NETO Y PASIVO', 'TOTAL EQUITY AND LIABILITIES', 'credit', true),
('balance', 'PN',        'PNP',     210, 'A) PATRIMONIO NETO', 'A) EQUITY', 'credit', true),
('balance', 'PN.A1',     'PN',      211, 'A-1) Fondos propios', 'A-1) Shareholders'' equity', 'credit', true),
('balance', 'PN.A1.I',   'PN.A1',   212, 'I. Capital', 'I. Capital', 'credit', false),
('balance', 'PN.A1.II',  'PN.A1',   213, 'II. Prima de emisión', 'II. Share premium', 'credit', false),
('balance', 'PN.A1.III', 'PN.A1',   214, 'III. Reservas', 'III. Reserves', 'credit', false),
('balance', 'PN.A1.IV',  'PN.A1',   215, 'IV. (Acciones y participaciones en patrimonio propias)', 'IV. (Treasury shares)', 'credit', false),
('balance', 'PN.A1.V',   'PN.A1',   216, 'V. Resultados de ejercicios anteriores', 'V. Prior years'' results', 'credit', false),
('balance', 'PN.A1.VI',  'PN.A1',   217, 'VI. Otras aportaciones de socios', 'VI. Other shareholder contributions', 'credit', false),
('balance', 'PN.A1.VII', 'PN.A1',   218, 'VII. Resultado del ejercicio', 'VII. Profit (loss) for the year', 'credit', false),
('balance', 'PN.A1.VIII','PN.A1',   219, 'VIII. (Dividendo a cuenta)', 'VIII. (Interim dividend)', 'credit', false),
('balance', 'PN.A2',     'PN',      220, 'A-2) Subvenciones, donaciones y legados recibidos', 'A-2) Grants, donations and bequests received', 'credit', false),
('balance', 'PNC',       'PNP',     230, 'B) PASIVO NO CORRIENTE', 'B) NON-CURRENT LIABILITIES', 'credit', true),
('balance', 'PNC.I',     'PNC',     231, 'I. Provisiones a largo plazo', 'I. Long-term provisions', 'credit', false),
('balance', 'PNC.II',    'PNC',     232, 'II. Deudas a largo plazo', 'II. Long-term debts', 'credit', false),
('balance', 'PNC.II.1',  'PNC.II',  233, '1. Deudas con entidades de crédito', '1. Bank borrowings', 'credit', false),
('balance', 'PNC.II.2',  'PNC.II',  234, '2. Acreedores por arrendamiento financiero', '2. Finance lease payables', 'credit', false),
('balance', 'PNC.II.3',  'PNC.II',  235, '3. Otras deudas a largo plazo', '3. Other long-term debts', 'credit', false),
('balance', 'PNC.III',   'PNC',     236, 'III. Deudas con empresas del grupo y asociadas a largo plazo', 'III. Long-term debts with group companies and associates', 'credit', false),
('balance', 'PNC.IV',    'PNC',     237, 'IV. Pasivos por impuesto diferido', 'IV. Deferred tax liabilities', 'credit', false),
('balance', 'PNC.V',     'PNC',     238, 'V. Periodificaciones a largo plazo', 'V. Long-term accruals', 'credit', false),
('balance', 'PC',        'PNP',     240, 'C) PASIVO CORRIENTE', 'C) CURRENT LIABILITIES', 'credit', true),
('balance', 'PC.I',      'PC',      241, 'I. Provisiones a corto plazo', 'I. Short-term provisions', 'credit', false),
('balance', 'PC.II',     'PC',      242, 'II. Deudas a corto plazo', 'II. Short-term debts', 'credit', false),
('balance', 'PC.II.1',   'PC.II',   243, '1. Deudas con entidades de crédito', '1. Bank borrowings', 'credit', false),
('balance', 'PC.II.2',   'PC.II',   244, '2. Acreedores por arrendamiento financiero', '2. Finance lease payables', 'credit', false),
('balance', 'PC.II.3',   'PC.II',   245, '3. Otras deudas a corto plazo', '3. Other short-term debts', 'credit', false),
('balance', 'PC.III',    'PC',      246, 'III. Deudas con empresas del grupo y asociadas a corto plazo', 'III. Short-term debts with group companies and associates', 'credit', false),
('balance', 'PC.IV',     'PC',      247, 'IV. Acreedores comerciales y otras cuentas a pagar', 'IV. Trade and other payables', 'credit', false),
('balance', 'PC.IV.1',   'PC.IV',   248, '1. Proveedores', '1. Suppliers', 'credit', false),
('balance', 'PC.IV.2',   'PC.IV',   249, '2. Otros acreedores', '2. Other payables', 'credit', false),
('balance', 'PC.V',      'PC',      250, 'V. Periodificaciones a corto plazo', 'V. Short-term accruals', 'credit', false);

-- ---------------------------------------------------------------------
-- PÉRDIDAS Y GANANCIAS · estructura (modelo PYMES). Importes: ingresos +, gastos −
-- ---------------------------------------------------------------------
insert into erp.fs_lines (statement, code, parent, sort, label, label_en, side, is_total) values
('pyg', 'P1',  'PA', 10,  '1. Importe neto de la cifra de negocios', '1. Revenue', 'credit', false),
('pyg', 'P2',  'PA', 20,  '2. Variación de existencias de productos terminados y en curso de fabricación', '2. Changes in inventories of finished goods and work in progress', 'credit', false),
('pyg', 'P3',  'PA', 30,  '3. Trabajos realizados por la empresa para su activo', '3. Work performed by the company for its assets', 'credit', false),
('pyg', 'P4',  'PA', 40,  '4. Aprovisionamientos', '4. Procurements', 'credit', false),
('pyg', 'P5',  'PA', 50,  '5. Otros ingresos de explotación', '5. Other operating income', 'credit', false),
('pyg', 'P6',  'PA', 60,  '6. Gastos de personal', '6. Personnel expenses', 'credit', false),
('pyg', 'P7',  'PA', 70,  '7. Otros gastos de explotación', '7. Other operating expenses', 'credit', false),
('pyg', 'P8',  'PA', 80,  '8. Amortización del inmovilizado', '8. Depreciation and amortisation', 'credit', false),
('pyg', 'P9',  'PA', 90,  '9. Imputación de subvenciones de inmovilizado no financiero y otras', '9. Non-financial asset grants recognised', 'credit', false),
('pyg', 'P10', 'PA', 100, '10. Excesos de provisiones', '10. Excess provisions', 'credit', false),
('pyg', 'P11', 'PA', 110, '11. Deterioro y resultado por enajenaciones del inmovilizado', '11. Impairment and gains (losses) on disposal of fixed assets', 'credit', false),
('pyg', 'P12', 'PA', 120, '12. Otros resultados', '12. Other results', 'credit', false),
('pyg', 'PA',  'PC', 130, 'A) RESULTADO DE EXPLOTACIÓN (1 a 12)', 'A) OPERATING PROFIT (LOSS) (1 to 12)', 'credit', true),
('pyg', 'P13', 'PB', 140, '13. Ingresos financieros', '13. Finance income', 'credit', false),
('pyg', 'P14', 'PB', 150, '14. Gastos financieros', '14. Finance costs', 'credit', false),
('pyg', 'P15', 'PB', 160, '15. Variación de valor razonable en instrumentos financieros', '15. Change in fair value of financial instruments', 'credit', false),
('pyg', 'P16', 'PB', 170, '16. Diferencias de cambio', '16. Exchange differences', 'credit', false),
('pyg', 'P17', 'PB', 180, '17. Deterioro y resultado por enajenaciones de instrumentos financieros', '17. Impairment and gains (losses) on disposal of financial instruments', 'credit', false),
('pyg', 'PB',  'PC', 190, 'B) RESULTADO FINANCIERO (13 a 17)', 'B) FINANCIAL RESULT (13 to 17)', 'credit', true),
('pyg', 'PC',  'PD', 200, 'C) RESULTADO ANTES DE IMPUESTOS (A + B)', 'C) PROFIT (LOSS) BEFORE TAX (A + B)', 'credit', true),
('pyg', 'P18', 'PD', 210, '18. Impuestos sobre beneficios', '18. Income tax', 'credit', false),
('pyg', 'PD',  null, 220, 'D) RESULTADO DEL EJERCICIO (C + 18)', 'D) PROFIT (LOSS) FOR THE YEAR (C + 18)', 'credit', true);

-- ---------------------------------------------------------------------
-- BALANCE · clasificación de cuentas (prefijo más largo). Primero el grupo, luego los casos concretos.
-- ---------------------------------------------------------------------
insert into erp.fs_mapping (statement, prefix, debit_line, credit_line) values
-- Grupo 1 · Financiación básica
('balance','1',    'PNC.II.3','PNC.II.3'),
('balance','10',   'PN.A1.I','PN.A1.I'),          -- capital (1030/1040 no exigido: resta)
('balance','108',  'PN.A1.IV','PN.A1.IV'), ('balance','109','PN.A1.IV','PN.A1.IV'),
('balance','11',   'PN.A1.III','PN.A1.III'), ('balance','110','PN.A1.II','PN.A1.II'), ('balance','118','PN.A1.VI','PN.A1.VI'),
('balance','12',   'PN.A1.V','PN.A1.V'), ('balance','129','PN.A1.VII','PN.A1.VII'),
('balance','13',   'PN.A2','PN.A2'),
('balance','14',   'PNC.I','PNC.I'),
('balance','16',   'PNC.III','PNC.III'), ('balance','1605','PNC.II.1','PNC.II.1'),
('balance','1615', 'PNC.II.3','PNC.II.3'), ('balance','1625','PNC.II.2','PNC.II.2'), ('balance','1635','PNC.II.3','PNC.II.3'),
('balance','170',  'PNC.II.1','PNC.II.1'), ('balance','174','PNC.II.2','PNC.II.2'),
('balance','181',  'PNC.V','PNC.V'),
('balance','19',   'PC.II.3','PC.II.3'),
-- Grupo 2 · Activo no corriente (amortizaciones y deterioros restan dentro de su partida)
('balance','2',    'ANC.II','ANC.II'),
('balance','20',   'ANC.I','ANC.I'), ('balance','21','ANC.II','ANC.II'), ('balance','22','ANC.III','ANC.III'),
('balance','23',   'ANC.II','ANC.II'), ('balance','24','ANC.IV','ANC.IV'), ('balance','25','ANC.V','ANC.V'),
('balance','26',   'ANC.V','ANC.V'),
('balance','2405', 'ANC.V','ANC.V'), ('balance','2415','ANC.V','ANC.V'), ('balance','2425','ANC.V','ANC.V'),
('balance','280',  'ANC.I','ANC.I'), ('balance','281','ANC.II','ANC.II'), ('balance','282','ANC.III','ANC.III'),
('balance','290',  'ANC.I','ANC.I'), ('balance','291','ANC.II','ANC.II'), ('balance','292','ANC.III','ANC.III'),
('balance','293',  'ANC.IV','ANC.IV'), ('balance','294','ANC.IV','ANC.IV'), ('balance','295','ANC.IV','ANC.IV'),
('balance','296',  'ANC.V','ANC.V'), ('balance','297','ANC.V','ANC.V'), ('balance','298','ANC.V','ANC.V'),
-- Grupo 3 · Existencias
('balance','3',    'AC.I','AC.I'),
-- Grupo 4 · Acreedores y deudores comerciales: el SIGNO de cada subcuenta decide activo o pasivo
('balance','40',   'AC.I','PC.IV.1'),             -- proveedor deudor = anticipo (407, en Existencias)
('balance','41',   'AC.II.3','PC.IV.2'),          -- acreedor deudor → otros deudores
('balance','43',   'AC.II.1','PC.IV.2'),          -- cliente acreedor = anticipo (438) → otros acreedores
('balance','44',   'AC.II.3','PC.IV.2'),
('balance','46',   'AC.II.3','PC.IV.2'),
('balance','47',   'AC.II.3','PC.IV.2'),          -- HP deudora / acreedora (IVA, IGIC, retenciones…)
('balance','474',  'ANC.VI','ANC.VI'), ('balance','479','PNC.IV','PNC.IV'),
('balance','48',   'AC.V','PC.V'),
('balance','49',   'AC.II.1','AC.II.1'),          -- deterioro de clientes: resta
('balance','499',  'PC.I','PC.I'),
-- Grupo 5 · Cuentas financieras
('balance','5',    'AC.IV','PC.II.3'),
('balance','51',   'AC.III','PC.III'), ('balance','5105','AC.IV','PC.II.1'), ('balance','5125','AC.IV','PC.II.2'),
('balance','520',  'AC.IV','PC.II.1'), ('balance','524','AC.IV','PC.II.2'), ('balance','527','AC.IV','PC.II.1'),
('balance','529',  'PC.I','PC.I'),
('balance','53',   'AC.III','PC.III'),
('balance','557',  'PN.A1.VIII','PN.A1.VIII'), ('balance','5580','AC.II.2','AC.II.2'),
('balance','567',  'AC.V','PC.V'), ('balance','568','AC.V','PC.V'),
('balance','57',   'AC.VI','PC.II.1'),            -- banco en descubierto → deudas con entidades de crédito
('balance','59',   'AC.IV','AC.IV'),
-- Grupos 6 y 7 · resultado aún sin regularizar
('balance','6',    'PN.A1.VII','PN.A1.VII'), ('balance','7','PN.A1.VII','PN.A1.VII');

-- ---------------------------------------------------------------------
-- PYG · clasificación de cuentas de los grupos 6 y 7
-- ---------------------------------------------------------------------
insert into erp.fs_mapping (statement, prefix, debit_line, credit_line)
select 'pyg', p, l, l from (values
 ('6','P7'), ('7','P5'),
 ('700','P1'), ('701','P1'), ('702','P1'), ('703','P1'), ('704','P1'), ('705','P1'), ('706','P1'), ('708','P1'), ('709','P1'),
 ('71','P2'), ('6930','P2'), ('7930','P2'),
 ('73','P3'),
 ('60','P4'), ('61','P4'), ('6931','P4'), ('6932','P4'), ('6933','P4'), ('7931','P4'), ('7932','P4'), ('7933','P4'),
 ('740','P5'), ('747','P5'), ('75','P5'),
 ('64','P6'), ('7950','P6'), ('7957','P6'),
 ('62','P7'), ('63','P7'), ('65','P7'), ('694','P7'), ('695','P7'), ('794','P7'), ('7954','P7'),
 ('630','P18'), ('633','P18'), ('638','P18'),
 ('68','P8'),
 ('746','P9'),
 ('795','P10'),
 ('67','P11'), ('69','P11'), ('77','P11'), ('79','P10'), ('790','P11'), ('791','P11'), ('792','P11'),
 ('678','P12'), ('778','P12'),
 ('76','P13'),
 ('66','P14'),
 ('663','P15'), ('763','P15'),
 ('668','P16'), ('768','P16'),
 ('666','P17'), ('667','P17'), ('673','P17'), ('675','P17'), ('696','P17'), ('697','P17'), ('698','P17'), ('699','P17'),
 ('766','P17'), ('773','P17'), ('775','P17'), ('796','P17'), ('797','P17'), ('798','P17'), ('799','P17')
) as x(p, l);

-- Control de coherencia del catálogo: toda partida de destino existe
do $$ begin
  if exists (select 1 from erp.fs_mapping m
             where not exists (select 1 from erp.fs_lines l where l.statement = m.statement and l.code = m.debit_line)
                or not exists (select 1 from erp.fs_lines l where l.statement = m.statement and l.code = m.credit_line)) then
    raise exception 'fs_mapping points to a missing fs_lines code';
  end if;
end $$;

alter table erp.fs_lines enable row level security;
alter table erp.fs_mapping enable row level security;
create policy read on erp.fs_lines for select to authenticated using (true);
create policy read on erp.fs_mapping for select to authenticated using (true);
revoke all on erp.fs_lines, erp.fs_mapping from anon, public;
grant select on erp.fs_lines, erp.fs_mapping to authenticated;

-- ---------------------------------------------------------------------
-- Saldos de cada subcuenta clasificados en su partida
-- ---------------------------------------------------------------------
create or replace function erp.fs_classified_accounts(p_company uuid, p_year int, p_statement text, p_to_date date default null)
returns table (account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
language sql stable as $$
  with acc as (
    select g.account_no, g.name, g.name_en, sum(l.debit - l.credit) as bal
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
    join erp.fiscal_years fy   on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g     on g.id = l.gl_account_id
    where e.company_id = p_company
      and (p_to_date is null or e.posting_date <= p_to_date)
      -- en la PyG solo cuentan los grupos 6 y 7
      and (p_statement = 'balance' or left(g.account_no, 1) in ('6', '7'))
    group by g.account_no, g.name, g.name_en
    having sum(l.debit - l.credit) <> 0
  )
  select a.account_no, a.name, a.name_en, a.bal,
         m.line,
         a.bal * case fl.side when 'debit' then 1 else -1 end
  from acc a
  cross join lateral (
    select case when a.bal >= 0 then fm.debit_line else fm.credit_line end as line
    from erp.fs_mapping fm
    where fm.statement = p_statement and a.account_no like fm.prefix || '%'
    order by length(fm.prefix) desc limit 1) m
  join erp.fs_lines fl on fl.statement = p_statement and fl.code = m.line;
$$;

-- Importe de cada partida (incluidos subtotales, sumando hacia arriba en la jerarquía)
create or replace function erp.fs_amounts(p_company uuid, p_year int, p_statement text, p_to_date date default null)
returns table (code text, amount numeric)
language sql stable as $$
  with recursive up(code, ancestor) as (
    select l.code, l.code from erp.fs_lines l where l.statement = p_statement
    union all
    select up.code, p.parent
    from up join erp.fs_lines p on p.statement = p_statement and p.code = up.ancestor
    where p.parent is not null
  ), detail as (
    select line_code, sum(amount) as amount
    from erp.fs_classified_accounts(p_company, p_year, p_statement, p_to_date)
    group by line_code
  )
  select up.ancestor, coalesce(sum(d.amount), 0)
  from up left join detail d on d.line_code = up.code
  group by up.ancestor;
$$;

-- ---------------------------------------------------------------------
-- ESTADO FINANCIERO con columna del ejercicio anterior (como en las cuentas anuales)
-- ---------------------------------------------------------------------
create or replace function erp.financial_statement(p_company uuid, p_year int, p_statement text, p_to_date date default null)
returns table (code text, parent text, sort int, level int, label text, label_en text, is_total boolean,
               amount numeric, amount_prev numeric)
language sql stable as $$
  with recursive depth(code, level) as (
    select l.code, 0 from erp.fs_lines l where l.statement = p_statement and l.parent is null
    union all
    select c.code, d.level + 1 from depth d join erp.fs_lines c on c.statement = p_statement and c.parent = d.code
  )
  select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total,
         coalesce(n.amount, 0), coalesce(prev.amount, 0)
  from erp.fs_lines l
  join depth d on d.code = l.code
  left join erp.fs_amounts(p_company, p_year, p_statement, p_to_date) n on n.code = l.code
  left join erp.fs_amounts(p_company, p_year - 1, p_statement,
                           (p_to_date - interval '1 year')::date) prev on prev.code = l.code
  where l.statement = p_statement
  order by l.sort;
$$;

-- Cuentas que forman una partida (drill-down: de la partida a sus subcuentas)
create or replace function erp.fs_line_accounts(p_company uuid, p_year int, p_statement text, p_code text, p_to_date date default null)
returns table (account_no text, account_name text, account_name_en text, line_code text, amount numeric)
language sql stable as $$
  with recursive below(code) as (
    select p_code
    union all
    select l.code from erp.fs_lines l join below b on l.parent = b.code where l.statement = p_statement
  )
  select c.account_no, c.account_name, c.account_name_en, c.line_code, c.amount
  from erp.fs_classified_accounts(p_company, p_year, p_statement, p_to_date) c
  where c.line_code in (select code from below)
  order by c.account_no;
$$;

revoke execute on function erp.fs_classified_accounts(uuid, int, text, date), erp.fs_amounts(uuid, int, text, date),
  erp.financial_statement(uuid, int, text, date), erp.fs_line_accounts(uuid, int, text, text, date) from anon, public;
grant execute on function erp.fs_classified_accounts(uuid, int, text, date), erp.fs_amounts(uuid, int, text, date),
  erp.financial_statement(uuid, int, text, date), erp.fs_line_accounts(uuid, int, text, text, date) to authenticated;
