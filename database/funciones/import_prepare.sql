-- =====================================================================
-- erp.import_prepare · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.import_prepare(p_batch uuid)
 RETURNS TABLE(year integer, month integer, entries bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  b    erp.import_batches;
  p    jsonb;
  v_y  int;
  v_d  smallint;
begin
  select * into b from erp.import_batches where id = p_batch for update;
  if not found or not erp.is_admin(b.company_id) then
    raise exception 'Import batch not found (or no permission)';
  end if;
  if b.status <> 'staging' then
    raise exception 'This import batch is already %', b.status;
  end if;
  if exists (select 1 from erp.journal_entries where company_id = b.company_id) then
    raise exception 'The company already has entries: imports go into a new, empty company';
  end if;
  p := erp.import_preview(p_batch);
  if not (p->>'can_import')::boolean then
    raise exception 'The file cannot be imported: %', p->'errors';
  end if;

  -- Ejercicios (naturales) de todos los años del fichero
  for v_y in select distinct extract(year from entry_date)::int from erp.import_lines where batch_id = p_batch order by 1 loop
    if not exists (select 1 from erp.fiscal_years f where f.company_id = b.company_id and f.year = v_y) then
      perform erp.create_fiscal_year(b.company_id, v_y);
    end if;
  end loop;

  -- Subcuentas que faltan, y las de redondeo si hacen falta
  insert into erp.gl_accounts (company_id, account_no, name, account_type, template_account, account_category)
  select b.company_id, a.account_no, erp.import_account_name(a.account_no, a.account_name), 'posting', '', ''
  from (select account_no, max(account_name) as account_name from erp.import_lines where batch_id = p_batch group by 1) a
  where not exists (select 1 from erp.gl_accounts g where g.company_id = b.company_id and g.account_no = a.account_no);

  select posting_account_digits into v_d from erp.companies where id = b.company_id;
  if (p->>'rounded_entries')::int > 0 then
    insert into erp.gl_accounts (company_id, account_no, name, account_type, template_account, account_category)
    select b.company_id, x.no, x.name, 'posting', '', ''
    from (values (rpad('678', v_d - 1, '0') || '9', 'Redondeos de importación (gasto)'),
                 (rpad('778', v_d - 1, '0') || '9', 'Redondeos de importación (ingreso)')) as x(no, name)
    where not exists (select 1 from erp.gl_accounts g where g.company_id = b.company_id and g.account_no = x.no);
  end if;

  update erp.import_batches set status = 'prepared', summary = p - 'unbalanced' - 'continuity' where id = p_batch;

  return query
    select extract(year from l.entry_date)::int, extract(month from l.entry_date)::int,
           count(distinct (l.entry_date, l.entry_ref, l.entry_type))
    from erp.import_lines l where l.batch_id = p_batch
    group by 1, 2 order by 1, 2;
end $function$
;
