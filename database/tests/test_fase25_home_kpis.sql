-- =====================================================================
-- PRUEBAS FASE 25 · Indicadores del Inicio (migración 0031)
-- Empresa de Canarias (IGIC 7 %) con facturas, cobro, liquidación del 1T y cierre del ejercicio
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local'),
  ('00000000-0000-0000-0000-0000000000c3', 'ajeno@test.local');

create table public.ctx (clave text primary key, valor uuid);
grant all on public.ctx to authenticated;

-- Factura rápida (IGIC 7 %) y asiento rápido
create or replace function public.factura(e uuid, ty text, p uuid, ext text, d date, acc text, amt numeric)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', ty, 'partner_id', p,
    'external_document_no', ext, 'invoice_date', d,
    'lines', jsonb_build_array(jsonb_build_object('account_no', acc, 'amount', amt, 'tax_code', 'IGIC7'))));
$$;
create or replace function public.asiento(e uuid, d date, l jsonb) returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, 'Movimiento')
  returning id into a;
  insert into erp.journal_lines (entry_id, line_no, gl_account_id, debit, credit)
  select a, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  return a;
end $$;
create or replace function public.k(d date, campo text) returns numeric language sql as $$
  select (erp.home_kpis((select valor from public.ctx where clave = 'empresa'), d) ->> campo)::numeric;
$$;
grant execute on function public.factura(uuid, text, uuid, text, date, text, numeric), public.asiento(uuid, date, jsonb),
  public.k(date, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; prov uuid; cli uuid; cli_acc text; j jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Indicadores SL', 'services', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  perform erp.create_fiscal_year(e, 2025);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('10000001', 'Capital'), ('57200001', 'Banco'), ('60000001', 'Compras'), ('70000001', 'Ventas')) as s(no, name);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Proveedor', 'B12345674');
  select partner_id, account_no into cli, cli_acc from erp.create_partner(e, 'customer', 'Cliente', 'B11111119');

  perform public.asiento(e, '2025-01-02', '[["57200001",10000,0],["10000001",0,10000]]');   -- capital
  perform public.factura(e, 'purchase', prov, 'P-1', '2025-02-10', '60000001', 1000);       -- 600 1.000 + IGIC 70
  perform public.factura(e, 'sale', cli, null, '2025-03-15', '70000001', 3000);              -- 700 3.000 + IGIC 210
  perform public.asiento(e, '2025-03-20', jsonb_build_array(jsonb_build_array('57200001', 3210, 0),
                                                            jsonb_build_array(cli_acc, 0, 3210)));   -- cobro
  perform erp.post_tax_settlement(e, 'IGIC', 2025, 1);                                       -- liquidación 1T a 31/03
  perform public.factura(e, 'sale', cli, null, '2025-05-10', '70000001', 2000);              -- 700 2.000 + IGIC 140

  -- ---------- A 30/06/2025 ----------
  assert public.k('2025-06-30', 'cash') = 13210, 'tesorería: 10.000 + 3.210';
  assert public.k('2025-06-30', 'cash_start') = 0, 'sin asiento de apertura → 0';
  assert public.k('2025-06-30', 'result') = 4000, 'resultado: 3.000 + 2.000 − 1.000';
  assert public.k('2025-06-30', 'quarter') = 2;
  assert public.k('2025-06-30', 'tax_output') = 140 and public.k('2025-06-30', 'tax_input') = 0, 'IGIC del 2T';
  assert public.k('2025-06-30', 'receivable') = 2140 and public.k('2025-06-30', 'receivable_accounts') = 1, 'pendiente de cobro';
  assert public.k('2025-06-30', 'payable') = 1070 and public.k('2025-06-30', 'payable_accounts') = 1, 'pendiente de pago';
  j := erp.home_kpis(e, '2025-06-30') -> 'cash_months';
  assert jsonb_array_length(j) = 6, 'seis meses: enero a junio';
  assert (j->0->>'balance')::numeric = 10000 and (j->1->>'balance')::numeric = 10000 and (j->2->>'balance')::numeric = 13210
     and (j->5->>'balance')::numeric = 13210, 'saldo a fin de mes, los meses sin movimientos repiten: ' || j::text;
  raise notice 'OK  · a 30/06: tesorería 13.210, resultado 4.000, IGIC 2T 140, cobro 2.140, pago 1.070, 6 meses';

  -- ---------- La liquidación del 1T no resta en el trimestre ----------
  assert public.k('2025-03-31', 'tax_output') = 210 and public.k('2025-03-31', 'tax_input') = 70,
    'IGIC del 1T sin el asiento de liquidación: ' || public.k('2025-03-31', 'tax_output') || ' / ' || public.k('2025-03-31', 'tax_input');
  raise notice 'OK  · el asiento de liquidación (4750 / 4700) no cuenta en el IGIC del trimestre';

  -- ---------- La fecha manda: a 15/02 todavía no hay ventas ----------
  assert public.k('2025-02-15', 'result') = -1000 and public.k('2025-02-15', 'cash') = 10000, 'a 15/02';
  assert jsonb_array_length(erp.home_kpis(e, '2025-02-15') -> 'cash_months') = 2, 'enero y febrero';
  raise notice 'OK  · todo se calcula a la fecha de trabajo';

  -- ---------- Fuera de cualquier ejercicio: nada ----------
  assert erp.home_kpis(e, '2030-01-01') is null, 'sin ejercicio → null';
  raise notice 'OK  · fecha sin ejercicio → null';

  -- ---------- Cierre del ejercicio: a 31/12 las cifras NO se ponen a cero ----------
  perform erp.close_fiscal_year(e, 2025, true);
  assert public.k('2025-12-31', 'result') = 4000, 'el resultado ignora la regularización';
  assert public.k('2025-12-31', 'cash') = 13210 and public.k('2025-12-31', 'receivable') = 2140, 'los saldos ignoran el cierre';
  raise notice 'OK  · ejercicio cerrado: a 31/12 se ve el resultado y los saldos, no los ceros del cierre';

  -- ---------- Ejercicio siguiente: apertura y comparación ----------
  assert public.k('2026-01-15', 'cash_start') = 13210 and public.k('2026-01-15', 'cash') = 13210, 'tesorería de la apertura';
  assert public.k('2026-01-15', 'result') = 0 and public.k('2026-01-15', 'result_prev') = 4000, 'resultado y año anterior';
  assert public.k('2026-01-15', 'receivable') = 2140, 'el cliente sigue debiendo';
  raise notice 'OK  · 2026: tesorería inicial 13.210 (apertura) y resultado de 2025 para comparar';
end $$;

-- ---------- Permisos ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$ begin
  assert public.k('2025-06-30', 'cash') = 13210, 'el lector ve los indicadores';
  raise notice 'OK  · el lector ve los indicadores';
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', false) \gset
do $$ begin
  perform public.k('2025-06-30', 'cash');
  raise exception 'FALLO: un usuario ajeno ha visto los indicadores';
exception when others then
  assert sqlerrm like 'Not allowed to read this company%', 'mensaje inesperado: ' || sqlerrm;
  raise notice 'OK  · un usuario ajeno no ve los indicadores de otra empresa';
end $$;
reset role;
do $$ begin
  begin
    set local role anon;
    perform erp.home_kpis((select valor from public.ctx where clave = 'empresa'), '2025-06-30');
    raise exception 'FALLO: anon ha podido ejecutar home_kpis';
  exception when insufficient_privilege then
    raise notice 'OK  · anon no puede ejecutar home_kpis';
  end;
end $$;

\echo '✔ FASE 25 OK · indicadores del Inicio'
