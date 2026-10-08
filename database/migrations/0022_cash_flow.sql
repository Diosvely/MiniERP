-- =====================================================================
-- 0022 · CASH FLOW STATEMENT · Estado de flujos de efectivo (Modo auditor, parte 2)
-- ---------------------------------------------------------------------
-- Explica por qué la tesorería (grupo 57) pasó de X a Y en el ejercicio, por los DOS métodos:
--
--   INDIRECTO (el del modelo normal del PGC): parte del resultado antes de impuestos, quita lo que no es dinero
--     (amortizaciones, deterioros, resultados por bajas…), suma las variaciones del capital corriente y separa
--     intereses e impuesto. Inversión y financiación salen de las variaciones de sus cuentas de balance.
--   DIRECTO (el que recomienda la NIC 7): cada asiento que mueve la 57 se clasifica por su CONTRAPARTIDA
--     (cobro de un cliente, pago a un proveedor, nómina, préstamo…).
--
-- Cuadre del auditor:  directo = indirecto = variación de la 57  (efectivo final − efectivo inicial).
--
-- Cómo se consigue que cuadre SIEMPRE: cada subcuenta tiene una "línea de destino" (erp.cf_mapping) y su flujo es
-- −(variación de su saldo) en el año. Como cada asiento cuadra, la suma de todas las cuentas que no son la 57 es
-- exactamente la variación de la 57. Las partidas de la PyG que no son de explotación (amortización, resultados por
-- bajas, intereses…) están dentro del resultado (línea 1) y se quitan en los AJUSTES (línea 2) para llevarlas a su sitio.
-- Solo cuentan los asientos normales: ni apertura, ni regularización, ni cierre.
-- =====================================================================

create table erp.cf_lines (
  method    text not null check (method in ('indirect', 'direct')),
  code      text not null,
  parent    text,
  sort      int  not null,
  label     text not null,
  label_en  text not null,
  is_total  boolean not null default false,
  primary key (method, code)
);

