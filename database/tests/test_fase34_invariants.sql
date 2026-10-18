-- =====================================================================
-- PRUEBAS FASE 34 · Invariantes contables con operaciones al azar (migración 0040)
--   Dos empresas (Madrid con IVA, Canarias con IGIC) hacen ~300 operaciones al azar cada una:
--   facturas de todos los regímenes, rectificativas, cobros y pagos parciales, asientos manuales, contraasientos,
--   liquidaciones trimestrales, el cierre del ejercicio y operaciones del año siguiente.
--   Cada 25 operaciones, en cada liquidación y en el cierre se exige que TODOS los invariantes estén en verde.
--   Semilla fija (setseed): el mismo «azar» en cada ejecución, para poder repetir un fallo.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

-- Importe al azar entre a y b, con céntimos
create or replace function public.azar(a numeric, b numeric) returns numeric language sql volatile as $$
  select round((a + random() * (b - a))::numeric, 2);
$$;
create or replace function public.uno(arr text[]) returns text language sql volatile as $$
  select arr[1 + floor(random() * array_length(arr, 1))::int];
$$;
-- Asiento manual contabilizado
create or replace function public.manual(e uuid, d date, l jsonb) returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and d between starting_date and ending_date), d, 'Manual al azar')
  returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  return a;
end $$;
-- Todos los invariantes en verde (o «no aplica»); si no, falla diciendo cuál y con qué datos
create or replace function public.invariantes(e uuid, y int, cuando text) returns int language plpgsql as $$
declare r record; n int := 0;
begin
  for r in select * from erp.integrity_checks(e, y) loop
    if r.status = 'fail' then
      raise exception 'INVARIANTE ROTO (%) · % · esperado % · real % · %', cuando, r.code, r.expected, r.actual, r.detail;
    end if;
    if r.status = 'ok' then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ~N operaciones al azar en una empresa, entre dos fechas; liquida cada trimestre que termina
create or replace function public.operar(e uuid, desde date, hasta date, n int, impuesto text) returns int language plpgsql as $$
declare
  i int; d date; q int; q_prev int; r numeric; f uuid; p record; o record; m uuid; k int := 0; ok int;
  codigos text[] := case impuesto when 'VAT' then array['VAT21', 'VAT21', 'VAT10', 'VAT4', 'VAT0'] else array['IGIC7', 'IGIC7', 'IGIC3', 'IGIC0', 'IGIC15'] end;
  general text := case impuesto when 'VAT' then 'VAT21' else 'IGIC7' end;
  lineas jsonb;
