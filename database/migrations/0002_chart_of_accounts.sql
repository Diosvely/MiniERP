-- =====================================================================
-- 0002 · CHART OF ACCOUNTS · Plan de cuentas (PGC 2007, grupos 1 a 7)
-- ---------------------------------------------------------------------
-- Dos niveles, igual que SAP y BC:
--   coa_template  ≈ SAP "Chart of Accounts" (SKA1)            → común a todas las empresas
--   gl_accounts   ≈ SAP account at company code level (SKB1)  ≈ BC "G/L Account"
--
-- account_type (igual que "Account Type" en BC):
--   heading  → grupos, subgrupos y cuentas del PGC (1-4 dígitos). NO admiten apuntes.   · cuenta de título
--   posting  → subcuentas de la empresa (ej. 43000001 Cliente X). SOLO aquí se apunta.  · subcuenta
--
-- account_category (masa patrimonial): asset, liability, equity, expense, income, mixed
-- Cada cuenta tiene nombre oficial en español (name) y traducción al inglés (name_en).
-- Grupos 8 y 9 (gastos/ingresos imputados al patrimonio neto) quedan para más adelante.
-- =====================================================================

create table erp.coa_template (
  account_no        text primary key check (account_no ~ '^[0-9]{1,4}$'),
  name              text not null,     -- nombre oficial PGC (español)
  name_en           text not null,     -- English translation
  level             smallint generated always as (length(account_no)) stored,
  account_group     smallint generated always as (left(account_no, 1)::smallint) stored,
  account_category  text not null default 'mixed'
                    check (account_category in ('asset', 'liability', 'equity', 'expense', 'income', 'mixed'))
);

create table erp.gl_accounts (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references erp.companies(id) on delete cascade,
  account_no        text not null check (account_no ~ '^[0-9]+$'),
  name              text not null,
  name_en           text,
  account_type      text not null check (account_type in ('heading', 'posting')),
  level             smallint generated always as (length(account_no)) stored,
  account_group     smallint generated always as (left(account_no, 1)::smallint) stored,
  template_account  text not null,     -- cuenta PGC de la que cuelga (ej. '430' para 43000001)
  account_category  text not null,
  blocked           boolean not null default false,
  created_at        timestamptz not null default now(),
  unique (company_id, account_no)
);
create index gl_accounts_company_no on erp.gl_accounts (company_id, account_no text_pattern_ops);

