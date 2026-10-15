-- =====================================================================
-- 0037 · COMPROBACIONES DEL AUDITOR (controles posteriores, estilo ERP español) · v0.33.0
-- ---------------------------------------------------------------------
-- Los ERP españoles (A3, Sage) dejan contabilizar casi todo a mano y controlan DESPUÉS: cuadres y listados de
-- revisión. Aquí esos controles están siempre activos, en los dos modos (estricto o guiado, 0036), y se ven en la
-- pantalla «Comprobaciones».
--
--   erp.audit_checks             → catálogo (DATOS): qué se comprueba, por qué, cómo se arregla y en qué pantalla
--   erp.run_audit_checks(...)    → resultado a una fecha: libro · contabilidad · diferencia · nº de casos · detalle
--
-- Qué se comprueba (ejercicio p_year, hasta p_to_date):
--   vat_input       472 (IVA / IGIC soportado) frente al libro registro de facturas recibidas
--   vat_output      477 (IVA / IGIC repercutido) frente al libro registro de facturas emitidas
--   withholdings    4751 (retenciones practicadas) frente al resumen de los modelos 111 / 115
--   partners        saldo de cada proveedor / cliente frente a lo pendiente de sus facturas (antigüedad, 0035)
--   anomalies       saldos al revés de su naturaleza (0013): banco acreedor, proveedor deudor, caja negativa…
--   tax_territory   IGIC en una empresa de la Península, o IVA en una de Canarias
--   controlled      asientos manuales sobre cuentas controladas (0036), los que el modo guiado deja pasar
--
-- Cómo se cuadran los impuestos: solo cuentan los asientos «normales» (sin apertura ni cierre) y se quitan los de
-- liquidación y prorrata, que cancelan la 472 / 477 a propósito. Lo que queda debería salir entero de las facturas:
-- la diferencia son los asientos manuales o importados que mueven la cuenta sin factura (no van al libro registro
-- ni al modelo 303 / 420). Un asiento y su contraasiento se anulan entre sí.
-- Seguridad: security invoker, la RLS decide qué se ve. Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Catálogo
-- ---------------------------------------------------------------------
create table if not exists erp.audit_checks (
  code      text primary key,
  sort      int  not null,
  area      text not null check (area in ('taxes', 'partners', 'ledger')),
  severity  text not null check (severity in ('info', 'warning', 'error')),
  title     text not null,
  title_en  text not null,
  why       text not null,     -- por qué lo mira un auditor
  why_en    text not null,
  fix       text not null,     -- cómo se arregla
  fix_en    text not null,
  screen    text not null      -- pantalla de la web donde se arregla
);
comment on table erp.audit_checks is 'Auditor checks (detective controls of Spanish ERPs): what is checked, why and where to fix it.';

insert into erp.audit_checks (code, sort, area, severity, title, title_en, why, why_en, fix, fix_en, screen) values
('vat_input', 10, 'taxes', 'warning',
 'IVA / IGIC soportado (472) frente al libro registro',
 'Input VAT / IGIC (472) against the VAT book',
 'La 472 solo debería moverse desde las facturas recibidas y la liquidación. Un asiento manual sobre la 472 no está en el libro registro ni en el modelo 303 / 420: o sobra en la contabilidad o falta la factura.',
 '472 should only move from received invoices and the settlement. A manual entry on 472 is not in the VAT book or the 303 / 420 return: either the ledger is wrong or the invoice is missing.',
 'Anula el asiento manual (contraasiento) y registra la factura recibida desde Facturas.',
 'Reverse the manual entry and register the received invoice from Invoices.',
 'journal'),
('vat_output', 20, 'taxes', 'warning',
 'IVA / IGIC repercutido (477) frente al libro registro',
 'Output VAT / IGIC (477) against the VAT book',
 'La 477 solo debería moverse desde las facturas emitidas y la liquidación. Si no cuadra, el modelo 303 / 420 declarará una cuota distinta de la contabilizada.',
 '477 should only move from issued invoices and the settlement. If it does not match, the 303 / 420 return will declare a different amount from the ledger.',
 'Anula el asiento manual (contraasiento) y emite la factura desde Facturas.',
 'Reverse the manual entry and issue the invoice from Invoices.',
 'journal'),
('withholdings', 30, 'taxes', 'info',
 'Retenciones practicadas (4751) frente a los modelos 111 / 115',
 'Withholdings (4751) against forms 111 / 115',
 'Las retenciones de profesionales y alquileres se ingresan con el modelo 111 / 115, que sale de las facturas. Una retención abonada a mano en la 4751 no estará en el resumen. Si es de nóminas, es normal: el ERP aún no tiene nóminas y la 111 también las incluye.',
 'Professional and rent withholdings are paid with form 111 / 115, built from the invoices. A withholding credited by hand to 4751 will not be in the summary. Payroll withholdings are fine: the ERP has no payroll yet and form 111 includes them too.',
 'Si no es de nóminas, anula el asiento y registra la factura con su retención desde Facturas.',
 'If it is not payroll, reverse the entry and register the invoice with its withholding from Invoices.',
 'withholdings'),
('partners', 40, 'partners', 'warning',
 'Terceros cuyo saldo no cuadra con sus facturas',
 'Partners whose balance does not match their invoices',
 'La cuenta del proveedor o cliente dice cuánto se debe; las facturas pendientes, qué se debe. Si no coinciden hay pagos hechos a mano sin vincular, saldos importados o facturas sin registrar.',
 'The partner account says how much is owed; the open invoices say what is owed. If they differ there are unlinked manual payments, imported balances or missing invoices.',
 'En Cobros y pagos, vincula el pago manual a su factura (o regístralo contra la factura).',
 'In Payments, link the manual payment to its invoice (or post it against the invoice).',
 'payments'),
