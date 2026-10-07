-- =====================================================================
-- PRUEBAS FASE 14 · Inversión del sujeto pasivo y recargo de equivalencia (migración 0019)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.asiento(p_invoice uuid) returns text language sql as $$
  select string_agg(g.account_no || case when l.debit > 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.invoices i join erp.journal_lines l on l.entry_id = i.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id where i.id = p_invoice;
$$;
create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object(
    'company_id', e, 'invoice_type', tipo, 'partner_id', tercero,
    'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Prueba', 'lines', lineas));
$$;
create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
grant execute on function public.asiento(uuid), public.factura(uuid, text, uuid, date, jsonb), public.falla(text, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Península: ISP, adquisición intracomunitaria y venta a un minorista en recargo ----------
do $$
declare e uuid; ue uuid; obra uuid; mino uuid; nac uuid; f uuid; c jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Mayorista Madrid SL', 'retail', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('60000001', 'Compras de mercaderías'), ('62300001', 'Servicios profesionales'), ('62200001', 'Reparaciones'),
    ('70000001', 'Ventas de mercaderías')) as s(no, name);
  select partner_id into ue   from erp.create_partner(e, 'vendor', 'Lieferant GmbH', 'DE123456789', 'eu');
  select partner_id into obra from erp.create_partner(e, 'creditor', 'Reformas Pérez SL', 'B12345674');
  select partner_id into nac  from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  select partner_id into mino from erp.create_partner(e, 'customer', 'Tienda Lola', '12345678Z');
  update erp.business_partners set equivalence_surcharge = true where id = mino;

  -- Configuración automática de cuentas especiales
  assert (select input_account_no || '/' || output_account_no from erp.v_tax_setup where company_id = e and tax_code = 'VAT21_AIB')
       = '47208021/47708021', 'subcuentas de AIB';
  assert (select input_account_no || '/' || output_account_no from erp.v_tax_setup where company_id = e and tax_code = 'VAT21_ISP')
       = '47209021/47709021', 'subcuentas de ISP';
  assert (select surcharge_account_no from erp.v_tax_setup where company_id = e and tax_code = 'VAT21') = '47707052', 'recargo 5,2 %';
  assert (select surcharge_account_no from erp.v_tax_setup where company_id = e and tax_code = 'VAT4') = '47707005', 'recargo 0,5 %';
  raise notice 'OK  · al configurar el IVA se crean 472/477 de AIB (…8…) e ISP (…9…) y el recargo repercutido (4770 7…)';

  -- Adquisición intracomunitaria: el proveedor alemán no cobra IVA; la empresa se lo autorrepercute
  f := public.factura(e, 'purchase', ue, '2026-04-10', '[{"account_no":"60000001","amount":10000,"tax_code":"VAT21_AIB"}]');
  assert public.asiento(f) = '60000001 D 10000.00 | 47208021 D 2100.00 | 47708021 H 2100.00 | 40000001 H 10000.00', public.asiento(f);
  assert (select total_amount from erp.v_invoices where id = f) = 10000, 'el proveedor solo cobra la base';
  raise notice 'OK  · AIB: 600 D 10.000 · 472 D 2.100 · 477 H 2.100 · 400 H 10.000 (el IVA no lo cobra el proveedor)';

  -- ISP de una obra: la constructora factura sin IVA
  f := public.factura(e, 'purchase', obra, '2026-04-15', '[{"account_no":"62200001","amount":2000,"tax_code":"VAT21_ISP"}]');
  assert public.asiento(f) = '62200001 D 2000.00 | 47209021 D 420.00 | 47709021 H 420.00 | 41000001 H 2000.00', public.asiento(f);
  raise notice 'OK  · ISP (obra): 472 D 420 = 477 H 420; acreedor por 2.000';

  -- Venta a un minorista en recargo: IVA 21 % + recargo 5,2 %
  f := public.factura(e, 'sale', mino, '2026-05-02', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"}]');
  assert public.asiento(f) = '70000001 H 1000.00 | 47700021 H 210.00 | 47707052 H 52.00 | 43000002 D 1262.00', public.asiento(f);
  assert (select total_surcharge from erp.v_invoices where id = f) = 52 and (select total_amount from erp.v_invoices where id = f) = 1262;
  -- Al cliente normal, sin recargo
  f := public.factura(e, 'sale', nac, '2026-05-03', '[{"account_no":"70000001","amount":500,"tax_code":"VAT21"}]');
  assert public.asiento(f) = '70000001 H 500.00 | 47700021 H 105.00 | 43000001 D 605.00';
  raise notice 'OK  · venta a minorista: 700 H 1.000 · 477 H 210 · 477 recargo H 52 · 430 D 1.262 (al cliente general, sin recargo)';

  -- Liquidación 2T: el ISP/AIB devenga y deduce; el recargo se ingresa; todo cuadra con el libro registro
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 2);
  assert (c->>'difference')::numeric = 0, format('cuadre libro registro / contabilidad: %s', c->>'difference');
  assert (c->>'output_tax')::numeric = 2100 + 420 + 210 + 52 + 105, 'devengado: AIB + ISP + IVA ventas + recargo';
  assert (c->>'input_tax')::numeric = 2100 + 420, 'deducible: AIB + ISP';
  assert (c->>'result')::numeric = 367, 'a ingresar: 210 + 52 + 105';
  assert c->'boxes' @> '[{"side":"output","kind":"surcharge","tax_amount":52},{"side":"output","kind":"reverse_charge","tax_code":"VAT21_AIB","tax_amount":2100}]';
  raise notice 'OK  · 303 del 2T: devengado 4.887 · deducible 2.520 · a ingresar 367 (el ISP y la AIB se anulan) · cuadra';
  perform erp.post_tax_settlement(e, 'VAT', 2026, 2);
