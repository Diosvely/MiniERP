-- =====================================================================
-- PRUEBAS FASE 65 · PGC de estudio (migración 0071 · v0.48.0)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.48.0.md): un libro de consulta del PGC, de solo lectura y común a todas las
-- empresas. Se comprueba que todo cuadra y que las referencias existen:
--   · Cuántos hay: 9 grupos, 78 subgrupos, 712 cuentas, 70 fichas, 23 NRV y 6 principios.
--   · Cada asiento de ejemplo (25 fichas lo tienen) cuadra (Debe = Haber) y sus subcuentas cuelgan de una cuenta del PGC.
--   · Cada ficha es de una cuenta que existe y cada NRV que cita está entre la 1 y la 23.
--   · Todo el plan de cuentas del ERP (coa_template) está en el PGC de estudio, con el mismo nombre.
--   · Las fichas están pendientes de validar (regla A3) y ninguna habla de otras herramientas (Power BI).
--   · Solo lectura: quien ha entrado lo lee; nadie lo cambia desde la web y sin entrar no se ve.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
grant execute on function public.falla(text, text) to authenticated, anon;

-- ---------- Cuántos hay ----------
do $$
begin
  assert (select count(*) from erp.pgc_groups) = 9, 'grupos';
  assert (select count(*) from erp.pgc_subgroups) = 78, 'subgrupos';
  assert (select count(*) from erp.pgc_accounts) = 712, 'cuentas';
  assert (select count(*) from erp.pgc_accounts where left(account, 1) between '1' and '7') = 704, '703 del PGC + la 2804';
  assert (select count(*) from erp.pgc_accounts where left(account, 1) in ('8', '9')) = 8, 'grupos 8 y 9: 830x, 84x y 94x';
  assert (select count(*) from erp.pgc_cards) = 70, 'fichas';
  assert (select count(*) from erp.pgc_valuation_rules) = 23, 'NRV';
  assert (select count(*) from erp.pgc_principles) = 6, 'principios';
  assert (select name from erp.pgc_accounts where account = '2804') = 'Amortización acumulada de fondo de comercio', 'la 2804';
  assert not exists (select 1 from erp.pgc_cards where left(code, 1) in ('8', '9')), 'los grupos 8 y 9 van sin ficha';
  raise notice 'OK  · 9 grupos, 78 subgrupos, 712 cuentas, 70 fichas, 23 NRV y 6 principios';
end $$;

-- ---------- Todo cuadra y las referencias existen ----------
do $$
begin
  assert not exists (select 1 from erp.pgc_cards c
                      where jsonb_array_length(c.example_lines) = 1
                         or (select sum(coalesce((l->>'debe')::numeric, 0)) - sum(coalesce((l->>'haber')::numeric, 0))
                               from jsonb_array_elements(c.example_lines) l) <> 0), 'cada ejemplo cuadra';
  assert not exists (select 1 from erp.pgc_cards c, jsonb_array_elements(c.example_lines) l
                      where l->>'subcuenta' !~ 'x'   -- la 129 usa «6xxxxxxx» a propósito (toda la clase 6)
                        and not exists (select 1 from erp.pgc_accounts a where a.account = left(l->>'subcuenta', 4)
                                                                            or a.account like left(l->>'subcuenta', 3) || '_')),
         'cada subcuenta del ejemplo cuelga de una cuenta del PGC';
  assert (select count(*) from erp.pgc_cards where jsonb_array_length(example_lines) > 0) = 25, '25 fichas con asiento de ejemplo';
  assert not exists (select 1 from erp.pgc_cards c
                      where not exists (select 1 from erp.pgc_accounts a where a.account = c.code
                                                                            or (length(c.code) = 3 and a.account like c.code || '_'))),
         'cada ficha es de una cuenta que existe';
  assert not exists (select 1 from erp.pgc_cards c, jsonb_array_elements(c.nrv) n
                      where not exists (select 1 from erp.pgc_valuation_rules r where r.number = n::int)), 'cada NRV citada existe';
  assert not exists (select 1 from erp.pgc_cards where jsonb_array_length(debits) = 0 or jsonb_array_length(credits) = 0
                                                    or usage = '' or balance = ''), 'cada ficha dice cuándo se carga, cuándo se abona y su saldo';
  assert not exists (select 1 from erp.pgc_accounts where jsonb_array_length(statement_lines) = 0), 'cada cuenta dice dónde aparece';
  assert not exists (select 1 from erp.pgc_accounts a join erp.pgc_subgroups s using (subgroup)
                      where left(a.account, 2) <> a.subgroup or left(s.subgroup, 1) <> s.grp), 'cada cuenta en su subgrupo y grupo';
  raise notice 'OK  · los ejemplos cuadran y las fichas, subcuentas y NRV citadas existen';
end $$;

-- ---------- El plan de cuentas del ERP está entero ----------
do $$
begin
  assert not exists (select 1 from erp.coa_template t where
      (length(t.account_no) = 1 and not exists (select 1 from erp.pgc_groups g where g.grp = t.account_no))
   or (length(t.account_no) = 2 and not exists (select 1 from erp.pgc_subgroups s where s.subgroup = t.account_no))
   or (length(t.account_no) = 3 and not exists (select 1 from erp.pgc_accounts a where a.account like t.account_no || '_'))
   or (length(t.account_no) = 4 and not exists (select 1 from erp.pgc_accounts a where a.account = t.account_no))),
    'cada cuenta de la plantilla está en el PGC de estudio';
  assert not exists (select 1 from erp.coa_template t join erp.pgc_accounts a on a.account = t.account_no where a.name <> t.name),
    'con el mismo nombre';
  raise notice 'OK  · las 400 cuentas del plan del ERP están en el PGC de estudio, con el mismo nombre';
end $$;

-- ---------- Regla A3 y textos propios ----------
do $$
begin
  assert not exists (select 1 from erp.pgc_cards where validated), 'las fichas están pendientes de validar por Diosvely';
  assert not exists (select 1 from erp.pgc_cards where warning || usage || example_text ilike '%power bi%'), 'sin Power BI (regresión: ficha 129)';
  assert (select warning from erp.pgc_cards where code = '129') ilike '%121%', 'la 129 explica qué pasa con la pérdida';
  raise notice 'OK  · fichas pendientes de validar (A3) y sin referencias a otras herramientas';
end $$;

-- ---------- Solo lectura ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
begin
  assert (select count(*) from erp.pgc_accounts) = 712, 'quien ha entrado lo lee';
  assert (select count(*) from erp.pgc_cards) = 70, 'y las fichas';
  assert public.falla($q$update erp.pgc_cards set usage = 'x' where code = '129'$q$, 'permission denied'), 'no cambia fichas';
  assert public.falla($q$insert into erp.pgc_accounts values ('9999', '99', 'x', '[]')$q$, 'permission denied'), 'ni crea cuentas';
  assert public.falla($q$delete from erp.pgc_principles$q$, 'permission denied'), 'ni borra principios';
  raise notice 'OK  · quien ha entrado lo lee, pero no lo cambia';
end $$;
reset role;
set role anon;
do $$
begin
  assert public.falla('select count(*) from erp.pgc_accounts', 'permission denied'), 'sin entrar no se ve';
  assert public.falla('select count(*) from erp.pgc_cards', 'permission denied'), 'ni las fichas';
  raise notice 'OK  · sin entrar no se ve';
end $$;
reset role;
