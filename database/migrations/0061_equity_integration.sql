-- =====================================================================
-- 0061 · OPERACIONES SOCIETARIAS INTEGRADAS: impuesto, cierre, auditor, cuentas controladas, glosario y supuestos · v0.42.0
-- ---------------------------------------------------------------------
--   · Facturas recibidas: una línea puede ir a la 113 (gastos de constitución o de ampliación, contra reservas: NRV 9.ª).
--   · Impuesto sobre Sociedades: esos gastos se proponen como ajuste deducible (LIS art. 11.3) y el impuesto que ahorran
--     va también a reservas (113 H) en el asiento del impuesto corriente; la 6300 es el impuesto de la base sin ellos.
--   · Cierre: aviso si el resultado del año anterior sigue sin repartir (la 129 con saldo).
--   · Auditor: la 47512 (retenciones de dividendos, modelo 123) no entra en la comprobación de la 4751 con el 111 / 115.
--   · Cuentas controladas: 190, 194, 1030, 5580, 526 y 557 solo las mueven las operaciones societarias. La 100, la 112 y
--     la 113, no (el asiento de apertura de una empresa que ya existía las necesita).
--   · Glosario: «Reserva legal», «Dividendo a cuenta», «Prima de emisión» y «Desembolsos pendientes».
--   · Base documental: la Ley de Sociedades de Capital (RDLeg 1/2010).
--   · Catálogo de operaciones y Practicar: el capital y el reparto del resultado, con dos supuestos.
-- Re-ejecutable.
-- =====================================================================

-- 0) El saldo de las operaciones societarias (0060), sin «security definer»: lo usa también la vista previa del cierre
--    con los permisos de quien la mira (RLS), así que solo ve sus empresas
create or replace function erp.equity_bal(p_company uuid, p_prefix text, p_date date)
returns numeric language sql stable security invoker set search_path = erp, public as $$
  select coalesce(sum(l.credit - l.debit), 0)
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  join erp.fiscal_years f on f.id = e.fiscal_year_id
  where e.company_id = p_company and e.status = 'posted' and e.entry_type not in ('closing', 'closing_pl')
    and p_date between f.starting_date and f.ending_date and e.posting_date <= p_date and g.account_no like p_prefix || '%';
$$;
grant execute on function erp.equity_bal(uuid, text, date) to authenticated;

-- 1) Conceptos (generados desde frontend/src/glossary.js con frontend/tests/glossarySql.js)
insert into erp.concepts (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc) values
('legalReserve', 590, 'Reserva legal', 'La parte del beneficio que la ley obliga a guardar: el 10 % hasta que llegue al 20 % del capital (art. 274 LSC); en una SL de menos de 3.000 € de capital, al menos el 20 % hasta que capital y reserva sumen 3.000 (art. 4.2). No se reparte como dividendo.', 'Capital 30.000, reserva 4.000, beneficio 50.000: 10 % = 5.000, pero solo faltan 2.000 para el 20 % → 112 H 2.000.', 'Legal reserve', 'The part of the profit the law requires to keep: 10 % until it reaches 20 % of the share capital (art. 274 LSC); in an SL with less than €3,000 of capital, at least 20 % until capital and reserve add up to 3,000 (art. 4.2). It is not paid out as dividends.', 'Capital 30,000, reserve 4,000, profit 50,000: 10 % = 5,000, but only 2,000 is missing to reach 20 % → 112 Cr 2,000.', 'Legal reserve (G/L account)', 'Legal reserve (equity account)', '{112}'),
('interimDividend', 600, 'Dividendo a cuenta', 'Dividendo que se paga antes de que la junta apruebe las cuentas, a cuenta del beneficio del año. Solo hasta el resultado desde el último cierre menos las pérdidas anteriores, la reserva legal y el impuesto estimado, y con liquidez (art. 277 LSC). La 557 resta del patrimonio neto hasta la junta.', 'Resultado a 30/09: 40.000; impuesto 10.000; reserva 3.000 → máximo 27.000. Acuerdo: 557 D 20.000 / 526 H 20.000.', 'Interim dividend', 'A dividend paid before the general meeting approves the accounts, on account of the profit of the year. Only up to the result since the last year end less prior losses, the legal reserve and the estimated tax, and with enough cash (art. 277 LSC). Account 557 reduces equity until the meeting.', 'Result at 30/09: 40,000; tax 10,000; reserve 3,000 → maximum 27,000. Resolution: 557 Dr 20,000 / 526 Cr 20,000.', 'Interim dividend (G/L account)', 'Interim dividend', '{557,526}'),
('sharePremium', 610, 'Prima de emisión', 'Lo que pagan los socios por encima del valor nominal al suscribir acciones o participaciones nuevas (110). Es patrimonio neto, no capital: compensa a los socios antiguos por las reservas que ya había.', 'Acciones de 10 € de nominal emitidas a 12 €: por cada una, 10 a la 100 y 2 a la 110.', 'Share premium', 'What shareholders pay above the nominal value when subscribing new shares (110). It is equity, not share capital: it compensates existing shareholders for the reserves already accumulated.', 'Shares of €10 nominal issued at €12: for each one, 10 to 100 and 2 to 110.', 'Share premium (G/L account)', 'Capital reserve (share premium)', '{110}'),
('uncalledCapital', 620, 'Desembolsos pendientes', 'Capital suscrito que los socios aún no han pagado. En la SA puede quedar pendiente hasta el 75 % (art. 79 LSC); en la SL, no. No exigido: 1030 (resta del patrimonio neto); exigido y sin cobrar: 5580 (un derecho de cobro).', 'SA de 60.000 con el 25 % pagado: 572 D 15.000 · 1030 D 45.000 / 190 H 60.000.', 'Uncalled share capital', 'Subscribed capital that shareholders have not paid yet. In an SA up to 75 % can remain unpaid (art. 79 LSC); not in an SL. Not called: 1030 (reduces equity); called and unpaid: 5580 (a receivable).', 'SA of 60,000 with 25 % paid: 572 Dr 15,000 · 1030 Dr 45,000 / 190 Cr 60,000.', 'Uncalled share capital', 'Subscribed capital unpaid', '{1030,5580,190,194}')
on conflict (key) do update set
  sort = excluded.sort, term = excluded.term, definition = excluded.definition, example = excluded.example,
  term_en = excluded.term_en, definition_en = excluded.definition_en, example_en = excluded.example_en,
  bc = excluded.bc, sap = excluded.sap, pgc = excluded.pgc;

