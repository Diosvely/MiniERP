-- =====================================================================
-- 0066 · CASO COMPLETO «Taller Atlántico SL» y lo que encontró en el estado de flujos de efectivo · v0.45.0
-- ---------------------------------------------------------------------
-- Supuesto de referencia: un ejercicio entero (2026), de la constitución a las cuentas anuales, calculado a mano y
-- validado antes de programar (supuestos-v0.45.0.md). Hecho con las funciones de cada módulo, el motor tiene que dar
-- la cuenta de resultados, el balance, el ECPN, el EFE por los dos métodos, el Impuesto sobre Sociedades y los
-- modelos 420 y 111 al céntimo.
--
-- Lo que no daba, y se arregla aquí (estado de flujos de efectivo):
--   1. Las facturas de inversión o de financiación. El pago al proveedor de la máquina (400) salía en explotación por
--      el método directo, y la notaría de la constitución (113, NRV 9.ª) no restaba de la financiación. Ahora el pago o
--      el cobro de una factura se clasifica como lo que la factura compró o vendió: la base de la 213, en inversión; la
--      de la 113, en financiación; el IGIC / IVA, en explotación. Lo mismo se hace con la factura en el método
--      indirecto, así que una máquina sin pagar ya no sale como inversión.
--   2. Los intereses devengados y no pagados (506, 527, 528) iban a financiación: son intereses (A-4 a).
--   3. El impuesto que se lleva a reservas (el ahorro de los gastos de constitución, 6300 / 113) salía como
--      financiación sin que hubiera dinero: va con el impuesto sobre beneficios (A-4 d).
--   4. El deterioro de clientes (490, 493) y de existencias (39) se veía dentro de la variación de los deudores: va en
--      los ajustes del resultado (A-2 b, correcciones valorativas por deterioro), como pide el modelo del PGC.
--   Con esto, directo = indirecto en cada actividad, y los asientos que «mezclan» actividades dejan de serlo.
--
--   · erp.cases / erp.case_expected: el catálogo de casos y sus cifras esperadas.
--   · erp.load_case(empresa, caso): carga el caso en una empresa nueva, operación a operación, con cada módulo.
--   · erp.case_compare(empresa): compara sus cuentas anuales con las del caso.
-- Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) EFE · Clasificación de cuentas
-- ---------------------------------------------------------------------
insert into erp.cf_mapping (prefix, home_line, adjust_line, direct_line) values
  ('506', 'IA4a', null, 'DA5'),   -- intereses a corto plazo de empréstitos
  ('527', 'IA4a', null, 'DA5'),   -- intereses a corto plazo de deudas con entidades de crédito
  ('528', 'IA4a', null, 'DA5'),   -- intereses a corto plazo de deudas
  ('39',  'IA2b', null, 'DA7'),   -- deterioro de existencias
  ('490', 'IA2b', null, 'DA7'),   -- deterioro de créditos comerciales
  ('493', 'IA2b', null, 'DA7')    -- … con partes vinculadas
on conflict (prefix) do update set home_line = excluded.home_line, adjust_line = excluded.adjust_line, direct_line = excluded.direct_line;

-- ---------------------------------------------------------------------
-- 2) EFE · Flujo de cada cuenta en cada asiento, ya clasificado
--    Base: −(variación) de cada subcuenta (salvo la 57) en cada asiento normal del año, con su línea (erp.cf_mapping).
--    Reclasificaciones:
--      a) Facturas con partidas de inversión o de financiación (bases de cuentas cuya línea es B o C). La cuenta del
--         tercero se reparte en la factura, en sus pagos o cobros (por lo aplicado) y en sus anulaciones, en la misma
--         proporción que la factura: la parte de cada base va a la línea de su cuenta; el resto (impuestos), se queda.
--      b) En los asientos con gasto o ingreso por impuesto sobre beneficios (630, 633, 638), lo que va al patrimonio
--         neto (grupo 1) es efecto impositivo: con el impuesto (A-4 d).
-- ---------------------------------------------------------------------
create or replace function erp.cf_line_flows(p_company uuid, p_year int)
returns table (entry_id uuid, account_no text, account_name text, account_name_en text, flow numeric,
               home_line text, adjust_line text, direct_line text, in_result boolean)
