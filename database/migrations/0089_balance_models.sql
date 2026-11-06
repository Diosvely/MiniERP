-- =====================================================================
-- 0089 · El Balance en los tres modelos del PGC (v0.60.0)
-- ---------------------------------------------------------------------
-- Duda de Diosvely (06-11-2026): en el ERP las Existencias son «I» y en el BOE son «II». El ERP presenta el Balance con
-- el modelo del PGC de PYMES (RD 1515/2007), que no tiene «Activos no corrientes mantenidos para la venta»; el BOE que
-- miró era el modelo NORMAL del PGC general (RD 1514/2007), que empieza el activo corriente por esa partida.
--
-- Decisión (diseno-v0.60.0.md, validado el 06-11-2026): el mismo Balance en tres modelos, PYMES por defecto.
--   · PYMES no cambia: sigue en erp.fs_lines / erp.fs_mapping y es la clasificación del ERP (ratios, tableros, Power BI,
--     caso, ECPN, avisos).
--   · El ABREVIADO y el NORMAL solo RECOLOCAN las mismas cuentas, con el mismo saldo calculado una vez
--     (erp.fs_classified_at): el total no puede cambiar de un modelo a otro.
--   · Misma regla de siempre: cada subcuenta por su propio saldo, sin compensar (deudora → una partida; acreedora → otra).
--   · Partidas y cuentas del NORMAL: copiadas del BOE consolidado por Diosvely (06-11-2026). El ABREVIADO agrupa las del
--     normal (pendiente de validar por Diosvely con el BOE).
--   · Solo el Balance: la PyG sigue en el modelo PYMES (decisión 4).
-- =====================================================================

-- ---------- 1. Tablas ----------
create table erp.fs_models (
  code      text primary key,
  sort      int  not null,
  label     text not null,
  label_en  text not null,
  norm      text not null,
  norm_en   text not null,
  source    text not null          -- clave de la base documental (erp.sources)
);

create table erp.fs_model_lines (
  model     text not null references erp.fs_models(code),
  code      text not null,
  parent    text,
  sort      int  not null,
  label     text not null,
  label_en  text not null,
  side      text not null check (side in ('debit', 'credit')),
  is_total  boolean not null default false,
  primary key (model, code)
);

create table erp.fs_model_mapping (
  model        text not null references erp.fs_models(code),
  prefix       text not null,
  debit_line   text not null,   -- partida si la subcuenta tiene saldo DEUDOR
  credit_line  text not null,   -- partida si la subcuenta tiene saldo ACREEDOR
  primary key (model, prefix)
);

alter table erp.fs_models enable row level security;
alter table erp.fs_model_lines enable row level security;
alter table erp.fs_model_mapping enable row level security;
create policy read on erp.fs_models for select to authenticated using (true);
create policy read on erp.fs_model_lines for select to authenticated using (true);
create policy read on erp.fs_model_mapping for select to authenticated using (true);
revoke all on erp.fs_models, erp.fs_model_lines, erp.fs_model_mapping from anon, public;
grant select on erp.fs_models, erp.fs_model_lines, erp.fs_model_mapping to authenticated;

insert into erp.fs_models (code, sort, label, label_en, norm, norm_en, source) values
('pymes',     1, 'PYMES',     'SMEs',        'Modelo del PGC de PYMES (RD 1515/2007, tercera parte)', 'SME chart of accounts model (Royal Decree 1515/2007, part three)', 'pgcpymes'),
('abreviado', 2, 'Abreviado', 'Abridged',    'Modelo abreviado del PGC (RD 1514/2007, tercera parte)', 'Abridged model of the PGC (Royal Decree 1514/2007, part three)', 'pgcmodelos'),
('normal',    3, 'Normal',    'Full',        'Modelo normal del PGC (RD 1514/2007, tercera parte)', 'Full model of the PGC (Royal Decree 1514/2007, part three)', 'pgcmodelos');