('anomalies', 50, 'ledger', 'warning',
 'Saldos al revés de su naturaleza',
 'Balances opposite to their nature',
 'Un banco acreedor, un proveedor deudor o una caja negativa no siempre son errores, pero un auditor los revisa y al cierre se reclasifican (572 → 5201, 400 → 407, 430 → 438).',
 'A bank with a credit balance, a vendor with a debit balance or negative cash are not always errors, but an auditor reviews them and reclassifies them at year end (572 → 5201, 400 → 407, 430 → 438).',
 'Revisa el mayor de la cuenta: falta un cobro, sobra un pago o hay que reclasificar al cierre.',
 'Review the account ledger: a receipt is missing, a payment is wrong or it must be reclassified at year end.',
 'reports'),
('tax_territory', 60, 'taxes', 'warning',
 'Impuesto que no corresponde al territorio',
 'Tax that does not match the territory',
 'En la Península y Baleares se aplica IVA; en Canarias, IGIC. Una empresa de la Península no repercute ni soporta IGIC (y al revés): una venta a Canarias va exenta, no con IGIC.',
 'The mainland and the Balearic Islands use VAT; the Canary Islands use IGIC. A mainland company neither charges nor bears IGIC (and vice versa): a sale to the Canaries is exempt, not taxed with IGIC.',
 'Rectifica la factura con el impuesto de tu territorio (o exenta) o anula el asiento manual.',
 'Correct the invoice with your territory tax (or exempt) or reverse the manual entry.',
 'invoices'),
('controlled', 70, 'ledger', 'warning',
 'Asientos manuales sobre cuentas controladas',
 'Manual entries on controlled accounts',
 'En SAP o Business Central la 400, 410, 430, 472, 477… solo las mueve su módulo. En modo guiado se permite el asiento manual, pero queda aquí para revisarlo: la factura no sabrá que está pagada y el libro de IVA no lo recoge.',
 'In SAP or Business Central 400, 410, 430, 472, 477… are posted only by their module. Guided mode allows the manual entry, but it is listed here for review: the invoice will not know it is paid and the VAT book does not include it.',
 'Si es un pago, vincúlalo en Cobros y pagos; si no, anúlalo y regístralo desde su pantalla.',
 'If it is a payment, link it in Payments; otherwise reverse it and register it from its screen.',
 'journal')
on conflict (code) do update set
  sort = excluded.sort, area = excluded.area, severity = excluded.severity,
  title = excluded.title, title_en = excluded.title_en, why = excluded.why, why_en = excluded.why_en,
  fix = excluded.fix, fix_en = excluded.fix_en, screen = excluded.screen;

alter table erp.audit_checks enable row level security;
drop policy if exists read on erp.audit_checks;
create policy read on erp.audit_checks for select to authenticated using (true);
revoke all on erp.audit_checks from anon, public;
grant select on erp.audit_checks to authenticated;

-- ---------------------------------------------------------------------
-- 2) Apuntes del ejercicio con su origen (para los cuadres)
--    source: invoice · settlement · pro_rata · payment · import · manual
--    (un contraasiento toma el origen del asiento que anula: así el par suma cero en su origen)
-- ---------------------------------------------------------------------
create or replace function erp.audit_lines(p_company uuid, p_year int, p_to_date date default null)
returns table (entry_id uuid, entry_no int, posting_date date, k uuid, source text,
               account_no text, account_name text, debit numeric, credit numeric, tax_code text)
language sql stable as $$
  select e.id, e.entry_no, e.posting_date, coalesce(e.reversal_of, e.id),
         case when exists (select 1 from erp.invoices i where i.entry_id = coalesce(e.reversal_of, e.id)) then 'invoice'
              when exists (select 1 from erp.tax_settlements s where s.entry_id = coalesce(e.reversal_of, e.id)) then 'settlement'
              when exists (select 1 from erp.pro_rata p where p.entry_id = coalesce(e.reversal_of, e.id)) then 'pro_rata'
              when exists (select 1 from erp.payments py where not py.linked
                           and coalesce(e.reversal_of, e.id) in (py.entry_id, py.cancel_entry_id)) then 'payment'
              when o.import_batch_id is not null then 'import'
              else 'manual' end,
         g.account_no, g.name, l.debit, l.credit, l.tax_code
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id
  join erp.journal_entries o on o.id = coalesce(e.reversal_of, e.id)
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
    and (p_to_date is null or e.posting_date <= p_to_date);
$$;

-- ---------------------------------------------------------------------
-- 3) Resultado de las comprobaciones
--    book       lo que dicen los documentos (libro registro, modelo 111 / 115, facturas pendientes)
--    ledger     lo que dice la contabilidad
--    difference ledger − book (en los listados sin importe, 0)
--    items      nº de casos (asientos, cuentas, terceros) · details: hasta 50, para enlazarlos en la web
--    status     ok, o la gravedad del catálogo (anomalies pasa a error si hay un saldo imposible, p. ej. caja)
-- ---------------------------------------------------------------------
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

revoke execute on function erp.audit_lines(uuid, int, date), erp.run_audit_checks(uuid, int, date) from anon, public;
grant execute on function erp.audit_lines(uuid, int, date), erp.run_audit_checks(uuid, int, date) to authenticated;
