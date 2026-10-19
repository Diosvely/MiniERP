-- =====================================================================
-- PRUEBAS FASE 48 · Modelos: integración y base documental (migración 0053)
-- ---------------------------------------------------------------------
--  Distribuciones Ebro SL (IVA, modo guiado), 2026:
--   1T: venta 1.000 al 21 % (210) y compra 400 al 21 % (84) → 303: 46 = 126; liquidación 126 → «Modelos frente a las
--       liquidaciones» en verde.
--   2T: venta 1.000 al 21 % (210) y un asiento manual de 50 en la 477 → la liquidación (contabilidad) da 260 y el 303
--       (libro registro) 210; liquidado aceptando la diferencia → aviso: 1 trimestre, diferencia 50.
--   347: un cliente sin NIF con 4.000 al 21 % (4.840) → «Terceros del 347 sin NIF», 1 caso.
--   Base documental: 10 fuentes; una sin revisar desde 2024 → «Fuentes sin revisar», 1 caso (informativa).
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.factura(e uuid, tipo text, tercero uuid, fecha date, lineas jsonb)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object(
    'company_id', e, 'invoice_type', tipo, 'partner_id', tercero,
    'external_document_no', case tipo when 'purchase' then 'P-' || substr(md5(random()::text), 1, 8) end,
    'invoice_date', fecha, 'description', 'Prueba', 'lines', lineas));
$$;
grant execute on function public.factura(uuid, text, uuid, date, jsonb) to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; cli uuid; sn uuid; prov uuid; w uuid; r record;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Distribuciones Ebro SL', 'retail', 'mainland', auth.uid()) returning id into e;
  insert into public.ctx values ('e', e);
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.set_control_mode(e, 'guided');
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('60000001', 'Compras de mercaderías'), ('70000001', 'Ventas de mercaderías'), ('57200001', 'Banco')) as s(no, name);
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
  select partner_id into sn   from erp.create_partner(e, 'customer', 'Cliente sin NIF');
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Proveedor Uno SL', 'B12345674');

  -- ---------- 1. Modelos frente a las liquidaciones ----------
  perform public.factura(e, 'sale', cli, '2026-02-10', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"}]');
  perform public.factura(e, 'purchase', prov, '2026-02-11', '[{"account_no":"60000001","amount":400,"tax_code":"VAT21"}]');
  perform erp.post_tax_settlement(e, 'VAT', 2026, 1);
  select * into r from erp.run_audit_checks(e, 2026, '2026-03-31') where code = 'tax_forms_settlements';
  assert r.status = 'ok' and r.book = 126 and r.ledger = 126 and r.screen = 'forms', r::text;
  raise notice 'OK  · 1T: el 303 (126) coincide con la liquidación';

  perform public.factura(e, 'sale', cli, '2026-05-10', '[{"account_no":"70000001","amount":1000,"tax_code":"VAT21"}]');
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-05-20', 'IVA a mano') returning id into w;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (w, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), 50, 0),
    (w, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '47700021'), 0, 50);
  perform erp.post_entry(w);
  assert (select amount from erp.tax_form_boxes(e, 2026, 2) where box = '46') = 210, 'el 303 sale del libro registro';
  perform erp.post_tax_settlement(e, 'VAT', 2026, 2, false, true);
  select * into r from erp.run_audit_checks(e, 2026, '2026-06-30') where code = 'tax_forms_settlements';
  assert r.status = 'warning' and r.items = 1 and r.book = 336 and r.ledger = 386 and r.difference = 50
     and r.details->0->>'quarter' = '2' and (r.details->0->>'form_result')::numeric = 210 and (r.details->0->>'settled')::numeric = 260, r::text;
  assert (select status from erp.run_audit_checks(e, 2026, '2026-03-31') where code = 'tax_forms_settlements') = 'ok', 'al 31/03, solo el 1T';
  raise notice 'OK  · 2T liquidado aceptando 50 de diferencia (asiento manual en la 477): aviso con el trimestre, 210 frente a 260';

  -- ---------- 2. 347 sin NIF ----------
  assert (select status from erp.run_audit_checks(e, 2026) where code = 'form347_missing_vat') = 'ok';
  perform public.factura(e, 'sale', sn, '2026-07-10', '[{"account_no":"70000001","amount":4000,"tax_code":"VAT21"}]');
  select * into r from erp.run_audit_checks(e, 2026) where code = 'form347_missing_vat';
  assert r.status = 'warning' and r.items = 1 and r.details->0->>'partner_name' = 'Cliente sin NIF' and (r.details->0->>'amount')::numeric = 4840, r::text;
  raise notice 'OK  · 347: el cliente sin NIF (4.840) se avisa';

  -- ---------- 3. Base documental ----------
  assert (select count(*) from erp.sources) = 10, 'diez fuentes';
  assert not exists (select 1 from erp.audit_checks c, unnest(c.sources) k where not exists (select 1 from erp.sources s where s.key = k)),
         'las comprobaciones citan fuentes que existen';
  assert (select sources from erp.audit_checks where code = 'tax_forms_settlements') = '{aeat303,atc420}';
  assert (select status from erp.run_audit_checks(e, 2026) where code = 'sources_review') = 'ok', 'todas comprobadas este año';
  assert (select count(*) from erp.concepts where key in ('taxForm', 'thirdPartyReturn')) = 2;
  raise notice 'OK  · base documental: 10 fuentes, citadas por las comprobaciones; glosario «Modelo tributario» y «Modelo 347»';
end $$;

-- una fuente sin revisar desde 2024 (como superusuario: la web no puede escribir en erp.sources)
reset role;
update erp.sources set checked = '2024-01-15' where key = 'riva';
set role authenticated;
do $$
declare r record;
begin
  select * into r from erp.run_audit_checks((select v from public.ctx where k = 'e'), 2026) where code = 'sources_review';
  assert r.status = 'info' and r.items = 1 and r.details->0->>'key' = 'riva', r::text;
  raise notice 'OK  · una fuente sin revisar en más de un año sale como informativa';
end $$;
do $$
begin
  begin
    update erp.sources set checked = current_date where key = 'riva';
    raise exception 'debería fallar';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK  · los usuarios no cambian la base documental';
end $$;

\echo '✔ FASE 48 OK · modelos: integración y base documental'
