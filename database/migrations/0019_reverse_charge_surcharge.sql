-- =====================================================================
-- 0019 · REVERSE CHARGE & EQUIVALENCE SURCHARGE · Inversión del sujeto pasivo y recargo de equivalencia
--        (bloque J5, parte 2)
-- ---------------------------------------------------------------------
-- 1) INVERSIÓN DEL SUJETO PASIVO (ISP) y ADQUISICIÓN INTRACOMUNITARIA DE BIENES (AIB) · solo en compras
--      El proveedor factura SIN impuesto y es la EMPRESA quien lo declara: se lo repercute y se lo soporta.
--        472 (soportado) al Debe  =  477 (repercutido) al Haber   → efecto neto cero si es deducible
--      Casos: servicios de empresas de otro país de la UE o de fuera, obras de construcción, chatarra…
--             (en Canarias: servicios de empresas de la Península o del extranjero → ISP de IGIC)
--      Subcuentas propias: 472x8… / 477x8… (AIB) · 472x9… / 477x9… (ISP)
--    BC: "VAT Calculation Type = Reverse Charge VAT" · SAP: códigos de impuesto de autorrepercusión (tipo "E"/"I")
--
-- 2) RECARGO DE EQUIVALENCIA (RE) · comercio minorista de personas físicas en la Península (no existe en el IGIC)
--      Mayorista (régimen general) que vende a un cliente en RE: IVA + recargo (5,2 / 1,4 / 0,5 %) → 4770x7…
--      Minorista en RE (vat_regime = 'equivalence_surcharge'):
--        compras: IVA y recargo NO deducibles → mayor coste de la compra (a la misma cuenta del gasto)
--        ventas:  con el IVA incluido en el precio (código VAT_RE_INC): no presenta el 303 de esa actividad
-- =====================================================================

-- ---------------------------------------------------------------------
-- Datos nuevos
-- ---------------------------------------------------------------------
alter table erp.companies add column vat_regime text not null default 'general'
  check (vat_regime in ('general', 'equivalence_surcharge'));
comment on column erp.companies.vat_regime is 'VAT regime: general, or equivalence surcharge (retailer, mainland Spain only).';

alter table erp.business_partners add column equivalence_surcharge boolean not null default false;
comment on column erp.business_partners.equivalence_surcharge is 'Customer under the equivalence surcharge: sales add the surcharge.';

alter table erp.tax_setup add column surcharge_account_id uuid references erp.gl_accounts(id);   -- 4770x7… recargo repercutido

alter table erp.invoice_tax_lines
  add column surcharge_amount numeric(15,2) not null default 0,   -- recargo de equivalencia
  add column deductible boolean not null default true;            -- false: comerciante en RE (y, en el futuro, prorrata)

alter table erp.invoices add column total_surcharge numeric(15,2) not null default 0;

insert into erp.tax_codes
  (code, tax_type, rate_category, rate_pct, equivalence_surcharge_pct, valid_from, description, description_en) values
('VAT21_AIB', 'VAT',  'intra_eu_acquisition', 21, null, '1993-01-01', 'Adquisición intracomunitaria de bienes 21 %', 'Intra-EU acquisition of goods 21%'),
('VAT10_AIB', 'VAT',  'intra_eu_acquisition', 10, null, '2012-09-01', 'Adquisición intracomunitaria de bienes 10 %', 'Intra-EU acquisition of goods 10%'),
('VAT4_AIB',  'VAT',  'intra_eu_acquisition',  4, null, '1995-01-01', 'Adquisición intracomunitaria de bienes 4 %', 'Intra-EU acquisition of goods 4%'),
('VAT21_ISP', 'VAT',  'reverse_charge',       21, null, '1993-01-01', 'Inversión del sujeto pasivo 21 % (servicios de empresas extranjeras, obras, chatarra…)', 'Reverse charge 21% (services from foreign businesses, construction, scrap…)'),
('VAT10_ISP', 'VAT',  'reverse_charge',       10, null, '2012-09-01', 'Inversión del sujeto pasivo 10 % (p. ej. obras de renovación de viviendas)', 'Reverse charge 10% (e.g. home renovation works)'),
('IGIC7_ISP', 'IGIC', 'reverse_charge',        7, null, '2012-07-01', 'Inversión del sujeto pasivo IGIC 7 % (servicios de empresas de fuera de Canarias, obras…)', 'IGIC reverse charge 7% (services from businesses outside the Canary Islands, construction…)'),
('VAT_RE_INC','VAT',  'retail_surcharge',      0, null, '1993-01-01', 'Venta de comerciante en recargo de equivalencia (IVA incluido en el precio)', 'Sale of a retailer under the equivalence surcharge (VAT included in the price)');

