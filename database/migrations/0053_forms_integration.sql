-- =====================================================================
-- 0053 · MODELOS: integración y BASE DOCUMENTAL · v0.39.0
-- ---------------------------------------------------------------------
--   · Base documental (erp.sources): las fuentes oficiales de cada regla (instrucciones de la AEAT y de la ATC, leyes y
--     reglamentos del BOE), con el enlace, el artículo que se usa y la fecha en que se comprobó. Es la copia de
--     frontend/src/sources.js (generada con frontend/tests/sourcesSql.js); un test vigila que coincidan.
--     Las comprobaciones del auditor (0037) citan sus fuentes (audit_checks.sources).
--   · Comprobaciones nuevas:
--       tax_forms_settlements  el resultado de cada 303 / 420 (libro registro) frente a su liquidación contabilizada
--       form347_missing_vat    terceros del 347 sin NIF
--       sources_review         fuentes oficiales sin revisar en más de un año
--   · Glosario (0038): «Modelo tributario (casillas)» y «Modelo 347».
-- Re-ejecutable.
-- =====================================================================

-- 1) Base documental
create table if not exists erp.sources (
  key       text primary key,
  issuer    text not null check (issuer in ('AEAT', 'ATC', 'BOE')),
  url       text not null check (url like 'https://%'),
  checked   date not null,
  title     text not null,
  ref       text not null,
  title_en  text not null,
  ref_en    text not null
);
comment on table erp.sources is 'Official sources behind the ERP rules (tax agency instructions, laws): link, article used and date checked.';
insert into erp.sources (key, issuer, url, checked, title, ref, title_en, ref_en) values
('aeat303', 'AEAT', 'https://sede.agenciatributaria.gob.es/Sede/todas-gestiones/impuestos-tasas/iva/modelo-303-iva-autoliquidacion_/instrucciones-2026.html', '2026-10-18', 'Modelo 303 · Instrucciones 2026', 'Casillas 01 a 89 y 108 a 124', 'Form 303 · 2026 instructions', 'Boxes 01 to 89 and 108 to 124'),
('aeat390', 'AEAT', 'https://sede.agenciatributaria.gob.es/static_files/Sede/Procedimiento_ayuda/G412/Instrucciones_modelo_390-2025.pdf', '2026-10-18', 'Modelo 390 · Instrucciones (ejercicio 2025)', 'Liquidación, resultado y volumen de operaciones', 'Form 390 · Instructions (2025)', 'Return, result and turnover'),
('aeat390manual', 'AEAT', 'https://sede.agenciatributaria.gob.es/static_files/Sede/Biblioteca/Manual/Practicos/IVA/IVA_2025/Imagenes/Cap_9_390_resumen_anual_es_es.pdf', '2026-10-18', 'Manual práctico de IVA 2025 · Capítulo 9: modelo 390', 'Ejemplo resuelto: casillas por tipo', 'VAT practical guide 2025 · Chapter 9: form 390', 'Worked example: boxes by rate'),
('atc420', 'ATC', 'https://www3.gobiernodecanarias.org/tributos/atc/documents/65729/201004/Instrucciones_modelo_420.pdf/59fbc2b2-7aff-4a68-95ea-4984da563cfc?t=1742821063325', '2026-10-18', 'Modelo 420 · Instrucciones', 'Casillas 01 a 51', 'Form 420 · Instructions', 'Boxes 01 to 51'),
('atc425', 'ATC', 'https://www3.gobiernodecanarias.org/tributos/atc/documents/65729/204267/Instrucciones_modelo_425.pdf/cf497b3d-275e-0bb3-4ffc-67fc70b0ade0?t=1742821251705', '2026-10-18', 'Modelo 425 · Instrucciones', 'Casillas 01 a 134', 'Form 425 · Instructions', 'Boxes 01 to 134'),
('liva', 'BOE', 'https://www.boe.es/eli/es/l/1992/12/28/37/con', '2026-10-18', 'Ley 37/1992, del Impuesto sobre el Valor Añadido', 'Art. 108: bienes de inversión (desde 3.005,06 €)', 'Law 37/1992 on Value Added Tax', 'Art. 108: capital goods (from €3,005.06)'),
('ley20_1991', 'BOE', 'https://www.boe.es/eli/es/l/1991/06/07/20/con', '2026-10-18', 'Ley 20/1991, del Régimen Económico Fiscal de Canarias (IGIC)', 'Art. 40: bienes de inversión (desde 500.000 pesetas = 3.005,06 €)', 'Law 20/1991, Canary Islands tax regime (IGIC)', 'Art. 40: capital goods (from 500,000 pesetas = €3,005.06)'),
('rd1065', 'BOE', 'https://www.boe.es/eli/es/rd/2007/07/27/1065/con', '2026-10-19', 'Real Decreto 1065/2007, de gestión e inspección tributaria', 'Arts. 31 a 35: declaración anual de operaciones con terceros (modelo 347)', 'Royal Decree 1065/2007 on tax management', 'Arts. 31 to 35: annual third-party return (form 347)'),
('aeat347faq', 'AEAT', 'https://sede.agenciatributaria.gob.es/Sede/todas-gestiones/impuestos-tasas/declaraciones-informativas/modelo-347-decla_____racion-anual-operaciones-personas_/preguntas-frecuentes.html', '2026-10-19', 'Modelo 347 · Preguntas frecuentes', 'Rectificaciones e imputación por trimestres', 'Form 347 · FAQ', 'Corrections and quarterly allocation'),
('riva', 'BOE', 'https://www.boe.es/eli/es/rd/1992/12/29/1624/con', '2026-10-19', 'Real Decreto 1624/1992, Reglamento del IVA', 'Arts. 78 a 81: declaración recapitulativa de operaciones intracomunitarias (modelo 349)', 'Royal Decree 1624/1992, VAT Regulation', 'Arts. 78 to 81: EC sales list (form 349)')
on conflict (key) do update set issuer = excluded.issuer, url = excluded.url, checked = excluded.checked, title = excluded.title,
  ref = excluded.ref, title_en = excluded.title_en, ref_en = excluded.ref_en;
