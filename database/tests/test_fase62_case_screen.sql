-- =====================================================================
-- PRUEBAS FASE 62 · Pantalla «Casos» (migraciones 0067 y 0068 · v0.46.0)
-- ---------------------------------------------------------------------
-- Diseño validado: diseno-v0.46.0.md.
--   · erp.create_case_company crea la empresa del caso (modo estricto, con el límite de empresas) y lo carga.
--   · «Completo»: las 19 operaciones hechas, cada una con sus asientos; las 97 cifras, iguales al documento.
--   · «Hasta el cierre»: las operaciones 1 a 10; las del cierre, pendientes, y sus cifras, «pendiente» (no «diferencia»).
--     Quien estudia hace el cierre con los módulos y entonces todo cuadra.
--   · Permisos, límite de empresas y borrar la empresa del caso.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null),
                                                                     ('00000000-0000-0000-0000-0000000000b2', 'member', 1);
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
grant execute on function public.falla(text, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- «Completo» ----------
do $$
declare x jsonb; e uuid; s text; n int;
begin
  x := erp.create_case_company('taller_atlantico', 'full');
  e := (x->>'company_id')::uuid;
  insert into public.ctx values ('full', e);
  assert x->>'name' = 'Taller Atlántico SL' and x->>'mode' = 'full', 'empresa del caso: ' || x::text;
  assert (select name || '/' || tax_territory || '/' || legal_form || '/' || control_mode || '/' || case_key || '/' || case_mode
          from erp.companies where id = e) = 'Taller Atlántico SL/canary_islands/sl/strict/taller_atlantico/full', 'ficha de la empresa';
  -- las 19 operaciones, hechas, con sus asientos
  select count(*), string_agg(p.n::text, ',') filter (where p.status <> 'done') into n, s from erp.case_progress(e) p;
  assert n = 19 and s is null, 'operaciones: ' || n || ' · pendientes: ' || coalesce(s, '-');
  assert (select jsonb_array_length(entries) from erp.case_progress(e) p where p.n = 1) = 3, 'constitución: tres asientos';
  assert (select jsonb_array_length(entries) from erp.case_progress(e) p where p.n = 10) = 10, 'IGIC y retenciones: 4 liquidaciones y 6 pagos';
  assert (select string_agg((x2->>'year'), ',' order by x2->>'year') from erp.case_progress(e) p, jsonb_array_elements(p.entries) x2 where p.n = 19)
       like '%2027%', 'el cierre lleva la apertura de 2027';
  assert (select jsonb_array_length(entries) from erp.case_progress(e) p where p.n = 14) = 0
     and (select status from erp.case_progress(e) p where p.n = 14) = 'done', 'reclasificación: no hay asiento, pero está hecha';
  assert (select count(*) from erp.case_entries where company_id = e) = (select count(*) from erp.journal_entries where company_id = e),
         'cada asiento es de una operación';
  -- las cifras
  select string_agg(kind || ' ' || code, ', ') filter (where status <> 'ok') into s from erp.case_compare(e);
  assert s is null, 'diferencias: ' || s;
  assert (select string_agg(distinct status, ',') from erp.case_compare(e)) = 'ok', 'todas ok';
  -- el texto de cada operación, en los dos idiomas, y su pantalla
  assert not exists (select 1 from erp.case_steps where case_key = 'taller_atlantico'
                     and (title_en = '' or why_en = '' or screen not in ('equity', 'invoices', 'assets', 'grants', 'financing', 'entry',
                          'settlement', 'adjustments', 'corporate_tax', 'closing'))), 'textos y pantallas';
  raise notice 'OK  · completo: empresa en modo estricto, 19 operaciones hechas con sus asientos y 97 cifras iguales al documento';
end $$;

-- ---------- Lo que necesita la web (0068) ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'full');
begin
  assert (select case_key || '/' || case_mode from erp.v_my_companies where id = e) = 'taller_atlantico/full', 'mis empresas: el caso';
  assert not exists (select 1 from erp.case_compare(e) where kind in ('pyg', 'balance', 'cf_indirect', 'cf_direct') and (label is null or label_en is null)),
         'cada partida de los estados, con su nombre';
  assert (select label from erp.case_compare(e) where kind = 'pyg' and code = 'PD') like '%RESULTADO DEL EJERCICIO%', 'nombre del resultado';
  assert (select label_en from erp.case_compare(e) where kind = 'balance' and code = 'ACT') like '%TOTAL%', 'nombre en inglés';
  raise notice 'OK  · la web: mis empresas dicen el caso y la comparación trae el nombre de cada partida';
end $$;

-- ---------- Un segundo caso: otro nombre ----------
do $$
declare x jsonb;
begin
  x := erp.create_case_company('taller_atlantico', 'until_closing');
  insert into public.ctx values ('until', (x->>'company_id')::uuid);
  assert x->>'name' = 'Taller Atlántico SL (2)', 'el segundo: ' || (x->>'name');
  assert public.falla($q$select erp.create_case_company('taller_atlantico', 'otro')$q$, 'Invalid case mode'), 'modo desconocido';
  assert public.falla($q$select erp.create_case_company('otro', 'full')$q$, 'Unknown case'), 'caso desconocido';
  raise notice 'OK  · el segundo caso se llama «Taller Atlántico SL (2)»; modo o caso desconocido, no';
end $$;

