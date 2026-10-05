-- =====================================================================
-- PRUEBAS FASE 8 · naturaleza de saldos y saldos anómalos (migración 0013)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');

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

-- Asiento rápido: fecha, pares (cuenta, debe, haber)
create or replace function public.asiento(e uuid, d date, l jsonb, p_post boolean default true) returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, 'Prueba')
  returning id into a;
  insert into erp.journal_lines (entry_id, line_no, gl_account_id, debit, credit)
  select a, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0),
         (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  if p_post then perform erp.post_entry(a); end if;
  return a;
end $$;
grant execute on function public.asiento(uuid, date, jsonb, boolean) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; r record; a uuid; n int;
begin
  -- ---------- Naturaleza por prefijo más largo ----------
  assert (erp.balance_nature('57200001')).nature = 'debit';
  assert (erp.balance_nature('57200001')).reclass_to = '5201';
  assert (erp.balance_nature('28100001')).nature = 'credit', 'amortización acumulada: acreedora';
  assert (erp.balance_nature('47000002')).nature = 'debit';
  assert (erp.balance_nature('47500002')).nature = 'credit';
  assert (erp.balance_nature('47210007')).nature = 'debit';
  assert (erp.balance_nature('60800001')).nature = 'credit', '608 resta: acreedora';
  assert (erp.balance_nature('70800001')).nature = 'debit', '708 resta: deudora';
  assert (erp.balance_nature('12900000')).nature = 'mixed';
  assert (erp.balance_nature('43800001')).nature = 'credit';
  raise notice 'OK  · naturaleza: 572 deudora, 281 acreedora, 4700 deudora, 4750 acreedora, 608 acreedora, 708 deudora, 129 mixta';

  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Auditoría SL', 'services', 'canary_islands', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('10000001', 'Capital'), ('57000001', 'Caja'), ('57200001', 'Banco'), ('43000001', 'Cliente'),
    ('40000001', 'Proveedor'), ('62300001', 'Servicios'), ('70500001', 'Ventas')) as s(no, name);
  assert (select block_inverse_balance from erp.gl_accounts where company_id = e and account_no = '57000001'), 'la caja nace bloqueada';
  assert not (select block_inverse_balance from erp.gl_accounts where company_id = e and account_no = '57200001');

  -- Constitución: 1.000 a caja · 500 a banco
  perform public.asiento(e, '2026-01-02', '[["57000001",1000,0],["57200001",500,0],["10000001",0,1500]]');
  -- Pago desde el banco de 800 (deja el banco en −300: descubierto)
  perform public.asiento(e, '2026-02-01', '[["62300001",800,0],["57200001",0,800]]');
  -- Cobro anticipado de un cliente 200 (cliente acreedor) y pago de más a un proveedor 50 (proveedor deudor)
  perform public.asiento(e, '2026-02-05', '[["57000001",200,0],["43000001",0,200]]');
  perform public.asiento(e, '2026-02-06', '[["40000001",50,0],["57000001",0,50]]');

  select count(*) into n from erp.balance_anomalies(e, 2026);
  assert n = 3, format('esperaba 3 anomalías, hay %s', n);
  select * into r from erp.balance_anomalies(e, 2026) where account_no = '57200001';
  assert r.balance = -300 and r.reclass_to = '5201' and r.expected = 'debit', r::text;
  select * into r from erp.balance_anomalies(e, 2026) where account_no = '43000001';
  assert r.balance = -200 and r.reclass_to = '438';
  select * into r from erp.balance_anomalies(e, 2026) where account_no = '40000001';
  assert r.balance = 50 and r.reclass_to = '407';
  raise notice 'OK  · anomalías: banco −300 → 5201 · cliente −200 → 438 · proveedor +50 → 407';

  -- A nivel de cuenta (3 dígitos) también se detectan; a nivel de grupo no se analiza
  assert (select count(*) from erp.balance_anomalies(e, 2026, 3)) = 3;
  assert (select count(*) from erp.balance_anomalies(e, 2026, 1)) = 0, 'a nivel de grupo se mezclan naturalezas';
  -- Con fecha de corte anterior al pago, el banco aún no está en descubierto
  assert not exists (select 1 from erp.balance_anomalies(e, 2026, null, '2026-01-31'));
  raise notice 'OK  · el informe respeta nivel y fecha de corte';

  -- ---------- Caja bloqueada: no puede quedar acreedora ----------
  perform public.debe_fallar(format('select public.asiento(%L, %L, %L)', e, '2026-03-01',
        '[["62300001",2000,0],["57000001",0,2000]]'), 'blocked for inverse balances', 'pagar con caja más de lo que hay');
  -- El asiento no se contabilizó (todo o nada): la caja sigue en 1.150
  assert (select sum(l.debit - l.credit) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id and j.status = 'posted'
          join erp.gl_accounts g on g.id = l.gl_account_id where g.company_id = e and g.account_no = '57000001') = 1150;
  -- Un pago que cabe sí entra
  perform public.asiento(e, '2026-03-01', '[["62300001",1000,0],["57000001",0,1000]]');
  -- Se puede desbloquear una cuenta (decisión del usuario)
  update erp.gl_accounts set block_inverse_balance = false where company_id = e and account_no = '57000001';
  perform public.asiento(e, '2026-03-02', '[["62300001",500,0],["57000001",0,500]]');
  select * into r from erp.balance_anomalies(e, 2026) where account_no = '57000001';
  assert r.severity = 'error' and r.balance = -350, r::text;
  raise notice 'OK  · caja bloqueada; si se desbloquea, el informe la marca como ERROR (−350)';
end $$;

reset role;
drop function public.debe_fallar(text, text, text);
drop function public.asiento(uuid, date, jsonb, boolean);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 8 (SALDOS) PASARON ==========='
