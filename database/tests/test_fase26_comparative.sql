-- =====================================================================
-- PRUEBAS FASE 26 · Balance y PyG comparativos a mitad de ejercicio (migración 0032)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');

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
create or replace function public.p(e uuid, y int, st text, c text, d date, col text) returns numeric language sql as $$
  select case col when 'n' then amount else amount_prev end from erp.financial_statement(e, y, st, d) where code = c;
$$;
grant execute on function public.asiento(uuid, date, jsonb), public.p(uuid, int, text, text, date, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Comparativa SL', 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2025);
  perform erp.create_fiscal_year(e, 2026);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('10000001', 'Capital'), ('57200001', 'Banco'), ('70500001', 'Servicios')) as s(no, name);

  perform public.asiento(e, '2025-01-02', '[["57200001",10000,0],["10000001",0,10000]]');
  perform public.asiento(e, '2025-03-10', '[["57200001",1000,0],["70500001",0,1000]]');   -- 1T 2025
  perform public.asiento(e, '2025-10-10', '[["57200001",4000,0],["70500001",0,4000]]');   -- 4T 2025
  perform public.asiento(e, '2026-02-10', '[["57200001",2500,0],["70500001",0,2500]]');   -- 1T 2026

  -- PyG a 31/03/2026: compara con el mismo periodo de 2025 (solo la venta de marzo)
  assert public.p(e, 2026, 'pyg', 'PD', '2026-03-31', 'n') = 2500, 'PyG 2026 a 31/03';
  assert public.p(e, 2026, 'pyg', 'PD', '2026-03-31', 'prev') = 1000,
    'PyG: el año anterior, hasta la misma fecha: ' || public.p(e, 2026, 'pyg', 'PD', '2026-03-31', 'prev');
  raise notice 'OK  · PyG a 31/03: 2.500 frente a 1.000 del mismo periodo de 2025';

  -- Balance a 31/03/2026: compara con el CIERRE de 2025 (todo el ejercicio: 10.000 + 1.000 + 4.000)
  assert public.p(e, 2026, 'balance', 'ACT', '2026-03-31', 'prev') = 15000,
    'Balance: el año anterior, a su cierre: ' || public.p(e, 2026, 'balance', 'ACT', '2026-03-31', 'prev');
  raise notice 'OK  · Balance a 31/03: se compara con el cierre de 2025 (15.000), no con el 31/03/2025';

  -- Sin fecha de corte: ejercicios completos en las dos columnas (como antes)
  assert public.p(e, 2026, 'pyg', 'PD', null, 'prev') = 5000, 'PyG completa de 2025';
  assert public.p(e, 2026, 'balance', 'ACT', null, 'prev') = 15000, 'Balance a cierre de 2025';
  raise notice 'OK  · sin fecha de corte: ejercicios completos';
end $$;

\echo '✔ FASE 26 OK · estados comparativos'
