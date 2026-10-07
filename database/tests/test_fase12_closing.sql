-- =====================================================================
-- PRUEBAS FASE 12 · Cierre del ejercicio (migración 0017)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'contable@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.asiento(e uuid, d date, txt text, l jsonb, borrador boolean default false)
returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, txt)
  returning id into a;
  insert into erp.journal_lines (entry_id, line_no, gl_account_id, debit, credit)
  select a, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  if not borrador then perform erp.post_entry(a); end if;
  return a;
end $$;
grant execute on function public.asiento(uuid, date, text, jsonb, boolean) to authenticated;

create or replace function public.partida(e uuid, y int, st text, c text) returns numeric language sql as $$
  select amount from erp.financial_statement(e, y, st) where code = c;
$$;
create or replace function public.saldo(e uuid, y int, cuenta text) returns numeric language sql as $$
  select coalesce(sum(b.balance), 0) from erp.year_account_balances(
    (select id from erp.fiscal_years where company_id = e and year = y)) b where b.account_no = cuenta;
$$;
grant execute on function public.partida(uuid, int, text, text), public.saldo(uuid, int, text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare
  e uuid; d uuid; c jsonb; r record; n int; ok boolean;
  act_antes numeric; res_antes numeric;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Cierre SL', 'retail', 'canary_islands', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.create_posting_account(e, s.no, s.name) from (values
    ('10000001','Capital'), ('17000001','Préstamo'), ('21600001','Mobiliario'), ('28160001','A.A. mobiliario'),
    ('40000001','Proveedor A'), ('43000001','Cliente A'), ('57000001','Caja'), ('57200001','Banco'),
    ('60000001','Compras'), ('62100001','Alquiler'), ('68100001','Amortización'), ('70000001','Ventas'),
    ('76900001','Otros ingresos financieros')) as s(no, name);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'accountant');

  perform public.asiento(e, '2026-01-02', 'Constitución', '[["57200001",10000,0],["10000001",0,10000]]');
  perform public.asiento(e, '2026-01-10', 'Préstamo', '[["57200001",5000,0],["17000001",0,5000]]');
  perform public.asiento(e, '2026-01-15', 'Mobiliario', '[["21600001",3000,0],["57200001",0,3000]]');
  perform public.asiento(e, '2026-02-01', 'Compra', '[["60000001",4000,0],["40000001",0,4000]]');
  perform public.asiento(e, '2026-03-01', 'Venta', '[["43000001",9000,0],["70000001",0,9000]]');
  perform public.asiento(e, '2026-03-05', 'Caja', '[["57000001",500,0],["57200001",0,500]]');
  perform public.asiento(e, '2026-03-20', 'Alquiler', '[["62100001",1200,0],["57200001",0,1200]]');
  perform public.asiento(e, '2026-06-30', 'Intereses cobrados', '[["57200001",20,0],["76900001",0,20]]');
  perform public.asiento(e, '2026-12-31', 'Amortización', '[["68100001",300,0],["28160001",0,300]]');
  -- Resultado: 9.000 + 20 − 4.000 − 1.200 − 300 = 3.520 de beneficio
  act_antes := public.partida(e, 2026, 'balance', 'ACT');
  res_antes := public.partida(e, 2026, 'pyg', 'PD');
  assert res_antes = 3520, 'resultado antes del cierre';

  -- ---------- 1) Comprobaciones ----------
  c := erp.year_closing_preview(e, 2026);
  assert (c->>'can_close')::boolean and not (c->>'has_warnings')::boolean, 'sin errores ni avisos';
  assert (c->>'result')::numeric = 3520;
  assert c->>'result_account_no' = '12900000', '129 + ceros hasta 8 dígitos';
  assert c->'checks' @> '[{"code":"result_account_created"},{"code":"next_year_created"}]', 'informa de lo que creará';
  assert jsonb_array_length(c->'closing_pl_lines') = 6, '5 cuentas de gastos e ingresos + 129';
  raise notice 'OK  · borrador: resultado 3.520, se crearán la 12900000 y el ejercicio 2027';

  d := public.asiento(e, '2026-12-31', 'Borrador olvidado', '[["62100001",10,0],["57000001",0,10]]', true);
  c := erp.year_closing_preview(e, 2026);
  assert not (c->>'can_close')::boolean and c->'checks' @> '[{"code":"draft_entries","severity":"error"}]';
  begin
    perform erp.close_fiscal_year(e, 2026, true); ok := false;
  exception when others then ok := sqlerrm like '%draft_entries%';
  end;
  assert ok, 'con borradores no se cierra';
  delete from erp.journal_entries where id = d;
  raise notice 'OK  · un borrador impide el cierre';

  perform erp.setup_taxes(e);   -- IGIC configurado y sin liquidar ningún trimestre → aviso
  c := erp.year_closing_preview(e, 2026);
  assert c->'checks' @> '[{"code":"unsettled_quarters","severity":"warning","detail":"IGIC 1T, IGIC 2T, IGIC 3T, IGIC 4T"}]';
  begin
    perform erp.close_fiscal_year(e, 2026); ok := false;
  exception when others then ok := sqlerrm like '%accept the warnings%';
  end;
  assert ok, 'los avisos hay que aceptarlos';
  raise notice 'OK  · trimestres sin liquidar: aviso que hay que aceptar';

  -- Un contable (no admin) no puede cerrar
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
  begin
    perform erp.close_fiscal_year(e, 2026, true); ok := false;
  exception when others then ok := sqlerrm like '%Only the company admin%';
  end;
  assert ok, 'solo el admin cierra';
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
  raise notice 'OK  · solo el administrador cierra el ejercicio';

  -- ---------- 2-4) Cerrar ----------
  select * into r from erp.close_fiscal_year(e, 2026, true);
  assert r.result = 3520 and r.closing_pl_no = 10 and r.closing_no = 11 and r.opening_no = 1, 'nº de asientos';
  assert (select status from erp.fiscal_years where company_id = e and year = 2026) = 'closed';
  assert (select status from erp.fiscal_years where company_id = e and year = 2027) = 'open', '2027 creado';
  assert not exists (select 1 from erp.year_account_balances((select id from erp.fiscal_years where company_id = e and year = 2026))),
    'tras el cierre todas las cuentas de 2026 están a cero';
  assert public.saldo(e, 2027, '12900000') = -3520, 'la 129 abre con el beneficio (acreedora)';
  assert public.saldo(e, 2027, '57200001') = 10320 and public.saldo(e, 2027, '28160001') = -300, 'apertura = saldos de cierre';
  assert public.saldo(e, 2027, '70000001') = 0, 'los ingresos no pasan de año';
  raise notice 'OK  · regularización (nº 10), cierre (nº 11) y apertura de 2027 (nº 1): 129 abre con 3.520 de beneficio';

  -- Los informes se ven igual antes y después del cierre
  assert public.partida(e, 2026, 'pyg', 'PD') = res_antes, 'PyG de 2026 intacta';
  assert public.partida(e, 2026, 'balance', 'ACT') = act_antes, 'balance de 2026 intacto';
  assert public.partida(e, 2026, 'balance', 'PN.A1.VII') = 3520;
  assert public.partida(e, 2027, 'balance', 'ACT') = act_antes and public.partida(e, 2027, 'balance', 'PNP') = act_antes,
    'el balance de 2027 arranca con el de 2026';
  assert public.partida(e, 2027, 'balance', 'PN.A1.VII') = 3520, '129 pendiente de aplicar';
  assert public.partida(e, 2027, 'pyg', 'PD') = 0;
  assert (select amount_prev from erp.financial_statement(e, 2027, 'balance') where code = 'ACT') = act_antes, 'columna 2026';
  raise notice 'OK  · balance y PyG de 2026 iguales tras cerrar; 2027 arranca con el balance de cierre';

  -- ---------- Bloqueos ----------
  begin
    perform public.asiento(e, '2026-12-31', 'Ajuste tardío', '[["62100001",100,0],["57200001",0,100]]'); ok := false;
  exception when others then ok := sqlerrm like '%is closed%';
  end;
  assert ok, 'ejercicio cerrado: no admite asientos';
  begin
    perform erp.reverse_entry((select closing_entry_id from erp.year_closings where company_id = e)); ok := false;
  exception when others then ok := sqlerrm like '%reopen the fiscal year%';
  end;
  assert ok, 'los asientos del cierre no se anulan desde el diario';
  begin
    update erp.fiscal_years set status = 'open' where company_id = e and year = 2026; ok := false;
  exception when others then ok := sqlerrm like '%Use the year-end closing%';
  end;
  assert ok, 'no se reabre cambiando el estado a mano';
  begin
    perform erp.post_closing_entry(e, (select id from erp.fiscal_years where company_id = e and year = 2027),
      '2027-01-01', 'opening', 'x', 'x', '[]'); ok := false;
  exception when others then ok := sqlerrm like '%only with close_fiscal_year%';
  end;
  assert ok, 'no se fabrican asientos de cierre fuera del asistente';
  assert (select count(distinct entry_no) from erp.v_general_journal where company_id = e and source = 'closing') = 3;
  raise notice 'OK  · bloqueos: sin asientos en 2026, sin anular el cierre desde el diario, sin cambiar el estado a mano';

  -- El asiento de apertura no es movimiento de IGIC del 1T de 2027
  assert erp.is_settlement_entry((select opening_entry_id from erp.year_closings where company_id = e));

  -- ---------- Reabrir para un ajuste tardío ----------
  perform public.asiento(e, '2027-01-20', 'Cobro cliente', '[["57200001",9000,0],["43000001",0,9000]]');
  perform erp.reopen_fiscal_year(e, 2026);
  assert (select status from erp.fiscal_years where company_id = e and year = 2026) = 'open';
  assert public.saldo(e, 2026, '70000001') = -9000, 'vuelven los saldos de ingresos';
  assert public.saldo(e, 2027, '12900000') = 0 and public.saldo(e, 2027, '57200001') = 9000, 'apertura anulada; queda el cobro';
  assert (select count(*) from erp.journal_entries where company_id = e and reversal_of is not null) = 3, '3 contraasientos';
  raise notice 'OK  · reabrir: 3 contraasientos (traza para el auditor) y 2026 vuelve a estar abierto';

  perform public.asiento(e, '2026-12-31', 'Ajuste tardío', '[["62100001",100,0],["57200001",0,100]]');
  select * into r from erp.close_fiscal_year(e, 2026, true);
  assert r.result = 3420, 'nuevo resultado';
  assert public.saldo(e, 2027, '12900000') = -3420 and public.saldo(e, 2027, '57200001') = 10220 + 9000;
  assert (select count(*) from erp.v_year_closings where company_id = e) = 2
     and (select count(*) from erp.v_year_closings where company_id = e and status = 'posted') = 1, 'historial';
  raise notice 'OK  · ajuste y nuevo cierre: resultado 3.420';

  -- ---------- Orden de los ejercicios ----------
  select * into r from erp.close_fiscal_year(e, 2027, true);
  begin
    perform erp.reopen_fiscal_year(e, 2026); ok := false;
  exception when others then ok := sqlerrm like '%Reopen fiscal year 2027 first%';
  end;
  assert ok, 'se reabre del más reciente al más antiguo';
  perform erp.reopen_fiscal_year(e, 2027);
  perform erp.reopen_fiscal_year(e, 2026);
  c := erp.year_closing_preview(e, 2027);
  assert c->'checks' @> '[{"code":"previous_year_open","severity":"error"}]', 'no se cierra 2027 con 2026 abierto';
  raise notice 'OK  · orden: se cierra del más antiguo al más reciente y se reabre al revés';
end $$;

reset role;
drop function public.asiento(uuid, date, text, jsonb, boolean);
drop function public.partida(uuid, int, text, text);
drop function public.saldo(uuid, int, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 12 (CIERRE DEL EJERCICIO) PASARON ==========='
