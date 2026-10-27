-- =====================================================================
-- PRUEBAS FASE 67 · Puente a Power BI (migración 0073 · v0.50.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.50.0.md): el esquema `bi` es un «contrato» de datos de solo lectura para
-- Power BI. Con el caso completo «Taller Atlántico SL» publicado como demo se comprueba que:
--   · Solo llegan las empresas demo (ni las demás ni una temporal, aunque esté marcada).
--   · Con `fact_saldos_mes` y el puente de líneas salen EXACTAMENTE el balance y la PyG del ERP a cada fin de mes.
--   · Con `fact_flujos` sale el estado de flujos del ERP por los dos métodos.
--   · Con esas cifras salen los 8 ratios de la primera entrega, iguales que en el ERP.
--   · `control_estados` enseña lo mismo que las pantallas del ERP.
--   · `powerbi_reader` lee `bi` y nada más; la web no ve `bi`.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;
create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
grant execute on function public.falla(text, text) to authenticated, powerbi_reader;

-- Lo que calcula Power BI con el contrato: cada línea suma sus hojas (el puente)
create or replace function public.pbi(st text) returns table (empresa_id uuid, fecha date, clave_linea text, importe numeric)
language sql as $$
  select f.empresa_id, f.fin_mes, p.clave_linea, sum(f.importe)
  from bi.fact_saldos_mes f join bi.puente_linea p on p.clave_hoja = f.clave_hoja
  where f.estado = st group by 1, 2, 3;
$$;

-- ---------- Datos: el caso completo, otro caso sin publicar y una temporal marcada como demo ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
begin
  insert into public.ctx values ('demo', (erp.create_case_company('taller_atlantico', 'full')->>'company_id')::uuid);
  insert into public.ctx values ('privada', (erp.create_case_company('taller_atlantico', 'until_closing')->>'company_id')::uuid);
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
update erp.companies set is_demo = true where id = (select e from public.ctx where k = 'demo');
-- Una temporal marcada como demo a mano (desde la web no se puede): tampoco debe llegar
insert into erp.companies (name, industry, tax_territory, created_by, temporary, is_demo, expires_at, last_seen_at)
values ('Temporal SL', 'services', 'mainland', '00000000-0000-0000-0000-0000000000a1', true, true, now() + interval '1 day', now());

-- ---------- Solo las demo ----------
do $$
declare d uuid := (select e from public.ctx where k = 'demo');
begin
  assert (select array_agg(empresa_id) from bi.dim_empresa) = array[d], 'solo la empresa demo';
  assert (select impuesto from bi.dim_empresa) = 'IGIC', 'Canarias → IGIC';
  assert not exists (select 1 from bi.dim_cuenta where empresa_id <> d), 'cuentas, solo de la demo';
  assert not exists (select 1 from bi.fact_apuntes where empresa_id <> d), 'apuntes, solo de la demo';
  assert not exists (select 1 from bi.fact_saldos_mes where empresa_id <> d), 'saldos, solo de la demo';
  assert not exists (select 1 from bi.fact_flujos where empresa_id <> d), 'flujos, solo de la demo';
  assert not exists (select 1 from bi.control_estados where empresa_id <> d), 'comprobación, solo de la demo';
  raise notice 'OK  · solo llega la empresa demo (ni la privada ni una temporal marcada)';
end $$;

-- ---------- Modelo ----------
do $$
declare d uuid := (select e from public.ctx where k = 'demo');
begin
  assert (select count(*) from bi.fact_apuntes) = (select count(*) from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id
                                                    where e.company_id = d and e.status = 'posted'), 'un apunte por línea contabilizada';
  assert (select sum(debe) = sum(haber) from bi.fact_apuntes), 'los apuntes cuadran';
  assert not exists (select 1 from bi.fact_apuntes a where not exists (select 1 from bi.dim_cuenta c where c.cuenta_id = a.cuenta_id)), 'cada apunte tiene su cuenta';
  assert not exists (select 1 from bi.fact_apuntes a where not exists (select 1 from bi.dim_fecha f where f.fecha = a.fecha)), 'y su fecha';
  assert not exists (select 1 from bi.fact_saldos_mes s where not exists (select 1 from bi.dim_linea l where l.clave_linea = s.clave_hoja)), 'cada saldo, su línea';
  assert not exists (select 1 from bi.fact_flujos s where not exists (select 1 from bi.dim_linea l where l.clave_linea = s.clave_hoja)), 'cada flujo, su línea';
  assert (select count(distinct estado) from bi.dim_linea) = 4, 'balance, pyg y flujos por los dos métodos';
  assert (select count(*) from bi.dim_linea) = (select count(*) from erp.fs_lines) + (select count(*) from erp.cf_lines), 'todas las líneas';
  assert (select count(*) from bi.dim_ratio where primera_entrega) = 8, 'los 8 ratios de la primera entrega';
  assert (select count(*) from bi.dim_fecha where es_fin_mes) >= 12, 'calendario';
  raise notice 'OK  · el modelo en estrella: claves completas y apuntes que cuadran';