-- ---------- 2. Modelo NORMAL · partidas (BOE consolidado, copiado por Diosvely el 06-11-2026) ----------
insert into erp.fs_model_lines (model, code, parent, sort, label, label_en, side, is_total)
select 'normal', code, parent, sort, label, label_en, side, is_total from (values
('ACT',          null,        100, 'TOTAL ACTIVO (A + B)', 'TOTAL ASSETS (A + B)', 'debit', true),
('ANC',          'ACT',       110, 'A) ACTIVO NO CORRIENTE', 'A) NON-CURRENT ASSETS', 'debit', true),
('ANC.I',        'ANC',       111, 'I. Inmovilizado intangible', 'I. Intangible assets', 'debit', false),
('ANC.I.1',      'ANC.I',     112, '1. Desarrollo', '1. Development', 'debit', false),
('ANC.I.2',      'ANC.I',     113, '2. Concesiones', '2. Concessions', 'debit', false),
('ANC.I.3',      'ANC.I',     114, '3. Patentes, licencias, marcas y similares', '3. Patents, licences, trademarks and similar', 'debit', false),
('ANC.I.4',      'ANC.I',     115, '4. Fondo de comercio', '4. Goodwill', 'debit', false),
('ANC.I.5',      'ANC.I',     116, '5. Aplicaciones informáticas', '5. Software', 'debit', false),
('ANC.I.6',      'ANC.I',     117, '6. Otro inmovilizado intangible', '6. Other intangible assets', 'debit', false),
('ANC.II',       'ANC',       120, 'II. Inmovilizado material', 'II. Property, plant and equipment', 'debit', false),
('ANC.II.1',     'ANC.II',    121, '1. Terrenos y construcciones', '1. Land and buildings', 'debit', false),
('ANC.II.2',     'ANC.II',    122, '2. Instalaciones técnicas, y otro inmovilizado material', '2. Plant and other property, plant and equipment', 'debit', false),
('ANC.II.3',     'ANC.II',    123, '3. Inmovilizado en curso y anticipos', '3. Assets under construction and advances', 'debit', false),
('ANC.III',      'ANC',       130, 'III. Inversiones inmobiliarias', 'III. Investment property', 'debit', false),
('ANC.III.1',    'ANC.III',   131, '1. Terrenos', '1. Land', 'debit', false),
('ANC.III.2',    'ANC.III',   132, '2. Construcciones', '2. Buildings', 'debit', false),
('ANC.IV',       'ANC',       140, 'IV. Inversiones en empresas del grupo y asociadas a largo plazo', 'IV. Long-term investments in group companies and associates', 'debit', false),
('ANC.IV.1',     'ANC.IV',    141, '1. Instrumentos de patrimonio', '1. Equity instruments', 'debit', false),
('ANC.IV.2',     'ANC.IV',    142, '2. Créditos a empresas', '2. Loans to companies', 'debit', false),
('ANC.IV.3',     'ANC.IV',    143, '3. Valores representativos de deuda', '3. Debt securities', 'debit', false),
('ANC.IV.4',     'ANC.IV',    144, '4. Derivados', '4. Derivatives', 'debit', false),
('ANC.IV.5',     'ANC.IV',    145, '5. Otros activos financieros', '5. Other financial assets', 'debit', false),
('ANC.V',        'ANC',       150, 'V. Inversiones financieras a largo plazo', 'V. Long-term financial investments', 'debit', false),
('ANC.V.1',      'ANC.V',     151, '1. Instrumentos de patrimonio', '1. Equity instruments', 'debit', false),
('ANC.V.2',      'ANC.V',     152, '2. Créditos a terceros', '2. Loans to third parties', 'debit', false),
('ANC.V.3',      'ANC.V',     153, '3. Valores representativos de deuda', '3. Debt securities', 'debit', false),
('ANC.V.4',      'ANC.V',     154, '4. Derivados', '4. Derivatives', 'debit', false),
('ANC.V.5',      'ANC.V',     155, '5. Otros activos financieros', '5. Other financial assets', 'debit', false),
('ANC.VI',       'ANC',       160, 'VI. Activos por impuesto diferido', 'VI. Deferred tax assets', 'debit', false),
('AC',           'ACT',       200, 'B) ACTIVO CORRIENTE', 'B) CURRENT ASSETS', 'debit', true),
('AC.I',         'AC',        201, 'I. Activos no corrientes mantenidos para la venta', 'I. Non-current assets held for sale', 'debit', false),
('AC.II',        'AC',        210, 'II. Existencias', 'II. Inventories', 'debit', false),
('AC.II.1',      'AC.II',     211, '1. Comerciales', '1. Goods for resale', 'debit', false),
('AC.II.2',      'AC.II',     212, '2. Materias primas y otros aprovisionamientos', '2. Raw materials and other supplies', 'debit', false),
('AC.II.3',      'AC.II',     213, '3. Productos en curso', '3. Work in progress', 'debit', false),
('AC.II.4',      'AC.II',     214, '4. Productos terminados', '4. Finished goods', 'debit', false),
('AC.II.5',      'AC.II',     215, '5. Subproductos, residuos y materiales recuperados', '5. By-products, waste and recovered materials', 'debit', false),
('AC.II.6',      'AC.II',     216, '6. Anticipos a proveedores', '6. Advances to suppliers', 'debit', false),
('AC.III',       'AC',        220, 'III. Deudores comerciales y otras cuentas a cobrar', 'III. Trade and other receivables', 'debit', false),
('AC.III.1',     'AC.III',    221, '1. Clientes por ventas y prestaciones de servicios', '1. Trade receivables', 'debit', false),
('AC.III.2',     'AC.III',    222, '2. Clientes, empresas del grupo y asociadas', '2. Trade receivables from group companies and associates', 'debit', false),
('AC.III.3',     'AC.III',    223, '3. Deudores varios', '3. Sundry receivables', 'debit', false),
('AC.III.4',     'AC.III',    224, '4. Personal', '4. Employees', 'debit', false),
('AC.III.5',     'AC.III',    225, '5. Activos por impuesto corriente', '5. Current tax assets', 'debit', false),
('AC.III.6',     'AC.III',    226, '6. Otros créditos con las Administraciones Públicas', '6. Other receivables from public administrations', 'debit', false),
('AC.III.7',     'AC.III',    227, '7. Accionistas (socios) por desembolsos exigidos', '7. Called-up capital not paid', 'debit', false),
('AC.IV',        'AC',        230, 'IV. Inversiones en empresas del grupo y asociadas a corto plazo', 'IV. Short-term investments in group companies and associates', 'debit', false),
('AC.IV.1',      'AC.IV',     231, '1. Instrumentos de patrimonio', '1. Equity instruments', 'debit', false),
('AC.IV.2',      'AC.IV',     232, '2. Créditos a empresas', '2. Loans to companies', 'debit', false),
('AC.IV.3',      'AC.IV',     233, '3. Valores representativos de deuda', '3. Debt securities', 'debit', false),
('AC.IV.4',      'AC.IV',     234, '4. Derivados', '4. Derivatives', 'debit', false),
('AC.IV.5',      'AC.IV',     235, '5. Otros activos financieros', '5. Other financial assets', 'debit', false),
('AC.V',         'AC',        240, 'V. Inversiones financieras a corto plazo', 'V. Short-term financial investments', 'debit', false),
('AC.V.1',       'AC.V',      241, '1. Instrumentos de patrimonio', '1. Equity instruments', 'debit', false),
('AC.V.2',       'AC.V',      242, '2. Créditos a empresas', '2. Loans to companies', 'debit', false),
('AC.V.3',       'AC.V',      243, '3. Valores representativos de deuda', '3. Debt securities', 'debit', false),
('AC.V.4',       'AC.V',      244, '4. Derivados', '4. Derivatives', 'debit', false),
('AC.V.5',       'AC.V',      245, '5. Otros activos financieros', '5. Other financial assets', 'debit', false),
('AC.VI',        'AC',        250, 'VI. Periodificaciones a corto plazo', 'VI. Short-term prepayments', 'debit', false),
('AC.VII',       'AC',        260, 'VII. Efectivo y otros activos líquidos equivalentes', 'VII. Cash and cash equivalents', 'debit', false),
('AC.VII.1',     'AC.VII',    261, '1. Tesorería', '1. Cash', 'debit', false),
('AC.VII.2',     'AC.VII',    262, '2. Otros activos líquidos equivalentes', '2. Other cash equivalents', 'debit', false),

('PNP',          null,        500, 'TOTAL PATRIMONIO NETO Y PASIVO (A + B + C)', 'TOTAL EQUITY AND LIABILITIES (A + B + C)', 'credit', true),
('PN',           'PNP',       510, 'A) PATRIMONIO NETO', 'A) EQUITY', 'credit', true),
('PN.A1',        'PN',        511, 'A-1) Fondos propios', 'A-1) Shareholders'' equity', 'credit', true),
('PN.A1.I',      'PN.A1',     512, 'I. Capital', 'I. Capital', 'credit', false),
('PN.A1.I.1',    'PN.A1.I',   513, '1. Capital escriturado', '1. Registered capital', 'credit', false),
('PN.A1.I.2',    'PN.A1.I',   514, '2. (Capital no exigido)', '2. (Uncalled capital)', 'credit', false),
('PN.A1.II',     'PN.A1',     515, 'II. Prima de emisión', 'II. Share premium', 'credit', false),
('PN.A1.III',    'PN.A1',     516, 'III. Reservas', 'III. Reserves', 'credit', false),
('PN.A1.III.1',  'PN.A1.III', 517, '1. Legal y estatutarias', '1. Legal and statutory', 'credit', false),
('PN.A1.III.2',  'PN.A1.III', 518, '2. Otras reservas', '2. Other reserves', 'credit', false),
('PN.A1.IV',     'PN.A1',     519, 'IV. (Acciones y participaciones en patrimonio propias)', 'IV. (Treasury shares)', 'credit', false),
('PN.A1.V',      'PN.A1',     520, 'V. Resultados de ejercicios anteriores', 'V. Prior years'' results', 'credit', false),
('PN.A1.V.1',    'PN.A1.V',   521, '1. Remanente', '1. Retained earnings', 'credit', false),
('PN.A1.V.2',    'PN.A1.V',   522, '2. (Resultados negativos de ejercicios anteriores)', '2. (Prior years'' losses)', 'credit', false),
('PN.A1.VI',     'PN.A1',     523, 'VI. Otras aportaciones de socios', 'VI. Other shareholder contributions', 'credit', false),
('PN.A1.VII',    'PN.A1',     524, 'VII. Resultado del ejercicio', 'VII. Profit (loss) for the year', 'credit', false),
('PN.A1.VIII',   'PN.A1',     525, 'VIII. (Dividendo a cuenta)', 'VIII. (Interim dividend)', 'credit', false),
('PN.A1.IX',     'PN.A1',     526, 'IX. Otros instrumentos de patrimonio neto', 'IX. Other equity instruments', 'credit', false),
('PN.A2',        'PN',        530, 'A-2) Ajustes por cambios de valor', 'A-2) Valuation adjustments', 'credit', false),
('PN.A2.I',      'PN.A2',     531, 'I. Activos financieros a valor razonable con cambios en el patrimonio neto', 'I. Financial assets at fair value through equity', 'credit', false),
('PN.A2.II',     'PN.A2',     532, 'II. Operaciones de cobertura', 'II. Hedging transactions', 'credit', false),
('PN.A2.III',    'PN.A2',     533, 'III. Otros', 'III. Other', 'credit', false),
('PN.A3',        'PN',        540, 'A-3) Subvenciones, donaciones y legados recibidos', 'A-3) Grants, donations and bequests received', 'credit', false),
('PNC',          'PNP',       600, 'B) PASIVO NO CORRIENTE', 'B) NON-CURRENT LIABILITIES', 'credit', true),
('PNC.I',        'PNC',       610, 'I. Provisiones a largo plazo', 'I. Long-term provisions', 'credit', false),
('PNC.I.1',      'PNC.I',     611, '1. Obligaciones por prestaciones a largo plazo al personal', '1. Long-term employee benefit obligations', 'credit', false),
('PNC.I.2',      'PNC.I',     612, '2. Actuaciones medioambientales', '2. Environmental actions', 'credit', false),
('PNC.I.3',      'PNC.I',     613, '3. Provisiones por reestructuración', '3. Restructuring provisions', 'credit', false),
('PNC.I.4',      'PNC.I',     614, '4. Otras provisiones', '4. Other provisions', 'credit', false),
('PNC.II',       'PNC',       620, 'II. Deudas a largo plazo', 'II. Long-term debts', 'credit', false),
('PNC.II.1',     'PNC.II',    621, '1. Obligaciones y otros valores negociables', '1. Bonds and other marketable securities', 'credit', false),
('PNC.II.2',     'PNC.II',    622, '2. Deudas con entidades de crédito', '2. Bank borrowings', 'credit', false),
('PNC.II.3',     'PNC.II',    623, '3. Acreedores por arrendamiento financiero', '3. Finance lease payables', 'credit', false),
('PNC.II.4',     'PNC.II',    624, '4. Derivados', '4. Derivatives', 'credit', false),
('PNC.II.5',     'PNC.II',    625, '5. Otros pasivos financieros', '5. Other financial liabilities', 'credit', false),
('PNC.III',      'PNC',       630, 'III. Deudas con empresas del grupo y asociadas a largo plazo', 'III. Long-term debts with group companies and associates', 'credit', false),
('PNC.IV',       'PNC',       640, 'IV. Pasivos por impuesto diferido', 'IV. Deferred tax liabilities', 'credit', false),
('PNC.V',        'PNC',       650, 'V. Periodificaciones a largo plazo', 'V. Long-term accruals', 'credit', false),
('PC',           'PNP',       700, 'C) PASIVO CORRIENTE', 'C) CURRENT LIABILITIES', 'credit', true),
('PC.I',         'PC',        701, 'I. Pasivos vinculados con activos no corrientes mantenidos para la venta', 'I. Liabilities associated with non-current assets held for sale', 'credit', false),
('PC.II',        'PC',        710, 'II. Provisiones a corto plazo', 'II. Short-term provisions', 'credit', false),
('PC.III',       'PC',        720, 'III. Deudas a corto plazo', 'III. Short-term debts', 'credit', false),
('PC.III.1',     'PC.III',    721, '1. Obligaciones y otros valores negociables', '1. Bonds and other marketable securities', 'credit', false),
('PC.III.2',     'PC.III',    722, '2. Deudas con entidades de crédito', '2. Bank borrowings', 'credit', false),
('PC.III.3',     'PC.III',    723, '3. Acreedores por arrendamiento financiero', '3. Finance lease payables', 'credit', false),
('PC.III.4',     'PC.III',    724, '4. Derivados', '4. Derivatives', 'credit', false),
('PC.III.5',     'PC.III',    725, '5. Otros pasivos financieros', '5. Other financial liabilities', 'credit', false),
('PC.IV',        'PC',        730, 'IV. Deudas con empresas del grupo y asociadas a corto plazo', 'IV. Short-term debts with group companies and associates', 'credit', false),
('PC.V',         'PC',        740, 'V. Acreedores comerciales y otras cuentas a pagar', 'V. Trade and other payables', 'credit', false),
('PC.V.1',       'PC.V',      741, '1. Proveedores', '1. Suppliers', 'credit', false),
('PC.V.2',       'PC.V',      742, '2. Proveedores, empresas del grupo y asociadas', '2. Suppliers, group companies and associates', 'credit', false),
('PC.V.3',       'PC.V',      743, '3. Acreedores varios', '3. Sundry payables', 'credit', false),
('PC.V.4',       'PC.V',      744, '4. Personal (remuneraciones pendientes de pago)', '4. Employees (wages payable)', 'credit', false),
('PC.V.5',       'PC.V',      745, '5. Pasivos por impuesto corriente', '5. Current tax liabilities', 'credit', false),
('PC.V.6',       'PC.V',      746, '6. Otras deudas con las Administraciones Públicas', '6. Other payables to public administrations', 'credit', false),
('PC.V.7',       'PC.V',      747, '7. Anticipos de clientes', '7. Customer advances', 'credit', false),
('PC.VI',        'PC',        750, 'VI. Periodificaciones a corto plazo', 'VI. Short-term accruals', 'credit', false)
) v(code, parent, sort, label, label_en, side, is_total);

