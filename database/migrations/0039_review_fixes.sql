-- =====================================================================
-- 0039 · ARREGLOS DE LA REVISIÓN EXTERNA · v0.33.1
-- ---------------------------------------------------------------------
-- Una revisión externa del proyecto (15-10-2026) encontró dos fallos reales:
--   1) Una 477 (o 472) que NO está configurada en Impuestos quedaba fuera de la liquidación: un apunte en 47700001
--      no entraba en el cuadre del 303 / 420. → tax_settlement_calc incluye toda 472 / 477 sin configurar en el
--      impuesto del territorio de la empresa (IVA en la Península, IGIC en Canarias). Así el cuadre libro registro
--      ↔ contabilidad la detecta y la liquidación la salda.
--   2) Un apunte manual con código IVA21, base 100 y cuota 500 se contabilizaba sin aviso. → nueva comprobación del
--      auditor «tax_quota»: cuota distinta de base × tipo (1 céntimo de tolerancia). En modo estricto ese asiento ya
--      no se puede contabilizar (0036); en guiado y en lo importado, se detecta después, como en un ERP español.
-- Pruebas de regresión: test_fase33_review_fixes.sql. Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Liquidación: también las 472 / 477 sin configurar
-- ---------------------------------------------------------------------
create or replace function erp.tax_settlement_calc(
  p_company uuid, p_tax_type text, p_year int, p_quarter int, p_refund boolean default false)
returns jsonb language plpgsql stable as $$
declare
  v_start    date := erp.quarter_start(p_year, p_quarter);
  v_end      date := erp.quarter_end(p_year, p_quarter);
  v_set      erp.tax_settlement_setup;
  v_out      numeric;
  v_in       numeric;
  v_reg_out  numeric;
  v_reg_in   numeric;
  v_carry    numeric;
  v_applied  numeric := 0;
  v_result   numeric;
  v_final    numeric;
  v_outcome  text;
  v_boxes    jsonb;
  v_lines    jsonb;
  v_done     erp.tax_settlements;