language sql stable security definer set search_path = erp, public as $$
  with base as (
    select l.entry_id, g.id as acc_id, g.account_no, g.name, g.name_en, -sum(l.debit - l.credit) as flow
    from erp.journal_lines l
    join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted' and e.entry_type = 'normal'
    join erp.fiscal_years fy on fy.id = e.fiscal_year_id and fy.year = p_year
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and g.account_no not like '57%'
    group by l.entry_id, g.id, g.account_no, g.name, g.name_en
    having sum(l.debit - l.credit) <> 0),
  mb as (
    select b.*, m.home_line, m.adjust_line, m.direct_line from base b cross join lateral erp.cf_account_map(b.account_no) m),
  -- a) facturas con bases de inversión o de financiación: la proporción de cada línea sobre la cuenta del tercero
  inv as (
    select i.id as invoice_id, i.entry_id, bp.gl_account_id as partner_acc
    from erp.invoices i join erp.business_partners bp on bp.id = i.partner_id
    where i.company_id = p_company and i.entry_id is not null),
  inv_acc as (
    select inv.invoice_id, inv.partner_acc, l.gl_account_id, -sum(l.debit - l.credit) as flow
    from inv join erp.journal_lines l on l.entry_id = inv.entry_id
    group by inv.invoice_id, inv.partner_acc, l.gl_account_id),
  inv_partner as (
    select invoice_id, flow from inv_acc where gl_account_id = partner_acc and flow <> 0),
  inv_group as (
    select a.invoice_id, m.home_line, m.direct_line, min(g.account_no) as account_no, sum(a.flow) as flow
    from inv_acc a join erp.gl_accounts g on g.id = a.gl_account_id
    cross join lateral erp.cf_account_map(g.account_no) m
    where a.gl_account_id <> a.partner_acc and g.account_no not like '57%' and substr(m.home_line, 2, 1) in ('B', 'C')
    group by a.invoice_id, m.home_line, m.direct_line
    having sum(a.flow) <> 0),
  ratio as (
    select g.invoice_id, g.home_line, g.direct_line, -g.flow / p.flow as r
    from inv_group g join inv_partner p on p.invoice_id = g.invoice_id),
  -- los asientos de cada factura: el suyo, sus anulaciones y sus pagos o cobros (lo aplicado, con el signo del asiento;
  -- en un pago que compensa una factura con su abono, el abono va al revés)
  docs as (
    select inv.invoice_id, inv.entry_id, inv.partner_acc, null::numeric as applied
    from inv where inv.invoice_id in (select invoice_id from ratio)
    union all
    select inv.invoice_id, r.id, inv.partner_acc, null
    from inv join erp.journal_entries r on r.reversal_of = inv.entry_id
    where inv.invoice_id in (select invoice_id from ratio)
    union all
    select inv.invoice_id, x.entry_id, inv.partner_acc, pa.amount * sign(pa.total)
    from inv
    join (select a.*, sum(a.amount) over (partition by a.payment_id) as total from erp.payment_applications a) pa on pa.invoice_id = inv.invoice_id
    join erp.payments p on p.id = pa.payment_id
    cross join lateral (select p.entry_id union select p.cancel_entry_id
                        union select r.id from erp.journal_entries r where r.reversal_of = p.entry_id) x(entry_id)
    where inv.invoice_id in (select invoice_id from ratio) and x.entry_id is not null),
  part as (
    -- la parte de la cuenta del tercero que corresponde a la factura en ese asiento
    select d.invoice_id, mb.entry_id, mb.account_no, mb.name, mb.name_en, mb.home_line, mb.adjust_line, mb.direct_line,
           case when d.applied is null then mb.flow else sign(mb.flow) * d.applied end as flow
    from docs d join mb on mb.entry_id = d.entry_id and mb.acc_id = d.partner_acc),
  moved as (
    select p.entry_id, p.account_no, p.name, p.name_en, p.home_line as from_home, p.adjust_line as from_adjust,
           p.direct_line as from_direct, r.home_line, r.direct_line, round(p.flow * r.r, 2) as amount
    from part p join ratio r on r.invoice_id = p.invoice_id),
  -- b) asientos del impuesto sobre beneficios
  tax_entries as (select distinct mb.entry_id from mb where mb.account_no ~ '^63[038]')
  select mb.entry_id, mb.account_no, mb.name, mb.name_en, mb.flow,
         case when mb.account_no like '1%' and mb.entry_id in (select t.entry_id from tax_entries t) then 'IA4d' else mb.home_line end,
         case when mb.account_no like '1%' and mb.entry_id in (select t.entry_id from tax_entries t) then null else mb.adjust_line end,
         case when mb.account_no like '1%' and mb.entry_id in (select t.entry_id from tax_entries t) then 'DA6' else mb.direct_line end,
         left(mb.account_no, 1) in ('6', '7') and mb.home_line <> 'IA4d'
  from mb
  union all   -- lo que se lleva cada base…
  select m.entry_id, m.account_no, m.name, m.name_en, m.amount, m.home_line, null, m.direct_line, false from moved m where m.amount <> 0
  union all   -- …y lo que deja de estar en la cuenta del tercero
  select m.entry_id, m.account_no, m.name, m.name_en, -m.amount, m.from_home, m.from_adjust, m.from_direct, false from moved m where m.amount <> 0;
