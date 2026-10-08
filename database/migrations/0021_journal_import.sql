-- =====================================================================
-- 0021 · JOURNAL IMPORT · Importación de diarios de otros ERP (Modo auditor, parte 1)
-- ---------------------------------------------------------------------
-- "De afuera hacia adentro": un diario completo de Sage, Dynamics BC u otro ERP se convierte (en la web) a la
-- PLANTILLA DEL LABORATORIO y entra en una EMPRESA NUEVA, con sus ejercicios, subcuentas, aperturas y cierres.
-- Después, balance, PyG, sumas y saldos, mayor, saldos anómalos y cierre funcionan igual que con lo registrado a mano.
--
--   Plantilla (una fila por apunte):
--     fecha · asiento · tipo (opening / normal / closing_pl / closing) · cuenta · nombre · debe · haber · concepto · documento
--
--   1. erp.import_start(...)            → crea la empresa (con los dígitos del fichero) y el lote
--   2. la web sube las filas a erp.import_lines (por bloques)
--   3. erp.import_preview(lote)          → controles de auditor ANTES de importar: cuadre por asiento, negativos,
--                                          cuentas nuevas, años, y si cada apertura coincide con el cierre anterior
--   4. erp.import_prepare(lote)          → ejercicios y subcuentas; devuelve los meses a importar
--   5. erp.import_post_month(lote, año, mes) → contabiliza un mes (llamadas cortas: Supabase corta a los pocos segundos)
--   6. erp.import_finish(lote)           → cierra los ejercicios anteriores (con los cierres del fichero o con el nuestro)
--
-- Rendimiento: las funciones del motor son SECURITY DEFINER (comprueban primero que eres administrador de la
-- empresa del lote y solo tocan esa empresa) para no evaluar la seguridad fila a fila en 100.000 apuntes.
--
-- Reglas del laboratorio (ADR 0011):
--   · una importación = una empresa nueva (no se mezclan datos importados con registrados);
--   · los importes negativos de Sage ("anular en negativo") pasan al lado contrario en positivo;
--   · los asientos descuadrados por céntimos (≤ 1 €) se cuadran con 678 / 778 "redondeos"; si es más, no se importa;
--   · los asientos históricos no se bloquean por saldos inversos: se SEÑALAN en el informe de saldos anómalos.
-- Como los paquetes de configuración / "Import G/L Entries" de BC o la LSMW de SAP para los saldos iniciales.
-- =====================================================================

-- Cuentas del PGC que faltaban en la plantilla (aparecen en diarios reales: Sage y Dynamics)
insert into erp.coa_template (account_no, name, name_en, account_category) values
('259', 'Desembolsos pendientes sobre participaciones en el patrimonio neto', 'Uncalled capital on equity investments', 'asset'),
('293', 'Deterioro de valor de participaciones a largo plazo en partes vinculadas', 'Impairment of long-term investments in related parties', 'asset'),
('297', 'Deterioro de valor de valores representativos de deuda a largo plazo', 'Impairment of long-term debt securities', 'asset'),
('598', 'Deterioro de valor de valores representativos de deuda a corto plazo', 'Impairment of short-term debt securities', 'asset'),
('633', 'Ajustes negativos en la imposición sobre beneficios', 'Negative adjustments to income tax', 'expense'),
('638', 'Ajustes positivos en la imposición sobre beneficios', 'Positive adjustments to income tax', 'expense'),
('644', 'Retribuciones a largo plazo mediante sistemas de prestación definida', 'Long-term defined benefit remuneration', 'expense'),
('673', 'Pérdidas procedentes de participaciones a largo plazo en partes vinculadas', 'Losses on long-term investments in related parties', 'expense'),
('796', 'Reversión del deterioro de participaciones e instrumentos de patrimonio neto a largo plazo', 'Reversal of impairment of long-term equity investments', 'income'),
('799', 'Reversión del deterioro de créditos a corto plazo', 'Reversal of impairment of short-term loans', 'income')
on conflict do nothing;

create table erp.import_batches (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references erp.companies(id) on delete cascade,
  source       text not null check (source in ('template', 'sage', 'dynamics')),
  file_name    text,
  status       text not null default 'staging' check (status in ('staging', 'prepared', 'posted')),
  summary      jsonb,
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  finished_at  timestamptz
);