-- ---------- 3. Modelo NORMAL · cuentas (columna «Núm. cuentas» del BOE) ----------
-- Gana el prefijo más largo. Las que el BOE no nombra van a la partida «otros» de su grupo, en el mismo lado que en
-- PYMES. Las cuentas al revés siguen la regla de la v0.59.2: van a la partida que corresponde a su saldo.
insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line)
select 'normal', prefix, debit_line, credit_line from (values
-- Grupo 1 · patrimonio neto y pasivo no corriente
('1',    'PNC.II.5',    'PNC.II.5'),
('10',   'PN.A1.I.1',   'PN.A1.I.1'),      -- 100, 101, 102
('1030', 'PN.A1.I.2',   'PN.A1.I.2'),      -- (1030), (1040) capital no exigido
('1040', 'PN.A1.I.2',   'PN.A1.I.2'),
('1034', 'PC.III.5',    'PC.III.5'),       -- (1034), (1044): en «5. Otros pasivos financieros» a corto, como dice el BOE
('1044', 'PC.III.5',    'PC.III.5'),
('108',  'PN.A1.IV',    'PN.A1.IV'),
('109',  'PN.A1.IV',    'PN.A1.IV'),
('11',   'PN.A1.III.2', 'PN.A1.III.2'),    -- 113, 1140, 1142, 1143, 1144, 115, 119
('110',  'PN.A1.II',    'PN.A1.II'),
('111',  'PN.A1.IX',    'PN.A1.IX'),
('112',  'PN.A1.III.1', 'PN.A1.III.1'),
('1141', 'PN.A1.III.1', 'PN.A1.III.1'),
('118',  'PN.A1.VI',    'PN.A1.VI'),
('12',   'PN.A1.V.1',   'PN.A1.V.1'),      -- 120
('121',  'PN.A1.V.2',   'PN.A1.V.2'),
('129',  'PN.A1.VII',   'PN.A1.VII'),
('13',   'PN.A3',       'PN.A3'),          -- 130, 131, 132
('133',  'PN.A2.I',     'PN.A2.I'),
('134',  'PN.A2.III',   'PN.A2.III'),
('1340', 'PN.A2.II',    'PN.A2.II'),
('135',  'PN.A2.III',   'PN.A2.III'),
('136',  'PN.A2.III',   'PN.A2.III'),
('137',  'PN.A2.III',   'PN.A2.III'),
('14',   'PNC.I.4',     'PNC.I.4'),        -- 141, 142, 143, 147
('140',  'PNC.I.1',     'PNC.I.1'),
('145',  'PNC.I.2',     'PNC.I.2'),
('146',  'PNC.I.3',     'PNC.I.3'),
('16',   'PNC.III',     'PNC.III'),        -- 1603, 1604, 1613, 1614, 1623, 1624, 1633, 1634
('1605', 'PNC.II.2',    'PNC.II.2'),
('1615', 'PNC.II.5',    'PNC.II.5'),
('1625', 'PNC.II.3',    'PNC.II.3'),
('1635', 'PNC.II.5',    'PNC.II.5'),
('170',  'PNC.II.2',    'PNC.II.2'),
('174',  'PNC.II.3',    'PNC.II.3'),
('176',  'PNC.II.4',    'PNC.II.4'),
('177',  'PNC.II.1',    'PNC.II.1'),
('178',  'PNC.II.1',    'PNC.II.1'),
('179',  'PNC.II.1',    'PNC.II.1'),
('181',  'PNC.V',       'PNC.V'),
('19',   'PC.III.5',    'PC.III.5'),       -- (190), (192), 194
-- Grupo 2 · activo no corriente
('2',    'ANC.II.2',    'ANC.II.2'),
('20',   'ANC.I.6',     'ANC.I.6'),        -- 205, 209 (y 200)
('201',  'ANC.I.1',     'ANC.I.1'),
('202',  'ANC.I.2',     'ANC.I.2'),
('203',  'ANC.I.3',     'ANC.I.3'),
('204',  'ANC.I.4',     'ANC.I.4'),
('206',  'ANC.I.5',     'ANC.I.5'),
('21',   'ANC.II.2',    'ANC.II.2'),       -- 212 a 219
('210',  'ANC.II.1',    'ANC.II.1'),
('211',  'ANC.II.1',    'ANC.II.1'),
('22',   'ANC.III.2',   'ANC.III.2'),
('220',  'ANC.III.1',   'ANC.III.1'),
('23',   'ANC.II.3',    'ANC.II.3'),
('24',   'ANC.IV.1',    'ANC.IV.1'),       -- 2403, 2404, (2493), (2494)
('241',  'ANC.IV.3',    'ANC.IV.3'),       -- 2413, 2414
('242',  'ANC.IV.2',    'ANC.IV.2'),       -- 2423, 2424
('2405', 'ANC.V.1',     'ANC.V.1'),
('2415', 'ANC.V.3',     'ANC.V.3'),
('2425', 'ANC.V.2',     'ANC.V.2'),
('2495', 'ANC.V.1',     'ANC.V.1'),
('25',   'ANC.V.5',     'ANC.V.5'),        -- 258
('250',  'ANC.V.1',     'ANC.V.1'),
('251',  'ANC.V.3',     'ANC.V.3'),
('252',  'ANC.V.2',     'ANC.V.2'),
('253',  'ANC.V.2',     'ANC.V.2'),
('254',  'ANC.V.2',     'ANC.V.2'),
('255',  'ANC.V.4',     'ANC.V.4'),
('259',  'ANC.V.1',     'ANC.V.1'),
('26',   'ANC.V.5',     'ANC.V.5'),
('280',  'ANC.I.6',     'ANC.I.6'),        -- (2805) y las demás
('2801', 'ANC.I.1',     'ANC.I.1'),
('2802', 'ANC.I.2',     'ANC.I.2'),
('2803', 'ANC.I.3',     'ANC.I.3'),
('2804', 'ANC.I.4',     'ANC.I.4'),
('2806', 'ANC.I.5',     'ANC.I.5'),
('281',  'ANC.II.2',    'ANC.II.2'),
('2811', 'ANC.II.1',    'ANC.II.1'),
('282',  'ANC.III.2',   'ANC.III.2'),
('290',  'ANC.I.6',     'ANC.I.6'),        -- (2905) y las demás
('2901', 'ANC.I.1',     'ANC.I.1'),
('2902', 'ANC.I.2',     'ANC.I.2'),
('2903', 'ANC.I.3',     'ANC.I.3'),
('2906', 'ANC.I.5',     'ANC.I.5'),
('291',  'ANC.II.2',    'ANC.II.2'),
('2910', 'ANC.II.1',    'ANC.II.1'),
('2911', 'ANC.II.1',    'ANC.II.1'),
('292',  'ANC.III.2',   'ANC.III.2'),
('2920', 'ANC.III.1',   'ANC.III.1'),
('293',  'ANC.IV.1',    'ANC.IV.1'),
('294',  'ANC.IV.3',    'ANC.IV.3'),       -- (2943), (2944)
('2945', 'ANC.V.3',     'ANC.V.3'),
('295',  'ANC.IV.2',    'ANC.IV.2'),       -- (2953), (2954)
('2955', 'ANC.V.2',     'ANC.V.2'),
('296',  'ANC.V.1',     'ANC.V.1'),
('297',  'ANC.V.3',     'ANC.V.3'),
('298',  'ANC.V.2',     'ANC.V.2'),
-- Grupo 3 · existencias
('3',    'AC.II.1',     'AC.II.1'),
('31',   'AC.II.2',     'AC.II.2'),
('32',   'AC.II.2',     'AC.II.2'),
('33',   'AC.II.3',     'AC.II.3'),
('34',   'AC.II.3',     'AC.II.3'),
('35',   'AC.II.4',     'AC.II.4'),
('36',   'AC.II.5',     'AC.II.5'),
('391',  'AC.II.2',     'AC.II.2'),
('392',  'AC.II.2',     'AC.II.2'),
('393',  'AC.II.3',     'AC.II.3'),
('394',  'AC.II.3',     'AC.II.3'),
('395',  'AC.II.4',     'AC.II.4'),
('396',  'AC.II.5',     'AC.II.5'),
-- Grupo 4 · acreedores y deudores (deudora → activo; acreedora → pasivo)
('40',   'AC.III.3',    'PC.V.1'),         -- 400, 401, 405; deudora: Deudores varios (v0.59.2)
('403',  'AC.III.3',    'PC.V.2'),
('404',  'AC.III.3',    'PC.V.2'),
('406',  'PC.V.1',      'PC.V.1'),         -- (406) resta en Proveedores
('407',  'AC.II.6',     'PC.V.1'),         -- anticipos a proveedores, en Existencias
('41',   'AC.III.3',    'PC.V.3'),
('43',   'AC.III.1',    'PC.V.7'),         -- 430, 431, 432, 435, 436, (437); acreedora: Anticipos de clientes (438)
('433',  'AC.III.2',    'PC.V.7'),
('434',  'AC.III.2',    'PC.V.7'),
('44',   'AC.III.3',    'PC.V.3'),
('46',   'AC.III.4',    'PC.V.4'),         -- 460 / 465, 466
('47',   'AC.III.6',    'PC.V.6'),         -- 4700, 4708, 471, 472 / 4750, 4751, 4758, 476, 477
('4709', 'AC.III.5',    'PC.V.6'),
('474',  'ANC.VI',      'ANC.VI'),
('4752', 'AC.III.5',    'PC.V.5'),
('479',  'PNC.IV',      'PNC.IV'),
('48',   'AC.VI',       'PC.VI'),          -- 480 / 485
('49',   'AC.III.1',    'AC.III.1'),       -- (490), (4935)
('4933', 'AC.III.2',    'AC.III.2'),
('4934', 'AC.III.2',    'AC.III.2'),
('499',  'PC.II',       'PC.II'),
-- Grupo 5 · cuentas financieras
('5',    'AC.V.5',      'PC.III.5'),
('50',   'AC.V.5',      'PC.III.1'),       -- 500, 501, 505, 506
('509',  'AC.V.5',      'PC.III.5'),
('51',   'AC.IV.5',     'PC.IV'),          -- 5103, 5104, 5113, 5114…
('5105', 'AC.V.5',      'PC.III.2'),
('5115', 'AC.V.5',      'PC.III.5'),
('5125', 'AC.V.5',      'PC.III.3'),
('5135', 'AC.V.5',      'PC.III.5'),
('5145', 'AC.V.5',      'PC.III.5'),
('520',  'AC.V.5',      'PC.III.2'),
('524',  'AC.V.5',      'PC.III.3'),
('527',  'AC.V.5',      'PC.III.2'),
('529',  'PC.II',       'PC.II'),
('53',   'AC.IV.1',     'PC.IV'),          -- 5303, 5304, (5393), (5394)
('531',  'AC.IV.3',     'PC.IV'),
('532',  'AC.IV.2',     'PC.IV'),
('533',  'AC.IV.3',     'PC.IV'),
('534',  'AC.IV.2',     'PC.IV'),
('535',  'AC.IV.5',     'PC.IV'),
('5305', 'AC.V.1',      'PC.III.5'),
('5315', 'AC.V.3',      'PC.III.5'),
('5325', 'AC.V.2',      'PC.III.5'),
('5335', 'AC.V.3',      'PC.III.5'),
('5345', 'AC.V.2',      'PC.III.5'),
('5355', 'AC.V.5',      'PC.III.5'),
('5395', 'AC.V.1',      'PC.III.5'),
('540',  'AC.V.1',      'PC.III.5'),
('541',  'AC.V.3',      'PC.III.5'),
('542',  'AC.V.2',      'PC.III.5'),
('543',  'AC.V.2',      'PC.III.5'),
('544',  'AC.III.4',    'PC.V.4'),         -- créditos al personal
('546',  'AC.V.3',      'PC.III.5'),
('547',  'AC.V.2',      'PC.III.5'),
('549',  'AC.V.1',      'PC.III.5'),
('5523', 'AC.IV.5',     'PC.IV'),
('5524', 'AC.IV.5',     'PC.IV'),
('5563', 'AC.IV.5',     'PC.IV'),
('5564', 'AC.IV.5',     'PC.IV'),
('557',  'PN.A1.VIII',  'PN.A1.VIII'),
('5580', 'AC.III.7',    'AC.III.7'),
('559',  'AC.V.4',      'PC.III.4'),       -- 5590, 5593 / 5595, 5598
('567',  'AC.VI',       'PC.VI'),
('568',  'AC.VI',       'PC.VI'),
('57',   'AC.VII.1',    'PC.III.2'),       -- 570 a 575; acreedora: Deudas con entidades de crédito
('576',  'AC.VII.2',    'PC.III.2'),
('58',   'AC.I',        'PC.I'),           -- 580 a 584, (599) / 585 a 589
('59',   'AC.V.5',      'AC.V.5'),
('593',  'AC.IV.1',     'AC.IV.1'),
('594',  'AC.IV.3',     'AC.IV.3'),
('5945', 'AC.V.3',      'AC.V.3'),
('595',  'AC.IV.2',     'AC.IV.2'),
('5955', 'AC.V.2',      'AC.V.2'),
('597',  'AC.V.3',      'AC.V.3'),
('598',  'AC.V.2',      'AC.V.2'),
('599',  'AC.I',        'AC.I'),
-- Grupos 6 y 7 sin regularizar, en el resultado; grupos 8 y 9 (de las subvenciones), en A-3
('6',    'PN.A1.VII',   'PN.A1.VII'),
('7',    'PN.A1.VII',   'PN.A1.VII'),
('8',    'PN.A3',       'PN.A3'),
('9',    'PN.A3',       'PN.A3')
) v(prefix, debit_line, credit_line);

