-- =====================================================================
-- PRUEBAS FASE 23 · Libro mayor rápido y borrado de empresas por tandas (migración 0029)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local'),
  ('00000000-0000-0000-0000-0000000000c3', 'ajeno@test.local');

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

create or replace function public.asiento(e uuid, d date, l jsonb) returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, 'Movimiento')
  returning id into a;
  insert into erp.journal_lines (entry_id, line_no, gl_account_id, debit, credit)
  select a, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  return a;
end $$;
grant execute on function public.asiento(uuid, date, jsonb) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- 1) Libro mayor: mismo resultado que la vista, saldo acumulado y fecha de corte ----------
do $$
declare e uuid; a uuid; n int; r record;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Mayor SL', 'services', 'mainland', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  perform erp.create_fiscal_year(e, 2026);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('10000001', 'Capital'), ('57200001', 'Banco'), ('62100001', 'Arrendamientos')) as s(no, name);

  perform public.asiento(e, '2026-01-02', '[["57200001",10000,0],["10000001",0,10000]]');
  perform public.asiento(e, '2026-02-01', '[["62100001",800,0],["57200001",0,800]]');
  a := public.asiento(e, '2026-03-01', '[["62100001",800,0],["57200001",0,800]]');
  perform erp.reverse_entry(a, '2026-03-05', 'Duplicado');           -- contraasiento
  perform public.asiento(e, '2026-04-01', '[["62100001",800,0],["57200001",0,800]]');
  insert into public.ctx values ('anulado', a);

  -- Igual que la vista v_general_ledger, fila a fila
  select count(*) into n from (
    (select posting_date, entry_no, debit, credit, running_balance from erp.general_ledger(e, 2026, '57200001')
     except
     select posting_date, entry_no, debit, credit, running_balance from erp.v_general_ledger
     where company_id = e and fiscal_year = 2026 and account_no = '57200001')
    union all
    (select posting_date, entry_no, debit, credit, running_balance from erp.v_general_ledger
     where company_id = e and fiscal_year = 2026 and account_no = '57200001'
     except
     select posting_date, entry_no, debit, credit, running_balance from erp.general_ledger(e, 2026, '57200001'))) d;
  assert n = 0, 'el mayor no coincide con la vista: ' || n || ' diferencias';
  raise notice 'OK  · el mayor coincide con la vista v_general_ledger';

  -- Saldo final del banco: 10.000 − 800 − 800 + 800 (contraasiento) − 800 = 8.400
  select running_balance into r from erp.general_ledger(e, 2026, '57200001') order by posting_date desc, entry_no desc limit 1;
  assert r.running_balance = 8400, 'saldo final del banco ' || r.running_balance;
  raise notice 'OK  · saldo acumulado del banco 8.400';

  -- Fecha de corte: hasta el 28/02 solo hay 2 movimientos y el saldo es 9.200
  assert (select count(*) from erp.general_ledger(e, 2026, '57200001', '2026-02-28')) = 2, 'fecha de corte';
  assert (select max(running_balance) filter (where posting_date = '2026-02-01') from erp.general_ledger(e, 2026, '57200001', '2026-02-28')) = 9200,
    'saldo a 28/02';
  raise notice 'OK  · fecha de corte';

  -- Viene ordenado y con el nº de asiento
  assert (select array_agg(entry_no) from erp.general_ledger(e, 2026, '62100001')) = array[2, 3, 4, 5],
    'orden del mayor: ' || (select array_agg(entry_no)::text from erp.general_ledger(e, 2026, '62100001'));
  raise notice 'OK  · orden por fecha y nº de asiento';

  -- Cuenta o ejercicio que no existen: vacío, sin error
  assert (select count(*) from erp.general_ledger(e, 2026, '99999999')) = 0, 'cuenta inexistente';
  assert (select count(*) from erp.general_ledger(e, 2019, '57200001')) = 0, 'ejercicio inexistente';
  raise notice 'OK  · cuenta o ejercicio inexistente → vacío';
end $$;

-- El lector ve el mayor; un usuario ajeno no ve nada (RLS sigue mandando)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$ begin
  assert (select count(*) from erp.general_ledger((select valor from public.ctx where clave = 'empresa'), 2026, '57200001')) = 5,
    'el lector debe ver el mayor';
  raise notice 'OK  · el lector ve el mayor';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', false) \gset
do $$ begin
  assert (select count(*) from erp.general_ledger((select valor from public.ctx where clave = 'empresa'), 2026, '57200001')) = 0,
    'un usuario ajeno no debe ver nada';
  raise notice 'OK  · un usuario ajeno no ve el mayor de otra empresa';
end $$;

-- ---------- 2) Borrar por tandas: permisos ----------
do $$ declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  perform public.debe_fallar(format('select erp.delete_company_step(%L)', e), 'Only the company admin', 'un ajeno no borra');
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$ declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  perform public.debe_fallar(format('select erp.delete_company_step(%L)', e), 'Only the company admin', 'un lector no borra');
end $$;
reset role;
do $$ begin
  begin
    set local role anon;
    perform erp.delete_company_step((select valor from public.ctx where clave = 'empresa'));
    raise exception 'FALLO: anon ha podido borrar';
  exception when insufficient_privilege then
    raise notice 'OK  · anon no puede ejecutar el borrado';
  end;
end $$;

-- ---------- 3) Borrar por tandas de 1 asiento: el contraasiento va con su original ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa'); n int; vueltas int := 0; antes int;
begin
  select count(*) into antes from erp.journal_entries where company_id = e;
  assert antes = 5, 'asientos antes de borrar: ' || antes;
  loop
    n := erp.delete_company_step(e, 1);
    vueltas := vueltas + 1;
    exit when n = 0;
    assert vueltas < 20, 'el borrado no termina';
    -- nunca queda un asiento apuntando a otro que ya no existe
    assert not exists (select 1 from erp.journal_entries j where j.company_id = e
                       and (j.reversal_of is not null and not exists (select 1 from erp.journal_entries o where o.id = j.reversal_of))),
      'quedó un contraasiento huérfano';
  end loop;
  -- 5 asientos; la pareja anulada sale en una sola tanda → 4 vueltas
  assert vueltas = 4, 'vueltas: ' || vueltas;
  raise notice 'OK  · borrado en % tandas; el contraasiento sale con su original', vueltas;
end $$;

reset role;
do $$ declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  assert not exists (select 1 from erp.companies where id = e), 'la empresa sigue existiendo';
  assert not exists (select 1 from erp.journal_lines where company_id = e), 'quedan apuntes';
  assert not exists (select 1 from erp.gl_accounts where company_id = e), 'quedan cuentas';
  assert not exists (select 1 from erp.fiscal_years where company_id = e), 'quedan ejercicios';
  assert not exists (select 1 from erp.company_users where company_id = e), 'quedan accesos';
  raise notice 'OK  · empresa borrada entera, en cascada';
end $$;

-- ---------- 4) Las claves foráneas tienen índice ----------
-- (salvo las que apuntan a los catálogos comunes de impuestos y retenciones: nunca se borran)
do $$ declare n int;
begin
  select count(*) into n
  from pg_constraint c
  where c.contype = 'f' and c.connamespace = 'erp'::regnamespace
    and c.confrelid not in ('erp.tax_codes'::regclass, 'erp.withholding_codes'::regclass)
    and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1]);
  assert n = 0, n || ' claves foráneas sin índice';
  raise notice 'OK  · todas las claves foráneas de datos de empresa tienen índice';
end $$;

\echo '✔ FASE 23 OK · libro mayor rápido y borrado por tandas'