-- Reglas: el RE solo existe en la Península
create or replace function erp.tg_company_vat_regime()
returns trigger language plpgsql as $$
begin
  if new.vat_regime = 'equivalence_surcharge' and new.tax_territory <> 'mainland' then
    raise exception 'The equivalence surcharge only exists for VAT (mainland Spain)';
  end if;
  return new;
end $$;
create trigger company_vat_regime before insert or update of vat_regime, tax_territory on erp.companies
  for each row execute function erp.tg_company_vat_regime();

create or replace function erp.tg_partner_equivalence()
returns trigger language plpgsql as $$
begin
  if new.equivalence_surcharge and (new.partner_type not in ('customer', 'debtor') or new.tax_territory <> 'mainland') then
    raise exception 'Only customers from mainland Spain can be under the equivalence surcharge';
  end if;
  return new;
end $$;
create trigger partner_equivalence before insert or update on erp.business_partners
  for each row execute function erp.tg_partner_equivalence();

-- ---------------------------------------------------------------------
-- Cuentas de los tipos especiales: se ponen solas al configurar el tipo (antes de validar la configuración)
--   472·x·8·rate  / 477·x·8·rate  → adquisición intracomunitaria
--   472·x·9·rate  / 477·x·9·rate  → inversión del sujeto pasivo
--   477·0·7·recargo×10            → recargo de equivalencia repercutido (5,2 → 052)
-- ---------------------------------------------------------------------
create or replace function erp.special_tax_account(
  p_company uuid, p_root text, p_tax_type text, p_marker text, p_value numeric, p_name text, p_name_en text)
returns uuid language plpgsql as $$
declare
  v_digits smallint;
  v_no     text;
  v_status text := 'linked';
  v_id     uuid;
begin
  select posting_account_digits into v_digits from erp.companies where id = p_company;
  v_no := p_root || case p_tax_type when 'VAT' then '0' else '1' end || p_marker
          || lpad(case when p_value = trunc(p_value) then p_value::int::text else (p_value * 10)::int::text end, v_digits - 5, '0');
  select e.account_id into v_id from erp.ensure_tax_account(p_company, v_no, p_name, p_name_en, v_status) e;
  return v_id;
end $$;

create or replace function erp.tg_tax_setup_special_accounts()
returns trigger language plpgsql as $$
declare
  c     erp.tax_codes;
  v_tax text;
  v_r   text;
