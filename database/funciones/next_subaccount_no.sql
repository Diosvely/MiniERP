-- =====================================================================
-- erp.next_subaccount_no · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0025_entry_tutor   →   la vigente es la de 0025_entry_tutor
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.next_subaccount_no(p_company uuid, p_template text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  with d as (select posting_account_digits as n from erp.companies where id = p_company)
  select coalesce(
           (select lpad((max(g.account_no::numeric) + 1)::text, d.n, '0')
            from erp.gl_accounts g
            where g.company_id = p_company and g.account_no like p_template || '%' and length(g.account_no) = d.n
            having max(g.account_no::numeric) is not null),
           rpad(p_template, d.n - 1, '0') || '1')
  from d;
$function$
;