-- ---------- 4. Modelo ABREVIADO: agrupa las partidas del normal ----------
-- Pendiente de validar por Diosvely con el BOE (modelo abreviado del RD 1514/2007, tercera parte).
insert into erp.fs_model_lines (model, code, parent, sort, label, label_en, side, is_total)
select 'abreviado', code, parent, sort, label, label_en, side, is_total from (values
('ACT',        null,        100, 'TOTAL ACTIVO (A + B)', 'TOTAL ASSETS (A + B)', 'debit', true),
('ANC',        'ACT',       110, 'A) ACTIVO NO CORRIENTE', 'A) NON-CURRENT ASSETS', 'debit', true),
('ANC.I',      'ANC',       111, 'I. Inmovilizado intangible', 'I. Intangible assets', 'debit', false),
('ANC.II',     'ANC',       120, 'II. Inmovilizado material', 'II. Property, plant and equipment', 'debit', false),
('ANC.III',    'ANC',       130, 'III. Inversiones inmobiliarias', 'III. Investment property', 'debit', false),
('ANC.IV',     'ANC',       140, 'IV. Inversiones en empresas del grupo y asociadas a largo plazo', 'IV. Long-term investments in group companies and associates', 'debit', false),
('ANC.V',      'ANC',       150, 'V. Inversiones financieras a largo plazo', 'V. Long-term financial investments', 'debit', false),
('ANC.VI',     'ANC',       160, 'VI. Activos por impuesto diferido', 'VI. Deferred tax assets', 'debit', false),
('AC',         'ACT',       200, 'B) ACTIVO CORRIENTE', 'B) CURRENT ASSETS', 'debit', true),
('AC.I',       'AC',        201, 'I. Activos no corrientes mantenidos para la venta', 'I. Non-current assets held for sale', 'debit', false),
('AC.II',      'AC',        210, 'II. Existencias', 'II. Inventories', 'debit', false),
('AC.III',     'AC',        220, 'III. Deudores comerciales y otras cuentas a cobrar', 'III. Trade and other receivables', 'debit', false),
('AC.III.1',   'AC.III',    221, '1. Clientes por ventas y prestaciones de servicios', '1. Trade receivables', 'debit', false),
('AC.III.2',   'AC.III',    222, '2. Accionistas (socios) por desembolsos exigidos', '2. Called-up capital not paid', 'debit', false),
('AC.III.3',   'AC.III',    223, '3. Otros deudores', '3. Other receivables', 'debit', false),
('AC.IV',      'AC',        230, 'IV. Inversiones en empresas del grupo y asociadas a corto plazo', 'IV. Short-term investments in group companies and associates', 'debit', false),
('AC.V',       'AC',        240, 'V. Inversiones financieras a corto plazo', 'V. Short-term financial investments', 'debit', false),
('AC.VI',      'AC',        250, 'VI. Periodificaciones a corto plazo', 'VI. Short-term prepayments', 'debit', false),
('AC.VII',     'AC',        260, 'VII. Efectivo y otros activos líquidos equivalentes', 'VII. Cash and cash equivalents', 'debit', false),

('PNP',        null,        500, 'TOTAL PATRIMONIO NETO Y PASIVO (A + B + C)', 'TOTAL EQUITY AND LIABILITIES (A + B + C)', 'credit', true),
('PN',         'PNP',       510, 'A) PATRIMONIO NETO', 'A) EQUITY', 'credit', true),
('PN.A1',      'PN',        511, 'A-1) Fondos propios', 'A-1) Shareholders'' equity', 'credit', true),
('PN.A1.I',    'PN.A1',     512, 'I. Capital', 'I. Capital', 'credit', false),
('PN.A1.I.1',  'PN.A1.I',   513, '1. Capital escriturado', '1. Registered capital', 'credit', false),
('PN.A1.I.2',  'PN.A1.I',   514, '2. (Capital no exigido)', '2. (Uncalled capital)', 'credit', false),
('PN.A1.II',   'PN.A1',     515, 'II. Prima de emisión', 'II. Share premium', 'credit', false),
('PN.A1.III',  'PN.A1',     516, 'III. Reservas', 'III. Reserves', 'credit', false),
('PN.A1.IV',   'PN.A1',     519, 'IV. (Acciones y participaciones en patrimonio propias)', 'IV. (Treasury shares)', 'credit', false),
('PN.A1.V',    'PN.A1',     520, 'V. Resultados de ejercicios anteriores', 'V. Prior years'' results', 'credit', false),
('PN.A1.VI',   'PN.A1',     523, 'VI. Otras aportaciones de socios', 'VI. Other shareholder contributions', 'credit', false),
('PN.A1.VII',  'PN.A1',     524, 'VII. Resultado del ejercicio', 'VII. Profit (loss) for the year', 'credit', false),
('PN.A1.VIII', 'PN.A1',     525, 'VIII. (Dividendo a cuenta)', 'VIII. (Interim dividend)', 'credit', false),
('PN.A1.IX',   'PN.A1',     526, 'IX. Otros instrumentos de patrimonio neto', 'IX. Other equity instruments', 'credit', false),
('PN.A2',      'PN',        530, 'A-2) Ajustes por cambios de valor', 'A-2) Valuation adjustments', 'credit', false),
('PN.A3',      'PN',        540, 'A-3) Subvenciones, donaciones y legados recibidos', 'A-3) Grants, donations and bequests received', 'credit', false),
('PNC',        'PNP',       600, 'B) PASIVO NO CORRIENTE', 'B) NON-CURRENT LIABILITIES', 'credit', true),
('PNC.I',      'PNC',       610, 'I. Provisiones a largo plazo', 'I. Long-term provisions', 'credit', false),
('PNC.II',     'PNC',       620, 'II. Deudas a largo plazo', 'II. Long-term debts', 'credit', false),
('PNC.II.1',   'PNC.II',    621, '1. Deudas con entidades de crédito', '1. Bank borrowings', 'credit', false),
('PNC.II.2',   'PNC.II',    622, '2. Acreedores por arrendamiento financiero', '2. Finance lease payables', 'credit', false),
('PNC.II.3',   'PNC.II',    623, '3. Otras deudas a largo plazo', '3. Other long-term debts', 'credit', false),
('PNC.III',    'PNC',       630, 'III. Deudas con empresas del grupo y asociadas a largo plazo', 'III. Long-term debts with group companies and associates', 'credit', false),
('PNC.IV',     'PNC',       640, 'IV. Pasivos por impuesto diferido', 'IV. Deferred tax liabilities', 'credit', false),
('PNC.V',      'PNC',       650, 'V. Periodificaciones a largo plazo', 'V. Long-term accruals', 'credit', false),
('PC',         'PNP',       700, 'C) PASIVO CORRIENTE', 'C) CURRENT LIABILITIES', 'credit', true),
('PC.I',       'PC',        701, 'I. Pasivos vinculados con activos no corrientes mantenidos para la venta', 'I. Liabilities associated with non-current assets held for sale', 'credit', false),
('PC.II',      'PC',        710, 'II. Provisiones a corto plazo', 'II. Short-term provisions', 'credit', false),
('PC.III',     'PC',        720, 'III. Deudas a corto plazo', 'III. Short-term debts', 'credit', false),
('PC.III.1',   'PC.III',    721, '1. Deudas con entidades de crédito', '1. Bank borrowings', 'credit', false),
('PC.III.2',   'PC.III',    722, '2. Acreedores por arrendamiento financiero', '2. Finance lease payables', 'credit', false),
('PC.III.3',   'PC.III',    723, '3. Otras deudas a corto plazo', '3. Other short-term debts', 'credit', false),
('PC.IV',      'PC',        730, 'IV. Deudas con empresas del grupo y asociadas a corto plazo', 'IV. Short-term debts with group companies and associates', 'credit', false),
('PC.V',       'PC',        740, 'V. Acreedores comerciales y otras cuentas a pagar', 'V. Trade and other payables', 'credit', false),
('PC.V.1',     'PC.V',      741, '1. Proveedores', '1. Suppliers', 'credit', false),
('PC.V.2',     'PC.V',      742, '2. Otros acreedores', '2. Other payables', 'credit', false),
('PC.VI',      'PC',        750, 'VI. Periodificaciones a corto plazo', 'VI. Short-term accruals', 'credit', false)
) v(code, parent, sort, label, label_en, side, is_total);

