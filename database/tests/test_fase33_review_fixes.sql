-- =====================================================================
-- PRUEBAS FASE 33 · Arreglos de la revisión externa (migración 0039) · pruebas de regresión
--   1) Una 477 sin configurar ya no se salta el cuadre ni la liquidación del 303
--   2) Cuota que no corresponde a base × tipo: comprobación «tax_quota»
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
-- Asiento manual contabilizado: [[cuenta, debe, haber, base], …]
create or replace function public.manual(e uuid, d date, l jsonb) returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, 'Manual')
  returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, tax_base)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0),
         (x.v->>1)::numeric, (x.v->>2)::numeric, (x.v->>3)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  execute 'set constraints all immediate';   -- la regla del modo estricto es diferida (0036): se comprueba ya
  execute 'set constraints all deferred';
  return a;
end $$;
create or replace function public.chk(e uuid, c text) returns text language sql as $$
  select r.status || ' · ' || r.items from erp.run_audit_checks(e, 2026) r where r.code = c;
$$;
grant execute on function public.falla(text, text), public.manual(uuid, date, jsonb), public.chk(uuid, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; cli uuid; m uuid; c jsonb; r record;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Revisión SL', 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('70500001', 'Prestaciones de servicios'), ('57200001', 'Banco'), ('62900001', 'Otros servicios'),
    ('47700001', 'IVA repercutido (sin configurar)')) as s(no, name);
  assert not exists (select 1 from erp.v_tax_setup where company_id = e and '47700001' in (input_account_no, output_account_no)),
         'la 47700001 no está configurada';
  select partner_id into cli from erp.create_partner(e, 'customer', 'Cliente Madrid SL', 'B11111119');
  perform erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'sale', 'document_kind', 'invoice',
    'partner_id', cli, 'invoice_date', '2026-02-10', 'description', 'Servicios',
    'lines', '[{"account_no":"70500001","amount":1000,"tax_code":"VAT21"}]'::jsonb));

  -- ---------- 1. Una 477 sin configurar entra en la liquidación ----------
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 1);
  assert (c->>'output_tax')::numeric = 210 and (c->>'difference')::numeric = 0, 'sin el apunte, cuadra: ' || c::text;
  perform public.manual(e, '2026-03-01', '[["57200001",500,0],["47700001",0,500]]');
  c := erp.tax_settlement_calc(e, 'VAT', 2026, 1);
  assert (c->>'output_tax')::numeric = 710, 'la 47700001 cuenta en el repercutido: ' || (c->>'output_tax');
  assert (c->>'register_output')::numeric = 210, 'el libro registro sigue en 210';
  assert (c->>'difference')::numeric = 500, 'el cuadre detecta los 500: ' || (c->>'difference');
  assert exists (select 1 from jsonb_array_elements(c->'lines') x where x->>'account_no' = '47700001' and (x->>'debit')::numeric = 500),
         'y la liquidación la salda: ' || (c->'lines')::text;
  assert public.falla(format('select * from erp.post_tax_settlement(%L, %L, 2026, 1)', e, 'VAT'), 'differ by'),
         'no se liquida con la diferencia sin aceptarla';
  raise notice 'OK  · 47700001 sin configurar: entra en el 303 (710 frente a 210 del libro) y bloquea la liquidación';

  -- …y en Canarias (IGIC), la misma cuenta no se mezcla en el IVA
  -- (las 472/477 sin configurar solo cuentan en el impuesto del territorio)
  assert public.falla(format('select erp.tax_settlement_calc(%L, %L, 2026, 1)', e, 'IGIC'), 'not set up'),
         'una empresa de la Península no liquida IGIC';
  raise notice 'OK  · las 472/477 sin configurar cuentan solo en el impuesto de su territorio';

  -- ---------- 2. Cuota que no corresponde a base × tipo ----------
  assert public.chk(e, 'tax_quota') = 'ok · 0', public.chk(e, 'tax_quota');
  m := public.manual(e, '2026-04-01', '[["62900001",100,0,null],["47200021",500,0,100],["57200001",0,600,null]]');
  assert public.chk(e, 'tax_quota') = 'warning · 1', 'base 100 al 21 % con cuota 500: ' || public.chk(e, 'tax_quota');
  select * into r from erp.run_audit_checks(e, 2026) x where x.code = 'tax_quota';
  assert (r.details->0->>'entry_id')::uuid = m and (r.details->0->>'expected')::numeric = 21
         and (r.details->0->>'amount')::numeric = 500 and r.details->0->>'tax_code' = 'VAT21', r.details::text;
  -- una cuota bien calculada (con redondeo) no sale
  perform public.manual(e, '2026-04-02', '[["62900001",33.33,0,null],["47200021",7,0,33.33],["57200001",0,40.33,null]]');
  assert public.chk(e, 'tax_quota') = 'warning · 1', 'la cuota correcta (33,33 × 21 % = 7,00) no sale';
  -- anulada, desaparece
  perform erp.reverse_entry(m, '2026-04-03', 'Cuota mal calculada');
  assert public.chk(e, 'tax_quota') = 'ok · 0', 'anulada: ' || public.chk(e, 'tax_quota');
  -- las facturas no cuentan (su cuota la calcula el ERP; con prorrata puede ser solo una parte)
  assert (select count(*) from erp.run_audit_checks(e, 2026) x where x.code = 'tax_quota' and x.items > 0) = 0;
  raise notice 'OK  · cuota 500 sobre base 100 al 21 %%: señalada (debería ser 21); la correcta y la anulada, no';

  -- ---------- 3. En modo estricto ni siquiera se contabiliza ----------
  perform erp.set_control_mode(e, 'strict');
  assert public.falla(format('select public.manual(%L, %L, %L)', e, '2026-05-01',
           '[["62900001",100,0,null],["47200021",500,0,100],["57200001",0,600,null]]'), 'controlled by'), 'estricto: no';
  raise notice 'OK  · en modo estricto ese asiento no se contabiliza';
end $$;

\echo '✔ FASE 33 OK · arreglos de la revisión externa'
