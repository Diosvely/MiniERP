-- =====================================================================
-- PRUEBAS FASE 35 · SUPUESTOS DE REFERENCIA (v0.34.0)
-- ---------------------------------------------------------------------
-- Cinco supuestos completos, con la solución CALCULADA A MANO desde la norma (no desde el código): cada cifra
-- esperada lleva su cálculo y el artículo que la justifica. El ERP tiene que coincidir AL CÉNTIMO en balance,
-- PyG, modelo 303 / 420 y modelos 111 / 115.
--
-- Normas (vigentes en 2026):
--   PGC 2007 (RD 1514/2007): cuadro de cuentas, modelo de balance y PyG, NRV 12.ª (IVA no deducible = mayor coste)
--   Ley 37/1992 del IVA (LIVA): tipos art. 90-91 · AIB art. 13 y 85 · ISP art. 84.Uno.2.º f) · recargo de
--     equivalencia art. 154-163 (tipos del recargo, art. 161) · prorrata art. 102-106 (redondeo, art. 104.Dos.2.º)
--   IGIC: Ley 20/1991 y Decreto Legislativo 1/2025 (tipo general 7 %, reducido 3 %)
--   IRPF: Ley 35/2006 y RD 439/2007 (RIRPF): retención de profesionales 15 % (art. 101.5 LIRPF, art. 95 RIRPF) y de
--     arrendamiento de inmuebles urbanos 19 % (art. 101.8 LIRPF, art. 100 RIRPF), modelos 111 y 115
--
-- Supuestos:
--   1. Servicios en la Península: profesional con IRPF, alquiler con IRPF, ventas al 21 % y al 10 %, cobro, pago,
--      303, 111 y 115, balance y PyG del 1T
--   2. Comercio en Canarias con IGIC: compra al 7 %, ventas al 7 % y al 3 %, modelo 420
--   3. Adquisición intracomunitaria y obra con inversión del sujeto pasivo (autorrepercusión)
--   4. Mayorista que vende a un minorista en recargo de equivalencia
--   5. Prorrata general: provisional 80 %, definitiva 71 % (redondeo al entero superior) y regularización
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.empresa(nombre text, territorio text, cuentas text[]) returns uuid language plpgsql as $$
declare e uuid; c text;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values (nombre, 'services', territorio, auth.uid())
  returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  foreach c in array cuentas loop perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2)); end loop;
  return e;
end $$;
create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb, retencion text default null)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', tipo, 'document_kind', 'invoice',
    'partner_id', tercero, 'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Supuesto', 'withholding_code', retencion, 'lines', lineas));
$$;
create or replace function public.manual(e uuid, d date, l jsonb) returns void language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = extract(year from d)), d, 'Supuesto') returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
end $$;
-- Partida de un estado (ACT, PNP, PD…) · saldo deudor (+) / acreedor (−) de las subcuentas que empiezan por un prefijo
create or replace function public.partida(e uuid, st text, c text) returns numeric language sql as $$
  select amount from erp.financial_statement(e, 2026, st) where code = c;
$$;
create or replace function public.saldo(e uuid, prefijo text) returns numeric language sql as $$
  select coalesce(sum(debit_balance - credit_balance), 0) from erp.trial_balance(e, 2026) where account_no like prefijo || '%';
$$;
-- Casilla del borrador del 303 / 420: lado (output / input), clase y tipo
create or replace function public.casilla(c jsonb, lado text, clase text, tipo numeric) returns text language sql as $$
  select coalesce(string_agg((b->>'tax_base') || ' → ' || (b->>'tax_amount'), ' + ' order by b->>'tax_code'), '—')
  from jsonb_array_elements(c->'boxes') b
  where b->>'side' = lado and b->>'kind' = clase and (b->>'rate_pct')::numeric = tipo;
$$;
grant execute on function public.empresa(text, text, text[]), public.factura(uuid, text, uuid, date, jsonb, text),
  public.manual(uuid, date, jsonb), public.partida(uuid, text, text), public.saldo(uuid, text),
  public.casilla(jsonb, text, text, numeric) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- =====================================================================
