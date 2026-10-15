-- =====================================================================
-- erp.tg_line_set_tax_code · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0010_tax_setup 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_line_set_tax_code()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  v_codes text[];
begin
  if coalesce(current_setting('erp.import_engine', true), '') = 'on' then
    return new;   -- los diarios importados no traen libro registro
  end if;
  if new.tax_code is null then
    select array_agg(s.tax_code) into v_codes
    from erp.tax_setup s
    where s.company_id = coalesce(new.company_id, (select e.company_id from erp.journal_entries e where e.id = new.entry_id))
      and new.gl_account_id in (s.input_account_id, s.output_account_id);
    if cardinality(v_codes) = 1 then
      new.tax_code := v_codes[1];
    end if;
  end if;
  return new;
end $function$
;
