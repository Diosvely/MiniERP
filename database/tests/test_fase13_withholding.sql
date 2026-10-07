-- =====================================================================
-- PRUEBAS FASE 13 · Retención IRPF y operaciones sin cuota (migración 0018)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

-- Asiento de una factura en texto: "cuenta D/H importe" ordenado por línea
create or replace function public.asiento(p_invoice uuid) returns text language sql as $$
  select string_agg(g.account_no || case when l.debit > 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.invoices i join erp.journal_lines l on l.entry_id = i.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id where i.id = p_invoice;
$$;
-- Registra una factura y devuelve su id
create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb,
                                          retencion text default null, clase text default 'invoice', corrige uuid default null)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object(
    'company_id', e, 'invoice_type', tipo, 'document_kind', clase, 'partner_id', tercero,
    'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Prueba', 'withholding_code', retencion,
    'corrected_invoice_id', corrige, 'lines', lineas));
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
grant execute on function public.asiento(uuid), public.factura(uuid, text, uuid, date, jsonb, text, text, uuid),
  public.falla(text, text) to authenticated;
create table public.ctx (clave text primary key, valor uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare
  e uuid; abogado uuid; casero uuid; cli uuid; cli_can uuid; cli_ue uuid; f uuid; c jsonb; r record;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Servicios Madrid SL', 'services', 'mainland', auth.uid()) returning id into e;
  insert into public.ctx values ('peninsula', e);
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('62100001', 'Arrendamientos'), ('62300001', 'Servicios profesionales'),
    ('70000001', 'Ventas de mercaderías'), ('70500001', 'Prestaciones de servicios')) as s(no, name);
  select partner_id into abogado from erp.create_partner(e, 'creditor', 'Abogada Ruiz', '12345678Z');
  select partner_id into casero  from erp.create_partner(e, 'creditor', 'Locales Centro SL', 'B12345674');
  select partner_id into cli     from erp.create_partner(e, 'customer', 'Cliente Madrid SL', 'B11111119');
  select partner_id into cli_can from erp.create_partner(e, 'customer', 'Hotel Tenerife SL', 'B22222228', 'canary_islands');
  select partner_id into cli_ue  from erp.create_partner(e, 'customer', 'Client Paris SARL', 'FR12345678901', 'eu');
  insert into public.ctx values ('cli', cli), ('cli_can', cli_can), ('cli_ue', cli_ue), ('abogado', abogado);

  -- ---------- Configuración automática ----------
  assert (select count(*) from erp.v_withholding_setup where company_id = e) = 3, 'IRPF15, IRPF7 e IRPF19 configurados al configurar el IVA';
  assert (select payable_account_no from erp.v_withholding_setup where company_id = e and withholding_code = 'IRPF15') = '47510001';
  assert (select payable_account_no from erp.v_withholding_setup where company_id = e and withholding_code = 'IRPF19') = '47510005';
  assert (select receivable_account_no from erp.v_withholding_setup where company_id = e and withholding_code = 'IRPF15') = '47300001';
  assert (select count(*) from erp.tax_setup where company_id = e and tax_code in ('VAT_E20','VAT_EXP','VAT_EU','VAT_NS')) = 4,
    'tipos sin cuota configurados';
  raise notice 'OK  · al configurar el IVA se crean 4751 (mod. 111 y 115), 473 y los tipos sin cuota';

  -- ---------- Retención en facturas recibidas ----------
  f := public.factura(e, 'purchase', abogado, '2026-02-10', '[{"account_no":"62300001","amount":1000,"tax_code":"VAT21"}]', 'IRPF15');
  assert public.asiento(f) = '62300001 D 1000.00 | 47200021 D 210.00 | 47510001 H 150.00 | 41000001 H 1060.00', public.asiento(f);
  assert (select amount_due from erp.v_invoices where id = f) = 1060 and (select total_amount from erp.v_invoices where id = f) = 1210;
  raise notice 'OK  · profesional: 1.000 + IVA 210 − IRPF 15 %% 150 → a pagar 1.060 (4751 al Haber)';

  perform public.factura(e, 'purchase', abogado, '2026-03-10', '[{"account_no":"62300001","amount":100,"tax_code":"VAT21"}]',
    'IRPF15', 'credit_memo', f);
  assert (select public.asiento(id) from erp.invoices where company_id = e and document_kind = 'credit_memo')
       = '62300001 H 100.00 | 47200021 H 21.00 | 47510001 D 15.00 | 41000001 D 106.00';
  raise notice 'OK  · rectificativa: la retención también se invierte';

  f := public.factura(e, 'purchase', casero, '2026-03-01', '[{"account_no":"62100001","amount":1000,"tax_code":"VAT21"}]', 'IRPF19');
  assert public.asiento(f) = '62100001 D 1000.00 | 47200021 D 210.00 | 47510005 H 190.00 | 41000002 H 1020.00', public.asiento(f);
  raise notice 'OK  · alquiler de local: IRPF 19 %% a la 4751 del modelo 115';

  -- ---------- Retención en facturas emitidas ----------
  f := public.factura(e, 'sale', cli, '2026-03-15', '[{"account_no":"70500001","amount":2000,"tax_code":"VAT21"}]', 'IRPF15');
  assert public.asiento(f) = '70500001 H 2000.00 | 47700021 H 420.00 | 47300001 D 300.00 | 43000001 D 2120.00', public.asiento(f);
  raise notice 'OK  · factura emitida con retención: 473 al Debe (pago a cuenta) y cliente por 2.120';

  -- ---------- Resumen trimestral (modelos 111 / 115) ----------
  select * into r from erp.withholding_summary(e, 2026, 1) where form = '111';
  assert r.recipients = 1 and r.base = 900 and r.amount = 135, 'mod. 111: 1.000 − 100';
  select * into r from erp.withholding_summary(e, 2026, 1) where form = '115';
  assert r.base = 1000 and r.amount = 190;
  select * into r from erp.withholding_summary(e, 2026, 1) where side = 'suffered';
  assert r.amount = 300 and r.form is null;
  raise notice 'OK  · resumen 1T: mod. 111 base 900 / retención 135 · mod. 115 base 1.000 / 190 · soportadas 300';

  -- ---------- Operaciones sin cuota ----------
  f := public.factura(e, 'sale', cli_can, '2026-03-20', '[{"account_no":"70000001","amount":5000,"tax_code":"VAT_EXP"}]');
  assert public.asiento(f) = '70000001 H 5000.00 | 43000002 D 5000.00', public.asiento(f);
  assert (select exemption_key from erp.v_invoice_register where invoice_id = f) = 'E2';
  f := public.factura(e, 'sale', cli_ue, '2026-03-21', '[{"account_no":"70000001","amount":3000,"tax_code":"VAT_EU"}]');
  assert (select exemption_key || ' ' || tax_base from erp.v_invoice_register where invoice_id = f) = 'E5 3000.00';
  perform public.factura(e, 'sale', cli_can, '2026-03-22', '[{"account_no":"70500001","amount":800,"tax_code":"VAT_NS"}]');
  perform public.factura(e, 'sale', cli, '2026-03-23', '[{"account_no":"70500001","amount":400,"tax_code":"VAT_E20"}]');
  raise notice 'OK  · exportación a Canarias (E2), entrega intracomunitaria (E5), no sujeta (N2) y exenta art. 20 (E1)';

  c := erp.tax_settlement_calc(e, 'VAT', 2026, 1);
  assert (c->>'difference')::numeric = 0, 'el libro registro cuadra con 472/477';
  assert c->'boxes' @> '[{"tax_code":"VAT_EXP","tax_base":5000},{"tax_code":"VAT_EU","tax_base":3000}]', 'casillas sin cuota';
  raise notice 'OK  · el borrador del 303 recoge las bases sin cuota y cuadra con la contabilidad';