create table erp.import_lines (
  batch_id      uuid not null references erp.import_batches(id) on delete cascade,
  company_id    uuid not null references erp.companies(id) on delete cascade,
  row_no        int not null,
  entry_date    date not null,
  entry_ref     text not null,                -- nº de asiento / transacción en el ERP de origen
  entry_type    text not null default 'normal' check (entry_type in ('opening', 'normal', 'closing_pl', 'closing')),
  account_no    text not null,
  account_name  text,
  debit         numeric(15,2) not null default 0,
  credit        numeric(15,2) not null default 0,
  description   text,
  document_no   text,
  primary key (batch_id, row_no)
);
create index import_lines_entry on erp.import_lines (batch_id, entry_date, entry_ref, entry_type);

alter table erp.journal_entries
  add column import_batch_id uuid references erp.import_batches(id) on delete set null,
  add column source_ref text;               -- nº de asiento en el ERP de origen
create index journal_entries_import on erp.journal_entries (import_batch_id, posting_date) where import_batch_id is not null;

-- Solo se suben filas a un lote abierto de una empresa que administras
create or replace function erp.import_batch_open(p_batch uuid, p_company uuid)
returns boolean language sql stable as $$
  select exists (select 1 from erp.import_batches b
                 where b.id = p_batch and b.company_id = p_company and b.status = 'staging');
$$;

alter table erp.import_batches enable row level security;
alter table erp.import_lines enable row level security;
create policy read on erp.import_batches for select to authenticated using (erp.can_read(company_id));
create policy write on erp.import_batches for all to authenticated
  using (erp.is_admin(company_id)) with check (erp.is_admin(company_id));
create policy read on erp.import_lines for select to authenticated using (erp.is_admin(company_id));
create policy write on erp.import_lines for insert to authenticated
  with check (erp.is_admin(company_id) and erp.import_batch_open(batch_id, company_id));
create policy remove on erp.import_lines for delete to authenticated
  using (erp.is_admin(company_id) and erp.import_batch_open(batch_id, company_id));

-- Importe normalizado: un negativo en el Debe es un Haber (y al revés)
create or replace function erp.import_debit(p_debit numeric, p_credit numeric)
returns numeric language sql immutable as $$ select greatest(p_debit, 0) + greatest(-p_credit, 0) $$;
create or replace function erp.import_credit(p_debit numeric, p_credit numeric)
returns numeric language sql immutable as $$ select greatest(p_credit, 0) + greatest(-p_debit, 0) $$;

-- Nombre de una subcuenta nueva: el del fichero o, si viene oculto ("****", "Nombre cuenta…"), el de su cuenta del PGC
create or replace function erp.import_account_name(p_account_no text, p_name text)
returns text language sql stable as $$
  select case
    when nullif(btrim(p_name), '') is null or p_name like '%*%' or p_name ilike 'nombre cuenta%' then
      coalesce((select t.name from erp.coa_template t where p_account_no like t.account_no || '%' and t.level >= 3
                order by t.level desc limit 1), 'Cuenta') || ' ' || p_account_no
    else btrim(p_name) end;
$$;

-- ---------------------------------------------------------------------
-- 1) EMPEZAR: empresa nueva + lote
-- ---------------------------------------------------------------------
create or replace function erp.import_start(
  p_name text, p_digits int, p_territory text, p_industry text, p_source text, p_file_name text default null)
returns table (company_id uuid, batch_id uuid)
language plpgsql as $$
declare
  v_company uuid;
  v_batch   uuid;
begin
  insert into erp.companies (name, industry, tax_territory, posting_account_digits, created_by)
  values (p_name, p_industry, p_territory, p_digits, auth.uid())
  returning id into v_company;
  insert into erp.import_batches (company_id, source, file_name)
  values (v_company, p_source, p_file_name)
  returning id into v_batch;
  return query select v_company, v_batch;
end $$;

-- ---------------------------------------------------------------------
-- 2) VISTA PREVIA con los controles de auditor (no cambia nada)
-- ---------------------------------------------------------------------
create or replace function erp.import_preview(p_batch uuid)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
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
end $$;

