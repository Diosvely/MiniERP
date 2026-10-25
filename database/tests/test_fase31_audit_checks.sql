-- =====================================================================
-- PRUEBAS FASE 31 · Comprobaciones del auditor (migración 0037)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local'),
  ('00000000-0000-0000-0000-0000000000c3', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb, retencion text default null)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object(
    'company_id', e, 'invoice_type', tipo, 'document_kind', 'invoice', 'partner_id', tercero,
    'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Prueba', 'withholding_code', retencion, 'lines', lineas));
$$;
-- Asiento manual contabilizado: [[cuenta, debe, haber], …]
create or replace function public.manual(e uuid, d date, l jsonb) returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, 'Manual')
  returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  return a;
end $$;
-- Una comprobación: estado · libro · contabilidad · casos
create or replace function public.chk(e uuid, c text, d date default null) returns text language sql as $$
  select r.status || ' · ' || coalesce(r.book::text, '-') || ' · ' || coalesce(r.ledger::text, '-') || ' · ' || r.items
  from erp.run_audit_checks(e, 2026, d) r where r.code = c;
$$;
grant execute on function public.factura(uuid, text, uuid, date, jsonb, text), public.manual(uuid, date, jsonb),
  public.chk(uuid, text, date) to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; abogada uuid; cli uuid; f1 uuid; fv uuid; m uuid; pm uuid; r record;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Auditoría Madrid SL', 'services', 'mainland', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('62300001', 'Servicios profesionales'), ('70500001', 'Prestaciones de servicios'), ('57200001', 'Banco'),
    ('10000001', 'Capital'), ('64000001', 'Sueldos'), ('62900001', 'Otros servicios'),
    ('28100001', 'Amortización acumulada')) as s(no, name);
  select partner_id into abogada from erp.create_partner(e, 'creditor', 'Abogada Ruiz', '12345678Z');
  select partner_id into cli     from erp.create_partner(e, 'customer', 'Cliente Madrid SL', 'B11111119');

  -- ---------- 1. Catálogo y empresa vacía: todo en verde ----------
  -- (la 0039 añade «tax_quota», la 0042 las dos del inmovilizado la 0044 las tres de los ajustes de cierre y la 0048 tres más: 16)
  assert (select count(*) from erp.audit_checks) = 22, 'veintidós comprobaciones (v0.43.0: financing_ledger; v0.44.0: grants_ledger)';
  assert (select count(*) from erp.run_audit_checks(e, 2026) where status <> 'ok') = 0, 'empresa vacía: todo ok';
  assert (select string_agg(code, ',' order by sort) from erp.run_audit_checks(e, 2026))
         = 'vat_input,vat_output,tax_forms_settlements,tax_quota,withholdings,partners,form347_missing_vat,anomalies,assets_ledger,assets_pending,adjustments_ledger,accruals_unreversed,impairments_collected,provisions_ledger,provisions_review,inventory_ledger,payroll_ledger,financing_ledger,tax_territory,grants_ledger,controlled,sources_review';
  perform public.manual(e, '2026-01-02', '[["57200001",10000,0],["10000001",0,10000]]');
  raise notice 'OK  · diez comprobaciones; empresa vacía, todo ok';

  -- ---------- 2. Con facturas, todo cuadra ----------
  f1 := public.factura(e, 'purchase', abogada, '2026-02-10', '[{"account_no":"62300001","amount":1000,"tax_code":"VAT21"}]', 'IRPF15');
  fv := public.factura(e, 'sale', cli, '2026-02-15', '[{"account_no":"70500001","amount":2000,"tax_code":"VAT21"}]');
  assert public.chk(e, 'vat_input')    = 'ok · 210.00 · 210.00 · 0', public.chk(e, 'vat_input');
  assert public.chk(e, 'vat_output')   = 'ok · 420.00 · 420.00 · 0', public.chk(e, 'vat_output');
  assert public.chk(e, 'withholdings') = 'ok · 150.00 · 150.00 · 0', public.chk(e, 'withholdings');
  assert public.chk(e, 'partners')     = 'ok · 0 · 0 · 0', public.chk(e, 'partners');
  assert (select count(*) from erp.run_audit_checks(e, 2026) where status <> 'ok') = 0, 'con facturas, todo ok';
  raise notice 'OK  · facturas: 472 = 210, 477 = 420 y 4751 = 150 cuadran con los libros';

  -- ---------- 3. IVA a mano: descuadra la 472 y sale en "controladas" ----------
  m := public.manual(e, '2026-03-01', '[["62900001",100,0],["47200021",21,0],["57200001",0,121]]');
  assert public.chk(e, 'vat_input') = 'warning · 210.00 · 231.00 · 1', public.chk(e, 'vat_input');
  select * into r from erp.run_audit_checks(e, 2026) x where x.code = 'vat_input';
  assert r.difference = 21 and (r.details->0->>'entry_id')::uuid = m and r.details->0->>'source' = 'manual'
         and (r.details->0->>'amount')::numeric = 21 and r.screen = 'journal', r.details::text;
  assert public.chk(e, 'controlled') = 'warning · - · - · 1', public.chk(e, 'controlled');
  assert public.chk(e, 'vat_input', '2026-02-28') = 'ok · 210.00 · 210.00 · 0', 'a una fecha anterior, cuadra';
  raise notice 'OK  · 472 a mano: libro 210, contabilidad 231, diferencia 21 (y el asiento, enlazado)';

  -- …el contraasiento lo arregla
  perform erp.reverse_entry(m, '2026-03-02', 'IVA sin factura');
  assert public.chk(e, 'vat_input') = 'ok · 210.00 · 210.00 · 0', public.chk(e, 'vat_input');
  assert public.chk(e, 'controlled') = 'ok · - · - · 0', public.chk(e, 'controlled');
  raise notice 'OK  · el contraasiento lo deja cuadrado (el par suma cero y no sale en el detalle)';

  -- ---------- 4. La liquidación cancela la 472 / 477 y no descuadra ----------
  perform erp.post_tax_settlement(e, 'VAT', 2026, 1);
  assert public.chk(e, 'vat_input')  = 'ok · 210.00 · 210.00 · 0', 'tras liquidar: ' || public.chk(e, 'vat_input');
  assert public.chk(e, 'vat_output') = 'ok · 420.00 · 420.00 · 0', 'tras liquidar: ' || public.chk(e, 'vat_output');
  raise notice 'OK  · la liquidación del 1T no descuadra (se excluye a propósito)';

  -- ---------- 5. Pago a mano sin vincular: el tercero no cuadra con sus facturas ----------
  pm := public.manual(e, '2026-04-10', '[["41000001",500,0],["57200001",0,500]]');
  assert public.chk(e, 'partners') = 'warning · 1060.00 · 560.00 · 1', public.chk(e, 'partners');
  select * into r from erp.run_audit_checks(e, 2026) x where x.code = 'partners';
  assert r.details->0->>'partner_name' = 'Abogada Ruiz' and (r.details->0->>'amount')::numeric = -500
         and r.details->0->>'invoice_type' = 'purchase' and r.screen = 'payments', r.details::text;
  assert public.chk(e, 'controlled') = 'warning · - · - · 1', 'el pago manual toca la 410';
  -- …vincularlo lo arregla en las dos
  perform erp.link_payment(jsonb_build_object('company_id', e, 'entry_id', pm, 'partner_id', abogada,
            'applications', jsonb_build_array(jsonb_build_object('invoice_id', f1, 'amount', 500))));
  assert public.chk(e, 'partners') = 'ok · 0 · 0 · 0', public.chk(e, 'partners');
  assert public.chk(e, 'controlled') = 'ok · - · - · 0', 'vinculado ya no cuenta';
  raise notice 'OK  · pago manual: la 410 dice 560 y las facturas 1.060; vincularlo lo cuadra';

  -- ---------- 6. Retenciones de nómina a mano (info) y el ingreso en Hacienda (no cuenta) ----------
  perform public.manual(e, '2026-04-30', '[["64000001",1000,0],["47510001",0,150],["57200001",0,850]]');
  assert public.chk(e, 'withholdings') = 'info · 150.00 · 300.00 · 1', public.chk(e, 'withholdings');
  perform public.manual(e, '2026-05-20', '[["47510001",300,0],["57200001",0,300]]');
  assert public.chk(e, 'withholdings') = 'info · 150.00 · 300.00 · 1', 'el ingreso del 111 no cuenta: ' || public.chk(e, 'withholdings');
  raise notice 'OK  · 4751: la nómina a mano sale como info (300 frente a 150); pagar a Hacienda no cuenta';

  -- ---------- 7. Saldos al revés: aviso, y error si es imposible ----------
  perform public.manual(e, '2026-06-01', '[["62900001",20000,0],["57200001",0,20000]]');
  assert public.chk(e, 'anomalies') = 'warning · - · - · 1', public.chk(e, 'anomalies');
  select * into r from erp.run_audit_checks(e, 2026) x where x.code = 'anomalies';
  assert r.details->0->>'account_no' = '57200001' and r.details->0->>'reclass_to' = '5201', r.details::text;
  perform public.manual(e, '2026-06-02', '[["28100001",50,0],["10000001",0,50]]');
  assert public.chk(e, 'anomalies') = 'error · - · - · 2', 'amortización deudora: ' || public.chk(e, 'anomalies');
  raise notice 'OK  · banco acreedor = aviso (→ 5201); amortización deudora = error';

  -- ---------- 8. IGIC en una empresa de la Península ----------
  perform erp.setup_taxes(e, 'IGIC');
  perform public.factura(e, 'purchase', abogada, '2026-07-01', '[{"account_no":"62300001","amount":100,"tax_code":"IGIC7"}]');
  assert public.chk(e, 'tax_territory') = 'warning · - · - · 1', public.chk(e, 'tax_territory');
  select * into r from erp.run_audit_checks(e, 2026) x where x.code = 'tax_territory';
  assert r.details->0->>'tax_code' = 'IGIC7' and r.details->0->>'source' = 'invoice', r.details::text;
  assert public.chk(e, 'vat_input') like 'ok %', 'la factura con IGIC sí está en el libro';
  raise notice 'OK  · factura con IGIC en Madrid: señalada';
end $$;

-- ---------- 9. Seguridad: el lector las ve; quien no es de la empresa, no ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa');
begin
  assert (select count(*) from erp.run_audit_checks(e, 2026)) = 22, 'el lector las ve';
  assert public.chk(e, 'partners') = 'ok · 0 · 0 · 0', public.chk(e, 'partners');
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa');
begin
  assert (select count(*) from erp.run_audit_checks(e, 2026)) = 0, 'otro usuario: nada';
  raise notice 'OK  · el lector ve las comprobaciones; un usuario ajeno no ve nada';
end $$;

\echo '✔ FASE 31 OK · comprobaciones del auditor'
