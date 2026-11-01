-- =====================================================================
-- erp.tax_accounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0082_tax_dashboard   →   la vigente es la de 0082_tax_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tax_accounts(p_company uuid, p_tax_type text)
 RETURNS TABLE(id uuid, side text)
 LANGUAGE sql
 STABLE
AS $function$
    select distinct s.output_account_id as id, 'output' as side from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.output_account_id is not null
    union
    select distinct s.input_account_id, 'input' from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.input_account_id is not null
    union   -- recargo de equivalencia repercutido: también se ingresa con el modelo 303
    select distinct s.surcharge_account_id, 'output' from erp.tax_setup s
      join erp.tax_codes c on c.code = s.tax_code
      where s.company_id = p_company and c.tax_type = p_tax_type and s.surcharge_account_id is not null
    union   -- v0.33.1: las 472 / 477 que NO están configuradas para ningún tipo cuentan en el impuesto del territorio.
            -- Antes un apunte en una 47700001 sin configurar quedaba fuera del cuadre del 303 / 420.
    select g.id, case when g.account_no like '472%' then 'input' else 'output' end
      from erp.gl_accounts g
      where g.company_id = p_company and g.account_type = 'posting'
        and (g.account_no like '472%' or g.account_no like '477%')
        and p_tax_type = (select case tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end
                          from erp.companies where id = p_company)
        and not exists (select 1 from erp.tax_setup s
                        where s.company_id = p_company and g.id in (s.input_account_id, s.output_account_id, s.surcharge_account_id))
$function$
;
