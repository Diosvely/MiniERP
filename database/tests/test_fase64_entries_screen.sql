-- =====================================================================
-- PRUEBAS FASE 64 · Pantalla «Asientos» (migración 0070 · v0.47.0)
-- ---------------------------------------------------------------------
-- Mejora de uso 9 (mejoras-de-uso.md), validada por Diosvely:
--   · Una fila por asiento: fecha, documento, concepto, total Debe y Haber, origen y estado.
--   · Estados: contabilizado · en edición (borrador que se puede contabilizar) · con error (y por qué: una sola línea,
--     no cuadra, mes cerrado, después del mes abierto, cuenta controlada en modo estricto…).
--   · Borradores a medias (una línea, sin cuadrar), seguirlos, borrarlos y contabilizar varios de una vez.
--   · Filtros de fechas (mes, desde / hasta, todos) y por páginas.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
create or replace function public.empresa(nombre text, mensual boolean, modo text) returns uuid language plpgsql as $$
declare e uuid; c text;
begin
  insert into erp.companies (name, industry, tax_territory, control_mode, created_by) values (nombre, 'services', 'canary_islands', modo, auth.uid()) returning id into e;
  perform erp.start_accounting(e, '2026-01-01', mensual);
  foreach c in array array['57200001:Banco', '70500001:Prestación de servicios', '62900001:Otros servicios', '41000001:Acreedores'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  return e;
end $$;
create or replace function public.cta(e uuid, n text) returns uuid language sql as $$ select id from erp.gl_accounts where company_id = e and account_no = n $$;
-- Borrador: líneas como [[cuenta, debe, haber], …]
create or replace function public.borrador(e uuid, d date, concepto text, l jsonb, id uuid default null) returns uuid language sql as $$
  select erp.save_draft(jsonb_build_object('company_id', e, 'entry_id', id, 'posting_date', d, 'description', concepto,
    'lines', (select jsonb_agg(jsonb_build_object('gl_account_id', public.cta(e, x->>0), 'debit', (x->>1)::numeric, 'credit', (x->>2)::numeric))
              from jsonb_array_elements(l) x)));
$$;
create or replace function public.fila(e uuid, a uuid) returns text language sql as $$
  select state || '/' || coalesce(problem, '-') || '/' || source || '/' || total_debit || '/' || total_credit || '/' || lines
  from erp.entries_list(e) where entry_id = a $$;
grant execute on function public.falla(text, text), public.empresa(text, boolean, text), public.cta(uuid, text),
  public.borrador(uuid, date, text, jsonb, uuid), public.fila(uuid, uuid) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Los tres estados ----------
do $$
declare e uuid := public.empresa('Asientos SL', false, 'guided'); a uuid; b uuid; c uuid; n int;
begin
  insert into public.ctx values ('e', e);
  a := public.borrador(e, '2026-02-10', 'Alquiler', '[["62900001", 800, 0], ["57200001", 0, 800]]');
  b := public.borrador(e, '2026-02-11', 'Seguro', '[["62900001", 1200, 0]]');
  c := public.borrador(e, '2026-02-12', 'Venta', '[["57200001", 500, 0], ["70500001", 0, 400]]');
  assert public.fila(e, a) = 'ok/-/manual/800.00/800.00/2', 'en edición: ' || public.fila(e, a);
  assert public.fila(e, b) = 'error/one_line/manual/1200.00/0.00/1', 'una sola línea: ' || public.fila(e, b);
  assert public.fila(e, c) = 'error/unbalanced/manual/500.00/400.00/2', 'no cuadra: ' || public.fila(e, c);
  -- se sigue el borrador: ya cuadra
  perform public.borrador(e, '2026-02-12', 'Venta', '[["57200001", 400, 0], ["70500001", 0, 400]]', c);
  assert public.fila(e, c) = 'ok/-/manual/400.00/400.00/2', 'arreglado: ' || public.fila(e, c);
  -- contabilizado
  perform erp.post_entry(a);
  assert public.fila(e, a) like 'posted/-/manual/800.00/800.00/2', 'contabilizado: ' || public.fila(e, a);
  assert (select entry_no from erp.entries_list(e) where entry_id = a) = 1, 'con número';
  assert (select entry_no from erp.entries_list(e) where entry_id = c) is null, 'el borrador, sin número';
  assert public.falla(format('select public.borrador(%L, %L, %L, %L, %L)', e, '2026-02-10', 'x', '[["62900001", 1, 0]]', a), 'posted and cannot be changed'),
         'un contabilizado no se toca';
  assert public.falla(format('select erp.delete_draft(%L)', a), 'Reverse it instead'), 'ni se borra';
  -- borrar un borrador
  perform erp.delete_draft(b);
  select count(*) into n from erp.entries_list(e);
  assert n = 2, 'quedan dos: ' || n;
  raise notice 'OK  · estados: en edición (cuadra), con error (una línea · no cuadra), contabilizado (con número); seguir y borrar borradores';
end $$;

-- ---------- El origen de cada asiento ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'e'); p uuid; f uuid; s text; r uuid;
begin
  perform erp.setup_taxes(e);
  select partner_id into p from erp.create_partner(e, 'creditor', 'Asesoría SL', 'B12345674');
  select invoice_id into f from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'document_kind', 'invoice',
    'partner_id', p, 'invoice_date', '2026-02-15', 'external_document_no', 'A-1', 'description', 'Asesoría',
    'lines', '[{"account_no": "62900001", "amount": 100, "tax_code": "IGIC7"}]'::jsonb));
  perform erp.post_payment(jsonb_build_object('company_id', e, 'payment_type', 'payment', 'partner_id', p, 'payment_date', '2026-02-20',
    'cash_account_no', '57200001', 'applications', jsonb_build_array(jsonb_build_object('invoice_id', f, 'amount', 107))));
  perform erp.reverse_entry((select entry_id from erp.entries_list(e) where entry_no = 1 and status = 'posted'), '2026-02-25', 'Error');
  select string_agg(source, ',' order by entry_no) into s from erp.entries_list(e) where status = 'posted';
  assert s = 'manual,invoice,payment,reversal', 'orígenes: ' || s;
  assert (select reversed_by_no from erp.entries_list(e) where entry_no = 1) = 4, 'el anulado dice su contraasiento';
  raise notice 'OK  · origen: manual, factura, pago y contraasiento';
