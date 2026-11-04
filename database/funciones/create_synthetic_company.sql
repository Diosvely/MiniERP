-- =====================================================================
-- erp.create_synthetic_company · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0086_synthetic_companies 0087_synthetic_batches   →   la vigente es la de 0087_synthetic_batches
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.create_synthetic_company(p_seed integer, p_profile text, p_months integer DEFAULT 12)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'erp', 'public'
AS $function$
declare v_p record; v_name text; v_n int := 1; e uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to create a synthetic company'; end if;
  if p_seed is null or p_seed not between 1 and 999999 then raise exception 'The seed must be a number from 1 to 999999'; end if;
  select * into v_p from erp.synthetic_profiles() s where s.profile = p_profile;
  if not found then raise exception 'Unknown synthetic profile: %', p_profile; end if;
  if p_months is null or p_months not between 1 and 12 then raise exception 'The months must be from 1 to 12'; end if;
  if p_months < v_p.min_months then
    raise exception 'The % profile needs at least % months', p_profile, v_p.min_months;
  end if;
  v_name := 'Sintética ' || p_seed || ' · ' || v_p.name || ' SL';
  while exists (select 1 from erp.companies c join erp.company_users u on u.company_id = c.id and u.user_id = auth.uid()
                where c.name = v_name) loop
    v_n := v_n + 1; v_name := 'Sintética ' || p_seed || ' · ' || v_p.name || ' SL (' || v_n || ')';
  end loop;
  insert into erp.companies (name, industry, tax_territory, legal_form, created_by, temporary)
  values (v_name, case p_profile when 'services' then 'services' else 'retail' end, v_p.territory, 'sl', auth.uid(),
          not erp.is_trusted())
  returning id into e;
  return erp.synthetic_prepare(e, p_seed, p_profile, p_months) || jsonb_build_object('name', v_name);
end $function$
;
