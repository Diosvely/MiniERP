-- =====================================================================
-- PRUEBAS FASE 81 · Empresas sintéticas con semilla (v0.59.0, paso 286 · migración 0086)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.59.0.md, 03-11-2026). Se comprueba:
--   · la misma semilla da la misma huella (con todos los identificadores internos distintos); otra semilla, otro
--     perfil u otros meses, otra; y la huella cambia si cambia un céntimo;
--   · cada perfil cumple los invariantes, cuadra con su liquidación (libro y cuentas), con el tablero de impuestos y
--     con la PyG, y su Balance cuadra;
--   · la lista de control: nada en los perfiles limpios y exactamente lo sembrado en «incidencias»;
--   · quién la crea y dónde (como al importar), sus límites, que no se publica como demo y que otro no ve su huella;
--   · rapidez.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'propietario@test.local'),
  ('00000000-0000-0000-0000-0000000000b1', 'miembro@test.local'),
  ('00000000-0000-0000-0000-0000000000c1', 'registrado@test.local');
insert into auth.users (id, email, is_anonymous) values ('00000000-0000-0000-0000-0000000000d1', null, true);
insert into erp.app_profiles (user_id, app_role, max_companies) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner', null),
  ('00000000-0000-0000-0000-0000000000b1', 'member', 20)
on conflict (user_id) do update set app_role = excluded.app_role, max_companies = excluded.max_companies;

create table public.ctx (k text primary key, e uuid, huella text);
grant all on public.ctx to authenticated;

