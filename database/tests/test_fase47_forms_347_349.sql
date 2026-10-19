-- =====================================================================
-- PRUEBAS FASE 47 · Modelos 347 y 349 (migración 0052)
-- ---------------------------------------------------------------------
-- Supuesto de referencia (calculado a mano desde el RD 1065/2007, arts. 31-35, y el RIVA, arts. 78-81):
--  Distribuciones Ebro SL (IVA), 2026:
--   347 · ventas (clave B):  Cliente General 2.000 al 21 % en el 1T (2.420) + 1.000 en el 3T (1.210) = 3.630 → SÍ
--                            Cliente Dos 2.000 al 21 % (2.420) → NO (no supera 3.005,06)
--                            Cliente Tres 3.000 al 10 % (3.300) − rectificativa 500 (550) = 2.750 → NO
--                            Cliente sin NIF 4.000 al 21 % (4.840) → SÍ, con el aviso de que falta el NIF
--         compras (clave A): Proveedor Uno 5.000 al 21 % en el 2T (6.050) → SÍ
--                            Reformas Pérez, obra con inversión del sujeto pasivo 4.000 (sin IVA en la factura) → SÍ, 4.000
--                            Abogada 4.000 con retención de IRPF → NO (va en el 190)
--                            Lieferant GmbH (adquisición intracomunitaria) y Kunde GmbH (entregas) → NO (van en el 349)
--   349 · 1T: Kunde GmbH E 30.000 (mercaderías, 700) y S 25.000 (servicios, 705); Lieferant GmbH A 10.000
--             E + S = 55.000 > 50.000 → presentación mensual
--         2T: rectificativa de 2.000 de la entrega del 1T → rectificación del 1T: rectificado 28.000, declarado 30.000
--             (y el 2T sigue siendo mensual: el 1T, dentro de los cuatro trimestres anteriores, pasó de 50.000)
--         Comercial Teide SL (IGIC): el 349 no aplica
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb,
                                          clase text default 'invoice', corrige uuid default null, retencion text default null)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object(
    'company_id', e, 'invoice_type', tipo, 'document_kind', clase, 'partner_id', tercero,
    'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Prueba', 'corrected_invoice_id', corrige, 'withholding_code', retencion, 'lines', lineas));
