-- =====================================================================
-- erp.equity_net_worth · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0060_equity_operations   →   la vigente es la de 0060_equity_operations
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.equity_net_worth(p_company uuid, p_date date, p_with_current boolean DEFAULT true)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select erp.equity_bal(p_company, '10', p_date) + erp.equity_bal(p_company, '11', p_date) + erp.equity_bal(p_company, '12', p_date)
       + erp.equity_bal(p_company, '13', p_date) + erp.equity_bal(p_company, '557', p_date)
       + case when p_with_current then erp.equity_bal(p_company, '6', p_date) + erp.equity_bal(p_company, '7', p_date) else 0 end;
$function$
;
