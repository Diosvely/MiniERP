-- =====================================================================
-- 0040 · INVARIANTES CONTABLES (integridad) · v0.34.0
-- ---------------------------------------------------------------------
-- Verdades que se cumplen SIEMPRE, las haya programado quien las haya programado. Si una falla, hay un error en el
-- ERP (no en el usuario). Las pruebas las comprueban después de cientos de operaciones al azar (fase 34); y quedan
-- como función para enseñarlas en la web o al chat.
--
--   entries_balanced    cada asiento contabilizado: Debe = Haber                         (partida doble)
--   trial_balance       sumas y saldos del ejercicio: total Debe = total Haber
--   balance_sheet       Activo = Patrimonio neto + Pasivo                                 (PGC, 3.ª parte, modelo de balance)
--   result_129          tras el cierre: lo que la regularización lleva a la 129 = resultado de la PyG
--   opening_closing     apertura del año siguiente = cierre de este, cuenta a cuenta
--   reversals_zero      asiento + su contraasiento = cero, cuenta a cuenta
--   invoice_partner     la línea del tercero de cada factura = total − retención
--   tax_register        472 / 477 que generan las facturas = cuotas del libro registro    (RIVA art. 62-64)
--   cash_flow           variación de la tesorería (57) = EFE directo = EFE indirecto       (PGC, NECA 9.ª)
--
-- Seguridad: security invoker (la RLS decide qué se ve). Re-ejecutable.
-- =====================================================================

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
end $$;

revoke execute on function erp.integrity_checks(uuid, int) from anon, public;
grant execute on function erp.integrity_checks(uuid, int) to authenticated;