-- SUPUESTO 1 · Servicios Ruiz SL (Península) · primer trimestre de 2026
-- ---------------------------------------------------------------------
--  02/01  Constitución con 10.000 € en el banco.
--  15/01  Factura de la abogada Ana Ruiz (persona física): base 1.000, IVA 21 %, retención 15 % (art. 101.5 LIRPF).
--         IVA 1.000 × 21 % = 210 · retención 1.000 × 15 % = 150 · a pagar 1.000 + 210 − 150 = 1.060
--         623 D 1.000 · 472 D 210  /  4751 H 150 · 410 H 1.060
--  01/02  Alquiler de la oficina (arrendador: una SL): base 800, IVA 21 %, retención 19 % (art. 101.8 LIRPF).
--         IVA 168 · retención 152 · a pagar 800 + 168 − 152 = 816
--  10/02  Venta de servicios a Cliente General SL: base 5.000, IVA 21 % = 1.050 · total 6.050
--  20/03  Venta a Cliente Dos SL: base 2.000, IVA 10 % = 200 (art. 91) · total 2.200
--  25/02  Cobro de Cliente General SL: 6.050 · 28/02 pago a la abogada: 1.060
--  Modelo 303 (1T): devengado 21 %: 5.000 → 1.050 · 10 %: 2.000 → 200 · total 1.250
--                   deducible: 1.000 → 210 + 800 → 168 = 378   ·   resultado 1.250 − 378 = 872 a ingresar (4750)
--  Modelo 111 (1T): 1 perceptor, base 1.000, retenciones 150 · Modelo 115 (1T): 1 perceptor, base 800, 152
--  PyG: ingresos 5.000 + 2.000 = 7.000 · gastos 1.000 + 800 = 1.800 · resultado 5.200 (antes de impuestos)
--  Balance a 31/03 (tras liquidar):
--    Activo: banco 10.000 + 6.050 − 1.060 = 14.990 · clientes 2.200 · total 17.190
--    PN y pasivo: capital 10.000 + resultado 5.200 + acreedores 816 + HP retenciones 150 + 152 = 302
--                 + HP acreedora por IVA 872 = 17.190
-- =====================================================================
do $$
declare e uuid; abogada uuid; casero uuid; c1 uuid; c2 uuid; f uuid; c jsonb; w record;
begin
  e := public.empresa('Servicios Ruiz SL', 'mainland', array['10000001:Capital', '57200001:Banco', '62100001:Arrendamientos',
         '62300001:Servicios profesionales', '70500001:Prestaciones de servicios']);
  select partner_id into abogada from erp.create_partner(e, 'creditor', 'Ana Ruiz (abogada)', '12345678Z');
  select partner_id into casero  from erp.create_partner(e, 'creditor', 'Inmuebles Centro SL', 'B87654323');
  select partner_id into c1      from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  select partner_id into c2      from erp.create_partner(e, 'customer', 'Cliente Dos SL', 'A58818501');

  perform public.manual(e, '2026-01-02', '[["57200001",10000,0],["10000001",0,10000]]');
  f := public.factura(e, 'purchase', abogada, '2026-01-15', '[{"account_no":"62300001","amount":1000,"tax_code":"VAT21"}]', 'IRPF15');
  assert (select string_agg(g.account_no || ' ' || case when l.debit > 0 then 'D ' || l.debit else 'H ' || l.credit end, ' | ' order by l.line_no)
          from erp.invoices i join erp.journal_lines l on l.entry_id = i.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
          where i.id = f) = '62300001 D 1000.00 | 47200021 D 210.00 | 47510001 H 150.00 | 41000001 H 1060.00', 'asiento de la abogada';
  perform public.factura(e, 'purchase', casero, '2026-02-01', '[{"account_no":"62100001","amount":800,"tax_code":"VAT21"}]', 'IRPF19');
  f := public.factura(e, 'sale', c1, '2026-02-10', '[{"account_no":"70500001","amount":5000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', c2, '2026-03-20', '[{"account_no":"70500001","amount":2000,"tax_code":"VAT10"}]');
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', 'collection', 'partner_id', c1, 'payment_date', '2026-02-25',
    'cash_account_no', '57200001', 'applications', jsonb_build_array(jsonb_build_object('invoice_id', f, 'amount', 6050))));
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', 'payment', 'partner_id', abogada, 'payment_date', '2026-02-28',
    'cash_account_no', '57200001', 'applications', jsonb_build_array(jsonb_build_object('invoice_id',
      (select id from erp.invoices where company_id = e and partner_id = abogada), 'amount', 1060))));

  -- Modelo 303
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 1);
  assert public.casilla(c, 'output', 'tax', 21) = '5000.00 → 1050.00', '303 · 21 %: ' || public.casilla(c, 'output', 'tax', 21);
  assert public.casilla(c, 'output', 'tax', 10) = '2000.00 → 200.00', '303 · 10 %: ' || public.casilla(c, 'output', 'tax', 10);
  assert (c->>'output_tax')::numeric = 1250 and (c->>'input_tax')::numeric = 378, '303 · devengado 1.250, deducible 378: ' || c::text;
  assert (c->>'final_result')::numeric = 872 and c->>'outcome' = 'payable' and (c->>'difference')::numeric = 0, '303 · 872 a ingresar';
  perform erp.post_tax_settlement(e, 'VAT', 2026, 1);

  -- Modelos 111 y 115
  select * into w from erp.withholding_summary(e, 2026, 1) x where x.form = '111';
  assert w.recipients = 1 and w.base = 1000 and w.amount = 150, '111: ' || row_to_json(w)::text;
  select * into w from erp.withholding_summary(e, 2026, 1) x where x.form = '115';
  assert w.recipients = 1 and w.base = 800 and w.amount = 152, '115: ' || row_to_json(w)::text;

  -- PyG y balance a 31/03
  assert public.partida(e, 'pyg', 'PD') = 5200, 'resultado 5.200: ' || public.partida(e, 'pyg', 'PD');
  assert public.saldo(e, '572') = 14990 and public.saldo(e, '430') = 2200, 'banco 14.990 y clientes 2.200';
  assert public.saldo(e, '4751') = -302 and public.saldo(e, '410') = -816 and public.saldo(e, '4750') = -872
         and public.saldo(e, '472') = 0 and public.saldo(e, '477') = 0, 'HP retenciones 302, acreedores 816, HP IVA 872; 472/477 a cero';
  assert public.partida(e, 'balance', 'ACT') = 17190 and public.partida(e, 'balance', 'PNP') = 17190,
         'balance 17.190 = 17.190: ' || public.partida(e, 'balance', 'ACT') || ' / ' || public.partida(e, 'balance', 'PNP');
  raise notice 'OK  · Supuesto 1 · Península: asiento con IRPF, 303 (1.250 − 378 = 872), 111 (150), 115 (152), PyG 5.200, balance 17.190';