end $$;

-- ---------- Balance y PyG a cada fin de mes = los del ERP ----------
do $$
declare n int;
begin
  select count(*) into n from (
    select coalesce(c.empresa_id, p.empresa_id), coalesce(c.fecha, p.fecha), coalesce(c.clave_linea, p.clave_linea)
    from (select * from bi.control_estados where estado in ('balance', 'pyg')) c
    full join (select * from public.pbi('balance') union all select * from public.pbi('pyg')) p
      on p.empresa_id = c.empresa_id and p.fecha = c.fecha and p.clave_linea = c.clave_linea
    where coalesce(c.importe, 0) <> coalesce(p.importe, 0)) x;
  assert n = 0, n || ' cifras del balance o la PyG no cuadran';
  assert (select count(distinct fecha) from bi.control_estados where estado = 'balance') = 24, 'los 24 fines de mes (2026 y la apertura de 2027)';
  raise notice 'OK  · el balance y la PyG de Power BI (saldos + puente) cuadran al céntimo con el ERP en los 24 fines de mes';
end $$;

-- ---------- Lo mismo que las pantallas del ERP ----------
-- Lo que enseñan las pantallas, como el usuario (la web no ve bi)…
create table public.pantalla (estado text, codigo text, importe numeric);
grant all on public.pantalla to authenticated;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare d uuid := (select e from public.ctx where k = 'demo'); y int; fin date;
begin
  select year, ending_date into y, fin from erp.fiscal_years where company_id = d order by year limit 1;
  insert into public.pantalla select 'balance', code, amount from erp.financial_statement(d, y, 'balance', fin);
  insert into public.pantalla select 'pyg', code, amount from erp.financial_statement(d, y, 'pyg', fin);
  insert into public.pantalla select 'efe_indirecto', code, amount from erp.cash_flow_statement(d, y, 'indirect');
  insert into public.pantalla select 'efe_directo', code, amount from erp.cash_flow_statement(d, y, 'direct');
  insert into public.pantalla select 'ratio', code, value from erp.financial_ratios(d, y);
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false) \gset
-- …frente a lo que lee Power BI
do $$
declare d uuid := (select e from public.ctx where k = 'demo'); y int; fin date; n int;
begin
  select year, ending_date into y, fin from erp.fiscal_years where company_id = d order by year limit 1;
  select count(*) into n from public.pantalla s
  left join bi.control_estados c on c.empresa_id = d and c.ejercicio = y and c.clave_linea = s.estado || '|' || s.codigo
                                and (s.estado not in ('balance', 'pyg') or c.fecha = fin)
  where c.importe is distinct from s.importe and not (c.importe is null and s.importe = 0);
  assert n = 0, n || ' cifras de la comprobación distintas de las pantallas';
  select count(*) into n from public.pantalla s
  left join (select p.clave_linea, sum(x.importe) as importe from bi.fact_flujos x
             join bi.puente_linea p on p.clave_hoja = x.clave_hoja where x.empresa_id = d and x.ejercicio = y group by 1) f
    on f.clave_linea = s.estado || '|' || s.codigo
  where s.estado like 'efe%' and coalesce(f.importe, 0) <> s.importe;
  assert n = 0, n || ' líneas de flujos distintas de la pantalla';
  assert (select count(*) from public.pantalla where estado = 'ratio') = 21, 'los 21 ratios';
  raise notice 'OK  · lo mismo que las pantallas del ERP: balance, PyG, flujos por los dos métodos y los 21 ratios';
end $$;

