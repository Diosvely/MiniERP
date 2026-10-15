-- =====================================================================
-- erp.cf_direct_detail · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0022_cash_flow   →   la vigente es la de 0022_cash_flow
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.cf_direct_detail(p_company uuid, p_year integer)
 RETURNS TABLE(line_code text, account_no text, account_name text, account_name_en text, amount numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  with c as (
    -- contrapartida de cada asiento con dinero: su flujo es −(su variación), con el signo de lo que entra o sale
    select l.entry_id, l.gl_account_id, -sum(l.debit - l.credit) as amount
    from erp.cf_entry_cash(p_company, p_year) ce
    join erp.journal_lines l on l.entry_id = ce.entry_id
    where ce.cash <> 0
    group by l.entry_id, l.gl_account_id
    having sum(l.debit - l.credit) <> 0),
  mp as (
    select g.id, g.account_no, g.name, g.name_en, m.direct_line
    from erp.gl_accounts g cross join lateral erp.cf_account_map(g.account_no) m
    where g.id in (select gl_account_id from c) and g.account_no not like '57%'),
  x as (
    -- inversión y deudas: cobro o pago según el NETO del asiento en esa línea
    -- (venta de un inmovilizado = coste + amortización acumulada + beneficio → un solo cobro)
    select c.*, mp.account_no, mp.name, mp.name_en, mp.direct_line,
           sum(c.amount) over (partition by c.entry_id, mp.direct_line) as entry_net
    from c join mp on mp.id = c.gl_account_id)
  select case direct_line
           when 'DB'  then case when entry_net < 0 then 'DB1' else 'DB2' end
           when 'DC2' then case when entry_net > 0 then 'DC2' else 'DC3' end
           else direct_line end,
         account_no, name, name_en, sum(amount)
  from x
  group by 1, 2, 3, 4;
$function$
;