insert into erp.cf_lines (method, code, parent, sort, label, label_en, is_total) values
-- ---------- MÉTODO INDIRECTO (modelo normal del PGC) ----------
('indirect', 'IA',   'IE', 100, 'A) FLUJOS DE EFECTIVO DE LAS ACTIVIDADES DE EXPLOTACIÓN', 'A) CASH FLOWS FROM OPERATING ACTIVITIES', true),
('indirect', 'IA1',  'IA', 110, '1. Resultado del ejercicio antes de impuestos', '1. Profit (loss) before tax', false),
('indirect', 'IA2',  'IA', 120, '2. Ajustes del resultado', '2. Adjustments to profit', true),
('indirect', 'IA2a', 'IA2', 121, 'a) Amortización del inmovilizado (+)', 'a) Depreciation and amortisation (+)', false),
('indirect', 'IA2b', 'IA2', 122, 'b) Correcciones valorativas por deterioro (+/−)', 'b) Impairment losses (+/−)', false),
('indirect', 'IA2c', 'IA2', 123, 'c) Variación de provisiones (+/−)', 'c) Change in provisions (+/−)', false),
('indirect', 'IA2d', 'IA2', 124, 'd) Imputación de subvenciones (−)', 'd) Grants recognised in profit (−)', false),
('indirect', 'IA2e', 'IA2', 125, 'e) Resultados por bajas y enajenaciones del inmovilizado (+/−)', 'e) Gains (losses) on disposal of fixed assets (+/−)', false),
('indirect', 'IA2f', 'IA2', 126, 'f) Resultados por bajas y enajenaciones de instrumentos financieros (+/−)', 'f) Gains (losses) on disposal of financial instruments (+/−)', false),
('indirect', 'IA2g', 'IA2', 127, 'g) Ingresos financieros (−)', 'g) Finance income (−)', false),
('indirect', 'IA2h', 'IA2', 128, 'h) Gastos financieros (+)', 'h) Finance costs (+)', false),
('indirect', 'IA3',  'IA', 130, '3. Cambios en el capital corriente', '3. Changes in working capital', true),
('indirect', 'IA3a', 'IA3', 131, 'a) Existencias (+/−)', 'a) Inventories (+/−)', false),
('indirect', 'IA3b', 'IA3', 132, 'b) Deudores y otras cuentas a cobrar (+/−)', 'b) Trade and other receivables (+/−)', false),
('indirect', 'IA3c', 'IA3', 133, 'c) Otros activos corrientes (+/−)', 'c) Other current assets (+/−)', false),
('indirect', 'IA3d', 'IA3', 134, 'd) Acreedores y otras cuentas a pagar (+/−)', 'd) Trade and other payables (+/−)', false),
('indirect', 'IA3e', 'IA3', 135, 'e) Otros pasivos corrientes (+/−)', 'e) Other current liabilities (+/−)', false),
('indirect', 'IA4',  'IA', 140, '4. Otros flujos de efectivo de las actividades de explotación', '4. Other cash flows from operating activities', true),
('indirect', 'IA4a', 'IA4', 141, 'a) Pagos de intereses (−)', 'a) Interest paid (−)', false),
('indirect', 'IA4b', 'IA4', 142, 'b) Cobros de dividendos (+)', 'b) Dividends received (+)', false),
('indirect', 'IA4c', 'IA4', 143, 'c) Cobros de intereses (+)', 'c) Interest received (+)', false),
('indirect', 'IA4d', 'IA4', 144, 'd) Cobros (pagos) por impuesto sobre beneficios (+/−)', 'd) Income tax received (paid) (+/−)', false),
('indirect', 'IB',   'IE', 200, 'B) FLUJOS DE EFECTIVO DE LAS ACTIVIDADES DE INVERSIÓN', 'B) CASH FLOWS FROM INVESTING ACTIVITIES', true),
('indirect', 'IB1',  'IB', 210, 'Inmovilizado intangible', 'Intangible assets', false),
('indirect', 'IB2',  'IB', 220, 'Inmovilizado material', 'Property, plant and equipment', false),
('indirect', 'IB3',  'IB', 230, 'Inversiones inmobiliarias', 'Investment property', false),
('indirect', 'IB4',  'IB', 240, 'Inversiones financieras y otros activos', 'Financial investments and other assets', false),
('indirect', 'IB5',  'IB', 250, 'Proveedores de inmovilizado (pagos aplazados)', 'Fixed-asset suppliers (deferred payments)', false),
('indirect', 'IC',   'IE', 300, 'C) FLUJOS DE EFECTIVO DE LAS ACTIVIDADES DE FINANCIACIÓN', 'C) CASH FLOWS FROM FINANCING ACTIVITIES', true),
('indirect', 'IC1',  'IC', 310, '9. Cobros y pagos por instrumentos de patrimonio', '9. Equity instruments received (paid)', false),
('indirect', 'IC2',  'IC', 320, '10. Cobros y pagos por instrumentos de pasivo financiero', '10. Financial liabilities received (paid)', false),
('indirect', 'IC3',  'IC', 330, '11. Pagos por dividendos y remuneraciones de otros instrumentos de patrimonio', '11. Dividends paid', false),
('indirect', 'IE',   null, 400, 'E) AUMENTO / DISMINUCIÓN NETA DEL EFECTIVO (A + B + C)', 'E) NET INCREASE / DECREASE IN CASH (A + B + C)', true),
-- ---------- MÉTODO DIRECTO (NIC 7) ----------
('direct', 'DA',   'DE', 100, 'A) FLUJOS DE EFECTIVO DE LAS ACTIVIDADES DE EXPLOTACIÓN', 'A) CASH FLOWS FROM OPERATING ACTIVITIES', true),
('direct', 'DA1',  'DA', 110, 'Cobros de clientes y deudores', 'Receipts from customers and debtors', false),
('direct', 'DA2',  'DA', 120, 'Pagos a proveedores y acreedores', 'Payments to suppliers and creditors', false),
('direct', 'DA3',  'DA', 130, 'Pagos al personal', 'Payments to employees', false),
('direct', 'DA4',  'DA', 140, 'Pagos y cobros de tributos (IVA / IGIC, retenciones, Seguridad Social…)', 'Taxes paid and refunded (VAT / IGIC, withholdings, social security…)', false),
('direct', 'DA5',  'DA', 150, 'Intereses y dividendos', 'Interest and dividends', false),
('direct', 'DA6',  'DA', 160, 'Impuesto sobre beneficios', 'Income tax', false),
('direct', 'DA7',  'DA', 170, 'Otros cobros y pagos de explotación', 'Other operating receipts and payments', false),
('direct', 'DB',   'DE', 200, 'B) FLUJOS DE EFECTIVO DE LAS ACTIVIDADES DE INVERSIÓN', 'B) CASH FLOWS FROM INVESTING ACTIVITIES', true),
('direct', 'DB1',  'DB', 210, 'Pagos por inversiones (−)', 'Payments for investments (−)', false),
('direct', 'DB2',  'DB', 220, 'Cobros por desinversiones (+)', 'Proceeds from disposals (+)', false),
('direct', 'DC',   'DE', 300, 'C) FLUJOS DE EFECTIVO DE LAS ACTIVIDADES DE FINANCIACIÓN', 'C) CASH FLOWS FROM FINANCING ACTIVITIES', true),
('direct', 'DC1',  'DC', 310, 'Cobros y pagos por instrumentos de patrimonio', 'Equity instruments received (paid)', false),
('direct', 'DC2',  'DC', 320, 'Emisión de deudas (préstamos recibidos) (+)', 'Borrowings received (+)', false),
('direct', 'DC3',  'DC', 330, 'Devolución y amortización de deudas (−)', 'Repayment of borrowings (−)', false),
('direct', 'DC4',  'DC', 340, 'Pagos por dividendos', 'Dividends paid', false),
('direct', 'DE',   null, 400, 'E) AUMENTO / DISMINUCIÓN NETA DEL EFECTIVO (A + B + C)', 'E) NET INCREASE / DECREASE IN CASH (A + B + C)', true);

