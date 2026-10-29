-- =====================================================================
-- erp.financial_ratios · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0023_financial_ratios 0074_report_simulation   →   la vigente es la de 0074_report_simulation
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.financial_ratios(p_company uuid, p_year integer, p_drafts boolean DEFAULT false)
 RETURNS TABLE(code text, grp text, sort integer, label text, label_en text, formula text, formula_en text, unit text, ref_min numeric, ref_max numeric, help text, help_en text, num numeric, den numeric, value numeric, value_prev numeric, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_prev text := coalesce(nullif(current_setting('erp.simulate', true), ''), 'off');
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if p_drafts then perform set_config('erp.simulate', 'on', true); end if;
  return query
  with cur as (select * from erp.ratio_parts(p_company, p_year)),
       prev as (select * from erp.ratio_parts(p_company, p_year - 1)),
       v as (
         select d.code,
                c.num, c.den,
                case when c.den is null then c.num when c.den <> 0 then round(c.num / c.den, 4) end as value,
                case when pr.den is null then pr.num when pr.den <> 0 then round(pr.num / pr.den, 4) end as value_prev
         from erp.ratio_defs d
         left join cur c on c.code = d.code
         left join prev pr on pr.code = d.code)
  select d.code, d.grp, d.sort, d.label, d.label_en, d.formula, d.formula_en, d.unit, d.ref_min, d.ref_max,
         d.help, d.help_en, v.num, v.den, v.value, v.value_prev,
         case when v.value is null or (d.ref_min is null and d.ref_max is null) then null
              when v.value < d.ref_min then 'low'
              when v.value > d.ref_max then 'high'
              else 'ok' end
  from erp.ratio_defs d
  join v on v.code = d.code
  order by array_position(array['liquidity', 'solvency', 'profitability', 'activity', 'cash'], d.grp), d.sort;
  perform set_config('erp.simulate', v_prev, true);
end $function$
;
