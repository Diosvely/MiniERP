-- =====================================================================
-- erp.dash_metric_values · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0075_dashboards   →   la vigente es la de 0075_dashboards
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.dash_metric_values(p_company uuid, p_year integer, p_dates date[])
 RETURNS TABLE(at date, v jsonb)
 LANGUAGE plpgsql
 STABLE
AS $function$
#variable_conflict use_column
declare
  bal jsonb; pyg jsonb; grp jsonb; vals jsonb; m erp.dash_metrics; x numeric; va numeric; vb numeric; d date;
begin
  -- { fecha: { partida: importe } } del Balance y de la PyG, y { fecha: { cuenta: saldo } } de la PyG (los grupos)
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into bal
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'balance', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into pyg
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'pyg', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into grp
  from (select c.at, jsonb_object_agg(c.account_no, c.balance) m from erp.fs_classified_at(p_company, p_year, 'pyg', p_dates) c group by c.at) z;

  foreach d in array (select array_agg(distinct x) from unnest(p_dates) x) loop
    vals := '{}';
    for m in select * from erp.dash_metrics order by sort loop
      if m.kind = 'line' then
        x := coalesce(((case m.statement when 'balance' then bal else pyg end) -> coalesce(d::text, '-') ->> m.line_code)::numeric, 0);
      elsif m.kind = 'group' then
        select m.sign * coalesce(sum(e.value::numeric), 0) into x
        from jsonb_each_text(coalesce(grp -> coalesce(d::text, '-'), '{}')) e where e.key like m.account_prefix || '%';
      else
        va := (vals ->> m.a)::numeric; vb := (vals ->> m.b)::numeric;
        x := case m.kind when 'sum' then va + vb when 'diff' then va - vb
                         else case when vb is null or vb = 0 then null else round(va / vb, 4) end end;
      end if;
      vals := vals || jsonb_build_object(m.code, x);
    end loop;
    at := d; v := vals; return next;
  end loop;
end $function$
;
