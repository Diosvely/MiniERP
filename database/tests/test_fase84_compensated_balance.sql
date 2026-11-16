-- =====================================================================
-- PRUEBAS FASE 84 · El Balance compensado, el menú «Auditorías» y la caja en su sitio (migración 0096 · v0.60.7)
-- ---------------------------------------------------------------------
-- Aprobado por Diosvely (15 y 16-11-2026). Un diario pequeño importado, con cifras redondas que se pueden rehacer a
-- mano, con lo mismo que la empresa de práctica del vídeo 03: un banco con dinero, otro en descubierto, la caja en
-- negativo (un error) y Hacienda deudora y acreedora a la vez.
--   57200002 Banco Sur 62.100 D · 57200001 Banco Norte 5.350 H · 57000000 Caja 500 H · 47200000 350 D · 47700000 2.100 H
--   30000000 Existencias 2.000 D · 10000000 Capital 50.000 H · resultado 6.500
-- Se comprueba:
--   · AF-19: la caja acreedora resta en el efectivo del activo; el descubierto bancario, en el pasivo;
--   · el Balance compensado, partida a partida y en los tres modelos, y sus ratios (y que los del ERP son los «sin
--     compensar»); la simulación con un borrador;
--   · el tablero «Saldos al revés» (sus tarjetas y la partida de cada modelo) y el grupo de cada tablero;
--   · otro usuario no ve nada.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'owner@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000b2', 'member', null)
on conflict (user_id) do nothing;
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
-- Sube filas a un lote: [fecha, asiento, tipo, cuenta, nombre, debe, haber]
create or replace function public.subir(b uuid, filas jsonb) returns void language sql as $$
  insert into erp.import_lines (batch_id, company_id, row_no, entry_date, entry_ref, entry_type, account_no, account_name,
                                debit, credit, description)
  select b, (select company_id from erp.import_batches where id = b),
         coalesce((select max(row_no) from erp.import_lines where batch_id = b), 0) + x.ord,
         (x.v->>0)::date, x.v->>1, x.v->>2, x.v->>3, x.v->>4, (x.v->>5)::numeric, (x.v->>6)::numeric, 'Prueba'
  from jsonb_array_elements(filas) with ordinality as x(v, ord);
$$;
create or replace function public.importar(b uuid) returns void language plpgsql as $$
declare m record; r jsonb;
begin
  for m in select * from erp.import_prepare(b) loop
    perform erp.import_post_month(b, m.year, m.month);
  end loop;
  loop
    r := erp.import_finish(b);
    exit when (r->>'done')::boolean;
  end loop;
end $$;
-- Una partida del Balance compensado: los dos importes
create or replace function public.comp(c uuid, model text, line text, sim boolean default false) returns numeric[] language sql as $$
  select array[x.amount, x.amount_comp] from erp.fs_compensated(c, 2026, '2026-10-31', sim, model) x where x.code = line;
$$;
create or replace function public.ratio(c uuid, model text, k text, sim boolean default false) returns numeric[] language sql as $$
  select array[x.amount, x.amount_comp] from erp.fs_compensated_ratios(c, 2026, '2026-10-31', sim, model) x where x.code = k;
$$;
grant execute on function public.falla(text, text), public.subir(uuid, jsonb), public.importar(uuid),
  public.comp(uuid, text, text, boolean), public.ratio(uuid, text, text, boolean) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid; b uuid;
begin
  select company_id, batch_id into e, b from erp.import_start('Brújula de prueba SL', 8, 'mainland', 'services', 'sage', 'prueba.csv');
  perform public.subir(b, '[
    ["2026-01-01","1","opening","57200002","Banco Sur",50000,0],
    ["2026-01-01","1","opening","10000000","Capital social",0,50000],
    ["2026-02-10","2","normal","57200002","Banco Sur",12100,0],
    ["2026-02-10","2","normal","70000000","Ventas de mercaderías",0,10000],
    ["2026-02-10","2","normal","47700000","IGIC repercutido",0,2100],
    ["2026-03-05","3","normal","60000000","Compras de mercaderías",5000,0],
    ["2026-03-05","3","normal","47200000","IGIC soportado",350,0],
    ["2026-03-05","3","normal","57200001","Banco Norte",0,5350],
    ["2026-04-15","4","normal","62900000","Otros servicios",500,0],
    ["2026-04-15","4","normal","57000000","Caja",0,500],
    ["2026-06-30","5","normal","30000000","Mercaderías",2000,0],
    ["2026-06-30","5","normal","61000000","Variación de existencias",0,2000]
  ]'::jsonb);
  perform public.importar(b);
  insert into public.ctx values ('c', e);
