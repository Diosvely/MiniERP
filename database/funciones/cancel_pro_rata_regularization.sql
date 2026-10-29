-- =====================================================================
-- erp.cancel_pro_rata_regularization · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0020_pro_rata   →   la vigente es la de 0020_pro_rata
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cancel_pro_rata_regularization(p_company uuid, p_tax_type text, p_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
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
end $function$
;