-- ---------------------------------------------------------------------
-- PGC data · Datos del PGC: (account_no, name, name_en)
-- ---------------------------------------------------------------------
insert into erp.coa_template (account_no, name, name_en) values
-- GROUP 1 ─ Basic financing · Financiación básica
('1', 'Financiación básica', 'Basic financing'),
('10', 'Capital', 'Capital'),
('100', 'Capital social', 'Share capital'),
('101', 'Fondo social', 'Social fund'),
('102', 'Capital', 'Capital (sole proprietor)'),
('103', 'Socios por desembolsos no exigidos', 'Uncalled share capital'),
('104', 'Socios por aportaciones no dinerarias pendientes', 'Shareholders, pending non-monetary contributions'),
('108', 'Acciones o participaciones propias en situaciones especiales', 'Treasury shares in special situations'),
('109', 'Acciones o participaciones propias para reducción de capital', 'Treasury shares for capital reduction'),
('11', 'Reservas y otros instrumentos de patrimonio', 'Reserves and other equity instruments'),
('110', 'Prima de emisión o asunción', 'Share premium'),
('111', 'Otros instrumentos de patrimonio neto', 'Other equity instruments'),
('112', 'Reserva legal', 'Legal reserve'),
('113', 'Reservas voluntarias', 'Voluntary reserves'),
('114', 'Reservas especiales', 'Special reserves'),
('118', 'Aportaciones de socios o propietarios', 'Shareholder contributions'),
('119', 'Diferencias por ajuste del capital a euros', 'Differences from redenomination of capital to euros'),
('12', 'Resultados pendientes de aplicación', 'Undistributed results'),
('120', 'Remanente', 'Retained earnings'),
('121', 'Resultados negativos de ejercicios anteriores', 'Prior years'' losses'),
('129', 'Resultado del ejercicio', 'Profit or loss for the year'),
('13', 'Subvenciones, donaciones y ajustes por cambios de valor', 'Grants, donations and valuation adjustments'),
('130', 'Subvenciones oficiales de capital', 'Official capital grants'),
('131', 'Donaciones y legados de capital', 'Capital donations and bequests'),
('132', 'Otras subvenciones, donaciones y legados', 'Other grants, donations and bequests'),
('137', 'Ingresos fiscales a distribuir en varios ejercicios', 'Tax income to be distributed over several years'),
('14', 'Provisiones', 'Provisions'),
('140', 'Provisión por retribuciones a largo plazo al personal', 'Provision for long-term employee benefits'),
('141', 'Provisión para impuestos', 'Provision for taxes'),
('142', 'Provisión para otras responsabilidades', 'Provision for other liabilities'),
('143', 'Provisión por desmantelamiento, retiro o rehabilitación del inmovilizado', 'Provision for dismantling, removal or restoration of fixed assets'),
('145', 'Provisión para actuaciones medioambientales', 'Provision for environmental actions'),
('146', 'Provisión para reestructuraciones', 'Provision for restructuring'),
('15', 'Deudas a largo plazo con características especiales', 'Long-term debts with special characteristics'),
('150', 'Acciones o participaciones a largo plazo consideradas como pasivos financieros', 'Long-term shares classified as financial liabilities'),
('16', 'Deudas a largo plazo con partes vinculadas', 'Long-term debts with related parties'),
('160', 'Deudas a largo plazo con entidades de crédito vinculadas', 'Long-term debts with related credit institutions'),
('161', 'Proveedores de inmovilizado a largo plazo, partes vinculadas', 'Long-term fixed asset suppliers, related parties'),
('162', 'Acreedores por arrendamiento financiero a largo plazo, partes vinculadas', 'Long-term finance lease payables, related parties'),
('163', 'Otras deudas a largo plazo con partes vinculadas', 'Other long-term debts with related parties'),
('17', 'Deudas a largo plazo por préstamos recibidos, empréstitos y otros conceptos', 'Long-term borrowings, bonds and other debts'),
('170', 'Deudas a largo plazo con entidades de crédito', 'Long-term debts with credit institutions'),
('171', 'Deudas a largo plazo', 'Long-term debts'),
('172', 'Deudas a largo plazo transformables en subvenciones, donaciones y legados', 'Long-term debts convertible into grants'),
('173', 'Proveedores de inmovilizado a largo plazo', 'Long-term fixed asset suppliers'),
('174', 'Acreedores por arrendamiento financiero a largo plazo', 'Long-term finance lease payables'),
('175', 'Efectos a pagar a largo plazo', 'Long-term notes payable'),
('177', 'Obligaciones y bonos', 'Bonds and debentures'),
('18', 'Pasivos por fianzas, garantías y otros conceptos a largo plazo', 'Long-term guarantees and other liabilities'),
('180', 'Fianzas recibidas a largo plazo', 'Long-term guarantees received'),
('181', 'Anticipos recibidos por ventas o prestaciones de servicios a largo plazo', 'Long-term advances received for sales or services'),
('185', 'Depósitos recibidos a largo plazo', 'Long-term deposits received'),
-- GROUP 2 ─ Non-current assets · Activo no corriente
('2', 'Activo no corriente', 'Non-current assets'),
('20', 'Inmovilizaciones intangibles', 'Intangible assets'),
('200', 'Investigación', 'Research'),
('201', 'Desarrollo', 'Development'),
('202', 'Concesiones administrativas', 'Administrative concessions'),
('203', 'Propiedad industrial', 'Industrial property'),
('204', 'Fondo de comercio', 'Goodwill'),
('205', 'Derechos de traspaso', 'Leasehold transfer rights'),
('206', 'Aplicaciones informáticas', 'Software'),
('209', 'Anticipos para inmovilizaciones intangibles', 'Advances for intangible assets'),
('21', 'Inmovilizaciones materiales', 'Property, plant and equipment'),
('210', 'Terrenos y bienes naturales', 'Land and natural resources'),
('211', 'Construcciones', 'Buildings'),
('212', 'Instalaciones técnicas', 'Technical installations'),
('213', 'Maquinaria', 'Machinery'),
('214', 'Utillaje', 'Tools'),
('215', 'Otras instalaciones', 'Other installations'),
('216', 'Mobiliario', 'Furniture'),
('217', 'Equipos para procesos de información', 'Computer equipment'),
('218', 'Elementos de transporte', 'Vehicles'),
('219', 'Otro inmovilizado material', 'Other property, plant and equipment'),
('22', 'Inversiones inmobiliarias', 'Investment property'),
('220', 'Inversiones en terrenos y bienes naturales', 'Investment in land and natural resources'),
('221', 'Inversiones en construcciones', 'Investment in buildings'),
('23', 'Inmovilizaciones materiales en curso', 'Property, plant and equipment under construction'),
('231', 'Construcciones en curso', 'Buildings under construction'),
('232', 'Instalaciones técnicas en montaje', 'Technical installations being assembled'),
('233', 'Maquinaria en montaje', 'Machinery being assembled'),
('237', 'Equipos para procesos de información en montaje', 'Computer equipment being assembled'),
('239', 'Anticipos para inmovilizaciones materiales', 'Advances for property, plant and equipment'),
('24', 'Inversiones financieras a largo plazo en partes vinculadas', 'Long-term investments in related parties'),
('240', 'Participaciones a largo plazo en partes vinculadas', 'Long-term equity investments in related parties'),
('241', 'Valores representativos de deuda a largo plazo de partes vinculadas', 'Long-term debt securities of related parties'),
('242', 'Créditos a largo plazo a partes vinculadas', 'Long-term loans to related parties'),
('25', 'Otras inversiones financieras a largo plazo', 'Other long-term financial investments'),
('250', 'Inversiones financieras a largo plazo en instrumentos de patrimonio', 'Long-term investments in equity instruments'),
('251', 'Valores representativos de deuda a largo plazo', 'Long-term debt securities'),
('252', 'Créditos a largo plazo', 'Long-term loans'),
('253', 'Créditos a largo plazo por enajenación de inmovilizado', 'Long-term receivables from sale of fixed assets'),
('254', 'Créditos a largo plazo al personal', 'Long-term loans to employees'),
('258', 'Imposiciones a largo plazo', 'Long-term time deposits'),
('26', 'Fianzas y depósitos constituidos a largo plazo', 'Long-term guarantees and deposits given'),
('260', 'Fianzas constituidas a largo plazo', 'Long-term guarantees given'),
('265', 'Depósitos constituidos a largo plazo', 'Long-term deposits given'),
('28', 'Amortización acumulada del inmovilizado', 'Accumulated depreciation and amortisation'),
('280', 'Amortización acumulada del inmovilizado intangible', 'Accumulated amortisation of intangible assets'),
('281', 'Amortización acumulada del inmovilizado material', 'Accumulated depreciation of property, plant and equipment'),
('282', 'Amortización acumulada de las inversiones inmobiliarias', 'Accumulated depreciation of investment property'),
('29', 'Deterioro de valor de activos no corrientes', 'Impairment of non-current assets'),
('290', 'Deterioro de valor del inmovilizado intangible', 'Impairment of intangible assets'),
('291', 'Deterioro de valor del inmovilizado material', 'Impairment of property, plant and equipment'),
('292', 'Deterioro de valor de las inversiones inmobiliarias', 'Impairment of investment property'),
-- GROUP 3 ─ Inventories · Existencias
('3', 'Existencias', 'Inventories'),
('30', 'Comerciales', 'Merchandise'),
('300', 'Mercaderías', 'Merchandise'),
('31', 'Materias primas', 'Raw materials'),
('310', 'Materias primas', 'Raw materials'),
('32', 'Otros aprovisionamientos', 'Other supplies'),
('320', 'Elementos y conjuntos incorporables', 'Components'),
('321', 'Combustibles', 'Fuel'),
('322', 'Repuestos', 'Spare parts'),
('325', 'Materiales diversos', 'Sundry materials'),
('326', 'Embalajes', 'Packaging'),
('327', 'Envases', 'Containers'),
('328', 'Material de oficina', 'Office supplies'),
('33', 'Productos en curso', 'Work in progress'),
('330', 'Productos en curso', 'Work in progress'),
('34', 'Productos semiterminados', 'Semi-finished goods'),
('340', 'Productos semiterminados', 'Semi-finished goods'),
('35', 'Productos terminados', 'Finished goods'),
('350', 'Productos terminados', 'Finished goods'),
('36', 'Subproductos, residuos y materiales recuperados', 'By-products, waste and recovered materials'),
('360', 'Subproductos', 'By-products'),
('365', 'Residuos', 'Waste'),
('368', 'Materiales recuperados', 'Recovered materials'),
('39', 'Deterioro de valor de las existencias', 'Impairment of inventories'),
('390', 'Deterioro de valor de las mercaderías', 'Impairment of merchandise'),
('391', 'Deterioro de valor de las materias primas', 'Impairment of raw materials'),
('392', 'Deterioro de valor de otros aprovisionamientos', 'Impairment of other supplies'),
('393', 'Deterioro de valor de los productos en curso', 'Impairment of work in progress'),
('394', 'Deterioro de valor de los productos semiterminados', 'Impairment of semi-finished goods'),
('395', 'Deterioro de valor de los productos terminados', 'Impairment of finished goods'),
('396', 'Deterioro de valor de los subproductos, residuos y materiales recuperados', 'Impairment of by-products, waste and recovered materials'),
-- GROUP 4 ─ Trade payables and receivables · Acreedores y deudores
('4', 'Acreedores y deudores por operaciones comerciales', 'Trade payables and receivables'),
('40', 'Proveedores', 'Suppliers'),
('400', 'Proveedores', 'Suppliers'),
('401', 'Proveedores, efectos comerciales a pagar', 'Suppliers, notes payable'),
('403', 'Proveedores, empresas del grupo', 'Suppliers, group companies'),
('404', 'Proveedores, empresas asociadas', 'Suppliers, associates'),
('405', 'Proveedores, otras partes vinculadas', 'Suppliers, other related parties'),
('406', 'Envases y embalajes a devolver a proveedores', 'Returnable packaging to suppliers'),
('407', 'Anticipos a proveedores', 'Advances to suppliers'),
('41', 'Acreedores varios', 'Sundry creditors'),
('410', 'Acreedores por prestaciones de servicios', 'Creditors for services'),
('411', 'Acreedores, efectos comerciales a pagar', 'Creditors, notes payable'),
('419', 'Acreedores por operaciones en común', 'Creditors for joint operations'),
('43', 'Clientes', 'Customers'),
('430', 'Clientes', 'Customers'),
('431', 'Clientes, efectos comerciales a cobrar', 'Customers, notes receivable'),
('432', 'Clientes, operaciones de factoring', 'Customers, factoring'),
('433', 'Clientes, empresas del grupo', 'Customers, group companies'),
('434', 'Clientes, empresas asociadas', 'Customers, associates'),
('435', 'Clientes, otras partes vinculadas', 'Customers, other related parties'),
('436', 'Clientes de dudoso cobro', 'Doubtful customers'),
('437', 'Envases y embalajes a devolver por clientes', 'Returnable packaging from customers'),
('438', 'Anticipos de clientes', 'Advances from customers'),
('44', 'Deudores varios', 'Sundry debtors'),
('440', 'Deudores', 'Debtors'),
('441', 'Deudores, efectos comerciales a cobrar', 'Debtors, notes receivable'),
('446', 'Deudores de dudoso cobro', 'Doubtful debtors'),
('449', 'Deudores por operaciones en común', 'Debtors for joint operations'),
('46', 'Personal', 'Personnel'),
('460', 'Anticipos de remuneraciones', 'Salary advances'),
('465', 'Remuneraciones pendientes de pago', 'Salaries payable'),
('466', 'Remuneraciones mediante sistemas de aportación definida pendientes de pago', 'Defined contribution plans payable'),
('47', 'Administraciones públicas', 'Public administrations'),
('470', 'Hacienda Pública, deudora por diversos conceptos', 'Tax receivables, other'),
('4700', 'Hacienda Pública, deudora por IVA', 'VAT receivable'),
('4708', 'Hacienda Pública, deudora por subvenciones concedidas', 'Grants receivable'),
('4709', 'Hacienda Pública, deudora por devolución de impuestos', 'Tax refunds receivable'),
('471', 'Organismos de la Seguridad Social, deudores', 'Social Security receivable'),
('472', 'Hacienda Pública, IVA soportado', 'Input VAT'),
('473', 'Hacienda Pública, retenciones y pagos a cuenta', 'Withholdings and payments on account'),
('474', 'Activos por impuesto diferido', 'Deferred tax assets'),
('475', 'Hacienda Pública, acreedora por conceptos fiscales', 'Tax payables, other'),
('4750', 'Hacienda Pública, acreedora por IVA', 'VAT payable'),
('4751', 'Hacienda Pública, acreedora por retenciones practicadas', 'Withholdings payable'),
('4752', 'Hacienda Pública, acreedora por impuesto sobre sociedades', 'Corporate income tax payable'),
('4758', 'Hacienda Pública, acreedora por subvenciones a reintegrar', 'Grants to be repaid'),
('476', 'Organismos de la Seguridad Social, acreedores', 'Social Security payable'),
('477', 'Hacienda Pública, IVA repercutido', 'Output VAT'),
('479', 'Pasivos por diferencias temporarias imponibles', 'Deferred tax liabilities'),
('48', 'Ajustes por periodificación', 'Accruals and deferrals'),
('480', 'Gastos anticipados', 'Prepaid expenses'),
('485', 'Ingresos anticipados', 'Deferred income'),
('49', 'Deterioro de valor de créditos comerciales y provisiones a corto plazo', 'Impairment of trade receivables and short-term provisions'),
('490', 'Deterioro de valor de créditos por operaciones comerciales', 'Impairment of trade receivables'),
('499', 'Provisiones por operaciones comerciales', 'Provisions for trade operations'),
-- GROUP 5 ─ Financial accounts · Cuentas financieras
('5', 'Cuentas financieras', 'Financial accounts'),
('52', 'Deudas a corto plazo por préstamos recibidos y otros conceptos', 'Short-term borrowings and other debts'),
('520', 'Deudas a corto plazo con entidades de crédito', 'Short-term debts with credit institutions'),
('5200', 'Préstamos a corto plazo de entidades de crédito', 'Short-term bank loans'),
('5201', 'Deudas a corto plazo por crédito dispuesto', 'Short-term credit lines drawn'),
('5208', 'Deudas por efectos descontados', 'Debts for discounted bills'),
('521', 'Deudas a corto plazo', 'Short-term debts'),
('523', 'Proveedores de inmovilizado a corto plazo', 'Short-term fixed asset suppliers'),
('524', 'Acreedores por arrendamiento financiero a corto plazo', 'Short-term finance lease payables'),
('525', 'Efectos a pagar a corto plazo', 'Short-term notes payable'),
('526', 'Dividendo activo a pagar', 'Dividends payable'),
('527', 'Intereses a corto plazo de deudas con entidades de crédito', 'Short-term interest payable to credit institutions'),
('528', 'Intereses a corto plazo de deudas', 'Short-term interest payable'),
('529', 'Provisiones a corto plazo', 'Short-term provisions'),
('54', 'Otras inversiones financieras a corto plazo', 'Other short-term financial investments'),
('540', 'Inversiones financieras a corto plazo en instrumentos de patrimonio', 'Short-term investments in equity instruments'),
('541', 'Valores representativos de deuda a corto plazo', 'Short-term debt securities'),
('542', 'Créditos a corto plazo', 'Short-term loans'),
('543', 'Créditos a corto plazo por enajenación de inmovilizado', 'Short-term receivables from sale of fixed assets'),
('544', 'Créditos a corto plazo al personal', 'Short-term loans to employees'),
('546', 'Intereses a corto plazo de valores representativos de deudas', 'Short-term interest on debt securities'),
('547', 'Intereses a corto plazo de créditos', 'Short-term interest on loans'),
('548', 'Imposiciones a corto plazo', 'Short-term time deposits'),
('55', 'Otras cuentas no bancarias', 'Other non-bank accounts'),
('550', 'Titular de la explotación', 'Owner''s account'),
('551', 'Cuenta corriente con socios y administradores', 'Current account with shareholders and directors'),
('552', 'Cuenta corriente con otras personas y entidades vinculadas', 'Current account with other related parties'),
('555', 'Partidas pendientes de aplicación', 'Suspense account'),
('557', 'Dividendo activo a cuenta', 'Interim dividend'),
('558', 'Socios por desembolsos exigidos', 'Called-up share capital receivable'),
('56', 'Fianzas y depósitos recibidos y constituidos a corto plazo y ajustes por periodificación', 'Short-term guarantees, deposits and accruals'),
('560', 'Fianzas recibidas a corto plazo', 'Short-term guarantees received'),
('561', 'Depósitos recibidos a corto plazo', 'Short-term deposits received'),
('565', 'Fianzas constituidas a corto plazo', 'Short-term guarantees given'),
('566', 'Depósitos constituidos a corto plazo', 'Short-term deposits given'),
('567', 'Intereses pagados por anticipado', 'Prepaid interest'),
('568', 'Intereses cobrados por anticipado', 'Interest received in advance'),
('57', 'Tesorería', 'Cash and cash equivalents'),
('570', 'Caja, euros', 'Cash, euros'),
('571', 'Caja, moneda extranjera', 'Cash, foreign currency'),
('572', 'Bancos e instituciones de crédito c/c vista, euros', 'Banks, current accounts, euros'),
('573', 'Bancos e instituciones de crédito c/c vista, moneda extranjera', 'Banks, current accounts, foreign currency'),
('574', 'Bancos e instituciones de crédito, cuentas de ahorro, euros', 'Banks, savings accounts, euros'),
('576', 'Inversiones a corto plazo de gran liquidez', 'Highly liquid short-term investments'),
-- GROUP 6 ─ Purchases and expenses · Compras y gastos
('6', 'Compras y gastos', 'Purchases and expenses'),
('60', 'Compras', 'Purchases'),
('600', 'Compras de mercaderías', 'Purchases of merchandise'),
('601', 'Compras de materias primas', 'Purchases of raw materials'),
('602', 'Compras de otros aprovisionamientos', 'Purchases of other supplies'),
('606', 'Descuentos sobre compras por pronto pago', 'Early payment discounts on purchases'),
('607', 'Trabajos realizados por otras empresas', 'Work performed by other companies'),
('608', 'Devoluciones de compras y operaciones similares', 'Purchase returns'),
('609', 'Rappels por compras', 'Volume rebates on purchases'),
('61', 'Variación de existencias', 'Change in inventories'),
('610', 'Variación de existencias de mercaderías', 'Change in merchandise inventories'),
('611', 'Variación de existencias de materias primas', 'Change in raw material inventories'),
('612', 'Variación de existencias de otros aprovisionamientos', 'Change in other supplies inventories'),
('62', 'Servicios exteriores', 'External services'),
('620', 'Gastos en investigación y desarrollo del ejercicio', 'Research and development expenses'),
('621', 'Arrendamientos y cánones', 'Rents and royalties'),
('622', 'Reparaciones y conservación', 'Repairs and maintenance'),
('623', 'Servicios de profesionales independientes', 'Professional services'),
('624', 'Transportes', 'Transport'),
('625', 'Primas de seguros', 'Insurance premiums'),
('626', 'Servicios bancarios y similares', 'Bank services and similar'),
('627', 'Publicidad, propaganda y relaciones públicas', 'Advertising and public relations'),
('628', 'Suministros', 'Utilities'),
('629', 'Otros servicios', 'Other services'),
('63', 'Tributos', 'Taxes'),
('630', 'Impuesto sobre beneficios', 'Income tax'),
('631', 'Otros tributos', 'Other taxes'),
('634', 'Ajustes negativos en la imposición indirecta', 'Negative adjustments to indirect taxation'),
('636', 'Devolución de impuestos', 'Tax refunds'),
('639', 'Ajustes positivos en la imposición indirecta', 'Positive adjustments to indirect taxation'),
('64', 'Gastos de personal', 'Staff costs'),
('640', 'Sueldos y salarios', 'Wages and salaries'),
('641', 'Indemnizaciones', 'Severance payments'),
('642', 'Seguridad Social a cargo de la empresa', 'Employer social security contributions'),
('643', 'Retribuciones a largo plazo mediante sistemas de aportación definida', 'Defined contribution pension costs'),
('649', 'Otros gastos sociales', 'Other employee benefits expenses'),
('65', 'Otros gastos de gestión', 'Other operating expenses'),
('650', 'Pérdidas de créditos comerciales incobrables', 'Bad debt losses'),
('651', 'Resultados de operaciones en común', 'Results of joint operations'),
('659', 'Otras pérdidas en gestión corriente', 'Other operating losses'),
('66', 'Gastos financieros', 'Finance costs'),
('660', 'Gastos financieros por actualización de provisiones', 'Finance costs from provision discounting'),
('661', 'Intereses de obligaciones y bonos', 'Interest on bonds and debentures'),
('662', 'Intereses de deudas', 'Interest on debts'),
('663', 'Pérdidas por valoración de instrumentos financieros por su valor razonable', 'Losses from fair value measurement of financial instruments'),
('665', 'Intereses por descuento de efectos y operaciones de factoring', 'Interest on discounted bills and factoring'),
('666', 'Pérdidas en participaciones y valores representativos de deuda', 'Losses on investments and debt securities'),
('667', 'Pérdidas de créditos no comerciales', 'Losses on non-trade receivables'),
('668', 'Diferencias negativas de cambio', 'Exchange losses'),
('669', 'Otros gastos financieros', 'Other finance costs'),
('67', 'Pérdidas procedentes de activos no corrientes y gastos excepcionales', 'Losses on non-current assets and exceptional expenses'),
('670', 'Pérdidas procedentes del inmovilizado intangible', 'Losses on intangible assets'),
('671', 'Pérdidas procedentes del inmovilizado material', 'Losses on property, plant and equipment'),
('672', 'Pérdidas procedentes de las inversiones inmobiliarias', 'Losses on investment property'),
('678', 'Gastos excepcionales', 'Exceptional expenses'),
('68', 'Dotaciones para amortizaciones', 'Depreciation and amortisation'),
('680', 'Amortización del inmovilizado intangible', 'Amortisation of intangible assets'),
('681', 'Amortización del inmovilizado material', 'Depreciation of property, plant and equipment'),
('682', 'Amortización de las inversiones inmobiliarias', 'Depreciation of investment property'),
('69', 'Pérdidas por deterioro y otras dotaciones', 'Impairment losses and other provisions'),
('690', 'Pérdidas por deterioro del inmovilizado intangible', 'Impairment losses on intangible assets'),
('691', 'Pérdidas por deterioro del inmovilizado material', 'Impairment losses on property, plant and equipment'),
('692', 'Pérdidas por deterioro de las inversiones inmobiliarias', 'Impairment losses on investment property'),
('693', 'Pérdidas por deterioro de existencias', 'Impairment losses on inventories'),
('694', 'Pérdidas por deterioro de créditos por operaciones comerciales', 'Impairment losses on trade receivables'),
('695', 'Dotación a la provisión por operaciones comerciales', 'Provision for trade operations'),
-- GROUP 7 ─ Sales and income · Ventas e ingresos
('7', 'Ventas e ingresos', 'Sales and income'),
('70', 'Ventas de mercaderías, de producción propia, de servicios, etc.', 'Sales of goods, finished products and services'),
('700', 'Ventas de mercaderías', 'Sales of merchandise'),
('701', 'Ventas de productos terminados', 'Sales of finished goods'),
('702', 'Ventas de productos semiterminados', 'Sales of semi-finished goods'),
('703', 'Ventas de subproductos y residuos', 'Sales of by-products and waste'),
('704', 'Ventas de envases y embalajes', 'Sales of packaging'),
('705', 'Prestaciones de servicios', 'Services rendered'),
('706', 'Descuentos sobre ventas por pronto pago', 'Early payment discounts on sales'),
('708', 'Devoluciones de ventas y operaciones similares', 'Sales returns'),
('709', 'Rappels sobre ventas', 'Volume rebates on sales'),
('71', 'Variación de existencias', 'Change in inventories'),
('710', 'Variación de existencias de productos en curso', 'Change in work in progress'),
('711', 'Variación de existencias de productos semiterminados', 'Change in semi-finished goods'),
('712', 'Variación de existencias de productos terminados', 'Change in finished goods'),
('713', 'Variación de existencias de subproductos, residuos y materiales recuperados', 'Change in by-products, waste and recovered materials'),
('73', 'Trabajos realizados para la empresa', 'Own work capitalised'),
('730', 'Trabajos realizados para el inmovilizado intangible', 'Own work capitalised as intangible assets'),
('731', 'Trabajos realizados para el inmovilizado material', 'Own work capitalised as property, plant and equipment'),
('732', 'Trabajos realizados en inversiones inmobiliarias', 'Own work capitalised as investment property'),
('733', 'Trabajos realizados para el inmovilizado material en curso', 'Own work capitalised as assets under construction'),
('74', 'Subvenciones, donaciones y legados', 'Grants, donations and bequests'),
('740', 'Subvenciones, donaciones y legados a la explotación', 'Operating grants'),
('746', 'Subvenciones, donaciones y legados de capital transferidos al resultado del ejercicio', 'Capital grants transferred to profit or loss'),
('747', 'Otras subvenciones, donaciones y legados transferidos al resultado del ejercicio', 'Other grants transferred to profit or loss'),
('75', 'Otros ingresos de gestión', 'Other operating income'),
('751', 'Resultados de operaciones en común', 'Results of joint operations'),
('752', 'Ingresos por arrendamientos', 'Rental income'),
('753', 'Ingresos de propiedad industrial cedida en explotación', 'Industrial property income'),
('754', 'Ingresos por comisiones', 'Commission income'),
('755', 'Ingresos por servicios al personal', 'Income from services to employees'),
('759', 'Ingresos por servicios diversos', 'Income from sundry services'),
('76', 'Ingresos financieros', 'Finance income'),
('760', 'Ingresos de participaciones en instrumentos de patrimonio', 'Income from equity investments'),
('761', 'Ingresos de valores representativos de deuda', 'Income from debt securities'),
('762', 'Ingresos de créditos', 'Income from loans'),
('763', 'Beneficios por valoración de instrumentos financieros por su valor razonable', 'Gains from fair value measurement of financial instruments'),
('766', 'Beneficios en participaciones y valores representativos de deuda', 'Gains on investments and debt securities'),
('768', 'Diferencias positivas de cambio', 'Exchange gains'),
('769', 'Otros ingresos financieros', 'Other finance income'),
('77', 'Beneficios procedentes de activos no corrientes e ingresos excepcionales', 'Gains on non-current assets and exceptional income'),
('770', 'Beneficios procedentes del inmovilizado intangible', 'Gains on intangible assets'),
('771', 'Beneficios procedentes del inmovilizado material', 'Gains on property, plant and equipment'),
('772', 'Beneficios procedentes de las inversiones inmobiliarias', 'Gains on investment property'),
('778', 'Ingresos excepcionales', 'Exceptional income'),
('79', 'Excesos y aplicaciones de provisiones y de pérdidas por deterioro', 'Reversals of provisions and impairment losses'),
('790', 'Reversión del deterioro del inmovilizado intangible', 'Reversal of impairment of intangible assets'),
('791', 'Reversión del deterioro del inmovilizado material', 'Reversal of impairment of property, plant and equipment'),
('792', 'Reversión del deterioro de las inversiones inmobiliarias', 'Reversal of impairment of investment property'),
('793', 'Reversión del deterioro de existencias', 'Reversal of impairment of inventories'),
('794', 'Reversión del deterioro de créditos por operaciones comerciales', 'Reversal of impairment of trade receivables'),
('795', 'Exceso de provisiones', 'Excess provisions');

