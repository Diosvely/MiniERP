-- =====================================================================
-- erp.invoice_entry_lines · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0011_invoices 0018_withholding_exempt 0019_reverse_charge_surcharge 0020_pro_rata 0041_fixed_assets 0061_equity_integration 0063_financing_integration   →   la vigente es la de 0063_financing_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.invoice_entry_lines(p jsonb)
 RETURNS TABLE(line_no integer, gl_account_id uuid, account_no text, account_name text, debit numeric, credit numeric, tax_code text, tax_base numeric, line_role text, src_line integer, amount numeric, sign integer, description text)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
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
    -- v0.43.0: la cuota de un leasing (desde Financiación): 174 / 524 (principal) y 527 / 528 (intereses devengados)
    if v_type = 'purchase' and a.account_no ~ '^(174|524|527|528)' and coalesce(current_setting('erp.loan_engine', true), '') <> 'on' then
      raise exception 'Line %: account % belongs to a finance lease: register the instalment invoice from Financing', r.n, a.account_no;
    end if;
    if v_type = 'purchase' and left(a.account_no, 1) not in ('2', '6') and a.account_no not like '113%'
       and not (a.account_no ~ '^(174|524|527|528)' and coalesce(current_setting('erp.loan_engine', true), '') = 'on') then
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