end $$;

-- =====================================================================
-- SUPUESTO 2 · Comercial Tenerife SL (Canarias, IGIC) · 1T 2026
-- ---------------------------------------------------------------------
--  Capital 20.000 en el banco.
--  Compra de mercaderías: base 3.000, IGIC 7 % = 210 · total 3.210        (tipo general, DL 1/2025)
--  Venta: base 5.000, IGIC 7 % = 350 · total 5.350
--  Venta de bienes al tipo reducido: base 1.000, IGIC 3 % = 30 · total 1.030
--  Modelo 420: devengado 350 + 30 = 380 · deducible 210 · resultado 170 a ingresar
--  PyG: ventas 6.000 − compras 3.000 = 3.000
--  Balance tras liquidar: activo = banco 20.000 + clientes 5.350 + 1.030 = 26.380
--                         PN y pasivo = capital 20.000 + resultado 3.000 + proveedor 3.210 + HP IGIC 170 = 26.380
-- =====================================================================
do $$
declare e uuid; prov uuid; cli uuid; c jsonb;
begin
  e := public.empresa('Comercial Tenerife SL', 'canary_islands', array['10000001:Capital', '57200001:Banco',
         '60000001:Compras de mercaderías', '70000001:Ventas de mercaderías']);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Distribuciones Canarias SL', 'B12345674');
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Hotel Playa SL', 'B11111119');
  perform public.manual(e, '2026-01-02', '[["57200001",20000,0],["10000001",0,20000]]');
  perform public.factura(e, 'purchase', prov, '2026-01-20', '[{"account_no":"60000001","amount":3000,"tax_code":"IGIC7"}]');
  perform public.factura(e, 'sale', cli, '2026-02-15', '[{"account_no":"70000001","amount":5000,"tax_code":"IGIC7"}]');
  perform public.factura(e, 'sale', cli, '2026-03-10', '[{"account_no":"70000001","amount":1000,"tax_code":"IGIC3"}]');
  c := erp.tax_settlement_calc(e, 'IGIC', 2026, 1);
  assert c->>'form' = '420', 'modelo 420';
  assert public.casilla(c, 'output', 'tax', 7) = '5000.00 → 350.00' and public.casilla(c, 'output', 'tax', 3) = '1000.00 → 30.00',
         '420 · devengado por tipos: ' || (c->'boxes')::text;
  assert (c->>'output_tax')::numeric = 380 and (c->>'input_tax')::numeric = 210 and (c->>'final_result')::numeric = 170,
         '420 · 380 − 210 = 170: ' || c::text;
  perform erp.post_tax_settlement(e, 'IGIC', 2026, 1);
  assert public.partida(e, 'pyg', 'PD') = 3000, 'resultado 3.000';
  assert public.partida(e, 'balance', 'ACT') = 26380 and public.partida(e, 'balance', 'PNP') = 26380, 'balance 26.380';
  raise notice 'OK  · Supuesto 2 · Canarias: 420 (350 + 30 − 210 = 170), PyG 3.000, balance 26.380';