alter table erp.sources enable row level security;
drop policy if exists read on erp.sources;
create policy read on erp.sources for select to authenticated using (true);
revoke all on erp.sources from anon, public;
grant select on erp.sources to authenticated;

alter table erp.audit_checks add column if not exists sources text[] not null default '{}';

-- 2) Conceptos (generados desde frontend/src/glossary.js con frontend/tests/glossarySql.js)
insert into erp.concepts (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc) values
('taxForm', 510, 'Modelo tributario (casillas)', 'Impreso oficial con el que se declara un impuesto. Cada importe va en una casilla numerada: en el 303 del IVA, el devengado (01-27), el deducible (28-45) y el resultado (46-71). El ERP lo calcula desde el libro registro y debe coincidir con la liquidación contabilizada.', 'Ventas al 21 % de 11.000: casilla 07 base 11.000, 08 tipo 21, 09 cuota 2.310.', 'Tax form (boxes)', 'The official form used to declare a tax. Each amount goes in a numbered box: in VAT form 303, output tax (01-27), deductible tax (28-45) and the result (46-71). The ERP calculates it from the invoice register and it must match the posted settlement.', 'Sales at 21 % of 11,000: box 07 base 11,000, 08 rate 21, 09 tax 2,310.', 'VAT statement', 'Advance return for tax on sales/purchases', '{472,477,4700,4750}'),
('thirdPartyReturn', 520, 'Modelo 347 (operaciones con terceros)', 'Declaración anual de los clientes y proveedores con los que se han superado 3.005,06 € en el año, IVA incluido, por trimestres. Hacienda la cruza con el 347 del otro: si no coinciden, pide explicaciones. No incluye lo que ya va en otros modelos (349, retenciones).', 'Cliente con 2.420 en el 1T y 1.210 en el 3T: total 3.630 > 3.005,06 → se declara con la clave B.', 'Form 347 (third-party operations)', 'Annual return listing customers and suppliers with more than €3,005.06 in the year, VAT included, by quarter. The tax agency cross-checks it with the other party''s 347. It excludes what other returns already cover (349, withholdings).', 'Customer with 2,420 in Q1 and 1,210 in Q3: total 3,630 > 3,005.06 → declared with key B.', 'Third-party annual return (form 347)', 'Annual return of transactions with third parties', '{400,410,430,440}')
on conflict (key) do update set
  sort = excluded.sort, term = excluded.term, definition = excluded.definition, example = excluded.example,
  term_en = excluded.term_en, definition_en = excluded.definition_en, example_en = excluded.example_en,
  bc = excluded.bc, sap = excluded.sap, pgc = excluded.pgc;

