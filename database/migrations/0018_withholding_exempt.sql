-- =====================================================================
-- 0018 · WITHHOLDING & EXEMPT OPERATIONS · Retención IRPF y operaciones sin cuota (bloque J5, parte 1)
-- ---------------------------------------------------------------------
-- 1) OPERACIONES SIN CUOTA, cada una con su causa (la que pide el libro registro / SII):
--      IVA   E1 exenta art. 20 · E2 exportación art. 21 (incluye envíos a Canarias, Ceuta y Melilla)
--            E5 entrega intracomunitaria art. 25 · N2 no sujeta por reglas de localización
--      IGIC  exenta · exportación (envíos a la Península, la UE o terceros países) · no sujeta
--    Reglas: exportación y entrega intracomunitaria solo en ventas; intracomunitaria solo a clientes de la UE;
--            exportación y no sujeta solo con terceros de fuera del territorio de la empresa.
--
-- 2) RETENCIÓN IRPF en la factura (profesionales 15 % / 7 % · alquileres 19 %), sobre la base imponible:
--      factura RECIBIDA → la empresa retiene: 4751 al Haber y la ingresa con el modelo 111 (profesionales) o 115 (alquileres)
--      factura EMITIDA  → el cliente nos retiene: 473 al Debe (pago a cuenta de nuestro impuesto)
--      el tercero queda por: base + cuota − retención
--    Como el "IRPF Withholding" de las localizaciones españolas de BC o los "Withholding tax codes" de SAP (FTXP / WHT).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Causas de las operaciones sin cuota
-- ---------------------------------------------------------------------
alter table erp.tax_codes add column exemption_key text;
comment on column erp.tax_codes.exemption_key is
  'Exemption / non-subject key of the invoice register (SII): E1 art. 20, E2 export, E5 intra-EU supply, N2 place-of-supply rules.';

insert into erp.tax_codes
  (code, tax_type, rate_category, rate_pct, equivalence_surcharge_pct, valid_from, description, description_en, exemption_key) values
('VAT_E20', 'VAT',  'exempt',      0, null, '1993-01-01', 'Exenta art. 20 (sanidad, enseñanza, seguros, alquiler de vivienda…)', 'Exempt, art. 20 (health, education, insurance, residential rent…)', 'E1'),
('VAT_EXP', 'VAT',  'export',      0, null, '1993-01-01', 'Exportación exenta art. 21 (incluye envíos a Canarias, Ceuta y Melilla)', 'Exempt export, art. 21 (incl. supplies to the Canary Islands, Ceuta and Melilla)', 'E2'),
('VAT_EU',  'VAT',  'intra_eu',    0, null, '1993-01-01', 'Entrega intracomunitaria exenta art. 25', 'Exempt intra-EU supply, art. 25', 'E5'),
('VAT_NS',  'VAT',  'not_subject', 0, null, '1993-01-01', 'No sujeta por reglas de localización (servicios a empresas de fuera del territorio)', 'Out of scope: place-of-supply rules (services to businesses outside the territory)', 'N2'),
('IGIC_E',  'IGIC', 'exempt',      0, null, '1993-01-01', 'Exenta (sanidad, enseñanza, seguros, alquiler de vivienda…)', 'Exempt (health, education, insurance, residential rent…)', 'E1'),
('IGIC_EXP','IGIC', 'export',      0, null, '1993-01-01', 'Exportación exenta (envíos a la Península, Baleares, la UE o terceros países)', 'Exempt export (supplies to mainland Spain, the Balearic Islands, the EU or third countries)', 'E2'),
('IGIC_NS', 'IGIC', 'not_subject', 0, null, '1993-01-01', 'No sujeta por reglas de localización (servicios a empresas de fuera de Canarias)', 'Out of scope: place-of-supply rules (services to businesses outside the Canary Islands)', 'N2');

