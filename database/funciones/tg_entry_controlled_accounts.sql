-- =====================================================================
-- erp.tg_entry_controlled_accounts · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0036_controlled_accounts   →   la vigente es la de 0036_controlled_accounts
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_controlled_accounts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  v_hit jsonb;
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on' then return null; end if;
  -- El asiento puede haberse borrado en la misma transacción; y solo importa el modo estricto
  if not exists (select 1 from erp.journal_entries e join erp.companies c on c.id = e.company_id
                 where e.id = new.id and e.status = 'posted' and c.control_mode = 'strict') then
    return null;
  end if;
  if not erp.entry_is_manual(new.id) then return null; end if;
  v_hit := erp.entry_controlled_lines(new.id);
  if jsonb_array_length(v_hit) > 0 then
    raise exception 'Account % is controlled by %: register it from that screen (or switch the company to guided mode)',
      v_hit->0->>'account_no', (select string_agg(m, ', ') from jsonb_array_elements_text(v_hit->0->'modules') m);
  end if;
  return null;
end $function$
;