end $$;

-- ---------- 1. AF-19 · La caja acreedora resta en el efectivo; el descubierto, en el pasivo ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert (public.comp(c, 'pymes', 'AC.VI'))[1] = 61600, 'PYMES: efectivo = Banco Sur 62.100 − caja 500';
  assert (public.comp(c, 'pymes', 'PC.II.1'))[1] = 5350, 'PYMES: deudas con entidades de crédito = solo el Banco Norte';
  assert (public.comp(c, 'normal', 'AC.VII.1'))[1] = 61600 and (public.comp(c, 'normal', 'PC.III.2'))[1] = 5350,
         'normal: VII. 1. Tesorería y III. 2. Deudas con entidades de crédito';
  assert (public.comp(c, 'abreviado', 'AC.VII'))[1] = 61600 and (public.comp(c, 'abreviado', 'PC.III.1'))[1] = 5350,
         'abreviado: VII. Efectivo y III. 1. Deudas con entidades de crédito';
  assert (select amount from erp.financial_statement(c, 2026, 'balance', '2026-10-31') where code = 'AC.VI') = 61600,
         'el Balance de siempre dice lo mismo';
  raise notice 'OK  · AF-19: la caja en negativo resta en el efectivo (61.600) y el descubierto va al pasivo (5.350)';
end $$;

-- ---------- 2. El Balance compensado, partida a partida ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); m text;
begin
  -- Sin compensar: activo 63.950 = PN 56.500 + pasivo 7.450. Compensado: los bancos y la 47 se netean → 58.250
  foreach m in array array['pymes', 'abreviado', 'normal'] loop
    assert public.comp(c, m, 'ACT') = array[63950, 58250]::numeric[], format('%s: total activo 63.950 frente a 58.250', m);
    assert public.comp(c, m, 'PNP') = array[63950, 58250]::numeric[], format('%s: los dos cuadran', m);
    assert public.comp(c, m, 'PN') = array[56500, 56500]::numeric[], format('%s: el patrimonio neto no cambia', m);
    assert public.comp(c, m, 'PC') = array[7450, 1750]::numeric[], format('%s: pasivo corriente 7.450 frente a 1.750', m);
  end loop;
  assert public.comp(c, 'pymes', 'AC.VI') = array[61600, 56250]::numeric[], 'efectivo: compensado, el Banco Norte resta';
  assert public.comp(c, 'pymes', 'PC.II.1') = array[5350, 0]::numeric[], 'compensado, el descubierto desaparece';
  assert public.comp(c, 'pymes', 'AC.II.3') = array[350, 0]::numeric[], 'Hacienda deudora: compensada con la acreedora';
  assert public.comp(c, 'pymes', 'PC.IV.2') = array[2100, 1750]::numeric[], 'Hacienda acreedora: 2.100 frente a 1.750';
  assert public.comp(c, 'pymes', 'AC.I') = array[2000, 2000]::numeric[], 'existencias: no cambian';
  raise notice 'OK  · Balance compensado: 63.950 frente a 58.250 en los tres modelos; esconde el descubierto y la 47';
end $$;

-- ---------- 3. Los ratios de los dos Balances ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  -- Prueba ácida: (63.950 − 2.000) / 7.450 = 8,3154 · compensado (58.250 − 2.000) / 1.750 = 32,1429
  assert public.ratio(c, 'pymes', 'QR') = array[8.3154, 32.1429]::numeric[], 'prueba ácida 8,32 frente a 32,14';
  assert public.ratio(c, 'normal', 'QR') = array[8.3154, 32.1429]::numeric[], 'igual en el modelo normal';
  assert public.ratio(c, 'pymes', 'LIQ') = array[8.5839, 33.2857]::numeric[], 'liquidez general';
  assert public.ratio(c, 'pymes', 'CASH') = array[8.2685, 32.1429]::numeric[], 'tesorería inmediata';
  assert public.ratio(c, 'pymes', 'DEBT') = array[0.1165, 0.0300]::numeric[], 'endeudamiento 11,6 % frente a 3,0 %';
  assert public.ratio(c, 'pymes', 'WC') = array[56500, 56500]::numeric[], 'el fondo de maniobra no cambia';
  assert (public.ratio(c, 'pymes', 'HIDDEN'))[1] = 5700, 'escondido: 5.350 del Banco Norte + 350 de la 47';
  -- Los ratios del ERP son los del Balance sin compensar
  assert (select round(value, 4) from erp.financial_ratios(c, 2026) where code = 'QR') = 8.3154,
         'la prueba ácida de la pantalla Ratios es la sin compensar';
  raise notice 'OK  · ratios: prueba ácida 8,32 sin compensar frente a 32,14 compensado; la de Ratios, 8,32';
