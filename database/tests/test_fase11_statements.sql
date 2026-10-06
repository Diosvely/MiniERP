-- =====================================================================
-- PRUEBAS FASE 11 · Balance de situación y Pérdidas y Ganancias (migración 0016)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.asiento(e uuid, d date, txt text, l jsonb) returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, txt)
  returning id into a;
  insert into erp.journal_lines (entry_id, line_no, gl_account_id, debit, credit)
  select a, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  return a;
end $$;
grant execute on function public.asiento(uuid, date, text, jsonb) to authenticated;

create or replace function public.partida(e uuid, y int, st text, c text, d date default null) returns numeric language sql as $$
  select amount from erp.financial_statement(e, y, st, d) where code = c;
$$;
grant execute on function public.partida(uuid, int, text, text, date) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; n int;
begin
  -- ---------- Catálogo ----------
  assert (select count(*) from erp.fs_lines where statement = 'balance' and parent is null) = 2, 'activo y PN+pasivo';
  assert (select count(*) from erp.fs_lines where statement = 'pyg' and parent is null) = 1, 'D) resultado';

  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Estados SL', 'retail', 'canary_islands', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2025);
  perform erp.create_fiscal_year(e, 2026);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('10000001','Capital'), ('17000001','Préstamo bancario l/p'), ('21600001','Mobiliario'), ('28160001','A.A. mobiliario'),
    ('30000001','Mercaderías'), ('40000001','Proveedor A'), ('40000002','Proveedor B'), ('43000001','Cliente A'), ('43000002','Cliente B'),
    ('47210007','IGIC soportado'), ('47710007','IGIC repercutido'), ('47500002','HP acreedora IGIC'),
    ('57000001','Caja'), ('57200001','Banco 1'), ('57200002','Banco 2'),
    ('60000001','Compras'), ('60800001','Devoluciones compras'), ('62100001','Alquiler'), ('64000001','Sueldos'),
    ('68100001','Amortización'), ('66200001','Intereses'), ('70000001','Ventas'), ('70800001','Devoluciones ventas'),
    ('76900001','Otros ingresos financieros'), ('63000001','Impuesto sobre beneficios'),
    ('12900000','Resultado del ejercicio')) as s(no, name);

  -- 2025 (para la columna del año anterior): capital 10.000 al banco y ventas 1.000
  perform public.asiento(e, '2025-01-01', 'Constitución', '[["57200001",10000,0],["10000001",0,10000]]');
  perform public.asiento(e, '2025-06-01', 'Ventas 2025', '[["57200001",1000,0],["70000001",0,1000]]');

  -- 2026
  perform public.asiento(e, '2026-01-01', 'Apertura', '[["57200001",11000,0],["10000001",0,10000],["12900000",0,1000]]');
  perform public.asiento(e, '2026-01-10', 'Préstamo', '[["57200002",5000,0],["17000001",0,5000]]');
  perform public.asiento(e, '2026-01-15', 'Mobiliario', '[["21600001",3000,0],["57200001",0,3000]]');
  perform public.asiento(e, '2026-02-01', 'Compra', '[["60000001",4000,0],["47210007",280,0],["40000001",0,4280]]');
  perform public.asiento(e, '2026-02-05', 'Devolución compra', '[["40000001",107,0],["60800001",0,100],["47210007",0,7]]');
  perform public.asiento(e, '2026-03-01', 'Venta', '[["43000001",8560,0],["70000001",0,8000],["47710007",0,560]]');
  perform public.asiento(e, '2026-03-05', 'Devolución venta', '[["70800001",500,0],["47710007",35,0],["43000001",0,535]]');
  perform public.asiento(e, '2026-03-10', 'Anticipo cliente B', '[["57000001",300,0],["43000002",0,300]]');
  perform public.asiento(e, '2026-03-11', 'Pago de más a proveedor B', '[["40000002",50,0],["57000001",0,50]]');
  perform public.asiento(e, '2026-03-20', 'Alquiler', '[["62100001",1200,0],["57200002",0,1200]]');
  perform public.asiento(e, '2026-03-25', 'Sueldos', '[["64000001",2000,0],["57200002",0,2000]]');
  perform public.asiento(e, '2026-03-28', 'Pago proveedor A (descubierto banco 2)', '[["40000001",4173,0],["57200002",0,4173]]');
  perform public.asiento(e, '2026-03-30', 'Intereses', '[["66200001",50,0],["57200001",0,50]]');
  perform public.asiento(e, '2026-03-30', 'Otros ingresos financieros', '[["57200001",20,0],["76900001",0,20]]');
  perform public.asiento(e, '2026-03-31', 'Amortización', '[["68100001",100,0],["28160001",0,100]]');
  perform public.asiento(e, '2026-03-31', 'Impuesto', '[["63000001",200,0],["47500002",0,200]]');

  -- ---------- PyG ----------
  assert public.partida(e, 2026, 'pyg', 'P1') = 7500,  'cifra de negocios 8.000 − 500 devoluciones';
  assert public.partida(e, 2026, 'pyg', 'P4') = -3900, 'aprovisionamientos −4.000 + 100';
  assert public.partida(e, 2026, 'pyg', 'P6') = -2000;
  assert public.partida(e, 2026, 'pyg', 'P7') = -1200;
  assert public.partida(e, 2026, 'pyg', 'P8') = -100;
  assert public.partida(e, 2026, 'pyg', 'PA') = 300,   'resultado de explotación';
  assert public.partida(e, 2026, 'pyg', 'PB') = -30,   'resultado financiero 20 − 50';
  assert public.partida(e, 2026, 'pyg', 'PC') = 270;
  assert public.partida(e, 2026, 'pyg', 'P18') = -200;
  assert public.partida(e, 2026, 'pyg', 'PD') = 70,    'resultado del ejercicio';
  assert (select amount_prev from erp.financial_statement(e, 2026, 'pyg') where code = 'PD') = 1000, 'columna 2025';
  raise notice 'OK  · PyG: cifra de negocios 7.500 · explotación 300 · financiero −30 · impuesto −200 · resultado 70 (2025: 1.000)';

  -- ---------- Balance ----------
  assert public.partida(e, 2026, 'balance', 'ACT') = public.partida(e, 2026, 'balance', 'PNP'), 'el balance cuadra';
  assert public.partida(e, 2026, 'balance', 'ANC.II') = 2900, 'mobiliario 3.000 − amortización acumulada 100';
  assert public.partida(e, 2026, 'balance', 'AC.I') = 50,      'proveedor B deudor = anticipo (en existencias)';
  assert public.partida(e, 2026, 'balance', 'AC.II.1') = 8025, 'cliente A deudor';
  assert public.partida(e, 2026, 'balance', 'AC.II.3') = 273,  'IGIC soportado 280 − 7';
  assert public.partida(e, 2026, 'balance', 'AC.VI') = 8220,   'banco 1 (7.970) + caja (250)';
  assert public.partida(e, 2026, 'balance', 'PC.II.1') = 2373, 'banco 2 en descubierto → deudas con entidades de crédito';
  assert public.partida(e, 2026, 'balance', 'PC.IV.1') = 0,    'proveedor A pagado';
  assert public.partida(e, 2026, 'balance', 'PC.IV.2') = 300 + 525 + 200, 'anticipo cliente B + IGIC repercutido + HP acreedora';
  assert public.partida(e, 2026, 'balance', 'PNC.II.1') = 5000;
  assert public.partida(e, 2026, 'balance', 'PN.A1.I') = 10000;
  assert public.partida(e, 2026, 'balance', 'PN.A1.VII') = 1070, '129 (1.000 de 2025 aún sin aplicar) + resultado 2026 (70)';
  raise notice 'OK  · balance cuadrado: activo = PN + pasivo = % ', public.partida(e, 2026, 'balance', 'ACT');
  raise notice 'OK  · sin compensar: banco 2 al pasivo, cliente B acreedor al pasivo, proveedor B deudor al activo';

  -- Fecha de corte: a 31/01 solo hay apertura, préstamo y mobiliario
  assert public.partida(e, 2026, 'balance', 'ACT', '2026-01-31') = 16000;
  assert public.partida(e, 2026, 'pyg', 'PD', '2026-01-31') = 0;
  raise notice 'OK  · fecha de corte';

  -- Drill-down: cuentas de "Efectivo"
  select count(*) into n from erp.fs_line_accounts(e, 2026, 'balance', 'AC.VI');
  assert n = 2, 'banco 1 y caja (el banco 2 está en el pasivo)';
  assert (select count(*) from erp.fs_line_accounts(e, 2026, 'balance', 'AC')) = 5, 'proveedor B, cliente A, IGIC soportado, banco 1 y caja';
  raise notice 'OK  · drill-down de partida a subcuentas';
end $$;

reset role;
drop function public.asiento(uuid, date, text, jsonb);
drop function public.partida(uuid, int, text, text, date);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 11 (ESTADOS FINANCIEROS) PASARON ==========='
