-- =====================================================================
-- erp.tg_import_batch_temporary · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0072_temporary_companies   →   la vigente es la de 0072_temporary_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_import_batch_temporary()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
begin
  if auth.uid() is not null and not erp.is_trusted()
     and not exists (select 1 from erp.companies where id = new.company_id and temporary) then
    raise exception 'Registered users import into a temporary company';
  end if;
  return new;
end $function$
;