-- ---------------------------------------------------------------------
-- Clasificación de cada cuenta (prefijo más largo):
--   home_line   → línea del método indirecto donde va su flujo
--   adjust_line → si es de la PyG y no es de explotación: ajuste que la quita del resultado (línea 2)
--   direct_line → línea del método directo cuando es la contrapartida de un cobro o pago
--                 ('DB' y 'DC2' se reparten por signo: pagos / cobros, emisión / devolución)
-- ---------------------------------------------------------------------
create table erp.cf_mapping (
  prefix       text primary key,
  home_line    text not null,
  adjust_line  text,
  direct_line  text not null
);

insert into erp.cf_mapping (prefix, home_line, adjust_line, direct_line) values
-- Grupo 1 · Financiación básica
('1', 'IC2', null, 'DC2'), ('10', 'IC1', null, 'DC1'), ('11', 'IC1', null, 'DC1'), ('12', 'IC1', null, 'DC1'),
('13', 'IC1', null, 'DC1'), ('14', 'IA2c', null, 'DA7'), ('173', 'IB5', null, 'DB'), ('175', 'IB5', null, 'DB'),
('19', 'IC1', null, 'DC1'),
-- Grupo 2 · Activo no corriente (con su amortización y su deterioro)
('2', 'IB2', null, 'DB'), ('20', 'IB1', null, 'DB'), ('21', 'IB2', null, 'DB'), ('22', 'IB3', null, 'DB'),
('23', 'IB2', null, 'DB'), ('24', 'IB4', null, 'DB'), ('25', 'IB4', null, 'DB'), ('26', 'IB4', null, 'DB'),
('27', 'IB4', null, 'DB'), ('280', 'IB1', null, 'DB'), ('281', 'IB2', null, 'DB'), ('282', 'IB3', null, 'DB'),
('29', 'IB4', null, 'DB'), ('290', 'IB1', null, 'DB'), ('291', 'IB2', null, 'DB'), ('292', 'IB3', null, 'DB'),
-- Grupo 3 · Existencias
('3', 'IA3a', null, 'DA7'),
-- Grupo 4 · Acreedores y deudores
('4', 'IA3d', null, 'DA7'), ('40', 'IA3d', null, 'DA2'), ('41', 'IA3d', null, 'DA2'), ('407', 'IA3b', null, 'DA2'),
('43', 'IA3b', null, 'DA1'), ('44', 'IA3b', null, 'DA1'), ('46', 'IA3d', null, 'DA3'), ('460', 'IA3b', null, 'DA3'),
('47', 'IA3d', null, 'DA4'), ('470', 'IA3b', null, 'DA4'), ('471', 'IA3b', null, 'DA4'), ('472', 'IA3b', null, 'DA4'),
('473', 'IA4d', null, 'DA6'), ('474', 'IA4d', null, 'DA6'), ('4752', 'IA4d', null, 'DA6'), ('479', 'IA4d', null, 'DA6'),
('480', 'IA3c', null, 'DA7'), ('485', 'IA3e', null, 'DA1'), ('49', 'IA3b', null, 'DA7'), ('499', 'IA2c', null, 'DA7'),
-- Grupo 5 · Cuentas financieras (la 57 es el efectivo: no se clasifica)
('5', 'IC2', null, 'DC2'), ('523', 'IB5', null, 'DB'), ('525', 'IB5', null, 'DB'), ('526', 'IC3', null, 'DC4'),
('529', 'IA2c', null, 'DA7'), ('53', 'IB4', null, 'DB'), ('54', 'IB4', null, 'DB'), ('55', 'IC1', null, 'DC1'),
('555', 'IA3e', null, 'DA7'), ('565', 'IB4', null, 'DB'), ('566', 'IB4', null, 'DB'), ('567', 'IA3c', null, 'DA7'),
('568', 'IA3e', null, 'DA7'), ('58', 'IB4', null, 'DB'), ('59', 'IB4', null, 'DB'),
-- Grupo 6 · Gastos (en el resultado; los que no son de explotación se llevan a su sitio con un ajuste)
('6', 'IA1', null, 'DA7'), ('60', 'IA1', null, 'DA2'), ('61', 'IA1', null, 'DA2'), ('62', 'IA1', null, 'DA2'),
('63', 'IA1', null, 'DA4'), ('630', 'IA4d', null, 'DA6'), ('633', 'IA4d', null, 'DA6'), ('638', 'IA4d', null, 'DA6'),
('64', 'IA1', null, 'DA3'),
('66', 'IA4a', 'IA2h', 'DA5'), ('663', 'IB4', 'IA2f', 'DB'), ('666', 'IB4', 'IA2f', 'DB'), ('667', 'IB4', 'IA2f', 'DB'),
('668', 'IA1', null, 'DA7'),
('670', 'IB1', 'IA2e', 'DB'), ('671', 'IB2', 'IA2e', 'DB'), ('672', 'IB3', 'IA2e', 'DB'), ('673', 'IB4', 'IA2f', 'DB'),
('675', 'IB4', 'IA2f', 'DB'),
('68', 'IB2', 'IA2a', 'DB'), ('680', 'IB1', 'IA2a', 'DB'), ('682', 'IB3', 'IA2a', 'DB'),
('690', 'IB1', 'IA2b', 'DB'), ('691', 'IB2', 'IA2b', 'DB'), ('692', 'IB3', 'IA2b', 'DB'), ('696', 'IB4', 'IA2b', 'DB'),
('697', 'IB4', 'IA2b', 'DB'), ('698', 'IB4', 'IA2b', 'DB'), ('699', 'IB4', 'IA2b', 'DB'),
-- Grupo 7 · Ingresos
('7', 'IA1', null, 'DA7'), ('70', 'IA1', null, 'DA1'), ('75', 'IA1', null, 'DA1'),
('746', 'IC1', 'IA2d', 'DC1'),
('76', 'IA4c', 'IA2g', 'DA5'), ('760', 'IA4b', 'IA2g', 'DA5'), ('763', 'IB4', 'IA2f', 'DB'), ('766', 'IB4', 'IA2f', 'DB'),
('768', 'IA1', null, 'DA7'),
('770', 'IB1', 'IA2e', 'DB'), ('771', 'IB2', 'IA2e', 'DB'), ('772', 'IB3', 'IA2e', 'DB'), ('773', 'IB4', 'IA2f', 'DB'),
('775', 'IB4', 'IA2f', 'DB'),
('790', 'IB1', 'IA2b', 'DB'), ('791', 'IB2', 'IA2b', 'DB'), ('792', 'IB3', 'IA2b', 'DB'), ('796', 'IB4', 'IA2b', 'DB'),
('797', 'IB4', 'IA2b', 'DB'), ('798', 'IB4', 'IA2b', 'DB'), ('799', 'IB4', 'IA2b', 'DB');