-- Las cuentas del abreviado: las del normal, con su partida agrupada
create or replace function erp.fs_abridged_line(p_normal text)
returns text language sql immutable set search_path = erp, public as $$
  select case
    when p_normal ~ '^(ANC\.(I|II|III|IV|V)|AC\.(II|IV|V|VII)|PN\.A1\.(III|V)|PN\.A2|PNC\.I)\.' then regexp_replace(p_normal, '\.[^.]+$', '')
    when p_normal in ('AC.III.1', 'AC.III.2') then 'AC.III.1'
    when p_normal = 'AC.III.7' then 'AC.III.2'
    when p_normal like 'AC.III.%' then 'AC.III.3'
    when p_normal = 'PNC.II.2' then 'PNC.II.1'
    when p_normal = 'PNC.II.3' then 'PNC.II.2'
    when p_normal like 'PNC.II.%' then 'PNC.II.3'
    when p_normal = 'PC.III.2' then 'PC.III.1'
    when p_normal = 'PC.III.3' then 'PC.III.2'
    when p_normal like 'PC.III.%' then 'PC.III.3'
    when p_normal in ('PC.V.1', 'PC.V.2') then 'PC.V.1'
    when p_normal like 'PC.V.%' then 'PC.V.2'
    else p_normal end;
$$;
insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line)
select 'abreviado', prefix, erp.fs_abridged_line(debit_line), erp.fs_abridged_line(credit_line)
from erp.fs_model_mapping where model = 'normal';