end $$;

-- =====================================================================
-- SUPUESTO 3 · Importadora Madrid SL · adquisición intracomunitaria e inversión del sujeto pasivo · 1T 2026
-- ---------------------------------------------------------------------
--  Capital 20.000.
--  Compra de mercaderías a Lieferant GmbH (Alemania): base 10.000. Es una AIB (art. 13 LIVA): el proveedor no cobra IVA
--  y la empresa se lo autorrepercute (art. 85): 600 D 10.000 · 472 D 2.100 / 477 H 2.100 · 400 H 10.000
--  Obra de reforma del local (Reformas Pérez SL): base 2.000 con ISP (art. 84.Uno.2.º f): 472 D 420 / 477 H 420
--  Venta nacional: base 4.000, IVA 21 % = 840 · total 4.840
--  Modelo 303: devengado 840 (régimen general) + 2.100 (AIB) + 420 (ISP) = 3.360
--              deducible 2.100 + 420 = 2.520 · resultado 840 a ingresar (la autorrepercusión es neutra)
--  PyG: 4.000 − 10.000 − 2.000 = −8.000 (pérdida)
--  Balance tras liquidar: activo = banco 20.000 + clientes 4.840 = 24.840
--                         PN y pasivo = capital 20.000 − 8.000 + proveedor 10.000 + acreedor 2.000 + HP IVA 840 = 24.840
-- =====================================================================
do $$
declare e uuid; ue uuid; obra uuid; cli uuid; c jsonb;
begin
  e := public.empresa('Importadora Madrid SL', 'mainland', array['10000001:Capital', '57200001:Banco',
         '60000001:Compras de mercaderías', '62200001:Reparaciones y conservación', '70000001:Ventas de mercaderías']);
  select partner_id into ue   from erp.create_partner(e, 'vendor', 'Lieferant GmbH', 'DE123456789', 'eu');
  select partner_id into obra from erp.create_partner(e, 'creditor', 'Reformas Pérez SL', 'B87654323');
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  perform public.manual(e, '2026-01-02', '[["57200001",20000,0],["10000001",0,20000]]');
  perform public.factura(e, 'purchase', ue, '2026-01-15', '[{"account_no":"60000001","amount":10000,"tax_code":"VAT21_AIB"}]');
  perform public.factura(e, 'purchase', obra, '2026-02-10', '[{"account_no":"62200001","amount":2000,"tax_code":"VAT21_ISP"}]');
  perform public.factura(e, 'sale', cli, '2026-03-01', '[{"account_no":"70000001","amount":4000,"tax_code":"VAT21"}]');
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 1);
  -- Autorrepercusión: la AIB (VAT21_AIB) y la ISP (VAT21_ISP) van por separado, como en el 303 (casillas 10-11 y 12-13)
  assert public.casilla(c, 'output', 'reverse_charge', 21) = '10000.00 → 2100.00 + 2000.00 → 420.00',
         '303 · autorrepercusión AIB y luego ISP: ' || (c->'boxes')::text;
  assert public.casilla(c, 'input', 'tax', 21) = '10000.00 → 2100.00 + 2000.00 → 420.00', '303 · y su deducción';
  assert (c->>'output_tax')::numeric = 3360 and (c->>'input_tax')::numeric = 2520 and (c->>'final_result')::numeric = 840,
         '303 · 3.360 − 2.520 = 840: ' || c::text;
  perform erp.post_tax_settlement(e, 'VAT', 2026, 1);
  assert public.saldo(e, '400') = -10000 and public.saldo(e, '410') = -2000, 'el alemán y la constructora cobran solo la base';
  assert public.partida(e, 'pyg', 'PD') = -8000, 'pérdida de 8.000: ' || public.partida(e, 'pyg', 'PD');
  assert public.partida(e, 'balance', 'ACT') = 24840 and public.partida(e, 'balance', 'PNP') = 24840, 'balance 24.840';
  raise notice 'OK  · Supuesto 3 · AIB e ISP: autorrepercusión neutra (3.360 − 2.520 = 840), pérdida 8.000, balance 24.840';
