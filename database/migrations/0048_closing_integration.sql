-- =====================================================================
-- 0048 · FIN DE EJERCICIO II INTEGRADO: comprobaciones, cierre y glosario · v0.37.0
-- ---------------------------------------------------------------------
--   · Comprobaciones (0037) nuevas:
--       provisions_ledger   141 / 142 / 5292 / 5293 / 499 frente a lo que ha contabilizado el módulo de Provisiones
--       provisions_review   al cierre, provisiones vivas que no se han revisado en el ejercicio (NRV 15.ª)
--       inventory_ledger    30-36 / 39 frente a los inventarios del cierre (un asiento manual o un saldo importado)
--     (y «inmovilizado frente a sus fichas» ya vigila la 29x desde la 0046)
--   · Cierre del ejercicio: avisos de inventario sin contabilizar y de provisiones sin revisar
--   · Glosario (0038): «Provisión», «Deterioro del inmovilizado» y «Variación de existencias»
-- Re-ejecutable.
-- =====================================================================

-- 1) Conceptos (generados desde frontend/src/glossary.js con frontend/tests/glossarySql.js)
insert into erp.concepts (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc) values
('provision', 450, 'Provisión', 'Obligación que ya existe por un suceso pasado, cuyo importe o fecha son inciertos (NRV 15.ª): un litigio, un acta, las garantías de lo vendido. Se dota por la mejor estimación, se revisa en cada cierre (más gasto o exceso a la 795) y se aplica al pagar.', 'Demanda probable de 12.000: 678 D 12.000 / 142 H 12.000; si la sentencia es de 14.000 sobre 15.000 provisionados, 1.000 de exceso (7953).', 'Provision', 'An existing obligation from a past event with an uncertain amount or date (PGC rule 15): a lawsuit, a tax assessment, warranties. It is recorded at the best estimate, reviewed at each year end (more expense or excess to 795) and applied when paid.', 'Probable lawsuit of 12,000: 678 Dr 12,000 / 142 Cr 12,000; if the ruling is 14,000 on 15,000 provided, 1,000 excess (7953).', 'Provision (G/L)', 'Provisions (accrual engine)', '{141,142,499,529}'),
('assetImpairment', 460, 'Deterioro del inmovilizado', 'Pérdida de valor de un activo por encima de su amortización: si el valor recuperable es menor que el valor neto contable, la diferencia va a la 69x / 29x (NRV 2.ª). Si se recupera, se revierte (79x) como mucho hasta el valor que tendría sin deterioro.', 'Máquina con valor neto 48.000 y recuperable 40.000: 691 D 8.000 / 2913 H 8.000; desde entonces se amortiza sobre 40.000.', 'Fixed asset impairment', 'A loss of value beyond depreciation: if the recoverable value is below the net book value, the difference goes to 69x / 29x (PGC rule 2). If it recovers, it is reversed (79x) at most up to the value it would have had without the impairment.', 'Machine with a net value of 48,000 and recoverable 40,000: 691 Dr 8,000 / 2913 Cr 8,000; it is then depreciated on 40,000.', 'Write-down', 'Unplanned depreciation', '{290,291,292,690,691,790,791}'),
('inventoryChange', 470, 'Variación de existencias', 'Ajuste del cierre con el método de inventario: se da de baja la existencia inicial y de alta la final del recuento contra la 61x (aprovisionamientos) o la 71x (productos). Así el gasto del año es lo consumido, no lo comprado.', 'Inicial 8.000 + compras 40.000 − final 6.000 = consumo 42.000 (600 40.000 + 610 2.000).', 'Change in inventories', 'A year-end adjustment with the periodic method: the opening stock is removed and the closing count added against 61x (supplies) or 71x (products). So the expense of the year is what was used, not what was bought.', 'Opening 8,000 + purchases 40,000 − closing 6,000 = cost of sales 42,000 (600 40,000 + 610 2,000).', 'Physical inventory', 'Physical inventory / stock change', '{30,31,32,35,39,610,611,612,71}')
on conflict (key) do update set
  sort = excluded.sort, term = excluded.term, definition = excluded.definition, example = excluded.example,
  term_en = excluded.term_en, definition_en = excluded.definition_en, example_en = excluded.example_en,
  bc = excluded.bc, sap = excluded.sap, pgc = excluded.pgc;