do $$
begin
  if exists (select 1 from erp.fs_model_mapping m
             where not exists (select 1 from erp.fs_model_lines l where l.model = m.model and l.code = m.debit_line)
                or not exists (select 1 from erp.fs_model_lines l where l.model = m.model and l.code = m.credit_line)) then
    raise exception 'fs_model_mapping points to a missing fs_model_lines code';
  end if;
end $$;

-- ---------- 5. Funciones ----------
-- Partidas de un modelo (PYMES: las de siempre, erp.fs_lines)
create or replace function erp.fs_model_line_set(p_model text)
returns table(code text, parent text, sort int, label text, label_en text, side text, is_total boolean)
language sql stable set search_path = erp, public as $$
  select l.code, l.parent, l.sort, l.label, l.label_en, l.side, l.is_total
  from erp.fs_lines l where p_model = 'pymes' and l.statement = 'balance'
  union all
  select l.code, l.parent, l.sort, l.label, l.label_en, l.side, l.is_total
  from erp.fs_model_lines l where p_model <> 'pymes' and l.model = p_model;
$$;

-- Cada cuenta del Balance en la partida del modelo. El saldo se calcula UNA vez (erp.fs_classified_at, el de PYMES);
-- el abreviado y el normal solo la recolocan por su propio saldo (deudor / acreedor), sin compensar.
create or replace function erp.fs_model_classified_at(p_company uuid, p_year int, p_model text, p_dates date[])
returns table(at date, account_no text, account_name text, account_name_en text, balance numeric, line_code text, amount numeric)
language sql stable set search_path = erp, public as $$
  select c.at, c.account_no, c.account_name, c.account_name_en, c.balance, c.line_code, c.amount
  from erp.fs_classified_at(p_company, p_year, 'balance', p_dates) c
  where p_model = 'pymes'
  union all
  select c.at, c.account_no, c.account_name, c.account_name_en, c.balance, m.line,
         c.balance * case l.side when 'debit' then 1 else -1 end
  from erp.fs_classified_at(p_company, p_year, 'balance', p_dates) c
  cross join lateral (
    select case when c.balance >= 0 then fm.debit_line else fm.credit_line end as line
    from erp.fs_model_mapping fm
    where fm.model = p_model and c.account_no like fm.prefix || '%'
    order by length(fm.prefix) desc limit 1) m
  join erp.fs_model_lines l on l.model = p_model and l.code = m.line
  where p_model <> 'pymes';