begin
  if p_quarter not between 1 and 4 then
    raise exception 'Invalid quarter: %', p_quarter;
  end if;
  select * into v_set from erp.tax_settlement_setup where company_id = p_company and tax_type = p_tax_type;
  if not found then
    raise exception '% is not set up for this company (Taxes tab)', p_tax_type;
  end if;
  select * into v_done from erp.tax_settlements
  where company_id = p_company and tax_type = p_tax_type and year = p_year and quarter = p_quarter and status = 'posted';

  -- 1) Movimiento del trimestre en las cuentas de impuesto (lo que dice la CONTABILIDAD)
  with acc as (
    select distinct s.output_account_id as id, 'output' as side from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.output_account_id is not null
    union
    select distinct s.input_account_id, 'input' from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.input_account_id is not null
    union   -- recargo de equivalencia repercutido: también se ingresa con el modelo 303
    select distinct s.surcharge_account_id, 'output' from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.surcharge_account_id is not null
    union   -- v0.33.1: las 472 / 477 que NO están configuradas para ningún tipo cuentan en el impuesto del territorio.
            -- Antes un apunte en una 47700001 sin configurar quedaba fuera del cuadre del 303 / 420.
    select g.id, case when g.account_no like '472%' then 'input' else 'output' end
      from erp.gl_accounts g
      where g.company_id = p_company and g.account_type = 'posting'
        and (g.account_no like '472%' or g.account_no like '477%')
        and p_tax_type = (select case tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end
                          from erp.companies where id = p_company)
        and not exists (select 1 from erp.tax_setup s
                        where s.company_id = p_company and g.id in (s.input_account_id, s.output_account_id, s.surcharge_account_id))
  ), mov as (
    select acc.id, acc.side, g.account_no, g.name,
           coalesce(sum(l.debit - l.credit), 0) as balance   -- saldo deudor (+) / acreedor (−) del trimestre
    from acc
    join erp.gl_accounts g on g.id = acc.id
    left join erp.journal_lines l on l.gl_account_id = acc.id
      and exists (select 1 from erp.journal_entries e where e.id = l.entry_id and e.status = 'posted'
                  and e.posting_date between v_start and v_end and not erp.is_settlement_entry(e.id))
    group by acc.id, acc.side, g.account_no, g.name
  )
  select coalesce(sum(-balance) filter (where side = 'output'), 0),
         coalesce(sum(balance)  filter (where side = 'input'), 0),
         coalesce(jsonb_agg(jsonb_build_object('account_no', account_no, 'account_name', name,
                    -- se salda: un saldo deudor se cierra al Haber y uno acreedor al Debe
                    'debit', case when balance < 0 then -balance else 0 end,
                    'credit', case when balance > 0 then balance else 0 end) order by account_no)
                  filter (where balance <> 0), '[]'::jsonb)
    into v_out, v_in, v_lines
  from mov;

  -- 2) Casillas del borrador por tipo, desde el LIBRO REGISTRO de facturas
  select coalesce(jsonb_agg(jsonb_build_object('side', b.side, 'kind', b.kind, 'tax_code', b.tax_code, 'rate_pct', b.rate_pct,
                    'tax_base', b.base, 'tax_amount', b.amount) order by b.side desc, b.kind desc, b.rate_pct desc), '[]'::jsonb),
         coalesce(sum(b.amount) filter (where b.side = 'output'), 0),
         coalesce(sum(b.amount) filter (where b.side = 'input'), 0)
    into v_boxes, v_reg_out, v_reg_in
  from (
    select x.side, x.kind, x.tax_code, x.rate_pct, sum(x.base) as base, sum(x.amount) as amount
    from (
      -- cuota de cada factura: emitidas → devengada · recibidas → deducible (si lo es)
      --   (en compras, solo la parte deducible: prorrata; lo no deducible del recargo de equivalencia no cuenta)
      select case r.invoice_type when 'sale' then 'output' else 'input' end as side, 'tax' as kind,
             r.tax_code, r.rate_pct, r.tax_base as base,
             case r.invoice_type when 'sale' then r.tax_amount else r.deductible_amount end as amount
      from erp.v_invoice_register r
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and (r.invoice_type = 'sale' or r.deductible_amount <> 0 or r.tax_amount = 0)
      union all
      -- inversión del sujeto pasivo y adquisiciones intracomunitarias: la empresa también DEVENGA la cuota
      select 'output', 'reverse_charge', r.tax_code, r.rate_pct, r.tax_base, r.tax_amount
      from erp.v_invoice_register r
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and r.invoice_type = 'purchase' and r.rate_category in ('reverse_charge', 'intra_eu_acquisition')
      union all
      -- recargo de equivalencia repercutido a clientes minoristas
      select 'output', 'surcharge', r.tax_code, c.equivalence_surcharge_pct, r.tax_base, r.surcharge_amount
      from erp.v_invoice_register r
      join erp.tax_codes c on c.code = r.tax_code
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and r.invoice_type = 'sale' and r.surcharge_amount <> 0
      union all
      -- regularización anual de la prorrata (4T): ajuste del IVA deducido al porcentaje definitivo
      select 'input', 'pro_rata', null, pr.definitive_pct, null, pr.regularization_amount
      from erp.pro_rata pr
      join erp.journal_entries je on je.id = pr.entry_id
      where pr.company_id = p_company and pr.tax_type = p_tax_type and je.posting_date between v_start and v_end
    ) x
    group by 1, 2, 3, 4
  ) b;

  -- 3) Cuotas a compensar de periodos anteriores
  select coalesce(sum(case when outcome = 'carry_forward' then -final_result else 0 end), 0)
         - coalesce(sum(carry_applied), 0)
    into v_carry
  from erp.tax_settlements
  where company_id = p_company and tax_type = p_tax_type and status = 'posted'
    and (year, quarter) < (p_year, p_quarter);

  v_result := v_out - v_in;
  if v_result > 0 and v_carry > 0 then
    v_applied := least(v_result, v_carry);
  end if;
  v_final := v_result - v_applied;
  v_outcome := case when v_final > 0 then 'payable'
                    when v_final = 0 then 'zero'
                    when p_quarter = 4 and p_refund then 'refund'
                    else 'carry_forward' end;

  -- 4) Líneas de compensación y resultado
  if v_applied > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.receivable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.receivable_account_id), 'debit', 0, 'credit', v_applied);
  end if;
  if v_final > 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.payable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.payable_account_id), 'debit', 0, 'credit', v_final);
  elsif v_final < 0 then
    v_lines := v_lines || jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_set.receivable_account_id),
      'account_name', (select name from erp.gl_accounts where id = v_set.receivable_account_id), 'debit', -v_final, 'credit', 0);
  end if;

  return jsonb_build_object(
    'tax_type', p_tax_type, 'year', p_year, 'quarter', p_quarter,
    'form', case p_tax_type when 'VAT' then '303' else '420' end,
    'period_start', v_start, 'period_end', v_end,
    'boxes', v_boxes,
    'output_tax', v_out, 'input_tax', v_in,
    'register_output', v_reg_out, 'register_input', v_reg_in,
    -- Cuadre auditor: el libro registro debe coincidir con la contabilidad
    'difference', (v_out - v_in) - (v_reg_out - v_reg_in),
    'result', v_result, 'carry_available', v_carry, 'carry_applied', v_applied,
    'final_result', v_final, 'outcome', v_outcome,
    'can_refund', p_quarter = 4 and v_final < 0,
    'lines', v_lines,
    'settled', v_done.id is not null, 'settlement_id', v_done.id);