-- 2) Fuente (generada desde frontend/src/sources.js con frontend/tests/sourcesSql.js)
insert into erp.sources (key, issuer, url, checked, title, ref, title_en, ref_en) values
('lsc', 'BOE', 'https://www.boe.es/eli/es/rdlg/2010/07/02/1/con', '2026-10-21', 'Real Decreto Legislativo 1/2010, Ley de Sociedades de Capital', 'Arts. 4 (capital mínimo; SL de menos de 3.000 €, Ley 18/2022), 78 y 79 (desembolso), 273, 274 y 277 (reparto, reserva legal y dividendo a cuenta), 295 a 304 (aumento) y 317 a 322 (reducción por pérdidas)', 'Royal Legislative Decree 1/2010, Spanish Companies Act (LSC)', 'Arts. 4 (minimum capital; SL under €3,000, Law 18/2022), 78 and 79 (payment), 273, 274 and 277 (distribution, legal reserve and interim dividend), 295 to 304 (increase) and 317 to 322 (reduction for losses)')
on conflict (key) do update set issuer = excluded.issuer, url = excluded.url, checked = excluded.checked, title = excluded.title,
  ref = excluded.ref, title_en = excluded.title_en, ref_en = excluded.ref_en;

-- 3) Cuentas controladas
insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('190', '{equity}', 'both', 'Acciones o participaciones emitidas: las mueven la constitución y las ampliaciones de capital.', 'Shares issued: posted by incorporation and capital increases.'),
('194', '{equity}', 'both', 'Capital pendiente de inscripción: lo mueven la constitución y las ampliaciones de capital.', 'Capital pending registration: posted by incorporation and capital increases.'),
('1030', '{equity}', 'both', 'Desembolsos no exigidos: los mueven el capital y los dividendos pasivos.', 'Uncalled capital: posted by capital operations and calls.'),
('5580', '{equity}', 'both', 'Desembolsos exigidos: los mueven los dividendos pasivos.', 'Called-up capital receivable: posted by calls.'),
('526', '{equity}', 'both', 'Dividendo a pagar: lo mueven el reparto del resultado, el dividendo a cuenta y su pago.', 'Dividend payable: posted by the distribution, interim dividends and their payment.'),
('557', '{equity}', 'both', 'Dividendo a cuenta: lo mueven el dividendo a cuenta y el reparto del resultado.', 'Interim dividend: posted by interim dividends and the distribution.')
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- 4) Catálogo de operaciones y supuestos
insert into erp.operations (key, sort, title, title_en, screen, entry, entry_en, accounts, concept, sources, description, description_en) values
('share_capital', 185, 'Constitución o ampliación de capital', 'Incorporation or capital increase', 'equity',
 '190 / 194 → 572 + 1030 / 190 → 194 / 100 (y 110 si hay prima)', '190 / 194 → 572 + 1030 / 190 → 194 / 100 (and 110 if there is a premium)',
 '{100,1030,190}', 'uncalledCapital', '{lsc,pgc}',
 'La emisión, la suscripción y el desembolso, y la inscripción en el Registro Mercantil, con lo no desembolsado en la 1030.',
 'Issue, subscription and payment, and registration, with the unpaid part in 1030.'),
('profit_distribution', 186, 'Reparto del resultado (junta)', 'Distribution of the result (general meeting)', 'equity',
 '129 D / 121 H · 112 H · 557 H · 526 H · 113 H (pérdida: 121 D / 129 H)', '129 Dr / 121 Cr · 112 Cr · 557 Cr · 526 Cr · 113 Cr (loss: 121 Dr / 129 Cr)',
 '{129,112,526}', 'legalReserve', '{lsc,pgc}',
 'La junta reparte el resultado del año anterior: primero compensa pérdidas, después la reserva legal, el dividendo y el resto a reservas.',
 'The general meeting distributes last year''s result: losses first, then the legal reserve, the dividend and the rest to reserves.')
on conflict (key) do update set sort = excluded.sort, title = excluded.title, title_en = excluded.title_en, screen = excluded.screen,
  entry = excluded.entry, entry_en = excluded.entry_en, accounts = excluded.accounts, concept = excluded.concept,
  sources = excluded.sources, description = excluded.description, description_en = excluded.description_en;

insert into erp.exercises (key, sort, level, operation, tax_type, title, title_en, statement, statement_en, expected, explanation, explanation_en, errors, sources, concept) values
('sa_incorporation', 170, 'advanced', 'share_capital', null, 'Constitución de una SA con desembolso pendiente', 'Incorporation of an SA with unpaid capital',
 'Se constituye una SA con 60.000 € de capital. Los socios pagan por banco el 25 % y el resto queda pendiente, sin exigir. Contabiliza el resultado final, ya inscrita en el Registro Mercantil (en un solo asiento).',
 'An SA is incorporated with €60,000 of share capital. The shareholders pay 25 % by bank and the rest remains unpaid, not yet called. Record the final result, already registered (in a single entry).',
 '[{"account": "572", "side": "debit", "amount": 15000}, {"account": "1030", "side": "debit", "amount": 45000}, {"account": "100", "side": "credit", "amount": 60000}]',
 'La SA tiene que tener desembolsado al menos el 25 % (art. 79 LSC): 15.000 entran en el banco y los 45.000 no exigidos van a la 1030, que resta del patrimonio neto. Paso a paso son tres asientos: emisión (190 / 194), suscripción (572 + 1030 / 190) e inscripción (194 / 100); el resultado es este.',
 'An SA must have at least 25 % paid (art. 79 LSC): 15,000 goes to the bank and the 45,000 not called goes to 1030, which reduces equity. Step by step there are three entries: issue (190 / 194), subscription (572 + 1030 / 190) and registration (194 / 100); this is the result.',
 '[{"account": "5580", "side": "debit", "msg": "La 5580 es lo que ya se ha exigido a los socios y no han pagado; lo que aún no se ha exigido va a la 1030.", "msg_en": "5580 is what has been called and not paid; what has not been called yet goes to 1030."},
   {"account": "440", "side": "debit", "msg": "Los socios no son deudores comerciales: lo pendiente de desembolsar va a la 1030.", "msg_en": "Shareholders are not trade debtors: the unpaid capital goes to 1030."},
   {"account": "100", "side": "debit", "msg": "El capital es patrimonio neto: va al Haber.", "msg_en": "Share capital is equity: it goes to the credit side."}]',
 '{lsc,pgc}', 'uncalledCapital'),