$$;

create or replace function erp.fs_model_amounts(p_company uuid, p_year int, p_model text, p_to_date date default null)
returns table(code text, amount numeric)
language sql stable set search_path = erp, public as $$
  with recursive lines as (select * from erp.fs_model_line_set(p_model)),
  up(code, ancestor) as (
    select l.code, l.code from lines l
    union all
    select up.code, p.parent from up join lines p on p.code = up.ancestor where p.parent is not null
  ), detail as (
    select c.line_code, sum(c.amount) as amount
    from erp.fs_model_classified_at(p_company, p_year, p_model, array[p_to_date]) c
    group by c.line_code
  )
  select up.ancestor, coalesce(sum(d.amount), 0)
  from up left join detail d on d.line_code = up.code
  group by up.ancestor;
$$;

create or replace function erp.fs_check_model(p_statement text, p_model text)
returns void language plpgsql stable set search_path = erp, public as $$
begin
  if not exists (select 1 from erp.fs_models where code = p_model) then
    raise exception 'Unknown balance sheet model: %', p_model;
  end if;
  if p_model <> 'pymes' and p_statement <> 'balance' then
    raise exception 'Only the balance sheet has other models (the income statement uses the SME model)';
  end if;
end $$;

-- financial_statement, fs_line_accounts y fs_line_anomalies reciben el modelo. Con 'pymes' (por defecto) hacen
-- EXACTAMENTE lo de antes: el mismo código, sin pasar por las tablas nuevas.
drop function if exists erp.financial_statement(uuid, integer, text, date, boolean);
create function erp.financial_statement(p_company uuid, p_year integer, p_statement text, p_to_date date default null,
                                        p_drafts boolean default false, p_model text default 'pymes')
