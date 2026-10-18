-- =====================================================================
-- erp.inventory_preview · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0047_inventory_closing   →   la vigente es la de 0047_inventory_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.inventory_preview(p_company uuid, p_date date)
 RETURNS TABLE(account_no text, account_name text, initial_value numeric, prev_impairment numeric, variation_account_no text)
 LANGUAGE sql
 STABLE
AS $function$
  with fy as (select id from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date)
  select g.account_no, g.name, erp.account_balance_in_year(g.id, fy.id, p_date),
         coalesce((select -erp.account_balance_in_year(a.id, fy.id, p_date) from erp.gl_accounts a
                   where a.company_id = p_company and a.account_type = 'posting' and a.account_no like '39' || substr(g.account_no, 2, 1) || '%'
                   limit 1), 0),
         case when substr(g.account_no, 2, 1) in ('0', '1', '2') then '61' || substr(g.account_no, 2, 1)
              else '71' || (substr(g.account_no, 2, 1)::int - 3)::text end
  from erp.gl_accounts g cross join fy
  where g.company_id = p_company and g.account_type = 'posting' and g.account_no ~ '^3[0-6]'
  order by g.account_no;
$function$
;