-- Coherencia del catálogo: una partida de la PyG que no se queda en el resultado necesita su ajuste
do $$ begin
  if exists (select 1 from erp.cf_mapping m
             where left(m.prefix, 1) in ('6', '7') and m.home_line <> 'IA1' and m.adjust_line is null
               and m.prefix not in ('630', '633', '638')) then
    raise exception 'cf_mapping: a P&L account outside line 1 needs an adjustment line';
  end if;
  if exists (select 1 from erp.cf_mapping m where not exists (select 1 from erp.cf_lines l where l.method = 'indirect' and l.code = m.home_line)) then
    raise exception 'cf_mapping: unknown home line';
  end if;
end $$;

alter table erp.cf_lines enable row level security;
alter table erp.cf_mapping enable row level security;
create policy read on erp.cf_lines for select to authenticated using (true);
create policy read on erp.cf_mapping for select to authenticated using (true);
revoke all on erp.cf_lines, erp.cf_mapping from anon, public;
grant select on erp.cf_lines, erp.cf_mapping to authenticated;


-- =====================================================================
-- FUNCIONES. Las internas (cf_*) son SECURITY DEFINER y no se exponen: leen el diario sin el coste de la RLS
-- fila a fila (con 100.000 apuntes es la diferencia entre 1 y 6 segundos). Las públicas comprueban erp.can_read.
-- =====================================================================