$$;

-- Flujo de cada subcuenta en el año (versión de la 0022, ya con las reclasificaciones): una fila por cuenta y línea
create or replace function erp.cf_account_flows(p_company uuid, p_year int)
returns table (account_no text, account_name text, account_name_en text, flow numeric,
               home_line text, adjust_line text, direct_line text, in_result boolean)
language sql stable security definer set search_path = erp, public as $$
  select f.account_no, f.account_name, f.account_name_en, sum(f.flow), f.home_line, f.adjust_line, f.direct_line, f.in_result
  from erp.cf_line_flows(p_company, p_year) f
  group by f.account_no, f.account_name, f.account_name_en, f.home_line, f.adjust_line, f.direct_line, f.in_result
  having sum(f.flow) <> 0;
$$;

-- Método directo (versión de la 0022): las contrapartidas de cada asiento que mueve la 57, ya reclasificadas
create or replace function erp.cf_direct_detail(p_company uuid, p_year int)
returns table (line_code text, account_no text, account_name text, account_name_en text, amount numeric)
language sql stable security definer set search_path = erp, public as $$
  with c as (
    select f.entry_id, f.account_no, f.account_name, f.account_name_en, f.direct_line, sum(f.flow) as amount
    from erp.cf_line_flows(p_company, p_year) f
    where f.entry_id in (select ce.entry_id from erp.cf_entry_cash(p_company, p_year) ce where ce.cash <> 0)
    group by 1, 2, 3, 4, 5
    having sum(f.flow) <> 0),
  x as (
    -- inversión y deudas: cobro o pago según el NETO del asiento en esa línea
    -- (venta de un inmovilizado = coste + amortización acumulada + beneficio → un solo cobro)
    select c.*, sum(c.amount) over (partition by c.entry_id, c.direct_line) as entry_net from c)
  select case direct_line
           when 'DB'  then case when entry_net < 0 then 'DB1' else 'DB2' end
           when 'DC2' then case when entry_net > 0 then 'DC2' else 'DC3' end
           else direct_line end,
         account_no, account_name, account_name_en, sum(amount)
  from x
  group by 1, 2, 3, 4;
