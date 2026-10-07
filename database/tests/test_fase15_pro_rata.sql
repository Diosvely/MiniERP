-- =====================================================================
-- PRUEBAS FASE 15 · Prorrata general (migración 0020)
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

do $$
declare e uuid; prov uuid; obra uuid; cli uuid; f uuid; c jsonb; r jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Academia Lola SL', 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('60000001', 'Compras de libros'), ('62200001', 'Reparaciones'),
    ('70000001', 'Venta de libros'), ('70500001', 'Clases')) as s(no, name);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Editorial Sur SL', 'B12345674');
  select partner_id into obra from erp.create_partner(e, 'creditor', 'Reformas Pérez SL', 'A33333337');
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Alumnos varios', 'B11111119');

  -- Prorrata provisional del 80 % (la definitiva del año anterior)
  perform erp.set_pro_rata(e, 'VAT', 2026, 80);

  f := public.factura(e, 'purchase', prov, '2026-02-01', '[{"account_no":"60000001","amount":1000,"tax_code":"VAT21"}]');
  assert public.asiento(f) = '60000001 D 1000.00 | 47200021 D 168.00 | 60000001 D 42.00 | 40000001 H 1210.00', public.asiento(f);
  assert (select deductible_amount from erp.v_invoice_register where invoice_id = f) = 168;
  raise notice 'OK  · compra con prorrata 80 %%: 472 D 168 (deducible) y 600 D 42 (más coste)';

  f := public.factura(e, 'purchase', obra, '2026-02-10', '[{"account_no":"62200001","amount":1000,"tax_code":"VAT21_ISP"}]');
  assert public.asiento(f) = '62200001 D 1000.00 | 47209021 D 168.00 | 62200001 D 42.00 | 47709021 H 210.00 | 41000001 H 1000.00', public.asiento(f);
  raise notice 'OK  · ISP con prorrata: 472 D 168 · 622 D 42 · 477 H 210 (se devenga entera, se deduce el 80 %%)';

  -- Ventas: con derecho (libros) y exentas sin derecho (clases, art. 20)
  perform public.factura(e, 'sale', cli, '2026-03-01', '[{"account_no":"70000001","amount":6001,"tax_code":"VAT21"}]');
  perform public.factura(e, 'sale', cli, '2026-03-02', '[{"account_no":"70500001","amount":4000,"tax_code":"VAT_E20"}]');

  c := erp.tax_settlement_calc(e, 'VAT', 2026, 1);
  assert (c->>'difference')::numeric = 0, format('el 303 cuadra con la prorrata: %s', c->>'difference');
  assert (c->>'input_tax')::numeric = 336, 'deducible: 168 + 168';
  raise notice 'OK  · 303 del 1T: deducible 336 (el 80 %%) y cuadra con la contabilidad';

  -- Regularización: 6.001 / 10.001 = 60,004 % → 61 % (unidad superior)
  r := erp.pro_rata_calc(e, 'VAT', 2026);
  assert (r->>'definitive_pct')::numeric = 61, 'redondeo a la unidad superior';
  assert (r->>'input_tax')::numeric = 420 and (r->>'deducted')::numeric = 336;
  assert (r->>'should_deduct')::numeric = 256.20 and (r->>'adjustment')::numeric = -79.80;
  assert r->'lines' = '[{"debit": 79.80, "credit": 0, "account_no": "63410001"}, {"debit": 0, "credit": 79.80, "account_no": "47200021"}]'::jsonb, r->>'lines';
  raise notice 'OK  · definitiva 61 %% (60,004 redondeado arriba) · debía deducir 256,20 · deducido 336 · ajuste −79,80';

  r := erp.post_pro_rata_regularization(e, 'VAT', 2026);
  assert (select provisional_pct from erp.pro_rata where company_id = e and year = 2027) = 61, 'la definitiva es la provisional de 2027';
  assert public.falla(format('select erp.set_pro_rata(%L, %L, 2026, 50)', e, 'VAT'), 'already regularized');
  assert public.falla(format('select erp.reverse_entry((select entry_id from erp.pro_rata where company_id = %L and year = 2026))', e),
    'pro rata regularization'), 'no se anula desde el diario';
  raise notice 'OK  · regularización 6341 D 79,80 / 472 H 79,80 a 31/12; 2027 empieza con 61 %%';

  c := erp.tax_settlement_calc(e, 'VAT', 2026, 4);
  assert (c->>'difference')::numeric = 0, format('el 4T cuadra con la regularización: %s', c->>'difference');
  assert (c->>'input_tax')::numeric = -79.80;
  assert c->'boxes' @> '[{"side":"input","kind":"pro_rata","tax_amount":-79.80}]';
  raise notice 'OK  · 303 del 4T: casilla de regularización de la prorrata −79,80 y cuadra';

  -- Deshacer y volver a regularizar; con el 4T liquidado, ya no
  perform erp.cancel_pro_rata_regularization(e, 'VAT', 2026);
  assert (select regularized_at from erp.pro_rata where company_id = e and year = 2026) is null;
  perform erp.post_pro_rata_regularization(e, 'VAT', 2026);
  perform erp.post_tax_settlement(e, 'VAT', 2026, 1);
  perform erp.post_tax_settlement(e, 'VAT', 2026, 2);
  perform erp.post_tax_settlement(e, 'VAT', 2026, 3);
  perform erp.post_tax_settlement(e, 'VAT', 2026, 4);
  assert public.falla(format('select erp.cancel_pro_rata_regularization(%L, %L, 2026)', e, 'VAT'), 'already settled');
  raise notice 'OK  · deshacer y repetir funciona; con el 4T liquidado ya no se puede tocar';
end $$;

reset role;
drop function public.asiento(uuid);
drop function public.factura(uuid, text, uuid, date, jsonb);
drop function public.falla(text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 15 (PRORRATA) PASARON ==========='