-- Masa patrimonial de cada cuenta · Account category
update erp.coa_template set account_category = case
  when account_no = '1'                               then 'mixed'
  when account_no ~ '^1[0-3]'                         then 'equity'
  when account_no ~ '^1'                              then 'liability'
  when account_no ~ '^[23]'                           then 'asset'    -- 28x, 29x, 39x: correctoras de activo (contra-assets)
  when account_no ~ '^(40|41|475|476|477|479|485|499)' then 'liability'
  when account_no ~ '^(43|44|460|470|471|472|473|474|480|490)' then 'asset'
  when account_no ~ '^(465|466)'                      then 'liability'
  when account_no ~ '^(52|560|561|568)'               then 'liability'
  when account_no ~ '^(54|57|565|566|567)'            then 'asset'
  when account_no ~ '^6'                              then 'expense'
  when account_no ~ '^7'                              then 'income'
  else 'mixed'                                        -- grupos/subgrupos 4, 5, 47, 55, 56…
end;

-- ---------------------------------------------------------------------
-- Al crear una empresa se copia el PGC como cuentas 'heading'
-- ---------------------------------------------------------------------
create or replace function erp.tg_company_copy_coa()
returns trigger language plpgsql security definer set search_path = erp, public as $$
begin
  insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
  select new.id, t.account_no, t.name, t.name_en, 'heading', t.account_no, t.account_category
  from erp.coa_template t;
  return new;