-- Clasificación de una subcuenta (prefijo más largo)
create or replace function erp.cf_account_map(p_account_no text)
returns erp.cf_mapping language sql stable as $$
  select m.* from erp.cf_mapping m where p_account_no like m.prefix || '%' order by length(m.prefix) desc limit 1;
$$;

-- ---------------------------------------------------------------------
-- Flujo de cada subcuenta en el año = −(variación de su saldo) en los asientos normales
--   (> 0 entra dinero · < 0 sale dinero); la 57 queda fuera: es el efectivo
-- ---------------------------------------------------------------------
create or replace function erp.cf_account_flows(p_company uuid, p_year int)
returns table (account_no text, account_name text, account_name_en text, flow numeric,
               home_line text, adjust_line text, direct_line text, in_result boolean)
language sql stable security definer set search_path = erp, public as $$
  select a.account_no, a.name, a.name_en, a.flow, m.home_line, m.adjust_line, m.direct_line,
         left(a.account_no, 1) in ('6', '7') and m.home_line <> 'IA4d'
  from (
    select g.account_no, g.name, g.name_en, -sum(l.debit - l.credit) as flow
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted' and e.entry_type = 'normal'
    join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and g.account_no not like '57%'
    group by g.account_no, g.name, g.name_en
    having sum(l.debit - l.credit) <> 0) a
  cross join lateral erp.cf_account_map(a.account_no) m;
$$;