begin
  select * into c from erp.tax_codes where code = new.tax_code;
  v_tax := case c.tax_type when 'VAT' then 'IVA' else 'IGIC' end;
  v_r := erp.tax_rate_text(c.rate_pct) || '%';
  if tg_op = 'INSERT' and c.rate_category = 'intra_eu_acquisition' then
    new.input_account_id  := erp.special_tax_account(new.company_id, '472', c.tax_type, '8', c.rate_pct,
      v_tax || ' soportado adq. intracomunitaria ' || v_r, 'Input VAT intra-EU acquisition ' || v_r);
    new.output_account_id := erp.special_tax_account(new.company_id, '477', c.tax_type, '8', c.rate_pct,
      v_tax || ' repercutido adq. intracomunitaria ' || v_r, 'Output VAT intra-EU acquisition ' || v_r);
  elsif tg_op = 'INSERT' and c.rate_category = 'reverse_charge' then
    new.input_account_id  := erp.special_tax_account(new.company_id, '472', c.tax_type, '9', c.rate_pct,
      v_tax || ' soportado ISP ' || v_r, 'Input ' || c.tax_type || ' reverse charge ' || v_r);
    new.output_account_id := erp.special_tax_account(new.company_id, '477', c.tax_type, '9', c.rate_pct,
      v_tax || ' repercutido ISP ' || v_r, 'Output ' || c.tax_type || ' reverse charge ' || v_r);
  end if;
  if c.equivalence_surcharge_pct is not null and new.surcharge_account_id is null and not new.blocked then
    new.surcharge_account_id := erp.special_tax_account(new.company_id, '477', 'VAT', '7', c.equivalence_surcharge_pct,
      'Recargo de equivalencia repercutido ' || erp.tax_rate_text(c.equivalence_surcharge_pct) || '%',
      'Equivalence surcharge ' || trim(trailing '.' from trim(trailing '0' from c.equivalence_surcharge_pct::text)) || '%');
  end if;
  return new;
end $$;

-- 'tax_setup_special…' se ejecuta antes que 'tax_setup_validate' (los triggers van por orden alfabético)
create trigger tax_setup_special_accounts before insert or update on erp.tax_setup
  for each row execute function erp.tg_tax_setup_special_accounts();

create or replace function erp.tg_tax_setup_validate()
returns trigger language plpgsql as $$
declare
  v_rate numeric;
begin
  select rate_pct into v_rate from erp.tax_codes where code = new.tax_code;
  perform erp.check_tax_account(new.company_id, new.input_account_id,  '472', 'input tax');
  perform erp.check_tax_account(new.company_id, new.output_account_id, '477', 'output tax');
  perform erp.check_tax_account(new.company_id, new.surcharge_account_id, '477', 'equivalence surcharge');
  if v_rate > 0 and not new.blocked and (new.input_account_id is null or new.output_account_id is null) then
    raise exception 'Tax code % needs an input (472) and an output (477) account', new.tax_code;
  end if;
  return new;
end $$;

-- Empresas existentes: los tipos nuevos y las cuentas del recargo
insert into erp.tax_setup (company_id, tax_code)
select distinct s.company_id, n.code
from erp.tax_setup s
join erp.tax_codes c on c.code = s.tax_code
join erp.tax_codes n on n.tax_type = c.tax_type
                    and n.rate_category in ('intra_eu_acquisition', 'reverse_charge', 'retail_surcharge')
on conflict do nothing;
update erp.tax_setup s set surcharge_account_id = null
from erp.tax_codes c
where c.code = s.tax_code and c.equivalence_surcharge_pct is not null and s.surcharge_account_id is null;

