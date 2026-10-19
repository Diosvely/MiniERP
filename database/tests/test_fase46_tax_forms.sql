-- =====================================================================
-- PRUEBAS FASE 46 · Casillas de los modelos 303 / 420 y resúmenes anuales 390 / 425 (migración 0051)
-- ---------------------------------------------------------------------
-- Supuesto de referencia (calculado a mano desde las instrucciones de los modelos y la LIVA / Ley 20/1991):
--  A) Distribuciones Ebro SL (IVA), 1.er trimestre de 2026:
--     ventas:  S1 10.000 al 21 % (2.100) · S2 2.000 al 10 % (200) · S3 rectificativa de S1 −1.000 (−210)
--              S4 1.000 al 21 % a un minorista en recargo (210 + recargo 5,2 % 52) · S5 entrega intracomunitaria 3.000
--              S6 exportación 1.500
--     compras: P1 mercaderías 4.000 al 21 % (840) · P2 máquina 6.000 al 21 % a la 213 (1.260, bien de inversión)
--              P3 ordenador 800 a la 217 (168: menos de 3.005,06 €, corriente: art. 108 LIVA)
--              P4 adquisición intracomunitaria 2.000 al 21 % (420 devengado y deducible)
--              P5 obra con inversión del sujeto pasivo 1.000 al 21 % (210 devengado y deducible)
--              P6 rectificativa de P1 −500 (−105)
--     303: 05/06 2.000 · 200 | 07/09 11.000 · 2.310 | 10/11 2.000 · 420 | 12/13 1.000 · 210 | 14/15 −1.000 · −210
--          22/24 1.000 · 52 | 27 = 2.982
--          28/29 5.800 · 1.218 | 30/31 6.000 · 1.260 | 36/37 2.000 · 420 | 40/41 −500 · −105 | 45 = 2.793
--          46 = 189 | 59 3.000 | 60 1.500 | 71 = 189 (igual que la liquidación)
--     2T: compra 10.000 al 21 % y venta 2.000 al 21 % → 46 = −1.680 (a compensar) · 3T sin operaciones (cero)
--     4T: venta 20.000 al 21 % → 46 = 4.200; 110 = 1.680, 78 = 1.680, 71 = 2.520
--     390: 03/04 2.000 · 200 | 05/06 33.000 · 6.930 | 25/26 2.000 · 420 | 27/28 1.000 · 210 | 29/30 −1.000 · −210
--          601/602 1.000 · 52 | 47 = 7.602 | 48/49 15.800 · 3.318 | 50/51 6.000 · 1.260 | 56/57 2.000 · 420
--          639/62 −500 · −105 | 64 = 4.893 | 65 = 2.709 (= 189 − 1.680 + 0 + 4.200) | 86 = 2.709 | 95 = 2.709 (189 + 2.520)
--          99 = 34.000 | 103 = 3.000 | 104 = 1.500 | 108 = 38.500
--  B) Comercial Teide SL (IGIC), 1.er trimestre de 2026:
--     ventas al 0 % 500, al 3 % 1.000 (30), al 7 % 5.000 (350), al 15 % 200 (30), rectificativa al 7 % −400 (−28),
--     exportación 800 · compras: corrientes 2.000 al 7 % (140), bien de inversión 4.000 al 7 % (280), servicio de un
--     profesional de la Península con inversión del sujeto pasivo 1.000 al 7 % (70)
--     420: 01-03 500 · 0 · 0 | 04-06 1.000 · 3 · 30 | 07-09 5.000 · 7 · 350 | 10-12 200 · 15 · 30 | 19/20 1.000 · 70
--          21/22 −400 · −28 | 25 = 452 | 26/27 3.000 · 210 | 28/29 4.000 · 280 | 40 = 490 | 41 = −38 | 45 = −38 | 46 800
--     425: 74 = 6.700 | 79 = 452 | 94 = 490 | 95 = −38 | 120 = 6.300 | 122 = 800 | 134 = 7.100
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb,
                                          clase text default 'invoice', corrige uuid default null)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object(
    'company_id', e, 'invoice_type', tipo, 'document_kind', clase, 'partner_id', tercero,
    'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Prueba', 'corrected_invoice_id', corrige, 'lines', lineas));
$$;
-- casillas de un modelo en texto: "05=2000.00 06=200.00 …" (solo las pedidas)
create or replace function public.casillas(e uuid, y int, q int, boxes text[]) returns text language sql as $$
  select string_agg(box || '=' || amount, ' ' order by array_position(boxes, box))
  from erp.tax_form_boxes(e, y, q) where box = any (boxes);
