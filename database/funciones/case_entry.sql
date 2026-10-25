-- =====================================================================
-- erp.case_entry · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0066_complete_case   →   la vigente es la de 0066_complete_case
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.case_entry(e uuid, p_date date, p_desc text, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'erp', 'public'
AS $function$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = extract(year from p_date)), p_date, p_desc) returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord,
         (select g.id from erp.gl_accounts g where g.company_id = e and g.account_type = 'posting' and g.account_no like (x.v->>0) || '%'
          order by g.account_no limit 1),
         (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(p_lines) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  return a;
end $function$
;
