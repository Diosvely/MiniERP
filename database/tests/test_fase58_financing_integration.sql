-- =====================================================================
-- PRUEBAS FASE 58 · Financiación integrada (migración 0063 · v0.43.0)
-- ---------------------------------------------------------------------
-- Supuestos de referencia: supuestos-v0.43.0.md. Empresa de Canarias (IGIC del 7 %).
--   F3  Leasing de una máquina de 50.000 (4 cuotas de 13.500 y opción de compra de 2.500, vida útil 10 años): el alta
--       crea la ficha del activo (amortización 5.000 al año); la primera cuota es una factura de la entidad:
--       5240 D 11.030,59 · 6623 D 2.469,41 · 472 D 945 / 410 H 14.445; al cierre, 1740 → 5240 11.575,37
--   F3b El mismo leasing recibido el 01/07: al 31/12, intereses devengados a la 527 con el tipo implícito; la factura
--       del 30/06 los salda (5240 + 527 + 6623)
--   Deshacer la cuota emite la rectificativa completa; el asistente de cierre tiene el paso «Financiación»; el auditor
--   compara las cuentas de los préstamos con el módulo.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
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
create or replace function public.empresa(nombre text) returns uuid language plpgsql as $$
declare e uuid; c text;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values (nombre, 'services', 'canary_islands', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  foreach c in array array['57200001:Banco', '70500001:Prestación de servicios', '62300001:Servicios de profesionales'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  return e;
end $$;
create or replace function public.manual(e uuid, d date, l jsonb) returns void language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = extract(year from d)), d, 'Supuesto') returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  execute 'set constraints all immediate';   -- la regla de las cuentas controladas es diferida: se comprueba aquí
  execute 'set constraints all deferred';
end $$;
create or replace function public.asiento(p uuid) returns text language sql as $$
  select string_agg(left(g.account_no, 4) || case when l.debit <> 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id where l.entry_id = p;
$$;
create or replace function public.resp(t text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('account_no', p[1], 'debit', case p[2] when 'D' then p[3]::numeric else 0 end,
                                      'credit', case p[2] when 'H' then p[3]::numeric else 0 end) order by ord)
  from unnest(string_to_array(t, ' | ')) with ordinality u(x, ord), string_to_array(u.x, ' ') p;
$$;
create or replace function public.leasing(e uuid, d date, extra jsonb default '{}') returns uuid language sql as $$
  select (erp.loan_create(jsonb_build_object('company_id', e, 'kind', 'leasing', 'description', 'Leasing máquina', 'lender', 'Leasing Atlántico',
          'fair_value', 50000, 'instalment', 13500, 'purchase_option', 2500, 'periods', 4, 'frequency', 1, 'start_date', d,
          'useful_life_months', 120) || extra)->>'loan_id')::uuid $$;
create or replace function public.cuota(l uuid, p uuid, doc text, d date default null) returns jsonb language sql as $$
  select erp.loan_instalment_invoice(jsonb_build_object('loan_id', l, 'partner_id', p, 'external_document_no', doc, 'tax_code', 'IGIC7')
         || case when d is null then '{}'::jsonb else jsonb_build_object('invoice_date', d) end) $$;
create or replace function public.saldo(e uuid, pref text, d date) returns numeric language sql as $$
  select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id where j.company_id = e and j.status = 'posted' and j.posting_date <= d and g.account_no like pref || '%';
$$;
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;
grant execute on function public.falla(text, text), public.empresa(text), public.manual(uuid, date, jsonb), public.asiento(uuid),
  public.resp(text), public.leasing(uuid, date, jsonb), public.cuota(uuid, uuid, text, date), public.saldo(uuid, text, date) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Glosario, cuentas controladas y Practicar ----------
do $$
declare g jsonb;
begin
  assert (select count(*) from erp.concepts where key in ('amortizedCost', 'effectiveRate', 'financeLease', 'debtMaturity')) = 4, 'glosario';
  assert (select count(*) from erp.control_rules where 'financing' = any (modules)) = 8, 'cuentas controladas: 170, 171, 174, 520, 521, 524, 527, 528';
  assert (select modules from erp.control_rules where account_prefix = '524') = '{financing,invoices}', 'la 524, también la factura de la cuota';
  assert (select screen from erp.operations where key = 'finance_lease') = 'financing' and (select screen from erp.audit_checks where code = 'financing_ledger') = 'financing';
  g := erp.grade_exercise('loan_with_fee', public.resp('57200001 D 99000 | 52000001 H 17432.81 | 17000001 H 81567.19'));
  assert (g->>'ok')::boolean and (g->>'score')::int = 100, g::text;
  g := erp.grade_exercise('loan_with_fee', public.resp('572 D 99000 | 626 D 1000 | 520 H 17739.64 | 170 H 82260.36'));
  assert not (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'tips') t where t->>'msg' like 'La comisión no es gasto del primer día%'), g::text;
  g := erp.grade_exercise('leasing_start', public.resp('213 D 50000 | 524 H 11030.59 | 174 H 38969.41'));
  assert (g->>'ok')::boolean, g::text;
  g := erp.grade_exercise('leasing_start', public.resp('621 D 50000 | 524 H 11030.59 | 174 H 38969.41'));
  assert not (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'tips') t where t->>'msg' like 'Es arrendamiento financiero%'), g::text;
  raise notice 'OK  · glosario (4), 8 cuentas controladas, comprobación del auditor, operaciones y supuestos de Practicar';
