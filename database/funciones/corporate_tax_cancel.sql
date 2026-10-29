-- =====================================================================
-- erp.corporate_tax_cancel · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0058_corporate_tax_posting   →   la vigente es la de 0058_corporate_tax_posting
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_cancel(p_company uuid, p_year integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_fy erp.fiscal_years; r erp.corporate_tax_returns;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to change the corporate tax of this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  select * into r from erp.corporate_tax_returns where fiscal_year_id = v_fy.id;
  if r.status is distinct from 'posted' then raise exception 'The corporate tax of % is not posted', p_year; end if;
  if v_fy.status = 'closed' or exists (select 1 from erp.year_closings c where c.company_id = p_company and c.fiscal_year_id = v_fy.id and c.status = 'posted') then
    raise exception 'The year % is closed: reopen it first', p_year;
  end if;
  if exists (select 1 from erp.corporate_tax_returns x join erp.fiscal_years f on f.id = x.fiscal_year_id
             where x.company_id = p_company and x.status = 'posted' and f.year > p_year) then
    raise exception 'A later corporate tax is posted: undo it first (it uses this one)';
  end if;
  if r.current_entry_id is not null then perform erp.adjust_reverse(r.current_entry_id, v_fy.ending_date, 'Deshacer el Impuesto sobre Sociedades'); end if;
  if r.deferred_entry_id is not null then perform erp.adjust_reverse(r.deferred_entry_id, v_fy.ending_date, 'Deshacer el Impuesto sobre Sociedades'); end if;
  update erp.corporate_tax_returns set status = 'draft', result = null, current_entry_id = null, deferred_entry_id = null, posted_at = null
  where id = r.id;
end $function$
;