-- Las empresas que ya tienen el impuesto configurado reciben los tipos nuevos (no llevan cuentas: no hay cuota)
insert into erp.tax_setup (company_id, tax_code)
select distinct s.company_id, n.code
from erp.tax_setup s
join erp.tax_codes c on c.code = s.tax_code
join erp.tax_codes n on n.tax_type = c.tax_type and n.exemption_key is not null
on conflict do nothing;

-- ---------------------------------------------------------------------
-- 2) Retenciones IRPF
-- ---------------------------------------------------------------------
create table erp.withholding_codes (
  code            text primary key,
  kind            text not null check (kind in ('professional', 'rent')),
  rate_pct        numeric(5,2) not null check (rate_pct > 0),
  form            text not null,          -- modelo trimestral en el que se declara la retención practicada
  valid_from      date not null,
  valid_to        date,
  description     text not null,
  description_en  text not null
);
insert into erp.withholding_codes (code, kind, rate_pct, form, valid_from, description, description_en) values
('IRPF15', 'professional', 15, '111', '2015-07-12', 'Profesionales (tipo general)', 'Professionals (standard rate)'),
('IRPF7',  'professional',  7, '111', '2015-07-12', 'Profesionales en inicio de actividad (año de alta y dos siguientes)', 'Professionals starting their activity (first three years)'),
('IRPF19', 'rent',         19, '115', '2016-01-01', 'Alquiler de locales e inmuebles urbanos', 'Rent of urban premises');
comment on table erp.withholding_codes is 'Personal income tax (IRPF) withholding rates. Always check against current legislation.';

create table erp.withholding_setup (
  company_id             uuid not null references erp.companies(id) on delete cascade,
  withholding_code       text not null references erp.withholding_codes(code),
  payable_account_id     uuid not null references erp.gl_accounts(id),   -- 4751 · retenciones practicadas (compras)
  receivable_account_id  uuid not null references erp.gl_accounts(id),   -- 473  · retenciones soportadas (ventas)
  blocked                boolean not null default false,
  primary key (company_id, withholding_code)
);

create or replace function erp.tg_withholding_setup_validate()
returns trigger language plpgsql as $$
begin
  perform erp.check_tax_account(new.company_id, new.payable_account_id,    '4751', 'withholding payable');
  perform erp.check_tax_account(new.company_id, new.receivable_account_id, '473',  'withholding receivable');
  return new;
end $$;

create trigger withholding_setup_validate before insert or update on erp.withholding_setup
  for each row execute function erp.tg_withholding_setup_validate();

-- Crea las cuentas y la configuración (sin comprobar permisos: lo llaman setup_withholdings y la migración)
--   4751…1 retenciones de profesionales (mod. 111) · 4751…5 retenciones de alquileres (mod. 115) · 473…1 retenciones soportadas
create or replace function erp.withholding_setup_core(p_company uuid)
returns table (withholding_code text, account_role text, account_no text, status text)
language plpgsql as $$
declare
  v_digits smallint;
  w        erp.withholding_codes;
  v_pay    uuid;
  v_rec    uuid;
  v_st     text;
  v_no     text;
begin
  select posting_account_digits into v_digits from erp.companies where id = p_company;
  for w in select * from erp.withholding_codes where valid_to is null or valid_to >= current_date order by code loop
    if exists (select 1 from erp.withholding_setup s where s.company_id = p_company and s.withholding_code = w.code) then
      withholding_code := w.code; account_role := null; account_no := null; status := 'existing';
      return next;
      continue;
    end if;
    v_no := rpad('4751', v_digits - 1, '0') || case w.form when '115' then '5' else '1' end;
    v_st := 'linked';
    select e.status, e.account_id into v_st, v_pay
    from erp.ensure_tax_account(p_company, v_no,
           'HP acreedora por retenciones practicadas (mod. ' || w.form || ')',
           'Withholdings payable (form ' || w.form || ')', v_st) e;
    withholding_code := w.code; account_role := 'payable'; account_no := v_no; status := v_st;
    return next;

    v_no := rpad('473', v_digits - 1, '0') || '1';
    v_st := 'linked';
    select e.status, e.account_id into v_st, v_rec
    from erp.ensure_tax_account(p_company, v_no, 'HP retenciones y pagos a cuenta', 'Withholdings and payments on account', v_st) e;
    withholding_code := w.code; account_role := 'receivable'; account_no := v_no; status := v_st;
    return next;

    insert into erp.withholding_setup (company_id, withholding_code, payable_account_id, receivable_account_id)
    values (p_company, w.code, v_pay, v_rec);
  end loop;
