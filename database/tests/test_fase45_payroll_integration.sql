-- =====================================================================
-- PRUEBAS FASE 45 · Nóminas: integración (migración 0050)
-- ---------------------------------------------------------------------
--  Oficina Guanche SL (los empleados del supuesto de la fase 44), enero a marzo de 2026, modo guiado:
--   · Comprobaciones: «Nóminas frente a la contabilidad» (465 / 476) en verde con las nóminas y sus pagos; un asiento
--     manual en la 465 la pone en aviso. «Retenciones (4751)» suma el IRPF de las nóminas: 3 × 275 = 825 frente a 825.
--   · Modelo 111 del 1T: nóminas en las casillas 01 a 03 → 2 perceptores, 3 × (2.000 + 1.750) = 11.250 de percepciones
--     y 825 de retenciones, junto a la factura de una abogada (casillas 07 a 09: 1.000 al 15 % = 150).
--   · Glosario: «Nómina» y «Seguridad Social a cargo de la empresa», con su ⓘ en la comprobación y en las cuentas.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local');
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
create or replace function public.saldo(e uuid, y int, prefijo text) returns numeric language sql as $$
  select coalesce(sum(debit_balance - credit_balance), 0) from erp.trial_balance(e, y) where account_no like prefijo || '%';
$$;
create or replace function public.asiento(e uuid, y int, n int) returns text language sql as $$
  select string_agg(g.account_no || ' ' || case when l.debit > 0 then 'D ' || l.debit else 'H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_entries j join erp.fiscal_years fy on fy.id = j.fiscal_year_id and fy.year = y
  join erp.journal_lines l on l.entry_id = j.id join erp.gl_accounts g on g.id = l.gl_account_id
  where j.company_id = e and j.entry_no = n;
$$;
create or replace function public.comprueba() returns void language plpgsql as $$
begin execute 'set constraints all immediate'; execute 'set constraints all deferred'; end $$;
grant execute on function public.falla(text, text), public.saldo(uuid, int, text), public.asiento(uuid, int, int), public.comprueba() to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; ana uuid; luis uuid; r record; m int; w uuid; abogada uuid; enero uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Oficina Guanche SL', 'services', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_posting_account(e, x.no, x.name) from (values ('57200001', 'Banco'), ('10000001', 'Capital'),
    ('62300001', 'Servicios de profesionales independientes')) as x(no, name);
  ana := erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Ana Ficticia', 'hire_date', '2025-03-01',
    'monthly_salary', 2000, 'extra_payments', 2, 'irpf_pct', 12));
  luis := erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Luis Ficticio', 'contract_type', 'temporary', 'hire_date', '2026-01-01',
    'monthly_salary', 1500, 'extra_payments', 2, 'extra_prorated', true, 'irpf_pct', 2));
  for m in 1..3 loop
    select pr.run_id into w from erp.run_payroll(jsonb_build_object('company_id', e, 'period', make_date(2026, m, 1))) pr;
    if m = 1 then enero := w; end if;
    perform erp.pay_payroll(jsonb_build_object('run_id', w, 'what', 'net', 'payment_date', (make_date(2026, m, 1) + interval '1 month - 1 day')::date, 'cash_account_no', '57200001'));
  end loop;
  perform erp.pay_payroll(jsonb_build_object('run_id', enero, 'what', 'social_security', 'payment_date', '2026-02-27', 'cash_account_no', '57200001'));

  -- ---------- 1. Comprobaciones ----------
  select * into r from erp.run_audit_checks(e, 2026, '2026-03-31') where code = 'payroll_ledger';
  assert r.status = 'ok' and r.items = 0 and r.screen = 'payroll' and r.area = 'ledger', r::text;
  select * into r from erp.run_audit_checks(e, 2026, '2026-03-31') where code = 'withholdings';
  assert r.status = 'ok' and r.book = 825 and r.ledger = 825, 'IRPF de nóminas en el libro: ' || r.book || ' / ' || r.ledger;
  assert (select concept from erp.audit_checks where code = 'payroll_ledger') = 'payroll';
  raise notice 'OK  · nóminas = 465 / 476; la 4751 cuadra con el IRPF de las nóminas (825)';

  -- …una nómina a mano en la 465 (modo guiado: se deja, pero se avisa)
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), '2026-03-31', 'Paga de beneficios a mano') returning id into w;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (w, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '64000001'), 500, 0),
    (w, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '46500001'), 0, 500);
  perform erp.post_entry(w);
  select * into r from erp.run_audit_checks(e, 2026, '2026-03-31') where code = 'payroll_ledger';
  assert r.status = 'warning' and r.items = 1 and r.difference = -500
     and r.details->0->>'account_no' = '46500001', r::text;
  perform erp.reverse_entry(w, '2026-03-31', 'Se hace desde Nóminas');
  assert (select status from erp.run_audit_checks(e, 2026, '2026-03-31') where code = 'payroll_ledger') = 'ok', 'anulada, en verde';
  raise notice 'OK  · un asiento manual en la 465 avisa (−500) y, anulado, vuelve a verde';

  -- ---------- 2. Modelo 111 del primer trimestre ----------
  select x.partner_id into abogada from erp.create_partner(e, 'creditor', 'Abogada Ficticia', '12345678Z') x;
  perform erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'document_kind', 'invoice',
    'partner_id', abogada, 'external_document_no', 'A-1', 'invoice_date', '2026-02-10', 'withholding_code', 'IRPF15',
    'lines', '[{"account_no":"62300001","amount":1000,"tax_code":"IGIC7"}]'::jsonb));
  select * into r from erp.withholding_summary(e, 2026, 1) where withholding_code = 'payroll';
  assert r.side = 'withheld' and r.form = '111' and r.rate_pct is null and r.recipients = 2 and r.base = 11250 and r.amount = 825, r::text;
  assert (select string_agg(coalesce(withholding_code, '-') || ' ' || amount, ', ') from erp.withholding_summary(e, 2026, 1) where form = '111')
       like 'payroll 825.00, %', 'las nóminas van primero: ' || (select string_agg(withholding_code || ' ' || amount, ', ') from erp.withholding_summary(e, 2026, 1));
  assert (select amount from erp.withholding_summary(e, 2026, 1) where form = '111' and withholding_code <> 'payroll') = 150, 'la abogada, aparte';
  assert not exists (select 1 from erp.withholding_summary(e, 2026, 2)), '2T: nada';
  select * into r from erp.run_audit_checks(e, 2026, '2026-03-31') where code = 'withholdings';
  assert r.status = 'ok' and r.book = 975 and r.ledger = 975, r::text;
  raise notice 'OK  · modelo 111 del 1T: nóminas 2 perceptores, 11.250 y 825 (casillas 01-03); profesionales 150 (07-09)';

  -- …una nómina anulada no cuenta
  perform erp.cancel_payroll((select id from erp.payroll_runs where company_id = e and period = '2026-03-31'));   -- deshace el pago del líquido
  perform erp.cancel_payroll((select id from erp.payroll_runs where company_id = e and period = '2026-03-31'));   -- y la nómina
  assert (select amount from erp.withholding_summary(e, 2026, 1) where withholding_code = 'payroll') = 550, 'dos meses';
  select * into r from erp.run_audit_checks(e, 2026, '2026-03-31') where code = 'withholdings';
  assert r.status = 'ok' and r.book = 700 and r.ledger = 700, r::text;
  assert (select status from erp.run_audit_checks(e, 2026, '2026-03-31') where code = 'payroll_ledger') = 'ok';
  raise notice 'OK  · anulada marzo: el 111 y las comprobaciones la quitan';

  -- ---------- 3. Glosario ----------
  assert (select string_agg(key, ',' order by sort) from erp.concepts where key in ('payroll', 'socialSecurity')) = 'payroll,socialSecurity';
  assert (select term from erp.concepts where key = 'socialSecurity') = 'Seguridad Social a cargo de la empresa';
  assert (select string_agg(key, ',' order by key) from erp.concepts_for_account('64200001')) like '%socialSecurity%', 'la 642 tiene su ⓘ';
  assert (select string_agg(key, ',' order by key) from erp.concepts_for_account('46500001')) like '%payroll%', 'y la 465';
  perform public.comprueba();
  assert not exists (select 1 from erp.integrity_checks(e, 2026) where status = 'fail');
  raise notice 'OK  · glosario: «Nómina» y «Seguridad Social a cargo de la empresa»; invariantes en verde';
end $$;

-- ---------- 4. Seguridad: el lector ve el 111 con las nóminas; otro usuario, nada ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select v from public.ctx where k = 'empresa');
begin
  assert not exists (select 1 from erp.withholding_summary(e, 2026, 1)), 'sin acceso a la empresa, nada';
  raise notice 'OK  · otro usuario no ve las nóminas en el 111';
end $$;

\echo '✔ FASE 45 OK · nóminas: integración'