begin
  q_prev := extract(quarter from desde)::int;
  for i in 1..n loop
    d := desde + ((hasta - desde) * i / n);
    q := extract(quarter from d)::int;
    -- Termina un trimestre: se liquida (sin aceptar diferencias: el libro y las cuentas TIENEN que cuadrar)
    if q <> q_prev then
      begin   -- amortización del trimestre (si hay activos)
        perform erp.post_depreciation(e, erp.quarter_end(extract(year from desde)::int, q_prev));
      exception when others then if sqlerrm not like 'Nothing to depreciate%' then raise; end if;
      end;
      perform erp.post_tax_settlement(e, impuesto, extract(year from desde)::int, q_prev);
      ok := public.invariantes(e, extract(year from desde)::int, format('tras liquidar el %sT', q_prev));
      q_prev := q;
    end if;
    r := random();
    begin
      if r < 0.28 then
        -- Factura recibida: proveedor nacional (1 o 2 líneas), abogada con IRPF, o (IVA) intracomunitaria / ISP
        select * into p from erp.v_partners where company_id = e and partner_type in ('vendor', 'creditor') order by random() limit 1;
        lineas := jsonb_build_array(jsonb_build_object('account_no', case when p.partner_type = 'vendor' then '60000001' else '62300001' end,
                    'amount', public.azar(20, 4000),
                    'tax_code', case when p.tax_territory = 'eu' then 'VAT21_AIB' when p.name like 'Reformas%' then 'VAT21_ISP'
                                     when p.name like 'Abogad%' then general else public.uno(codigos) end));
        if random() < 0.3 and p.tax_territory <> 'eu' and p.name not like 'Reformas%' then
          lineas := lineas || jsonb_build_object('account_no', '62900001', 'amount', public.azar(5, 300), 'tax_code', public.uno(codigos));
        end if;
        perform erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase', 'document_kind', 'invoice',
          'partner_id', p.id, 'external_document_no', 'P-' || i || '-' || substr(md5(random()::text), 1, 5), 'invoice_date', d,
          'description', 'Compra al azar', 'withholding_code', case when p.name like 'Abogad%' then 'IRPF15' end, 'lines', lineas));
      elsif r < 0.52 then
        -- Factura emitida: cliente general o minorista (recargo de equivalencia, solo con IVA)
        select * into p from erp.v_partners where company_id = e and partner_type = 'customer' order by random() limit 1;
        perform erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'sale', 'document_kind', 'invoice',
          'partner_id', p.id, 'invoice_date', d, 'description', 'Venta al azar',
          'lines', jsonb_build_array(jsonb_build_object('account_no', '70000001', 'amount', public.azar(20, 6000), 'tax_code',
                     case when p.name like 'Tienda%' then general else public.uno(codigos) end))));
      elsif r < 0.60 then
        -- Rectificativa de una factura anterior: 10 % de su primera línea, mismo tipo
        select i2.id, i2.invoice_type, i2.partner_id, l.account_no, l.amount, l.tax_code into o
        from erp.invoices i2 join erp.invoice_lines il on il.invoice_id = i2.id and il.line_no = 1
        join erp.gl_accounts l2 on l2.id = il.gl_account_id
        cross join lateral (select l2.account_no, il.amount, il.tax_code) l
        where i2.company_id = e and i2.document_kind = 'invoice' and i2.posting_date <= d
          and i2.posting_date >= make_date(extract(year from d)::int, 1, 1)
          and not (i2.invoice_type = 'sale' and left(l.account_no, 1) = '2')   -- (la rectificativa de la VENTA de un activo: backlog)
        order by random() limit 1;
        if found then
          perform erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', o.invoice_type, 'document_kind', 'credit_memo',
            'partner_id', o.partner_id, 'corrected_invoice_id', o.id, 'invoice_date', d, 'description', 'Rectificativa al azar',
            'external_document_no', case o.invoice_type when 'purchase' then 'R-' || i || '-' || substr(md5(random()::text), 1, 5) end,
            'lines', jsonb_build_array(jsonb_build_object('account_no', o.account_no, 'amount', round(o.amount * 0.1, 2), 'tax_code', o.tax_code))));
        end if;
      elsif r < 0.76 then
        -- Cobro o pago de una partida abierta: entera o en parte
        select * into o from erp.open_items(e, d) x where x.pending > 0 order by random() limit 1;
        if found then
          perform erp.post_payment(jsonb_build_object('company_id', e,
            'payment_type', case o.invoice_type when 'purchase' then 'payment' else 'collection' end,
            'partner_id', o.partner_id, 'payment_date', d, 'cash_account_no', '57200001',
            'applications', jsonb_build_array(jsonb_build_object('invoice_id', o.invoice_id,
              'amount', case when random() < 0.5 then o.pending else greatest(round(o.pending * random()::numeric, 2), 0.01) end))));
        end if;
      elsif r < 0.86 then
        -- Asiento manual: gasto bancario, intereses, nómina con retención, amortización o préstamo
        perform public.manual(e, d, case floor(random() * 5)::int
          when 0 then jsonb_build_array(jsonb_build_array('62600001', x.a, 0), jsonb_build_array('57200001', 0, x.a))
          when 1 then jsonb_build_array(jsonb_build_array('66200001', x.a, 0), jsonb_build_array('57200001', 0, x.a))
          when 2 then jsonb_build_array(jsonb_build_array('64000001', x.a * 10, 0), jsonb_build_array('47510001', 0, round(x.a * 1.5, 2)),
                                        jsonb_build_array('57200001', 0, x.a * 10 - round(x.a * 1.5, 2)))
          when 3 then jsonb_build_array(jsonb_build_array('62200001', x.a, 0), jsonb_build_array('57200001', 0, x.a))   -- (la amortización la hace el módulo)
          else jsonb_build_array(jsonb_build_array('57200001', x.a * 10, 0), jsonb_build_array('17000001', 0, x.a * 10)) end)
        from (select public.azar(10, 900) as a) x;
      elsif r < 0.92 then
        -- Contraasiento de un asiento manual anterior que siga vivo
        select e2.id into m from erp.journal_entries e2
        where e2.company_id = e and e2.status = 'posted' and e2.entry_type = 'normal' and e2.reversal_of is null
          and e2.reversed_by is null and e2.posting_date <= d and e2.posting_date >= make_date(extract(year from d)::int, 1, 1)
          and e2.description = 'Manual al azar'
        order by random() limit 1;
        if found then perform erp.reverse_entry(m, d, 'Contraasiento al azar'); end if;
      elsif r < 0.96 then
        -- Inmovilizado: comprar (con su factura y su ficha) o vender uno en uso (factura a su cuenta + baja)
        select a.* into o from erp.fixed_assets a where a.company_id = e and a.status = 'active' and a.start_date < d
          and not exists (select 1 from erp.asset_depreciations x where x.asset_id = a.id and x.period_end > d)
        order by random() limit 1;
        if random() < 0.6 or not found then
          select * into p from erp.v_partners where company_id = e and partner_type = 'vendor' and tax_territory <> 'eu'
          order by random() limit 1;
          f := (select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'purchase',
            'document_kind', 'invoice', 'partner_id', p.id, 'external_document_no', 'A-' || i || '-' || substr(md5(random()::text), 1, 5),
            'invoice_date', d, 'description', 'Compra de inmovilizado al azar',
            'lines', jsonb_build_array(jsonb_build_object('account_no', public.uno(array['21600001', '21700001']),
                       'amount', public.azar(300, 9000), 'tax_code', general)))));
          perform erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Activo ' || i,
            'asset_account_no', (select g.account_no from erp.invoice_lines l join erp.gl_accounts g on g.id = l.gl_account_id where l.invoice_id = f),
            'cost', (select amount from erp.invoice_lines where invoice_id = f), 'residual_value', 0, 'start_date', d,
            'useful_life_months', (12 * (2 + floor(random() * 8)))::int, 'invoice_id', f));
        else
          select * into p from erp.v_partners where company_id = e and partner_type = 'customer' and name not like 'Tienda%'
          order by random() limit 1;
          f := (select invoice_id from erp.post_invoice(jsonb_build_object('company_id', e, 'invoice_type', 'sale',
            'document_kind', 'invoice', 'partner_id', p.id, 'invoice_date', d, 'description', 'Venta de inmovilizado al azar',
            'lines', jsonb_build_array(jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = o.asset_account_id),
                       'amount', public.azar(10, o.cost), 'tax_code', general)))));
          perform erp.dispose_asset(jsonb_build_object('asset_id', o.id, 'disposal_date', d, 'invoice_id', f));
        end if;
      else
        -- Traspaso del banco a la caja y gasto pagado por caja (la caja nunca queda en negativo)
        perform public.manual(e, d, jsonb_build_array(jsonb_build_array('57000001', 200, 0), jsonb_build_array('57200001', 0, 200)));
        perform public.manual(e, d, jsonb_build_array(jsonb_build_array('62900001', 50, 0), jsonb_build_array('57000001', 0, 50)));
      end if;
      k := k + 1;
    exception when others then
      -- Una regla del ERP puede rechazar una operación al azar (es su trabajo); se anota y se sigue.
      -- Pero un invariante roto nunca se ignora.
      if sqlerrm like 'INVARIANTE ROTO%' then raise; end if;
      raise notice 'rechazada (%): %', r, sqlerrm;
    end;
    if i % 25 = 0 then ok := public.invariantes(e, extract(year from desde)::int, format('operación %s', i)); end if;
  end loop;
  return k;
