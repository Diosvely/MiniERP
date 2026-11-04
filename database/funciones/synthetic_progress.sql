-- =====================================================================
-- erp.synthetic_progress · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0087_synthetic_batches   →   la vigente es la de 0087_synthetic_batches
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.synthetic_progress(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
declare v_done int; v_total int; v_next date;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select count(*) filter (where done)::int, count(*)::int, min(d) filter (where not done)
  into v_done, v_total, v_next from erp.synthetic_plan where company_id = p_company;
  return jsonb_build_object('done', v_done, 'total', v_total, 'left', v_total - v_done, 'next_date', v_next);
end $function$
;