-- Importes de cada línea del método indirecto (sin totales)
create or replace function erp.cf_indirect_detail(p_company uuid, p_year int)
returns table (line_code text, account_no text, account_name text, account_name_en text, amount numeric)
language sql stable security definer set search_path = erp, public as $$
  with f as (select * from erp.cf_account_flows(p_company, p_year))
  -- 1. Resultado antes de impuestos: todas las cuentas de la PyG salvo el impuesto sobre beneficios
  select 'IA1', account_no, account_name, account_name_en, flow from f where in_result
  -- 2. Ajustes: se quita del resultado lo que no es de explotación…
  union all
  select adjust_line, account_no, account_name, account_name_en, -flow from f where in_result and adjust_line is not null
  -- …y cada flujo va a su línea (las cuentas de balance, el impuesto y lo que se quitó del resultado)
  union all
  select home_line, account_no, account_name, account_name_en, flow from f
  where not in_result or (home_line <> 'IA1' and adjust_line is not null);
$$;

-- Movimiento de la 57 en cada asiento normal del año (los que no la mueven no salen)
create or replace function erp.cf_entry_cash(p_company uuid, p_year int)
returns table (entry_id uuid, cash numeric)
language sql stable security definer set search_path = erp, public as $$
  select l.entry_id, sum(l.debit - l.credit)
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  where e.company_id = p_company and e.status = 'posted' and e.entry_type = 'normal'
  group by l.entry_id;
$$;

-- Importes de cada línea del método directo: contrapartidas de cada asiento que mueve la 57
create or replace function erp.cf_direct_detail(p_company uuid, p_year int)
returns table (line_code text, account_no text, account_name text, account_name_en text, amount numeric)
language sql stable security definer set search_path = erp, public as $$
  with c as (
    -- contrapartida de cada asiento con dinero: su flujo es −(su variación), con el signo de lo que entra o sale
    select l.entry_id, l.gl_account_id, -sum(l.debit - l.credit) as amount
    from erp.cf_entry_cash(p_company, p_year) ce
    join erp.journal_lines l on l.entry_id = ce.entry_id
    where ce.cash <> 0
    group by l.entry_id, l.gl_account_id
    having sum(l.debit - l.credit) <> 0),
  mp as (
    select g.id, g.account_no, g.name, g.name_en, m.direct_line
    from erp.gl_accounts g cross join lateral erp.cf_account_map(g.account_no) m
    where g.id in (select gl_account_id from c) and g.account_no not like '57%'),
  x as (
    -- inversión y deudas: cobro o pago según el NETO del asiento en esa línea
    -- (venta de un inmovilizado = coste + amortización acumulada + beneficio → un solo cobro)
    select c.*, mp.account_no, mp.name, mp.name_en, mp.direct_line,
           sum(c.amount) over (partition by c.entry_id, mp.direct_line) as entry_net
    from c join mp on mp.id = c.gl_account_id)
  select case direct_line
           when 'DB'  then case when entry_net < 0 then 'DB1' else 'DB2' end
           when 'DC2' then case when entry_net > 0 then 'DC2' else 'DC3' end
           else direct_line end,
         account_no, name, name_en, sum(amount)
  from x
  group by 1, 2, 3, 4;
$$;

-- Efectivo (57) al principio y al final del ejercicio: con la apertura, sin el cierre
create or replace function erp.cf_cash(p_company uuid, p_year int)
returns table (opening numeric, closing numeric)
language sql stable security definer set search_path = erp, public as $$
  select coalesce(sum(l.debit - l.credit) filter (where e.entry_type = 'opening'), 0),
         coalesce(sum(l.debit - l.credit) filter (where e.entry_type in ('opening', 'normal')), 0)
  from erp.journal_lines l
  join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
  join erp.gl_accounts g on g.id = l.gl_account_id and g.account_no like '57%'
  where e.company_id = p_company;
$$;