end $$;

grant execute on function public.azar(numeric, numeric), public.uno(text[]), public.manual(uuid, date, jsonb),
  public.invariantes(uuid, int, text), public.operar(uuid, date, date, int, text) to authenticated;
create table public.ctx (k text primary key, v uuid);
grant all on public.ctx to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
select setseed(0.20261015);

do $$
declare e uuid; territorio text; impuesto text; n int; ok int; r record; hechas int;
begin
  foreach territorio in array array['mainland', 'canary_islands'] loop
    impuesto := case territorio when 'mainland' then 'VAT' else 'IGIC' end;
    insert into erp.companies (name, industry, tax_territory, created_by)
    values ('Azar ' || impuesto || ' SL', 'services', territorio, auth.uid()) returning id into e;
    perform erp.create_fiscal_year(e, 2026);
    perform erp.setup_taxes(e);
    perform erp.create_posting_account(e, s.no, s.name) from (values
      ('10000001', 'Capital'), ('17000001', 'Préstamo'), ('28160001', 'A.A. mobiliario'), ('57000001', 'Caja'),
      ('57200001', 'Banco'), ('60000001', 'Compras'), ('62300001', 'Profesionales'), ('62200001', 'Reparaciones'),
      ('62600001', 'Servicios bancarios'), ('62900001', 'Otros servicios'), ('64000001', 'Sueldos'),
      ('66200001', 'Intereses'), ('68100001', 'Amortización'), ('70000001', 'Ventas'),
      ('21600001', 'Mobiliario'), ('21700001', 'Equipos informáticos'), ('30000001', 'Mercaderías'), ('67800001', 'Gastos excepcionales')) as s(no, name);
    perform erp.create_partner(e, 'vendor', 'Proveedor Uno SL', 'B12345674');
    perform erp.create_partner(e, 'creditor', 'Abogada Ruiz', '12345678Z');
    perform erp.create_partner(e, 'customer', 'Cliente General SL', 'B11111119');
    perform erp.create_partner(e, 'customer', 'Cliente Dos SL', 'A58818501');
    if impuesto = 'VAT' then
      perform erp.create_partner(e, 'vendor', 'Lieferant GmbH', 'DE123456789', 'eu');
      perform erp.create_partner(e, 'creditor', 'Reformas Pérez SL', 'B87654323');
      perform erp.create_partner(e, 'customer', 'Tienda Lola', '87654321X');
      update erp.business_partners set equivalence_surcharge = true where company_id = e and name = 'Tienda Lola';
    end if;
    perform public.manual(e, '2026-01-02', '[["57200001",100000,0],["10000001",0,100000]]');

    -- 1) Año 2026: ~300 operaciones al azar, con sus liquidaciones trimestrales
    hechas := public.operar(e, '2026-01-03', '2026-12-30', 300, impuesto);
    begin perform erp.post_depreciation(e, '2026-12-31');
    exception when others then if sqlerrm not like 'Nothing to depreciate%' then raise; end if; end;
    perform erp.post_tax_settlement(e, impuesto, 2026, 4);
    -- v0.36.0 · Ajustes de cierre al 31/12: las cuatro periodificaciones y deterioros (individuales y global)
    perform erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'prepaid_expense', 'description', 'Seguro al azar',
      'pl_account_no', '62200001', 'cutoff_date', '2026-12-31', 'total_amount', public.azar(600, 3000),
      'coverage_start', '2026-' || lpad((7 + floor(random() * 6))::int::text, 2, '0') || '-' || lpad((1 + floor(random() * 28))::int::text, 2, '0'),
      'coverage_months', 12));
    perform erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'deferred_income', 'description', 'Cobro por adelantado al azar',
      'pl_account_no', '70000001', 'cutoff_date', '2026-12-31', 'total_amount', public.azar(1000, 6000), 'coverage_start', '2026-11-01', 'coverage_months', 6));
    perform erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'accrued_expense', 'description', 'Factura pendiente de recibir',
      'pl_account_no', '62900001', 'cutoff_date', '2026-12-31', 'amount', public.azar(50, 900)));
    perform erp.create_accrual(jsonb_build_object('company_id', e, 'kind', 'accrued_income', 'description', 'Pendiente de facturar',
      'pl_account_no', '70000001', 'cutoff_date', '2026-12-31', 'amount', public.azar(50, 900)));
    for r in select o.invoice_id from erp.open_items(e, '2026-12-31') o where o.invoice_type = 'sale' and o.pending > 0
             order by random() limit 3 loop
      perform erp.impair_receivable(jsonb_build_object('invoice_id', r.invoice_id, 'impair_date', '2026-12-31', 'pct', public.uno(array['50', '100'])));
    end loop;
    begin
      perform erp.impair_receivables_global(jsonb_build_object('company_id', e, 'impair_date', '2026-12-31',
        'rates', '{"d1_90":5,"d91_180":10,"d181_365":25,"d365_plus":50}'::jsonb));
    exception when others then if sqlerrm not like 'Nothing to impair%' then raise; end if;
    end;
    assert (select status from erp.run_audit_checks(e, 2026) where code = 'adjustments_ledger') = 'ok', 'ajustes = 480/485/4009/4309/490';
    -- v0.37.0 · Provisiones, deterioro de un activo e inventario al 31/12
    perform erp.create_provision(jsonb_build_object('company_id', e, 'kind', 'liabilities', 'description', 'Litigio al azar',
      'amount', public.azar(1000, 9000), 'provision_date', '2026-12-31', 'expense_account_no', '67800001'));
    perform erp.create_provision(jsonb_build_object('company_id', e, 'kind', 'commercial', 'description', 'Garantías al azar',
      'amount', public.azar(100, 900), 'provision_date', '2026-12-31'));
    for r in select a.id, erp.asset_net_value_at(a.id, '2026-12-31') as nbv from erp.fixed_assets a
             where a.company_id = e and a.status = 'active' and erp.asset_net_value_at(a.id, '2026-12-31') > 100 order by random() limit 1 loop
      perform erp.impair_asset(jsonb_build_object('asset_id', r.id, 'impairment_date', '2026-12-31', 'recoverable_value', round(r.nbv * 0.7, 2)));
    end loop;
    perform erp.post_inventory(jsonb_build_object('company_id', e, 'count_date', '2026-12-31',
      'lines', jsonb_build_array(jsonb_build_object('account_no', '30000001', 'final_value', public.azar(500, 8000), 'impairment', public.azar(0, 300)))));
    -- v0.38.0 · Nóminas: dos empleados al azar, doce meses, el líquido pagado cada mes y los seguros sociales al mes siguiente
    --   (los de diciembre se quedan en la 476 y se pagan en enero de 2027); un mes se anula y se rehace
    perform erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Empleado ' || k, 'hire_date', '2025-06-01',
      'contract_type', public.uno(array['indefinite', 'temporary']), 'monthly_salary', public.azar(1300, 6500),
      'extra_payments', public.uno(array['0', '2', '2', '3']), 'extra_prorated', random() < 0.5, 'irpf_pct', public.azar(2, 25)))
    from generate_series(1, 2) k;
    for n in 1..12 loop
      select pr.run_id into r from erp.run_payroll(jsonb_build_object('company_id', e, 'period', make_date(2026, n, 1))) pr;
      if n = 5 then perform erp.cancel_payroll(r.run_id); select pr.run_id into r from erp.run_payroll(jsonb_build_object('company_id', e, 'period', '2026-05-31')) pr; end if;
      perform erp.pay_payroll(jsonb_build_object('run_id', r.run_id, 'what', 'net', 'payment_date', (make_date(2026, n, 1) + interval '1 month - 1 day')::date, 'cash_account_no', '57200001'));
      if n < 12 then
        perform erp.pay_payroll(jsonb_build_object('run_id', r.run_id, 'what', 'social_security', 'payment_date', (make_date(2026, n + 1, 1) + interval '1 month - 1 day')::date, 'cash_account_no', '57200001'));
      end if;
    end loop;
    assert (select coalesce(sum(debit_balance - credit_balance), 0) from erp.trial_balance(e, 2026) where account_no like '476%') = -(select sum(s.ss_employee + s.ss_employer) from erp.payslips s join erp.payroll_runs pr on pr.id = s.run_id
                                              where pr.company_id = e and pr.status = 'posted' and pr.period = '2026-12-31'), '476 = seguros sociales de diciembre';
    assert (select coalesce(sum(debit_balance - credit_balance), 0) from erp.trial_balance(e, 2026) where account_no like '465%') = 0,
           '465 a cero: líquidos pagados y las pagas extra devengadas, pagadas en diciembre';
    assert (select string_agg(c.code || '=' || c.status, ' ' order by c.sort) from erp.run_audit_checks(e, 2026) c
            where c.code in ('assets_ledger', 'provisions_ledger', 'inventory_ledger', 'payroll_ledger'))
           = 'assets_ledger=ok provisions_ledger=ok inventory_ledger=ok payroll_ledger=ok',
           (select string_agg(c.code || '=' || c.status || c.details::text, ' ') from erp.run_audit_checks(e, 2026) c
            where c.code in ('assets_ledger', 'provisions_ledger', 'inventory_ledger', 'payroll_ledger'));
    assert (select status from erp.run_audit_checks(e, 2026) where code = 'assets_ledger') = 'ok', 'las fichas cuadran con la 21x / 281';
    assert (select status from erp.run_audit_checks(e, 2026) where code = 'assets_pending') = 'ok', 'todo amortizado al 31/12';
    ok := public.invariantes(e, 2026, 'fin de 2026');
    raise notice 'OK  · % · 2026: % operaciones hechas, % invariantes en verde, 4 liquidaciones sin diferencias', impuesto, hechas, ok;

    -- 2) Cierre del ejercicio: la 129 recibe el resultado y la apertura de 2027 es el cierre de 2026
    perform erp.close_fiscal_year(e, 2026, true);
    ok := public.invariantes(e, 2026, 'tras el cierre');
    assert (select status from erp.integrity_checks(e, 2026) where code = 'result_129') = 'ok', 'el 129 se comprueba';
    assert (select status from erp.integrity_checks(e, 2026) where code = 'opening_closing') = 'ok', 'la apertura se comprueba';
    raise notice 'OK  · % · cierre de 2026: 129 = resultado de la PyG y apertura de 2027 = cierre, cuenta a cuenta', impuesto;

    -- 3) Año 2027: se revierten las periodificaciones en la apertura; más operaciones sobre los saldos abiertos
    assert (select status from erp.run_audit_checks(e, 2027, '2027-01-01') where code = 'accruals_unreversed') = 'warning', 'sin revertir: aviso';
    assert erp.reverse_accruals(e, '2027-01-01') = 4, 'las cuatro periodificaciones se revierten el 01/01';
    hechas := public.operar(e, '2027-01-02', '2027-06-29', 80, impuesto);
    -- …los deterioros de lo que ya se ha cobrado se revierten; uno que siga pendiente, insolvencia firme
    for r in select c.details from erp.run_audit_checks(e, 2027, '2027-06-30') c where c.code = 'impairments_collected' loop
      perform erp.reverse_impairment((x->>'impairment_id')::uuid, '2027-06-30') from jsonb_array_elements(r.details) x;
    end loop;
    for r in select i.invoice_id from erp.receivable_impairments i join erp.open_items(e, '2027-06-30') o on o.invoice_id = i.invoice_id
             where i.company_id = e and i.status = 'active' and o.pending > 0 limit 1 loop
      perform erp.write_off_receivable(jsonb_build_object('invoice_id', r.invoice_id, 'writeoff_date', '2027-06-30'));
    end loop;
    perform erp.reverse_impairment(i.id, '2027-06-30') from erp.receivable_impairments i
    where i.company_id = e and i.method = 'global' and i.status = 'active';
    -- …la provisión del litigio se aplica (sentencia) y la de garantías se revisa
    perform erp.apply_provision(jsonb_build_object('provision_id', pv.id, 'application_date', '2027-06-30',
      'paid', round(erp.provision_balance(pv.id) * (0.8 + random() * 0.4)::numeric, 2), 'cash_account_no', '57200001'))
    from erp.provisions pv where pv.company_id = e and pv.kind = 'liabilities';
    perform erp.revise_provision(jsonb_build_object('provision_id', pv.id, 'review_date', '2027-06-30', 'new_amount', public.azar(100, 900)))
    from erp.provisions pv where pv.company_id = e and pv.kind = 'commercial';
    -- …los seguros sociales de diciembre de 2026, en enero
    perform erp.pay_payroll(jsonb_build_object('run_id', pr.id, 'what', 'social_security', 'payment_date', '2027-01-31', 'cash_account_no', '57200001'))
    from erp.payroll_runs pr where pr.company_id = e and pr.period = '2026-12-31' and pr.status = 'posted';
    assert (select coalesce(sum(debit_balance - credit_balance), 0) from erp.trial_balance(e, 2027) where account_no like '476%') = 0, 'la 476 queda a cero en 2027';
    assert (select status from erp.run_audit_checks(e, 2027, '2027-06-30') where code = 'payroll_ledger') = 'ok', 'nóminas = 465 / 476 en 2027';
    assert (select string_agg(c.code || '=' || c.status, ' ' order by c.sort) from erp.run_audit_checks(e, 2027, '2027-06-30') c
            where c.code in ('assets_ledger', 'provisions_ledger', 'inventory_ledger'))
           = 'assets_ledger=ok provisions_ledger=ok inventory_ledger=ok',
           (select string_agg(c.code || '=' || c.status || c.details::text, ' ') from erp.run_audit_checks(e, 2027, '2027-06-30') c
            where c.code in ('assets_ledger', 'provisions_ledger', 'inventory_ledger'));
    assert (select string_agg(c.code || '=' || c.status, ' ' order by c.sort) from erp.run_audit_checks(e, 2027, '2027-06-30') c
            where c.code in ('adjustments_ledger', 'accruals_unreversed', 'impairments_collected'))
           = 'adjustments_ledger=ok accruals_unreversed=ok impairments_collected=ok',
           (select string_agg(c.code || '=' || c.status || ' ' || c.details::text, ' ') from erp.run_audit_checks(e, 2027, '2027-06-30') c
            where c.code in ('adjustments_ledger', 'accruals_unreversed', 'impairments_collected'));
    ok := public.invariantes(e, 2027, 'en 2027');
    raise notice 'OK  · % · 2027: % operaciones más, % invariantes en verde', impuesto, hechas, ok;
  end loop;
