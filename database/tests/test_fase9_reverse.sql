-- =====================================================================
-- PRUEBAS FASE 9 · anular asientos (migración 0014)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local');

create or replace function public.debe_fallar(p_sql text, p_texto text, p_prueba text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm ilike '%' || p_texto || '%' then
      raise notice 'OK  · %  →  %', p_prueba, sqlerrm;
      return;
    end if;
    raise exception 'FALLO · % · error inesperado: %', p_prueba, sqlerrm;
  end;
  raise exception 'FALLO · % · debía dar error y no lo dio', p_prueba;
end $$;
grant execute on function public.debe_fallar(text, text, text) to authenticated;
create table public.ctx (clave text primary key, valor uuid);
grant all on public.ctx to authenticated;

create or replace function public.asiento(e uuid, d date, l jsonb) returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, 'Pago alquiler')
  returning id into a;
  insert into erp.journal_lines (entry_id, line_no, gl_account_id, debit, credit)
  select a, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  return a;
end $$;
grant execute on function public.asiento(uuid, date, jsonb) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; a uuid; n int; r record; prov uuid; inv uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Anulaciones SL', 'services', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('62100001', 'Arrendamientos'), ('57200001', 'Banco'), ('60000001', 'Compras')) as s(no, name);

  a := public.asiento(e, '2026-03-01', '[["62100001",800,0],["57200001",0,800]]');
  insert into public.ctx values ('asiento', a);

  -- No se puede anular con fecha anterior al original
  perform public.debe_fallar(format('select erp.reverse_entry(%L, %L)', a, '2026-02-01'), 'cannot be earlier', 'anular con fecha anterior');

  n := erp.reverse_entry(a, '2026-03-15', 'Cargo duplicado del banco');
  select * into r from erp.journal_entries where reversal_of = a;
  assert r.entry_no = n and r.posting_date = '2026-03-15';
  assert r.reversal_reason = 'Cargo duplicado del banco';
  assert r.description = 'Anulación del asiento 1: Pago alquiler · Cargo duplicado del banco', r.description;
  assert (select reversed_by_no from erp.v_general_journal where entry_id = a limit 1) = n;
  assert (select reversal_of_no || '/' || source from erp.v_general_journal where entry_id = r.id limit 1) = '1/reversal';
  assert (select sum(l.debit - l.credit) from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
          where g.company_id = e and g.account_no = '62100001') = 0, 'el gasto queda anulado';
  raise notice 'OK  · anulación con fecha y motivo: contraasiento enlazado en los dos sentidos';

  perform public.debe_fallar(format('select erp.reverse_entry(%L)', a), 'already reversed', 'anular dos veces');
  perform public.debe_fallar(format('select erp.reverse_entry(%L)', r.id), 'cannot be reversed', 'anular una anulación');

  -- Factura → rectificativa
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Proveedor', 'B12345674');
  select invoice_id into inv from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase',
    'partner_id', prov, 'external_document_no', 'X-1', 'invoice_date', '2026-04-01',
    'lines', jsonb_build_array(jsonb_build_object('account_no', '60000001', 'amount', 100, 'tax_code', 'IGIC7'))));
  assert (select source from erp.v_general_journal where entry_id = (select entry_id from erp.invoices where id = inv) limit 1) = 'invoice';
  perform public.debe_fallar(format('select erp.reverse_entry(%L)', (select entry_id from erp.invoices where id = inv)),
    'credit memo', 'anular el asiento de una factura');

  -- Liquidación → deshacer liquidación
  perform erp.post_tax_settlement(e, 'IGIC', 2026, 2);
  perform public.debe_fallar(format('select erp.reverse_entry(%L)', (select entry_id from erp.tax_settlements where company_id = e)),
    'Undo settlement', 'anular el asiento de una liquidación');
  perform erp.cancel_tax_settlement((select id from erp.tax_settlements where company_id = e));
  assert (select status from erp.tax_settlements where company_id = e) = 'cancelled', 'deshacer liquidación sigue funcionando';
  assert (select count(*) from erp.v_general_journal where source = 'settlement' and company_id = e and line_no = 1) = 2;
  raise notice 'OK  · facturas y liquidaciones se anulan por su propio circuito';
end $$;

-- Un lector no anula
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
        a uuid;
begin
  select id into a from erp.journal_entries where company_id = e and reversal_of is null and reversed_by is null
    and not exists (select 1 from erp.invoices i where i.entry_id = journal_entries.id) limit 1;
  if a is null then
    select entry_id into a from erp.invoices where company_id = e limit 1;
  end if;
  perform public.debe_fallar(format('select erp.reverse_entry(%L)', a), 'No permission', 'un viewer no anula');
end $$;

reset role;
drop table public.ctx;
drop function public.debe_fallar(text, text, text);
drop function public.asiento(uuid, date, jsonb);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 9 (ANULACIÓN) PASARON ==========='
