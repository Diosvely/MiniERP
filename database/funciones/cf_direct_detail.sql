-- =====================================================================
-- erp.cf_direct_detail · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow 0066_complete_case   →   la vigente es la de 0066_complete_case
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_direct_detail(p_company uuid, p_year integer)
 RETURNS TABLE(line_code text, account_no text, account_name text, account_name_en text, amount numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with c as (
    select f.entry_id, f.account_no, f.account_name, f.account_name_en, f.direct_line, sum(f.flow) as amount
    from erp.cf_line_flows(p_company, p_year) f
    where f.entry_id in (select ce.entry_id from erp.cf_entry_cash(p_company, p_year) ce where ce.cash <> 0)
    group by 1, 2, 3, 4, 5
    having sum(f.flow) <> 0),
  x as (
    -- inversión y deudas: cobro o pago según el NETO del asiento en esa línea
    -- (venta de un inmovilizado = coste + amortización acumulada + beneficio → un solo cobro)
    select c.*, sum(c.amount) over (partition by c.entry_id, c.direct_line) as entry_net from c)
  select case direct_line
           when 'DB'  then case when entry_net < 0 then 'DB1' else 'DB2' end
           when 'DC2' then case when entry_net > 0 then 'DC2' else 'DC3' end
           else direct_line end,
         account_no, account_name, account_name_en, sum(amount)
  from x
  group by 1, 2, 3, 4;
$function$
;
