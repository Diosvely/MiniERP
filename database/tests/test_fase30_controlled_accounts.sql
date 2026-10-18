-- =====================================================================
-- PRUEBAS FASE 30 · Cuentas controladas: modo estricto (SAP / BC) o guiado (ERP españoles) · migración 0036
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'contable@test.local');
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
-- Asiento manual en borrador: [[cuenta, debe, haber], …]
create or replace function public.borrador(e uuid, d date, l jsonb, tipo text default 'normal') returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, entry_type)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, 'Manual', tipo)
  returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  return a;
end $$;
-- Contabiliza y comprueba en el acto la regla diferida (en la web se comprueba al final de la llamada)
create or replace function public.contabiliza(a uuid) returns int language plpgsql as $$
declare n int;
begin
  n := erp.post_entry(a);
  execute 'set constraints all immediate';
  execute 'set constraints all deferred';
  return n;
end $$;
create or replace function public.comprueba() returns void language plpgsql as $$
begin
  execute 'set constraints all immediate';
  execute 'set constraints all deferred';
end $$;
create or replace function public.factura(e uuid, tercero uuid, fecha date, lineas jsonb) returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'document_kind', 'invoice',
    'partner_id', tercero, 'external_document_no', 'P-' || substr(md5(random()::text), 1, 8), 'invoice_date', fecha,
    'description', 'Prueba', 'lines', lineas));