end $$;

-- ---------- 4. La simulación: un borrador que pasa dinero del Sur al Norte ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (c, (select id from erp.fiscal_years where company_id = c and year = 2026), '2026-10-30', 'Traspaso al Banco Norte')
  returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200001'), 5350);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, (select id from erp.gl_accounts where company_id = c and account_no = '57200002'), 5350);
  assert (public.ratio(c, 'pymes', 'HIDDEN'))[1] = 5700, 'sin simular, el borrador no cuenta';
  assert (public.ratio(c, 'pymes', 'HIDDEN', true))[1] = 350, 'simulando, el descubierto desaparece: solo queda la 47';
  delete from erp.journal_entries where id = a;
  raise notice 'OK  · simulación: con el traspaso en borrador, solo queda escondida la 47 (350)';
end $$;

-- ---------- 5. El tablero «Saldos al revés» y el menú «Auditorías» ----------
do $$
declare c uuid := (select e from public.ctx where k = 'c'); d jsonb; cards jsonb; caja jsonb; norte jsonb;
begin
  assert (select area from erp.dashboards where code = 'calidad') = 'auditoria', 'Calidad de la contabilidad, en auditorías';
  assert (select area from erp.dashboards where code = 'saldos_reves') = 'auditoria', 'Saldos al revés, en auditorías';
  assert not exists (select 1 from erp.dashboards where code not in ('calidad', 'saldos_reves') and area <> 'tablero'),
         'los demás, en tableros';
  d := erp.dashboard_data(c, 'saldos_reves', 2026, '2026-10-31');
  assert d ->> 'area' = 'auditoria', 'el tablero dice su grupo';
  cards := d -> 'widgets' -> 0 -> 'cards';
  assert jsonb_array_length(cards) = (select count(*) from erp.balance_anomalies(c, 2026, null, '2026-10-31')),
         'una tarjeta por cada saldo al revés';
  select x into caja from jsonb_array_elements(cards) x where x ->> 'account_no' = '57000000';
  select x into norte from jsonb_array_elements(cards) x where x ->> 'account_no' = '57200001';
  assert caja ->> 'severity' = 'error' and (caja ->> 'balance')::numeric = -500, 'la caja: imposible';
  assert caja -> 'lines' -> 'normal' ->> 'code' = 'AC.VII.1' and caja -> 'lines' -> 'pymes' ->> 'code' = 'AC.VI'
     and caja -> 'lines' -> 'abreviado' ->> 'code' = 'AC.VII', 'la caja: en el efectivo en los tres modelos';
  assert norte ->> 'severity' = 'warning' and norte -> 'lines' -> 'normal' ->> 'code' = 'PC.III.2'
     and norte -> 'lines' -> 'normal' ->> 'label' = '2. Deudas con entidades de crédito', 'el Banco Norte: revisar, en el pasivo';
  assert (cards -> 0 ->> 'severity') = 'error', 'primero los imposibles';
  -- Los demás tableros no traen tarjetas
  assert erp.dashboard_data(c, 'calidad', 2026) -> 'widgets' -> 0 -> 'cards' = 'null'::jsonb, 'calidad: sin tarjetas';
  raise notice 'OK  · «Saldos al revés»: % tarjetas, la caja imposible en el efectivo y el Banco Norte en el pasivo',
    jsonb_array_length(cards);
end $$;

-- ---------- 6. Otro usuario no ve nada ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare c uuid := (select e from public.ctx where k = 'c');
begin
  assert public.falla(format('select erp.fs_compensated(%L, 2026)', c), 'Not allowed'), 'el Balance compensado de otro';
  assert public.falla(format('select erp.fs_compensated_ratios(%L, 2026)', c), 'Not allowed'), 'sus ratios';
  assert public.falla(format('select erp.reverse_cards(%L, 2026)', c), 'Not allowed'), 'sus tarjetas';
  raise notice 'OK  · otro usuario no ve el Balance compensado, sus ratios ni las tarjetas';
end $$;