$$;

-- Cuadre del auditor (versión de la 0022): los asientos sin dinero que mezclan actividades, ya con las reclasificaciones
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
  with per_act as (
    select f.entry_id as id, substr(f.home_line, 2, 1) as act, sum(f.flow) as amount
    from erp.cf_line_flows(p_company, p_year) f
    where f.entry_id not in (select ce.entry_id from erp.cf_entry_cash(p_company, p_year) ce where ce.cash <> 0)
    group by 1, 2
    having sum(f.flow) <> 0)
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

revoke execute on function erp.cf_line_flows(uuid, int), erp.cf_account_flows(uuid, int), erp.cf_direct_detail(uuid, int)
  from anon, public;
grant execute on function erp.cash_flow_check(uuid, int) to authenticated;

-- ---------------------------------------------------------------------
-- 3) Catálogo de casos completos y sus cifras esperadas (calculadas a mano y validadas)
-- ---------------------------------------------------------------------
create table if not exists erp.cases (
  key            text primary key,
  sort           int  not null,
  title          text not null,
  title_en       text not null,
  description    text not null,
  description_en text not null,
  tax_territory  text not null,
  legal_form     text not null,
  year           int  not null
);
create table if not exists erp.case_expected (
  case_key text not null references erp.cases (key) on delete cascade,
  kind     text not null check (kind in ('pyg', 'balance', 'cf_indirect', 'cf_direct', 'ecpn', 'cit', 'tax_form', 'withholding')),
  code     text not null,
  amount   numeric(14, 2) not null,
  sort     int not null,
  primary key (case_key, kind, code)
);
comment on table erp.cases is 'Casos completos: un ejercicio entero, de la constitución a las cuentas anuales, que erp.load_case carga en una empresa nueva';
comment on table erp.case_expected is 'Cifras esperadas de cada caso (calculadas a mano antes de programar), para erp.case_compare';

alter table erp.cases enable row level security;
alter table erp.case_expected enable row level security;
drop policy if exists read on erp.cases;
drop policy if exists read on erp.case_expected;
create policy read on erp.cases for select to authenticated using (true);
create policy read on erp.case_expected for select to authenticated using (true);
revoke all on erp.cases, erp.case_expected from anon, public;
grant select on erp.cases, erp.case_expected to authenticated;

alter table erp.companies add column if not exists case_key text references erp.cases (key);
comment on column erp.companies.case_key is 'Caso completo cargado en la empresa (erp.load_case)';
create index if not exists companies_case_key_idx on erp.companies (case_key);

insert into erp.cases (key, sort, title, title_en, description, description_en, tax_territory, legal_form, year) values
('taller_atlantico', 10, 'Taller Atlántico SL · un ejercicio completo', 'Taller Atlántico SL · a complete year',
 'SL de Tenerife (IGIC del 7 %), comercio de recambios, constituida el 02/01/2026: constitución, facturas, cobros y pagos, una máquina con su subvención de capital, un préstamo, liquidaciones del IGIC y retenciones; en el cierre, amortización, imputación de la subvención, intereses, periodificación, deterioro de un cliente, existencias, Impuesto sobre Sociedades (entidad de nueva creación) y cierre.',
 'An SL in Tenerife (7 % IGIC), a spare-parts trader incorporated on 02/01/2026: incorporation, invoices, receipts and payments, a machine with its capital grant, a loan, IGIC returns and withholdings; at year end, depreciation, grant transfer, interest, an accrual, a doubtful customer, inventory, corporate tax (newly created entity) and closing.',
 'canary_islands', 'sl', 2026)
on conflict (key) do update set sort = excluded.sort, title = excluded.title, title_en = excluded.title_en, description = excluded.description,
  description_en = excluded.description_en, tax_territory = excluded.tax_territory, legal_form = excluded.legal_form, year = excluded.year;