-- ---------------------------------------------------------------------
-- MOTOR DE FACTURAS (sustituye al de la 0018): ISP, AIB y recargo de equivalencia
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
      'cat', tc.rate_category, 're_pct', tc.equivalence_surcharge_pct,
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
    select w.tax_code as code, max(w.rate) as rate, max(w.re_pct) as re_pct, max(w.cat) as cat,
           sum(w.sign * w.amount) as base,
           (array_agg(w.in_acc))[1] as in_acc, (array_agg(w.out_acc))[1] as out_acc, (array_agg(w.re_acc))[1] as re_acc,
           (array_agg(w.gl_account_id order by w.n))[1] as first_acc
    from jsonb_to_recordset(v_work) as w(n int, tax_code text, rate numeric, re_pct numeric, cat text, sign int,
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

    if t.cat in ('reverse_charge', 'intra_eu_acquisition') then
      -- ISP / adquisición intracomunitaria: la EMPRESA se repercute y se soporta la cuota.
      -- 472 al Debe y 477 al Haber por el mismo importe; el proveedor no la cobra (no suma al total)
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := t.in_acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.in_acc;
      debit  := case when v_signed > 0 then v_signed else 0 end;
      credit := case when v_signed > 0 then 0 else -v_signed end;
      line_role := 'tax';
      return next;
      v_n := v_n + 1;
      line_no := v_n; gl_account_id := t.out_acc;
      select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = t.out_acc;
      debit  := case when v_signed > 0 then 0 else -v_signed end;
      credit := case when v_signed > 0 then v_signed else 0 end;
      line_role := 'tax_rc';
      return next;
      continue;
    end if;

    -- Cuota normal (o no deducible: comerciante en recargo de equivalencia → mayor coste, a la cuenta de la compra)
    v_side_acc := case when v_nd then t.first_acc when v_type = 'purchase' then t.in_acc else t.out_acc end;
    v_total := v_total + v_signed;
    v_n := v_n + 1;
    line_no := v_n; gl_account_id := v_side_acc;
    select g.account_no, g.name into account_no, account_name from erp.gl_accounts g where g.id = v_side_acc;
    debit  := case when (v_type = 'purchase') = (v_signed > 0) then abs(v_signed) else 0 end;
    credit := case when (v_type = 'purchase') = (v_signed > 0) then 0 else abs(v_signed) end;
    line_role := case when v_nd then 'tax_nd' else 'tax' end;
    return next;

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
-- REGISTRAR (sustituye al de la 0018): recargo, deducibilidad y total sin la cuota del ISP
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
           'surcharge_amount', x.surcharge, 'deductible', x.deductible, 'reverse_charge', x.rc))
    into v_taxes
  from (
    select e.tax_code, max(e.tax_base) as tax_base,
           coalesce(sum(e.sgn) filter (where e.line_role in ('tax', 'tax_nd')), 0) as tax_amount,
           coalesce(sum(e.sgn) filter (where e.line_role in ('surcharge', 'surcharge_nd')), 0) as surcharge,
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

  insert into erp.invoice_tax_lines (invoice_id, company_id, tax_code, tax_base, tax_amount, surcharge_amount, deductible)
  select v_inv, v_company, x.tax_code, x.tax_base, x.tax_amount, x.surcharge_amount, x.deductible
  from jsonb_to_recordset(v_taxes) as x(tax_code text, tax_base numeric, tax_amount numeric, surcharge_amount numeric,
                                        deductible boolean);
  perform set_config('erp.invoice_engine', 'off', true);

  return query select v_inv, v_no, v_entry_no;
exception
  when unique_violation then
    raise exception 'Invoice % of % is already registered', v_ext, v_partner.name;
end $$;

-- ---------------------------------------------------------------------
-- LIQUIDACIÓN (sustituye al de la 0012): el ISP devenga y deduce; el recargo se ingresa; lo no deducible no cuenta
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
      select case r.invoice_type when 'sale' then 'output' else 'input' end as side, 'tax' as kind,
             r.tax_code, r.rate_pct, r.tax_base as base, r.tax_amount as amount
      from erp.v_invoice_register r
      where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between v_start and v_end
        and (r.invoice_type = 'sale' or r.deductible)
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
-- Vistas (columnas nuevas al final)
-- ---------------------------------------------------------------------
create or replace view erp.v_invoice_register with (security_invoker = true) as
select i.company_id, fy.year as fiscal_year, i.id as invoice_id, i.invoice_type, i.document_kind,
       i.invoice_no, i.external_document_no, i.invoice_date, i.posting_date,
       bp.vat_registration_no, bp.name as partner_name, bp.tax_territory,
       t.tax_code, c.tax_type, c.rate_pct, t.tax_base, t.tax_amount, t.tax_base + t.tax_amount as total,
       je.entry_no,
       c.rate_category, c.exemption_key,
       t.surcharge_amount, t.deductible
from erp.invoices i
join erp.fiscal_years fy        on fy.id = i.fiscal_year_id
join erp.business_partners bp  on bp.id = i.partner_id
join erp.invoice_tax_lines t    on t.invoice_id = i.id
join erp.tax_codes c            on c.code = t.tax_code
join erp.journal_entries je     on je.id = i.entry_id;

create or replace view erp.v_invoices with (security_invoker = true) as
select i.id, i.company_id, fy.year as fiscal_year, i.invoice_type, i.document_kind, i.invoice_no,
       i.external_document_no, i.invoice_date, i.posting_date, i.description,
       i.partner_id, bp.name as partner_name, bp.vat_registration_no, g.account_no as partner_account_no,
       i.total_base, i.total_tax, i.total_amount, je.entry_no,
       ci.invoice_no as corrected_invoice_no, coalesce(ci.external_document_no, i.corrected_reference) as corrected_reference,
       i.withholding_code, i.withholding_base, i.withholding_amount,
       i.total_amount - i.withholding_amount as amount_due,
       i.total_surcharge
from erp.invoices i
join erp.fiscal_years fy        on fy.id = i.fiscal_year_id
join erp.business_partners bp  on bp.id = i.partner_id
left join erp.gl_accounts g     on g.id = bp.gl_account_id
join erp.journal_entries je     on je.id = i.entry_id
left join erp.invoices ci       on ci.id = i.corrected_invoice_id;

create or replace view erp.v_partners with (security_invoker = true) as
select bp.id, bp.company_id, bp.partner_type, bp.vat_registration_no, bp.name, bp.tax_territory,
       bp.email, bp.blocked, bp.created_at,
       g.account_no,
       coalesce((select sum(l.debit - l.credit)
                 from erp.journal_lines l
                 join erp.journal_entries e on e.id = l.entry_id
                 where l.gl_account_id = bp.gl_account_id and e.status = 'posted'), 0) as balance,
       bp.equivalence_surcharge
from erp.business_partners bp
left join erp.gl_accounts g on g.id = bp.gl_account_id;

create or replace view erp.v_my_companies with (security_invoker = true) as
select c.id, c.name, c.vat_registration_no, c.industry, c.tax_territory,
       c.posting_account_digits, c.is_demo, c.created_at,
       erp.my_role(c.id) as my_role,
       c.vat_regime
from erp.companies c;

create or replace view erp.v_tax_setup with (security_invoker = true) as
select s.company_id, s.tax_code, c.tax_type, c.rate_category, c.rate_pct,
       c.equivalence_surcharge_pct, c.description, c.description_en, s.blocked,
       s.input_account_id,  ai.account_no as input_account_no,  ai.name as input_account_name,
       s.output_account_id, ao.account_no as output_account_no, ao.name as output_account_name,
       c.exemption_key,
       s.surcharge_account_id, ar.account_no as surcharge_account_no, ar.name as surcharge_account_name
from erp.tax_setup s
join erp.tax_codes c on c.code = s.tax_code
left join erp.gl_accounts ai on ai.id = s.input_account_id
left join erp.gl_accounts ao on ao.id = s.output_account_id
left join erp.gl_accounts ar on ar.id = s.surcharge_account_id;

-- Régimen de IVA de la empresa (solo el administrador)
create or replace function erp.set_vat_regime(p_company uuid, p_regime text)
returns void language plpgsql as $$
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can change the VAT regime';
  end if;
  update erp.companies set vat_regime = p_regime where id = p_company;
end $$;

grant select on erp.v_invoice_register, erp.v_invoices, erp.v_partners, erp.v_my_companies, erp.v_tax_setup to authenticated;
revoke execute on function erp.special_tax_account(uuid, text, text, text, numeric, text, text),
  erp.set_vat_regime(uuid, text) from anon, public;
grant execute on function erp.special_tax_account(uuid, text, text, text, numeric, text, text),
  erp.set_vat_regime(uuid, text) to authenticated;
