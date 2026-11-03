-- =====================================================================
-- erp.company_fingerprint · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0086_synthetic_companies   →   la vigente es la de 0086_synthetic_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.company_fingerprint(p_company uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'erp', 'public'
AS $function$
declare v text;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select md5(coalesce(string_agg(x.t, E'\n' order by x.entry_no, x.posting_date, x.t), '')) into v
  from (select j.entry_no, j.posting_date,
               concat_ws('|', j.entry_no, j.posting_date, j.status, j.description,
                 (select string_agg(concat_ws(':', g.account_no, l.debit, l.credit), ',' order by l.line_no, g.account_no, l.debit, l.credit)
                  from erp.journal_lines l join erp.gl_accounts g on g.id = l.gl_account_id where l.entry_id = j.id)) as t
        from erp.journal_entries j where j.company_id = p_company) x;
  return erp.synthetic_version() || '-' || upper(substr(v, 1, 8));
end $function$
;
