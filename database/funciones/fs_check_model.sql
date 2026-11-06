-- =====================================================================
-- erp.fs_check_model · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0089_balance_models   →   la vigente es la de 0089_balance_models
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_check_model(p_statement text, p_model text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
begin
  if not exists (select 1 from erp.fs_models where code = p_model) then
    raise exception 'Unknown balance sheet model: %', p_model;
  end if;
  if p_model <> 'pymes' and p_statement <> 'balance' then
    raise exception 'Only the balance sheet has other models (the income statement uses the SME model)';
  end if;
end $function$
;
