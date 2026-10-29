-- =====================================================================
-- erp.corporate_tax_prepare · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_prepare(p_company uuid, p_year integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_fy erp.fiscal_years; v_ret erp.corporate_tax_returns;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to prepare the corporate tax of this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'No fiscal year % in this company', p_year; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', p_year; end if;
  select * into v_ret from erp.corporate_tax_returns where fiscal_year_id = v_fy.id;
  if v_ret.status = 'posted' then raise exception 'The corporate tax of % is already posted: cancel it first', p_year; end if;
  if v_ret.id is null then
    insert into erp.corporate_tax_returns (company_id, fiscal_year_id, regime)
    values (p_company, v_fy.id, erp.corporate_tax_regime_hint(p_company, p_year)->>'suggested') returning * into v_ret;
  end if;
  -- quitar los propuestos que ya no salen; poner al día los demás; añadir los nuevos
  delete from erp.corporate_tax_adjustments a where a.return_id = v_ret.id and a.auto
    and not exists (select 1 from erp.corporate_tax_proposals(p_company, p_year) x
                    where x.origin = a.origin and x.source_id = a.source_id and x.direction = a.direction);
  update erp.corporate_tax_adjustments a set kind = x.kind, concept = x.concept, amount = x.amount, article = x.article
  from erp.corporate_tax_proposals(p_company, p_year) x
  where a.return_id = v_ret.id and a.auto and x.origin = a.origin and x.source_id = a.source_id and x.direction = a.direction;
  insert into erp.corporate_tax_adjustments (return_id, company_id, origin, source_id, kind, direction, concept, amount, article, included, auto)
  select v_ret.id, p_company, x.origin, x.source_id, x.kind, x.direction, x.concept, x.amount, x.article, x.included, true
  from erp.corporate_tax_proposals(p_company, p_year) x
  where not exists (select 1 from erp.corporate_tax_adjustments a where a.return_id = v_ret.id and a.auto
                    and a.origin = x.origin and a.source_id = x.source_id and a.direction = x.direction);
  return v_ret.id;
end $function$
;
