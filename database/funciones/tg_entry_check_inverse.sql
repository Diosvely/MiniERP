-- =====================================================================
-- erp.tg_entry_check_inverse · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0013_balance_rules 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_entry_check_inverse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  r record;
begin
  -- Diarios importados: los saldos inversos se SEÑALAN (informe de saldos anómalos), no se bloquean
  if coalesce(current_setting('erp.import_engine', true), '') = 'on' then
    return new;
  end if;
  for r in
    select g.account_no, g.name, n.nature,
           (select coalesce(sum(l2.debit - l2.credit), 0)
              from erp.journal_lines l2
              join erp.journal_entries e2 on e2.id = l2.entry_id
             where l2.gl_account_id = g.id and e2.status = 'posted'
               and e2.fiscal_year_id = new.fiscal_year_id and e2.posting_date <= new.posting_date) as bal
    from (select distinct gl_account_id from erp.journal_lines where entry_id = new.id) x
    join erp.gl_accounts g on g.id = x.gl_account_id and g.block_inverse_balance
    cross join lateral erp.balance_nature(g.account_no) n
  loop
    if (r.nature = 'debit' and r.bal < 0) or (r.nature = 'credit' and r.bal > 0) then
      raise exception 'Account % (%) would have a % balance of % on %: it is blocked for inverse balances',
        r.account_no, r.name, case when r.bal < 0 then 'credit' else 'debit' end, abs(r.bal), new.posting_date;
    end if;
  end loop;
  return new;
end $function$
;