end $$;

-- ---------- Reglas ----------
do $$
declare e uuid := (select id from erp.companies where name = 'Mayorista Madrid SL');
        nac uuid := (select id from erp.business_partners where name = 'Cliente General SL');
        obra uuid := (select id from erp.business_partners where name = 'Reformas Pérez SL');
        ue uuid := (select id from erp.business_partners where name = 'Lieferant GmbH');
begin
  assert public.falla(format($q$select public.factura(%L, 'sale', %L, '2026-07-01', '[{"account_no":"70000001","amount":10,"tax_code":"VAT21_ISP"}]')$q$, e, nac),
    'only for received invoices'), 'ISP en una venta';
  assert public.falla(format($q$select public.factura(%L, 'purchase', %L, '2026-07-01', '[{"account_no":"60000001","amount":10,"tax_code":"VAT21_AIB"}]')$q$, e, obra),
    'vendor from another EU country'), 'AIB a un proveedor español';
  assert public.falla(format($q$select public.factura(%L, 'sale', %L, '2026-07-01', '[{"account_no":"70000001","amount":10,"tax_code":"VAT_RE_INC"}]')$q$, e, nac),
    'only for sales of a retailer'), 'VAT_RE_INC en régimen general';
  assert public.falla(format('update erp.business_partners set equivalence_surcharge = true where id = %L', ue),
    'Only customers from mainland'), 'un proveedor no está en recargo';
  raise notice 'OK  · reglas: ISP/AIB solo en compras, AIB solo con proveedor UE, VAT_RE_INC solo para minoristas en RE';
end $$;

-- ---------- Minorista en recargo de equivalencia ----------
do $$
declare e uuid; mayorista uuid; cli uuid; f uuid; c jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Tienda Lola', 'retail', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.set_vat_regime(e, 'equivalence_surcharge');
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('60000001', 'Compras de mercaderías'), ('70000001', 'Ventas de mercaderías')) as s(no, name);
  select partner_id into mayorista from erp.create_partner(e, 'vendor', 'Mayorista Madrid SL', 'B12345674');
  select partner_id into cli from erp.create_partner(e, 'customer', 'Cliente de mostrador', '12345678Z');

  -- Compra: IVA y recargo no deducibles → mayor coste de la mercadería
  f := public.factura(e, 'purchase', mayorista, '2026-05-02', '[{"account_no":"60000001","amount":1000,"tax_code":"VAT21"}]');
  assert public.asiento(f) = '60000001 D 1000.00 | 60000001 D 210.00 | 60000001 D 52.00 | 40000001 H 1262.00', public.asiento(f);
  assert (select deductible from erp.v_invoice_register where invoice_id = f) = false;
  raise notice 'OK  · minorista: compra 1.000 + IVA 210 + recargo 52, todo a la 600 (no deducible) · proveedor 1.262';

  -- Venta con el IVA incluido; con un tipo con cuota, error
  f := public.factura(e, 'sale', cli, '2026-05-10', '[{"account_no":"70000001","amount":1500,"tax_code":"VAT_RE_INC"}]');
  assert public.asiento(f) = '70000001 H 1500.00 | 43000001 D 1500.00';
  assert public.falla(format($q$select public.factura(%L, 'sale', %L, '2026-05-11', '[{"account_no":"70000001","amount":10,"tax_code":"VAT21"}]')$q$, e, cli),
    'VAT included');
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 2);
  assert (c->>'result')::numeric = 0 and (c->>'difference')::numeric = 0, 'el minorista no liquida IVA';
  raise notice 'OK  · minorista: vende con el IVA incluido (VAT_RE_INC) y su 303 queda a cero';
end $$;

-- ---------- Canarias: ISP de IGIC (servicio de una empresa peninsular) ----------
do $$
declare e uuid; pen uuid; f uuid; c jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Hotel Canario SL', 'services', 'canary_islands', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, '62300001', 'Servicios profesionales');
  select partner_id into pen from erp.create_partner(e, 'creditor', 'Consultora Madrid SL', 'B12345674', 'mainland');
  f := public.factura(e, 'purchase', pen, '2026-06-01', '[{"account_no":"62300001","amount":3000,"tax_code":"IGIC7_ISP"}]');
  assert public.asiento(f) = '62300001 D 3000.00 | 47219007 D 210.00 | 47719007 H 210.00 | 41000001 H 3000.00', public.asiento(f);
  c := erp.tax_settlement_calc(e, 'IGIC', 2026, 2);
  assert (c->>'difference')::numeric = 0 and (c->>'result')::numeric = 0;
  assert public.falla($q$update erp.companies set vat_regime = 'equivalence_surcharge' where name = 'Hotel Canario SL'$q$,
    'only exists for VAT'), 'no hay recargo en Canarias';
  raise notice 'OK  · Canarias: servicio de la Península → ISP de IGIC 7 %% (472 = 477), y sin recargo de equivalencia';
end $$;

reset role;
drop function public.asiento(uuid);
drop function public.factura(uuid, text, uuid, date, jsonb);
drop function public.falla(text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 14 (ISP Y RECARGO DE EQUIVALENCIA) PASARON ==========='
