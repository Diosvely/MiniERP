-- =====================================================================
-- erp.set_pro_rata · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0020_pro_rata   →   la vigente es la de 0020_pro_rata
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.set_pro_rata(p_company uuid, p_tax_type text, p_year integer, p_pct numeric)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can set the pro rata';
  end if;
  if exists (select 1 from erp.pro_rata where company_id = p_company and tax_type = p_tax_type and year = p_year
             and entry_id is not null) then
    raise exception 'The % pro rata of % is already regularized: undo the regularization first', p_tax_type, p_year;
  end if;
  if (select vat_regime from erp.companies where id = p_company) = 'equivalence_surcharge' then
    raise exception 'A retailer under the equivalence surcharge does not apply the pro rata';
  end if;
  perform set_config('erp.pro_rata_engine', 'on', true);
  if p_pct is null then
    delete from erp.pro_rata where company_id = p_company and tax_type = p_tax_type and year = p_year;
  else
    insert into erp.pro_rata (company_id, tax_type, year, provisional_pct)
    values (p_company, p_tax_type, p_year, p_pct)
    on conflict (company_id, tax_type, year) do update set provisional_pct = excluded.provisional_pct,
      definitive_pct = null, regularization_amount = null;
  end if;
  perform set_config('erp.pro_rata_engine', 'off', true);
end $function$
;