end $$;

-- ---------- Reglas de cada causa ----------
do $$
declare
  e uuid := (select valor from public.ctx where clave = 'peninsula');
  cli uuid := (select valor from public.ctx where clave = 'cli');
  cli_can uuid := (select valor from public.ctx where clave = 'cli_can');
  cli_ue uuid := (select valor from public.ctx where clave = 'cli_ue');
  abogado uuid := (select valor from public.ctx where clave = 'abogado');
begin
  assert public.falla(format($q$select public.factura(%L, 'sale', %L, '2026-03-25', '[{"account_no":"70000001","amount":10,"tax_code":"VAT_EXP"}]')$q$, e, cli),
    'outside the company tax territory'), 'exportación a un cliente de la Península';
  assert public.falla(format($q$select public.factura(%L, 'sale', %L, '2026-03-25', '[{"account_no":"70000001","amount":10,"tax_code":"VAT_EXP"}]')$q$, e, cli_ue),
    'intra-EU supply, not an export'), 'venta a la UE como exportación';
  assert public.falla(format($q$select public.factura(%L, 'sale', %L, '2026-03-25', '[{"account_no":"70000001","amount":10,"tax_code":"VAT_EU"}]')$q$, e, cli_can),
    'customer from another EU country'), 'intracomunitaria a Canarias';
  assert public.falla(format($q$select public.factura(%L, 'purchase', %L, '2026-03-25', '[{"account_no":"62300001","amount":10,"tax_code":"VAT_EXP"}]')$q$, e, abogado),
    'only for issued invoices'), 'exportación en una compra';
  assert public.falla(format($q$select public.factura(%L, 'sale', %L, '2026-03-25', '[{"account_no":"70500001","amount":10,"tax_code":"VAT21"}]', 'IRPF99')$q$, e, cli),
    'Unknown withholding'), 'retención inexistente';
  raise notice 'OK  · reglas: exportación y no sujeta fuera del territorio, intracomunitaria solo UE, solo en ventas, retención válida';