end $$;

-- =====================================================================
-- SUPUESTO 4 · Mayorista Sur SL · venta a un minorista en recargo de equivalencia · 1T 2026
-- ---------------------------------------------------------------------
--  Tienda Lola (persona física, comerciante minorista en recargo de equivalencia, art. 154 LIVA):
--    base 1.000 al 21 %: IVA 210 + recargo 5,2 % = 52 (art. 161) · total 1.262
--    base   500 al 10 %: IVA  50 + recargo 1,4 % =  7               · total   557   → la tienda debe 1.819
--  Cliente General SL (régimen general): base 1.000 al 21 % = 210, sin recargo · total 1.210
--  Modelo 303: IVA devengado 210 + 50 + 210 = 470 · recargo devengado 52 + 7 = 59 · total 529 · nada que deducir
-- =====================================================================
do $$
declare e uuid; lola uuid; cli uuid; c jsonb;
begin
  e := public.empresa('Mayorista Sur SL', 'mainland', array['57200001:Banco', '70000001:Ventas de mercaderías']);
  select partner_id into lola from erp.create_partner(e, 'customer', 'Tienda Lola', '87654321X');
  update erp.business_partners set equivalence_surcharge = true where id = lola;
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  perform public.factura(e, 'sale', lola, '2026-02-01', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"},
                                                         {"account_no":"70000001","amount":500,"tax_code":"VAT10"}]');
  perform public.factura(e, 'sale', cli, '2026-02-05', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"}]');
  assert public.saldo(e, '430') = 1819 + 1210, 'la tienda debe 1.819 y el cliente 1.210: ' || public.saldo(e, '430');
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 1);
  assert public.casilla(c, 'output', 'surcharge', 5.2) = '1000.00 → 52.00' and public.casilla(c, 'output', 'surcharge', 1.4) = '500.00 → 7.00',
         '303 · recargo 5,2 % y 1,4 %: ' || (c->'boxes')::text;
  assert (c->>'output_tax')::numeric = 529 and (c->>'input_tax')::numeric = 0 and (c->>'final_result')::numeric = 529,
         '303 · 470 de IVA + 59 de recargo = 529: ' || c::text;
  raise notice 'OK  · Supuesto 4 · recargo de equivalencia: 5,2 %% → 52 y 1,4 %% → 7; 303 = 470 + 59 = 529';
end $$;