-- 3) Comprobaciones nuevas
insert into erp.audit_checks (code, sort, area, severity, title, title_en, why, why_en, fix, fix_en, screen, concept) values
('tax_forms_settlements', 22, 'taxes', 'warning',
 'Modelos trimestrales frente a las liquidaciones',
 'Quarterly returns against the settlements',
 'El resultado del 303 / 420 sale del libro registro de facturas; la liquidación, de la contabilidad. Tienen que coincidir en cada trimestre liquidado. Si se liquidó aceptando una diferencia, el modelo que se presente no será el que dice la contabilidad.',
 'The 303 / 420 result comes from the invoice register; the settlement, from the books. They must match in every settled quarter. If it was settled accepting a difference, the filed return will not match the books.',
 'Anula la liquidación, corrige el asiento manual de la 472 / 477 que causa la diferencia (Comprobaciones: IVA soportado y repercutido) y vuelve a liquidar.',
 'Cancel the settlement, correct the manual 472 / 477 entry causing the difference (Checks: input and output tax) and settle again.',
 'forms', 'taxForm'),
('form347_missing_vat', 42, 'partners', 'warning',
 'Terceros del modelo 347 sin NIF',
 'Form 347 third parties without tax ID',
 'Los clientes y proveedores con más de 3.005,06 € en el año van al 347 con su NIF: sin él, el modelo no se puede presentar y Hacienda no lo puede cruzar.',
 'Customers and suppliers with more than €3,005.06 in the year go to form 347 with their tax ID: without it the return cannot be filed or cross-checked.',
 'Completa el NIF en la ficha del tercero.',
 'Fill in the tax ID in the third party record.',
 'partners', 'thirdPartyReturn'),
('sources_review', 90, 'taxes', 'info',
 'Fuentes oficiales sin revisar en más de un año',
 'Official sources not reviewed for over a year',
 'Las reglas del ERP se apoyan en instrucciones y normas que cambian (tipos, casillas, límites). Cada fuente guarda la fecha en que se comprobó; pasado un año hay que volver a mirarla.',
 'The ERP rules rely on instructions and laws that change (rates, boxes, thresholds). Each source keeps the date it was checked; after a year it must be reviewed.',
 'Abre la fuente, comprueba que la regla sigue igual y actualiza su fecha (src/sources.js y una migración).',
 'Open the source, check that the rule still holds and update its date (src/sources.js and a migration).',
 'forms', 'taxForm')
on conflict (code) do update set
  sort = excluded.sort, area = excluded.area, severity = excluded.severity,
  title = excluded.title, title_en = excluded.title_en, why = excluded.why, why_en = excluded.why_en,
  fix = excluded.fix, fix_en = excluded.fix_en, screen = excluded.screen, concept = excluded.concept;

-- las fuentes de cada comprobación (las de los impuestos y de los modelos)
update erp.audit_checks set sources = x.sources from (values
  ('vat_input', '{aeat303,atc420}'::text[]), ('vat_output', '{aeat303,atc420}'), ('tax_quota', '{liva,ley20_1991}'),
  ('tax_forms_settlements', '{aeat303,atc420}'), ('form347_missing_vat', '{rd1065,aeat347faq}')) as x(code, sources)
