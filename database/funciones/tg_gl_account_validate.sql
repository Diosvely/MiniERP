-- =====================================================================
-- erp.tg_gl_account_validate · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0002_chart_of_accounts   →   la vigente es la de 0002_chart_of_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_gl_account_validate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_digits  smallint;
  v_parent  erp.coa_template;
begin
  if new.account_type = 'heading' then
    return new;  -- las copia el sistema desde la plantilla
  end if;

  select posting_account_digits into v_digits from erp.companies where id = new.company_id;
  if length(new.account_no) <> v_digits then
    raise exception 'Posting account % must have % digits', new.account_no, v_digits;
  end if;

  select * into v_parent
  from erp.coa_template
  where new.account_no like account_no || '%' and level >= 3
  order by level desc
  limit 1;

  if v_parent is null then
    raise exception 'Posting account % does not belong to any PGC account (3 or 4 digits)', new.account_no;
  end if;

  new.template_account := v_parent.account_no;
  new.account_category := v_parent.account_category;
  return new;
end $function$
;