end $$;

-- ---------- Empresa canaria (IGIC) ----------
do $$
declare e uuid; pen uuid; can uuid; ue uuid; f uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Exportadora Canaria SL', 'retail', 'canary_islands', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, '70000001', 'Ventas de mercaderías');
  select partner_id into pen from erp.create_partner(e, 'customer', 'Cliente Sevilla SL', 'B11111119', 'mainland');
  select partner_id into can from erp.create_partner(e, 'customer', 'Cliente Las Palmas SL', 'B22222228');
  select partner_id into ue  from erp.create_partner(e, 'customer', 'Kunde Berlin GmbH', 'DE123456789', 'eu');
  f := public.factura(e, 'sale', pen, '2026-04-10', '[{"account_no":"70000001","amount":1500,"tax_code":"IGIC_EXP"}]');
  assert public.asiento(f) = '70000001 H 1500.00 | 43000001 D 1500.00';
  perform public.factura(e, 'sale', ue, '2026-04-11', '[{"account_no":"70000001","amount":700,"tax_code":"IGIC_EXP"}]');
  assert public.falla(format($q$select public.factura(%L, 'sale', %L, '2026-04-12', '[{"account_no":"70000001","amount":10,"tax_code":"IGIC_EXP"}]')$q$, e, can),
    'outside the company tax territory');
  assert (select count(*) from erp.v_withholding_setup where company_id = e) = 3, 'IRPF también en Canarias';
  raise notice 'OK  · Canarias: envío a la Península y a la UE = exportación exenta de IGIC; a otro canario, no';
end $$;

reset role;
drop function public.asiento(uuid);
drop function public.factura(uuid, text, uuid, date, jsonb, text, text, uuid);
drop function public.falla(text, text);
drop table public.ctx;
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 13 (RETENCIONES Y OPERACIONES SIN CUOTA) PASARON ==========='