end $$;

create or replace function erp.setup_withholdings(p_company uuid)
returns table (withholding_code text, account_role text, account_no text, status text)
language plpgsql as $$
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can configure withholdings';
  end if;
  return query select * from erp.withholding_setup_core(p_company);
end $$;

-- Las empresas que ya configuraron sus impuestos quedan también con las retenciones configuradas
do $$
declare c uuid;
begin
  for c in select distinct company_id from erp.tax_setup loop
    perform erp.withholding_setup_core(c);
  end loop;
end $$;

-- Y las que lo configuren a partir de ahora, también (al crear las cuentas de la liquidación de IVA / IGIC)
create or replace function erp.tg_withholding_auto_setup()
returns trigger language plpgsql as $$
begin
  perform erp.withholding_setup_core(new.company_id);
  return new;
end $$;

create trigger withholding_auto_setup after insert on erp.tax_settlement_setup
  for each row execute function erp.tg_withholding_auto_setup();

-- La factura guarda su retención
alter table erp.invoices
  add column withholding_code    text references erp.withholding_codes(code),
  add column withholding_base    numeric(15,2),
  add column withholding_amount  numeric(15,2) not null default 0;   -- con signo: negativo en rectificativas

-- ---------------------------------------------------------------------
-- MOTOR DE FACTURAS (sustituye al de la 0011): causas de exención y retención
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

    -- Regla del lado: reducen las cuentas 606/608/609 · 706/708/709 y todas las líneas de una rectificativa
    v_sign := case when v_kind = 'credit_memo'
                     or a.template_account in ('606', '608', '609', '706', '708', '709') then -1 else 1 end;

    v_work := v_work || jsonb_build_object(
      'n', r.n, 'gl_account_id', a.id, 'account_no', a.account_no, 'account_name', a.name,
      'amount', round(r.amount_txt::numeric, 2), 'tax_code', r.code, 'sign', v_sign, 'rate', tc.rate_pct,
      'description', r.descr,
      'tax_account', case v_type when 'purchase' then s.input_account_id else s.output_account_id end);
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
    select w.tax_code as code, max(w.rate) as rate, sum(w.sign * w.amount) as base,
           (array_agg(w.tax_account))[1] as acc
    from jsonb_to_recordset(v_work) as w(tax_code text, rate numeric, sign int, amount numeric, tax_account uuid)
    group by w.tax_code order by w.tax_code
  loop
    v_signed := round(t.base * t.rate / 100, 2);
    v_total := v_total + v_signed;
    src_line := null; amount := null; sign := null; description := null;
    tax_code := t.code; tax_base := t.base;
    if v_signed <> 0 then
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := t.acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.acc;
      debit  := case when (v_type = 'purchase') = (v_signed > 0) then abs(v_signed) else 0 end;
      credit := case when (v_type = 'purchase') = (v_signed > 0) then 0 else abs(v_signed) end;
      line_role := 'tax';
    else
      -- tipo 0 % o exento: no hay apunte, pero sí base para el libro registro
      line_no := null; gl_account_id := null; account_no := null; account_name := null;
      debit := 0; credit := 0; line_role := 'tax_exempt';
    end if;
    return next;
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
-- REGISTRAR (sustituye al de la 0011): guarda la retención en la factura
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
  select jsonb_agg(jsonb_build_object('tax_code', e.tax_code, 'tax_base', e.tax_base,
           'tax_amount', case when e.line_role = 'tax_exempt' then 0
                              when (v_type = 'purchase') = (e.debit > 0) then e.debit + e.credit
                              else -(e.debit + e.credit) end))
    into v_taxes
  from jsonb_to_recordset(v_lines) as e(tax_code text, tax_base numeric, debit numeric, credit numeric, line_role text)
  where e.line_role in ('tax', 'tax_exempt');
  select sum(x.tax_base), sum(x.tax_amount) into v_base, v_tax
  from jsonb_to_recordset(v_taxes) as x(tax_base numeric, tax_amount numeric);

  perform set_config('erp.invoice_engine', 'on', true);
  insert into erp.invoices (company_id, fiscal_year_id, invoice_type, document_kind, invoice_no, external_document_no,
                            partner_id, invoice_date, posting_date, description, corrected_invoice_id, corrected_reference,
                            total_base, total_tax, total_amount, entry_id,
                            withholding_code, withholding_base, withholding_amount)
  values (v_company, v_fy.id, v_type, v_kind, v_no, v_ext, v_partner.id, v_date, v_posting,
          coalesce(v_desc, ''), v_corr, v_corr_ref, v_base, v_tax, v_base + v_tax, v_entry,
          case when v_wh_amt is not null then v_wh_code end, v_wh_base, coalesce(v_wh_amt, 0))
  returning id into v_inv;

  insert into erp.invoice_lines (invoice_id, company_id, line_no, gl_account_id, description, amount, tax_code, sign)
  select v_inv, v_company, e.src_line, e.gl_account_id, e.description, e.amount, e.tax_code, e.sign
  from jsonb_to_recordset(v_lines) as e(src_line int, gl_account_id uuid, description text, amount numeric,
                                        tax_code text, sign int, line_role text)
  where e.line_role = 'base';

  insert into erp.invoice_tax_lines (invoice_id, company_id, tax_code, tax_base, tax_amount)
  select v_inv, v_company, x.tax_code, x.tax_base, x.tax_amount
  from jsonb_to_recordset(v_taxes) as x(tax_code text, tax_base numeric, tax_amount numeric);
  perform set_config('erp.invoice_engine', 'off', true);

  return query select v_inv, v_no, v_entry_no;
