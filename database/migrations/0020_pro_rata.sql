-- =====================================================================
-- 0020 · PRO RATA · Prorrata general del IVA / IGIC (bloque J5, parte 3)
-- ---------------------------------------------------------------------
-- Una empresa que hace a la vez operaciones CON derecho a deducir (ventas con IVA, exportaciones…) y operaciones
-- exentas SIN ese derecho (art. 20: enseñanza, sanidad, seguros, alquiler de vivienda…) solo deduce una parte
-- del impuesto que soporta (LIVA arts. 102–106; igual en el IGIC):
--
--   Durante el año   → prorrata PROVISIONAL = la definitiva del año anterior (o una estimada el primer año).
--                      En cada compra: 472 por la parte deducible y la cuenta de la compra por el resto (más coste).
--   Al final del año → prorrata DEFINITIVA = operaciones con derecho / total de operaciones × 100,
--                      redondeada a la unidad SUPERIOR (sin IVA y sin las operaciones exentas del art. 20).
--                      Se regulariza la diferencia en el 4T (casilla de regularización de la prorrata):
--                        deducido de menos → 472 Debe / 6391 Ajustes positivos en IVA de activo corriente Haber
--                        deducido de más   → 6341 Ajustes negativos en IVA de activo corriente Debe / 472 Haber
--                      y la definitiva pasa a ser la provisional del año siguiente.
--
--   erp.set_pro_rata(empresa, impuesto, año, %)              → activa o cambia la prorrata provisional del año
--   erp.pro_rata_calc(empresa, impuesto, año)                → borrador de la regularización
--   erp.post_pro_rata_regularization(empresa, impuesto, año) → contabiliza la regularización (31/12)
--   erp.cancel_pro_rata_regularization(empresa, impuesto, año)
--
-- Simplificaciones del laboratorio: no hay prorrata especial ni sectores diferenciados, y no se regularizan
-- los bienes de inversión de años anteriores (las cuotas del inmovilizado siguen la prorrata del año de compra).
-- =====================================================================

create table erp.pro_rata (
  company_id             uuid not null references erp.companies(id) on delete cascade,
  tax_type               text not null check (tax_type in ('VAT', 'IGIC')),
  year                   smallint not null,
  provisional_pct        numeric(5,2) not null check (provisional_pct between 0 and 100),
  definitive_pct         numeric(5,2) check (definitive_pct between 0 and 100),
  regularization_amount  numeric(15,2),          -- > 0 deducción adicional · < 0 se devuelve deducción
  entry_id               uuid references erp.journal_entries(id),
  regularized_at         timestamptz,
  primary key (company_id, tax_type, year)
);
comment on table erp.pro_rata is 'General pro rata (partial VAT/IGIC deduction) per company, tax and year.';