('profit_distribution', 180, 'advanced', 'profit_distribution', null, 'Reparto del beneficio con reserva legal', 'Distribution of the profit with legal reserve',
 'Una SL con 20.000 € de capital y 3.000 € de reserva legal aprueba en junta el reparto del beneficio de 40.000 € del año anterior: dividendo de 20.000 € y el resto a reservas voluntarias. Contabiliza el acuerdo de la junta.',
 'An SL with €20,000 of share capital and €3,000 of legal reserve approves the distribution of last year''s €40,000 profit: a €20,000 dividend and the rest to voluntary reserves. Record the resolution.',
 '[{"account": "129", "side": "debit", "amount": 40000}, {"account": "112", "side": "credit", "amount": 1000}, {"account": "526", "side": "credit", "amount": 20000}, {"account": "113", "side": "credit", "amount": 19000}]',
 'Reserva legal (art. 274 LSC): el 10 % del beneficio (4.000) hasta llegar al 20 % del capital (4.000); como ya hay 3.000, solo falta 1.000. El dividendo acordado se debe a los socios (526) hasta que se paga, y el resto, 19.000, va a reservas voluntarias. La retención del 19 % se practica al pagar.',
 'Legal reserve (art. 274 LSC): 10 % of the profit (4,000) until it reaches 20 % of capital (4,000); as there is already 3,000, only 1,000 is missing. The dividend is owed to the shareholders (526) until paid, and the remaining 19,000 goes to voluntary reserves. The 19 % withholding is applied on payment.',
 '[{"account": "129", "side": "credit", "msg": "La 129 tiene saldo acreedor (el beneficio): al repartirlo se salda cargándola (Debe).", "msg_en": "Account 129 has a credit balance (the profit): distributing it debits it."},
   {"account": "557", "side": "credit", "msg": "La 557 es el dividendo a cuenta; aquí no lo hay: el dividendo acordado se debe en la 526.", "msg_en": "557 is the interim dividend; there is none here: the dividend owed goes to 526."},
   {"account": "4751", "side": "credit", "msg": "La retención se practica al pagar el dividendo, no al acordarlo.", "msg_en": "The withholding is applied when the dividend is paid, not when it is approved."}]',
 '{lsc,pgc}', 'legalReserve')
on conflict (key) do update set sort = excluded.sort, level = excluded.level, operation = excluded.operation, tax_type = excluded.tax_type,
  title = excluded.title, title_en = excluded.title_en, statement = excluded.statement, statement_en = excluded.statement_en,
  expected = excluded.expected, explanation = excluded.explanation, explanation_en = excluded.explanation_en,
  errors = excluded.errors, sources = excluded.sources, concept = excluded.concept;

-- 5) Ajustes del impuesto: el origen nuevo
alter table erp.corporate_tax_adjustments drop constraint if exists corporate_tax_adjustments_origin_check;
alter table erp.corporate_tax_adjustments add constraint corporate_tax_adjustments_origin_check
  check (origin in ('depreciation', 'asset_impairment', 'receivable_impairment', 'provision', 'equity_costs', 'manual'));

-- 6) Ajustes propuestos (versión de la 0059 con el apartado f)
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
  -- f) v0.42.0 · Gastos de constitución y de ampliación de capital cargados a reservas (NRV 9.ª, apdo. 4): no pasan por
  --    la PyG pero son deducibles (LIS art. 11.3: solo no lo son si una norma lo dice). Uno por factura recibida a la 113.
  for i in select inv.id, coalesce(inv.external_document_no, inv.invoice_no) as doc, sum(l.debit - l.credit) as amount
           from erp.invoices inv join erp.journal_entries e on e.id = inv.entry_id
           join erp.journal_lines l on l.entry_id = e.id join erp.gl_accounts g on g.id = l.gl_account_id
           where inv.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted' and e.reversed_by is null
             and g.account_no like '113%'
           group by inv.id, inv.external_document_no, inv.invoice_no having sum(l.debit - l.credit) > 0 loop
    origin := 'equity_costs'; source_id := i.id; kind := 'permanent'; direction := 'decrease';
    concept := format('Gastos de constitución o ampliación cargados a reservas (113) · factura %s', i.doc);
    amount := i.amount; article := 'LIS art. 11.3'; included := true; return next;
  end loop;
end $$;