-- Detalle de un método (sin totales)
create or replace function erp.cf_detail(p_company uuid, p_year int, p_method text)
returns table (line_code text, account_no text, account_name text, account_name_en text, amount numeric)
language plpgsql stable security definer set search_path = erp, public as $$
begin
  if p_method = 'indirect' then return query select * from erp.cf_indirect_detail(p_company, p_year);
  elsif p_method = 'direct' then return query select * from erp.cf_direct_detail(p_company, p_year);
  else raise exception 'Unknown cash flow method: %', p_method;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- ESTADO DE FLUJOS DE EFECTIVO con columna del ejercicio anterior
-- ---------------------------------------------------------------------
create or replace function erp.cash_flow_statement(p_company uuid, p_year int, p_method text)
returns table (code text, parent text, sort int, level int, label text, label_en text, is_total boolean,
               amount numeric, amount_prev numeric)
language plpgsql stable security definer set search_path = erp, public as $$
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_method not in ('indirect', 'direct') then raise exception 'Unknown cash flow method: %', p_method; end if;
  return query
  with recursive depth(code, level) as (
    select l.code, 0 from erp.cf_lines l where l.method = p_method and l.parent is null
    union all
    select c.code, d.level + 1 from depth d join erp.cf_lines c on c.method = p_method and c.parent = d.code
  ), up(code, ancestor) as (
    select l.code, l.code from erp.cf_lines l where l.method = p_method
    union all
    select up.code, p.parent from up join erp.cf_lines p on p.method = p_method and p.code = up.ancestor
    where p.parent is not null
  ), det as (
    select x.line_code, sum(x.amount) as amount, 0 as y from erp.cf_detail(p_company, p_year, p_method) x group by 1
    union all
    select x.line_code, sum(x.amount), 1 from erp.cf_detail(p_company, p_year - 1, p_method) x group by 1
  ), tot as (
    select up.ancestor as code,
           coalesce(sum(d.amount) filter (where d.y = 0), 0) as amount,
           coalesce(sum(d.amount) filter (where d.y = 1), 0) as amount_prev
    from up left join det d on d.line_code = up.code
    group by up.ancestor)
  select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total, t.amount, t.amount_prev
  from erp.cf_lines l
  join depth d on d.code = l.code
  join tot t on t.code = l.code
  where l.method = p_method
  order by l.sort;
end $$;

-- Cuentas que forman una línea (drill-down)
create or replace function erp.cf_line_accounts(p_company uuid, p_year int, p_method text, p_code text)
returns table (account_no text, account_name text, account_name_en text, amount numeric)
language plpgsql stable security definer set search_path = erp, public as $$
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_method not in ('indirect', 'direct') then raise exception 'Unknown cash flow method: %', p_method; end if;
  return query
  with recursive below(code) as (
    select p_code
    union all
    select l.code from erp.cf_lines l join below b on l.parent = b.code where l.method = p_method
  )
  select x.account_no, x.account_name, x.account_name_en, sum(x.amount)
  from erp.cf_detail(p_company, p_year, p_method) x
  where x.line_code in (select code from below)
  group by 1, 2, 3
  having sum(x.amount) <> 0
  order by 1;
end $$;