-- ---------------------------------------------------------------------
-- 3) PREPARAR: ejercicios y subcuentas; devuelve los meses a contabilizar
-- ---------------------------------------------------------------------
create or replace function erp.import_prepare(p_batch uuid)
returns table (year int, month int, entries bigint)
language plpgsql security definer set search_path = erp, public as $$
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
end $$;

-- ---------------------------------------------------------------------
-- 4) CONTABILIZAR UN MES (en bloque: miles de apuntes en una llamada corta)
-- ---------------------------------------------------------------------
create or replace function erp.import_post_month(p_batch uuid, p_year int, p_month int)
returns int language plpgsql security definer set search_path = erp, public as $$
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
end $$;

-- ---------------------------------------------------------------------
-- 5) TERMINAR: cierra UN ejercicio por llamada (el más antiguo pendiente, salvo el último del fichero);
--    cuando no queda ninguno, borra las filas temporales y da el lote por importado. Devuelve {year, …, done}.
--    · si el año siguiente trae su APERTURA (Sage, A3…): se cierra con los asientos del propio fichero
--    · si no (Dynamics BC no hace cierre ni apertura): se cierra con nuestro asistente, que los genera
-- ---------------------------------------------------------------------
create or replace function erp.import_finish(p_batch uuid)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
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
end $$;

-- ---------------------------------------------------------------------
-- Triggers: en modo importación se saltan las comprobaciones fila a fila que el motor ya hace en bloque
-- ---------------------------------------------------------------------
create or replace function erp.tg_line_validate()
returns trigger language plpgsql as $$
declare
  v_entry    erp.journal_entries;
  v_account  erp.gl_accounts;
begin
  if coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  -- Importación: el motor ya ha validado empresa, cuentas y número de línea (miles de apuntes por llamada)
  if tg_op = 'INSERT' and coalesce(current_setting('erp.import_engine', true), '') = 'on' then
    return new;
  end if;

  -- 1) El asiento debe estar en borrador (vale para INSERT, UPDATE y DELETE)
  select * into v_entry from erp.journal_entries
  where id = case when tg_op = 'DELETE' then old.entry_id else new.entry_id end;

  if v_entry.status = 'posted' then
    raise exception 'Entry % is posted: its lines cannot be changed', v_entry.entry_no;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  -- 2) La empresa del apunte es siempre la del asiento
  new.company_id := v_entry.company_id;

  -- 3) La cuenta: de la misma empresa, subcuenta y no bloqueada
  select * into v_account from erp.gl_accounts where id = new.gl_account_id;
  if v_account.company_id <> new.company_id then
    raise exception 'Account % does not belong to this company', v_account.account_no;
  end if;
  if v_account.account_type <> 'posting' then
    raise exception 'Account % (%) is a heading account: use a posting account', v_account.account_no, v_account.name;
  end if;
  if v_account.blocked then
    raise exception 'Account % is blocked', v_account.account_no;
  end if;

  -- 4) Número de línea automático si no se indica
  if new.line_no is null then
    select coalesce(max(line_no), 0) + 1 into new.line_no from erp.journal_lines where entry_id = new.entry_id;
  end if;
  return new;
end $$;

create or replace function erp.tg_line_set_tax_code()
returns trigger language plpgsql as $$
declare
  v_codes text[];
begin
  if coalesce(current_setting('erp.import_engine', true), '') = 'on' then
    return new;   -- los diarios importados no traen libro registro
  end if;
  if new.tax_code is null then
    select array_agg(s.tax_code) into v_codes
    from erp.tax_setup s
    where s.company_id = coalesce(new.company_id, (select e.company_id from erp.journal_entries e where e.id = new.entry_id))
      and new.gl_account_id in (s.input_account_id, s.output_account_id);
    if cardinality(v_codes) = 1 then
      new.tax_code := v_codes[1];
    end if;
  end if;
  return new;
end $$;

create or replace function erp.tg_line_tax_period_lock()
returns trigger language plpgsql as $$
declare
  v_entry  erp.journal_entries;
  v_type   text;
  v_q      erp.tax_settlements;