-- 7) Cálculo del impuesto (versión de la 0057 con el efecto en reservas, marcado «v0.42.0»)
CREATE OR REPLACE FUNCTION erp.corporate_tax_calc(p_company uuid, p_year integer, p_regime text DEFAULT NULL::text, p_recognize boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_fy erp.fiscal_years; v_ret erp.corporate_tax_returns; v_hint jsonb; v_regime text; v_recognize boolean;
  v_adj jsonb; v_result numeric; v_perm numeric; v_tinc numeric; v_tdec numeric; v_prev numeric;
  v_limit numeric; v_avail numeric; v_comp numeric := 0; v_usage jsonb := '[]'; v_left numeric; b record;
  v_base numeric; v_q jsonb; v_quota numeric; v_rate numeric; v_wh numeric; v_diff numeric;
  v_loss numeric; v_credit numeric; v_credit_used numeric := 0; v_def numeric; v_warn jsonb := '[]';
  v_eq numeric; v_eqtax numeric := 0;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  select * into v_ret from erp.corporate_tax_returns where fiscal_year_id = v_fy.id;
  if v_ret.status = 'posted' then return v_ret.result || jsonb_build_object('status', 'posted', 'return_id', v_ret.id); end if;
  v_hint := erp.corporate_tax_regime_hint(p_company, p_year);
  v_regime := coalesce(p_regime, v_ret.regime, v_hint->>'suggested');
  v_recognize := coalesce(p_recognize, v_ret.recognize_loss_credit, false);

  -- ajustes: los de la declaración (borrador) o los propuestos
  if v_ret.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'origin', a.origin, 'source_id', a.source_id, 'kind', a.kind,
             'direction', a.direction, 'concept', a.concept, 'amount', a.amount, 'article', a.article, 'included', a.included,
             'auto', a.auto) order by a.auto desc, a.origin, a.created_at), '[]') into v_adj
    from erp.corporate_tax_adjustments a where a.return_id = v_ret.id;
  else
    select coalesce(jsonb_agg(jsonb_build_object('id', null, 'origin', x.origin, 'source_id', x.source_id, 'kind', x.kind,
             'direction', x.direction, 'concept', x.concept, 'amount', x.amount, 'article', x.article, 'included', x.included,
             'auto', true)), '[]') into v_adj
    from erp.corporate_tax_proposals(p_company, p_year) x;
  end if;

  v_result := erp.pre_tax_result(p_company, v_fy.id);
  select coalesce(sum(case x->>'direction' when 'increase' then 1 else -1 end * (x->>'amount')::numeric) filter (where x->>'kind' = 'permanent'), 0),
         coalesce(sum((x->>'amount')::numeric) filter (where x->>'kind' = 'temporary' and x->>'direction' = 'increase'), 0),
         coalesce(sum((x->>'amount')::numeric) filter (where x->>'kind' = 'temporary' and x->>'direction' = 'decrease'), 0)
    into v_perm, v_tinc, v_tdec
  from jsonb_array_elements(v_adj) x where (x->>'included')::boolean;
  v_prev := v_result + v_perm + v_tinc - v_tdec;

  -- compensación de bases negativas (art. 26.1): hasta el 70 % de la base previa, y en todo caso 1 millón
  select coalesce(sum(pending), 0) into v_avail from erp.corporate_tax_loss_carryforwards(p_company, p_year);
  v_limit := case when v_prev > 0 then greatest(round(v_prev * 0.70, 2), least(v_prev, 1000000)) else 0 end;
  v_left := least(v_avail, v_limit, greatest(v_prev, 0));
  for b in select * from erp.corporate_tax_loss_carryforwards(p_company, p_year) loop
    exit when v_left <= 0;
    v_usage := v_usage || jsonb_build_object('origin_year', b.origin_year, 'amount', least(b.pending, v_left));
    if b.credit_rate is not null then v_credit_used := v_credit_used + round(least(b.pending, v_left) * b.credit_rate / 100, 2); end if;
    v_comp := v_comp + least(b.pending, v_left);
    v_left := v_left - least(b.pending, v_left);
  end loop;
  v_base := v_prev - v_comp;

  v_q := erp.corporate_tax_quota(p_year, v_regime, greatest(v_base, 0));
  v_quota := (v_q->>'quota')::numeric;
  v_rate := (v_q->>'marginal_rate')::numeric;
  -- retenciones y pagos fraccionados: saldo deudor de la 473 al cierre
  select coalesce(sum(l.debit - l.credit), 0) into v_wh
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
    and e.entry_type not in ('closing_pl', 'closing') and g.account_no like '473%';
  v_diff := v_quota - v_wh;
  -- v0.42.0 · gastos cargados a reservas (113): el impuesto que ahorran va también contra reservas, no a la PyG (NRV 13.ª,
  -- apdo. 2.1): el gasto por impuesto corriente (6300) es el de la base sin ellos y la diferencia va a la 113 al Haber
  select coalesce(sum((x->>'amount')::numeric), 0) into v_eq
  from jsonb_array_elements(v_adj) x where (x->>'included')::boolean and x->>'origin' = 'equity_costs';
  if v_eq > 0 then
    v_eqtax := ((erp.corporate_tax_quota(p_year, v_regime, greatest(v_base + v_eq, 0)))->>'quota')::numeric - v_quota;
  end if;

  -- impuesto diferido (NRV 13.ª): diferencias temporarias × tipo; bases negativas, solo si se registra el crédito
  v_loss := greatest(-v_prev, 0);
  v_credit := case when v_recognize then round(v_loss * v_rate / 100, 2) else 0 end;
  v_def := round(v_tdec * v_rate / 100, 2) - round(v_tinc * v_rate / 100, 2) - v_credit + v_credit_used;

  if v_regime <> v_hint->>'suggested' and not (v_regime = 'new_entity')
     and not (v_regime = 'erd' and v_hint->>'suggested' = 'micro') then
    v_warn := v_warn || jsonb_build_object('code', 'regime_mismatch', 'suggested', v_hint->>'suggested', 'turnover', v_hint->'turnover');
  end if;
  if v_regime in ('micro', 'erd') and not (v_hint->>'is_erd')::boolean then
    v_warn := v_warn || jsonb_build_object('code', 'regime_not_allowed', 'turnover', v_hint->'turnover');
  end if;
  if v_wh < 0 then v_warn := v_warn || jsonb_build_object('code', 'withholdings_credit_balance', 'amount', v_wh); end if;
  if v_loss > 0 and not v_recognize then v_warn := v_warn || jsonb_build_object('code', 'loss_credit_not_recognized', 'amount', v_loss); end if;

  return jsonb_build_object(
    'status', coalesce(v_ret.status, 'none'), 'return_id', v_ret.id, 'year', p_year, 'regime', v_regime,
    'recognize_loss_credit', v_recognize, 'hint', v_hint,
    'pre_tax_result', v_result, 'adjustments', v_adj,
    'permanent', v_perm, 'temporary_increase', v_tinc, 'temporary_decrease', v_tdec,
    'base_before_losses', v_prev, 'losses_available', v_avail, 'losses_limit', v_limit,
    'losses_compensated', v_comp, 'loss_usage', v_usage, 'taxable_base', v_base,
    'quota', v_quota, 'brackets', v_q->'brackets', 'rates_year', v_q->'rates_year',
    'withholdings', v_wh, 'differential', v_diff,
    'outcome', case when v_diff > 0 then 'pay' when v_diff < 0 then 'refund' else 'zero' end,
    'deferred_rate', v_rate, 'loss_generated', v_loss, 'loss_credit', v_credit, 'loss_credit_used', v_credit_used,
    'current_tax', v_quota + v_eqtax, 'deferred_tax', v_def, 'tax_expense', v_quota + v_eqtax + v_def,
    'equity_costs', v_eq, 'equity_tax_effect', v_eqtax,
    'net_result', v_result - v_quota - v_eqtax - v_def, 'warnings', v_warn);
