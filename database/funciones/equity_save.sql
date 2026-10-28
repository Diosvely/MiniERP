-- =====================================================================
-- erp.equity_save · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_save(p_company uuid, p_code text, p_kind text, p_date date, p_desc text, p_data jsonb, p_result jsonb, p_entries uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_id uuid;
begin
  insert into erp.equity_operations (company_id, code, kind, op_date, description, data, result, entry_ids)
  values (p_company, p_code, p_kind, p_date, p_desc, p_data, p_result, array_remove(p_entries, null))
  returning id into v_id;
  return p_result || jsonb_build_object('operation_id', v_id, 'code', p_code,
    'entry_nos', (select coalesce(jsonb_agg(e.entry_no order by e.entry_no), '[]') from erp.journal_entries e where e.id = any (p_entries)));
end $function$
;
