-- =====================================================================
-- 0059 · IMPUESTO SOBRE SOCIEDADES INTEGRADO: cierre, invariante, cuentas controladas, glosario y supuestos · v0.41.0
-- ---------------------------------------------------------------------
--   · Cierre: el asistente tiene el paso 10 «Impuesto sobre Sociedades» (antes de la regularización, que pasa a ser el
--     11) y la vista previa del cierre avisa si falta: en modo ESTRICTO no deja cerrar (error); en GUIADO, aviso. Después
--     de contabilizarlo, avisa si la 473 no ha quedado a cero.
--   · Invariante 10: el gasto por impuesto de la contabilidad (630) = el de la declaración contabilizada. Con el
--     invariante 4 (la 129 recibe el resultado de la PyG), la 129 = resultado antes de impuestos − (6300 + 6301).
--   · Cuentas controladas: la 630 y la 474 solo las mueve el Impuesto sobre Sociedades. La 4752, la 4709 y la 473, no:
--     el pago o el cobro de Hacienda y los pagos fraccionados se registran con un asiento.
--   · Ajustes propuestos: el concepto ya no lleva importes con punto decimal (van en su columna).
--   · Glosario: «Base imponible», «Diferencia temporaria», «Impuesto corriente» e «Impuesto diferido».
--   · Base documental: la Ley 27/2014 con todos los artículos que se usan.
--   · Catálogo de operaciones y Practicar: el impuesto del ejercicio y dos supuestos (corriente y diferido).
-- Re-ejecutable.
-- =====================================================================

-- 1) Conceptos (generados desde frontend/src/glossary.js con frontend/tests/glossarySql.js)
insert into erp.concepts (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc) values
('taxableBase', 550, 'Base imponible', 'El beneficio sobre el que se paga el Impuesto sobre Sociedades: el resultado contable más o menos los ajustes de lo que la ley del impuesto no deja deducir o deja deducir en otro año (art. 10.3 LIS), menos las bases negativas de años anteriores.', 'Resultado 182.000 + multa 1.000 + exceso de amortización 2.600 = base 185.600.', 'Taxable base', 'The profit on which corporate income tax is paid: the accounting profit plus or minus the adjustments for what the tax law does not allow to deduct, or allows in another year (art. 10.3 LIS), less tax losses from previous years.', 'Profit 182,000 + fine 1,000 + excess depreciation 2,600 = base 185,600.', 'Corporate income tax base (not standard: local add-ons)', 'Taxable income (tax provision)', '{630,4752}'),
('temporaryDifference', 560, 'Diferencia temporaria', 'Un gasto o un ingreso que la contabilidad y el impuesto reconocen en años distintos: hoy no se deduce, pero se deducirá (o al revés). Genera un impuesto diferido; a diferencia de la permanente (una multa), revierte.', 'Amortización contable 5.000 y fiscal 2.400: 2.600 se deducirán en los años siguientes.', 'Temporary difference', 'An expense or income recognised by the accounts and by the tax in different years: not deductible today but deductible later (or the other way round). It creates a deferred tax; unlike a permanent difference (a fine), it reverses.', 'Accounting depreciation 5,000 and tax depreciation 2,400: 2,600 will be deducted in the following years.', 'Deferred tax (temporary difference)', 'Temporary difference (deferred taxes)', '{4740,479}'),
('currentTax', 570, 'Impuesto corriente', 'El Impuesto sobre Sociedades que corresponde pagar por el ejercicio: la cuota íntegra. Se carga a la 6300; lo ya retenido o pagado a cuenta (473) se descuenta y queda la cuota diferencial, a pagar (4752) o a devolver (4709).', 'Cuota 37.976 con 10.000 pagados a cuenta: 6300 D 37.976 / 473 H 10.000 · 4752 H 27.976.', 'Current tax', 'The corporate income tax payable for the year: the gross tax. It is charged to 6300; what was withheld or paid on account (473) is deducted, leaving the amount payable (4752) or refundable (4709).', 'Tax 37,976 with 10,000 paid on account: 6300 Dr 37,976 / 473 Cr 10,000 · 4752 Cr 27,976.', 'Corporate income tax expense (current)', 'Current income tax', '{6300,4752,4709,473}'),
('deferredTax', 580, 'Impuesto diferido', 'La parte del gasto por impuesto que se paga en otros años por las diferencias temporarias y las bases negativas (PGC, NRV 13.ª). Con él, el gasto del año no depende de cuándo se paga: activo 4740 / 4745 o pasivo 479 contra la 6301.', 'Diferencia temporaria de 2.600 al 21 %: 4740 D 546 / 6301 H 546.', 'Deferred tax', 'The part of the tax expense paid in other years because of temporary differences and tax losses (PGC, NRV 13.ª). With it, the expense of the year does not depend on when it is paid: asset 4740 / 4745 or liability 479 against 6301.', 'Temporary difference of 2,600 at 21 %: 4740 Dr 546 / 6301 Cr 546.', 'Deferred tax', 'Deferred taxes', '{6301,4740,4745,479}')
on conflict (key) do update set
  sort = excluded.sort, term = excluded.term, definition = excluded.definition, example = excluded.example,
  term_en = excluded.term_en, definition_en = excluded.definition_en, example_en = excluded.example_en,
  bc = excluded.bc, sap = excluded.sap, pgc = excluded.pgc;

