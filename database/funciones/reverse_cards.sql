-- =====================================================================
-- erp.reverse_cards · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0096_compensated_balance_and_audits   →   la vigente es la de 0096_compensated_balance_and_audits
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.reverse_cards(p_company uuid, p_year integer, p_to date DEFAULT NULL::date, p_drafts boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off'); r jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  with an as (select * from erp.balance_anomalies(p_company, p_year, null, p_to, p_drafts)),
  cls as (
    select m.code as model, c.account_no, c.line_code, s.label, s.label_en
    from erp.fs_models m
    cross join lateral erp.fs_model_classified_at(p_company, p_year, m.code, array[p_to]) c
    join erp.fs_model_line_set(m.code) s on s.code = c.line_code
    where c.account_no in (select account_no from an))
  select coalesce(jsonb_agg(jsonb_build_object(
           'account_no', a.account_no, 'name', a.name, 'name_en', a.name_en, 'expected', a.expected,
           'balance', a.balance, 'severity', a.severity, 'note', a.note, 'note_en', a.note_en,
           'lines', (select jsonb_object_agg(k.model, jsonb_build_object('code', k.line_code, 'label', k.label, 'label_en', k.label_en))
                     from cls k where k.account_no = a.account_no))
         order by case a.severity when 'error' then 0 else 1 end, a.account_no), '[]')
  into r from an a;
  perform set_config('erp.simulate', v_prev, true);
  return r;
end $function$
;
