-- =====================================================================
-- PRUEBAS FASE 2 · empresas demo y límites por usuario (migración 0007)
-- Ejecutar en una base limpia: stub + migraciones 0001-0007 (sin test_fase1 antes).
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'visitante@test.local');

-- El propietario se nombra desde el SQL Editor (como harás en Supabase)
insert into erp.app_profiles (user_id, app_role, max_companies)
values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.debe_fallar(p_sql text, p_texto text, p_prueba text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm ilike '%' || p_texto || '%' then
      raise notice 'OK  · %  →  %', p_prueba, sqlerrm;
      return;
    end if;
    raise exception 'FALLO · % · error inesperado: %', p_prueba, sqlerrm;
  end;
  raise exception 'FALLO · % · debía dar error y no lo dio', p_prueba;
end $$;
grant execute on function public.debe_fallar(text, text, text) to authenticated;
create table public.ctx (clave text primary key, valor uuid);
grant all on public.ctx to authenticated;

set role authenticated;

-- ---------- Propietario ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare d uuid; p uuid; ej uuid; a uuid; c1 uuid; c2 uuid;
begin
  assert (select app_role from erp.my_profile()) = 'owner';
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Demo Canarias SL', 'services', 'canary_islands', auth.uid()) returning id into d;
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Privada del owner', 'retail', 'mainland', auth.uid()) returning id into p;
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Tercera del owner', 'retail', 'mainland', auth.uid());
  raise notice 'OK  · el owner crea empresas sin límite (3)';

  update erp.companies set is_demo = true where id = d;
  raise notice 'OK  · el owner publica una empresa como demo';

  ej := erp.create_fiscal_year(d, 2026);
  c1 := erp.create_posting_account(d, '57200001', 'Banco');
  c2 := erp.create_posting_account(d, '10000001', 'Capital');
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (d, ej, '2026-01-02', 'Constitución') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)  values (a, c1, 3000);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, c2, 3000);
  perform erp.post_entry(a);

  insert into public.ctx values ('demo', d), ('privada', p), ('ejercicio_demo', ej), ('banco_demo', c1);
end $$;

-- ---------- Visitante (member) ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare
  d  uuid := (select valor from public.ctx where clave = 'demo');
  p  uuid := (select valor from public.ctx where clave = 'privada');
  ej uuid := (select valor from public.ctx where clave = 'ejercicio_demo');
  c1 uuid := (select valor from public.ctx where clave = 'banco_demo');
  mine uuid;
begin
  assert (select app_role from erp.my_profile()) = 'member';
  assert (select max_companies from erp.my_profile()) = 1;

  -- Ve la demo y su contabilidad, pero no las empresas privadas del owner
  assert (select count(*) from erp.companies where id = d) = 1, 'debe ver la demo';
  assert (select count(*) from erp.companies where id = p) = 0, 'NO debe ver la privada';
  assert (select count(*) from erp.v_general_journal where company_id = d) = 2, 'debe ver el diario de la demo';
  assert (select count(*) from erp.trial_balance(d, 2026)) = 2, 'debe ver sumas y saldos de la demo';
  assert (select count(*) from erp.gl_accounts where company_id = d) = 364;   -- 362 del PGC (0021) + 2 subcuentas
  assert (select my_role from erp.v_my_companies where id = d) is null, 'en la demo no tiene rol';
  assert (select count(*) from erp.company_users where company_id = d) = 0, 'no ve el equipo de la demo';
  raise notice 'OK  · el visitante ve la empresa demo y sus informes, no las privadas';

  -- No puede escribir en la demo
  perform public.debe_fallar(format('insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (%L,%L,%L,%L)',
                                    d, ej, '2026-02-01', 'x'), 'row-level security', 'no crea asientos en la demo');
  perform public.debe_fallar(format('select erp.create_posting_account(%L, %L, %L)', d, '43000001', 'x'),
                             'row-level security', 'no crea subcuentas en la demo');
  update erp.companies set name = 'hackeada' where id = d;   -- RLS: 0 filas afectadas, sin error
  update erp.accounting_periods set status = 'closed' where fiscal_year_id = ej;
  perform public.debe_fallar(format('select erp.delete_company(%L)', d), 'Only the company admin', 'no borra la demo');
  raise notice 'OK  · el visitante no puede modificar nada de la demo';

  -- Su propia empresa: 1 y con todas las funciones
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Mi empresa', 'services', 'canary_islands', auth.uid()) returning id into mine;
  assert (select my_role from erp.v_my_companies where id = mine) = 'admin';
  perform erp.create_fiscal_year(mine, 2026);
  perform erp.create_posting_account(mine, '57200001', 'Banco');
  raise notice 'OK  · el visitante crea 1 empresa y es admin de ella';

  perform public.debe_fallar(format('insert into erp.companies (name, industry, tax_territory, created_by) values (%L,%L,%L,auth.uid())',
                                    'Segunda', 'retail', 'mainland'), 'Company limit reached', 'no puede crear una segunda empresa');
  perform public.debe_fallar(format('update erp.companies set is_demo = true where id = %L', mine),
                             'Only the application owner', 'no puede publicar su empresa como demo');
  perform public.debe_fallar('insert into erp.app_profiles (user_id, app_role) values (auth.uid(), ''owner'')',
                             'permission denied', 'no puede hacerse owner');
end $$;

-- ---------- Comprobaciones como administrador ----------
reset role;
do $$
declare d uuid := (select valor from public.ctx where clave = 'demo');
begin
  assert (select name from erp.companies where id = d) = 'Demo Canarias SL', 'el nombre de la demo no debe cambiar';
  assert (select count(*) from erp.accounting_periods p join erp.fiscal_years f on f.id = p.fiscal_year_id
          where f.company_id = d and p.status = 'closed') = 0, 'los periodos de la demo no deben cerrarse';
  raise notice 'OK  · la demo sigue intacta';
end $$;

-- ---------- El owner despublica: el visitante deja de verla ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
update erp.companies set is_demo = false where id = (select valor from public.ctx where clave = 'demo');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$ begin
  assert (select count(*) from erp.companies where id = (select valor from public.ctx where clave = 'demo')) = 0;
  raise notice 'OK  · al despublicar, el visitante deja de verla';
end $$;

reset role;
drop table public.ctx;
drop function public.debe_fallar(text, text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 2 (DEMO) PASARON ==========='
