-- =====================================================================
-- erp.post_tax_settlement · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0012_tax_settlement   →   la vigente es la de 0012_tax_settlement
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.post_tax_settlement(p_company uuid, p_tax_type text, p_year integer, p_quarter integer, p_refund boolean DEFAULT false, p_accept_difference boolean DEFAULT false)
 RETURNS TABLE(settlement_id uuid, entry_no integer, final_result numeric, outcome text)
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  c         jsonb;
  v_fy      erp.fiscal_years;
  v_entry   uuid;
  v_no      int;
  v_id      uuid;
begin
  if not erp.can_write(p_company) then
    raise exception 'No permission to post tax settlements in this company';
  end if;
  perform pg_advisory_xact_lock(hashtext('settlement/' || p_company || '/' || p_tax_type));

  if exists (select 1 from erp.tax_settlements s where s.company_id = p_company and s.tax_type = p_tax_type
             and s.status = 'posted' and (s.year, s.quarter) >= (p_year, p_quarter)) then
    raise exception 'Quarter %T % (or a later one) is already settled', p_quarter, p_year;
  end if;

  c := erp.tax_settlement_calc(p_company, p_tax_type, p_year, p_quarter, p_refund);
  -- Control auditor: lo que se declara (libro registro) debe coincidir con la contabilidad (472/477).
  -- Si no coincide, hay que aceptarlo expresamente y la diferencia queda guardada en la liquidación.
  if (c->>'difference')::numeric <> 0 and not p_accept_difference then
    raise exception 'The invoice register and the tax accounts differ by %: review manual entries on 472/477 before settling',
      c->>'difference';
  end if;

  perform set_config('erp.tax_settlement_engine', 'on', true);

  if jsonb_array_length(c->'lines') > 0 then
    select * into v_fy from erp.fiscal_years
    where company_id = p_company and (c->>'period_end')::date between starting_date and ending_date;
    if v_fy.id is null then
      raise exception 'No fiscal year for %', c->>'period_end';
    end if;
    insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
    values (p_company, v_fy.id, (c->>'period_end')::date,
            'Liquidación ' || case p_tax_type when 'VAT' then 'IVA' else 'IGIC' end || ' ' || p_quarter || 'T ' || p_year
              || ' (modelo ' || (c->>'form') || ')',
            (c->>'form') || '-' || p_year || '-' || p_quarter || 'T')
    returning id into v_entry;

    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
    select v_entry, p_company, x.ord, g.id, (x.l->>'debit')::numeric, (x.l->>'credit')::numeric
    from jsonb_array_elements(c->'lines') with ordinality as x(l, ord)
    join erp.gl_accounts g on g.company_id = p_company and g.account_no = x.l->>'account_no';

    v_no := erp.post_entry(v_entry);
  end if;

  insert into erp.tax_settlements (company_id, tax_type, year, quarter, period_start, period_end, output_tax, input_tax,
                                   carry_applied, final_result, register_difference, outcome, entry_id)
  values (p_company, p_tax_type, p_year, p_quarter, (c->>'period_start')::date, (c->>'period_end')::date,
          (c->>'output_tax')::numeric, (c->>'input_tax')::numeric, (c->>'carry_applied')::numeric,
          (c->>'final_result')::numeric, (c->>'difference')::numeric, c->>'outcome', v_entry)
  returning id into v_id;

  perform set_config('erp.tax_settlement_engine', 'off', true);
  return query select v_id, v_no, (c->>'final_result')::numeric, c->>'outcome';
end $function$
;