$$;
grant execute on function public.falla(text, text), public.borrador(uuid, date, jsonb, text), public.contabiliza(uuid),
  public.comprueba(), public.factura(uuid, uuid, date, jsonb) to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; prov uuid; a uuid; f uuid; p uuid; antes uuid; c jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Controladas SL', 'services', 'mainland', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'accountant');
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('62300001', 'Servicios profesionales'), ('57200001', 'Banco'), ('40090001', 'Facturas pendientes de recibir'),
    ('62900001', 'Otros servicios'), ('10000001', 'Capital')) as s(no, name);
  select partner_id into prov from erp.create_partner(e, 'creditor', 'Asesoría Gómez SL', 'B12345674');
  insert into public.ctx values ('prov', prov);

  -- ---------- 1. Las reglas son datos; gana el prefijo más largo ----------
  assert (erp.control_rule_for('41000001')).modules = '{invoices,payments}';
  assert (erp.control_rule_for('40090001')).modules = '{accruals}', '4009: Periodificaciones (v0.36.0), gana a la 400';
  assert (erp.control_rule_for('57200001')).account_prefix is null, 'el banco no está controlado';
  c := erp.controlled_lines('[{"account_no":"62300001","debit":100,"credit":0},{"account_no":"41000001","debit":0,"credit":100},
                               {"account_no":"47500001","debit":50,"credit":0},{"account_no":"47500001","debit":0,"credit":50}]');
  assert jsonb_array_length(c) = 2 and c->0->>'account_no' = '41000001' and (c->1->>'line')::int = 4,
         '410 por cualquier lado; 4750 solo por el Haber: ' || c::text;
  raise notice 'OK  · reglas por prefijo (la 4009 gana a la 400, 4750 solo al Haber, el banco libre)';

  -- ---------- 2. Modo guiado (por defecto): el asiento manual se contabiliza ----------
  assert (select control_mode from erp.v_my_companies where id = e) = 'guided', 'por defecto, guiado';
  antes := public.borrador(e, '2026-01-15', '[["62300001",100,0],["41000001",0,100]]');
  perform public.contabiliza(antes);
  insert into public.ctx values ('antes', antes);
  raise notice 'OK  · guiado: el asiento manual 623 a 410 se contabiliza (estilo ERP español)';

  -- ---------- 3. Modo estricto ----------
  perform erp.set_control_mode(e, 'strict');
  assert (select control_mode from erp.v_my_companies where id = e) = 'strict';
  a := public.borrador(e, '2026-02-01', '[["62300001",200,0],["41000001",0,200]]');   -- el borrador sí se puede guardar
  assert public.falla(format('select public.contabiliza(%L)', a), 'controlled by invoices, payments'), 'manual a la 410: no';
  assert (select status from erp.journal_entries where id = a) = 'draft', 'sigue en borrador';
  a := public.borrador(e, '2026-02-01', '[["47200021",21,0],["57200001",0,21]]');
  assert public.falla(format('select public.contabiliza(%L)', a), 'controlled by invoices, settlement'), 'manual al IVA: no';
  raise notice 'OK  · estricto: un asiento manual sobre 410 o 472 no se contabiliza (se queda en borrador)';

  -- …pero lo que no está controlado, o el lado libre, sí
  perform public.contabiliza(public.borrador(e, '2026-02-02', '[["62900001",50,0],["57200001",0,50]]'));
  assert public.falla(format('select public.contabiliza(%L)', public.borrador(e, '2026-02-03', '[["62300001",80,0],["40090001",0,80]]')),
         'controlled by accruals'), 'la 4009, desde v0.36.0 solo con Periodificaciones';
  perform public.contabiliza(public.borrador(e, '2026-02-04', '[["47500001",300,0],["57200001",0,300]]'));
  assert public.falla(format('select public.contabiliza(%L)', public.borrador(e, '2026-02-05', '[["57200001",300,0],["47500001",0,300]]')),
         'controlled by settlement'), 'la 4750 al Haber solo la liquidación';
  raise notice 'OK  · estricto: gastos y banco y el pago de la 4750 a Hacienda sí; la 4009, solo desde Periodificaciones';

  -- Los módulos sí mueven las cuentas controladas
  f := public.factura(e, prov, '2026-03-01', '[{"account_no":"62300001","amount":1000,"tax_code":"VAT21"}]');
  perform public.comprueba();
  p := (select payment_id from erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', 'payment', 'partner_id', prov,
         'payment_date', '2026-03-10', 'cash_account_no', '57200001',
         'applications', jsonb_build_array(jsonb_build_object('invoice_id', f, 'amount', 1210)))));
  perform public.comprueba();
  perform erp.cancel_payment(p, '2026-03-11');
  perform public.comprueba();
  raise notice 'OK  · estricto: factura, pago y su anulación funcionan (los genera su módulo)';

  -- Contraasiento de un asiento manual antiguo, y apertura: nunca se bloquean
  perform erp.reverse_entry(antes, '2026-03-15', 'Error');
  perform public.comprueba();
  perform public.contabiliza(public.borrador(e, '2026-01-01', '[["10000001",0,500],["41000001",500,0]]', 'opening'));
  raise notice 'OK  · estricto: contraasientos y apertura no se bloquean';

  -- Vuelta a guiado: el mismo asiento ya se puede contabilizar
  perform erp.set_control_mode(e, 'guided');
  perform public.contabiliza(public.borrador(e, '2026-04-01', '[["62300001",200,0],["41000001",0,200]]'));
  assert jsonb_array_length(erp.entry_controlled_lines((select id from erp.journal_entries where company_id = e and posting_date = '2026-04-01'))) = 1,
         'el asiento queda señalado para Comprobaciones';
  perform erp.set_control_mode(e, 'strict');
  raise notice 'OK  · guiado otra vez: se contabiliza, y queda señalado';
end $$;

-- ---------- 4. Solo el administrador cambia el modo ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa');
begin
  assert public.falla(format('select erp.set_control_mode(%L, %L)', e, 'guided'), 'Only the company admin'), 'un contable no';
  assert (select control_mode from erp.v_my_companies where id = e) = 'strict';
  -- y el contable también está sujeto al modo estricto
  assert public.falla(format('select public.contabiliza(%L)', public.borrador(e, '2026-05-01', '[["62300001",10,0],["41000001",0,10]]')),
         'controlled by');
  raise notice 'OK  · solo el administrador cambia el modo; el contable trabaja con él';
end $$;

-- ---------- 5. Borrar la empresa en modo estricto ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa'); n int;
begin
  loop
    n := erp.delete_company_step(e, 5);
    exit when n = 0;
  end loop;
  perform public.comprueba();
  assert not exists (select 1 from erp.companies where id = e);
  raise notice 'OK  · una empresa en modo estricto se borra entera';
end $$;

\echo '✔ FASE 30 OK · cuentas controladas'