end $$;

create trigger company_copy_coa
  after insert on erp.companies
  for each row execute function erp.tg_company_copy_coa();

-- ---------------------------------------------------------------------
-- Alta de subcuentas: comprueba la longitud y la cuelga de la cuenta PGC más larga que sea prefijo.
-- Ej (8 dígitos): 43000001 → 430 · 47510001 → 4751 · 57200001 → 572
-- ---------------------------------------------------------------------
create or replace function erp.tg_gl_account_validate()
returns trigger language plpgsql as $$
declare
  v_digits  smallint;
  v_parent  erp.coa_template;
begin
  if new.account_type = 'heading' then
    return new;  -- las copia el sistema desde la plantilla
  end if;

  select posting_account_digits into v_digits from erp.companies where id = new.company_id;
  if length(new.account_no) <> v_digits then
    raise exception 'Posting account % must have % digits', new.account_no, v_digits;
  end if;

  select * into v_parent
  from erp.coa_template
  where new.account_no like account_no || '%' and level >= 3
  order by level desc
  limit 1;

  if v_parent is null then
    raise exception 'Posting account % does not belong to any PGC account (3 or 4 digits)', new.account_no;
  end if;

  new.template_account := v_parent.account_no;
  new.account_category := v_parent.account_category;
  return new;
end $$;

create trigger gl_account_validate
  before insert or update of account_no, account_type on erp.gl_accounts
  for each row execute function erp.tg_gl_account_validate();

-- Atajo: crea una subcuenta y devuelve su id
create or replace function erp.create_posting_account(
  p_company uuid, p_account_no text, p_name text, p_name_en text default null)
returns uuid language sql as $$
  insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
  values (p_company, p_account_no, p_name, p_name_en, 'posting', '', '')   -- el trigger rellena template_account y account_category
  returning id;
$$;
