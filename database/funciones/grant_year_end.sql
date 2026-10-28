-- =====================================================================
-- erp.grant_year_end · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0064_grants   →   la vigente es la de 0064_grants
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.grant_year_end(p_company uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare pv jsonb; x jsonb; g erp.grants; v_entry uuid; v_n int := 0;
begin
  perform erp.grant_check(p_company, p_date);
  pv := erp.grant_year_end_preview(p_company, p_date);
  for x in select * from jsonb_array_elements(pv->'grants') loop
    select * into g from erp.grants where id = (x->>'grant_id')::uuid;
    if (x->>'depreciation_pending')::boolean then
      raise exception 'Asset % is not depreciated up to %: post the depreciation first (Fixed assets)', x->>'asset_code', p_date;
    end if;
    if exists (select 1 from erp.grant_events where grant_id = g.id and status = 'posted' and event_date > p_date) then
      raise exception '% has postings after %', g.code, p_date;
    end if;
    if (x->>'imputation')::numeric > 0 or (x->>'tax')::numeric > 0 then
      v_entry := erp.equity_entry(p_company, p_date, 'Subvención transferida al resultado · ' || g.description, g.code,
                   jsonb_build_array(erp.equity_line(g.transfer_account_id, (x->>'imputation')::numeric, 0), erp.equity_line(g.result_account_id, 0, (x->>'imputation')::numeric),
                                     erp.equity_line(g.deferred_account_id, (x->>'tax')::numeric, 0), erp.equity_line(g.tax_account_id, 0, (x->>'tax')::numeric)));
      insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, tax_amount, entry_id)
      values (g.id, p_company, 'imputation', p_date, (x->>'imputation')::numeric, (x->>'tax')::numeric, v_entry);
      v_n := v_n + 1;
    end if;
  end loop;
  return pv || jsonb_build_object('entries', v_n);
end $function$
;