-- 2) Comprobaciones nuevas (y la de territorio pasa detrás, para dejar juntas las de contabilidad)
update erp.audit_checks set sort = 65 where code = 'tax_territory';
insert into erp.audit_checks (code, sort, area, severity, title, title_en, why, why_en, fix, fix_en, screen, concept) values
('provisions_ledger', 60, 'ledger', 'warning',
 'Provisiones frente a la contabilidad',
 'Provisions against the books',
 'La 141, 142, 5292, 5293 y 499 solo deben moverse desde el módulo de Provisiones: así cada saldo tiene su ficha, se revisa en el cierre y se aplica al pagar. Un asiento manual o un saldo importado sin ficha queda sin control.',
 'Accounts 141, 142, 5292, 5293 and 499 should only be posted from Provisions: so each balance has its record, is reviewed at year end and applied when paid. A manual entry or an imported balance without a record is out of control.',
 'Da de alta la provisión en Ajustes de cierre (y anula el asiento manual), o revierte el saldo importado que ya no corresponde.',
 'Create the provision in Year-end adjustments (and reverse the manual entry), or reverse the imported balance.',
 'adjustments', 'provision'),
('provisions_review', 61, 'ledger', 'warning',
 'Provisiones sin revisar en el cierre',
 'Provisions not reviewed at year end',
 'Las provisiones se revisan en cada cierre con la mejor estimación de ese momento (NRV 15.ª): si el riesgo ha cambiado, la provisión se ajusta (más gasto o exceso a la 795).',
 'Provisions are reviewed at each year end with the best estimate at that time (PGC rule 15): if the risk has changed, the provision is adjusted (more expense or excess to 795).',
 'En Ajustes de cierre, «Revisar» cada provisión con la estimación del 31/12 (aunque no cambie, escribe la misma… o la nueva).',
 'In Year-end adjustments, «Review» each provision with the estimate at 31/12.',
 'adjustments', 'provision'),
('inventory_ledger', 62, 'ledger', 'warning',
 'Existencias frente a los inventarios',
 'Inventories against the year-end counts',
 'Con el método de inventario, la 30-36 y la 39 solo cambian en el cierre, con el recuento. Si se mueven por otro asiento, el balance no refleja lo que hay en el almacén.',
 'With the periodic method, 30-36 and 39 change only at year end, with the count. If another entry moves them, the balance sheet does not show what is in stock.',
 'Contabiliza el inventario del cierre en Ajustes de cierre y anula el asiento manual (las compras van a la 600-602).',
 'Post the year-end inventory in Year-end adjustments and reverse the manual entry (purchases go to 600-602).',
 'adjustments', 'inventoryChange')
on conflict (code) do update set
  sort = excluded.sort, area = excluded.area, severity = excluded.severity,
  title = excluded.title, title_en = excluded.title_en, why = excluded.why, why_en = excluded.why_en,
  fix = excluded.fix, fix_en = excluded.fix_en, screen = excluded.screen, concept = excluded.concept;