exception
  when unique_violation then
    raise exception 'Invoice % of % is already registered', v_ext, v_partner.name;
end $$;

-- ---------------------------------------------------------------------
-- Vistas: lista de facturas con retención y libro registro con la causa de exención
-- (columnas nuevas al final: create or replace view solo permite añadir por detrás)
-- ---------------------------------------------------------------------
create or replace view erp.v_invoices with (security_invoker = true) as
select i.id, i.company_id, fy.year as fiscal_year, i.invoice_type, i.document_kind, i.invoice_no,
       i.external_document_no, i.invoice_date, i.posting_date, i.description,
       i.partner_id, bp.name as partner_name, bp.vat_registration_no, g.account_no as partner_account_no,
       i.total_base, i.total_tax, i.total_amount, je.entry_no,
       ci.invoice_no as corrected_invoice_no, coalesce(ci.external_document_no, i.corrected_reference) as corrected_reference,
       i.withholding_code, i.withholding_base, i.withholding_amount,
       i.total_amount - i.withholding_amount as amount_due      -- líquido a pagar / cobrar
from erp.invoices i
join erp.fiscal_years fy        on fy.id = i.fiscal_year_id
join erp.business_partners bp  on bp.id = i.partner_id
left join erp.gl_accounts g     on g.id = bp.gl_account_id
join erp.journal_entries je     on je.id = i.entry_id
left join erp.invoices ci       on ci.id = i.corrected_invoice_id;

create or replace view erp.v_invoice_register with (security_invoker = true) as
select i.company_id, fy.year as fiscal_year, i.id as invoice_id, i.invoice_type, i.document_kind,
       i.invoice_no, i.external_document_no, i.invoice_date, i.posting_date,
       bp.vat_registration_no, bp.name as partner_name, bp.tax_territory,
       t.tax_code, c.tax_type, c.rate_pct, t.tax_base, t.tax_amount, t.tax_base + t.tax_amount as total,
       je.entry_no,
       c.rate_category, c.exemption_key