end $function$
;

-- 8) Contabilizar el impuesto (versión de la 0058 con la 113)
CREATE OR REPLACE FUNCTION erp.corporate_tax_post(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_fy erp.fiscal_years; v_ret uuid; g jsonb; v_cur jsonb := '[]'; v_def jsonb := '[]'; a record;
  v_quota numeric; v_diff numeric; v_dtax numeric; v_e1 uuid; v_e2 uuid; v_d numeric;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post the corporate tax of this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', p_year; end if;
  if exists (select 1 from erp.year_closings c where c.company_id = p_company and c.fiscal_year_id = v_fy.id and c.status = 'posted') then
    raise exception 'The year % is already closed (regularization posted): the corporate tax goes before it', p_year;
  end if;
  v_ret := erp.corporate_tax_prepare(p_company, p_year);
  g := erp.corporate_tax_calc(p_company, p_year);
  v_quota := (g->>'current_tax')::numeric; v_diff := (g->>'differential')::numeric; v_dtax := (g->>'deferred_tax')::numeric;

  -- impuesto corriente
  v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '6300', 'Impuesto corriente'), 'debit', v_quota, 'credit', 0);
  -- v0.42.0 · el ahorro de impuesto de los gastos cargados a reservas, a reservas (113 H)
  if coalesce((g->>'equity_tax_effect')::numeric, 0) > 0 then
    v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '113', 'Reservas voluntarias'), 'debit', 0, 'credit', (g->>'equity_tax_effect')::numeric);
  end if;
  for a in select gl.id, sum(l.debit - l.credit) as bal
           from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts gl on gl.id = l.gl_account_id
           where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted'
             and e.entry_type not in ('closing_pl', 'closing') and gl.account_no like '473%'
           group by gl.id having sum(l.debit - l.credit) <> 0 loop
    v_cur := v_cur || jsonb_build_object('account_id', a.id, 'debit', greatest(-a.bal, 0), 'credit', greatest(a.bal, 0));
  end loop;
  if v_diff > 0 then
    v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '4752', 'Hacienda Pública, acreedora por impuesto sobre sociedades'), 'debit', 0, 'credit', v_diff);
  elsif v_diff < 0 then
    v_cur := v_cur || jsonb_build_object('account_id', erp.adjust_account(p_company, '4709', 'Hacienda Pública, deudora por devolución de impuestos'), 'debit', -v_diff, 'credit', 0);
  end if;
  v_e1 := erp.corporate_tax_entry(p_company, v_fy.ending_date, 'Impuesto sobre Sociedades ' || p_year || ' · impuesto corriente', v_cur);

  -- impuesto diferido
  v_d := round((g->>'temporary_increase')::numeric * (g->>'deferred_rate')::numeric / 100, 2) - round((g->>'temporary_decrease')::numeric * (g->>'deferred_rate')::numeric / 100, 2);
  if v_d <> 0 then
    v_def := v_def || jsonb_build_object('account_id', erp.adjust_account(p_company, '4740', 'Activos por diferencias temporarias deducibles'),
                                         'debit', greatest(v_d, 0), 'credit', greatest(-v_d, 0));
  end if;
  if (g->>'loss_credit')::numeric > 0 or (g->>'loss_credit_used')::numeric > 0 then
    v_def := v_def || jsonb_build_object('account_id', erp.adjust_account(p_company, '4745', 'Crédito por pérdidas a compensar del ejercicio'),
                                         'debit', (g->>'loss_credit')::numeric, 'credit', (g->>'loss_credit_used')::numeric);
  end if;
  if v_dtax <> 0 then
    v_def := v_def || jsonb_build_object('account_id', erp.adjust_account(p_company, '6301', 'Impuesto diferido'),
                                         'debit', greatest(v_dtax, 0), 'credit', greatest(-v_dtax, 0));
  end if;
  v_e2 := erp.corporate_tax_entry(p_company, v_fy.ending_date, 'Impuesto sobre Sociedades ' || p_year || ' · impuesto diferido', v_def);

  update erp.corporate_tax_returns set status = 'posted', result = g - 'status' - 'return_id', current_entry_id = v_e1,
    deferred_entry_id = v_e2, posted_at = now() where id = v_ret;
  return g || jsonb_build_object('status', 'posted', 'return_id', v_ret,
    'current_entry_no', (select entry_no from erp.journal_entries where id = v_e1),
    'deferred_entry_no', (select entry_no from erp.journal_entries where id = v_e2));
end $function$
;