delete from erp.case_expected where case_key = 'taller_atlantico';
insert into erp.case_expected (case_key, kind, code, amount, sort)
select 'taller_atlantico', x.kind, x.code, x.amount, (row_number() over ())::int
from (values
  -- Cuenta de pérdidas y ganancias
  ('pyg', 'P1', 120000), ('pyg', 'P4', -37000), ('pyg', 'P7', -4840), ('pyg', 'P8', -3000), ('pyg', 'P9', 1200),
  ('pyg', 'PA', 76360), ('pyg', 'P14', -740.85), ('pyg', 'PB', -740.85), ('pyg', 'PC', 75619.15), ('pyg', 'P18', -11342.87),
  ('pyg', 'PD', 64276.28),
  -- Balance al 31/12/2026
  ('balance', 'ANC', 37000), ('balance', 'ANC.II', 37000), ('balance', 'AC', 160160), ('balance', 'AC.I', 8000),
  ('balance', 'AC.II', 21400), ('balance', 'AC.V', 900), ('balance', 'AC.VI', 129860), ('balance', 'ACT', 197160),
  ('balance', 'PN', 134526.28), ('balance', 'PN.A1.I', 60000), ('balance', 'PN.A1.III', -850), ('balance', 'PN.A1.VII', 64276.28),
  ('balance', 'PN.A2', 11100), ('balance', 'PNC', 24183.74), ('balance', 'PNC.II', 20483.74), ('balance', 'PNC.IV', 3700),
  ('balance', 'PC', 38449.98), ('balance', 'PC.II', 10257.11), ('balance', 'PC.IV.1', 16050), ('balance', 'PC.IV.2', 12142.87),
  ('balance', 'PNP', 197160),
  -- Estado de cambios en el patrimonio neto
  ('ecpn', 'part_a.result', 64276.28), ('ecpn', 'part_a.b_grants', 16000), ('ecpn', 'part_a.b_tax', -4000),
  ('ecpn', 'part_a.b_total', 12000), ('ecpn', 'part_a.c_grants', -1200), ('ecpn', 'part_a.c_tax', 300),
  ('ecpn', 'part_a.c_total', -900), ('ecpn', 'part_a.total', 75376.28), ('ecpn', 'start', 0),
  ('ecpn', 'part_b.recognised.result', 64276.28), ('ecpn', 'part_b.recognised.grants', 11100),
  ('ecpn', 'part_b.owners.capital', 60000), ('ecpn', 'part_b.other.reserves', -850), ('ecpn', 'end', 134526.28),
  ('ecpn', 'balance_net_worth', 134526.28),
  -- Estado de flujos de efectivo, método indirecto
  ('cf_indirect', 'IA1', 75619.15), ('cf_indirect', 'IA2', 4680.85), ('cf_indirect', 'IA2a', 3000), ('cf_indirect', 'IA2b', 2140),
  ('cf_indirect', 'IA2d', -1200), ('cf_indirect', 'IA2h', 740.85), ('cf_indirect', 'IA3', -15440), ('cf_indirect', 'IA3a', -8000),
  ('cf_indirect', 'IA3b', -23540), ('cf_indirect', 'IA3c', -900), ('cf_indirect', 'IA3d', 17000), ('cf_indirect', 'IA4', 0),
  ('cf_indirect', 'IA', 64860), ('cf_indirect', 'IB', -40000), ('cf_indirect', 'IC1', 75000), ('cf_indirect', 'IC2', 30000),
  ('cf_indirect', 'IC', 105000), ('cf_indirect', 'IE', 129860),
  -- … y método directo
  ('cf_direct', 'DA1', 104860), ('cf_direct', 'DA2', -37826), ('cf_direct', 'DA4', -2174), ('cf_direct', 'DA', 64860),
  ('cf_direct', 'DB1', -40000), ('cf_direct', 'DB', -40000), ('cf_direct', 'DC1', 75000), ('cf_direct', 'DC2', 30000),
  ('cf_direct', 'DC', 105000), ('cf_direct', 'DE', 129860),
  -- Impuesto sobre Sociedades
  ('cit', 'pre_tax_result', 75619.15), ('cit', 'taxable_base', 74619.15), ('cit', 'quota', 11192.87),
  ('cit', 'tax_expense', 11342.87), ('cit', 'equity_tax_effect', 150), ('cit', 'differential', 11192.87),
  -- Modelo 420 (trimestre.casilla): 25 devengado · 40 deducible · 45 resultado
  ('tax_form', '1.25', 1750), ('tax_form', '1.40', 812), ('tax_form', '1.45', 938),
  ('tax_form', '2.25', 3850), ('tax_form', '2.40', 3542), ('tax_form', '2.45', 308),
  ('tax_form', '3.25', 1400), ('tax_form', '3.40', 742), ('tax_form', '3.45', 658),
  ('tax_form', '4.25', 1400), ('tax_form', '4.40', 1092), ('tax_form', '4.45', 308),
  -- Modelo 111 (trimestre.modelo): retenciones practicadas
  ('withholding', '1.111', 90), ('withholding', '2.111', 90), ('withholding', '3.111', 90), ('withholding', '4.111', 90)
) as x(kind, code, amount);