end $$;

-- Un invariante roto se detecta (la comprobación no da siempre «ok»): se rompe a propósito un asiento como superusuario
reset role;
do $$
declare e uuid := (select id from erp.companies where name = 'Azar VAT SL'); l uuid;
begin
  select l2.id into l from erp.journal_lines l2 join erp.journal_entries e2 on e2.id = l2.entry_id
  where e2.company_id = e and e2.status = 'posted' and l2.debit > 0
    and e2.fiscal_year_id = (select id from erp.fiscal_years where company_id = e and year = 2027)
  order by e2.entry_no desc limit 1;
  alter table erp.journal_lines disable trigger user;
  update erp.journal_lines set debit = debit + 0.01 where id = l;
  alter table erp.journal_lines enable trigger user;
  assert (select status from erp.integrity_checks(e, 2027) where code = 'entries_balanced') = 'fail', 'detecta el descuadre';
  assert (select status from erp.integrity_checks(e, 2027) where code = 'trial_balance') = 'fail', 'y en sumas y saldos';
  raise notice 'OK  · si se rompe un asiento a mano (sin las reglas), los invariantes lo detectan';
end $$;

-- Qué ha hecho el azar (para ver que recorre todos los caminos)
select c.name as empresa,
  (select count(*) from erp.invoices i where i.company_id = c.id and document_kind = 'invoice') as facturas,
  (select count(*) from erp.invoices i where i.company_id = c.id and document_kind = 'credit_memo') as rectificativas,
  (select count(*) from erp.invoices i where i.company_id = c.id and withholding_amount <> 0) as con_irpf,
  (select count(*) from erp.v_invoice_register r where r.company_id = c.id and r.rate_category in ('reverse_charge', 'intra_eu_acquisition')) as isp_aib,
  (select count(*) from erp.v_invoice_register r where r.company_id = c.id and r.surcharge_amount <> 0) as recargo,
  (select count(*) from erp.payments p where p.company_id = c.id) as cobros_pagos,
  (select count(*) from erp.journal_entries j where j.company_id = c.id and j.reversal_of is not null) as contraasientos,
  (select count(*) from erp.tax_settlements t where t.company_id = c.id) as liquidaciones,
  (select count(*) from erp.fixed_assets a where a.company_id = c.id) as activos,
  (select count(*) from erp.fixed_assets a where a.company_id = c.id and a.status = 'disposed') as vendidos,
  (select count(*) from erp.accruals a where a.company_id = c.id and a.status = 'reversed') as periodificaciones,
  (select count(*) from erp.receivable_impairments i where i.company_id = c.id) as deterioros,
  (select count(*) from erp.receivable_writeoffs w where w.company_id = c.id) as insolvencias,
  (select count(*) from erp.asset_events v where v.company_id = c.id) as sucesos_activos,
  (select count(*) from erp.provision_movements v where v.company_id = c.id) as mov_provisiones,
  (select count(*) from erp.payroll_runs v where v.company_id = c.id and v.status = 'posted') as nominas
from erp.companies c order by 1;
\echo '✔ FASE 34 OK · invariantes contables con operaciones al azar'