-- 9) Líneas de una factura (versión vigente con la 113 en las recibidas)
CREATE OR REPLACE FUNCTION erp.invoice_entry_lines(p jsonb)
 RETURNS TABLE(line_no integer, gl_account_id uuid, account_no text, account_name text, debit numeric, credit numeric, tax_code text, tax_base numeric, line_role text, src_line integer, amount numeric, sign integer, description text)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_company   uuid := (p->>'company_id')::uuid;
  v_type      text := p->>'invoice_type';
  v_kind      text := coalesce(p->>'document_kind', 'invoice');
  v_partner   erp.business_partners;
  v_pacc      erp.gl_accounts;
  v_work      jsonb := '[]'::jsonb;   -- líneas ya validadas (sin tablas temporales)
  v_total     numeric := 0;
  v_n         int := 0;
  v_signed    numeric;
  v_sign      int;
  r           record;
  t           record;
  a           erp.gl_accounts;
  s           erp.tax_setup;
  tc          erp.tax_codes;
  v_comp      erp.companies;
  v_wh_code   text := nullif(btrim(p->>'withholding_code'), '');
  v_wh        erp.withholding_codes;
  v_whs       erp.withholding_setup;
  v_base_total numeric := 0;
  v_wh_amt    numeric := 0;
  v_nd        boolean;              -- compras de un comerciante en recargo de equivalencia: nada es deducible
  v_re        numeric;
  v_side_acc  uuid;
  v_posting   date := coalesce(nullif(p->>'posting_date', ''), p->>'invoice_date')::date;
  v_pr        numeric;              -- prorrata provisional del año (null = deducción total)
  v_ded       numeric;