-- 2) Fuente (generada desde frontend/src/sources.js con frontend/tests/sourcesSql.js)
insert into erp.sources (key, issuer, url, checked, title, ref, title_en, ref_en) values
('lis', 'BOE', 'https://www.boe.es/eli/es/l/2014/11/27/27/con', '2026-10-20', 'Ley 27/2014, del Impuesto sobre Sociedades', 'Arts. 10 a 15 (base imponible, amortizaciones, deterioros, provisiones y gastos no deducibles), 26 (bases negativas), 29 y DT 44.ª (tipos) y 101 y 104 (reducida dimensión)', 'Law 27/2014 on Corporate Income Tax', 'Arts. 10 to 15 (taxable base, depreciation, impairments, provisions and non-deductible expenses), 26 (tax losses), 29 and DT 44.ª (rates) and 101 and 104 (reduced size)')
on conflict (key) do update set issuer = excluded.issuer, url = excluded.url, checked = excluded.checked, title = excluded.title,
  ref = excluded.ref, title_en = excluded.title_en, ref_en = excluded.ref_en;

-- 3) Cuentas controladas
insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('630', '{corporate_tax}', 'both', 'Impuesto sobre beneficios: lo contabiliza el Impuesto sobre Sociedades del cierre.', 'Income tax: posted by the corporate income tax at year end.'),
('474', '{corporate_tax}', 'both', 'Activos por impuesto diferido: los mueve el Impuesto sobre Sociedades.', 'Deferred tax assets: posted by the corporate income tax.')
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- 4) Catálogo de operaciones y supuestos
insert into erp.operations (key, sort, title, title_en, screen, entry, entry_en, accounts, concept, sources, description, description_en) values
('corporate_tax', 175, 'Impuesto sobre Sociedades del ejercicio', 'Corporate income tax of the year', 'corporate_tax',
 '6300 D / 473 H · 4752 H (o 4709 D) · diferido: 4740 / 4745 / 6301', '6300 Dr / 473 Cr · 4752 Cr (or 4709 Dr) · deferred: 4740 / 4745 / 6301',
 '{630}', 'currentTax', '{lis,pgc}',
 'Al cierre, antes de la regularización: del resultado contable a la base imponible, la cuota y lo que queda por pagar o devolver, con el impuesto diferido.',
 'At year end, before closing the income statement: from the accounting profit to the taxable base, the tax and what remains to pay or be refunded, with deferred tax.')
on conflict (key) do update set sort = excluded.sort, title = excluded.title, title_en = excluded.title_en, screen = excluded.screen,
  entry = excluded.entry, entry_en = excluded.entry_en, accounts = excluded.accounts, concept = excluded.concept,
  sources = excluded.sources, description = excluded.description, description_en = excluded.description_en;

