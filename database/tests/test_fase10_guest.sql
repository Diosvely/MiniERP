-- =====================================================================
-- PRUEBAS FASE 10 · acceso de invitados a las demos (migración 0015)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
  ('00000000-0000-0000-0000-0000000000c3', null);           -- invitado (sin email)
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

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

-- El propietario publica una empresa demo y tiene otra privada
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare d uuid; p uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by, is_demo)
  values ('Demo Pública SL', 'services', 'canary_islands', auth.uid(), true) returning id into d;
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Privada SL', 'services', 'canary_islands', auth.uid()) returning id into p;
  perform erp.create_fiscal_year(d, 2026);
  perform erp.setup_taxes(d);
  perform erp.create_posting_account(d, '57200001', 'Banco');
  insert into public.ctx values ('demo', d), ('privada', p);
  assert not erp.is_anonymous();
  assert erp.can_write(d);
end $$;

-- ---------- Invitado ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', false) \gset
select set_config('request.jwt.claims', '{"is_anonymous": true}', false) \gset
do $$
declare d uuid := (select valor from public.ctx where clave = 'demo');
        p uuid := (select valor from public.ctx where clave = 'privada');
        r record;
begin
  assert erp.is_anonymous();
  select * into r from erp.my_profile();
  assert r.app_role = 'guest' and r.max_companies = 0, r::text;

  -- Ve la demo (empresa, cuentas, impuestos) y no la privada
  assert (select count(*) from erp.v_my_companies) = 1, 'solo la demo';
  assert (select name from erp.v_my_companies) = 'Demo Pública SL';
  assert (select count(*) from erp.gl_accounts where company_id = d) > 0;
  assert (select count(*) from erp.v_tax_setup where company_id = d) = 8;
  assert (select count(*) from erp.gl_accounts where company_id = p) = 0, 'la privada es invisible';
  raise notice 'OK  · el invitado ve la demo completa y no ve la empresa privada';

  -- No escribe nada
  assert not erp.can_write(d) and not erp.is_admin(d);
  perform public.debe_fallar(format('insert into erp.companies (name, industry, tax_territory, created_by) values (%L, %L, %L, auth.uid())',
          'Mía', 'services', 'mainland'), 'Guest visitors', 'el invitado crea una empresa');
  perform public.debe_fallar(format('select erp.create_posting_account(%L, %L, %L)', d, '57200002', 'Hack'),
          'row-level security', 'el invitado crea una cuenta en la demo');
  perform public.debe_fallar(format('select * from erp.create_partner(%L, %L, %L)', d, 'customer', 'Hack'),
          'No permission', 'el invitado crea un tercero');
  perform public.debe_fallar(format('select * from erp.setup_taxes(%L)', d), 'Only the company admin', 'el invitado configura impuestos');
  perform public.debe_fallar(format('select * from erp.post_tax_settlement(%L, %L, 2026, 1)', d, 'IGIC'), 'No permission', 'el invitado liquida');
  update erp.companies set is_demo = false where id = d;      -- la RLS no deja tocar la fila: 0 filas
  assert (select is_demo from erp.v_my_companies where id = d), 'la demo sigue publicada';
  raise notice 'OK  · el invitado no puede crear ni modificar nada';

  -- Sí guarda su idioma
  insert into erp.user_settings (user_id, language) values (auth.uid(), 'en')
  on conflict (user_id) do update set language = excluded.language;
  raise notice 'OK  · el invitado puede guardar su idioma';
end $$;

-- ---------- Un usuario registrado normal sigue igual ----------
select set_config('request.jwt.claims', '{}', false) \gset
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
begin
  assert not erp.is_anonymous();
  assert (select app_role from erp.my_profile()) = 'owner';
  assert erp.can_write((select valor from public.ctx where clave = 'demo'));
  raise notice 'OK  · un usuario registrado no se ve afectado';
end $$;

reset role;
drop table public.ctx;
drop function public.debe_fallar(text, text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 10 (INVITADOS) PASARON ==========='
