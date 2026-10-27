-- =====================================================================
-- 0073 · PUENTE A POWER BI: un «contrato» de datos de solo lectura · v0.50.0
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.50.0.md, 27-10-2026). Para la demo de la charla: un diario se importa,
-- se publica como DEMO y Claude Code construye en Power BI (proyecto PBIP, con el servidor MCP) el balance, la cuenta
-- de pérdidas y ganancias, el estado de flujos y 8 ratios, que se comprueban contra el ERP al céntimo.
--   · Esquema aparte, `bi`: no cambia nada del ERP y la web no lo ve (no está en la API de Supabase).
--   · Solo las empresas DEMO (una temporal nunca puede serlo, v0.49.0).
--   · Modelo en estrella: dimensiones (empresa, fecha, cuenta, línea de los estados, ratio) y hechos (apuntes, saldos a
--     fin de mes con su línea del balance YA DECIDIDA por el ERP, flujos de efectivo ya clasificados).
--   · `control_estados`: las cifras que enseña el ERP, para la página «Comprobación» de Power BI.
--   · Power BI entra con su propio usuario, `powerbi_reader`, que SOLO lee `bi`. Se crea sin poder entrar: la
--     contraseña la pone Diosvely en el SQL Editor (nunca en el repositorio):
--         alter role powerbi_reader with login password '…';
--   · Escalable: cada informe del ERP que pase a Power BI será una vista más aquí, con los mismos nombres.
-- Re-ejecutable.
-- =====================================================================

create schema if not exists bi;
comment on schema bi is 'Power BI bridge (v0.50.0): read-only star schema of the DEMO companies. Not exposed in the API.';
revoke all on schema bi from public;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'powerbi_reader') then
    create role powerbi_reader nologin;
  end if;
end $$;
comment on role powerbi_reader is 'Power BI: reads only the bi schema (v0.50.0). Login and password are set by the owner in the SQL Editor.';

-- Las empresas que llegan a Power BI: las demo (nunca una temporal)
create or replace function bi.demo_companies()
returns setof uuid language sql stable security definer set search_path = erp, public as $$
  select c.id from erp.companies c where c.is_demo and not c.temporary;
$$;

-- ---------- Dimensiones ----------
create or replace view bi.dim_empresa as
select c.id as empresa_id, c.name as empresa, c.tax_territory as territorio,
       case when c.tax_territory = 'canary_islands' then 'IGIC' else 'IVA' end as impuesto,
       c.industry as sector, c.posting_account_digits as digitos_subcuenta
from erp.companies c
where c.id in (select bi.demo_companies());

create or replace view bi.dim_fecha as
with r as (
  select min(fy.starting_date) as desde, max(fy.ending_date) as hasta
  from erp.fiscal_years fy where fy.company_id in (select bi.demo_companies())
)
select d::date as fecha,
       extract(year from d)::int as anio,
       extract(quarter from d)::int as trimestre,
       extract(month from d)::int as mes,
       (array['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'])
         [extract(month from d)::int] as nombre_mes,
       to_char(d, 'YYYY-MM') as anio_mes,
       (date_trunc('month', d) + interval '1 month - 1 day')::date as fin_mes,
       d::date = (date_trunc('month', d) + interval '1 month - 1 day')::date as es_fin_mes
from r, generate_series(r.desde, r.hasta, interval '1 day') d
where r.desde is not null;

create or replace view bi.dim_cuenta as
select g.id as cuenta_id, g.company_id as empresa_id, g.account_no as subcuenta, g.name as nombre, g.name_en as nombre_en,
       left(g.account_no, 4) as cuenta_pgc, pa.name as nombre_cuenta_pgc,
       left(g.account_no, 2) as subgrupo, ps.name as nombre_subgrupo,
       left(g.account_no, 1) as grupo, pg.name as nombre_grupo
from erp.gl_accounts g
left join erp.pgc_accounts pa on pa.account = left(g.account_no, 4)
left join erp.pgc_subgroups ps on ps.subgroup = left(g.account_no, 2)
left join erp.pgc_groups pg on pg.grp = left(g.account_no, 1)
where g.company_id in (select bi.demo_companies()) and g.account_type = 'posting';

-- Las líneas de los estados (balance, pyg, efe_indirecto, efe_directo): la jerarquía de las matrices
create or replace view bi.dim_linea as
with recursive l as (
  select statement as estado, code, parent, sort, label, label_en, is_total, side from erp.fs_lines
  union all
  select case method when 'indirect' then 'efe_indirecto' else 'efe_directo' end, code, parent, sort, label, label_en,
         is_total, null from erp.cf_lines
), depth as (
  select estado, code, 1 as nivel from l where parent is null
  union all
  select l.estado, l.code, d.nivel + 1 from depth d join l on l.estado = d.estado and l.parent = d.code
)
select l.estado || '|' || l.code as clave_linea, l.estado, l.code as codigo,
       case when l.parent is null then null else l.estado || '|' || l.parent end as clave_padre,
       l.sort as orden, d.nivel, l.label as texto, l.label_en as texto_en, l.is_total as es_total, l.side as lado