end $$;

-- ---------- F3 · Leasing: ficha del activo, factura de la cuota y cierre ----------
do $$
declare e uuid := public.empresa('Leasing Canarias SL'); p uuid; l uuid; x jsonb; s text; f uuid;
begin
  insert into public.ctx values ('f3', e);
  select partner_id into p from erp.create_partner(e, 'creditor', 'Leasing Atlántico SA', 'B12345674');
  insert into public.ctx values ('f3p', p);
  -- antes de nada, el asistente no tiene préstamos
  assert (select status || '/' || step from erp.closing_checklist(e, 2026) where code = 'financing') = 'na/9', 'sin préstamos: no aplica';
  assert public.falla(format('select erp.loan_create(%L)', jsonb_build_object('company_id', e, 'kind', 'leasing', 'description', 'x',
           'fair_value', 50000, 'instalment', 13500, 'periods', 4, 'frequency', 1, 'start_date', '2026-01-01')), 'useful life'), 'sin vida útil, no';
  l := public.leasing(e, '2026-01-01');
  insert into public.ctx values ('f3l', l);
  -- la ficha del activo: 50.000, 10 años, en la 213
  assert (select a.cost || '/' || a.useful_life_months || '/' || left(g.account_no, 3) || '/' || a.acquisition_date
          from erp.fixed_assets a join erp.gl_accounts g on g.id = a.asset_account_id where a.id = (select asset_id from erp.loans where id = l))
       = '50000.00/120/213/2026-01-01', 'ficha del activo';
  -- la cuota, como factura recibida de la entidad, con IGIC sobre la cuota entera
  x := public.cuota(l, p, 'LA-2026/1');
  f := (x->>'invoice_id')::uuid;
  s := public.asiento((select entry_id from erp.invoices where id = f));
  assert s = '5240 D 11030.59 | 6623 D 2469.41 | 4721 D 945.00 | 4100 H 14445.00', 'factura de la cuota: ' || s;
  assert (select total_base || '/' || total_tax || '/' || total_amount || '/' || posting_date from erp.invoices where id = f) = '13500.00/945.00/14445.00/2026-12-31', 'totales de la factura';
  assert (select source from erp.v_general_journal where entry_id = (select entry_id from erp.invoices where id = f) limit 1) = 'invoice', 'origen: factura';
  assert (select count(*)::int from erp.loan_events v where v.loan_id = l and v.kind = 'payment' and v.status = 'posted') = 1 and (erp.loan_next_instalment(l)->>'n')::int = 2, 'pagada la primera cuota';
  -- el cierre: la amortización (Inmovilizado) y la reclasificación (Financiación)
  perform erp.post_depreciation(e, '2026-12-31');
  assert public.saldo(e, '681', '2026-12-31') = -5000 and public.saldo(e, '2813', '2026-12-31') = 5000, 'amortización: ' || public.saldo(e, '681', '2026-12-31');
  assert (select status from erp.closing_checklist(e, 2026) where code = 'financing') = 'pending', 'falta la reclasificación';
  perform erp.loan_year_end(e, '2026-12-31');
  assert (select status from erp.closing_checklist(e, 2026) where code = 'financing') = 'done', 'financiación hecha';
  assert public.saldo(e, '1740', '2026-12-31') = 27394.04 and public.saldo(e, '5240', '2026-12-31') = 11575.37, 'balance del leasing';
  assert (select string_agg(step || ':' || code, ' ' order by step) from erp.closing_checklist(e, 2026) where step >= 9) = '9:financing 10:audit_checks 11:corporate_tax 12:close', 'pasos';
  execute 'set constraints all immediate'; execute 'set constraints all deferred';
  assert (select status from erp.run_audit_checks(e, 2026, '2026-12-31') where code = 'financing_ledger') = 'ok', 'auditor: financiación';
  assert (select status from erp.run_audit_checks(e, 2026, '2026-12-31') where code = 'assets_ledger') = 'ok', 'auditor: inmovilizado (la ficha cuadra con la 213)';
  raise notice 'OK  · F3: ficha del activo, factura de la cuota (5240 + 6623 + IGIC 945 / 410 14.445) y cierre en verde';