insert into erp.exercises (key, sort, level, operation, tax_type, title, title_en, statement, statement_en, expected, explanation, explanation_en, errors, sources, concept) values
('corporate_tax_current', 150, 'advanced', 'corporate_tax', null, 'Impuesto sobre Sociedades del año', 'Corporate income tax of the year',
 'Al cierre, la sociedad tiene una base imponible de 100.000 € y tributa al tipo general (25 %). Durante el año pagó 8.000 € a cuenta (pagos fraccionados, cuenta 473). Contabiliza el impuesto corriente.',
 'At year end the company has a taxable base of €100,000 and pays the general rate (25 %). During the year it paid €8,000 on account (instalments, account 473). Record the current tax.',
 '[{"account": "6300", "side": "debit", "amount": 25000}, {"account": "473", "side": "credit", "amount": 8000}, {"account": "4752", "side": "credit", "amount": 17000}]',
 'El gasto es la cuota: 25 % × 100.000 = 25.000 (6300, impuesto corriente). Lo pagado a cuenta (473) se descuenta y queda a ingresar la diferencia: 17.000 en la 4752, que se paga con el modelo 200 en julio.',
 'The expense is the tax: 25 % × 100,000 = 25,000 (6300, current tax). What was paid on account (473) is deducted and the difference is payable: 17,000 in 4752, paid with form 200 in July.',
 '[{"account": "4750", "side": "credit", "msg": "La 4750 es la deuda del IVA; la del Impuesto sobre Sociedades es la 4752.", "msg_en": "4750 is the VAT payable; corporate income tax payable is 4752."},
   {"account": "6301", "side": "debit", "msg": "La 6301 es el impuesto diferido; lo que corresponde pagar por el año es el impuesto corriente (6300).", "msg_en": "6301 is deferred tax; the tax payable for the year is current tax (6300)."},
   {"account": "4709", "side": "debit", "msg": "Sale a pagar (25.000 > 8.000): la diferencia va a la 4752, no a la 4709.", "msg_en": "It is payable (25,000 > 8,000): the difference goes to 4752, not 4709."}]',
 '{lis,pgc}', 'currentTax'),
('corporate_tax_deferred', 160, 'advanced', 'corporate_tax', null, 'Impuesto diferido por la amortización', 'Deferred tax from depreciation',
 'La amortización contable de una máquina ha sido de 5.000 €, pero la ley del impuesto solo deja deducir 2.400 € este año (el máximo de la tabla). La diferencia se deducirá en los años siguientes. Con un tipo del 25 %, contabiliza el impuesto diferido.',
 'The accounting depreciation of a machine was €5,000, but the tax law only allows €2,400 to be deducted this year (the table maximum). The difference will be deducted in the following years. At a 25 % rate, record the deferred tax.',
 '[{"account": "4740", "side": "debit", "amount": 650}, {"account": "6301", "side": "credit", "amount": 650}]',
 'Los 2.600 de amortización que hoy no se deducen (art. 12.1.a LIS) se deducirán después: hoy se paga 2.600 × 25 % = 650 de más, que se recuperará. Es un activo por impuesto diferido (4740) que reduce el gasto por impuesto del año (6301 al Haber, NRV 13.ª).',
 'The 2,600 of depreciation not deductible today (art. 12.1.a LIS) will be deducted later: 2,600 × 25 % = 650 more tax is paid today and will be recovered. It is a deferred tax asset (4740) that reduces the tax expense of the year (6301 credit, NRV 13.ª).',
 '[{"account": "479", "side": "credit", "msg": "Pagas más impuesto ahora y menos después: es un activo (4740), no un pasivo (479).", "msg_en": "You pay more tax now and less later: it is an asset (4740), not a liability (479)."},
   {"account": "6300", "side": "credit", "msg": "El impuesto diferido va a la 6301; la 6300 es el corriente.", "msg_en": "Deferred tax goes to 6301; 6300 is current tax."},
   {"account": "4745", "side": "debit", "msg": "La 4745 es el crédito por bases negativas; una diferencia temporaria va a la 4740.", "msg_en": "4745 is the credit for tax losses; a temporary difference goes to 4740."}]',
 '{lis,pgc}', 'deferredTax')
on conflict (key) do update set sort = excluded.sort, level = excluded.level, operation = excluded.operation, tax_type = excluded.tax_type,
  title = excluded.title, title_en = excluded.title_en, statement = excluded.statement, statement_en = excluded.statement_en,
  expected = excluded.expected, explanation = excluded.explanation, explanation_en = excluded.explanation_en,
  errors = excluded.errors, sources = excluded.sources, concept = excluded.concept;

