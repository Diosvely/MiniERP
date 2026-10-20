-- =====================================================================
-- erp.corporate_tax_manual · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0057_corporate_tax   →   la vigente es la de 0057_corporate_tax
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.corporate_tax_manual(p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare r erp.corporate_tax_returns; v_id uuid := nullif(p->>'id', '')::uuid; a erp.corporate_tax_adjustments;
begin
  if v_id is not null then
    select * into a from erp.corporate_tax_adjustments where id = v_id;
    if not found or a.auto then raise exception 'Only manual adjustments can be edited'; end if;
    r := erp.corporate_tax_draft(a.return_id);
    if coalesce((p->>'delete')::boolean, false) then delete from erp.corporate_tax_adjustments where id = v_id; return null; end if;
    update erp.corporate_tax_adjustments set kind = p->>'kind', direction = p->>'direction', concept = btrim(p->>'concept'),
      amount = (p->>'amount')::numeric, article = nullif(btrim(p->>'article'), '') where id = v_id;
    return v_id;
  end if;
  r := erp.corporate_tax_draft((p->>'return_id')::uuid);
  insert into erp.corporate_tax_adjustments (return_id, company_id, origin, kind, direction, concept, amount, article, included, auto)
  values (r.id, r.company_id, 'manual', p->>'kind', p->>'direction', btrim(p->>'concept'), (p->>'amount')::numeric,
          nullif(btrim(p->>'article'), ''), true, false)
  returning id into v_id;
  return v_id;
end $function$
;