where erp.audit_checks.code = x.code;

-- 4) Versiones nuevas (copiadas de la vigente, 0050; cambia solo lo marcado «v0.39.0»)
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
      -- v0.38.0: más el IRPF de las nóminas (también va al modelo 111, casillas 01 a 03)
      v_book := v_book + coalesce((select sum(s.irpf) from erp.payslips s
                                   join erp.payroll_runs pr on pr.id = s.run_id
                                   join erp.journal_entries je on je.id = pr.entry_id
                                   join erp.fiscal_years f on f.id = je.fiscal_year_id
                                   where pr.company_id = p_company and pr.status = 'posted' and f.year = p_year and pr.period <= v_to), 0);
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

    elsif r.code = 'tax_forms_settlements' then
      -- v0.39.0 · el resultado de cada modelo trimestral (303 / 420, desde el libro registro) frente a su liquidación
      --   contabilizada (desde la contabilidad): un trimestre liquidado aceptando una diferencia
      with q as (
        select g.q, erp.quarter_end(p_year, g.q) as q_end,
               (select b.amount from erp.tax_form_boxes(p_company, p_year, g.q) b where b.box = case v_type when 'VAT' then '46' else '41' end) as form_result,
               (select s.output_tax - s.input_tax from erp.tax_settlements s where s.company_id = p_company and s.tax_type = v_type
                  and s.year = p_year and s.quarter = g.q and s.status = 'posted') as settled
        from generate_series(1, 4) g(q)
        where erp.quarter_end(p_year, g.q) <= v_to
      ), n as (   -- solo los trimestres liquidados (los que faltan por liquidar los avisa el asistente de cierre)
        select q.*, row_number() over (order by q.q) as rn from q
        where q.settled is not null and q.settled <> q.form_result
      )
      select (select coalesce(sum(form_result), 0) from q where settled is not null), (select coalesce(sum(settled), 0) from q), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('quarter', n.q, 'form', case v_type when 'VAT' then '303' else '420' end,
                                                   'form_result', n.form_result, 'settled', n.settled, 'amount', coalesce(n.settled, 0) - n.form_result)
                                order by n.rn), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'form347_missing_vat' then
      -- v0.39.0 · terceros que hay que declarar en el 347 (más de 3.005,06 € en el año) y no tienen NIF
      with n as (select f.*, row_number() over (order by f.partner_name) as rn from erp.form_347(p_company, p_year) f where f.missing_vat_no)
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('partner_id', n.partner_id, 'partner_name', n.partner_name, 'op_key', n.op_key,
                                                   'amount', n.total) order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'sources_review' then
      -- v0.39.0 · fuentes oficiales sin revisar en más de un año (las normas y las instrucciones cambian)
      with n as (select s.*, row_number() over (order by s.checked, s.key) as rn from erp.sources s where s.checked < current_date - interval '1 year')
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('key', n.key, 'name', n.title, 'issuer', n.issuer, 'checked', n.checked) order by n.rn), '[]')
      into v_items, v_det
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

    elsif r.code in ('provisions_ledger', 'inventory_ledger', 'payroll_ledger') then
      -- v0.37.0 · las cuentas de provisiones (141 / 142 / 5292 / 5293 / 499) y de existencias (30-36 / 39) frente a lo
      --   que han contabilizado sus módulos: la diferencia es un asiento manual o un saldo importado sin su ficha
      with lm as (
        select g.id as acc, sum(jl.debit - jl.credit) as amount,
               bool_or(exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
                       or exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id and ic.status = 'posted')
                       -- v0.38.0: la nómina y sus pagos
                       or exists (select 1 from erp.payroll_runs pr where e.id in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id))) as module
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and case r.code when 'provisions_ledger' then g.account_no ~ '^(141|142|5292|5293|499)'
                          when 'payroll_ledger' then g.account_no ~ '^(465|476)'   -- v0.38.0
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
