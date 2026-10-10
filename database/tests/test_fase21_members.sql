-- =====================================================================
-- PRUEBAS FASE 21 · Accesos, titulares de los datos y cuota de IA (migración 0027)
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
select public.como('a1') \gset

do $$
declare e uuid; otra uuid; k jsonb; i int;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Empresa del Amigo SL', 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Otra Empresa SL', 'services', 'mainland', auth.uid()) returning id into otra;

  -- ---------- El owner da acceso por email (como Miembro: contable + titular de los datos) ----------
  assert public.falla(format($q$select erp.grant_company_access(%L, 'nadie@test.local', 'accountant', true)$q$, e), 'no registered user');
  assert public.falla(format($q$select erp.grant_company_access(%L, 'AMIGO@test.local', 'jefe', true)$q$, e), 'unknown role');
  perform erp.grant_company_access(e, ' AMIGO@test.local ', 'accountant', true);
  assert (select count(*) from erp.company_access(e)) = 2, 'el owner (admin) y el amigo';
  assert (select data_owner and role = 'accountant' from erp.company_access(e) where email = 'amigo@test.local');
  assert erp.ai_allowed(e) and (erp.ai_status(e)->>'limit') is null, 'el owner: IA sin límite';

  -- ---------- El Miembro ----------
  perform public.como('b2');
  assert (select count(*) from erp.v_my_companies where my_role is not null) = 1, 'solo ve su empresa';
  assert (select is_data_owner from erp.v_my_companies where id = e);
  assert erp.ai_allowed(e) and not erp.ai_allowed(otra), 'IA solo en su empresa';
  assert (erp.ai_status(e)->>'limit')::int = 10;
  k := erp.ai_context(e, 2026);
  assert k->>'year' = '2026', 'el Analista IA le funciona';
  k := erp.entry_tutor_context(e);
  assert jsonb_array_length(k->'valuation_rules') = 23, 'el Tutor también';
  -- Puede contabilizar (contable): crea una subcuenta como hace el tutor
  perform erp.create_posting_account(e, '62900001', 'Otros servicios');
  -- Pero no gestiona accesos ni ve la lista
  assert public.falla(format($q$select erp.grant_company_access(%L, 'curioso@test.local', 'viewer')$q$, e), 'only the application owner');
  assert public.falla(format('select * from erp.company_access(%L)', e), 'only the application owner');
  -- Publica él su demo, con su mención
  perform erp.set_company_demo(e, true, 'Datos del curso de Amigo');
  assert (select is_demo and data_credit = 'Datos del curso de Amigo' from erp.companies where id = e);
  perform erp.set_company_demo(e, false);
  assert (select not is_demo and data_credit = 'Datos del curso de Amigo' from erp.companies where id = e), 'despublica y la mención se queda';
  assert public.falla(format('select erp.set_company_demo(%L, true)', otra), 'data owner');
  -- Cuota: 10 al día
  for i in 1..10 loop perform erp.ai_consume(e); end loop;
  assert public.falla(format('select erp.ai_consume(%L)', e), 'daily ai limit');
  -- Opina sobre la IA
  insert into erp.ai_feedback (company_id, kind, prompt, answer, verdict, comment, model)
  values (e, 'tutor', 'Vendo una furgoneta…', '{"lines": []}', 'wrong', 'La amortización va al Debe', 'gpt-oss');
  assert public.falla(format($q$insert into erp.ai_feedback (company_id, kind, answer, verdict) values (%L, 'tutor', '{}', 'correct')$q$, otra),
                      'row-level security');

  -- ---------- Un usuario cualquiera: ni la empresa, ni la IA ----------
  perform public.como('c3');
  assert not exists (select 1 from erp.v_my_companies where id = e), 'no la ve (no es demo)';
  assert not erp.ai_allowed(e);
  assert public.falla(format('select erp.ai_consume(%L)', e), 'not enabled');
  assert public.falla(format('select erp.ai_context(%L, 2026)', e), 'not enabled');
  assert public.falla(format('select erp.set_company_demo(%L, true)', e), 'data owner');
  assert (select count(*) from erp.ai_feedback) = 0, 'no ve opiniones ajenas';

  -- ---------- El owner ----------
  perform public.como('a1');
  assert (select count(*) from erp.ai_feedback where verdict = 'wrong') = 1, 'el owner lee las opiniones';
  assert (select ai_calls_today from erp.company_access(e) where email = 'amigo@test.local') = 10, 'la llamada rechazada no cuenta';
  -- Sube la cuota del amigo y le quita el acceso
  -- (la cuota de cada usuario se cambia en el SQL Editor: update erp.app_profiles set ai_daily_limit = …)
  perform erp.revoke_company_access(e, '00000000-0000-0000-0000-0000000000b2');
  assert (select count(*) from erp.company_access(e)) = 1;
  assert public.falla(format('select erp.revoke_company_access(%L, auth.uid())', e), 'your own access');
end $$;

\echo '=========== TODAS LAS PRUEBAS DE LA FASE 21 (ACCESOS Y TITULARES DE DATOS) PASARON ==========='