create or replace procedure public.como(p_sub text, p_anon boolean default false) language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_sub, false);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_sub, 'is_anonymous', p_anon)::text, false);
end $$;
grant execute on procedure public.como(text, boolean) to authenticated;
create or replace function public.falla(p_sql text, p_msg text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || p_msg || '%' then return true; end if;
  raise exception 'Se esperaba «%» y salió «%»', p_msg, sqlerrm;
end $$;
grant execute on function public.falla(text, text) to authenticated;
create or replace function public.item(t jsonb, metric text) returns jsonb language sql as $$
  select i from jsonb_array_elements(t -> 'widgets') w, jsonb_array_elements(w -> 'items') i
  where i ->> 'code' = metric order by (w ->> 'kind') in ('kpis', 'table') limit 1;
$$;
grant execute on function public.item(jsonb, text) to authenticated;

set role authenticated;
call public.como('00000000-0000-0000-0000-0000000000b1');

-- ---------- 1. La misma semilla, la misma huella ----------
do $$
declare j jsonb; p text; t0 timestamptz; ms int;
begin
  foreach p in array array['services', 'trade', 'workshop', 'incidents'] loop
    t0 := clock_timestamp();
    j := erp.create_synthetic_company(4817, p, 12);
    ms := extract(epoch from clock_timestamp() - t0) * 1000;
    insert into public.ctx values (p, (j ->> 'company_id')::uuid, j ->> 'fingerprint');
    raise notice 'OK  · semilla 4817 · % · 12 meses: % asientos, huella %, % ms', p, j ->> 'entries', j ->> 'fingerprint', ms;
    assert ms < 15000, format('un año de %s en menos de 15 s: %s ms', p, ms);
    assert (j ->> 'entries')::int between 300 and 600, format('unas 25 operaciones al mes: %s asientos', j ->> 'entries');
  end loop;
  -- otra vez la misma: todos los identificadores internos son otros, la contabilidad es la misma
  j := erp.create_synthetic_company(4817, 'workshop', 12);
  insert into public.ctx values ('workshop_otra', (j ->> 'company_id')::uuid, j ->> 'fingerprint');
  assert j ->> 'fingerprint' = (select huella from public.ctx where k = 'workshop'), 'la misma semilla, la misma huella';
  assert j ->> 'name' = 'Sintética 4817 · Taller SL (2)', 'el nombre no se repite: ' || (j ->> 'name');
  assert (select count(*) from erp.journal_entries where company_id = (j ->> 'company_id')::uuid)
       = (select count(*) from erp.journal_entries where company_id = (select e from public.ctx where k = 'workshop')), 'los mismos asientos';
  -- otra semilla, otros meses u otro perfil: otra huella
  assert (erp.create_synthetic_company(4818, 'workshop', 12) ->> 'fingerprint') <> (select huella from public.ctx where k = 'workshop'),
    'otra semilla, otra huella';
  assert (erp.create_synthetic_company(4817, 'workshop', 6) ->> 'fingerprint') <> (select huella from public.ctx where k = 'workshop'),
    'otros meses, otra huella';
  assert (select count(distinct huella) from public.ctx where k in ('services', 'trade', 'workshop', 'incidents')) = 4, 'otro perfil, otra huella';
  assert (erp.create_synthetic_company(4817, 'services', 1) ->> 'entries')::int > 10, 'un solo mes también';
  raise notice 'OK  · la misma semilla da la misma huella; otra semilla, otros meses u otro perfil, otra';
end $$;

-- la huella cambia si cambia un céntimo (y no depende de los identificadores ni de las horas)
reset role;
set session_replication_role = replica;   -- un asiento contabilizado no se cambia: se salta la protección solo aquí
update erp.journal_lines set debit = debit + 0.01 where id = (select l.id from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  where j.company_id = (select e from public.ctx where k = 'workshop_otra') and l.debit > 0 order by j.entry_no, l.line_no limit 1);
set session_replication_role = origin;
set role authenticated;
call public.como('00000000-0000-0000-0000-0000000000b1');
do $$
begin
  assert erp.company_fingerprint((select e from public.ctx where k = 'workshop_otra')) <> (select huella from public.ctx where k = 'workshop'),
    'un céntimo cambia la huella';
  assert erp.company_fingerprint((select e from public.ctx where k = 'workshop')) = (select huella from public.ctx where k = 'workshop'),
    'la huella se puede volver a calcular';
  raise notice 'OK  · un céntimo cambia la huella';
end $$;

-- ---------- 2. Cada perfil cuadra ----------
do $$
declare r record; c uuid; t jsonb; q int; v text;
begin
  for r in select * from public.ctx where k in ('services', 'trade', 'workshop', 'incidents') loop
    c := r.e;
    assert not exists (select 1 from erp.integrity_checks(c, 2026) i where i.status = 'fail'),
      format('%s: invariantes · %s', r.k, (select string_agg(i.code, ', ') from erp.integrity_checks(c, 2026) i where i.status = 'fail'));
    assert (select x.amount from erp.financial_statement(c, 2026, 'balance', null) x where x.code = 'ACT')
         = (select x.amount from erp.financial_statement(c, 2026, 'balance', null) x where x.code = 'PNP'), r.k || ': el Balance cuadra';
    -- cada liquidación: el libro registro y las cuentas coinciden, y el tablero dice lo mismo
    assert not exists (select 1 from erp.tax_settlements s where s.company_id = c and s.status = 'posted' and s.register_difference <> 0),
      r.k || ': libro registro = cuentas en cada trimestre';
    t := erp.dashboard_data(c, 'impuestos', 2026);
    for q in select s.quarter from erp.tax_settlements s where s.company_id = c and s.status = 'posted' loop
      assert (public.item(t, 'TAX_RES') -> 'series' ->> (q - 1))::numeric
           = (select s.final_result from erp.tax_settlements s where s.company_id = c and s.year = 2026 and s.quarter = q and s.status = 'posted'),
        format('%s: el tablero de impuestos = la liquidación del %sT', r.k, q);
    end loop;
    assert (select count(*) from erp.tax_settlements s where s.company_id = c and s.status = 'posted') = case r.k when 'incidents' then 3 else 4 end,
      r.k || ': cuatro liquidaciones (tres en incidencias)';
    t := erp.dashboard_data(c, 'resumen', 2026);
    assert (public.item(t, 'SALES') ->> 'value')::numeric
         = (select x.amount from erp.financial_statement(c, 2026, 'pyg', null) x where x.code = 'P1'), r.k || ': ventas = PyG';
    v := erp.company_fingerprint(c);
    assert v = r.huella, r.k || ': la huella no cambia al leer';
  end loop;
  raise notice 'OK  · los cuatro perfiles: invariantes, Balance, liquidaciones (libro = cuentas = tablero) y ventas = PyG';
  -- lo propio de cada perfil
  c := (select e from public.ctx where k = 'trade');
  assert exists (select 1 from erp.business_partners where company_id = c and equivalence_surcharge), 'comercio: clientes en recargo';
  assert exists (select 1 from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
                 where l.company_id = c and g.account_no like '4770%' and g.name like 'Recargo de equivalencia%' and l.credit > 0),
    'comercio: recargo de equivalencia repercutido';
  assert not exists (select 1 from erp.payroll_runs where company_id = c), 'comercio: sin nóminas';
  c := (select e from public.ctx where k = 'workshop');
  assert (select tax_type from erp.tax_settlements where company_id = c limit 1) = 'IGIC', 'taller: IGIC';
  assert (select count(*) from erp.payroll_runs where company_id = c and status = 'posted') = 12, 'taller: doce nóminas';
  assert exists (select 1 from erp.fixed_assets where company_id = c) and exists (select 1 from erp.loans where company_id = c),
    'taller: una máquina y un préstamo';
  c := (select e from public.ctx where k = 'services');
  assert (select tax_type from erp.tax_settlements where company_id = c limit 1) = 'VAT', 'servicios: IVA';
  assert exists (select 1 from erp.invoices where company_id = c and withholding_code = 'IRPF19')
     and exists (select 1 from erp.invoices where company_id = c and withholding_code = 'IRPF15'), 'servicios: retenciones del 115 y del 111';
  raise notice 'OK  · comercio con recargo y sin nóminas; taller con IGIC, nóminas, máquina y préstamo; servicios con IVA, 111 y 115';
end $$;

-- ---------- 3. La lista de control: nada en los limpios, lo sembrado en «incidencias» ----------
do $$
declare r record; c uuid;
begin
  for r in select * from public.ctx where k in ('services', 'trade', 'workshop') loop
    assert not exists (select 1 from erp.quality_checks(r.e, 2026, '2026-12-31') q where q.severity not in ('ok', 'na', 'info')),
      format('%s: lista de control limpia · %s', r.k,
        (select string_agg(q.code || '=' || q.severity, ', ') from erp.quality_checks(r.e, 2026, '2026-12-31') q where q.severity not in ('ok', 'na', 'info')));
  end loop;
  c := (select e from public.ctx where k = 'incidents');
  assert (select string_agg(q.code || '=' || q.severity, ', ' order by q.code) from erp.quality_checks(c, 2026, '2026-12-31') q
          where q.severity not in ('ok', 'na', 'info'))
       = 'anomalies=warning, drafts=warning, overdue_in=error, settlements=error, unreconciled=warning',
    'incidencias: ' || (select string_agg(q.code || '=' || q.severity, ', ' order by q.code) from erp.quality_checks(c, 2026, '2026-12-31') q
                        where q.severity not in ('ok', 'na', 'info'));
  assert (select count(*) from erp.balance_anomalies(c, 2026) a where a.account_no like '400%') = 1, 'el proveedor deudor';
  assert (select count(*) from erp.journal_entries where company_id = c and status = 'draft') = 1, 'el borrador descuadrado';
  assert (select value from erp.quality_checks(c, 2026, '2026-12-31') q where q.code = 'settlements') = 1
     and not exists (select 1 from erp.tax_settlements where company_id = c and quarter = 2 and status = 'posted'), 'el 2T sin liquidar';
  assert (select extra from erp.quality_checks(c, 2026, '2026-12-31') q where q.code = 'overdue_in') > 0, 'un cliente con vencido de más de 90 días';
  raise notice 'OK  · lista de control: limpia en servicios, comercio y taller; en incidencias, exactamente lo sembrado';
end $$;

-- ---------- 4. Quién la crea, dónde y sus límites ----------
do $$
declare j jsonb;
begin
  assert public.falla('select erp.create_synthetic_company(0, ''workshop'', 12)', 'from 1 to 999999');
  assert public.falla('select erp.create_synthetic_company(5, ''bakery'', 12)', 'Unknown synthetic profile');
  assert public.falla('select erp.create_synthetic_company(5, ''workshop'', 13)', 'from 1 to 12');
  assert public.falla('select erp.create_synthetic_company(5, ''incidents'', 3)', 'at least 6 months');
  assert (select temporary from erp.companies where id = (select e from public.ctx where k = 'workshop')) = false, 'un miembro: permanente';
  assert (select synthetic_seed || ' ' || synthetic_profile || ' ' || synthetic_months from erp.v_my_companies
          where id = (select e from public.ctx where k = 'workshop')) = '4817 workshop 12', 'la web ve la semilla, el perfil y los meses';
  -- otro usuario no ve su huella
  call public.como('00000000-0000-0000-0000-0000000000c1');
  assert public.falla(format('select erp.company_fingerprint(%L)', (select e from public.ctx where k = 'workshop')), 'Not allowed');
  -- un registrado sin perfil: en una empresa temporal, y solo una a la vez
  j := erp.create_synthetic_company(4817, 'workshop', 3);
  assert (select temporary from erp.companies where id = (j ->> 'company_id')::uuid), 'un registrado: temporal';
  assert public.falla('select erp.create_synthetic_company(4817, ''services'', 3)', 'already have a temporary company');
  -- un invitado, no
  call public.como('00000000-0000-0000-0000-0000000000d1', true);
  assert public.falla('select erp.create_synthetic_company(4817, ''workshop'', 3)', 'Guest visitors');
  -- sin sesión, tampoco
  raise notice 'OK  · se crea como al importar (miembro: permanente; registrado: temporal; invitado: no) y con sus límites';
end $$;

-- una sintética no se publica como demo (ni siquiera el propietario)
call public.como('00000000-0000-0000-0000-0000000000a1');
do $$
declare c uuid;
begin
  c := (erp.create_synthetic_company(7, 'services', 1) ->> 'company_id')::uuid;
  assert public.falla(format('select erp.set_company_demo(%L, true)', c), 'cannot be published as demo');
  raise notice 'OK  · una sintética no se publica como demo';
end $$;

reset role;
do $$ begin
  assert not has_function_privilege('anon', 'erp.create_synthetic_company(int, text, int)', 'execute'), 'sin sesión, no';
end $$;

\echo 'FASE 81 OK'