-- ---------- «Hasta el cierre» ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'until'); s text; f uuid; v_ret uuid;
begin
  assert (select case_mode from erp.companies where id = e) = 'until_closing', 'modo';
  select string_agg(p.n::text, ',' order by p.n) into s from erp.case_progress(e) p where p.status = 'pending';
  assert s = '11,12,13,14,15,16,17,18,19', 'pendientes: ' || coalesce(s, '-');
  assert (select fy.status from erp.fiscal_years fy where fy.company_id = e and fy.year = 2026) = 'open', 'el año, abierto';
  -- antes del cierre: lo que no cuadra está «pendiente», no es una diferencia
  assert not exists (select 1 from erp.case_compare(e) where status = 'diff'), 'sin diferencias antes del cierre';
  assert (select count(*) from erp.case_compare(e) where status = 'pending') > 0, 'hay cifras pendientes';
  assert (select status from erp.case_compare(e) where kind = 'pyg' and code = 'P1') = 'ok'
     and (select status from erp.case_compare(e) where kind = 'tax_form' and code = '4.45') = 'ok', 'las ventas y el 420 ya cuadran';
  -- el cierre, hecho por quien estudia, con cada módulo
  perform erp.post_depreciation(e, '2026-12-31');
  assert (select status from erp.case_progress(e) p where p.n = 11) = 'done', 'amortización hecha (paso del asistente)';
  perform erp.grant_year_end(e, '2026-12-31');
  perform erp.loan_year_end(e, '2026-12-31');
  perform erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'prepaid_expense', 'description', 'Seguro',
    'pl_account_no', '62500001', 'cutoff_date', '2026-12-31', 'total_amount', 1200, 'coverage_start', '2026-10-01', 'coverage_months', 12));
  select i.id into f from erp.invoices i join erp.business_partners b on b.id = i.partner_id where i.company_id = e and b.name = 'Cliente Dudoso SL';
  perform erp.impair_receivable(jsonb_build_object('invoice_id', f, 'impair_date', '2026-12-31'));
  perform erp.post_inventory(jsonb_build_object('company_id', e, 'count_date', '2026-12-31', 'lines', '[{"account_no": "30000001", "final_value": 8000}]'::jsonb));
  v_ret := erp.corporate_tax_prepare(e, 2026);
  perform erp.corporate_tax_settings(v_ret, 'new_entity', false);
  perform erp.corporate_tax_calc(e, 2026);
  perform erp.corporate_tax_post(e, 2026);
  perform erp.close_fiscal_year(e, 2026, true);
  select string_agg(p.n::text, ',' order by p.n) into s from erp.case_progress(e) p where p.status = 'pending';
  assert s is null, 'después del cierre, pendientes: ' || s;
  select string_agg(kind || ' ' || code, ', ') into s from erp.case_compare(e) where status <> 'ok';
  assert s is null, 'después del cierre, diferencias: ' || s;
  raise notice 'OK  · hasta el cierre: operaciones 11 a 19 pendientes y sus cifras «pendiente»; con el cierre hecho, todo cuadra';
end $$;

-- ---------- Un cierre mal hecho: «diferencia» ----------
do $$
declare x jsonb := erp.create_case_company('taller_atlantico', 'until_closing'); e uuid := (x->>'company_id')::uuid; v_ret uuid; n int;
begin
  insert into public.ctx values ('mal', e);
  -- se olvida la amortización, la subvención, el préstamo y los ajustes: solo el impuesto
  v_ret := erp.corporate_tax_prepare(e, 2026);
  perform erp.corporate_tax_settings(v_ret, 'new_entity', false);
  perform erp.corporate_tax_calc(e, 2026);
  perform erp.corporate_tax_post(e, 2026);
  select count(*) into n from erp.case_compare(e) where status = 'diff';
  assert n > 0 and (select status from erp.case_compare(e) where kind = 'pyg' and code = 'P8') = 'diff', 'diferencias: ' || n;
  assert (select difference from erp.case_compare(e) where kind = 'pyg' and code = 'P8') = 3000, 'falta la amortización: 3.000';
  raise notice 'OK  · un cierre incompleto sale como diferencia (falta la amortización: 3.000)';
end $$;

-- ---------- Permisos, límite de empresas y borrar ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'full'); x jsonb;
begin
  assert public.falla(format('select * from erp.case_progress(%L)', e), 'Not allowed'), 'otro usuario no ve el progreso';
  assert public.falla(format('select erp.case_mark(%L, 1)', e), 'No permission'), 'ni apunta asientos';
  assert (select count(*) from erp.case_entries where company_id = e) = 0, 'ni los ve';
  x := erp.create_case_company();          -- con su única empresa
  assert x->>'name' = 'Taller Atlántico SL' and x->>'mode' = 'full', 'el suyo: ' || x::text;
  assert public.falla('select erp.create_case_company()', 'Company limit reached'), 'límite de empresas';
  raise notice 'OK  · otro usuario: no ve ni toca el caso ajeno; carga el suyo y respeta su límite de empresas';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'mal'); v int;
begin
  loop v := erp.delete_company_step(e); exit when v = 0; end loop;
  assert not exists (select 1 from erp.companies where id = e) and not exists (select 1 from erp.case_entries where company_id = e),
         'empresa del caso borrada';
  raise notice 'OK  · la empresa del caso se borra entera';
end $$;
select set_config('request.jwt.claim.sub', '', false) \gset
do $$ begin
  assert public.falla('select erp.create_case_company()', 'Sign in'), 'sin sesión, no';
  raise notice 'OK  · sin sesión no se carga un caso';
end $$;
reset role;
