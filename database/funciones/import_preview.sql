-- =====================================================================
-- erp.import_preview · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.import_preview(p_batch uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  b          erp.import_batches;
  v_digits   smallint;
  v_years    jsonb;
  v_unbal    jsonb;
  v_big      int;
  v_small    int;
  v_accounts jsonb;
  v_cont     jsonb := '[]';
  v_errors   jsonb := '[]';
  y          record;
  v_result   numeric;
  v_diff     jsonb;
begin
  select * into b from erp.import_batches where id = p_batch;
  if not found or not erp.is_admin(b.company_id) then
    raise exception 'Import batch not found (or no permission)';
  end if;
  select posting_account_digits into v_digits from erp.companies where id = b.company_id;

  -- Años: apuntes, asientos, sumas y qué tipos de asiento trae cada uno
  select coalesce(jsonb_agg(x order by x.year), '[]') into v_years
  from (select extract(year from entry_date)::int as year, count(*) as rows,
               count(distinct (entry_date, entry_ref, entry_type)) as entries,
               sum(erp.import_debit(debit, credit)) as debit, sum(erp.import_credit(debit, credit)) as credit,
               bool_or(entry_type = 'opening') as has_opening, bool_or(entry_type = 'closing_pl') as has_closing_pl,
               bool_or(entry_type = 'closing') as has_closing,
               min(entry_date) as first_date, max(entry_date) as last_date
        from erp.import_lines where batch_id = p_batch group by 1) x;

  -- Cuadre de cada asiento
  with g as (
    select entry_date, entry_ref, entry_type,
           sum(erp.import_debit(debit, credit) - erp.import_credit(debit, credit)) as diff
    from erp.import_lines where batch_id = p_batch group by 1, 2, 3)
  select count(*) filter (where abs(diff) > 1), count(*) filter (where diff <> 0 and abs(diff) <= 1),
         coalesce(jsonb_agg(jsonb_build_object('date', entry_date, 'ref', entry_ref, 'diff', diff)
                  order by abs(diff) desc) filter (where diff <> 0), '[]')
    into v_big, v_small, v_unbal
  from g;

  -- Cuentas: cuántas, cuántas nuevas y cuáles no sirven (longitud o sin cuenta del PGC)
  with a as (select distinct account_no from erp.import_lines where batch_id = p_batch)
  select jsonb_build_object(
           'total', count(*),
           'new', count(*) filter (where not exists (select 1 from erp.gl_accounts g where g.company_id = b.company_id and g.account_no = a.account_no)),
           'wrong_length', coalesce(jsonb_agg(a.account_no) filter (where length(a.account_no) <> v_digits or a.account_no !~ '^[0-9]+$'), '[]'),
           'no_pgc', coalesce(jsonb_agg(a.account_no) filter (where not exists (
              select 1 from erp.coa_template t where a.account_no like t.account_no || '%' and t.level >= 3)), '[]'))
    into v_accounts
  from a;

  -- Continuidad: ¿la apertura de cada año coincide con el cierre del anterior? (cuentas de balance, grupos 1 a 5)
  for y in select (x->>'year')::int as year from jsonb_array_elements(v_years) x
           where (x->>'has_opening')::boolean
             and exists (select 1 from jsonb_array_elements(v_years) p where (p->>'year')::int = (x->>'year')::int - 1)
  loop
    -- resultado del año anterior aún sin regularizar (si el fichero no trae la regularización)
    select coalesce(sum(erp.import_debit(debit, credit) - erp.import_credit(debit, credit)), 0) into v_result
    from erp.import_lines
    where batch_id = p_batch and extract(year from entry_date) = y.year - 1
      and left(account_no, 1) in ('6', '7') and entry_type <> 'closing';
    with prev as (
      select account_no, sum(erp.import_debit(debit, credit) - erp.import_credit(debit, credit)) as bal
      from erp.import_lines
      where batch_id = p_batch and extract(year from entry_date) = y.year - 1 and entry_type <> 'closing'
        and left(account_no, 1) between '1' and '5'
      group by 1),
    op as (
      select account_no, sum(erp.import_debit(debit, credit) - erp.import_credit(debit, credit)) as bal
      from erp.import_lines
      where batch_id = p_batch and extract(year from entry_date) = y.year and entry_type = 'opening'
      group by 1),
    d as (
      select coalesce(p.account_no, o.account_no) as account_no, coalesce(p.bal, 0) as closing, coalesce(o.bal, 0) as opening
      from prev p full join op o on o.account_no = p.account_no)
    select coalesce(jsonb_agg(jsonb_build_object('account_no', account_no, 'closing', closing, 'opening', opening,
             'difference', opening - closing,
             -- la 129 que abre con el resultado no regularizado no es un error: falta la regularización en el fichero
             'unregularized_result', account_no like '129%' and opening - closing = v_result and v_result <> 0)
             order by abs(opening - closing) desc), '[]')
      into v_diff
    from d where opening <> closing;
    v_cont := v_cont || jsonb_build_object('year', y.year, 'differences', v_diff);
  end loop;

  -- Errores que impiden importar
  if jsonb_array_length(v_accounts->'wrong_length') > 0 then
    v_errors := v_errors || jsonb_build_object('code', 'wrong_length', 'detail', v_digits);
  end if;
  if jsonb_array_length(v_accounts->'no_pgc') > 0 then
    v_errors := v_errors || jsonb_build_object('code', 'no_pgc', 'detail', v_accounts->'no_pgc');
  end if;
  if v_big > 0 then
    v_errors := v_errors || jsonb_build_object('code', 'unbalanced', 'detail', v_big);
  end if;
  if not exists (select 1 from erp.import_lines where batch_id = p_batch) then
    v_errors := v_errors || jsonb_build_object('code', 'empty', 'detail', null);
  end if;

  return jsonb_build_object(
    'batch_id', p_batch, 'status', b.status, 'source', b.source, 'file_name', b.file_name,
    'rows', (select count(*) from erp.import_lines where batch_id = p_batch),
    'zero_rows', (select count(*) from erp.import_lines where batch_id = p_batch and debit = 0 and credit = 0),
    'negative_rows', (select count(*) from erp.import_lines where batch_id = p_batch and (debit < 0 or credit < 0)),
    'years', v_years,
    'rounded_entries', v_small, 'unbalanced_entries', v_big,
    'unbalanced', (select coalesce(jsonb_agg(x), '[]') from (select x from jsonb_array_elements(v_unbal) x limit 15) s),
    'accounts', v_accounts,
    'continuity', v_cont,
    'errors', v_errors,
    'can_import', b.status = 'staging' and jsonb_array_length(v_errors) = 0,
    'summary', b.summary);
end $function$
;