-- 5) Ajustes propuestos con conceptos limpios (versión de la 0057; cambia solo el texto de los conceptos)
create or replace function erp.corporate_tax_proposals(p_company uuid, p_year int)
returns table (origin text, source_id uuid, kind text, direction text, concept text, amount numeric, article text, included boolean)
language plpgsql stable as $$
declare
  v_fy erp.fiscal_years; v_erd boolean; v_debtors numeric;
  a record; v_acc numeric; v_fm numeric; v_m numeric; v_pend numeric; v_inc numeric; v_dec numeric; v_disposed boolean;
  i record; p record;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  v_erd := (erp.corporate_tax_regime_hint(p_company, p_year)->>'is_erd')::boolean;

  -- a) Amortización contable frente al máximo fiscal (art. 12.1.a). Meses de uso con la misma regla que la contable
  --    (el primer mes, por días); el máximo, sobre el coste.
  for a in select f.*, c.max_pct, c.code as class from erp.fixed_assets f join erp.depreciation_classes c on c.code = f.class_code
           where f.company_id = p_company and f.start_date <= v_fy.ending_date loop
    select coalesce(sum(d.amount), 0) into v_acc from erp.asset_depreciations d
    where d.asset_id = a.id and d.period_end between v_fy.starting_date and v_fy.ending_date;
    v_disposed := a.status = 'disposed' and a.disposal_date between v_fy.starting_date and v_fy.ending_date;
    v_m := erp.asset_months_at(1200, a.start_date, least(v_fy.ending_date, coalesce(a.disposal_date, v_fy.ending_date)))
         - case when a.start_date < v_fy.starting_date then erp.asset_months_at(1200, a.start_date, v_fy.starting_date - 1) else 0 end;
    v_fm := round(erp.asset_cost_at(a.id, v_fy.ending_date) * a.max_pct / 100 * greatest(v_m, 0) / 12, 2);
    v_pend := erp.corporate_tax_pending(p_company, 'depreciation', a.id, p_year);
    if v_acc - v_fm >= 0.01 then
      origin := 'depreciation'; source_id := a.id; kind := 'temporary'; direction := 'increase';
      concept := format('Amortización por encima del máximo fiscal · %s %s (máximo de la tabla: %s %%)', a.code, a.name, trim_scale(a.max_pct));
      amount := v_acc - v_fm; article := 'LIS art. 12.1.a'; included := true; return next;
    elsif v_pend > 0 and (v_disposed or v_fm - v_acc >= 0.01) then
      origin := 'depreciation'; source_id := a.id; kind := 'temporary'; direction := 'decrease';
      concept := case when v_disposed then format('Reversión al dar de baja · %s %s', a.code, a.name)
                      else format('Reversión: amortización contable por debajo del máximo fiscal · %s %s', a.code, a.name) end;
      amount := case when v_disposed then v_pend else least(v_pend, v_fm - v_acc) end;
      article := 'LIS art. 12.1.a'; included := true; return next;
    end if;
  end loop;

  -- b) Deterioro del inmovilizado: no deducible (art. 13.2.a); revierte con su reversión o con la baja
  for a in select f.* from erp.fixed_assets f where f.company_id = p_company
           and exists (select 1 from erp.asset_events e where e.asset_id = f.id and e.kind in ('impairment', 'reversal')) loop
    select coalesce(sum(e.amount) filter (where e.kind = 'impairment'), 0), coalesce(sum(e.amount) filter (where e.kind = 'reversal'), 0)
      into v_inc, v_dec
    from erp.asset_events e where e.asset_id = a.id and e.event_date between v_fy.starting_date and v_fy.ending_date;
    v_pend := erp.corporate_tax_pending(p_company, 'asset_impairment', a.id, p_year);
    v_disposed := a.status = 'disposed' and a.disposal_date between v_fy.starting_date and v_fy.ending_date;
    if v_inc > 0 then
      origin := 'asset_impairment'; source_id := a.id; kind := 'temporary'; direction := 'increase';
      concept := format('Deterioro del inmovilizado · %s %s', a.code, a.name); amount := v_inc;
      article := 'LIS art. 13.2.a'; included := true; return next;
    end if;
    v_dec := least(v_pend + v_inc, case when v_disposed then v_pend + v_inc else v_dec end);
    if v_dec > 0 then
      origin := 'asset_impairment'; source_id := a.id; kind := 'temporary'; direction := 'decrease';
      concept := format('Reversión del deterioro%s · %s %s', case when v_disposed then ' (baja)' else '' end, a.code, a.name);
      amount := v_dec; article := 'LIS art. 13.2.a'; included := true; return next;
    end if;
  end loop;

  -- c) Deterioro de clientes (art. 13.1 y 104)
  select coalesce(sum(o.pending), 0) into v_debtors from erp.open_items(p_company, v_fy.ending_date) o where o.invoice_type = 'sale';
  for i in select ri.*, inv.due_date, inv.invoice_no from erp.receivable_impairments ri left join erp.invoices inv on inv.id = ri.invoice_id
           where ri.company_id = p_company and ri.status <> 'cancelled' loop
    if i.impair_date between v_fy.starting_date and v_fy.ending_date then
      -- deterioro y fin en el mismo año: el gasto (694) y el ingreso (794) se compensan, no hay ajuste
      continue when i.end_date is not null and i.end_date <= v_fy.ending_date;
      if i.method = 'individual' and v_fy.ending_date < (i.due_date + interval '6 months')::date then
        origin := 'receivable_impairment'; source_id := i.id; kind := 'temporary'; direction := 'increase';
        concept := format('Deterioro %s · factura %s: no han pasado 6 meses desde el vencimiento (%s)', i.code, i.invoice_no,
                          to_char(i.due_date, 'DD/MM/YYYY'));
        amount := i.amount; article := 'LIS art. 13.1.a'; included := true; return next;
      elsif i.method = 'global' and greatest(0, i.amount - case when v_erd then round(v_debtors * 0.01, 2) else 0 end) > 0 then
        origin := 'receivable_impairment'; source_id := i.id; kind := 'temporary'; direction := 'increase';
        concept := case when v_erd then format('Deterioro global %s por encima del 1 %% de los deudores', i.code)
                        else format('Deterioro global %s: no deducible', i.code) end;
        amount := i.amount - case when v_erd then round(v_debtors * 0.01, 2) else 0 end;
        article := case when v_erd then 'LIS art. 13.1 y 104' else 'LIS art. 13.1' end; included := true; return next;
      end if;
    elsif i.impair_date < v_fy.starting_date then
      v_pend := erp.corporate_tax_pending(p_company, 'receivable_impairment', i.id, p_year);
      if v_pend > 0 and ((i.end_date is not null and i.end_date between v_fy.starting_date and v_fy.ending_date)
                         or (i.status = 'active' and i.method = 'individual' and v_fy.ending_date >= (i.due_date + interval '6 months')::date)) then
        origin := 'receivable_impairment'; source_id := i.id; kind := 'temporary'; direction := 'decrease';
        concept := case when i.end_date is not null then format('Reversión: el deterioro %s se ha revertido o aplicado', i.code)
                        else format('Reversión: el deterioro %s ya es deducible (6 meses desde el vencimiento)', i.code) end;
        amount := v_pend; article := 'LIS art. 13.1'; included := true; return next;
      end if;
    end if;
  end loop;

  -- d) Provisiones (art. 14): dotaciones del año y, si ya se ajustaron antes, su reversión
  for p in select pr.*, coalesce(sum(greatest(0, m.balance_after - m.balance_before)) filter (where m.kind in ('allocation', 'revision')), 0) as inc,
                  coalesce(sum(greatest(0, m.balance_before - m.balance_after)) filter (where m.kind in ('revision', 'application')), 0) as dec
           from erp.provisions pr
           left join erp.provision_movements m on m.provision_id = pr.id and m.movement_date between v_fy.starting_date and v_fy.ending_date
           where pr.company_id = p_company and pr.status <> 'cancelled'
           group by pr.id loop
    if p.inc > 0 then
      origin := 'provision'; source_id := p.id; kind := 'temporary'; direction := 'increase';
      concept := format('Provisión %s · %s', p.code, p.description); amount := p.inc;
      article := case p.kind when 'commercial' then 'LIS art. 14.9 (garantías: límite por experiencia)'
                             when 'taxes' then 'LIS art. 14 y 15 (deducible salvo el propio IS y las sanciones)'
                             else 'LIS art. 14.1 (deducible si nace de una obligación legal o contractual)' end;
      included := p.kind = 'commercial'; return next;
    end if;
    v_pend := erp.corporate_tax_pending(p_company, 'provision', p.id, p_year);
    if p.dec > 0 and v_pend > 0 then
      origin := 'provision'; source_id := p.id; kind := 'temporary'; direction := 'decrease';
      concept := format('Reversión de la provisión %s (aplicada o revisada a la baja)', p.code); amount := least(v_pend, p.dec);
      article := 'LIS art. 14'; included := true; return next;
    end if;
  end loop;