returns table(code text, parent text, sort integer, level integer, label text, label_en text, is_total boolean,
              amount numeric, amount_prev numeric)
language plpgsql stable set jit = off as $$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  perform erp.fs_check_model(p_statement, p_model);
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  if p_model = 'pymes' then
    return query
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
    -- Ejercicio anterior: el Balance, a su cierre (null = completo); la PyG, hasta la misma fecha del año anterior
    left join erp.fs_amounts(p_company, p_year - 1, p_statement,
                             case when p_statement = 'balance' then null
                                  else (p_to_date - interval '1 year')::date end) prev on prev.code = l.code
    where l.statement = p_statement
    order by l.sort;
  else
    return query
    with recursive lines as (select * from erp.fs_model_line_set(p_model)),
    depth(code, level) as (
      select l.code, 0 from lines l where l.parent is null
      union all
      select c.code, d.level + 1 from depth d join lines c on c.parent = d.code
    )
    select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total,
           coalesce(n.amount, 0), coalesce(prev.amount, 0)
    from lines l
    join depth d on d.code = l.code
    left join erp.fs_model_amounts(p_company, p_year, p_model, p_to_date) n on n.code = l.code
    left join erp.fs_model_amounts(p_company, p_year - 1, p_model, null) prev on prev.code = l.code
    order by l.sort;
  end if;
  perform set_config('erp.simulate', v_prev, true);
end $$;

drop function if exists erp.fs_line_accounts(uuid, integer, text, text, date, boolean);
create function erp.fs_line_accounts(p_company uuid, p_year integer, p_statement text, p_code text,
                                     p_to_date date default null, p_drafts boolean default false,
                                     p_model text default 'pymes')
returns table(account_no text, account_name text, account_name_en text, line_code text, amount numeric)
language plpgsql stable set jit = off as $$
#variable_conflict use_column
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  perform erp.fs_check_model(p_statement, p_model);
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  if p_model = 'pymes' then
    return query
    with recursive below(code) as (
      select p_code
      union all
      select l.code from erp.fs_lines l join below b on l.parent = b.code where l.statement = p_statement
    )
    select c.account_no, c.account_name, c.account_name_en, c.line_code, c.amount
    from erp.fs_classified_accounts(p_company, p_year, p_statement, p_to_date) c
    where c.line_code in (select b.code from below b)
    order by c.account_no;
  else
    return query
    with recursive lines as (select * from erp.fs_model_line_set(p_model)),
    below(code) as (
      select p_code
      union all
      select l.code from lines l join below b on l.parent = b.code
    )
    select c.account_no, c.account_name, c.account_name_en, c.line_code, c.amount
    from erp.fs_model_classified_at(p_company, p_year, p_model, array[p_to_date]) c
    where c.line_code in (select b.code from below b)
    order by c.account_no;
  end if;
  perform set_config('erp.simulate', v_prev, true);
end $$;

drop function if exists erp.fs_line_anomalies(uuid, integer, date, boolean);
create function erp.fs_line_anomalies(p_company uuid, p_year integer, p_to date default null,
                                      p_drafts boolean default false, p_model text default 'pymes')
returns table(line_code text, account_no text, name text, name_en text, balance numeric, expected text, severity text,
              note text, note_en text)
language plpgsql stable set jit = off as $$
#variable_conflict use_column
declare v_prev_sim text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  perform erp.fs_check_model('balance', p_model);
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  select c.line_code, a.account_no, a.name, a.name_en, a.balance, a.expected, a.severity, a.note, a.note_en
  from erp.balance_anomalies(p_company, p_year, null, p_to, p_drafts) a
  join erp.fs_model_classified_at(p_company, p_year, p_model, array[p_to]) c on c.account_no = a.account_no
  order by c.line_code, a.account_no;
  perform set_config('erp.simulate', v_prev_sim, true);
end $$;

-- Sin sesión, ninguna función (0085): las nuevas, solo para quien tiene sesión
do $$
declare f text;
begin
  foreach f in array array[
    'erp.fs_abridged_line(text)', 'erp.fs_model_line_set(text)',
    'erp.fs_model_classified_at(uuid, integer, text, date[])', 'erp.fs_model_amounts(uuid, integer, text, date)',
    'erp.fs_check_model(text, text)',
    'erp.financial_statement(uuid, integer, text, date, boolean, text)',
    'erp.fs_line_accounts(uuid, integer, text, text, date, boolean, text)',
    'erp.fs_line_anomalies(uuid, integer, date, boolean, text)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ---------- 6. Base documental ----------
insert into erp.sources (key, issuer, url, checked, title, ref, title_en, ref_en) values
('pgcmodelos', 'BOE', 'https://www.boe.es/eli/es/rd/2007/11/16/1514/con', '2026-11-06', 'Real Decreto 1514/2007, Plan General de Contabilidad', 'Tercera parte: modelos normales y abreviados del balance', 'Royal Decree 1514/2007, Spanish chart of accounts (PGC)', 'Part three: full and abridged balance sheet models'),
('pgcpymes', 'BOE', 'https://www.boe.es/eli/es/rd/2007/11/16/1515/con', '2026-11-06', 'Real Decreto 1515/2007, Plan General de Contabilidad de Pequeñas y Medianas Empresas', 'Tercera parte: modelo de balance de PYMES', 'Royal Decree 1515/2007, chart of accounts for small and medium-sized enterprises', 'Part three: SME balance sheet model')
on conflict (key) do update set issuer = excluded.issuer, url = excluded.url, checked = excluded.checked,
  title = excluded.title, ref = excluded.ref, title_en = excluded.title_en, ref_en = excluded.ref_en;

-- ---------- 7. La nota del proveedor deudor vale para los tres modelos ----------
update erp.balance_rules set
  note = 'Proveedor con saldo deudor: se presenta en Otros deudores (en el modelo normal, Deudores varios), sin compensar con los demás proveedores. Revisa su mayor: si es un anticipo, llévalo a la 407; si es un pago duplicado o un abono pendiente, es un derecho de cobro.',
  note_en = 'Vendor with a debit balance: presented in Other receivables (Sundry receivables in the full model), not offset against the other vendors. Check its ledger: if it is an advance, move it to 407; if it is a duplicate payment or a pending credit, it is a receivable.'
where prefix = '400';