-- ---------------------------------------------------------------------
-- CUADRE DEL AUDITOR: efectivo inicial + flujos = efectivo final, por los dos métodos, y por actividades
--   Directo e indirecto coinciden en cada actividad salvo por los asientos SIN dinero que mezclan actividades
--   (p. ej. una compra de inmovilizado a un proveedor 400, o un pago a proveedor con la póliza de crédito):
--   se listan para explicar la diferencia.
-- ---------------------------------------------------------------------
create or replace function erp.cash_flow_check(p_company uuid, p_year int)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare
  v_cash   record;
  v_ind    jsonb;
  v_dir    jsonb;
  v_cross  jsonb;
  v_ctot   jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_cash from erp.cf_cash(p_company, p_year);
  -- totales por actividad: la segunda letra del código (IA3b → A, DB1 → B)
  select jsonb_object_agg(a, s) into v_ind
  from (select substr(line_code, 2, 1) a, sum(amount) s from erp.cf_indirect_detail(p_company, p_year) group by 1) x;
  select jsonb_object_agg(a, s) into v_dir
  from (select substr(line_code, 2, 1) a, sum(amount) s from erp.cf_direct_detail(p_company, p_year) group by 1) x;

  -- Asientos sin dinero (la 57 no varía) con cuentas de actividades distintas
  with cash as (select * from erp.cf_entry_cash(p_company, p_year) where cash <> 0),
  acc as (
    select e.id, l.gl_account_id, -sum(l.debit - l.credit) as amount
    from erp.journal_entries e
    join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.journal_lines l on l.entry_id = e.id
    where e.company_id = p_company and e.status = 'posted' and e.entry_type = 'normal'
      and e.id not in (select entry_id from cash)
    group by e.id, l.gl_account_id
    having sum(l.debit - l.credit) <> 0),
  mp as (
    select g.id, substr(m.home_line, 2, 1) as act
    from erp.gl_accounts g cross join lateral erp.cf_account_map(g.account_no) m
    where g.id in (select gl_account_id from acc) and g.account_no not like '57%'),
  per_act as (
    select acc.id, mp.act, sum(acc.amount) as amount
    from acc join mp on mp.id = acc.gl_account_id
    group by acc.id, mp.act
    having sum(acc.amount) <> 0)
  select coalesce(jsonb_agg(jsonb_build_object('entry_no', e.entry_no, 'date', e.posting_date,
                    'description', e.description, 'activities', x.acts) order by e.entry_no), '[]'),
         jsonb_build_object('A', coalesce(sum((x.acts->>'A')::numeric), 0), 'B', coalesce(sum((x.acts->>'B')::numeric), 0),
                            'C', coalesce(sum((x.acts->>'C')::numeric), 0))
    into v_cross, v_ctot
  from (select id, jsonb_object_agg(act, amount) as acts from per_act group by id) x
  join erp.journal_entries e on e.id = x.id;

  return jsonb_build_object(
    'year', p_year,
    'cash_opening', v_cash.opening, 'cash_closing', v_cash.closing, 'cash_change', v_cash.closing - v_cash.opening,
    'indirect', jsonb_build_object('A', coalesce((v_ind->>'A')::numeric, 0), 'B', coalesce((v_ind->>'B')::numeric, 0),
                                   'C', coalesce((v_ind->>'C')::numeric, 0),
                                   'total', coalesce((select sum(value::numeric) from jsonb_each_text(v_ind)), 0)),
    'direct', jsonb_build_object('A', coalesce((v_dir->>'A')::numeric, 0), 'B', coalesce((v_dir->>'B')::numeric, 0),
                                 'C', coalesce((v_dir->>'C')::numeric, 0),
                                 'total', coalesce((select sum(value::numeric) from jsonb_each_text(v_dir)), 0)),
    'balanced', coalesce((select sum(value::numeric) from jsonb_each_text(v_ind)), 0) = v_cash.closing - v_cash.opening
            and coalesce((select sum(value::numeric) from jsonb_each_text(v_dir)), 0) = v_cash.closing - v_cash.opening,
    'cross_entries', (select coalesce(jsonb_agg(x), '[]') from (select x from jsonb_array_elements(v_cross) x limit 20) s),
    'cross_count', jsonb_array_length(v_cross),
    -- lo que esos asientos explican: indirecto − directo en cada actividad
    'cross_total', v_ctot);
end $$;

-- Solo las tres funciones públicas se pueden llamar desde la web
revoke execute on function erp.cf_account_map(text), erp.cf_account_flows(uuid, int), erp.cf_indirect_detail(uuid, int),
  erp.cf_entry_cash(uuid, int), erp.cf_direct_detail(uuid, int), erp.cf_cash(uuid, int), erp.cf_detail(uuid, int, text),
  erp.cash_flow_statement(uuid, int, text), erp.cf_line_accounts(uuid, int, text, text), erp.cash_flow_check(uuid, int)
  from anon, public;
grant execute on function erp.cash_flow_statement(uuid, int, text), erp.cf_line_accounts(uuid, int, text, text),
  erp.cash_flow_check(uuid, int) to authenticated;