-- =====================================================================
-- SUPUESTO 5 · Inmobiliaria Mixta SL · prorrata general · 2026
-- ---------------------------------------------------------------------
--  Alquila locales (gravado al 21 %) y viviendas (exento, art. 20.Uno.23.º b LIVA): prorrata general (art. 102).
--  Porcentaje provisional: el definitivo del año anterior, 80 % (art. 105.Dos).
--  1T · reparación común: base 1.000, IVA 210 → deducible 210 × 80 % = 168 · no deducible 42 = mayor gasto (NRV 12.ª)
--       622 D 1.042 · 472 D 168 / 410 H 1.210
--  1T · alquiler de locales: base 6.000, IVA 1.260 · alquiler de viviendas: base 2.500, exento
--  Modelo 303 1T: devengado 1.260 · deducible 168 · resultado 1.092
--  Prorrata definitiva (art. 104.Dos): 6.000 / (6.000 + 2.500) = 70,59 % → se redondea a la unidad superior: 71 %
--  Deducción definitiva 210 × 71 % = 149,10 · deducido 168 → regularización −18,90 en la última declaración
--  (art. 105.Tres): 6341 D 18,90 (ajustes negativos en la imposición indirecta) / 472 H 18,90
--  Modelo 303 4T: deducible −18,90 → resultado 18,90 a ingresar
--  PyG del año: ingresos 8.500 − gasto 1.042 − ajuste 18,90 = 7.439,10
-- =====================================================================
do $$
declare e uuid; obra uuid; local uuid; viv uuid; c jsonb; q int;
begin
  e := public.empresa('Inmobiliaria Mixta SL', 'mainland', array['57200001:Banco', '62200001:Reparaciones y conservación',
         '75200001:Ingresos por arrendamientos']);
  perform erp.set_pro_rata(e, 'VAT', 2026, 80);
  select partner_id into obra  from erp.create_partner(e, 'creditor', 'Reformas Pérez SL', 'B87654323');
  select partner_id into local from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  select partner_id into viv   from erp.create_partner(e, 'customer', 'Inquilino Vivienda', '11111111H');
  perform public.factura(e, 'purchase', obra, '2026-01-20', '[{"account_no":"62200001","amount":1000,"tax_code":"VAT21"}]');
  assert public.saldo(e, '622') = 1042 and public.saldo(e, '472') = 168, 'IVA no deducible al gasto: 622 = 1.042, 472 = 168';
  perform public.factura(e, 'sale', local, '2026-02-01', '[{"account_no":"75200001","amount":6000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', viv,   '2026-02-01', '[{"account_no":"75200001","amount":2500,"tax_code":"VAT_E20"}]');
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 1);
  assert (c->>'output_tax')::numeric = 1260 and (c->>'input_tax')::numeric = 168 and (c->>'final_result')::numeric = 1092,
         '303 1T · 1.260 − 168 = 1.092: ' || c::text;
  foreach q in array array[1, 2, 3] loop perform erp.post_tax_settlement(e, 'VAT', 2026, q); end loop;

  c := erp.pro_rata_calc(e, 'VAT', 2026);
  assert (c->>'operations_with_right')::numeric = 6000 and (c->>'operations_total')::numeric = 8500, 'numerador y denominador';
  assert (c->>'definitive_pct')::numeric = 71, 'prorrata definitiva 70,59 % → 71 % (unidad superior): ' || (c->>'definitive_pct');
  assert (c->>'should_deduct')::numeric = 149.10 and (c->>'deducted')::numeric = 168 and (c->>'adjustment')::numeric = -18.90,
         'regularización 149,10 − 168 = −18,90: ' || c::text;
  perform erp.post_pro_rata_regularization(e, 'VAT', 2026);
  assert public.saldo(e, '6341') = 18.90, 'ajuste negativo 6341 = 18,90';
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 4);
  assert (c->>'input_tax')::numeric = -18.90 and (c->>'final_result')::numeric = 18.90, '303 4T · 18,90 a ingresar: ' || c::text;
  perform erp.post_tax_settlement(e, 'VAT', 2026, 4);
  assert public.partida(e, 'pyg', 'PD') = 7439.10, 'resultado 8.500 − 1.042 − 18,90 = 7.439,10: ' || public.partida(e, 'pyg', 'PD');
  assert public.partida(e, 'balance', 'ACT') = public.partida(e, 'balance', 'PNP'), 'el balance cuadra';
  raise notice 'OK  · Supuesto 5 · prorrata: 80 %% provisional, 70,59 %% → 71 %% definitiva, regularización −18,90 (6341), resultado 7.439,10';
end $$;

-- Y en las cinco empresas, todos los invariantes en verde
do $$
declare r record;
begin
  for r in select c.name, i.code, i.status from erp.companies c cross join lateral erp.integrity_checks(c.id, 2026) i loop
    assert r.status <> 'fail', format('%s · invariante %s roto', r.name, r.code);
  end loop;
  raise notice 'OK  · los invariantes de las cinco empresas, en verde';
end $$;

\echo '✔ FASE 35 OK · supuestos de referencia'