-- 3) Versiones nuevas (copiadas de la vigente; cambia solo lo marcado «v0.37.0»)
CREATE OR REPLACE FUNCTION erp.run_audit_checks(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(code text, sort integer, area text, status text, title text, title_en text, why text, why_en text, fix text, fix_en text, screen text, book numeric, ledger numeric, difference numeric, items integer, details jsonb)
 LANGUAGE plpgsql
 STABLE
AS $function$
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

    elsif r.code = 'assets_ledger' then
      -- v0.35.0 · cada cuenta de inmovilizado (coste de los activos en uso) y de amortización acumulada (lo amortizado)
      --   frente a su saldo contable a la fecha (sin terrenos 210 / 220, que no tienen ficha amortizable)
      with f as (
        select a.asset_account_id as acc, sum(a.cost) as book from erp.fixed_assets a
        where a.company_id = p_company and (a.status = 'active' or a.disposal_date > v_to) and a.acquisition_date <= v_to
        group by 1
        union all
        select a.depreciation_account_id, -sum(d.amount) from erp.fixed_assets a
        join erp.asset_depreciations d on d.asset_id = a.id and d.period_end <= v_to
        where a.company_id = p_company and (a.status = 'active' or a.disposal_date > v_to)
        group by 1
        union all
        -- v0.37.0 · el deterioro (29x) frente al deterioro neto de las fichas
        select (select jl.gl_account_id from erp.journal_lines jl join erp.gl_accounts g2 on g2.id = jl.gl_account_id
                where jl.entry_id = ev.entry_id and g2.account_no like '29%' limit 1),
               -sum(case ev.kind when 'impairment' then ev.amount else -ev.amount end)
        from erp.asset_events ev join erp.fixed_assets a on a.id = ev.asset_id
        where ev.company_id = p_company and ev.kind in ('impairment', 'reversal') and ev.event_date <= v_to
          and (a.status = 'active' or a.disposal_date > v_to)
        group by 1
      ), l as (
        -- saldo acumulado a la fecha: todos los ejercicios, sin los asientos de cierre ni las aperturas del propio ERP
        -- (repetirían saldos); una apertura IMPORTADA sí cuenta
        select g.id as acc, sum(jl.debit - jl.credit) as ledger
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and (left(g.account_no, 2) in ('20', '21', '22', '28') or left(g.account_no, 3) in ('290', '291', '292'))
          and left(g.account_no, 3) not in ('210', '220')
        group by 1
      ), x as (
        select coalesce(f.acc, l.acc) as acc, coalesce(sum(f.book), 0) as book, coalesce(max(l.ledger), 0) as ledger
        from f full join l on l.acc = f.acc group by coalesce(f.acc, l.acc)
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'assets_pending' then
      -- v0.35.0 · activos con amortización pendiente hasta el último fin de mes de la fecha de corte
      -- (último fin de mes: la propia fecha si es fin de mes; si no, el del mes anterior)
      with c as (select (date_trunc('month', v_to + 1) - interval '1 day')::date as cut),
      p as (
        select a.id, a.code, a.name, a.start_date,
               erp.asset_depr_at(a.id, c.cut) - erp.asset_posted(a.id) as pending,
               (select max(d.period_end) from erp.asset_depreciations d where d.asset_id = a.id) as last_period
        from erp.fixed_assets a cross join c
        where a.company_id = p_company and a.status = 'active'
      ), n as (select p.*, row_number() over (order by p.code) as rn from p where p.pending > 0)
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('asset_id', n.id, 'code', n.code, 'name', n.name, 'amount', n.pending,
                                                   'last_period', n.last_period) order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'adjustments_ledger' then
      -- v0.36.0 · 480 / 485 / 4009 / 4309 frente a las periodificaciones vivas y 490 frente a los deterioros vivos, a la fecha
      --   (viva: contabilizada hasta la fecha y aún sin revertir, aplicar ni anular a esa fecha)
      with f as (
        select a.balance_account_id as acc,
               sum(case when a.kind in ('prepaid_expense', 'accrued_income') then a.amount else -a.amount end) as book
        from erp.accruals a
        where a.company_id = p_company and a.cutoff_date <= v_to
          and (a.reversal_date is null or a.reversal_date > v_to)
          and (a.cancel_entry_id is null or (select ce.posting_date from erp.journal_entries ce where ce.id = a.cancel_entry_id) > v_to)
        group by 1
        union all
        select (select g.id from erp.gl_accounts g join erp.journal_lines jl on jl.gl_account_id = g.id
                where jl.entry_id = i.entry_id and g.account_no like '490%' limit 1), -sum(i.amount)
        from erp.receivable_impairments i
        where i.company_id = p_company and i.impair_date <= v_to
          and (i.end_date is null or i.end_date > v_to)
          and (i.cancel_entry_id is null or (select ce.posting_date from erp.journal_entries ce where ce.id = i.cancel_entry_id) > v_to)
        group by 1
      ), l as (
        -- saldo acumulado a la fecha (todos los ejercicios, sin cierres ni aperturas del propio ERP), como assets_ledger
        select g.id as acc, sum(jl.debit - jl.credit) as ledger
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and (g.account_no like '480%' or g.account_no like '485%' or g.account_no like '4009%'
               or g.account_no like '4309%' or g.account_no like '490%')
        group by 1
      ), x as (
        select coalesce(f.acc, l.acc) as acc, coalesce(sum(f.book), 0) as book, coalesce(max(l.ledger), 0) as ledger
        from f full join l on l.acc = f.acc group by coalesce(f.acc, l.acc)
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'accruals_unreversed' then
      -- v0.36.0 · periodificaciones de un ejercicio anterior que siguen sin revertir en este
      with fy as (select f.starting_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year),
      n as (
        select a.id, a.code, a.description, a.cutoff_date, a.amount, row_number() over (order by a.code) as rn
        from erp.accruals a cross join fy
        where a.company_id = p_company and a.status = 'active' and a.cutoff_date < fy.starting_date and fy.starting_date <= v_to
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('accrual_id', n.id, 'code', n.code, 'name', n.description,
                                                   'cutoff_date', n.cutoff_date, 'amount', n.amount) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code in ('provisions_ledger', 'inventory_ledger') then
      -- v0.37.0 · las cuentas de provisiones (141 / 142 / 5292 / 5293 / 499) y de existencias (30-36 / 39) frente a lo
      --   que han contabilizado sus módulos: la diferencia es un asiento manual o un saldo importado sin su ficha
      with lm as (
        select g.id as acc, sum(jl.debit - jl.credit) as amount,
               bool_or(exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
                       or exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id and ic.status = 'posted')) as module
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and case when r.code = 'provisions_ledger'
                   then g.account_no ~ '^(141|142|5292|5293|499)'
                   else g.account_no ~ '^3[0-6]|^39' end
          -- un movimiento anulado y su contraasiento se compensan: ninguno de los dos cuenta como del módulo
          and not (e.reversal_of is not null or e.reversed_by is not null)
        group by g.id, e.id
      ), x as (
        select acc, coalesce(sum(amount) filter (where module), 0) as book, sum(amount) as ledger from lm group by acc
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'provisions_review' then
      -- v0.37.0 · al cierre, provisiones vivas sin revisar en el ejercicio (NRV 15.ª: se revisan en cada cierre)
      with fy as (select f.starting_date, f.ending_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year),
      n as (
        select pv.id, pv.code, pv.description, erp.provision_balance(pv.id) as balance,
               (select max(m.movement_date) from erp.provision_movements m where m.provision_id = pv.id) as last_date,
               row_number() over (order by pv.code) as rn
        from erp.provisions pv cross join fy
        where pv.company_id = p_company and pv.status = 'active' and v_to >= fy.ending_date
          and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date < fy.starting_date)
          and not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                          and m.movement_date between fy.starting_date and fy.ending_date)
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('provision_id', n.id, 'code', n.code, 'name', n.description,
                                                   'amount', n.balance, 'last_date', n.last_date) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'impairments_collected' then
      -- v0.36.0 · deterioro individual vivo de una factura que ya no tiene nada pendiente (cobrada o rectificada)
      with n as (
        select i.id, i.code, i.amount, o.invoice_no, o.partner_name, row_number() over (order by i.code) as rn
        from erp.receivable_impairments i
        join erp.open_items(p_company, v_to) o on o.invoice_id = i.invoice_id
        where i.company_id = p_company and i.method = 'individual' and i.status = 'active' and i.impair_date <= v_to
          and o.pending <= 0
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('impairment_id', n.id, 'code', n.code, 'invoice_no', n.invoice_no,
                                                   'partner_name', n.partner_name, 'amount', n.amount) order by n.rn)
                      filter (where n.rn <= 50), '[]')
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
end $function$
;
;

CREATE OR REPLACE FUNCTION erp.year_closing_preview(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_fy       erp.fiscal_years;
  v_prev     erp.fiscal_years;
  v_next     erp.fiscal_years;
  v_done     erp.year_closings;
  v_checks   jsonb := '[]';
  v_n        int;
  v_txt      text;
  v_result   numeric;
  v_res_no   text := erp.result_account_no(p_company);
  v_pl       jsonb;
  v_close    jsonb;
begin
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then
    raise exception 'Fiscal year % does not exist', p_year;
  end if;
  select * into v_prev from erp.fiscal_years where company_id = p_company and year = p_year - 1;
  select * into v_next from erp.fiscal_years where company_id = p_company and year = p_year + 1;
  select * into v_done from erp.year_closings where fiscal_year_id = v_fy.id and status = 'posted';

  -- 1) COMPROBACIONES · error = impide cerrar · warning = hay que aceptarlo · info = solo informa
  if v_prev.id is not null and v_prev.status = 'open'
     and exists (select 1 from erp.journal_entries where fiscal_year_id = v_prev.id and status = 'posted') then
    v_checks := v_checks || jsonb_build_object('code', 'previous_year_open', 'severity', 'error', 'detail', p_year - 1);
  end if;

  select count(*) into v_n from erp.journal_entries where fiscal_year_id = v_fy.id and status = 'draft';
  if v_n > 0 then
    v_checks := v_checks || jsonb_build_object('code', 'draft_entries', 'severity', 'error', 'detail', v_n);
  end if;

  -- Trimestres de IVA / IGIC sin liquidar (después del cierre ya no se podrán contabilizar)
  select string_agg(x.tax || ' ' || x.q || 'T', ', ' order by x.tax, x.q) into v_txt
  from (select case s.tax_type when 'VAT' then 'IVA' else 'IGIC' end as tax, q
        from erp.tax_settlement_setup s cross join generate_series(1, 4) q
        where s.company_id = p_company
          and not exists (select 1 from erp.tax_settlements t
                          where t.company_id = p_company and t.tax_type = s.tax_type
                            and t.year = p_year and t.quarter = q and t.status = 'posted')) x;
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'unsettled_quarters', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- Saldos anómalos graves (p. ej. caja acreedora): se arrastrarían al año siguiente
  select string_agg(a.account_no, ', ' order by a.account_no) into v_txt
  from erp.balance_anomalies(p_company, p_year) a where a.severity = 'error';
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'anomalies', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.35.0 · Inmovilizado sin amortizar hasta el final del ejercicio (la amortización es un gasto del año: NRV 2.ª)
  select string_agg(a.code, ', ' order by a.code) into v_txt
  from erp.fixed_assets a
  where a.company_id = p_company and a.status = 'active' and a.start_date <= v_fy.ending_date
    and erp.asset_depr_at(a.id, v_fy.ending_date) > erp.asset_posted(a.id);
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'assets_not_depreciated', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.36.0 · Periodificaciones de un ejercicio anterior sin revertir (el gasto o el ingreso se quedaría en el balance)
  select string_agg(a.code, ', ' order by a.code) into v_txt
  from erp.accruals a
  where a.company_id = p_company and a.status = 'active' and a.cutoff_date < v_fy.starting_date;
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'accruals_unreversed', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.37.0 · Inventario sin contabilizar (hay existencias o compras de aprovisionamientos) y provisiones sin revisar
  if not exists (select 1 from erp.inventory_counts c where c.fiscal_year_id = v_fy.id and c.status = 'posted')
     -- (solo si la empresa tiene cuentas de existencias: una de servicios con alguna compra suelta no tiene almacén)
     and exists (select 1 from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting' and g.account_no ~ '^3[0-6]') then
    v_checks := v_checks || jsonb_build_object('code', 'inventory_not_counted', 'severity', 'warning', 'detail', p_year);
  end if;
  select string_agg(pv.code, ', ' order by pv.code) into v_txt
  from erp.provisions pv
  where pv.company_id = p_company and pv.status = 'active'
    and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date < v_fy.starting_date)
    and not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                    and m.movement_date between v_fy.starting_date and v_fy.ending_date);
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'provisions_not_reviewed', 'severity', 'warning', 'detail', v_txt);
  end if;

  if not exists (select 1 from erp.gl_accounts where company_id = p_company and account_no = v_res_no) then
    v_checks := v_checks || jsonb_build_object('code', 'result_account_created', 'severity', 'info', 'detail', v_res_no);
  end if;
  if v_next.id is null then
    v_checks := v_checks || jsonb_build_object('code', 'next_year_created', 'severity', 'info', 'detail', p_year + 1);
  elsif v_next.status = 'closed' then
    v_checks := v_checks || jsonb_build_object('code', 'next_year_closed', 'severity', 'error', 'detail', p_year + 1);
  end if;

  -- 2) REGULARIZACIÓN: cada cuenta de gastos e ingresos se salda al lado contrario; la diferencia, a la 129
  select -coalesce(sum(b.balance), 0),
         coalesce(jsonb_agg(jsonb_build_object('account_no', b.account_no, 'account_name', b.account_name,
                    'debit', greatest(-b.balance, 0), 'credit', greatest(b.balance, 0)) order by b.account_no), '[]')
    into v_result, v_pl
  from erp.year_account_balances(v_fy.id) b
  where left(b.account_no, 1) in ('6', '7');
  if v_result <> 0 then
    v_pl := v_pl || jsonb_build_object('account_no', v_res_no, 'account_name', 'Resultado del ejercicio',
                      'debit', greatest(-v_result, 0), 'credit', greatest(v_result, 0));
  end if;

  -- 3) CIERRE: saldos de balance (grupos 1 a 5) después de la regularización, saldados al lado contrario
  select coalesce(jsonb_agg(jsonb_build_object('account_no', c.account_no, 'account_name', c.account_name,
                    'debit', greatest(-c.balance, 0), 'credit', greatest(c.balance, 0)) order by c.account_no), '[]')
    into v_close
  from (
    select b.account_no, b.account_name,
           b.balance + case when b.account_no = v_res_no then -v_result else 0 end as balance
    from erp.year_account_balances(v_fy.id) b
    where left(b.account_no, 1) between '1' and '5'
    union all   -- la 129 aún sin movimientos
    select v_res_no, 'Resultado del ejercicio', -v_result
    where v_result <> 0
      and not exists (select 1 from erp.year_account_balances(v_fy.id) b where b.account_no = v_res_no)
  ) c
  where c.balance <> 0;

  return jsonb_build_object(
    'year', p_year, 'status', v_fy.status,
    'closing_date', v_fy.ending_date, 'opening_date', v_fy.ending_date + 1,
    'checks', v_checks,
    'can_close', v_fy.status = 'open' and not exists (select 1 from jsonb_array_elements(v_checks) c where c->>'severity' = 'error'),
    'has_warnings', exists (select 1 from jsonb_array_elements(v_checks) c where c->>'severity' = 'warning'),
    'result', coalesce(v_done.result, v_result),
    'result_account_no', v_res_no,
    'closing_pl_lines', v_pl,
    'closing_lines', v_close,
    'closed', v_done.id is not null,
    'closing_id', v_done.id,
    'entries', case when v_done.id is null then null else jsonb_build_object(
       'closing_pl', (select entry_no from erp.journal_entries where id = v_done.closing_pl_entry_id),
       'closing',    (select entry_no from erp.journal_entries where id = v_done.closing_entry_id),
       'opening',    (select entry_no from erp.journal_entries where id = v_done.opening_entry_id)) end,
    'can_reopen', v_done.id is not null and coalesce(v_next.status, 'open') = 'open');
