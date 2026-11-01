-- =====================================================================
-- erp.dash_metric_values · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0075_dashboards 0080_profitability_dashboard 0081_treasury_dashboard   →   la vigente es la de 0081_treasury_dashboard
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.dash_metric_values(p_company uuid, p_year integer, p_dates date[])
 RETURNS TABLE(at date, v jsonb)
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
#variable_conflict use_column
declare
  bal jsonb; pyg jsonb; grp jsonb; csh jsonb; vals jsonb; m erp.dash_metrics; x numeric; va numeric; vb numeric; d date;
  v_start date; v_end date; days int;
begin
  select fy.starting_date, fy.ending_date into v_start, v_end from erp.fiscal_years fy where fy.company_id = p_company and fy.year = p_year;
  -- { fecha: { partida: importe } } del Balance y de la PyG, y { fecha: { cuenta: saldo } } de la PyG (los grupos)
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into bal
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'balance', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into pyg
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'pyg', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into grp
  from (select c.at, jsonb_object_agg(c.account_no, c.balance) m from erp.fs_classified_at(p_company, p_year, 'pyg', p_dates) c group by c.at) z;
  -- 0081: { fecha: { in, out } } de la tesorería, solo si alguna métrica la usa
  csh := '{}';
  if exists (select 1 from erp.dash_metrics where kind = 'cash') then
    select coalesce(jsonb_object_agg(coalesce(c.at::text, '-'), jsonb_build_object('in', c.cash_in, 'out', c.cash_out)), '{}') into csh
    from erp.cash_moves_at(p_company, p_year, p_dates) c;
  end if;

  foreach d in array (select array_agg(distinct x) from unnest(p_dates) x) loop
    vals := '{}';
    -- 0081: días transcurridos del ejercicio hasta la fecha (como mucho 365: al cierre, el × 365 de Ratios)
    days := least(coalesce(least(d, v_end), v_end) - v_start + 1, 365);
    for m in select * from erp.dash_metrics order by sort loop
      if m.kind = 'line' then
        -- 0080: con signo (-1 = el gasto en positivo)
        x := coalesce(m.sign, 1)
             * coalesce(((case m.statement when 'balance' then bal else pyg end) -> coalesce(d::text, '-') ->> m.line_code)::numeric, 0);
      elsif m.kind = 'group' then
        select m.sign * coalesce(sum(e.value::numeric), 0) into x
        from jsonb_each_text(coalesce(grp -> coalesce(d::text, '-'), '{}')) e where e.key like m.account_prefix || '%';
      elsif m.kind = 'cash' then
        x := coalesce((csh -> coalesce(d::text, '-') ->> m.flow)::numeric, 0);
      else
        va := (vals ->> m.a)::numeric; vb := (vals ->> m.b)::numeric;
        x := case m.kind when 'sum' then va + vb when 'diff' then va - vb
                         when 'days' then case when vb is null or vb = 0 or days <= 0 then null else round(va * days / vb, 4) end
                         else case when vb is null or vb = 0 then null else round(va / vb, 4) end end;
      end if;
      vals := vals || jsonb_build_object(m.code, x);
    end loop;
    at := d; v := vals; return next;
  end loop;
end $function$
;