end $$;

-- ---------- Fechas y páginas ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'e'); n int;
begin
  perform public.borrador(e, '2026-03-05', 'Marzo', '[["62900001", 10, 0], ["57200001", 0, 10]]');
  assert (select count(*) from erp.entries_list(e, '2026-03-01', '2026-03-31')) = 1, 'mes de marzo';
  assert (select count(*) from erp.entries_list(e, '2026-02-01', '2026-02-28')) = 5, 'febrero';
  assert (select count(*) from erp.entries_list(e)) = 6, 'todos';
  select count(*) into n from erp.entries_list(e, null, null, 2, 0);
  assert n = 2 and (select max(total_count) from erp.entries_list(e, null, null, 2, 0)) = 6, 'página de 2, de 6';
  assert (select string_agg(to_char(posting_date, 'MM-DD'), ',') from erp.entries_list(e, null, null, 2, 2)) = '02-20,02-15', 'segunda página';
  assert (select posting_date from erp.entries_list(e) limit 1) = '2026-03-05', 'lo más reciente, arriba';
  raise notice 'OK  · filtro por fechas (marzo, febrero, todos) y por páginas, de lo más reciente a lo más antiguo';
end $$;

-- ---------- Contabilizar varios a la vez ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'e'); a uuid; b uuid; r jsonb;
begin
  a := public.borrador(e, '2026-03-06', 'Uno', '[["62900001", 20, 0], ["57200001", 0, 20]]');
  b := public.borrador(e, '2026-03-07', 'Mal', '[["62900001", 20, 0], ["57200001", 0, 10]]');
  r := erp.post_entries(e, (select array_agg(entry_id) from erp.entries_list(e) where status = 'draft'));
  assert jsonb_array_length(r->'posted') = 3 and jsonb_array_length(r->'failed') = 1, 'tres contabilizados y uno no: ' || r::text;
  assert r->'failed'->0->>'problem' = 'unbalanced' and r->'failed'->0->>'entry_id' = b::text, 'el que no cuadra se queda';
  assert (select string_agg(entry_no::text, ',' order by posting_date) from erp.entries_list(e) where posting_date >= '2026-02-12' and status = 'posted' and source = 'manual') = '5,6,7',
         'se numeran por fecha';
  raise notice 'OK  · contabilizar varios: los que se pueden, por fecha; el que no cuadra se queda en borrador';
end $$;

-- ---------- Mes a mes y modo estricto ----------
do $$
declare e uuid := public.empresa('Mes SL', true, 'strict'); a uuid; b uuid; c uuid; r jsonb;
begin
  a := public.borrador(e, '2026-02-10', 'Febrero', '[["62900001", 10, 0], ["57200001", 0, 10]]');
  assert public.fila(e, a) like 'error/after_month/%', 'después del mes abierto: ' || public.fila(e, a);
  c := public.borrador(e, '2026-01-12', 'Enero', '[["62900001", 10, 0], ["57200001", 0, 10]]');
  perform erp.close_month(e, true);
  b := public.borrador(e, '2026-02-11', 'Acreedor a mano', '[["62900001", 10, 0], ["41000001", 0, 10]]');
  assert public.fila(e, b) like 'error/controlled/%', 'cuenta controlada en estricto: ' || public.fila(e, b);
  assert public.fila(e, c) like 'error/period_closed/%', 'mes cerrado: ' || public.fila(e, c);
  assert public.fila(e, a) like 'ok/%', 'febrero, ahora sí';
  r := erp.post_entries(e, array[a, b, c]);
  assert jsonb_array_length(r->'posted') = 1 and (select string_agg(x->>'problem', ',' order by x->>'problem') from jsonb_array_elements(r->'failed') x) = 'controlled,period_closed',
         'contabilizar varios: ' || r::text;
  raise notice 'OK  · con error: después del mes abierto, mes cerrado y cuenta controlada en modo estricto (que no se contabiliza)';
end $$;

-- ---------- Permisos ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'e');
begin
  assert public.falla(format('select * from erp.entries_list(%L)', e), 'Not allowed'), 'otro usuario no ve la lista';
  assert public.falla(format('select erp.save_draft(%L)', jsonb_build_object('company_id', e, 'posting_date', '2026-02-01')), 'No permission'), 'ni guarda borradores';
  assert public.falla(format('select erp.delete_draft(%L)', (select id from erp.journal_entries where company_id = e and status = 'draft' limit 1)), 'No permission'), 'ni los borra';
  assert public.falla(format('select erp.post_entries(%L, %L)', e, '{}'), 'No permission'), 'ni contabiliza';
  raise notice 'OK  · otro usuario no ve ni toca los asientos de una empresa ajena';
end $$;
reset role;
