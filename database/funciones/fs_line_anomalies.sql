-- =====================================================================
-- erp.fs_line_anomalies · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0084_quality_dashboard   →   la vigente es la de 0084_quality_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_line_anomalies(p_company uuid, p_year integer, p_to date DEFAULT NULL::date, p_drafts boolean DEFAULT false)
 RETURNS TABLE(line_code text, account_no text, name text, name_en text, balance numeric, expected text, severity text, note text, note_en text)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare v_prev_sim text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  select c.line_code, a.account_no, a.name, a.name_en, a.balance, a.expected, a.severity, a.note, a.note_en
  from erp.balance_anomalies(p_company, p_year, null, p_to, p_drafts) a
  join erp.fs_classified_accounts(p_company, p_year, 'balance', p_to) c on c.account_no = a.account_no
  order by c.line_code, a.account_no;
  perform set_config('erp.simulate', v_prev_sim, true);
end $function$
;
