-- =====================================================================
-- PRUEBAS FASE 82 · El Balance en los tres modelos del PGC (v0.60.0 · migración 0089)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.60.0.md, 06-11-2026). Se comprueba:
--   · cobertura: cada cuenta del PGC de estudio, deudora y acreedora, tiene partida en cada modelo y en la MISMA masa
--     que en PYMES (salvo las que el BOE mueve a propósito: 1034 y 1044, capital pendiente de inscripción);
--   · el mismo Balance en los tres modelos: mismos totales y cada cuenta una sola vez, en empresas sintéticas reales;
--   · casos concretos del BOE (Existencias II.1, 407, proveedor deudor, banco en descubierto, 580…);
--   · PYMES no cambia: sin p_model es lo de antes, y la PyG no tiene otros modelos.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'propietario@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null)
on conflict (user_id) do update set app_role = excluded.app_role, max_companies = excluded.max_companies;

create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;
create or replace function public.falla(p_sql text, p_msg text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || p_msg || '%' then return true; end if;
  raise exception 'Se esperaba «%» y salió «%»', p_msg, sqlerrm;
end $$;
grant execute on function public.falla(text, text) to authenticated;

-- ---------- 1. Cobertura de las cuentas del PGC de estudio ----------
-- La partida de una cuenta en un modelo, según el signo del saldo, y su masa (A, B, C del activo o del PN y pasivo)
create or replace function public.partida(p_model text, p_account text, p_debit boolean) returns text language sql as $$
  select case when p_debit then m.debit_line else m.credit_line end
  from (select prefix, debit_line, credit_line from erp.fs_mapping where p_model = 'pymes' and statement = 'balance'
        union all
        select prefix, debit_line, credit_line from erp.fs_model_mapping where model = p_model) m
  where p_account like m.prefix || '%' order by length(m.prefix) desc limit 1;
$$;
create or replace function public.masa(p_model text, p_line text) returns text language sql as $$
  with recursive up(code, parent) as (
    select code, parent from erp.fs_model_line_set(p_model) where code = p_line
    union all
    select l.code, l.parent from up join erp.fs_model_line_set(p_model) l on l.code = up.parent
  )
  select code from up where parent in ('ACT', 'PNP');
$$;

do $$
declare r record; n int := 0; malas text[] := '{}';
begin
  for r in
    select a.account, d.debit, m.model,
           public.partida('pymes', a.account, d.debit) as p, public.partida(m.model, a.account, d.debit) as x
    from erp.pgc_accounts a
    cross join (values (true), (false)) d(debit)
    cross join (values ('abreviado'), ('normal')) m(model)
    where public.partida('pymes', a.account, d.debit) is not null
  loop
    n := n + 1;
    if r.x is null then
      malas := malas || format('%s %s %s: sin partida', r.model, r.account, case when r.debit then 'D' else 'H' end);
    elsif public.masa('pymes', r.p) is distinct from public.masa(r.model, r.x)
          and r.account not in ('1034', '1044') then
      malas := malas || format('%s %s %s: %s (%s) frente a PYMES %s (%s)', r.model, r.account,
                               case when r.debit then 'D' else 'H' end, r.x, public.masa(r.model, r.x), r.p, public.masa('pymes', r.p));
    end if;
  end loop;
  assert n > 2500, format('se comprueban todas las cuentas (%s)', n);
  assert cardinality(malas) = 0, array_to_string(malas, E'\n');
  -- Las de capital pendiente de inscripción sí cambian de masa, porque así lo dice el BOE
  assert public.masa('normal', public.partida('normal', '1034', false)) = 'PC', '1034 en el pasivo corriente';
  raise notice 'OK  · cobertura: % casos (cuenta × saldo × modelo), todos con partida y en su masa', n;
end $$;

-- Casos del BOE (la foto y el texto que copió Diosvely)
do $$
begin
  assert public.partida('normal', '30000000', true) = 'AC.II.1', 'mercaderías: II. Existencias · 1. Comerciales';
  assert public.partida('pymes', '30000000', true) = 'AC.I', 'en PYMES: I. Existencias';
  assert public.partida('abreviado', '30000000', true) = 'AC.II', 'en el abreviado: II. Existencias';
  assert public.partida('normal', '40700000', true) = 'AC.II.6', '407: 6. Anticipos a proveedores';
  assert public.partida('normal', '40000001', true) = 'AC.III.3', 'proveedor deudor: 3. Deudores varios (v0.59.2)';
  assert public.partida('abreviado', '40000001', true) = 'AC.III.3', 'en el abreviado: 3. Otros deudores';
  assert public.partida('normal', '40000001', false) = 'PC.V.1', 'proveedor: V. 1. Proveedores';
  assert public.partida('normal', '40600000', true) = 'PC.V.1', '406 resta en Proveedores';
  assert public.partida('normal', '43000001', false) = 'PC.V.7', 'cliente acreedor: 7. Anticipos de clientes';
  assert public.partida('normal', '57200000', false) = 'PC.III.2', 'banco en descubierto: III. 2. Deudas con entidades de crédito';
  assert public.partida('abreviado', '57200000', false) = 'PC.III.1', 'en el abreviado: III. 1. Deudas con entidades de crédito';
  assert public.partida('normal', '58000000', true) = 'AC.I', '580: I. Activos no corrientes mantenidos para la venta';
  assert public.partida('normal', '58500000', false) = 'PC.I', '585: I. Pasivos vinculados';
  assert public.partida('normal', '47090000', true) = 'AC.III.5' and public.partida('normal', '47200000', true) = 'AC.III.6'
     and public.partida('normal', '47520000', false) = 'PC.V.5' and public.partida('normal', '47510000', false) = 'PC.V.6',
     'Hacienda: impuesto corriente y otras AAPP';
  assert public.partida('normal', '13000000', false) = 'PN.A3' and public.partida('pymes', '13000000', false) = 'PN.A2',
     'subvenciones: A-3 en el general, A-2 en PYMES';
  assert public.partida('normal', '13300000', false) = 'PN.A2.I', '133: A-2) Ajustes por cambios de valor';
  assert public.partida('normal', '20600000', true) = 'ANC.I.5' and public.partida('normal', '28060000', false) = 'ANC.I.5',
     'aplicaciones informáticas y su amortización';
  assert public.partida('normal', '24050000', true) = 'ANC.V.1' and public.partida('normal', '24030000', true) = 'ANC.IV.1',
     '2405 a inversiones financieras; 2403 al grupo';
  assert public.partida('normal', '17000000', false) = 'PNC.II.2' and public.partida('normal', '12100000', true) = 'PN.A1.V.2',
     'préstamo y resultados negativos';
  raise notice 'OK  · casos del BOE (Existencias, 407, proveedor deudor, banco, 58x, Hacienda, PN)';
end $$;

-- v0.60.3 · AF-04: el modelo abreviado, comparado con el BOE por auditoría fiscal (casos del «Balance abreviado»)
do $$
begin
  assert public.partida('abreviado', '43300000', true) = 'AC.III.1', 'clientes del grupo: 1. Clientes';
  assert public.partida('abreviado', '55800000', true) = 'AC.III.2', '5580: 2. Accionistas por desembolsos exigidos';
  assert public.partida('abreviado', '54400000', true) = 'AC.III.3', 'créditos al personal: 3. Otros deudores';
  assert public.partida('abreviado', '40700000', true) = 'AC.II', '407 en Existencias';
  assert public.partida('abreviado', '16250000', false) = 'PNC.II.2' and public.partida('abreviado', '17600000', false) = 'PNC.II.3',
     'deudas a largo: 2. arrendamiento financiero y 3. otras';
  assert public.partida('abreviado', '43800000', false) = 'PC.V.2' and public.partida('abreviado', '40300000', false) = 'PC.V.1',
     'anticipos de clientes y proveedores del grupo';
  assert public.partida('abreviado', '10340000', false) = 'PC.III.3', '1034: 3. Otras deudas a corto plazo';
  raise notice 'OK  · AF-04: casos del Balance abreviado del BOE';
end $$;

-- v0.60.3 · AF-05 (regresión, regla A1): las correctoras del activo con saldo acreedor RESTAN en su partida del activo,
-- como dice el BOE con el paréntesis: (437), (5393), (5394), (5395), (549). Antes de la 0092 salían en el pasivo.
do $$
begin
  assert public.partida('normal', '43700000', false) = 'AC.III.1' and public.partida('abreviado', '43700000', false) = 'AC.III.1'
     and public.partida('pymes', '43700000', false) = 'AC.II.1', '(437) resta en Clientes en los tres modelos';
  assert public.partida('normal', '53930000', false) = 'AC.IV.1' and public.partida('abreviado', '53930000', false) = 'AC.IV'
     and public.partida('pymes', '53930000', false) = 'AC.III', '(5393) resta en Inversiones en empresas del grupo a corto';
  assert public.partida('normal', '53940000', false) = 'AC.IV.1' and public.partida('pymes', '53940000', false) = 'AC.III',
     '(5394) igual';
  assert public.partida('normal', '53950000', false) = 'AC.V.1' and public.partida('abreviado', '53950000', false) = 'AC.V'
     and public.partida('pymes', '53950000', false) = 'AC.IV', '(5395) resta en Inversiones financieras a corto';
  assert public.partida('normal', '54900000', false) = 'AC.V.1' and public.partida('abreviado', '54900000', false) = 'AC.V'
     and public.partida('pymes', '54900000', false) = 'AC.IV', '(549) resta en Inversiones financieras a corto';
  -- lo demás no cambia: el cliente acreedor y los anticipos de clientes siguen en el pasivo
  assert public.partida('normal', '43000001', false) = 'PC.V.7' and public.partida('normal', '43800000', false) = 'PC.V.7'
     and public.partida('pymes', '43000001', false) = 'PC.IV.2', 'la 430 y la 438 acreedoras siguen en el pasivo';
  raise notice 'OK  · AF-05: (437), (5393), (5394), (5395) y (549) restan en el activo en los tres modelos';
end $$;

-- ---------- 2. El mismo Balance en los tres modelos, con empresas reales ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1"}', false);

insert into public.ctx
select p, (j ->> 'company_id')::uuid
from (values ('workshop'), ('incidents'), ('trade'), ('services')) v(p),
     lateral (select erp.create_synthetic_company(4817, v.p, 12) as j) c,
     lateral (select erp.synthetic_run((c.j ->> 'company_id')::uuid)) r;

do $$
declare c record; m text; d date; n int;
begin
  for c in select k, e from public.ctx loop
    foreach m in array array['abreviado', 'normal'] loop
      foreach d in array array['2026-03-31'::date, '2026-09-30', null] loop
        -- mismos totales
        assert (select array_agg(amount order by code) from erp.financial_statement(c.e, 2026, 'balance', d, false, m)
                where code in ('ACT', 'PNP', 'AC', 'ANC', 'PN', 'PNC', 'PC'))
             = (select array_agg(amount order by code) from erp.financial_statement(c.e, 2026, 'balance', d)
                where code in ('ACT', 'PNP', 'AC', 'ANC', 'PN', 'PNC', 'PC')),
               format('%s · %s · %s: mismas masas que PYMES', c.k, m, d);
        -- cuadra, y cada cuenta una sola vez, la misma que en PYMES
        assert (select sum(amount) filter (where code = 'ACT') - sum(amount) filter (where code = 'PNP')
                from erp.financial_statement(c.e, 2026, 'balance', d, false, m)) = 0, format('%s · %s: cuadra', c.k, m);
        assert (select count(*) from erp.fs_line_accounts(c.e, 2026, 'balance', 'ACT', d, false, m))
             + (select count(*) from erp.fs_line_accounts(c.e, 2026, 'balance', 'PNP', d, false, m))
             = (select count(*) from erp.fs_line_accounts(c.e, 2026, 'balance', 'ACT', d))
             + (select count(*) from erp.fs_line_accounts(c.e, 2026, 'balance', 'PNP', d)),
               format('%s · %s: cada cuenta una vez', c.k, m);
        -- la suma de las partidas hoja es su total (no se pierde ni se duplica nada al desplegar)
        select count(*) into n from erp.financial_statement(c.e, 2026, 'balance', d, false, m) f
        where not f.is_total and exists (select 1 from erp.fs_model_line_set(m) h where h.parent = f.code)
          and f.amount <> (select coalesce(sum(h.amount), 0) from erp.financial_statement(c.e, 2026, 'balance', d, false, m) h
                           where h.parent = f.code);
        assert n = 0, format('%s · %s: cada partida es la suma de sus líneas', c.k, m);
      end loop;
    end loop;
  end loop;
  raise notice 'OK  · las 4 sintéticas, a 3 fechas: mismas masas, cuadra y cada cuenta una vez en el abreviado y el normal';
end $$;

-- El taller: mercaderías y el ⚠ del proveedor deudor de «incidencias» en su partida de cada modelo
do $$
declare w uuid := (select e from public.ctx where k = 'workshop');
        i uuid := (select e from public.ctx where k = 'incidents');
begin
  assert (select amount from erp.financial_statement(w, 2026, 'balance', null, false, 'normal') where code = 'AC.II')
       = (select amount from erp.financial_statement(w, 2026, 'balance') where code = 'AC.I'),
       'Existencias: II en el normal = I en PYMES';
  assert (select array_agg(line_code order by account_no) from erp.fs_line_anomalies(i, 2026, null, false, 'normal')
          where account_no like '400%') = array['AC.III.3'], '⚠ del proveedor deudor: 3. Deudores varios en el normal';
  assert (select array_agg(line_code order by account_no) from erp.fs_line_anomalies(i, 2026, null, false, 'pymes')
          where account_no like '400%') = array['AC.II.3'], 'y en PYMES, 3. Otros deudores (como en la v0.59.2)';
  assert (select count(*) from erp.fs_line_anomalies(i, 2026, null, false, 'normal'))
       = (select count(*) from erp.fs_line_anomalies(i, 2026)), 'los mismos avisos en todos los modelos';
  assert (select note from erp.fs_line_anomalies(i, 2026, null, false, 'normal') where account_no like '400%')
         like '%en el modelo normal, Deudores varios%', 'la nota nombra la partida del normal';
  -- Año anterior: el taller solo tiene 2026, así que la columna del anterior está a cero en todos
  assert (select bool_and(amount_prev = 0) from erp.financial_statement(w, 2026, 'balance', null, false, 'normal')), 'sin 2025';
  raise notice 'OK  · Existencias II = I, y el ⚠ del proveedor deudor en su partida de cada modelo';
end $$;

-- ---------- 3. PYMES no cambia; la PyG y un modelo desconocido ----------
do $$
declare w uuid := (select e from public.ctx where k = 'workshop');
begin
  assert (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.financial_statement(w, 2026, 'balance') x)
       = (select jsonb_agg(to_jsonb(x) order by x.sort) from erp.financial_statement(w, 2026, 'balance', null, false, 'pymes') x),
       'sin modelo = PYMES';
  assert (select count(*) from erp.financial_statement(w, 2026, 'balance')) = (select count(*) from erp.fs_lines where statement = 'balance'),
       'PYMES con sus partidas de siempre';
  assert public.falla(format('select * from erp.financial_statement(%L, 2026, %L, null, false, %L)', w, 'pyg', 'normal'),
                      'Only the balance sheet'), 'la PyG solo en PYMES';
  assert public.falla(format('select * from erp.financial_statement(%L, 2026, %L, null, false, %L)', w, 'balance', 'otro'),
                      'Unknown balance sheet model'), 'modelo desconocido';
  assert public.falla(format('select * from erp.fs_line_anomalies(%L, 2026, null, false, %L)', w, 'otro'),
                      'Unknown balance sheet model'), 'modelo desconocido en el aviso';
  raise notice 'OK  · PYMES igual que antes; la PyG solo en PYMES; modelo desconocido, error';
end $$;

-- ---------- 4. Otro usuario no ve nada ----------
reset role;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c1', 'otro@test.local');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1"}', false);
do $$
declare w uuid := (select e from public.ctx where k = 'workshop');
begin
  assert (select bool_and(amount = 0) from erp.financial_statement(w, 2026, 'balance', null, false, 'normal')), 'el normal de otro, a cero';
  assert (select count(*) from erp.fs_line_accounts(w, 2026, 'balance', 'ACT', null, false, 'normal')) = 0, 'sin cuentas';
  assert public.falla(format('select * from erp.fs_line_anomalies(%L, 2026, null, false, %L)', w, 'normal'),
                      'Not allowed'), 'ni avisos';
  raise notice 'OK  · otro usuario no ve el balance de la empresa en ningún modelo';
end $$;