end $$;

-- ---------------------------------------------------------------------
-- 2) Comprobación «cuota que no corresponde a base × tipo»
-- ---------------------------------------------------------------------
insert into erp.audit_checks (code, sort, area, severity, title, title_en, why, why_en, fix, fix_en, screen, concept) values
('tax_quota', 25, 'taxes', 'warning',
 'Cuota de IVA / IGIC que no corresponde a base × tipo',
 'VAT / IGIC amount that does not match base × rate',
 'En un apunte de la 472 o la 477 la cuota debe ser la base por el tipo (base 100 al 21 % → 21). Si no, el impuesto está mal calculado o la base está mal anotada, y el modelo 303 / 420 no cuadrará.',
 'In a 472 or 477 line the tax must be the base times the rate (base 100 at 21% → 21). Otherwise the tax is miscalculated or the base is wrong, and the 303 / 420 return will not match.',
 'Anula el asiento (contraasiento) y regístralo desde Facturas: el ERP calcula la cuota solo.',
 'Reverse the entry and register it from Invoices: the ERP calculates the tax itself.',
 'journal', 'taxBase')
on conflict (code) do update set
  sort = excluded.sort, area = excluded.area, severity = excluded.severity,
  title = excluded.title, title_en = excluded.title_en, why = excluded.why, why_en = excluded.why_en,
  fix = excluded.fix, fix_en = excluded.fix_en, screen = excluded.screen, concept = excluded.concept;

create or replace function erp.run_audit_checks(p_company uuid, p_year int, p_to_date date default null)
returns table (code text, sort int, area text, status text, title text, title_en text,
               why text, why_en text, fix text, fix_en text, screen text,
               book numeric, ledger numeric, difference numeric, items int, details jsonb)
language plpgsql stable as $$
declare
  v_to     date := coalesce(p_to_date, (select f.ending_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year));
  v_type   text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
  r        record;
  v_sev    text;
  v_prefix text;
  v_sign   int;
  v_err    boolean;
  v_book numeric; v_ledger numeric; v_items int; v_det jsonb;
