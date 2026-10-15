-- =====================================================================
-- erp.post_pro_rata_regularization · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0020_pro_rata   →   la vigente es la de 0020_pro_rata
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.post_pro_rata_regularization(p_company uuid, p_tax_type text, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
end $function$
;
