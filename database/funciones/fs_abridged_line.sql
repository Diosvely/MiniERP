-- =====================================================================
-- erp.fs_abridged_line · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0089_balance_models   →   la vigente es la de 0089_balance_models
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_abridged_line(p_normal text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'erp', 'public'
AS $function$
  select case
    when p_normal ~ '^(ANC\.(I|II|III|IV|V)|AC\.(II|IV|V|VII)|PN\.A1\.(III|V)|PN\.A2|PNC\.I)\.' then regexp_replace(p_normal, '\.[^.]+$', '')
    when p_normal in ('AC.III.1', 'AC.III.2') then 'AC.III.1'
    when p_normal = 'AC.III.7' then 'AC.III.2'
    when p_normal like 'AC.III.%' then 'AC.III.3'
    when p_normal = 'PNC.II.2' then 'PNC.II.1'
    when p_normal = 'PNC.II.3' then 'PNC.II.2'
    when p_normal like 'PNC.II.%' then 'PNC.II.3'
    when p_normal = 'PC.III.2' then 'PC.III.1'
    when p_normal = 'PC.III.3' then 'PC.III.2'
    when p_normal like 'PC.III.%' then 'PC.III.3'
    when p_normal in ('PC.V.1', 'PC.V.2') then 'PC.V.1'
    when p_normal like 'PC.V.%' then 'PC.V.2'
    else p_normal end;
$function$
;
