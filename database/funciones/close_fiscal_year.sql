-- =====================================================================
-- erp.close_fiscal_year · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0017_year_closing   →   la vigente es la de 0017_year_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.close_fiscal_year(p_company uuid, p_year integer, p_accept_warnings boolean DEFAULT false)
 RETURNS TABLE(closing_id uuid, result numeric, closing_pl_no integer, closing_no integer, opening_no integer)
 LANGUAGE plpgsql
AS $function$
declare
  c        jsonb;
  v_fy     erp.fiscal_years;
  v_next   uuid;
  v_pl     uuid;
  v_close  uuid;
  v_open   uuid;
  v_id     uuid;
  v_res_no text;
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can close the fiscal year';
  end if;
  perform pg_advisory_xact_lock(hashtext('closing/' || p_company));

  c := erp.year_closing_preview(p_company, p_year);
  if (c->>'status') = 'closed' then
    raise exception 'Fiscal year % is already closed', p_year;
  end if;
  if not (c->>'can_close')::boolean then
    raise exception 'Fiscal year % cannot be closed: %', p_year,
      (select string_agg((x->>'code') || ' (' || (x->>'detail') || ')', ', ')
       from jsonb_array_elements(c->'checks') x where x->>'severity' = 'error');
  end if;
  if (c->>'has_warnings')::boolean and not p_accept_warnings then
    raise exception 'Review and accept the warnings before closing: %',
      (select string_agg((x->>'code') || ' (' || (x->>'detail') || ')', ', ')
       from jsonb_array_elements(c->'checks') x where x->>'severity' = 'warning');
  end if;

  perform set_config('erp.year_closing_engine', 'on', true);
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;

  -- Subcuenta 129 y ejercicio siguiente, si no existen
  v_res_no := c->>'result_account_no';
  if not exists (select 1 from erp.gl_accounts where company_id = p_company and account_no = v_res_no) then
    perform erp.create_posting_account(p_company, v_res_no, 'Resultado del ejercicio', 'Profit (loss) for the year');
  end if;
  select id into v_next from erp.fiscal_years where company_id = p_company and year = p_year + 1;
  if v_next is null then
    v_next := erp.create_fiscal_year(p_company, p_year + 1);
  end if;

  -- 2) Regularización · 3) Cierre (31/12) · 4) Apertura (1/1), con las líneas del cierre al revés
  v_pl := erp.post_closing_entry(p_company, v_fy.id, v_fy.ending_date, 'closing_pl',
            'Regularización del ejercicio ' || p_year, 'REG-' || p_year, c->'closing_pl_lines');
  v_close := erp.post_closing_entry(p_company, v_fy.id, v_fy.ending_date, 'closing',
            'Asiento de cierre del ejercicio ' || p_year, 'CIE-' || p_year, c->'closing_lines');
  v_open := erp.post_closing_entry(p_company, v_next, v_fy.ending_date + 1, 'opening',
            'Asiento de apertura del ejercicio ' || (p_year + 1), 'APE-' || (p_year + 1),
            (select coalesce(jsonb_agg(jsonb_build_object('account_no', l->>'account_no',
                               'debit', l->'credit', 'credit', l->'debit')), '[]')
             from jsonb_array_elements(c->'closing_lines') l));

  insert into erp.year_closings (company_id, fiscal_year_id, year, result, closing_pl_entry_id, closing_entry_id,
                                 opening_entry_id, warnings)
  values (p_company, v_fy.id, p_year, (c->>'result')::numeric, v_pl, v_close, v_open,
          (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(c->'checks') x where x->>'severity' = 'warning'))
  returning id into v_id;

  update erp.fiscal_years set status = 'closed' where id = v_fy.id;
  perform set_config('erp.year_closing_engine', 'off', true);

  return query select v_id, (c->>'result')::numeric,
    (select entry_no from erp.journal_entries where id = v_pl),
    (select entry_no from erp.journal_entries where id = v_close),
    (select entry_no from erp.journal_entries where id = v_open);
end $function$
;
