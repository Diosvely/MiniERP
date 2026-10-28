-- =====================================================================
-- erp.import_post_month · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0021_journal_import   →   la vigente es la de 0021_journal_import
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.import_post_month(p_batch uuid, p_year integer, p_month integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  b       erp.import_batches;
  v_start date := make_date(p_year, p_month, 1);
  v_end   date := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date;
  v_fy    erp.fiscal_years;
  v_d     smallint;
  v_n     int;
begin
  select * into b from erp.import_batches where id = p_batch;
  if not found or not erp.is_admin(b.company_id) then
    raise exception 'Import batch not found (or no permission)';
  end if;
  if b.status <> 'prepared' then
    raise exception 'Prepare the import batch first';
  end if;
  if exists (select 1 from erp.journal_entries e where e.import_batch_id = p_batch and e.posting_date between v_start and v_end) then
    raise exception 'Month %/% of this batch is already imported', p_month, p_year;
  end if;
  select * into v_fy from erp.fiscal_years where company_id = b.company_id and year = p_year;
  select posting_account_digits into v_d from erp.companies where id = b.company_id;
  perform pg_advisory_xact_lock(hashtext(v_fy.id::text));
  perform set_config('erp.import_engine', 'on', true);

  -- Asientos (en borrador): uno por fecha + nº de asiento + tipo
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no, entry_type,
                                   import_batch_id, source_ref)
  select b.company_id, v_fy.id, l.entry_date,
         coalesce(max(nullif(btrim(l.description), '')), 'Asiento importado ' || l.entry_ref),
         max(nullif(btrim(l.document_no), '')), l.entry_type, p_batch, l.entry_ref
  from erp.import_lines l
  where l.batch_id = p_batch and l.entry_date between v_start and v_end
  group by l.entry_date, l.entry_ref, l.entry_type;

  -- Apuntes (los importes a cero no se importan; los negativos cambian de lado)
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
  select e.id, b.company_id,
         row_number() over (partition by e.id order by l.row_no),
         g.id, erp.import_debit(l.debit, l.credit), erp.import_credit(l.debit, l.credit),
         nullif(btrim(l.description), '')
  from erp.import_lines l
  join erp.journal_entries e on e.import_batch_id = p_batch and e.status = 'draft'
                            and e.posting_date = l.entry_date and e.source_ref = l.entry_ref and e.entry_type = l.entry_type
  join erp.gl_accounts g on g.company_id = b.company_id and g.account_no = l.account_no
  where l.batch_id = p_batch and l.entry_date between v_start and v_end
    and erp.import_debit(l.debit, l.credit) - erp.import_credit(l.debit, l.credit) <> 0
    and not (erp.import_debit(l.debit, l.credit) > 0 and erp.import_credit(l.debit, l.credit) > 0);
  -- (una fila con Debe y Haber a la vez se parte en dos apuntes)
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
  select e.id, b.company_id, 1000 + row_number() over (partition by e.id order by l.row_no) * 2 + k.k, g.id,
         case k.k when 0 then erp.import_debit(l.debit, l.credit) else 0 end,
         case k.k when 1 then erp.import_credit(l.debit, l.credit) else 0 end,
         nullif(btrim(l.description), '')
  from erp.import_lines l
  cross join (values (0), (1)) k(k)
  join erp.journal_entries e on e.import_batch_id = p_batch and e.status = 'draft'
                            and e.posting_date = l.entry_date and e.source_ref = l.entry_ref and e.entry_type = l.entry_type
  join erp.gl_accounts g on g.company_id = b.company_id and g.account_no = l.account_no
  where l.batch_id = p_batch and l.entry_date between v_start and v_end
    and erp.import_debit(l.debit, l.credit) > 0 and erp.import_credit(l.debit, l.credit) > 0;

  -- Redondeo de los asientos descuadrados por céntimos (678 / 778)
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
  select x.id, b.company_id, 9999, g.id, greatest(-x.diff, 0), greatest(x.diff, 0), 'Redondeo de importación'
  from (select e.id, sum(jl.debit - jl.credit) as diff
        from erp.journal_entries e join erp.journal_lines jl on jl.entry_id = e.id
        where e.import_batch_id = p_batch and e.status = 'draft' and e.posting_date between v_start and v_end
        group by e.id having sum(jl.debit - jl.credit) <> 0) x
  join erp.gl_accounts g on g.company_id = b.company_id
   and g.account_no = case when x.diff > 0 then rpad('778', v_d - 1, '0') || '9' else rpad('678', v_d - 1, '0') || '9' end;

  -- Asientos sin apuntes (solo importes a cero): fuera
  delete from erp.journal_entries e
  where e.import_batch_id = p_batch and e.status = 'draft' and e.posting_date between v_start and v_end
    and not exists (select 1 from erp.journal_lines jl where jl.entry_id = e.id);

  -- Contabilizar: numeración correlativa del ejercicio por fecha (apertura primero, cierre al final)
  with n as (
    select e.id, (select coalesce(max(x.entry_no), 0) from erp.journal_entries x where x.fiscal_year_id = v_fy.id)
                 + row_number() over (order by e.posting_date,
                     case e.entry_type when 'opening' then 0 when 'normal' then 1 when 'closing_pl' then 2 else 3 end,
                     case when e.source_ref ~ '^[0-9]+$' then lpad(e.source_ref, 20, '0') else e.source_ref end) as no
    from erp.journal_entries e
    where e.import_batch_id = p_batch and e.status = 'draft' and e.posting_date between v_start and v_end)
  update erp.journal_entries e set status = 'posted', entry_no = n.no, posted_at = now()
  from n where n.id = e.id;
  get diagnostics v_n = row_count;

  perform set_config('erp.import_engine', 'off', true);
  return v_n;
end $function$
;
