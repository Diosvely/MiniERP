-- =====================================================================
-- PRUEBAS FASE 24 · Solo el owner nombra titulares de los datos (migración 0030)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'amigo@test.local'),
  ('00000000-0000-0000-0000-0000000000c3', 'curioso@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
create or replace function public.como(u text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000' || u, false);
$$;
grant execute on function public.falla(text, text), public.como(text) to authenticated;

set role authenticated;

do $$
declare e_owner uuid; e_curioso uuid;
begin
  -- ---------- El owner importa una empresa y nombra Miembro (titular de los datos) al amigo ----------
  perform public.como('a1');
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Empresa del Amigo SL', 'services', 'mainland', auth.uid()) returning id into e_owner;
  perform erp.grant_company_access(e_owner, 'amigo@test.local', 'accountant', true);
  assert (select data_owner from erp.company_users
          where company_id = e_owner and user_id = '00000000-0000-0000-0000-0000000000b2'), 'el owner nombra titular';
  raise notice 'OK  · el owner sigue pudiendo nombrar titulares con grant_company_access';

  -- ---------- Un usuario normal crea su empresa (queda como admin) e intenta nombrarse titular ----------
  perform public.como('c3');
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Empresa del Curioso SL', 'services', 'mainland', auth.uid()) returning id into e_curioso;
  assert public.falla(format($q$update erp.company_users set data_owner = true
                                where company_id = %L and user_id = auth.uid()$q$, e_curioso), 'only the application owner');
  assert not erp.is_data_owner(e_curioso), 'no es titular';
  assert not erp.ai_allowed(e_curioso), 'sin IA';
  assert public.falla(format($q$select erp.set_company_demo(%L, true, 'spam')$q$, e_curioso), 'only the application owner or the data owner');
  raise notice 'OK  · un admin no puede nombrarse titular, ni usar la IA, ni publicar su empresa como demo';

  -- ---------- Tampoco puede crear una fila nueva como titular ----------
  assert public.falla(format($q$insert into erp.company_users (company_id, user_id, role, data_owner)
                                values (%L, '00000000-0000-0000-0000-0000000000b2', 'viewer', true)$q$, e_curioso),
                      'only the application owner');
  raise notice 'OK  · un admin no puede añadir a otro usuario como titular';

  -- ---------- El Miembro conserva sus permisos ----------
  perform public.como('b2');
  assert erp.is_data_owner(e_owner), 'el amigo sigue siendo titular';
  perform erp.set_company_demo(e_owner, true, 'Datos cedidos por el amigo');
  assert (select is_demo from erp.companies where id = e_owner), 'el titular publica su demo';
  raise notice 'OK  · el titular de los datos sigue publicando su empresa como demo';
end $$;

reset role;
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 24 (TITULARES DE LOS DATOS) PASARON ==========='