end $$;

-- ---------- Las cuentas del leasing, solo desde Financiación ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'f3'); p uuid := (select c.e from public.ctx c where c.k = 'f3p');
        f uuid := (select invoice_id from erp.loan_events where kind = 'payment' and loan_id = (select c.e from public.ctx c where c.k = 'f3l'));
begin
  assert public.falla(format($q$select erp.post_invoice('{"company_id": "%s", "invoice_type": "purchase", "document_kind": "invoice", "partner_id": "%s", "invoice_date": "2026-12-31", "description": "x", "external_document_no": "M-1", "lines": [{"account_no": "52400001", "amount": 100, "tax_code": "IGIC7"}]}')$q$, e, p), 'from Financing'),
         'una factura normal no puede ir a la 524';
  assert public.falla(format($q$select erp.post_invoice('{"company_id": "%s", "invoice_type": "purchase", "document_kind": "credit_memo", "partner_id": "%s", "invoice_date": "2026-12-31", "description": "x", "external_document_no": "M-2", "corrected_invoice_id": "%s", "lines": [{"account_no": "62300001", "amount": 100, "tax_code": "IGIC7"}]}')$q$, e, p, f), 'undo it from Financing'),
         'la rectificativa de una cuota, solo desde Financiación';
  -- un asiento manual a la 5240 descuadra el módulo: el auditor lo ve
  perform public.manual(e, '2026-12-31', '[["52400001", 100, 0], ["57200001", 0, 100]]');
  assert (select status || '/' || difference from erp.run_audit_checks(e, 2026, '2026-12-31') where code = 'financing_ledger') = 'warning/100.00',
         (select status || '/' || coalesce(difference::text, '') from erp.run_audit_checks(e, 2026, '2026-12-31') where code = 'financing_ledger');
  perform public.manual(e, '2026-12-31', '[["57200001", 100, 0], ["52400001", 0, 100]]');
  raise notice 'OK  · la 524 no entra en una factura normal, la cuota no se rectifica a mano y el auditor ve el asiento manual';
end $$;

-- ---------- Deshacer: la reclasificación y la cuota (con su rectificativa) ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'f3'); p uuid := (select c.e from public.ctx c where c.k = 'f3p');
        l uuid := (select c.e from public.ctx c where c.k = 'f3l'); x jsonb; cm uuid;
