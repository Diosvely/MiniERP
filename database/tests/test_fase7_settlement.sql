-- =====================================================================
-- PRUEBAS FASE 7 · liquidación trimestral de IVA / IGIC (migración 0012)
-- Ejecutar en una base limpia: stub + migraciones 0001-0012.
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

-- Factura rápida: tipo, tercero, nº, fecha, cuenta, base
create or replace function public.factura(e uuid, ty text, p uuid, ext text, d date, acc text, amt numeric)
returns uuid language sql as $$
  select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', ty, 'partner_id', p,
    'external_document_no', ext, 'invoice_date', d,
    'lines', jsonb_build_array(jsonb_build_object('account_no', acc, 'amount', amt, 'tax_code', 'IGIC7'))));
$$;
grant execute on function public.factura(uuid, text, uuid, text, date, text, numeric) to authenticated;

create or replace function public.asiento(p_entry uuid) returns text language sql as $$
  select string_agg(g.account_no || case when l.debit > 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id where l.entry_id = p_entry;
$$;
grant execute on function public.asiento(uuid) to authenticated;

create or replace function public.saldo(e uuid, acc text) returns numeric language sql as $$
  select coalesce(sum(l.debit - l.credit), 0) from erp.journal_lines l
  join erp.journal_entries j on j.id = l.entry_id and j.status = 'posted'
  join erp.gl_accounts g on g.id = l.gl_account_id where g.company_id = e and g.account_no = acc;
$$;
grant execute on function public.saldo(uuid, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; ej uuid; prov uuid; cli uuid; c jsonb; r record; q2 uuid; a uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Tienda Canaria', 'retail', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  ej := erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('60000001', 'Compras'), ('70000001', 'Ventas'), ('57200001', 'Banco')) as s(no, name);
  select partner_id into prov from erp.create_partner(e, 'vendor', 'Proveedor', 'B12345674');
  select partner_id into cli  from erp.create_partner(e, 'customer', 'Cliente', 'B11111119');

  -- ---------- 1T: soportado mayor que repercutido → a compensar ----------
  perform public.factura(e, 'purchase', prov, 'P-1', '2026-02-10', '60000001', 1000);   -- IGIC 70
  perform public.factura(e, 'sale',     cli,  null,  '2026-03-15', '70000001', 500);    -- IGIC 35
  c := erp.tax_settlement_calc(e, 'IGIC', 2026, 1);
  assert c->>'form' = '420';
  assert (c->>'output_tax')::numeric = 35 and (c->>'input_tax')::numeric = 70, c::text;
  assert (c->>'difference')::numeric = 0, 'libro registro = contabilidad';
  assert (c->>'final_result')::numeric = -35 and c->>'outcome' = 'carry_forward', c::text;
  assert jsonb_array_length(c->'boxes') = 2;
  select * into r from erp.post_tax_settlement(e, 'IGIC', 2026, 1);
  assert public.asiento((select entry_id from erp.tax_settlements where id = r.settlement_id))
         = '47210007 H 70.00 | 47710007 D 35.00 | 47000002 D 35.00',
         public.asiento((select entry_id from erp.tax_settlements where id = r.settlement_id));
  assert (select posting_date from erp.journal_entries j join erp.tax_settlements s on s.entry_id = j.id where s.id = r.settlement_id) = '2026-03-31';
  assert public.saldo(e, '47210007') = 0 and public.saldo(e, '47710007') = 0, 'las cuentas de impuesto quedan a cero';
  raise notice 'OK  · 1T: 477 D 35 · 472 H 70 · 4700 D 35 (a compensar), asiento a 31/03';

  -- Repetir el trimestre
  perform public.debe_fallar(format('select * from erp.post_tax_settlement(%L, %L, 2026, 1)', e, 'IGIC'),
        'already settled', 'liquidar dos veces el 1T');

  -- ---------- Trimestre bloqueado ----------
  perform public.debe_fallar(format('select public.factura(%L, %L, %L, %L, %L, %L, 100)', e, 'purchase', prov, 'P-TARDE', '2026-03-20', '60000001'),
        'already settled', 'factura con fecha de un trimestre liquidado');
  -- La misma factura con fecha de registro en el 2T sí entra (fecha de factura 20/03, registro 05/04)
  perform erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'partner_id', prov,
        'external_document_no', 'P-TARDE', 'invoice_date', '2026-03-20', 'posting_date', '2026-04-05',
        'lines', jsonb_build_array(jsonb_build_object('account_no', '60000001', 'amount', 100, 'tax_code', 'IGIC7'))));
  raise notice 'OK  · factura que llega tarde: se registra en el trimestre siguiente';

  -- ---------- 2T: a ingresar, compensando lo pendiente ----------
  perform public.factura(e, 'sale', cli, null, '2026-05-20', '70000001', 2000);         -- IGIC 140
  c := erp.tax_settlement_calc(e, 'IGIC', 2026, 2);
  assert (c->>'result')::numeric = 133, c::text;                                          -- 140 − 7
  assert (c->>'carry_available')::numeric = 35 and (c->>'carry_applied')::numeric = 35;
  assert (c->>'final_result')::numeric = 98 and c->>'outcome' = 'payable';
  select * into r from erp.post_tax_settlement(e, 'IGIC', 2026, 2);
  q2 := r.settlement_id;
  assert public.asiento((select entry_id from erp.tax_settlements where id = q2))
         = '47210007 H 7.00 | 47710007 D 140.00 | 47000002 H 35.00 | 47500002 H 98.00',
         public.asiento((select entry_id from erp.tax_settlements where id = q2));
  assert public.saldo(e, '47000002') = 0, '4700 compensada';
  assert public.saldo(e, '47500002') = -98, '4750: 98 a ingresar';
  raise notice 'OK  · 2T: 477 D 140 · 472 H 7 · 4700 H 35 (compensación) · 4750 H 98 (a ingresar)';

  -- ---------- Deshacer ----------
  perform public.debe_fallar(format('select erp.cancel_tax_settlement(%L)', (select id from erp.tax_settlements where quarter = 1 and company_id = e)),
        'Only the last', 'deshacer una liquidación que no es la última');
  perform erp.cancel_tax_settlement(q2);
  assert public.saldo(e, '47500002') = 0 and public.saldo(e, '47710007') = -140, 'el contraasiento deja todo como antes';
  c := erp.tax_settlement_calc(e, 'IGIC', 2026, 2);
  assert (c->>'final_result')::numeric = 98 and (c->>'output_tax')::numeric = 140, 'la anulada no cuenta como movimiento';
  perform erp.post_tax_settlement(e, 'IGIC', 2026, 2);
  raise notice 'OK  · deshacer la última liquidación (contraasiento) y volver a liquidar';

  -- ---------- 3T: apunte manual en la 477 sin factura → diferencia ----------
  perform public.factura(e, 'sale', cli, null, '2026-08-01', '70000001', 1000);         -- IGIC 70
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, ej, '2026-08-02', 'Apunte manual sin factura') returning id into a;
  insert into erp.journal_lines (entry_id, line_no, gl_account_id, debit, credit) values
    (a, 1, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), 7, 0),
    (a, 2, (select id from erp.gl_accounts where company_id = e and account_no = '47710007'), 0, 7);
  perform erp.post_entry(a);
  c := erp.tax_settlement_calc(e, 'IGIC', 2026, 3);
  assert (c->>'difference')::numeric = 7, c::text;
  perform public.debe_fallar(format('select * from erp.post_tax_settlement(%L, %L, 2026, 3)', e, 'IGIC'),
        'differ by 7', 'libro registro ≠ contabilidad');
  select * into r from erp.post_tax_settlement(e, 'IGIC', 2026, 3, false, true);
  assert r.final_result = 77;
  assert (select register_difference from erp.tax_settlements where id = r.settlement_id) = 7, 'la diferencia queda guardada';
  raise notice 'OK  · diferencia libro registro ↔ 477: se bloquea, y si se acepta queda registrada (77 a ingresar)';

  -- ---------- 4T negativo: devolución ----------
  perform public.factura(e, 'purchase', prov, 'P-4T', '2026-11-10', '60000001', 3000);  -- IGIC 210
  c := erp.tax_settlement_calc(e, 'IGIC', 2026, 4);
  assert (c->>'can_refund')::boolean and c->>'outcome' = 'carry_forward';
  select * into r from erp.post_tax_settlement(e, 'IGIC', 2026, 4, true);
  assert r.outcome = 'refund' and r.final_result = -210;
  raise notice 'OK  · 4T negativo: se puede pedir la devolución (210 en la 4700)';

  -- ---------- Solo en el 4T se puede pedir devolución ----------
  c := erp.tax_settlement_calc(e, 'IGIC', 2026, 1, true);
  assert not (c->>'can_refund')::boolean;
end $$;

-- ---------- Lector ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  assert (select count(*) from erp.v_tax_settlements where company_id = e and status = 'posted') = 4;
  perform public.debe_fallar(format('select * from erp.post_tax_settlement(%L, %L, 2027, 1)', e, 'IGIC'),
        'No permission', 'un viewer no liquida');
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  perform public.debe_fallar(format('update erp.tax_settlements set final_result = 0 where company_id = %L', e),
        'post_tax_settlement', 'modificar una liquidación a mano');
  perform erp.delete_company(e);
  assert not exists (select 1 from erp.tax_settlements where company_id = e);
  raise notice 'OK  · borrar la empresa borra sus liquidaciones';
end $$;

reset role;
drop table public.ctx;
drop function public.debe_fallar(text, text, text);
drop function public.factura(uuid, text, uuid, text, date, text, numeric);
drop function public.asiento(uuid);
drop function public.saldo(uuid, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 7 (LIQUIDACIÓN) PASARON ==========='
