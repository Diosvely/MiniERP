-- =====================================================================
-- erp.create_case_company · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0067_case_screen   →   la vigente es la de 0067_case_screen
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.create_case_company(p_case text DEFAULT 'taller_atlantico'::text, p_mode text DEFAULT 'full'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'erp', 'public'
AS $function$
declare v_case erp.cases; v_name text; v_n int := 1; e uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to load a case'; end if;
  select * into v_case from erp.cases where key = p_case;
  if not found then raise exception 'Unknown case: %', p_case; end if;
  if p_mode is null or p_mode not in ('full', 'until_closing') then raise exception 'Invalid case mode: %', p_mode; end if;
  v_name := v_case.company_name;
  while exists (select 1 from erp.companies c join erp.company_users u on u.company_id = c.id and u.user_id = auth.uid()
                where c.name = v_name) loop
    v_n := v_n + 1; v_name := v_case.company_name || ' (' || v_n || ')';
  end loop;
  insert into erp.companies (name, industry, tax_territory, legal_form, control_mode, created_by)
  values (v_name, 'retail', v_case.tax_territory, v_case.legal_form, 'strict', auth.uid()) returning id into e;
  return erp.load_case(e, p_case, p_mode) || jsonb_build_object('name', v_name);
end $function$
;
