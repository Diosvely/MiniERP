-- =====================================================================
-- erp.inventory_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0047_inventory_closing   →   la vigente es la de 0047_inventory_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.inventory_account(p_company uuid, p_stock_no text, p_kind text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare d text := substr(p_stock_no, 2, 1); v_prefix text;
begin
  v_prefix := case p_kind
    when 'variation' then case when d in ('0', '1', '2') then '61' || d else '71' || (d::int - 3)::text end
    when 'allowance' then '39' || d
    when 'expense'   then '693' || case d when '0' then '1' when '1' then '2' when '2' then '3' else '0' end
    else                  '793' || case d when '0' then '1' when '1' then '2' when '2' then '3' else '0' end end;
  return erp.adjust_account(p_company, v_prefix,
    coalesce((select t.name from erp.coa_template t where t.account_no = v_prefix),
             (select t.name from erp.coa_template t where t.account_no = left(v_prefix, 3))));
end $function$
;