end $function$
;
;

-- Asistente de cierre: el paso del inventario, como el aviso del cierre (copiada de la 0047; cambia lo marcado)
create or replace function erp.closing_checklist(p_company uuid, p_year int)
returns table (step int, code text, status text, detail jsonb, screen text)
language plpgsql stable as $$
declare
  v_fy    erp.fiscal_years;
  v_type  text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
  v_n     int;
  v_m     int;
  v_txt   text;
begin
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found or not erp.can_read(p_company) then return; end if;

  -- 1) Liquidaciones de IVA / IGIC de los cuatro trimestres
  select count(*) into v_n from erp.tax_settlements s
  where s.company_id = p_company and s.year = p_year and s.status = 'posted' and s.tax_type = v_type;
  select count(*) into v_m from erp.invoices i where i.company_id = p_company and i.fiscal_year_id = v_fy.id;
  step := 1; code := 'settlements'; screen := 'settlement';
  status := case when v_n >= 4 then 'done' when v_m = 0 and v_n = 0 then 'na' else 'pending' end;
  detail := jsonb_build_object('settled', v_n, 'tax', v_type); return next;

  -- 2) Periodificaciones del año anterior revertidas
  select count(*) into v_n from erp.accruals a where a.company_id = p_company and a.status = 'active' and a.cutoff_date < v_fy.starting_date;
  step := 2; code := 'accruals_reversed'; screen := 'adjustments';
  status := case when v_n = 0 then 'done' else 'pending' end; detail := jsonb_build_object('pending', v_n); return next;

  -- 3) Amortización del inmovilizado hasta el 31/12
  select count(*), count(*) filter (where erp.asset_depr_at(a.id, v_fy.ending_date) > erp.asset_posted(a.id)) into v_m, v_n
  from erp.fixed_assets a where a.company_id = p_company and a.status = 'active' and a.start_date <= v_fy.ending_date;
  step := 3; code := 'depreciation'; screen := 'assets';
  status := case when v_m = 0 then 'na' when v_n = 0 then 'done' else 'pending' end;
  detail := jsonb_build_object('assets', v_m, 'pending', v_n); return next;

  -- 4) Deterioro del inmovilizado: el valor recuperable lo estima la empresa
  step := 4; code := 'asset_impairment'; screen := 'assets';
  status := case when v_m = 0 then 'na' else 'review' end;
  detail := jsonb_build_object('impaired', (select count(distinct ev.asset_id) from erp.asset_events ev join erp.fixed_assets a on a.id = ev.asset_id
                                            where ev.company_id = p_company and ev.kind = 'impairment' and a.status = 'active')); return next;

  -- 5) Periodificaciones del cierre (las de este año)
  select count(*) into v_n from erp.accruals a where a.company_id = p_company and a.status <> 'cancelled'
    and a.cutoff_date between v_fy.starting_date and v_fy.ending_date;
  step := 5; code := 'accruals'; screen := 'adjustments';
  status := case when v_n > 0 then 'done' else 'review' end; detail := jsonb_build_object('accruals', v_n); return next;

  -- 6) Deterioro de clientes: vencidas hace más de 6 meses sin deterioro, y deterioros de facturas ya cobradas
  select count(*) into v_n from erp.open_items(p_company, v_fy.ending_date) o
  where o.invoice_type = 'sale' and o.pending > 0 and o.due_date + interval '6 months' <= v_fy.ending_date
    and not exists (select 1 from erp.receivable_impairments i where i.invoice_id = o.invoice_id and i.status = 'active');
  select count(*) into v_m from erp.receivable_impairments i join erp.open_items(p_company, v_fy.ending_date) o on o.invoice_id = i.invoice_id
  where i.company_id = p_company and i.status = 'active' and i.method = 'individual' and o.pending <= 0;
  step := 6; code := 'bad_debts'; screen := 'adjustments';
  status := case when v_m > 0 then 'pending' when v_n > 0 then 'review' else 'done' end;
  detail := jsonb_build_object('overdue_6m', v_n, 'collected', v_m); return next;

  -- 7) Provisiones revisadas este año
  select count(*), count(*) filter (where not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                                                      and m.movement_date between v_fy.starting_date and v_fy.ending_date))
  into v_m, v_n from erp.provisions pv where pv.company_id = p_company and pv.status = 'active'
    and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date <= v_fy.ending_date);
  step := 7; code := 'provisions'; screen := 'adjustments';
  status := case when v_m = 0 then 'review' when v_n = 0 then 'done' else 'pending' end;
  detail := jsonb_build_object('active', v_m, 'not_reviewed', v_n); return next;

  -- 8) Inventario del cierre (si hay existencias o compras de aprovisionamientos)
  select count(*) into v_n from erp.inventory_counts c where c.fiscal_year_id = v_fy.id and c.status = 'posted';
  -- v0.37.0 (0048): con cuentas de existencias, falta; sin ellas pero con compras de aprovisionamientos, revisar
  select count(*) into v_m from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting' and g.account_no ~ '^3[0-6]';
  step := 8; code := 'inventory'; screen := 'adjustments';
  status := case when v_n > 0 then 'done' when v_m > 0 then 'pending'
                 when exists (select 1 from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id
                              join erp.gl_accounts g on g.id = l.gl_account_id
                              where e.fiscal_year_id = v_fy.id and e.status = 'posted' and g.account_no ~ '^60[0-2]') then 'review'
                 else 'na' end;
  detail := jsonb_build_object('posted', v_n > 0); return next;

  -- 9) Comprobaciones del auditor sin avisos ni errores
  select count(*), string_agg(c.code, ', ' order by c.sort) into v_n, v_txt
  from erp.run_audit_checks(p_company, p_year, v_fy.ending_date) c where c.status in ('warning', 'error');
  step := 9; code := 'audit_checks'; screen := 'checks';
  status := case when v_n = 0 then 'done' else 'pending' end; detail := jsonb_build_object('open', v_n, 'codes', v_txt); return next;

  -- 10) Cierre del ejercicio (regularización, cierre y apertura)
  step := 10; code := 'close'; screen := 'closing';
  status := case when v_fy.status = 'closed' then 'done' else 'pending' end;
  detail := jsonb_build_object('fiscal_year_status', v_fy.status); return next;
end $$;