from l join depth d on d.estado = l.estado and d.code = l.code;

-- Puente: cada línea suma sus propios importes y los de todas las líneas que cuelgan de ella (los totales)
create or replace view bi.puente_linea as
with recursive l as (
  select statement as estado, code, parent from erp.fs_lines
  union all
  select case method when 'indirect' then 'efe_indirecto' else 'efe_directo' end, code, parent from erp.cf_lines
), up as (
  select estado, code as hoja, code as ancestro from l
  union all
  select up.estado, up.hoja, l.parent from up join l on l.estado = up.estado and l.code = up.ancestro where l.parent is not null
)
select estado || '|' || ancestro as clave_linea, estado || '|' || hoja as clave_hoja, estado from up;

create or replace view bi.dim_ratio as
select code as ratio, grp as grupo, sort as orden, label as nombre, label_en as nombre_en, formula, formula_en, unit as unidad,
       ref_min as referencia_min, ref_max as referencia_max, help as ayuda,
       code in ('WC', 'CR', 'QR', 'DEBT', 'ROA', 'ROE', 'NPM', 'EBITDA') as primera_entrega
from erp.ratio_defs;

-- ---------- Hechos ----------
create or replace view bi.fact_apuntes as
select l.id as apunte_id, e.company_id as empresa_id, e.id as asiento_id, fy.year as ejercicio, e.entry_no as numero,
       e.posting_date as fecha, e.entry_type as tipo_asiento, e.description as concepto, e.document_no as documento,
       l.gl_account_id as cuenta_id, l.debit as debe, l.credit as haber, l.debit - l.credit as importe
from erp.journal_lines l
join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
join erp.fiscal_years fy on fy.id = e.fiscal_year_id
where e.company_id in (select bi.demo_companies());

-- Saldo de cada cuenta a cada fin de mes (acumulado del ejercicio, sin los asientos de regularización y cierre, como
-- el ERP) y su línea del balance o de la PyG YA DECIDIDA por el ERP (en el balance depende del signo: un banco en
-- descubierto va al pasivo). Importe con el signo con que se enseña: activo y pasivo en positivo; en la PyG, los
-- ingresos en positivo y los gastos en negativo.
create or replace view bi.fact_saldos_mes as
with fy as (
  select fy.id, fy.company_id, fy.year, fy.starting_date, fy.ending_date
  from erp.fiscal_years fy where fy.company_id in (select bi.demo_companies())
), meses as (
  select fy.id as fy_id, fy.company_id, fy.year,
         least((date_trunc('month', m) + interval '1 month - 1 day')::date, fy.ending_date) as fin_mes
  from fy, generate_series(date_trunc('month', fy.starting_date), fy.ending_date, interval '1 month') m
), mov as (
  select e.fiscal_year_id, g.account_no, e.posting_date, sum(l.debit - l.credit) as imp
  from erp.journal_lines l
  join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted' and e.entry_type not in ('closing_pl', 'closing')
  join erp.gl_accounts g on g.id = l.gl_account_id
  where e.fiscal_year_id in (select id from fy)
  group by 1, 2, 3
), acum as (
  select m.company_id, m.year, m.fin_mes, mv.account_no, sum(mv.imp) as saldo
  from meses m join mov mv on mv.fiscal_year_id = m.fy_id and mv.posting_date <= m.fin_mes
  group by 1, 2, 3, 4
  having sum(mv.imp) <> 0
), est as (
  select 'balance' as estado union all select 'pyg'
)
select a.company_id as empresa_id, a.year as ejercicio, a.fin_mes, g.id as cuenta_id, a.account_no as subcuenta,
       est.estado, est.estado || '|' || m.line as clave_hoja, a.saldo,
       a.saldo * case fl.side when 'debit' then 1 else -1 end as importe
from acum a
join erp.gl_accounts g on g.company_id = a.company_id and g.account_no = a.account_no
cross join est
cross join lateral (
  select case when a.saldo >= 0 then fm.debit_line else fm.credit_line end as line
  from erp.fs_mapping fm
  where fm.statement = est.estado and a.account_no like fm.prefix || '%'
  order by length(fm.prefix) desc limit 1) m
join erp.fs_lines fl on fl.statement = est.estado and fl.code = m.line
where est.estado = 'balance' or left(a.account_no, 1) in ('6', '7');