end $$;

-- 6) Invariante 10 (versión de la 0040 con el nuevo, al final)
create or replace function erp.integrity_checks(p_company uuid, p_year int)
returns table (code text, sort int, status text, expected numeric, actual numeric, detail jsonb, title text, title_en text)
language plpgsql stable as $$
declare
  v_fy    erp.fiscal_years;
  v_close erp.year_closings;
  v_n     int;
  v_a     numeric;
  v_b     numeric;
  v_c     numeric;
  v_d     numeric;
  v_det   jsonb;
  v_cf    jsonb;
begin
  select * into v_fy from erp.fiscal_years f where f.company_id = p_company and f.year = p_year;
  if not found then return; end if;
  select * into v_close from erp.year_closings y where y.company_id = p_company and y.fiscal_year_id = v_fy.id;

  -- 1) Cada asiento cuadra
  select count(*), coalesce(jsonb_agg(x.entry_no order by x.entry_no) filter (where x.rn <= 20), '[]')
    into v_n, v_det
  from (select e.entry_no, row_number() over (order by e.entry_no) rn
        from erp.journal_entries e join erp.journal_lines l on l.entry_id = e.id
        where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
        group by e.id, e.entry_no having sum(l.debit) <> sum(l.credit)) x;
  code := 'entries_balanced'; sort := 10; status := case when v_n = 0 then 'ok' else 'fail' end;
  expected := 0; actual := v_n; detail := v_det;
  title := 'Cada asiento cuadra (Debe = Haber)'; title_en := 'Every entry balances (debit = credit)';
  return next;

  -- 2) Sumas y saldos
  select coalesce(sum(t.total_debit), 0), coalesce(sum(t.total_credit), 0) into v_a, v_b
  from erp.trial_balance(p_company, p_year) t;
  code := 'trial_balance'; sort := 20; status := case when v_a = v_b then 'ok' else 'fail' end;
  expected := v_a; actual := v_b; detail := null;
  title := 'Sumas y saldos: total Debe = total Haber'; title_en := 'Trial balance: total debits = total credits';
  return next;

  -- 3) Activo = Patrimonio neto + Pasivo
  select coalesce(max(f.amount) filter (where f.code = 'ACT'), 0), coalesce(max(f.amount) filter (where f.code = 'PNP'), 0)
    into v_a, v_b
  from erp.financial_statement(p_company, p_year, 'balance') f;
  code := 'balance_sheet'; sort := 30; status := case when v_a = v_b then 'ok' else 'fail' end;
  expected := v_a; actual := v_b; detail := null;
  title := 'Activo = Patrimonio neto + Pasivo'; title_en := 'Assets = Equity + Liabilities';
  return next;

  -- 4) Tras el cierre, la 129 recibe exactamente el resultado de la PyG
  code := 'result_129'; sort := 40; title := 'La regularización lleva a la 129 el resultado de la PyG';
  title_en := 'The closing of the P&L takes the P&L result to account 129'; detail := null;
  if v_close.id is null or v_close.closing_pl_entry_id is null then
    status := 'n/a'; expected := null; actual := null;
  else
    select coalesce(max(f.amount) filter (where f.code = 'PD'), 0) into v_a from erp.financial_statement(p_company, p_year, 'pyg') f;
    select coalesce(sum(l.credit - l.debit), 0) into v_b
    from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
    where l.entry_id = v_close.closing_pl_entry_id and g.account_no like '129%';
    status := case when v_a = v_b then 'ok' else 'fail' end; expected := v_a; actual := v_b;
  end if;
  return next;

  -- 5) Apertura del año siguiente = cierre de este, cuenta a cuenta (cierre + apertura = 0)
  code := 'opening_closing'; sort := 50; title := 'La apertura del año siguiente es el cierre de este, cuenta a cuenta';
  title_en := 'Next year''s opening equals this year''s closing, account by account';
  if v_close.id is null or v_close.closing_entry_id is null or v_close.opening_entry_id is null then
    status := 'n/a'; expected := null; actual := null; detail := null;
  else
    select count(*), coalesce(jsonb_agg(x.account_no order by x.account_no) filter (where x.rn <= 20), '[]') into v_n, v_det
    from (select g.account_no, row_number() over (order by g.account_no) rn
          from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id
          where l.entry_id in (v_close.closing_entry_id, v_close.opening_entry_id)
          group by g.account_no having sum(l.debit - l.credit) <> 0) x;
    status := case when v_n = 0 then 'ok' else 'fail' end; expected := 0; actual := v_n; detail := v_det;
  end if;
  return next;

  -- 6) Asiento + contraasiento = cero, cuenta a cuenta
  select count(*), coalesce(jsonb_agg(x.entry_no order by x.entry_no) filter (where x.rn <= 20), '[]') into v_n, v_det
  from (select o.entry_no, row_number() over (order by o.entry_no) rn
        from erp.journal_entries r
        join erp.journal_entries o on o.id = r.reversal_of
        where r.company_id = p_company and r.fiscal_year_id = v_fy.id and r.status = 'posted'
          and exists (select 1 from erp.journal_lines l where l.entry_id in (r.id, o.id)
                      group by l.gl_account_id having sum(l.debit - l.credit) <> 0)) x;
  code := 'reversals_zero'; sort := 60; status := case when v_n = 0 then 'ok' else 'fail' end;
  expected := 0; actual := v_n; detail := v_det;
  title := 'Un asiento y su contraasiento suman cero'; title_en := 'An entry and its reversal add up to zero';
  return next;

  -- 7) La línea del tercero de cada factura = total − retención (recibida: Haber · emitida: Debe)
  select count(*), coalesce(jsonb_agg(x.invoice_no order by x.invoice_no) filter (where x.rn <= 20), '[]') into v_n, v_det
  from (select i.invoice_no, row_number() over (order by i.invoice_no) rn
        from erp.invoices i
        join erp.business_partners bp on bp.id = i.partner_id
        where i.company_id = p_company and i.fiscal_year_id = v_fy.id
          and (select coalesce(sum(l.debit - l.credit), 0) from erp.journal_lines l
               where l.entry_id = i.entry_id and l.gl_account_id = bp.gl_account_id)
              <> (i.total_amount - i.withholding_amount) * case i.invoice_type when 'sale' then 1 else -1 end) x;
  code := 'invoice_partner'; sort := 70; status := case when v_n = 0 then 'ok' else 'fail' end;
  expected := 0; actual := v_n; detail := v_det;
  title := 'En cada factura, el tercero queda por el total menos la retención';
  title_en := 'In every invoice, the partner is posted at total minus withholding';
  return next;

  -- 8) 472 / 477 de los asientos de las facturas = cuotas del libro registro
  --    477: repercutido de las ventas + recargo de equivalencia + autorrepercusión (ISP, adquisición intracomunitaria)
  --    472: soportado deducible de las compras (con prorrata, solo la parte deducible)
  select coalesce(sum(case when g.account_no like '477%' then l.credit - l.debit else 0 end), 0),
         coalesce(sum(case when g.account_no like '472%' then l.debit - l.credit else 0 end), 0)
    into v_a, v_b
  from erp.invoices i
  join erp.journal_lines l on l.entry_id = i.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id
  where i.company_id = p_company and i.fiscal_year_id = v_fy.id;
  select coalesce(sum(case when r.invoice_type = 'sale' then r.tax_amount + coalesce(r.surcharge_amount, 0)
                           when r.rate_category in ('reverse_charge', 'intra_eu_acquisition') then r.tax_amount
                           else 0 end), 0),
         coalesce(sum(case when r.invoice_type = 'purchase' then r.deductible_amount else 0 end), 0)
    into v_c, v_d
  from erp.v_invoice_register r where r.company_id = p_company and r.fiscal_year = p_year;
  code := 'tax_register'; sort := 80;
  status := case when v_a = v_c and v_b = v_d then 'ok' else 'fail' end;
  expected := v_c + v_d; actual := v_a + v_b;
  detail := jsonb_build_object('ledger_477', v_a, 'register_output', v_c, 'ledger_472', v_b, 'register_input', v_d);
  title := 'Las 472 / 477 de las facturas = las cuotas del libro registro';
  title_en := 'Invoice 472 / 477 postings = the VAT register amounts';
  return next;

  -- 9) Variación de la tesorería = EFE directo = EFE indirecto
  v_cf := erp.cash_flow_check(p_company, p_year);
  v_a := (v_cf->>'cash_change')::numeric;
  v_b := (v_cf->'indirect'->>'total')::numeric;
  v_c := (v_cf->'direct'->>'total')::numeric;
  code := 'cash_flow'; sort := 90; status := case when v_a = v_b and v_a = v_c then 'ok' else 'fail' end;
  expected := v_a; actual := v_b; detail := jsonb_build_object('cash_change', v_a, 'indirect', v_b, 'direct', v_c);
  title := 'Variación de la tesorería (57) = EFE directo = EFE indirecto';
  title_en := 'Change in cash (57) = direct cash flow = indirect cash flow';
  return next;

  -- 10) v0.41.0 · Gasto por impuesto en la contabilidad (630) = el de la declaración contabilizada (corriente + diferido)
  --     Con la regularización, la 129 recibe el resultado antes de impuestos menos ese gasto (invariante 4).
  select (r.result->>'tax_expense')::numeric into v_c from erp.corporate_tax_returns r
  where r.fiscal_year_id = v_fy.id and r.status = 'posted';
  code := 'corporate_tax'; sort := 100;
  if v_c is null then
    status := 'n/a'; expected := null; actual := null; detail := null;
  else
    select coalesce(sum(l.debit - l.credit), 0) into v_a
    from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
      and e.entry_type not in ('closing_pl', 'closing') and g.account_no like '630%';
    status := case when v_a = v_c then 'ok' else 'fail' end; expected := v_c; actual := v_a;
    detail := jsonb_build_object('ledger_630', v_a, 'return_tax_expense', v_c);
  end if;
  title := 'Gasto por impuesto (630) = el de la declaración del Impuesto sobre Sociedades';
  title_en := 'Income tax expense (630) = the corporate income tax return';
  return next;
