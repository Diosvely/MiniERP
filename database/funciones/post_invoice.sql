-- =====================================================================
-- erp.post_invoice · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0011_invoices 0018_withholding_exempt 0019_reverse_charge_surcharge 0020_pro_rata   →   la vigente es la de 0020_pro_rata
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.post_invoice(p jsonb)
 RETURNS TABLE(invoice_id uuid, invoice_no text, entry_no integer)
 LANGUAGE plpgsql
AS $function$
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
end $function$
;