begin
  assert erp.loan_cancel(l)->>'kind' = 'reclassification', 'primero la reclasificación';
  x := erp.loan_cancel(l);
  assert x->>'kind' = 'payment' and x->>'credit_memo_no' = 'CR-2026-0001', 'la cuota se deshace con su rectificativa: ' || x::text;
  cm := (select cancel_invoice_id from erp.loan_events where loan_id = l and kind = 'payment');
  assert (select document_kind || '/' || total_amount || '/' || corrected_invoice_id from erp.invoices where id = cm)
       = 'credit_memo/-14445.00/' || (select invoice_id from erp.loan_events where loan_id = l and kind = 'payment'), 'rectificativa completa';
  assert public.saldo(e, '5240', '2026-12-31') = 11030.59 and public.saldo(e, '472', '2026-12-31') = 0 and public.saldo(e, '6623', '2026-12-31') = 0, 'todo como antes de la cuota';
  assert (select count(*)::int from erp.loan_events v where v.loan_id = l and v.kind = 'payment' and v.status = 'posted') = 0, 'la cuota vuelve a estar pendiente';
  -- se registra de nuevo (otra factura de la entidad)
  perform public.cuota(l, p, 'LA-2026/1B');
  assert (select count(*)::int from erp.loan_events v where v.loan_id = l and v.kind = 'payment' and v.status = 'posted') = 1, 'registrada de nuevo';
  execute 'set constraints all immediate'; execute 'set constraints all deferred';
  assert (select status from erp.run_audit_checks(e, 2026, '2026-12-31') where code = 'financing_ledger') = 'ok', 'el auditor sigue en verde';
  raise notice 'OK  · deshacer la cuota emite la rectificativa completa (CR-2026-0001) y se puede volver a registrar';
end $$;

-- ---------- Deshacer el alta: primero la amortización; la ficha se borra con el alta ----------
do $$
declare e uuid := public.empresa('Leasing deshecho SL'); l uuid; a uuid; d uuid;
begin
  l := public.leasing(e, '2026-01-01');
  a := (select asset_id from erp.loans where id = l);
  perform erp.post_depreciation(e, '2026-06-30');
  assert public.falla(format('select erp.loan_cancel(%L)', l), 'already has depreciation'), 'con amortización, no';
  d := (select entry_id from erp.asset_depreciations where asset_id = a order by period_end desc limit 1);
  perform erp.cancel_depreciation(d, '2026-06-30');
  perform erp.loan_cancel(l);
  assert (select status from erp.loans where id = l) = 'cancelled' and not exists (select 1 from erp.fixed_assets where id = a), 'leasing y ficha anulados';
  assert public.saldo(e, '213', '2026-12-31') = 0 and public.saldo(e, '174', '2026-12-31') = 0, 'sin saldos';
  raise notice 'OK  · el alta del leasing no se deshace con amortizaciones; sin ellas, la ficha se borra';
end $$;

-- ---------- F3b · Intereses devengados del leasing y la factura que los salda ----------
do $$
declare e uuid := public.empresa('Leasing julio SL'); p uuid; l uuid; v_acc numeric; s text; x jsonb;
begin
  select partner_id into p from erp.create_partner(e, 'creditor', 'Leasing Atlántico SA', 'B12345674');
  l := public.leasing(e, '2026-07-01');
  v_acc := round(50000 * (power(1 + (select effective_rate from erp.loans where id = l), 0.5) - 1), 2);
  assert (erp.loan_year_end_preview(e, '2026-12-31')->>'accrual_total')::numeric = v_acc, 'devengo con el tipo implícito: ' || v_acc;
  perform erp.loan_year_end(e, '2026-12-31');
  assert public.saldo(e, '527', '2026-12-31') = v_acc, 'a la 527';
  x := public.cuota(l, p, 'LA-2027/1');
  s := public.asiento((select entry_id from erp.invoices where id = (x->>'invoice_id')::uuid));
  assert s = '5240 D 11030.59 | 5270 D ' || v_acc || ' | 6623 D ' || (2469.41 - v_acc) || ' | 4721 D 945.00 | 4100 H 14445.00', 'factura del 30/06: ' || s;
  assert public.saldo(e, '527', '2027-06-30') = 0, 'la 527 queda a cero';
  raise notice 'OK  · F3b: intereses devengados del leasing (%) y la factura del 30/06 que los salda', v_acc;
end $$;

-- ---------- Seguridad ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare l uuid := (select c.e from public.ctx c where c.k = 'f3l'); p uuid := (select c.e from public.ctx c where c.k = 'f3p');
begin
  assert public.falla(format('select public.cuota(%L, %L, %L)', l, p, 'X-1'), 'No permission'), 'otro usuario no registra la cuota';
  assert (select count(*) from erp.loans) = 0, 'ni ve el leasing';
  raise notice 'OK  · otro usuario no registra cuotas de un leasing ajeno';
end $$;

\echo '✔ FASE 58 OK · Financiación integrada: ficha del activo, factura de la cuota del leasing, cierre, auditor y Practicar'