-- ---------------------------------------------------------------------
-- 4) Ayudas para cargar un caso: cada una llama a la función del módulo, como haría su pantalla
-- ---------------------------------------------------------------------
-- Factura (Facturas)
create or replace function erp.case_invoice(e uuid, p_type text, p_partner uuid, p_date date, p_doc text, p_desc text,
                                            p_lines jsonb, p_withholding text default null)
returns uuid language sql set search_path = erp, public as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', p_type, 'document_kind', 'invoice',
    'partner_id', p_partner, 'invoice_date', p_date, 'external_document_no', case p_type when 'purchase' then p_doc end,
    'description', p_desc, 'withholding_code', p_withholding, 'lines', p_lines));
$$;
-- Pago o cobro de una factura entera, por el banco (Cobros y pagos)
create or replace function erp.case_payment(e uuid, p_type text, p_partner uuid, p_date date, p_invoice uuid)
returns void language plpgsql set search_path = erp, public as $$
begin
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', p_type, 'partner_id', p_partner,
    'payment_date', p_date, 'cash_account_no', '57200001',
    'applications', jsonb_build_array(jsonb_build_object('invoice_id', p_invoice,
      'amount', (select i.total_amount - coalesce(i.withholding_amount, 0) from erp.invoices i where i.id = p_invoice)))));
end $$;
-- Saldo acreedor de las cuentas de un prefijo a una fecha
create or replace function erp.case_balance(e uuid, p_prefix text, p_date date)
returns numeric language sql stable set search_path = erp, public as $$
  select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id
  where j.company_id = e and j.status = 'posted' and j.posting_date <= p_date and g.account_no like p_prefix || '%';