from erp.invoices i
join erp.fiscal_years fy        on fy.id = i.fiscal_year_id
join erp.business_partners bp  on bp.id = i.partner_id
join erp.invoice_tax_lines t    on t.invoice_id = i.id
join erp.tax_codes c            on c.code = t.tax_code
join erp.journal_entries je     on je.id = i.entry_id;

-- ---------------------------------------------------------------------
-- Registro de retenciones (una fila por factura) y resumen trimestral (modelos 111 / 115)
-- ---------------------------------------------------------------------
create or replace view erp.v_withholding_register with (security_invoker = true) as
select i.company_id, fy.year as fiscal_year, extract(quarter from i.posting_date)::int as quarter,
       i.id as invoice_id, i.invoice_type,
       case i.invoice_type when 'purchase' then 'withheld' else 'suffered' end as side,  -- practicada / soportada
       w.code as withholding_code, w.kind, w.form, w.rate_pct,
       i.invoice_no, i.external_document_no, i.invoice_date, i.posting_date,
       bp.id as partner_id, bp.vat_registration_no, bp.name as partner_name,
       i.withholding_base, i.withholding_amount, je.entry_no
from erp.invoices i
join erp.withholding_codes w    on w.code = i.withholding_code
join erp.fiscal_years fy        on fy.id = i.fiscal_year_id
join erp.business_partners bp  on bp.id = i.partner_id
join erp.journal_entries je     on je.id = i.entry_id
where i.withholding_amount <> 0;

create or replace function erp.withholding_summary(p_company uuid, p_year int, p_quarter int)
returns table (side text, form text, withholding_code text, rate_pct numeric,
               recipients int, base numeric, amount numeric)
language sql stable as $$
  select r.side, case r.side when 'withheld' then r.form end, r.withholding_code, r.rate_pct,
         count(distinct r.partner_id)::int, sum(r.withholding_base), sum(r.withholding_amount)
  from erp.v_withholding_register r
  where r.company_id = p_company and r.fiscal_year = p_year and r.quarter = p_quarter
  group by r.side, r.form, r.withholding_code, r.rate_pct
  order by r.side desc, r.form, r.withholding_code;
$$;

-- ---------------------------------------------------------------------
-- Seguridad
-- ---------------------------------------------------------------------
alter table erp.withholding_codes enable row level security;
alter table erp.withholding_setup enable row level security;
create policy read on erp.withholding_codes for select to authenticated using (true);
create policy read   on erp.withholding_setup for select to authenticated using (erp.can_read(company_id));
create policy manage on erp.withholding_setup for all to authenticated
  using (erp.is_admin(company_id)) with check (erp.is_admin(company_id));

create or replace view erp.v_withholding_setup with (security_invoker = true) as
select s.company_id, s.withholding_code, w.kind, w.rate_pct, w.form, w.description, w.description_en, s.blocked,
       ap.account_no as payable_account_no, ap.name as payable_account_name,
       ar.account_no as receivable_account_no, ar.name as receivable_account_name
from erp.withholding_setup s
join erp.withholding_codes w on w.code = s.withholding_code
join erp.gl_accounts ap on ap.id = s.payable_account_id
join erp.gl_accounts ar on ar.id = s.receivable_account_id;

revoke all on erp.withholding_codes, erp.withholding_setup, erp.v_withholding_setup, erp.v_withholding_register from anon, public;
grant select on erp.withholding_codes, erp.v_withholding_setup, erp.v_withholding_register, erp.v_invoices, erp.v_invoice_register to authenticated;
grant select, insert, update, delete on erp.withholding_setup to authenticated;

revoke execute on function erp.withholding_setup_core(uuid), erp.setup_withholdings(uuid),
  erp.withholding_summary(uuid, int, int), erp.tg_withholding_auto_setup() from anon, public;
grant execute on function erp.withholding_setup_core(uuid), erp.setup_withholdings(uuid),
  erp.withholding_summary(uuid, int, int), erp.tg_withholding_auto_setup() to authenticated;