-- Flujos de efectivo de cada ejercicio, ya clasificados por el ERP (método indirecto y directo)
create or replace function bi.f_flujos()
returns table (empresa_id uuid, ejercicio int, estado text, clave_hoja text, subcuenta text, nombre text, importe numeric)
language sql stable security definer set search_path = erp, public as $$
  select fy.company_id, fy.year, x.estado, x.estado || '|' || d.line_code, d.account_no, d.account_name, d.amount
  from erp.fiscal_years fy
  cross join (values ('indirect', 'efe_indirecto'), ('direct', 'efe_directo')) x(metodo, estado)
  cross join lateral erp.cf_detail(fy.company_id, fy.year, x.metodo) d
  where fy.company_id in (select bi.demo_companies()) and d.amount <> 0;
$$;
create or replace view bi.fact_flujos as select * from bi.f_flujos();

-- ---------- Comprobación: las cifras que enseña el ERP ----------
-- Balance y PyG a cada fin de mes (con sus totales); flujos y ratios por ejercicio
create or replace function bi.f_control_estados()
returns table (empresa_id uuid, ejercicio int, fecha date, estado text, clave_linea text, importe numeric, numerador numeric, denominador numeric)
language sql stable security definer set search_path = erp, public as $$
  with fy as (
    select fy.company_id, fy.year, fy.starting_date, fy.ending_date
    from erp.fiscal_years fy where fy.company_id in (select bi.demo_companies())
  ), meses as (
    select fy.company_id, fy.year, least((date_trunc('month', m) + interval '1 month - 1 day')::date, fy.ending_date) as fin_mes
    from fy, generate_series(date_trunc('month', fy.starting_date), fy.ending_date, interval '1 month') m
  ), cf as (
    select fy.company_id, fy.year, fy.ending_date, x.estado, x.metodo, d.line_code, sum(d.amount) as amount
    from fy
    cross join (values ('indirect', 'efe_indirecto'), ('direct', 'efe_directo')) x(metodo, estado)
    cross join lateral erp.cf_detail(fy.company_id, fy.year, x.metodo) d
    group by 1, 2, 3, 4, 5, 6
  )
  select m.company_id, m.year, m.fin_mes, s.st, s.st || '|' || a.code, a.amount, null::numeric, null::numeric
  from meses m
  cross join (values ('balance'), ('pyg')) s(st)
  cross join lateral erp.fs_amounts(m.company_id, m.year, s.st, m.fin_mes) a
  union all
  select cf.company_id, cf.year, cf.ending_date, cf.estado, p.clave_linea, sum(cf.amount), null, null
  from cf join bi.puente_linea p on p.clave_hoja = cf.estado || '|' || cf.line_code
  group by 1, 2, 3, 4, 5
  union all
  select fy.company_id, fy.year, fy.ending_date, 'ratio', 'ratio|' || r.code,
         case when r.den is null then r.num when r.den <> 0 then round(r.num / r.den, 4) end, r.num, r.den
  from fy cross join lateral erp.ratio_parts(fy.company_id, fy.year) r;
$$;
create or replace view bi.control_estados as select * from bi.f_control_estados();

comment on view bi.dim_empresa is 'Demo companies (only these reach Power BI).';
comment on view bi.dim_fecha is 'Calendar covering the fiscal years of the demo companies.';
comment on view bi.dim_cuenta is 'Posting accounts with their PGC account, subgroup and group.';
comment on view bi.dim_linea is 'Lines of the statements (balance, pyg, efe_indirecto, efe_directo): hierarchy for the matrices.';
comment on view bi.puente_linea is 'Bridge: each line (clave_linea) adds the amounts of every leaf line below it (clave_hoja).';
comment on view bi.dim_ratio is 'Ratio definitions; primera_entrega marks the 8 of the first release.';
comment on view bi.fact_apuntes is 'Posted journal lines of the demo companies.';
comment on view bi.fact_saldos_mes is 'Account balance at each month end (year to date) with its statement line already decided by the ERP.';
comment on view bi.fact_flujos is 'Cash flows of each fiscal year, already classified by the ERP (indirect and direct method).';
comment on view bi.control_estados is 'What the ERP shows (statements by month end, cash flows and ratios by year): to check Power BI.';

-- ---------- Permisos: powerbi_reader solo lee bi; nadie más desde la web ----------
revoke all on all tables in schema bi from public, anon, authenticated;
revoke all on all functions in schema bi from public, anon, authenticated;
grant usage on schema bi to powerbi_reader;
grant select on all tables in schema bi to powerbi_reader;
grant execute on all functions in schema bi to powerbi_reader;