$$;
-- Asiento manual (Nuevo asiento): [[prefijo de la subcuenta, debe, haber], …]
create or replace function erp.case_entry(e uuid, p_date date, p_desc text, p_lines jsonb)
returns uuid language plpgsql set search_path = erp, public as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = extract(year from p_date)), p_date, p_desc) returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord,
         (select g.id from erp.gl_accounts g where g.company_id = e and g.account_type = 'posting' and g.account_no like (x.v->>0) || '%'
          order by g.account_no limit 1),
         (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(p_lines) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  return a;
end $$;

-- ---------------------------------------------------------------------
-- 5) Cargar un caso en una empresa nueva, operación a operación, con las funciones de cada módulo
--    (las mismas que usan las pantallas: los permisos son los de quien lo carga)
-- ---------------------------------------------------------------------
create or replace function erp.load_case(p_company uuid, p_case text default 'taller_atlantico')
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
  -- 2. Notaría y registro, a reservas (NRV 9.ª), pagados en el acto (Facturas · Cobros y pagos)
  f := erp.case_invoice(e, 'purchase', notaria, '2026-01-05', 'N-1', 'Notaría y registro de la constitución',
         '[{"account_no": "11300001", "amount": 1000, "tax_code": "IGIC7"}]');
  perform erp.case_payment(e, 'payment', notaria, '2026-01-05', f);
  -- 6. La máquina, su ficha y su pago (Facturas · Inmovilizado · Cobros y pagos)
  f_maq := erp.case_invoice(e, 'purchase', maq, '2026-04-01', 'M-1', 'Máquina de diagnosis',
             '[{"account_no": "21300001", "amount": 40000, "tax_code": "IGIC7"}]');
  select asset_id into a from erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Máquina de diagnosis',
    'asset_account_no', '21300001', 'cost', 40000, 'useful_life_months', 120, 'start_date', '2026-04-01',
    'acquisition_date', '2026-04-01', 'invoice_id', f_maq));
  perform erp.case_payment(e, 'payment', maq, '2026-04-15', f_maq);
  -- 7. Subvención de capital del 40 % de la máquina, cobrada el 30/06 (Subvenciones)
  g := (erp.grant_create(jsonb_build_object('company_id', e, 'kind', 'capital', 'description', 'Subvención para la máquina de diagnosis',
         'grantor', 'Gobierno de Canarias', 'amount', 16000, 'date', '2026-04-15', 'asset_id', a))->>'grant_id')::uuid;
  perform erp.grant_collect(jsonb_build_object('grant_id', g, 'date', '2026-06-30'));
  -- 8. Préstamo de 30.000 al 5 %, tres cuotas anuales (Financiación)
  perform erp.loan_create(jsonb_build_object('company_id', e, 'description', 'Préstamo para circulante', 'lender', 'Banco Atlántico',
    'principal', 30000, 'rate', 5, 'periods', 3, 'frequency', 1, 'start_date', '2026-07-01'));
  -- 9. Seguro anual, exento, pagado (Nuevo asiento)
  perform erp.case_entry(e, '2026-10-01', 'Seguro anual del taller', '[["62500001", 1200, 0], ["57200001", 0, 1200]]');
  -- 3, 4, 5 y 10. Cada trimestre: compras, ventas, asesoría, liquidación del IGIC y retenciones
  for q in 1..4 loop
    f := erp.case_invoice(e, 'purchase', prov, v_end[q] - 45, 'C-' || q, 'Compra de recambios',
           jsonb_build_array(jsonb_build_object('account_no', '60000001', 'amount', v_purchases[q], 'tax_code', 'IGIC7')));
    if q < 4 then perform erp.case_payment(e, 'payment', prov, v_end[q] - 30, f); end if;
    f := erp.case_invoice(e, 'sale', cli, v_end[q] - 40, null, 'Venta de recambios',
           jsonb_build_array(jsonb_build_object('account_no', '70000001', 'amount', v_sales[q], 'tax_code', 'IGIC7')));
    if q < 4 then perform erp.case_payment(e, 'collection', cli, v_end[q] - 10, f); end if;
    if q = 1 then   -- la venta dudosa del 15/03, que no se cobra
      f_dud := erp.case_invoice(e, 'sale', dud, '2026-03-15', null, 'Venta de recambios',
                 '[{"account_no": "70000001", "amount": 2000, "tax_code": "IGIC7"}]');
    end if;
    f := erp.case_invoice(e, 'purchase', aseso, v_end[q], 'A-' || q, 'Asesoría del trimestre',
           '[{"account_no": "62300001", "amount": 600, "tax_code": "IGIC7"}]', 'IRPF15');
    if q < 4 then perform erp.case_payment(e, 'payment', aseso, v_end[q], f); end if;
    perform erp.post_tax_settlement(e, 'IGIC', 2026, q);
    if q < 4 then   -- los modelos 420 y 111 se pagan el día 20 del mes siguiente; los del 4T, en enero
      v_pay := v_end[q] + 20;
      v_due := erp.case_balance(e, '4750', v_pay);
      perform erp.case_entry(e, v_pay, 'Pago del modelo 420 · ' || q || 'T',
        jsonb_build_array(jsonb_build_array('4750', v_due, 0), jsonb_build_array('57200001', 0, v_due)));
      perform erp.case_entry(e, v_pay, 'Pago del modelo 111 · ' || q || 'T', '[["4751", 90, 0], ["57200001", 0, 90]]');
    end if;
  end loop;

  -- 11 a 19. El cierre del 31/12/2026
  perform erp.post_depreciation(e, '2026-12-31');                    -- 11. Inmovilizado
  perform erp.grant_year_end(e, '2026-12-31');                       -- 12. Subvenciones
  perform erp.loan_year_end(e, '2026-12-31');                        -- 13 y 14. Financiación
  perform erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'prepaid_expense', 'description', 'Seguro anual del taller',
    'pl_account_no', '62500001', 'cutoff_date', '2026-12-31', 'total_amount', 1200, 'coverage_start', '2026-10-01',
    'coverage_months', 12));                                        -- 15. Ajustes de cierre
  perform erp.impair_receivable(jsonb_build_object('invoice_id', f_dud, 'impair_date', '2026-12-31'));   -- 16
  perform erp.post_inventory(jsonb_build_object('company_id', e, 'count_date', '2026-12-31',
    'lines', '[{"account_no": "30000001", "final_value": 8000}]'::jsonb));                               -- 17
  v_ret := erp.corporate_tax_prepare(e, 2026);                       -- 18. Impuesto sobre Sociedades
  perform erp.corporate_tax_settings(v_ret, 'new_entity', false);
  perform erp.corporate_tax_calc(e, 2026);
  perform erp.corporate_tax_post(e, 2026);
  perform erp.close_fiscal_year(e, 2026, true);                      -- 19. Cierre del ejercicio

  update erp.companies set case_key = p_case where id = e;
  return jsonb_build_object('company_id', e, 'case', p_case,
    'entries', (select count(*) from erp.journal_entries j where j.company_id = e and j.status = 'posted'));
