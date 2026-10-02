-- =====================================================================
-- 0008 · IMPORT POSTING ACCOUNTS · Importación de subcuentas desde CSV
-- ---------------------------------------------------------------------
-- Patrón "cargar → previsualizar → validar → importar" (como los paquetes de configuración
-- de Business Central o la LSMW / Migration Cockpit de SAP). Se reutilizará para importar
-- asientos, clientes y proveedores.
--
-- La web lee el CSV y envía las filas en JSON:
--   [{"account_no": "57200001", "name": "Banco 1", "name_en": "Bank 1"}, ...]
--
-- erp.import_posting_accounts(company, rows, dry_run)
--   dry_run = true  → solo valida y devuelve el estado de cada fila (vista previa). No guarda nada.
--   dry_run = false → importa TODO o NADA: si alguna fila tiene error, no se guarda ninguna.
--
-- Estados por fila: 'insert' (nueva) · 'update' (ya existe: se actualizan los nombres) · 'error'
-- La seguridad la sigue imponiendo RLS: solo admin/accountant de la empresa pueden importar.
-- =====================================================================

-- Cuenta del PGC de la que cuelga una subcuenta (la más larga que sea prefijo, de 3 o 4 dígitos)
create or replace function erp.template_parent(p_account_no text)
returns text language sql stable as $$
  select account_no from erp.coa_template
  where p_account_no like account_no || '%' and level >= 3
  order by level desc
  limit 1;
$$;

create or replace function erp.import_posting_accounts(
  p_company uuid, p_rows jsonb, p_dry_run boolean default true)
returns table (line_no int, account_no text, name text, status text, message text)
language plpgsql as $$
declare
  v_digits  smallint;
  v_result  jsonb;
  v_errors  int;
  r         record;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Rows must be a JSON array';
  end if;
  if jsonb_array_length(p_rows) > 2000 then
    raise exception 'Too many rows: maximum 2000 per import';
  end if;

  select c.posting_account_digits into v_digits from erp.companies c where c.id = p_company;
  if v_digits is null then
    raise exception 'Company not found (or no permission)';
  end if;
  if not p_dry_run and not erp.can_write(p_company) then
    raise exception 'No permission to import into this company';
  end if;

  -- 1) Normalizar y clasificar todas las filas (sin guardar nada)
  with src as (
    select e.ord::int as line_no,
           regexp_replace(coalesce(e.val->>'account_no', ''), '\s', '', 'g') as account_no,
           nullif(btrim(e.val->>'name'), '')    as name,
           nullif(btrim(e.val->>'name_en'), '') as name_en
    from jsonb_array_elements(p_rows) with ordinality as e(val, ord)
  ),
  firsts as (select s.account_no, min(s.line_no) as first_line from src s group by s.account_no),
  classified as (
    select s.*, erp.template_parent(s.account_no) as parent, g.account_type, f.first_line
    from src s
    join firsts f on f.account_no = s.account_no
    left join erp.gl_accounts g on g.company_id = p_company and g.account_no = s.account_no
  ),
  checked as (
    select c.*,
      case
        when c.account_no !~ '^[0-9]+$'        then 'error'
        when length(c.account_no) <> v_digits  then 'error'
        when c.name is null                    then 'error'
        when c.parent is null                  then 'error'
        when c.line_no > c.first_line          then 'error'
        when c.account_type = 'posting'        then 'update'
        when c.account_type is not null        then 'error'
        else 'insert'
      end as status,
      case
        when c.account_no !~ '^[0-9]+$'        then 'Account number must contain digits only'
        when length(c.account_no) <> v_digits  then format('Must have %s digits', v_digits)
        when c.name is null                    then 'Name is required'
        when c.parent is null                  then 'Does not belong to any PGC account (3 or 4 digits)'
        when c.line_no > c.first_line          then 'Duplicated in file (line ' || c.first_line || ')'
        when c.account_type = 'posting'        then 'Already exists: names will be updated'
        when c.account_type is not null        then 'Is a heading account of the PGC'
        else 'New posting account under ' || c.parent
      end as message
    from classified c
  )
  select jsonb_agg(to_jsonb(k) order by k.line_no) into v_result from checked k;

  -- 2) Importar (todo o nada)
  if not p_dry_run then
    select count(*) into v_errors from jsonb_array_elements(v_result) x where x->>'status' = 'error';
    if v_errors > 0 then
      raise exception 'Import cancelled: % row(s) with errors. Nothing was saved.', v_errors;
    end if;

    for r in select * from jsonb_to_recordset(v_result)
               as x(line_no int, account_no text, name text, name_en text, status text) loop
      if r.status = 'insert' then
        insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
        values (p_company, r.account_no, r.name, r.name_en, 'posting', '', '');   -- el trigger rellena cuenta madre y masa
      else
        update erp.gl_accounts g set name = r.name, name_en = coalesce(r.name_en, g.name_en)
        where g.company_id = p_company and g.account_no = r.account_no;
      end if;
    end loop;
  end if;

  return query
    select x.line_no, x.account_no, x.name, x.status, x.message
    from jsonb_to_recordset(coalesce(v_result, '[]'))
         as x(line_no int, account_no text, name text, status text, message text)
    order by x.line_no;
end $$;

revoke execute on function erp.template_parent(text), erp.import_posting_accounts(uuid, jsonb, boolean) from anon, public;
grant execute on function erp.template_parent(text), erp.import_posting_accounts(uuid, jsonb, boolean) to authenticated;