begin
  if coalesce(current_setting('erp.tax_settlement_engine', true), '') = 'on'
     or coalesce(current_setting('erp.year_closing_engine', true), '') = 'on'
     or coalesce(current_setting('erp.import_engine', true), '') = 'on'
     or coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return new;
  end if;
  select * into v_entry from erp.journal_entries where id = new.entry_id;
  select c.tax_type into v_type
  from erp.tax_setup s join erp.tax_codes c on c.code = s.tax_code
  where s.company_id = v_entry.company_id and new.gl_account_id in (s.input_account_id, s.output_account_id)
  limit 1;
  if v_type is null then
    return new;
  end if;
  select * into v_q from erp.tax_settlements
  where company_id = v_entry.company_id and tax_type = v_type and status = 'posted'
    and v_entry.posting_date <= period_end
  order by period_end desc limit 1;
  if found then
    raise exception '% quarter %T % is already settled: post this with a later date (or cancel the settlement)',
      v_type, v_q.quarter, v_q.year;
  end if;
  return new;
end $$;

create or replace function erp.tg_entry_check_inverse()
returns trigger language plpgsql as $$
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
end $$;

-- ---------------------------------------------------------------------
-- Sumas y saldos (y saldos anómalos) SIN el asiento de cierre, como la opción "excluir cierre" de A3 / ContaPlus:
-- en un ejercicio cerrado (importado o no) se siguen viendo los saldos finales
-- ---------------------------------------------------------------------
create or replace function erp.trial_balance(
  p_company uuid, p_year int, p_level int default null, p_to_date date default null)
returns table (account_no text, name text, name_en text, total_debit numeric, total_credit numeric,
               debit_balance numeric, credit_balance numeric)
language sql stable as $$
  with mov as (
    select case when p_level is null then a.account_no else left(a.account_no, p_level) end as account_no,
           l.debit, l.credit
    from erp.journal_lines l
    join erp.journal_entries e  on e.id = l.entry_id
    join erp.fiscal_years    fy on fy.id = e.fiscal_year_id
    join erp.gl_accounts     a  on a.id = l.gl_account_id
    where e.company_id = p_company
      and fy.year = p_year
      and e.status = 'posted'
      and e.entry_type <> 'closing'            -- sin el asiento de cierre: si no, un año cerrado sale todo a cero
      and (p_to_date is null or e.posting_date <= p_to_date)
  )
  select m.account_no,
         a.name,
         a.name_en,
         sum(m.debit),
         sum(m.credit),
         greatest(sum(m.debit) - sum(m.credit), 0),
         greatest(sum(m.credit) - sum(m.debit), 0)
  from mov m
  left join erp.gl_accounts a on a.company_id = p_company and a.account_no = m.account_no
  group by m.account_no, a.name, a.name_en
  order by m.account_no;
$$;

-- Libro diario: los asientos importados se reconocen por su origen
create or replace view erp.v_import_batches with (security_invoker = true) as
select b.id, b.company_id, c.name as company_name, b.source, b.file_name, b.status, b.summary, b.created_at, b.finished_at
from erp.import_batches b join erp.companies c on c.id = b.company_id;

revoke all on erp.import_batches, erp.import_lines, erp.v_import_batches from anon, public;
grant select, insert, update on erp.import_batches to authenticated;
grant select on erp.v_import_batches to authenticated;
grant select, insert, delete on erp.import_lines to authenticated;
revoke execute on function erp.import_batch_open(uuid, uuid), erp.import_debit(numeric, numeric), erp.import_credit(numeric, numeric),
  erp.import_account_name(text, text), erp.import_start(text, int, text, text, text, text), erp.import_preview(uuid),
  erp.import_prepare(uuid), erp.import_post_month(uuid, int, int), erp.import_finish(uuid) from anon, public;
grant execute on function erp.import_batch_open(uuid, uuid), erp.import_debit(numeric, numeric), erp.import_credit(numeric, numeric),
  erp.import_account_name(text, text), erp.import_start(text, int, text, text, text, text), erp.import_preview(uuid),
  erp.import_prepare(uuid), erp.import_post_month(uuid, int, int), erp.import_finish(uuid) to authenticated;
