-- =====================================================================
-- PRUEBAS FASE 56 · Operaciones societarias integradas (migración 0061 · v0.42.0)
-- ---------------------------------------------------------------------
--   · Factura recibida a la 113 (gastos de constitución, NRV 9.ª) y su efecto en el Impuesto sobre Sociedades:
--       resultado 100.000; gastos en reservas 1.200 (deducibles, LIS art. 11.3) → base 98.800; cuota 25 % = 24.700;
--       el ahorro (300) va a la 113: 6300 D 25.000 / 113 H 300 · 4752 H 24.700; gasto 25.000 = 25 % del resultado.
--   · Cierre: aviso «resultado sin repartir» mientras la 129 del año anterior tenga saldo.
--   · Auditor: la retención de dividendos (47512) no descuadra la 4751 con el 111 / 115.
--   · Cuentas controladas (526 en modo estricto), glosario, fuente LSC y los dos supuestos de Practicar.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
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
  insert into erp.companies (name, industry, tax_territory, created_by) values (nombre, 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  foreach c in array array['57200001:Banco', '70500001:Prestación de servicios', '11300001:Reservas voluntarias'] loop
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
  select string_agg(g.account_no || case when l.debit <> 0 then ' D ' || l.debit else ' H ' || l.credit end, ' | ' order by l.line_no)
  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id where l.entry_id = p;
$$;
create or replace function public.chk(e uuid, y int, c text) returns text language sql as $$
  select x->>'severity' from jsonb_array_elements(erp.year_closing_preview(e, y)->'checks') x where x->>'code' = c;
$$;
create or replace function public.resp(t text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('account_no', p[1], 'debit', case p[2] when 'D' then p[3]::numeric else 0 end,
                                      'credit', case p[2] when 'H' then p[3]::numeric else 0 end) order by ord)
  from unnest(string_to_array(t, ' | ')) with ordinality u(x, ord), string_to_array(u.x, ' ') p;
$$;
grant execute on function public.falla(text, text), public.empresa(text), public.manual(uuid, date, jsonb), public.asiento(uuid),
  public.chk(uuid, int, text), public.resp(text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Glosario, fuente, cuentas controladas y Practicar ----------
do $$
declare g jsonb;
begin
  assert (select count(*) from erp.concepts where key in ('legalReserve', 'interimDividend', 'sharePremium', 'uncalledCapital')) = 4, 'glosario';
  assert (select ref from erp.sources where key = 'lsc') like '%274%', 'fuente: Ley de Sociedades de Capital';
  assert (select count(*) from erp.control_rules where modules = '{equity}') = 6, 'cuentas controladas: 190, 194, 1030, 5580, 526, 557';
  assert not exists (select 1 from erp.control_rules where account_prefix in ('100', '112', '113')), 'la apertura necesita la 100, la 112 y la 113';
  g := erp.grade_exercise('profit_distribution', public.resp('12900000 D 40000 | 11200001 H 1000 | 52600001 H 20000 | 11300001 H 19000'));
  assert (g->>'ok')::boolean and (g->>'score')::int = 100, g::text;
  g := erp.grade_exercise('profit_distribution', public.resp('129 D 40000 | 112 H 1000 | 557 H 20000 | 113 H 19000'));
  assert not (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'tips') t where t->>'msg' like 'La 557 es el dividendo a cuenta%'), g::text;
  g := erp.grade_exercise('sa_incorporation', public.resp('572 D 15000 | 1030 D 45000 | 100 H 60000'));
  assert (g->>'ok')::boolean, g::text;
  g := erp.grade_exercise('sa_incorporation', public.resp('572 D 15000 | 5580 D 45000 | 100 H 60000'));
  assert not (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'tips') t where t->>'msg' like 'La 5580 es lo que ya se ha exigido%'), g::text;
  assert (select screen from erp.operations where key = 'profit_distribution') = 'equity';
  raise notice 'OK  · glosario (4), fuente LSC, 6 cuentas controladas, operaciones y supuestos de Practicar';
end $$;

