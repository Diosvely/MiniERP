-- =====================================================================
-- erp.corporate_tax_draft · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_draft(p_return uuid)
 RETURNS erp.corporate_tax_returns
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare r erp.corporate_tax_returns;
begin
  select * into r from erp.corporate_tax_returns where id = p_return;
  if not found then raise exception 'Corporate tax return not found'; end if;
  if not erp.can_write(r.company_id) then raise exception 'No permission to change the corporate tax of this company'; end if;
  if r.status <> 'draft' then raise exception 'The corporate tax is already posted: cancel it first'; end if;
  return r;
end $function$
;