create or replace function erp.tg_pro_rata_protect()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on'
     or coalesce(current_setting('erp.pro_rata_engine', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  raise exception 'The pro rata is changed only with set_pro_rata() and its regularization';
end $$;
create trigger pro_rata_protect before insert or update or delete on erp.pro_rata
  for each row execute function erp.tg_pro_rata_protect();

-- El asiento de regularización no se anula suelto: se deshace con cancel_pro_rata_regularization()
create or replace function erp.tg_entry_pro_rata_reverse()
returns trigger language plpgsql as $$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.pro_rata_engine', true), '') <> 'on'
     and exists (select 1 from erp.pro_rata where entry_id = new.reversal_of) then
    raise exception 'This entry is a pro rata regularization: undo it from the Pro rata screen';
  end if;
  return new;
end $$;
create trigger entry_pro_rata_reverse before insert on erp.journal_entries
  for each row execute function erp.tg_entry_pro_rata_reverse();

-- Lo deducido de cada factura queda en el libro registro (la prorrata lo hace distinto de la cuota)
alter table erp.invoice_tax_lines add column deductible_amount numeric(15,2) not null default 0;
-- facturas existentes: compras deducibles → lo deducido es la cuota
-- (las facturas no se modifican nunca: se desactiva su protección solo durante este relleno)
alter table erp.invoice_tax_lines disable trigger invoice_tax_line_protect;
update erp.invoice_tax_lines t set deductible_amount = t.tax_amount
from erp.invoices i
where i.id = t.invoice_id and i.invoice_type = 'purchase' and t.deductible;
alter table erp.invoice_tax_lines enable trigger invoice_tax_line_protect;

-- ---------------------------------------------------------------------
-- Activar / cambiar / quitar la prorrata provisional de un año (p_pct null = sin prorrata)
-- ---------------------------------------------------------------------
create or replace function erp.set_pro_rata(p_company uuid, p_tax_type text, p_year int, p_pct numeric)
returns void language plpgsql as $$
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can set the pro rata';
  end if;
  if exists (select 1 from erp.pro_rata where company_id = p_company and tax_type = p_tax_type and year = p_year
             and entry_id is not null) then
    raise exception 'The % pro rata of % is already regularized: undo the regularization first', p_tax_type, p_year;
  end if;
  if (select vat_regime from erp.companies where id = p_company) = 'equivalence_surcharge' then
    raise exception 'A retailer under the equivalence surcharge does not apply the pro rata';
  end if;
  perform set_config('erp.pro_rata_engine', 'on', true);
  if p_pct is null then
    delete from erp.pro_rata where company_id = p_company and tax_type = p_tax_type and year = p_year;
  else
    insert into erp.pro_rata (company_id, tax_type, year, provisional_pct)
    values (p_company, p_tax_type, p_year, p_pct)
    on conflict (company_id, tax_type, year) do update set provisional_pct = excluded.provisional_pct,
      definitive_pct = null, regularization_amount = null;
  end if;
  perform set_config('erp.pro_rata_engine', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- BORRADOR de la regularización anual
-- ---------------------------------------------------------------------
create or replace function erp.pro_rata_calc(p_company uuid, p_tax_type text, p_year int)
returns jsonb language plpgsql stable as $$
declare
  v_pr       erp.pro_rata;
  v_with     numeric;     -- operaciones con derecho a deducir
  v_total    numeric;     -- todas las operaciones (con derecho + exentas sin derecho)
  v_def      numeric;
  v_input    numeric;     -- cuotas soportadas del año
  v_deducted numeric;     -- deducido con la provisional
  v_should   numeric;
  v_adj      numeric;
  v_acc472   uuid;
  v_settled  boolean;
begin
  select * into v_pr from erp.pro_rata where company_id = p_company and tax_type = p_tax_type and year = p_year;
  if not found then
    raise exception 'The company has no % pro rata in %', p_tax_type, p_year;
  end if;

  -- Numerador y denominador: bases de las facturas EMITIDAS del año (sin IVA)
  select coalesce(sum(r.tax_base) filter (where r.rate_category <> 'exempt'), 0), coalesce(sum(r.tax_base), 0)
    into v_with, v_total
  from erp.v_invoice_register r
  where r.company_id = p_company and r.tax_type = p_tax_type and r.fiscal_year = p_year and r.invoice_type = 'sale'
    and r.rate_category <> 'retail_surcharge';
  v_def := case when v_total <= 0 then 100 else least(100, ceil(v_with / v_total * 100)) end;

  -- Cuotas soportadas del año y lo que se dedujo con la provisional
  select coalesce(sum(r.tax_amount), 0), coalesce(sum(r.deductible_amount), 0)
    into v_input, v_deducted
  from erp.v_invoice_register r
  where r.company_id = p_company and r.tax_type = p_tax_type and r.fiscal_year = p_year and r.invoice_type = 'purchase'
    and r.tax_amount <> 0 and r.surcharge_amount = 0 and (r.deductible or r.deductible_amount <> r.tax_amount);
  v_should := round(v_input * v_def / 100, 2);
  v_adj := coalesce(v_pr.regularization_amount, v_should - v_deducted);

  select s.input_account_id into v_acc472
  from erp.tax_setup s join erp.tax_codes c on c.code = s.tax_code
  where s.company_id = p_company and c.tax_type = p_tax_type and c.rate_category = 'standard' and s.input_account_id is not null
  limit 1;

  select exists (select 1 from erp.tax_settlements t where t.company_id = p_company and t.tax_type = p_tax_type
                 and t.year = p_year and t.quarter = 4 and t.status = 'posted') into v_settled;

  return jsonb_build_object(
    'tax_type', p_tax_type, 'year', p_year,
    'provisional_pct', v_pr.provisional_pct,
    'operations_with_right', v_with, 'operations_total', v_total,
    'definitive_pct', coalesce(v_pr.definitive_pct, v_def),
    'input_tax', v_input, 'deducted', v_deducted, 'should_deduct', v_should,
    'adjustment', v_adj,
    'lines', case when v_adj > 0 then jsonb_build_array(
                   jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_acc472), 'debit', v_adj, 'credit', 0),
                   jsonb_build_object('account_no', rpad('6391', (select posting_account_digits from erp.companies where id = p_company) - 1, '0')
                                        || case p_tax_type when 'VAT' then '1' else '2' end, 'debit', 0, 'credit', v_adj))
                  when v_adj < 0 then jsonb_build_array(
                   jsonb_build_object('account_no', rpad('6341', (select posting_account_digits from erp.companies where id = p_company) - 1, '0')
                                        || case p_tax_type when 'VAT' then '1' else '2' end, 'debit', -v_adj, 'credit', 0),
                   jsonb_build_object('account_no', (select account_no from erp.gl_accounts where id = v_acc472), 'debit', 0, 'credit', -v_adj))
                  else '[]'::jsonb end,
    'regularized', v_pr.entry_id is not null or v_pr.regularized_at is not null,
    'entry_no', (select entry_no from erp.journal_entries where id = v_pr.entry_id),
    'q4_settled', v_settled,
    'next_year_pct', (select provisional_pct from erp.pro_rata where company_id = p_company and tax_type = p_tax_type and year = p_year + 1));
end $$;

-- ---------------------------------------------------------------------
-- CONTABILIZAR la regularización (31/12, antes de liquidar el 4T)
-- ---------------------------------------------------------------------
create or replace function erp.post_pro_rata_regularization(p_company uuid, p_tax_type text, p_year int)
returns jsonb language plpgsql as $$
declare
  c        jsonb;
  v_fy     erp.fiscal_years;
  v_entry  uuid;
  v_no     int;
  v_st     text;
  v_tax    text := case p_tax_type when 'VAT' then 'IVA' else 'IGIC' end;
  l        jsonb;
begin
  if not erp.can_write(p_company) then
    raise exception 'No permission to regularize the pro rata in this company';
  end if;
  c := erp.pro_rata_calc(p_company, p_tax_type, p_year);
  if (c->>'regularized')::boolean then
    raise exception 'The % pro rata of % is already regularized', p_tax_type, p_year;
  end if;
  if (c->>'q4_settled')::boolean then
    raise exception 'Q4 % is already settled: cancel that settlement first (the regularization goes in Q4)', p_year;
  end if;

  perform set_config('erp.pro_rata_engine', 'on', true);
  if jsonb_array_length(c->'lines') > 0 then
    -- Cuentas de ajuste (6341 / 6391) si no existen
    for l in select * from jsonb_array_elements(c->'lines') loop
      if not exists (select 1 from erp.gl_accounts where company_id = p_company and account_no = l->>'account_no') then
        v_st := 'linked';
        perform erp.ensure_tax_account(p_company, l->>'account_no',
          case when l->>'account_no' like '634%' then 'Ajustes negativos en ' || v_tax || ' de activo corriente'
               else 'Ajustes positivos en ' || v_tax || ' de activo corriente' end,
          case when l->>'account_no' like '634%' then 'Negative ' || p_tax_type || ' adjustments' else 'Positive ' || p_tax_type || ' adjustments' end,
          v_st);
      end if;
    end loop;
    select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
    insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
    values (p_company, v_fy.id, v_fy.ending_date,
            'Regularización de la prorrata de ' || v_tax || ' ' || p_year || ': definitiva ' || (c->>'definitive_pct')
              || ' % (provisional ' || (c->>'provisional_pct') || ' %)',
            'PRORRATA-' || p_year)
    returning id into v_entry;
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
    select v_entry, p_company, x.ord, g.id, (x.l->>'debit')::numeric, (x.l->>'credit')::numeric
    from jsonb_array_elements(c->'lines') with ordinality as x(l, ord)
    join erp.gl_accounts g on g.company_id = p_company and g.account_no = x.l->>'account_no';
    update erp.journal_lines set tax_code = null where entry_id = v_entry;   -- no es una operación del libro registro
    v_no := erp.post_entry(v_entry);
  end if;

  update erp.pro_rata
  set definitive_pct = (c->>'definitive_pct')::numeric, regularization_amount = (c->>'adjustment')::numeric,
      entry_id = v_entry, regularized_at = now()
  where company_id = p_company and tax_type = p_tax_type and year = p_year;

  -- La definitiva de este año es la provisional del siguiente
  insert into erp.pro_rata (company_id, tax_type, year, provisional_pct)
  values (p_company, p_tax_type, p_year + 1, (c->>'definitive_pct')::numeric)
  on conflict (company_id, tax_type, year) do update set provisional_pct = excluded.provisional_pct
    where erp.pro_rata.entry_id is null;
  perform set_config('erp.pro_rata_engine', 'off', true);

  return jsonb_build_object('definitive_pct', c->'definitive_pct', 'adjustment', c->'adjustment', 'entry_no', v_no);
end $$;

create or replace function erp.cancel_pro_rata_regularization(p_company uuid, p_tax_type text, p_year int)
returns void language plpgsql as $$
declare
  v_pr erp.pro_rata;
begin
  if not erp.can_write(p_company) then
    raise exception 'No permission to undo the pro rata regularization in this company';
  end if;
  select * into v_pr from erp.pro_rata where company_id = p_company and tax_type = p_tax_type and year = p_year;
  if v_pr.regularized_at is null then
    raise exception 'The % pro rata of % is not regularized', p_tax_type, p_year;
  end if;
  if exists (select 1 from erp.tax_settlements t where t.company_id = p_company and t.tax_type = p_tax_type
             and t.year = p_year and t.quarter = 4 and t.status = 'posted') then
    raise exception 'Q4 % is already settled: cancel that settlement first', p_year;
  end if;
  perform set_config('erp.pro_rata_engine', 'on', true);
  if v_pr.entry_id is not null then
    perform erp.reverse_entry(v_pr.entry_id, null, 'Deshacer la regularización de la prorrata');
  end if;
  update erp.pro_rata set definitive_pct = null, regularization_amount = null, entry_id = null, regularized_at = null
  where company_id = p_company and tax_type = p_tax_type and year = p_year;
  perform set_config('erp.pro_rata_engine', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- MOTOR DE FACTURAS (sustituye al de la 0019): la prorrata reparte la cuota entre 472 y la cuenta de la compra
-- ---------------------------------------------------------------------
create or replace function erp.invoice_entry_lines(p jsonb)
returns table (line_no int, gl_account_id uuid, account_no text, account_name text,
               debit numeric, credit numeric, tax_code text, tax_base numeric, line_role text,
               src_line int, amount numeric, sign int, description text)
language plpgsql stable as $$
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
    if v_type = 'purchase' and left(a.account_no, 1) not in ('2', '6') then
      raise exception 'Line %: account % is not valid in a received invoice (use group 6 or 2)', r.n, a.account_no;
    end if;
    if v_type = 'sale' and left(a.account_no, 1) <> '7' then
      raise exception 'Line %: account % is not valid in an issued invoice (use group 7)', r.n, a.account_no;
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
end $$;

-- ---------------------------------------------------------------------
-- REGISTRAR (sustituye al de la 0019): guarda lo deducido de cada tipo
-- ---------------------------------------------------------------------
create or replace function erp.post_invoice(p jsonb)
returns table (invoice_id uuid, invoice_no text, entry_no int)
language plpgsql as $$
declare
  v_company   uuid := (p->>'company_id')::uuid;
  v_type      text := p->>'invoice_type';
  v_kind      text := coalesce(p->>'document_kind', 'invoice');
  v_date      date := (p->>'invoice_date')::date;
  v_posting   date := coalesce((p->>'posting_date')::date, (p->>'invoice_date')::date);
  v_ext       text := nullif(btrim(p->>'external_document_no'), '');
  v_desc      text := nullif(btrim(p->>'description'), '');
  v_corr      uuid := nullif(p->>'corrected_invoice_id', '')::uuid;
  v_corr_ref  text := nullif(btrim(p->>'corrected_reference'), '');
  v_partner   erp.business_partners;
  v_fy        erp.fiscal_years;
  v_entry     uuid;
  v_inv       uuid;
  v_no        text;
  v_seq       int;
  v_prefix    text;
  v_base      numeric;
  v_tax       numeric;
  v_entry_no  int;
  v_lines     jsonb;
  v_taxes     jsonb;
  c           erp.invoices;
  v_wh_code   text := nullif(btrim(p->>'withholding_code'), '');
  v_wh_base   numeric;
  v_wh_amt    numeric;
  v_surcharge numeric;
begin
  if not erp.can_write(v_company) then
    raise exception 'No permission to register invoices in this company';
  end if;
  if v_date is null then
    raise exception 'The invoice date is required';
  end if;
  if v_posting < v_date then
    raise exception 'The posting date cannot be earlier than the invoice date';
  end if;
  if v_type = 'purchase' and v_ext is null then
    raise exception 'Enter the vendor invoice number';
  end if;

  select * into v_partner from erp.business_partners where id = (p->>'partner_id')::uuid and company_id = v_company;

  -- Rectificativa: debe identificar la factura que corrige (del mismo tercero y tipo)
  if v_kind = 'credit_memo' then
    if v_corr is null and v_corr_ref is null then
      raise exception 'A credit memo must identify the invoice it corrects';
    end if;
    if v_corr is not null then
      select * into c from erp.invoices where id = v_corr;
      if c.id is null or c.company_id <> v_company or c.partner_id <> v_partner.id
         or c.invoice_type <> v_type or c.document_kind <> 'invoice' then
        raise exception 'The corrected invoice must be an invoice of the same partner';
      end if;
    end if;
  end if;

  select * into v_fy from erp.fiscal_years
  where company_id = v_company and v_posting between starting_date and ending_date;
  if v_fy.id is null then
    raise exception 'No fiscal year for date %', v_posting;
  end if;

  -- Cálculo (valida líneas, cuentas, tipos y regla del lado)
  select jsonb_agg(to_jsonb(e)) into v_lines from erp.invoice_entry_lines(p) e;
  select e.tax_base, case when v_type = 'purchase' then e.credit - e.debit else e.debit - e.credit end
    into v_wh_base, v_wh_amt
  from jsonb_to_recordset(v_lines) as e(tax_base numeric, debit numeric, credit numeric, line_role text)
  where e.line_role = 'withholding';

  -- Numeración correlativa por serie y ejercicio (F/R ventas · C/CR compras), sin huecos
  v_prefix := case v_type || '/' || v_kind
                when 'sale/invoice' then 'F' when 'sale/credit_memo' then 'R'
                when 'purchase/invoice' then 'C' else 'CR' end;
  perform pg_advisory_xact_lock(hashtext('invoice/' || v_company || '/' || v_prefix || '/' || v_fy.year));
  select coalesce(max(split_part(i.invoice_no, '-', 3)::int), 0) + 1 into v_seq
  from erp.invoices i
  where i.company_id = v_company and i.invoice_type = v_type and i.invoice_no like v_prefix || '-' || v_fy.year || '-%';
  v_no := v_prefix || '-' || v_fy.year || '-' || lpad(v_seq::text, 4, '0');

  -- Asiento
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (v_company, v_fy.id, v_posting,
          coalesce(v_desc, case v_kind when 'credit_memo' then 'Rectificativa ' else 'Factura ' end
                           || coalesce(v_ext, v_no) || ' · ' || v_partner.name),
          case v_type when 'sale' then v_no else v_ext end)
  returning id into v_entry;

  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, partner_id,
                                 tax_code, tax_base, description)
  select v_entry, v_company, e.line_no, e.gl_account_id, e.debit, e.credit, v_partner.id,
         case when e.line_role = 'tax' then e.tax_code end, e.tax_base, e.description
  from jsonb_to_recordset(v_lines) as e(line_no int, gl_account_id uuid, debit numeric, credit numeric,
                                        tax_code text, tax_base numeric, line_role text, description text)
  where e.line_role <> 'tax_exempt';

  v_entry_no := erp.post_entry(v_entry);

  -- Resumen por tipo de impuesto con signo (negativo si reduce: rectificativas, devoluciones…)
  --   tax_amount: cuota (en ISP, la autorrepercutida) · surcharge_amount: recargo de equivalencia · deductible: ¿se deduce?
  select jsonb_agg(jsonb_build_object('tax_code', x.tax_code, 'tax_base', x.tax_base, 'tax_amount', x.tax_amount,
           'surcharge_amount', x.surcharge, 'deductible', x.deductible, 'reverse_charge', x.rc,
           'deductible_amount', x.deductible_amount))
    into v_taxes
  from (
    select e.tax_code, max(e.tax_base) as tax_base,
           coalesce(sum(e.sgn) filter (where e.line_role in ('tax', 'tax_nd')), 0) as tax_amount,
           coalesce(sum(e.sgn) filter (where e.line_role in ('surcharge', 'surcharge_nd')), 0) as surcharge,
           coalesce(sum(e.sgn) filter (where e.line_role = 'tax'), 0) as deductible_amount,
           not bool_or(e.line_role in ('tax_nd', 'surcharge_nd')) as deductible,
           bool_or(e.line_role = 'tax_rc') as rc
    from (select e.*, case when (v_type = 'purchase') = (e.debit > 0) then e.debit + e.credit else -(e.debit + e.credit) end as sgn
          from jsonb_to_recordset(v_lines) as e(tax_code text, tax_base numeric, debit numeric, credit numeric, line_role text)
          where e.line_role in ('tax', 'tax_exempt', 'tax_nd', 'tax_rc', 'surcharge', 'surcharge_nd')) e
    group by e.tax_code) x;
  -- Total de la factura: lo que cobra el proveedor (en ISP la cuota no la cobra él)
  select sum(x.tax_base), sum(x.tax_amount) filter (where not x.reverse_charge), sum(x.surcharge_amount)
    into v_base, v_tax, v_surcharge
  from jsonb_to_recordset(v_taxes) as x(tax_base numeric, tax_amount numeric, surcharge_amount numeric, reverse_charge boolean);
  v_tax := coalesce(v_tax, 0); v_surcharge := coalesce(v_surcharge, 0);

  perform set_config('erp.invoice_engine', 'on', true);
  insert into erp.invoices (company_id, fiscal_year_id, invoice_type, document_kind, invoice_no, external_document_no,
                            partner_id, invoice_date, posting_date, description, corrected_invoice_id, corrected_reference,
                            total_base, total_tax, total_amount, entry_id,
                            withholding_code, withholding_base, withholding_amount, total_surcharge)
  values (v_company, v_fy.id, v_type, v_kind, v_no, v_ext, v_partner.id, v_date, v_posting,
          coalesce(v_desc, ''), v_corr, v_corr_ref, v_base, v_tax, v_base + v_tax + v_surcharge, v_entry,
          case when v_wh_amt is not null then v_wh_code end, v_wh_base, coalesce(v_wh_amt, 0), v_surcharge)
  returning id into v_inv;

  insert into erp.invoice_lines (invoice_id, company_id, line_no, gl_account_id, description, amount, tax_code, sign)
  select v_inv, v_company, e.src_line, e.gl_account_id, e.description, e.amount, e.tax_code, e.sign
  from jsonb_to_recordset(v_lines) as e(src_line int, gl_account_id uuid, description text, amount numeric,
                                        tax_code text, sign int, line_role text)
  where e.line_role = 'base';

  insert into erp.invoice_tax_lines (invoice_id, company_id, tax_code, tax_base, tax_amount, surcharge_amount, deductible,
                                     deductible_amount)
  select v_inv, v_company, x.tax_code, x.tax_base, x.tax_amount, x.surcharge_amount, x.deductible,
         case when v_type = 'purchase' then x.deductible_amount else 0 end
  from jsonb_to_recordset(v_taxes) as x(tax_code text, tax_base numeric, tax_amount numeric, surcharge_amount numeric,
                                        deductible boolean, deductible_amount numeric);
  perform set_config('erp.invoice_engine', 'off', true);

  return query select v_inv, v_no, v_entry_no;
exception
  when unique_violation then
    raise exception 'Invoice % of % is already registered', v_ext, v_partner.name;
end $$;

-- ---------------------------------------------------------------------
-- LIQUIDACIÓN (sustituye al de la 0019): deducible = lo deducido; incluye la regularización de la prorrata
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
-- Libro registro con lo deducido (columna nueva al final)
-- ---------------------------------------------------------------------
create or replace view erp.v_invoice_register with (security_invoker = true) as
select i.company_id, fy.year as fiscal_year, i.id as invoice_id, i.invoice_type, i.document_kind,
       i.invoice_no, i.external_document_no, i.invoice_date, i.posting_date,
       bp.vat_registration_no, bp.name as partner_name, bp.tax_territory,
       t.tax_code, c.tax_type, c.rate_pct, t.tax_base, t.tax_amount, t.tax_base + t.tax_amount as total,
       je.entry_no,
       c.rate_category, c.exemption_key,
       t.surcharge_amount, t.deductible,
       t.deductible_amount
from erp.invoices i
join erp.fiscal_years fy        on fy.id = i.fiscal_year_id
join erp.business_partners bp  on bp.id = i.partner_id
join erp.invoice_tax_lines t    on t.invoice_id = i.id
join erp.tax_codes c            on c.code = t.tax_code
join erp.journal_entries je     on je.id = i.entry_id;

create or replace view erp.v_pro_rata with (security_invoker = true) as
select p.company_id, p.tax_type, p.year, p.provisional_pct, p.definitive_pct, p.regularization_amount,
       p.regularized_at, e.entry_no
from erp.pro_rata p
left join erp.journal_entries e on e.id = p.entry_id;

alter table erp.pro_rata enable row level security;
create policy read  on erp.pro_rata for select to authenticated using (erp.can_read(company_id));
create policy write on erp.pro_rata for all to authenticated
  using (erp.can_write(company_id)) with check (erp.can_write(company_id));

revoke all on erp.pro_rata, erp.v_pro_rata from anon, public;
grant select, insert, update, delete on erp.pro_rata to authenticated;
grant select on erp.v_pro_rata, erp.v_invoice_register to authenticated;
revoke execute on function erp.set_pro_rata(uuid, text, int, numeric), erp.pro_rata_calc(uuid, text, int),
  erp.post_pro_rata_regularization(uuid, text, int), erp.cancel_pro_rata_regularization(uuid, text, int) from anon, public;
grant execute on function erp.set_pro_rata(uuid, text, int, numeric), erp.pro_rata_calc(uuid, text, int),
  erp.post_pro_rata_regularization(uuid, text, int), erp.cancel_pro_rata_regularization(uuid, text, int) to authenticated;