-- ---------- Gastos de constitución en la 113 y el Impuesto sobre Sociedades ----------
do $$
declare e uuid := public.empresa('Gastos SL'); n uuid; f uuid; g jsonb; v_ret uuid;
begin
  select partner_id into n from erp.create_partner(e, 'creditor', 'Notaría Ejemplo SL', 'B12345674');
  assert public.falla(format($q$select erp.post_invoice('{"company_id": "%s", "invoice_type": "purchase", "document_kind": "invoice", "partner_id": "%s", "invoice_date": "2026-01-20", "description": "x", "external_document_no": "N-1", "lines": [{"account_no": "57200001", "amount": 100, "tax_code": "VAT21"}]}')$q$, e, n), 'not valid in a received invoice'),
         'una factura recibida sigue sin poder ir a la 572';
  select invoice_id into f from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'document_kind', 'invoice',
         'partner_id', n, 'invoice_date', '2026-01-20', 'description', 'Escritura de constitución', 'external_document_no', 'N-26/14',
         'lines', '[{"account_no":"11300001","amount":1200,"tax_code":"VAT21"}]'::jsonb));
  assert public.asiento((select entry_id from erp.invoices where id = f)) like '11300001 D 1200.00 | 472% D 252.00 | 41%H 1452.00', public.asiento((select entry_id from erp.invoices where id = f));
  perform public.manual(e, '2026-06-30', '[["57200001", 100000, 0], ["70500001", 0, 100000]]');
  v_ret := erp.corporate_tax_prepare(e, 2026);
  perform erp.corporate_tax_settings(v_ret, 'general', false);
  assert (select amount from erp.corporate_tax_adjustments where return_id = v_ret and origin = 'equity_costs') = 1200
     and (select kind || '/' || direction from erp.corporate_tax_adjustments where return_id = v_ret and origin = 'equity_costs') = 'permanent/decrease',
         'propone el ajuste deducible';
  g := erp.corporate_tax_calc(e, 2026);
  assert (g->>'taxable_base')::numeric = 98800 and (g->>'quota')::numeric = 24700 and (g->>'equity_tax_effect')::numeric = 300
     and (g->>'current_tax')::numeric = 25000 and (g->>'tax_expense')::numeric = 25000 and (g->>'net_result')::numeric = 75000, g::text;
  g := erp.corporate_tax_post(e, 2026);
  assert public.asiento((select current_entry_id from erp.corporate_tax_returns where id = v_ret)) = '63000001 D 25000.00 | 11300001 H 300.00 | 47520001 H 24700.00',
         public.asiento((select current_entry_id from erp.corporate_tax_returns where id = v_ret));
  assert (select status from erp.integrity_checks(e, 2026) where code = 'corporate_tax') = 'ok', 'la 630 cuadra con la declaración';
  raise notice 'OK  · factura a la 113: ajuste deducible de 1.200; cuota 24.700; 6300 25.000 / 113 300 · 4752 24.700';
end $$;

-- ---------- Cierre, auditor y cuentas controladas ----------
do $$
declare e uuid := public.empresa('Junta SL'); g jsonb;
begin
  perform erp.set_control_mode(e, 'strict');
  perform erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-02', 'capital', 30000));
  perform public.manual(e, '2026-06-30', '[["57200001", 50000, 0], ["70500001", 0, 50000]]');
  perform erp.set_control_mode(e, 'guided');   -- (sin el impuesto, en estricto no se cierra: ver la fase 54)
  perform erp.close_fiscal_year(e, 2026, true);
  perform erp.set_control_mode(e, 'strict');
  assert public.chk(e, 2027, 'result_not_distributed') = 'warning', 'resultado del año anterior sin repartir';
  perform erp.equity_distribution(jsonb_build_object('company_id', e, 'date', '2027-05-20', 'dividend', 30000));
  execute 'set constraints all immediate'; execute 'set constraints all deferred';   -- en estricto, el módulo sí puede
  assert public.chk(e, 2027, 'result_not_distributed') is null, 'repartido: ya no avisa';
  assert public.falla(format('select public.manual(%L, %L, %L)', e, '2027-06-01', '[["52600001", 100, 0], ["57200001", 0, 100]]'), 'controlled'),
         'estricto: la 526 solo la mueven las operaciones societarias';
  g := erp.equity_dividend_payment(jsonb_build_object('company_id', e, 'date', '2027-06-01'));
  execute 'set constraints all immediate'; execute 'set constraints all deferred';
  assert (select coalesce(difference, 0) = 0 and status = 'ok' from erp.run_audit_checks(e, 2027, '2027-12-31') where code = 'withholdings'),
         'la retención de dividendos (47512, modelo 123) no descuadra la 4751 con el 111 / 115: '
         || (select status || ' ' || coalesce(difference::text, '') from erp.run_audit_checks(e, 2027, '2027-12-31') where code = 'withholdings');
  assert not exists (select 1 from erp.integrity_checks(e, 2027) where status = 'fail'),
         (select string_agg(code, ', ') from erp.integrity_checks(e, 2027) where status = 'fail');
  raise notice 'OK  · aviso de resultado sin repartir; 526 controlada en estricto; la 47512 fuera de la comprobación del 111';
end $$;