begin
  if v_type is null or v_to is null then return; end if;     -- empresa o ejercicio que no existe (o no se puede ver)

  for r in select * from erp.audit_checks c order by c.sort loop
    v_book := null; v_ledger := null; v_items := 0; v_det := '[]'; v_sev := r.severity;

    if r.code in ('vat_input', 'vat_output') then
      -- 472 al Debe (soportado) · 477 al Haber (repercutido); sin liquidación ni prorrata
      v_prefix := case r.code when 'vat_input' then '472' else '477' end;
      v_sign   := case r.code when 'vat_input' then 1 else -1 end;
      select coalesce(sum(v_sign * (a.debit - a.credit)) filter (where a.source = 'invoice'), 0),
             coalesce(sum(v_sign * (a.debit - a.credit)), 0)
      into v_book, v_ledger
      from erp.audit_lines(p_company, p_year, v_to) a
      where a.account_no like v_prefix || '%' and a.source not in ('settlement', 'pro_rata');
      -- Detalle: asientos manuales o importados (cada uno junto con su contraasiento: si se anularon, no salen)
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(v_sign * (a.debit - a.credit)) as amount
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.account_no like v_prefix || '%' and a.source in ('manual', 'import')
        group by a.k, a.source having sum(a.debit - a.credit) <> 0
      ), n as (
        select g.*, e.entry_no, e.posting_date, row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'amount', n.amount)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'tax_quota' then
      -- v0.33.1: apuntes manuales o importados en 472 / 477 con base y tipo, cuya cuota no es base × tipo
      --   (tolerancia de 1 céntimo por redondeo; un asiento ya anulado no cuenta)
      with x as (
        select e.id as entry_id, e.entry_no, e.posting_date,
               case when e.import_batch_id is not null then 'import' else 'manual' end as source,
               g.account_no, l.tax_code, c.rate_pct, l.tax_base,
               abs(l.debit - l.credit) as amount, round(abs(l.tax_base) * c.rate_pct / 100, 2) as expected
        from erp.journal_lines l
        join erp.journal_entries e on e.id = l.entry_id
        join erp.fiscal_years fy on fy.id = e.fiscal_year_id
        join erp.gl_accounts g on g.id = l.gl_account_id
        join erp.tax_codes c on c.code = l.tax_code
        where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
          and e.posting_date <= v_to and e.reversal_of is null
          and not exists (select 1 from erp.journal_entries rv
                          where rv.reversal_of = e.id and rv.status = 'posted' and rv.posting_date <= v_to)
          and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
          and (g.account_no like '472%' or g.account_no like '477%')
          and coalesce(l.tax_base, 0) <> 0
      ), n as (
        select x.*, row_number() over (order by x.posting_date, x.entry_no) as rn
        from x where abs(x.amount - x.expected) > 0.01
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.entry_id, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'tax_code', n.tax_code,
                                                   'rate_pct', n.rate_pct, 'tax_base', n.tax_base,
                                                   'amount', n.amount, 'expected', n.expected)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'withholdings' then
      -- Libro: retenciones practicadas en facturas recibidas (modelos 111 / 115)
      select coalesce(sum(w.withholding_amount), 0) into v_book
      from erp.v_withholding_register w
      where w.company_id = p_company and w.fiscal_year = p_year and w.side = 'withheld' and w.posting_date <= v_to;
      -- Contabilidad: asientos que ABONAN la 4751 (las retenciones). Los que la cargan son el ingreso en Hacienda.
      -- Un contraasiento va con su original (por eso se agrupa por k y el signo es el del original).
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(a.credit - a.debit) as amount,
               (select sum(l.credit - l.debit) from erp.journal_lines l join erp.gl_accounts ga on ga.id = l.gl_account_id
                where l.entry_id = a.k and ga.account_no like '4751%') as original
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.account_no like '4751%'
        group by a.k, a.source
      ), n as (
        select g.*, e.entry_no, e.posting_date,
               row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
        where g.original > 0
      )
      select coalesce(sum(n.amount), 0),
             count(*) filter (where n.source in ('manual', 'import') and n.amount <> 0)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'amount', n.amount)
                                order by n.rn) filter (where n.source in ('manual', 'import') and n.amount <> 0), '[]')
      into v_ledger, v_items, v_det
      from n;

    elsif r.code = 'partners' then
      with x as (
        select 'purchase' as t, a.* from erp.aging(p_company, 'purchase', v_to) a
        union all
        select 'sale', a.* from erp.aging(p_company, 'sale', v_to) a
      ), d as (
        select x.*, row_number() over (order by abs(x.account_balance - x.total) desc, x.partner_name) as rn
        from x where x.account_balance <> x.total
      )
      select coalesce(sum(d.total), 0), coalesce(sum(d.account_balance), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('partner_id', d.partner_id, 'partner_name', d.partner_name,
                                                   'account_no', d.partner_account_no, 'invoice_type', d.t,
                                                   'pending', d.total, 'balance', d.account_balance,
                                                   'amount', d.account_balance - d.total)
                                order by d.rn) filter (where d.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from d;

    elsif r.code = 'anomalies' then
      select count(*)::int, bool_or(b.severity = 'error'),
             coalesce(jsonb_agg(jsonb_build_object('account_no', b.account_no, 'account_name', b.name, 'expected', b.expected,
                                                   'amount', b.balance, 'reclass_to', b.reclass_to, 'severity', b.severity,
                                                   'note', b.note, 'note_en', b.note_en)), '[]')
      into v_items, v_err, v_det
      from erp.balance_anomalies(p_company, p_year, null, v_to) b;
      if v_err then v_sev := 'error'; end if;
      v_det := coalesce((select jsonb_agg(j.d) from jsonb_array_elements(v_det) with ordinality j(d, n) where j.n <= 50), '[]');

    elsif r.code = 'tax_territory' then
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, min(a.tax_code) as tax_code, sum(a.debit - a.credit) as amount
        from erp.audit_lines(p_company, p_year, v_to) a join erp.tax_codes c on c.code = a.tax_code
        where c.tax_type <> v_type
        group by a.k, a.source
        having count(*) filter (where a.entry_id = a.k) > count(*) filter (where a.entry_id <> a.k)  -- sin anular
      ), n as (
        select g.*, e.entry_no, e.posting_date, row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'tax_code', n.tax_code,
                                                   'amount', n.amount)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'controlled' then
      -- Manuales sin anular que tocan una cuenta controlada; no cuentan los vinculados a un pago (ya están conciliados)
      with m as (
        select distinct a.entry_id, a.entry_no, a.posting_date
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.source = 'manual' and a.entry_id = a.k
      ), h as (
        select m.*, erp.entry_controlled_lines(m.entry_id) as hit
        from m
        where not exists (select 1 from erp.journal_entries x
                          where x.reversal_of = m.entry_id and x.status = 'posted' and x.posting_date <= v_to)
          and not exists (select 1 from erp.payments py where py.entry_id = m.entry_id and py.linked)
      ), n as (
        select h.*, row_number() over (order by h.posting_date, h.entry_no) as rn
        from h where jsonb_array_length(h.hit) > 0
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.entry_id, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'account_no', n.hit->0->>'account_no', 'modules', n.hit->0->'modules')
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;
    end if;

    code := r.code; sort := r.sort; area := r.area;
    status := case when coalesce(v_ledger, 0) = coalesce(v_book, 0) and v_items = 0 then 'ok' else v_sev end;
    title := r.title; title_en := r.title_en; why := r.why; why_en := r.why_en; fix := r.fix; fix_en := r.fix_en;
    screen := r.screen; book := v_book; ledger := v_ledger;
    difference := case when v_book is null then null else v_ledger - v_book end;
    items := v_items; details := v_det;
    return next;
  end loop;
end $$;

revoke execute on function erp.run_audit_checks(uuid, int, date) from anon, public;
grant execute on function erp.run_audit_checks(uuid, int, date) to authenticated;