-- ---------- Los 8 ratios de la primera entrega salen de las cifras de Power BI ----------
do $$
declare d uuid := (select e from public.ctx where k = 'demo'); y int; fin date; b jsonb; p jsonb; r jsonb;
  pn numeric;
begin
  select year, ending_date into y, fin from erp.fiscal_years where company_id = d order by year limit 1;
  select jsonb_object_agg(replace(clave_linea, 'balance|', ''), importe) into b from public.pbi('balance') where fecha = fin;
  select jsonb_object_agg(replace(clave_linea, 'pyg|', ''), importe) into p from public.pbi('pyg') where fecha = fin;
  select jsonb_object_agg(replace(clave_linea, 'ratio|', ''), importe) into r from bi.control_estados where estado = 'ratio' and ejercicio = y;
  pn := (b->>'PN')::numeric;
  assert (b->>'AC')::numeric - (b->>'PC')::numeric = (r->>'WC')::numeric, 'fondo de maniobra';
  assert round((b->>'AC')::numeric / (b->>'PC')::numeric, 4) = (r->>'CR')::numeric, 'liquidez general';
  assert round(((b->>'AC')::numeric - coalesce((b->>'AC.I')::numeric, 0)) / (b->>'PC')::numeric, 4) = (r->>'QR')::numeric, 'prueba ácida';
  assert round(((b->>'PNC')::numeric + (b->>'PC')::numeric) / (pn + (b->>'PNC')::numeric + (b->>'PC')::numeric), 4) = (r->>'DEBT')::numeric, 'endeudamiento';
  assert round((p->>'PA')::numeric / (b->>'ACT')::numeric, 4) = (r->>'ROA')::numeric, 'ROA';
  assert round((p->>'PD')::numeric / pn, 4) = (r->>'ROE')::numeric, 'ROE';
  assert round((p->>'PD')::numeric / (p->>'P1')::numeric, 4) = (r->>'NPM')::numeric, 'margen neto';
  assert (p->>'PA')::numeric - coalesce((p->>'P8')::numeric, 0) = (r->>'EBITDA')::numeric, 'EBITDA (la amortización, en negativo en la PyG)';
  assert (b->>'ACT')::numeric = pn + (b->>'PNC')::numeric + (b->>'PC')::numeric, 'y el balance cuadra: activo = patrimonio neto + pasivo';
  raise notice 'OK  · los 8 ratios salen de las cifras de Power BI igual que en el ERP (FM %, liquidez %, ROE %)', r->>'WC', r->>'CR', r->>'ROE';
end $$;

-- ---------- Al despublicar, desaparece ----------
do $$
begin
  update erp.companies set is_demo = false where id = (select e from public.ctx where k = 'demo');
  assert not exists (select 1 from bi.dim_empresa) and not exists (select 1 from bi.fact_saldos_mes), 'sin demo, sin datos';
  update erp.companies set is_demo = true where id = (select e from public.ctx where k = 'demo');
  raise notice 'OK  · al quitar la marca de demo, la empresa desaparece de Power BI en el siguiente refresco';
end $$;

-- ---------- Permisos ----------
set role powerbi_reader;
do $$
begin
  perform count(*) from bi.dim_empresa; perform count(*) from bi.dim_fecha; perform count(*) from bi.dim_cuenta;
  perform count(*) from bi.dim_linea; perform count(*) from bi.puente_linea; perform count(*) from bi.dim_ratio;
  perform count(*) from bi.fact_apuntes; perform count(*) from bi.fact_saldos_mes; perform count(*) from bi.fact_flujos;
  assert (select count(*) from bi.control_estados) > 0, 'Power BI lee todo bi';
  assert public.falla('select count(*) from erp.companies', 'permission denied'), 'pero nada del ERP';
  assert public.falla('select count(*) from erp.journal_lines', 'permission denied'), 'ni los asientos';
  raise notice 'OK  · powerbi_reader lee todo bi y nada del ERP';
end $$;
reset role;
set role authenticated;
do $$
begin
  assert public.falla('select count(*) from bi.dim_empresa', 'permission denied'), 'la web no ve bi';
  assert public.falla('select count(*) from bi.control_estados', 'permission denied'), 'ni la comprobación';
  raise notice 'OK  · la web (authenticated) no ve bi';
end $$;
reset role;