end $$;

-- ---------------------------------------------------------------------
-- 6) Comparar las cuentas de la empresa con las del caso
-- ---------------------------------------------------------------------
create or replace function erp.case_compare(p_company uuid, p_case text default null)
returns table (kind text, code text, expected numeric, actual numeric, difference numeric, ok boolean, sort int)
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
  select y.kind, y.code, y.expected, y.actual, y.actual - y.expected, y.actual = y.expected, y.sort
  from (
    select x.kind, x.code, x.amount as expected, x.sort,
           coalesce(case x.kind when 'ecpn' then (v_ecpn #>> string_to_array(x.code, '.'))::numeric
                                when 'cit' then (v_cit ->> x.code)::numeric
                                else (select sum(a.v) from act a where a.k = x.kind and a.c = x.code) end, 0) as actual
    from erp.case_expected x where x.case_key = v_case.key) y
  order by y.sort;
end $$;

grant execute on function erp.load_case(uuid, text), erp.case_compare(uuid, text) to authenticated;
revoke execute on function erp.load_case(uuid, text), erp.case_compare(uuid, text) from anon, public;
revoke execute on function erp.case_invoice(uuid, text, uuid, date, text, text, jsonb, text), erp.case_payment(uuid, text, uuid, date, uuid),
  erp.case_balance(uuid, text, date), erp.case_entry(uuid, date, text, jsonb) from anon, public;
grant execute on function erp.case_invoice(uuid, text, uuid, date, text, text, jsonb, text), erp.case_payment(uuid, text, uuid, date, uuid),
  erp.case_balance(uuid, text, date), erp.case_entry(uuid, date, text, jsonb) to authenticated;
