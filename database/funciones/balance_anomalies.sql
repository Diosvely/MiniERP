-- =====================================================================
-- erp.balance_anomalies · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0013_balance_rules 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.balance_anomalies(p_company uuid, p_year integer, p_level integer DEFAULT NULL::integer, p_to_date date DEFAULT NULL::date, p_drafts boolean DEFAULT false)
 RETURNS TABLE(account_no text, name text, name_en text, expected text, balance numeric, reclass_to text, severity text, note text, note_en text)
 LANGUAGE sql
 STABLE
AS $function$
  select tb.account_no, tb.name, tb.name_en, r.nature,
         tb.debit_balance - tb.credit_balance,
         r.reclass_to, r.severity, r.note, r.note_en
  from erp.trial_balance(p_company, p_year, p_level, p_to_date, p_drafts) tb
  cross join lateral erp.balance_nature(tb.account_no) r
  -- a nivel de grupo (1) o subgrupo (2) se mezclan cuentas de distinta naturaleza: no se analiza
  where (p_level is null or p_level >= 3)
    and ((r.nature = 'debit'  and tb.credit_balance > 0)
      or (r.nature = 'credit' and tb.debit_balance  > 0))
  order by case r.severity when 'error' then 0 else 1 end, tb.account_no;
$function$
;