end $$;

-- 7) Vista previa del cierre (versión de la 0048, marcado «v0.41.0»)
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

  -- v0.41.0 · Impuesto sobre Sociedades: va antes de la regularización (en modo estricto, sin él no se cierra)
  if v_fy.status = 'open' and erp.pre_tax_result(p_company, v_fy.id) <> 0
     and not exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then
    v_checks := v_checks || jsonb_build_object('code', 'corporate_tax_missing',
      'severity', case when (select control_mode from erp.companies where id = p_company) = 'strict' then 'error' else 'warning' end,
      'detail', p_year);
  end if;
  -- …y después de contabilizarlo, la 473 (retenciones y pagos a cuenta) tiene que quedar a cero
  if v_fy.status = 'open' and exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then
    select string_agg(g.account_no, ', ') into v_txt from (
      select g.account_no from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
      where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted' and e.entry_type not in ('closing_pl', 'closing')
        and g.account_no like '473%' group by g.account_no having sum(l.debit - l.credit) <> 0) g;
    if v_txt is not null then
      v_checks := v_checks || jsonb_build_object('code', 'withholdings_left', 'severity', 'warning', 'detail', v_txt);
    end if;
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

-- 8) Asistente de cierre (versión de la 0048 con el paso 10 nuevo)
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

  -- 10) v0.41.0 · Impuesto sobre Sociedades (antes de la regularización)
  step := 10; code := 'corporate_tax'; screen := 'corporate_tax';
  status := case when exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then 'done'
                 when erp.pre_tax_result(p_company, v_fy.id) = 0 then 'na' else 'pending' end;
  detail := jsonb_build_object('pre_tax_result', erp.pre_tax_result(p_company, v_fy.id)); return next;

  -- 11) Cierre del ejercicio (regularización, cierre y apertura)
  step := 11; code := 'close'; screen := 'closing';
  status := case when v_fy.status = 'closed' then 'done' else 'pending' end;
  detail := jsonb_build_object('fiscal_year_status', v_fy.status); return next;
end $$;