$$;
create or replace function public.casilla(e uuid, y int, q int, b text) returns numeric language sql as $$
  select amount from erp.tax_form_boxes(e, y, q) where box = b;
$$;
grant execute on function public.factura(uuid, text, uuid, date, jsonb, text, uuid), public.casillas(uuid, int, int, text[]),
  public.casilla(uuid, int, int, text) to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- A) IVA ----------
do $$
declare e uuid; nac uuid; mino uuid; ueC uuid; ext uuid; prov uuid; ueP uuid; obra uuid; s1 uuid; p1 uuid; c jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Distribuciones Ebro SL', 'retail', 'mainland', auth.uid()) returning id into e;
  insert into public.ctx values ('iva', e);
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('60000001', 'Compras de mercaderías'), ('62200001', 'Reparaciones'), ('70000001', 'Ventas de mercaderías'),
    ('21300001', 'Maquinaria'), ('21700001', 'Equipos para procesos de información')) as s(no, name);
  select partner_id into nac  from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  select partner_id into mino from erp.create_partner(e, 'customer', 'Tienda Lola', '12345678Z');
  update erp.business_partners set equivalence_surcharge = true where id = mino;
  select partner_id into ueC  from erp.create_partner(e, 'customer', 'Kunde GmbH', 'DE987654321', 'eu');
  select partner_id into ext  from erp.create_partner(e, 'customer', 'Client Inc', 'US123456', 'non_eu');
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Proveedor Uno SL', 'B12345674');
  select partner_id into ueP  from erp.create_partner(e, 'vendor', 'Lieferant GmbH', 'DE123456789', 'eu');
  select partner_id into obra from erp.create_partner(e, 'creditor', 'Reformas Pérez SL', 'B87654323');

  s1 := public.factura(e, 'sale', nac, '2026-01-10', '[{"account_no":"70000001","amount":10000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', nac, '2026-01-12', '[{"account_no":"70000001","amount":2000,"tax_code":"VAT10"}]');
  perform public.factura(e, 'sale', nac, '2026-02-01', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"}]', 'credit_memo', s1);
  perform public.factura(e, 'sale', mino, '2026-02-05', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', ueC, '2026-02-10', '[{"account_no":"70000001","amount":3000,"tax_code":"VAT_EU"}]');
  perform public.factura(e, 'sale', ext, '2026-02-11', '[{"account_no":"70000001","amount":1500,"tax_code":"VAT_EXP"}]');
  p1 := public.factura(e, 'purchase', prov, '2026-01-15', '[{"account_no":"60000001","amount":4000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'purchase', prov, '2026-01-20', '[{"account_no":"21300001","amount":6000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'purchase', prov, '2026-01-21', '[{"account_no":"21700001","amount":800,"tax_code":"VAT21"}]');
  perform public.factura(e, 'purchase', ueP, '2026-02-15', '[{"account_no":"60000001","amount":2000,"tax_code":"VAT21_AIB"}]');
  perform public.factura(e, 'purchase', obra, '2026-03-01', '[{"account_no":"62200001","amount":1000,"tax_code":"VAT21_ISP"}]');
  perform public.factura(e, 'purchase', prov, '2026-03-10', '[{"account_no":"60000001","amount":500,"tax_code":"VAT21"}]', 'credit_memo', p1);

  assert (select string_agg(distinct form, ',') from erp.tax_form_boxes(e, 2026, 1)) = '303', 'modelo 303';
  assert public.casillas(e, 2026, 1, array['04','05','06','07','08','09','10','11','12','13','14','15','22','24','27'])
       = '04=2000.00 05=10 06=200.00 07=11000.00 08=21 09=2310.00 10=2000.00 11=420.00 12=1000.00 13=210.00 14=-1000.00 15=-210.00 22=1000.00 24=52.00 27=2982.00',
         public.casillas(e, 2026, 1, array['04','05','06','07','08','09','10','11','12','13','14','15','22','24','27']);
  assert not exists (select 1 from erp.tax_form_boxes(e, 2026, 1) where box in ('150', '151', '152')), 'sin tipo cero, no salen sus casillas';
  raise notice 'OK  · 303 devengado: 10 %% y 21 %%, AIB (10/11), ISP (12/13), rectificativa (14/15), recargo 5,2 %% (22/24); 27 = 2.982';
  assert public.casillas(e, 2026, 1, array['28','29','30','31','36','37','40','41','45','46'])
       = '28=5800.00 29=1218.00 30=6000.00 31=1260.00 36=2000.00 37=420.00 40=-500.00 41=-105.00 45=2793.00 46=189.00',
         public.casillas(e, 2026, 1, array['28','29','30','31','36','37','40','41','45','46']);
  raise notice 'OK  · 303 deducible: la máquina (6.000) es bien de inversión; el ordenador (800 < 3.005,06) es corriente; 45 = 2.793; 46 = 189';
  assert public.casillas(e, 2026, 1, array['59','60','65','110','78','87','71']) = '59=3000.00 60=1500.00 65=100 110=0 78=0 87=0 71=189.00',
         public.casillas(e, 2026, 1, array['59','60','65','110','78','87','71']);
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 1);
  assert (c->>'final_result')::numeric = public.casilla(e, 2026, 1, '71') and (c->>'difference')::numeric = 0, 'la casilla 71 = la liquidación';
  perform erp.post_tax_settlement(e, 'VAT', 2026, 1);
  raise notice 'OK  · 59 entregas intracomunitarias, 60 exportaciones; 71 = 189, igual que la liquidación contabilizada';

  -- 2T a compensar, 3T a cero, 4T con la compensación
  perform public.factura(e, 'purchase', prov, '2026-04-10', '[{"account_no":"60000001","amount":10000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', nac, '2026-05-10', '[{"account_no":"70000001","amount":2000,"tax_code":"VAT21"}]');
  assert public.casilla(e, 2026, 2, '46') = -1680 and public.casilla(e, 2026, 2, '71') = -1680;
  perform erp.post_tax_settlement(e, 'VAT', 2026, 2);
  perform erp.post_tax_settlement(e, 'VAT', 2026, 3);
  perform public.factura(e, 'sale', nac, '2026-11-10', '[{"account_no":"70000001","amount":20000,"tax_code":"VAT21"}]');
  assert public.casillas(e, 2026, 4, array['46','110','78','87','71']) = '46=4200.00 110=1680.00 78=1680.00 87=0.00 71=2520.00',
         public.casillas(e, 2026, 4, array['46','110','78','87','71']);
  perform erp.post_tax_settlement(e, 'VAT', 2026, 4);
  assert public.casillas(e, 2026, 4, array['78','71']) = '78=1680.00 71=2520.00', 'contabilizada, la compensación es la de la liquidación';
  raise notice 'OK  · 2T −1.680 a compensar; 4T 4.200 − 1.680 (110 / 78) = 2.520 a ingresar';

  -- 390
  assert (select string_agg(distinct form, ',') from erp.tax_form_boxes(e, 2026)) = '390', 'resumen anual 390';
  assert public.casillas(e, 2026, null, array['03','04','05','06','25','26','27','28','29','30','601','602','47'])
       = '03=2000.00 04=200.00 05=33000.00 06=6930.00 25=2000.00 26=420.00 27=1000.00 28=210.00 29=-1000.00 30=-210.00 601=1000.00 602=52.00 47=7602.00',
         public.casillas(e, 2026, null, array['03','04','05','06','25','26','27','28','29','30','601','602','47']);
  assert public.casillas(e, 2026, null, array['605','606','613','614','629','630','48','49','50','51','56','57','639','62','64','65'])
       = '605=15800.00 606=3318.00 613=6000.00 614=1260.00 629=2000.00 630=420.00 48=15800.00 49=3318.00 50=6000.00 51=1260.00 56=2000.00 57=420.00 639=-500.00 62=-105.00 64=4893.00 65=2709.00',
         public.casillas(e, 2026, null, array['605','606','613','614','629','630','48','49','50','51','56','57','639','62','64','65']);
  assert public.casillas(e, 2026, null, array['84','85','86','95','97','98','99','103','104','107','108'])
       = '84=2709.00 85=0 86=2709.00 95=2709.00 97=0 98=0 99=34000.00 103=3000.00 104=1500.00 107=0 108=38500.00',
         public.casillas(e, 2026, null, array['84','85','86','95','97','98','99','103','104','107','108']);
  assert public.casilla(e, 2026, null, '65') = (select sum(public.casilla(e, 2026, q, '46')) from generate_series(1, 4) q), '65 = suma de los 46';
  raise notice 'OK  · 390: 47 = 7.602, 64 = 4.893, 65 = 2.709 = suma de los cuatro trimestres = 95 ingresado; volumen 108 = 38.500';
end $$;

-- ---------- B) IGIC ----------
do $$
declare e uuid; cli uuid; ext uuid; prov uuid; pen uuid; f uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Comercial Teide SL', 'retail', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('igic', e);
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('60000001', 'Compras de mercaderías'), ('62300001', 'Servicios de profesionales'), ('70000001', 'Ventas de mercaderías'),
    ('21300001', 'Maquinaria')) as s(no, name);
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Cliente Canario SL', 'B11111119');
  select partner_id into ext  from erp.create_partner(e, 'customer', 'Client Inc', 'US123456', 'non_eu');
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Proveedor Canario SL', 'B12345674');
  select partner_id into pen  from erp.create_partner(e, 'creditor', 'Consultora Madrid SL', 'B87654323', 'mainland');

  perform public.factura(e, 'sale', cli, '2026-01-10', '[{"account_no":"70000001","amount":500,"tax_code":"IGIC0"},{"account_no":"70000001","amount":1000,"tax_code":"IGIC3"}]');
  f := public.factura(e, 'sale', cli, '2026-01-11', '[{"account_no":"70000001","amount":5000,"tax_code":"IGIC7"},{"account_no":"70000001","amount":200,"tax_code":"IGIC15"}]');
  perform public.factura(e, 'sale', cli, '2026-02-01', '[{"account_no":"70000001","amount":400,"tax_code":"IGIC7"}]', 'credit_memo', f);
  perform public.factura(e, 'sale', ext, '2026-02-02', '[{"account_no":"70000001","amount":800,"tax_code":"IGIC_EXP"}]');
  perform public.factura(e, 'purchase', prov, '2026-01-15', '[{"account_no":"60000001","amount":2000,"tax_code":"IGIC7"}]');
  perform public.factura(e, 'purchase', prov, '2026-01-16', '[{"account_no":"21300001","amount":4000,"tax_code":"IGIC7"}]');
  perform public.factura(e, 'purchase', pen, '2026-02-20', '[{"account_no":"62300001","amount":1000,"tax_code":"IGIC7_ISP"}]');

  assert (select string_agg(distinct form, ',') from erp.tax_form_boxes(e, 2026, 1)) = '420', 'modelo 420';
  assert public.casillas(e, 2026, 1, array['01','02','03','04','05','06','07','08','09','10','11','12','19','20','21','22','25'])
       = '01=500.00 02=0.00 03=0.00 04=1000.00 05=3.00 06=30.00 07=5000.00 08=7.00 09=350.00 10=200.00 11=15.00 12=30.00 19=1000.00 20=70.00 21=-400.00 22=-28.00 25=452.00',
         public.casillas(e, 2026, 1, array['01','02','03','04','05','06','07','08','09','10','11','12','19','20','21','22','25']);
  assert public.casillas(e, 2026, 1, array['26','27','28','29','40','41','43','45','46'])
       = '26=3000.00 27=210.00 28=4000.00 29=280.00 40=490.00 41=-38.00 43=0 45=-38.00 46=800.00',
         public.casillas(e, 2026, 1, array['26','27','28','29','40','41','43','45','46']);
  assert public.casilla(e, 2026, 1, '45') = (erp.tax_settlement_calc(e, 'IGIC', 2026, 1)->>'final_result')::numeric, '45 = la liquidación';
  raise notice 'OK  · 420: cuatro tipos en sus casillas (0, 3, 7 y 15 %%), ISP 19/20, rectificativa 21/22; 25 = 452, 40 = 490, 45 = −38';
  perform erp.post_tax_settlement(e, 'IGIC', 2026, 1);
  assert (select string_agg(distinct form, ',') from erp.tax_form_boxes(e, 2026)) = '425', 'resumen anual 425';
  assert public.casillas(e, 2026, null, array['74','75','76','70','71','79','80','81','82','83','94','95','113','114','115','116','120','122','133','134'])
       = '74=6700.00 75=1000.00 76=70.00 70=-400.00 71=-28.00 79=452.00 80=3000.00 81=210.00 82=4000.00 83=280.00 94=490.00 95=-38.00 113=-38.00 114=0 115=-38.00 116=0 120=6300.00 122=800.00 133=0 134=7100.00',
         public.casillas(e, 2026, null, array['74','75','76','70','71','79','80','81','82','83','94','95','113','114','115','116','120','122','133','134']);
  raise notice 'OK  · 425: 79 = 452, 94 = 490, 95 = −38; volumen 134 = 7.100';
end $$;

-- ---------- Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
begin
  assert not exists (select 1 from erp.tax_form_boxes((select v from public.ctx where k = 'iva'), 2026, 1) where amount <> 0), 'otro usuario: sin datos';
  raise notice 'OK  · otro usuario no ve las casillas de la empresa';
end $$;

\echo '✔ FASE 46 OK · casillas de los modelos 303 / 420 y resúmenes 390 / 425'