begin
  if v_type is null or v_type not in ('purchase', 'sale') then
    raise exception 'Invalid invoice type: %', v_type;
  end if;
  if v_kind not in ('invoice', 'credit_memo') then
    raise exception 'Invalid document kind: %', v_kind;
  end if;

  -- Tercero: proveedor/acreedor en compras, cliente/deudor en ventas
  select * into v_partner from erp.business_partners bp
  where bp.id = nullif(p->>'partner_id', '')::uuid and bp.company_id = v_company;
  if not found then
    raise exception 'Choose the partner of the invoice';
  end if;
  if v_type = 'purchase' and v_partner.partner_type not in ('vendor', 'creditor') then
    raise exception 'A received invoice needs a vendor (400) or creditor (410), not a %', v_partner.partner_type;
  end if;
  if v_type = 'sale' and v_partner.partner_type not in ('customer', 'debtor') then
    raise exception 'An issued invoice needs a customer (430) or debtor (440), not a %', v_partner.partner_type;
  end if;
  if v_partner.blocked then
    raise exception 'Partner % is blocked', v_partner.name;
  end if;
  select * into v_pacc from erp.gl_accounts g where g.id = v_partner.gl_account_id;
  if v_pacc.id is null then
    raise exception 'Partner % has no posting account', v_partner.name;
  end if;

  select * into v_comp from erp.companies c where c.id = v_company;
  v_nd := v_comp.vat_regime = 'equivalence_surcharge' and v_type = 'purchase';

  -- Retención IRPF (opcional): debe existir y estar configurada en la empresa
  if v_wh_code is not null then
    select * into v_wh from erp.withholding_codes w where w.code = v_wh_code;
    if not found then
      raise exception 'Unknown withholding code %', v_wh_code;
    end if;
    select * into v_whs from erp.withholding_setup ws where ws.company_id = v_company and ws.withholding_code = v_wh_code;
    if not found or v_whs.blocked then
      raise exception 'Withholding % is not set up for this company (Taxes tab)', v_wh_code;
    end if;
  end if;

  if jsonb_array_length(coalesce(p->'lines', '[]'::jsonb)) = 0 then
    raise exception 'The invoice has no lines';
  end if;

  -- 0) Validar y resolver cada línea
  for r in
    select x.ord::int as n, btrim(x.l->>'account_no') as acc_no, x.l->>'amount' as amount_txt,
           x.l->>'tax_code' as code, nullif(btrim(x.l->>'description'), '') as descr
    from jsonb_array_elements(p->'lines') with ordinality as x(l, ord)
  loop
    select * into a from erp.gl_accounts g where g.company_id = v_company and g.account_no = r.acc_no;
    if not found then
      raise exception 'Line %: account % does not exist', r.n, coalesce(r.acc_no, '');
    end if;
    if a.account_type <> 'posting' then
      raise exception 'Line %: account % is a heading account', r.n, a.account_no;
    end if;
    -- Regla contable: compras a grupos 2 (inmovilizado) o 6 (gastos); ventas al grupo 7 (ingresos)
    -- v0.42.0: también la 113 (gastos de constitución o de ampliación de capital, que van contra reservas: NRV 9.ª)
    if v_type = 'purchase' and left(a.account_no, 1) not in ('2', '6') and a.account_no not like '113%' then
      raise exception 'Line %: account % is not valid in a received invoice (use group 6 or 2, or 113 for incorporation or capital increase costs)', r.n, a.account_no;
    end if;
    -- v0.35.0: la venta de un inmovilizado se factura a su cuenta (20x / 21x / 22x); la baja la hace el módulo
    if v_type = 'sale' and left(a.account_no, 1) <> '7' and left(a.account_no, 2) not in ('20', '21', '22') then
      raise exception 'Line %: account % is not valid in an issued invoice (use group 7, or the asset account to sell a fixed asset)', r.n, a.account_no;
    end if;
    if coalesce(nullif(r.amount_txt, '')::numeric, 0) <= 0 then
      raise exception 'Line %: the amount must be greater than zero', r.n;
    end if;

    select * into tc from erp.tax_codes c where c.code = r.code;
    if not found then
      raise exception 'Line %: choose a tax code', r.n;
    end if;
    select * into s from erp.tax_setup ts where ts.company_id = v_company and ts.tax_code = r.code;
    if not found or s.blocked then
      raise exception 'Line %: tax code % is not set up for this company (Taxes tab)', r.n, r.code;
    end if;

    -- Operaciones sin cuota: cada causa tiene sus condiciones (lo que comprobaría un inspector)
    if tc.rate_category in ('export', 'intra_eu') and v_type <> 'sale' then
      raise exception 'Line %: % (export / intra-EU supply) is only for issued invoices', r.n, r.code;
    end if;
    if tc.rate_category = 'intra_eu' and v_partner.tax_territory <> 'eu' then
      raise exception 'Line %: an intra-EU supply (%) needs a customer from another EU country', r.n, r.code;
    end if;
    if tc.rate_category = 'export' and v_comp.tax_territory = 'mainland' and v_partner.tax_territory = 'eu' then
      raise exception 'Line %: a sale of goods to another EU country is an intra-EU supply, not an export', r.n;
    end if;
    if tc.rate_category in ('export', 'not_subject') and v_partner.tax_territory = v_comp.tax_territory then
      raise exception 'Line %: % is only for partners outside the company tax territory (%)', r.n, r.code, v_comp.tax_territory;
    end if;

    -- Inversión del sujeto pasivo y adquisición intracomunitaria: solo en compras
    if tc.rate_category in ('reverse_charge', 'intra_eu_acquisition') and v_type <> 'purchase' then
      raise exception 'Line %: % (reverse charge) is only for received invoices', r.n, r.code;
    end if;
    if tc.rate_category = 'intra_eu_acquisition' and v_partner.tax_territory <> 'eu' then
      raise exception 'Line %: an intra-EU acquisition (%) needs a vendor from another EU country', r.n, r.code;
    end if;
    if tc.rate_category in ('reverse_charge', 'intra_eu_acquisition') and v_comp.vat_regime = 'equivalence_surcharge' then
      raise exception 'Line %: reverse charge is not available for a retailer under the equivalence surcharge in this lab', r.n;
    end if;
    -- Recargo de equivalencia: el minorista vende con el IVA incluido en el precio (no lo liquida)
    if tc.rate_category = 'retail_surcharge' and not (v_comp.vat_regime = 'equivalence_surcharge' and v_type = 'sale') then
      raise exception 'Line %: % is only for sales of a retailer under the equivalence surcharge', r.n, r.code;
    end if;
    if v_comp.vat_regime = 'equivalence_surcharge' and v_type = 'sale' and tc.rate_pct > 0 then
      raise exception 'Line %: a retailer under the equivalence surcharge records its sales with VAT included (code VAT_RE_INC)', r.n;
    end if;
    if v_type = 'sale' and v_partner.equivalence_surcharge and tc.equivalence_surcharge_pct is not null
       and s.surcharge_account_id is null then
      raise exception 'Line %: the equivalence surcharge account for % is not set up (Taxes: run the setup again)', r.n, r.code;
    end if;

    -- Regla del lado: reducen las cuentas 606/608/609 · 706/708/709 y todas las líneas de una rectificativa
    v_sign := case when v_kind = 'credit_memo'
                     or a.template_account in ('606', '608', '609', '706', '708', '709') then -1 else 1 end;

    v_work := v_work || jsonb_build_object(
      'n', r.n, 'gl_account_id', a.id, 'account_no', a.account_no, 'account_name', a.name,
      'amount', round(r.amount_txt::numeric, 2), 'tax_code', r.code, 'sign', v_sign, 'rate', tc.rate_pct,
      'description', r.descr,
      'cat', tc.rate_category, 're_pct', tc.equivalence_surcharge_pct, 'ttype', tc.tax_type,
      'in_acc', s.input_account_id, 'out_acc', s.output_account_id, 're_acc', s.surcharge_account_id);
  end loop;

  -- 1) Líneas de base: compras aumentan al DEBE · ventas aumentan al HABER
  for r in select * from jsonb_to_recordset(v_work)
             as w(n int, gl_account_id uuid, account_no text, account_name text, amount numeric,
                  tax_code text, sign int, description text) order by n
  loop
    v_n := v_n + 1;
    v_signed := r.sign * r.amount;
    v_total := v_total + v_signed;
    line_no := v_n; gl_account_id := r.gl_account_id; account_no := r.account_no; account_name := r.account_name;
    debit  := case when (v_type = 'purchase') = (v_signed > 0) then abs(v_signed) else 0 end;
    credit := case when (v_type = 'purchase') = (v_signed > 0) then 0 else abs(v_signed) end;
    tax_code := r.tax_code; tax_base := null; line_role := 'base';
    src_line := r.n; amount := r.amount; sign := r.sign; description := r.description;
    return next;
  end loop;

  v_base_total := v_total;   -- base imponible neta de la factura (con signo)

  -- 2) Cuotas: una por tipo, sobre la base neta de la factura, redondeada a céntimos
  for t in
    select w.tax_code as code, max(w.rate) as rate, max(w.re_pct) as re_pct, max(w.cat) as cat, max(w.ttype) as ttype,
           sum(w.sign * w.amount) as base,
           (array_agg(w.in_acc))[1] as in_acc, (array_agg(w.out_acc))[1] as out_acc, (array_agg(w.re_acc))[1] as re_acc,
           (array_agg(w.gl_account_id order by w.n))[1] as first_acc
    from jsonb_to_recordset(v_work) as w(n int, tax_code text, rate numeric, re_pct numeric, cat text, ttype text, sign int,
                                         amount numeric, in_acc uuid, out_acc uuid, re_acc uuid, gl_account_id uuid)
    group by w.tax_code order by w.tax_code
  loop
    v_signed := round(t.base * t.rate / 100, 2);
    src_line := null; amount := null; sign := null; description := null;
    tax_code := t.code; tax_base := t.base;

    if v_signed = 0 then
      -- tipo 0 % o sin cuota: no hay apunte, pero sí base para el libro registro
      line_no := null; gl_account_id := null; account_no := null; account_name := null;
      debit := 0; credit := 0; line_role := 'tax_exempt';
      return next;
      continue;
    end if;

    -- Prorrata: en las compras solo se deduce el porcentaje provisional del año; el resto es más coste
    v_pr := null;
    if v_type = 'purchase' and not v_nd then
      select pr.provisional_pct into v_pr from erp.pro_rata pr
      where pr.company_id = v_company and pr.tax_type = t.ttype and pr.year = extract(year from v_posting);
    end if;
    v_ded := case when v_pr is null then v_signed else round(v_signed * v_pr / 100, 2) end;

    if t.cat in ('reverse_charge', 'intra_eu_acquisition') then
      -- ISP / adquisición intracomunitaria: la EMPRESA se repercute y se soporta la cuota.
      -- 472 al Debe y 477 al Haber por el mismo importe; el proveedor no la cobra (no suma al total)
      if v_ded <> 0 then
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.in_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.in_acc;
        debit  := case when v_ded > 0 then v_ded else 0 end;
        credit := case when v_ded > 0 then 0 else -v_ded end;
        line_role := 'tax';
        return next;
      end if;
      if v_signed - v_ded <> 0 then   -- parte no deducible por la prorrata: a la cuenta de la compra
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.first_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.first_acc;
        debit  := case when v_signed - v_ded > 0 then v_signed - v_ded else 0 end;
        credit := case when v_signed - v_ded > 0 then 0 else v_ded - v_signed end;
        line_role := 'tax_nd';
        return next;
      end if;
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := t.out_acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.out_acc;
      debit  := case when v_signed > 0 then 0 else -v_signed end;
      credit := case when v_signed > 0 then v_signed else 0 end;
      line_role := 'tax_rc';
      return next;
      continue;
    end if;

    v_total := v_total + v_signed;
    if v_pr is not null then
      -- Prorrata: 472 por la parte deducible y la cuenta de la compra por el resto
      if v_ded <> 0 then
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.in_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.in_acc;
        debit  := case when v_ded > 0 then v_ded else 0 end;
        credit := case when v_ded > 0 then 0 else -v_ded end;
        line_role := 'tax';
        return next;
      end if;
      if v_signed - v_ded <> 0 then
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := t.first_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.first_acc;
        debit  := case when v_signed - v_ded > 0 then v_signed - v_ded else 0 end;
        credit := case when v_signed - v_ded > 0 then 0 else v_ded - v_signed end;
        line_role := 'tax_nd';
        return next;
      end if;
    else
      -- Cuota normal (o no deducible: comerciante en recargo de equivalencia → mayor coste, a la cuenta de la compra)
      v_side_acc := case when v_nd then t.first_acc when v_type = 'purchase' then t.in_acc else t.out_acc end;
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := v_side_acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = v_side_acc;
      debit  := case when (v_type = 'purchase') = (v_signed > 0) then abs(v_signed) else 0 end;
      credit := case when (v_type = 'purchase') = (v_signed > 0) then 0 else abs(v_signed) end;
      line_role := case when v_nd then 'tax_nd' else 'tax' end;
      return next;
    end if;

    -- Recargo de equivalencia: lo cobra el mayorista al minorista (477 recargo) y el minorista lo paga sin deducirlo
    if t.re_pct is not null and (v_nd or (v_type = 'sale' and v_partner.equivalence_surcharge)) then
      v_re := round(t.base * t.re_pct / 100, 2);
      if v_re <> 0 then
        v_total := v_total + v_re;
        v_side_acc := case when v_nd then t.first_acc else t.re_acc end;
        v_n := v_n + 1;
        line_no := v_n; gl_account_id := v_side_acc;
        select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = v_side_acc;
        debit  := case when (v_type = 'purchase') = (v_re > 0) then abs(v_re) else 0 end;
        credit := case when (v_type = 'purchase') = (v_re > 0) then 0 else abs(v_re) end;
        line_role := case when v_nd then 'surcharge_nd' else 'surcharge' end;
        return next;
      end if;
    end if;
  end loop;

  -- 3) Retención IRPF sobre la base imponible (sin el impuesto):
  --    compras → 4751 al HABER (la empresa la retiene y la ingresa en Hacienda: modelos 111 / 115)
  --    ventas  → 473 al DEBE (el cliente nos la retiene: es un pago a cuenta de nuestro impuesto)
  if v_wh_code is not null then
    v_wh_amt := round(v_base_total * v_wh.rate_pct / 100, 2);
    if v_wh_amt <> 0 then
      v_n := v_n + 1;
      line_no := v_n;
      gl_account_id := case v_type when 'purchase' then v_whs.payable_account_id else v_whs.receivable_account_id end;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g
      where g.id = case v_type when 'purchase' then v_whs.payable_account_id else v_whs.receivable_account_id end;
      debit  := case when (v_type = 'purchase') = (v_wh_amt > 0) then 0 else abs(v_wh_amt) end;
      credit := case when (v_type = 'purchase') = (v_wh_amt > 0) then abs(v_wh_amt) else 0 end;
      tax_code := v_wh_code; tax_base := v_base_total; line_role := 'withholding';
      src_line := null; amount := null; sign := null; description := null;
      return next;
    end if;
  end if;

  -- 4) Tercero: lado contrario, por el total menos la retención (lo que realmente se paga o se cobra)
  if v_total = 0 then
    raise exception 'The invoice total is zero';
  end if;
  if v_kind = 'invoice' and v_total < 0 then
    raise exception 'The invoice total is negative: register it as a credit memo';
  end if;
  v_n := v_n + 1;
  line_no := v_n; gl_account_id := v_pacc.id; account_no := v_pacc.account_no; account_name := v_pacc.name;
  debit  := case when (v_type = 'purchase') = (v_total - v_wh_amt > 0) then 0 else abs(v_total - v_wh_amt) end;
  credit := case when (v_type = 'purchase') = (v_total - v_wh_amt > 0) then abs(v_total - v_wh_amt) else 0 end;
  tax_code := null; tax_base := null; line_role := 'partner';
  src_line := null; amount := null; sign := null; description := null;
  return next;
end $function$
;

-- 10) Comprobaciones del auditor (versión vigente sin la 47512 en la de retenciones)
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
                where l.entry_id = a.k and ga.account_no like '4751%' and ga.account_no not like '47512%') as original
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.account_no like '4751%' and a.account_no not like '47512%'   -- v0.42.0: la 47512 (dividendos) va al modelo 123
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

-- 11) Vista previa del cierre (versión de la 0059 con el aviso del resultado sin repartir)
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

  -- v0.42.0 · el resultado del año anterior sigue en la 129: la junta aún no lo ha repartido (Operaciones societarias)
  if v_fy.status = 'open' and erp.equity_bal(p_company, '129', v_fy.ending_date) <> 0 then
    v_checks := v_checks || jsonb_build_object('code', 'result_not_distributed', 'severity', 'warning',
      'detail', erp.equity_bal(p_company, '129', v_fy.ending_date));
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