$$;
grant execute on function public.factura(uuid, text, uuid, date, jsonb, text, uuid, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; g uuid; c2 uuid; c3 uuid; sn uuid; p1 uuid; obra uuid; abo uuid; ueP uuid; ueC uuid; f uuid; t3 uuid; r record;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Distribuciones Ebro SL', 'retail', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('60000001', 'Compras de mercaderías'), ('62200001', 'Reparaciones'), ('62300001', 'Servicios de profesionales'),
    ('70000001', 'Ventas de mercaderías'), ('70500001', 'Prestaciones de servicios')) as s(no, name);
  select partner_id into g   from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  select partner_id into c2  from erp.create_partner(e, 'customer', 'Cliente Dos SL', 'A58818501');
  select partner_id into c3  from erp.create_partner(e, 'customer', 'Cliente Tres', '87654321X');
  select partner_id into sn  from erp.create_partner(e, 'customer', 'Cliente sin NIF');
  select partner_id into p1  from erp.create_partner(e, 'vendor', 'Proveedor Uno SL', 'B12345674');
  select partner_id into obra from erp.create_partner(e, 'creditor', 'Reformas Pérez SL', 'B87654323');
  select partner_id into abo from erp.create_partner(e, 'creditor', 'Abogada Ficticia', '12345678Z');
  select partner_id into ueP from erp.create_partner(e, 'vendor', 'Lieferant GmbH', 'DE123456789', 'eu');
  select partner_id into ueC from erp.create_partner(e, 'customer', 'Kunde GmbH', 'DE987654321', 'eu');

  perform public.factura(e, 'sale', g, '2026-02-10', '[{"account_no":"70000001","amount":2000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', g, '2026-08-10', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', c2, '2026-03-10', '[{"account_no":"70000001","amount":2000,"tax_code":"VAT21"}]');
  t3 := public.factura(e, 'sale', c3, '2026-04-10', '[{"account_no":"70000001","amount":3000,"tax_code":"VAT10"}]');
  perform public.factura(e, 'sale', c3, '2026-05-10', '[{"account_no":"70000001","amount":500,"tax_code":"VAT10"}]', 'credit_memo', t3);
  perform public.factura(e, 'sale', sn, '2026-06-10', '[{"account_no":"70000001","amount":4000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'purchase', p1, '2026-05-15', '[{"account_no":"60000001","amount":5000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'purchase', obra, '2026-06-15', '[{"account_no":"62200001","amount":4000,"tax_code":"VAT21_ISP"}]');
  perform public.factura(e, 'purchase', abo, '2026-03-20', '[{"account_no":"62300001","amount":4000,"tax_code":"VAT21"}]', 'invoice', null, 'IRPF15');
  perform public.factura(e, 'purchase', ueP, '2026-02-20', '[{"account_no":"60000001","amount":10000,"tax_code":"VAT21_AIB"}]');
  f := public.factura(e, 'sale', ueC, '2026-03-01', '[{"account_no":"70000001","amount":30000,"tax_code":"VAT_EU"},{"account_no":"70500001","amount":25000,"tax_code":"VAT_EU"}]');

  -- ---------- 347 ----------
  assert (select string_agg(op_key || ' ' || partner_name || ' ' || q1 || '/' || q2 || '/' || q3 || '/' || q4 || '=' || total
                            || case when missing_vat_no then ' sin NIF' else '' end, ' | ')
          from erp.form_347(e, 2026))
       = 'B Cliente General SL 2420.00/0/1210.00/0=3630.00 | B Cliente sin NIF 0/4840.00/0/0=4840.00 sin NIF | A Proveedor Uno SL 0/6050.00/0/0=6050.00 | A Reformas Pérez SL 0/4000.00/0/0=4000.00',
         (select string_agg(op_key || ' ' || partner_name || ' ' || q1 || '/' || q2 || '/' || q3 || '/' || q4 || '=' || total
                            || case when missing_vat_no then ' sin NIF' else '' end, ' | ') from erp.form_347(e, 2026));
  raise notice 'OK  · 347: dos clientes (3.630 en dos trimestres; 4.840 sin NIF) y dos proveedores (6.050; 4.000 con ISP)';
  raise notice 'OK  · 347: fuera Cliente Dos (2.420), Cliente Tres (3.300 − 550 = 2.750), la abogada (retención) y las operaciones intracomunitarias';

  -- ---------- 349 ----------
  assert (select string_agg(section || ' ' || vat_registration_no || ' ' || op_key || ' ' || amount, ' | ' order by op_key) from erp.form_349(e, 2026, 1))
       = 'operation DE123456789 A 10000.00 | operation DE987654321 E 30000.00 | operation DE987654321 S 25000.00',
         (select string_agg(section || ' ' || vat_registration_no || ' ' || op_key || ' ' || amount, ' | ') from erp.form_349(e, 2026, 1));
  assert erp.form_349_period(e, 2026, 1) = 'monthly', 'E + S = 55.000 > 50.000';
  perform public.factura(e, 'sale', ueC, '2026-04-05', '[{"account_no":"70000001","amount":2000,"tax_code":"VAT_EU"}]', 'credit_memo', f);
  select * into r from erp.form_349(e, 2026, 2);
  assert r.section = 'rectification' and r.op_key = 'E' and r.corrected_period = '1T 2026' and r.amount = 28000 and r.previously_declared = 30000, r::text;
  assert (select count(*) from erp.form_349(e, 2026, 2)) = 1, 'en el 2T solo la rectificación';
  assert erp.form_349_period(e, 2026, 2) = 'monthly' and erp.form_349_period(e, 2026, 3) = 'monthly' and erp.form_349_period(e, 2027, 2) = 'quarterly',
         'mensual mientras el 1T esté entre los cuatro trimestres anteriores';
  assert not exists (select 1 from erp.form_349(e, 2026, 1) where op_key = 'E' and amount <> 30000), 'el 1T no cambia';
  raise notice 'OK  · 349 1T: E 30.000, S 25.000, A 10.000 (mensual: E + S = 55.000); 2T: rectificación del 1T, 28.000 frente a 30.000';
end $$;

-- ---------- IGIC: el 349 no aplica ----------
do $$
declare e uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Comercial Teide SL', 'retail', 'canary_islands', auth.uid()) returning id into e;
  assert not exists (select 1 from erp.form_349(e, 2026, 1)), 'IGIC: sin 349';
  assert not exists (select 1 from erp.form_347(e, 2026)), 'sin operaciones, sin 347';
  raise notice 'OK  · empresa canaria (IGIC): el 349 no aplica';
end $$;

\echo '✔ FASE 47 OK · modelos 347 y 349'
