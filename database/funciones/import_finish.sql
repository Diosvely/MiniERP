-- =====================================================================
-- erp.import_finish · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.import_finish(p_batch uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  b       erp.import_batches;
  y       erp.fiscal_years;
  v_last  int;
  v_res   numeric;
  v_with  text;
begin
  select * into b from erp.import_batches where id = p_batch for update;
  if not found or not erp.is_admin(b.company_id) then
    raise exception 'Import batch not found (or no permission)';
  end if;
  if b.status <> 'prepared' then
    raise exception 'This import batch is %', b.status;
  end if;
  if exists (select date_trunc('month', l.entry_date) from erp.import_lines l where l.batch_id = p_batch
             except
             select date_trunc('month', e.posting_date) from erp.journal_entries e where e.import_batch_id = p_batch) then
    raise exception 'Some months of this batch are not imported yet';
  end if;

  select max(f.year) into v_last from erp.fiscal_years f where f.company_id = b.company_id;
  select * into y from erp.fiscal_years f
  where f.company_id = b.company_id and f.year < v_last and f.status = 'open' order by f.year limit 1;

  if found then
    -- Resultado del ejercicio (grupos 6 y 7 sin regularización ni cierre)
    select -coalesce(sum(l.debit - l.credit), 0) into v_res
    from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.fiscal_year_id = y.id and e.entry_type not in ('closing_pl', 'closing') and left(g.account_no, 1) in ('6', '7');

    if exists (select 1 from erp.journal_entries e join erp.fiscal_years n on n.id = e.fiscal_year_id
               where e.import_batch_id = p_batch and e.entry_type = 'opening' and n.year = y.year + 1) then
      -- Cierre del fichero: se registra como cierre del ejercicio (y se puede reabrir como cualquier otro)
      perform set_config('erp.year_closing_engine', 'on', true);
      insert into erp.year_closings (company_id, fiscal_year_id, year, result, closing_pl_entry_id, closing_entry_id,
                                     opening_entry_id, warnings)
      values (b.company_id, y.id, y.year, v_res,
              (select min(e.id::text)::uuid from erp.journal_entries e where e.fiscal_year_id = y.id and e.entry_type = 'closing_pl'),
              (select min(e.id::text)::uuid from erp.journal_entries e where e.fiscal_year_id = y.id and e.entry_type = 'closing'),
              (select min(e.id::text)::uuid from erp.journal_entries e join erp.fiscal_years n on n.id = e.fiscal_year_id
                where n.company_id = b.company_id and n.year = y.year + 1 and e.entry_type = 'opening'),
              '[{"code": "imported", "severity": "info"}]');
      update erp.fiscal_years set status = 'closed' where id = y.id;
      perform set_config('erp.year_closing_engine', 'off', true);
      v_with := 'file';
    else
      -- (modo importación: un saldo inverso histórico, p. ej. caja acreedora, se señala pero no impide cerrar)
      perform set_config('erp.import_engine', 'on', true);
      perform erp.close_fiscal_year(b.company_id, y.year, true);
      perform set_config('erp.import_engine', 'off', true);
      v_with := 'assistant';
    end if;
    update erp.import_batches
    set summary = coalesce(summary, '{}') || jsonb_build_object('closings',
          coalesce(summary->'closings', '[]') || jsonb_build_object('year', y.year, 'closed_with', v_with, 'result', v_res))
    where id = p_batch;
    return jsonb_build_object('year', y.year, 'closed_with', v_with, 'result', v_res, 'done', false);
  end if;

  delete from erp.import_lines where batch_id = p_batch;
  update erp.import_batches
  set status = 'posted', finished_at = now(),
      summary = coalesce(summary, '{}') || jsonb_build_object(
                  'entries', (select count(*) from erp.journal_entries where import_batch_id = p_batch))
  where id = p_batch;
  return jsonb_build_object('done', true);
end $function$
;
