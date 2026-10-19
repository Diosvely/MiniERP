-- =====================================================================
-- 0052 · MODELOS 347 Y 349 · v0.39.0
-- ---------------------------------------------------------------------
-- Declaraciones informativas que salen solas del libro registro de facturas:
--   · 347 · Operaciones con terceras personas (RD 1065/2007, arts. 31 a 35): cada tercero con el que la empresa ha
--     superado 3.005,06 € en el año, por separado compras (clave A) y ventas (clave B), con el IVA / IGIC incluido y
--     el desglose por trimestres. Fuera: las operaciones intracomunitarias y las exportaciones (van en el 349 o no se
--     declaran), las facturas con retención de IRPF (ya están en el 190 / 180) y los terceros extranjeros.
--   · 349 · Operaciones intracomunitarias (RIVA, arts. 78 a 81), solo con IVA: entregas de bienes (E), prestaciones de
--     servicios (S), adquisiciones de bienes (A) y de servicios (I), por NIF-IVA, con las rectificaciones de periodos
--     anteriores aparte. Es mensual si las entregas y servicios (E + S) pasan de 50.000 € en el trimestre o en alguno
--     de los cuatro anteriores; si no, trimestral.
-- Servicios o bienes: la línea a la 705 / 759 (ventas) o a la 62 (compras) es un servicio.
-- No incluye: cobros en metálico de más de 6.000 € (el ERP no sabe qué cobros son en efectivo), arrendamientos de
-- locales, operaciones triangulares ni consignas. Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Modelo 347: erp.form_347(empresa, año)
-- ---------------------------------------------------------------------
create or replace function erp.form_347(p_company uuid, p_year int)
returns table (partner_id uuid, partner_name text, vat_registration_no text, op_key text,
               q1 numeric, q2 numeric, q3 numeric, q4 numeric, total numeric, missing_vat_no boolean)
language sql stable as $$
  with x as (
    select i.partner_id, case i.invoice_type when 'purchase' then 'A' else 'B' end as op_key,
           extract(quarter from i.posting_date)::int as q,
           -- importe total de la operación: base + impuesto repercutido + recargo (en la ISP el proveedor no repercute)
           sum(t.tax_base + case when c.rate_category in ('reverse_charge', 'intra_eu_acquisition') then 0 else t.tax_amount end
               + t.surcharge_amount) as amount
    from erp.invoices i
    join erp.invoice_tax_lines t on t.invoice_id = i.id
    join erp.tax_codes c on c.code = t.tax_code
    join erp.business_partners bp on bp.id = i.partner_id
    where i.company_id = p_company and i.posting_date between make_date(p_year, 1, 1) and make_date(p_year, 12, 31)
      and i.withholding_amount = 0                                   -- con retención: van en el 190 / 180
      and bp.tax_territory in ('mainland', 'canary_islands', 'ceuta_melilla')
      and c.rate_category not in ('intra_eu', 'intra_eu_acquisition', 'export')
    group by 1, 2, 3
  )
  select x.partner_id, bp.name, bp.vat_registration_no, x.op_key,
         coalesce(sum(x.amount) filter (where x.q = 1), 0), coalesce(sum(x.amount) filter (where x.q = 2), 0),
         coalesce(sum(x.amount) filter (where x.q = 3), 0), coalesce(sum(x.amount) filter (where x.q = 4), 0),
         sum(x.amount), bp.vat_registration_no is null or btrim(bp.vat_registration_no) = ''
  from x join erp.business_partners bp on bp.id = x.partner_id
  group by x.partner_id, bp.name, bp.vat_registration_no, x.op_key
  having abs(sum(x.amount)) > 3005.06                                -- «superior a 3.005,06 €» (art. 33.1)
  order by x.op_key desc, bp.name;
$$;

-- ---------------------------------------------------------------------
-- 2) Modelo 349: líneas intracomunitarias, por clave (de cada línea de la factura)
-- ---------------------------------------------------------------------
create or replace function erp.intra_eu_lines(p_company uuid)
returns table (invoice_id uuid, corrected_invoice_id uuid, posting_date date, partner_id uuid, op_key text, amount numeric)
language sql stable as $$
  select i.id, i.corrected_invoice_id, i.posting_date, i.partner_id,
         case when i.invoice_type = 'sale' then case when g.account_no ~ '^(705|759)' then 'S' else 'E' end
              else case when g.account_no ~ '^62' then 'I' else 'A' end end,
         sum(l.amount * l.sign)
  from erp.invoices i
  join erp.invoice_lines l on l.invoice_id = i.id
  join erp.tax_codes c on c.code = l.tax_code
  join erp.gl_accounts g on g.id = l.gl_account_id
  where i.company_id = p_company
    and ((i.invoice_type = 'sale' and c.rate_category = 'intra_eu') or (i.invoice_type = 'purchase' and c.rate_category = 'intra_eu_acquisition'))
  group by 1, 2, 3, 4, 5;
$$;

-- Periodo del 349: mensual si E + S pasa de 50.000 € en el trimestre o en alguno de los cuatro anteriores
create or replace function erp.form_349_period(p_company uuid, p_year int, p_quarter int)
returns text language sql stable as $$
  select case when exists (
    select 1 from erp.intra_eu_lines(p_company) x
    where x.op_key in ('E', 'S')
      and x.posting_date between erp.quarter_start(p_year, p_quarter) - interval '12 months' and erp.quarter_end(p_year, p_quarter)
    group by date_trunc('quarter', x.posting_date)
    having sum(x.amount) > 50000) then 'monthly' else 'quarterly' end;
$$;

-- Modelo 349 del trimestre: operaciones y rectificaciones de periodos anteriores
--   section operation:     el importe del trimestre por NIF-IVA y clave (las rectificativas del mismo trimestre, restadas)
--   section rectification: rectificativa de una factura de otro trimestre → periodo corregido, importe rectificado
--                          (lo declarado más la corrección) e importe declarado anteriormente
create or replace function erp.form_349(p_company uuid, p_year int, p_quarter int)
returns table (section text, partner_id uuid, partner_name text, vat_registration_no text, op_key text,
               amount numeric, corrected_period text, previously_declared numeric)
language plpgsql stable as $$
#variable_conflict use_column
declare v_type text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
        v_from date := erp.quarter_start(p_year, p_quarter); v_to date := erp.quarter_end(p_year, p_quarter);
begin
  if p_quarter not between 1 and 4 then raise exception 'Invalid quarter: %', p_quarter; end if;
  if v_type = 'IGIC' then return; end if;   -- Canarias no forma parte del territorio de aplicación del IVA de la UE
  return query
  with l as (
    select x.*, o.posting_date as original_date
    from erp.intra_eu_lines(p_company) x
    left join erp.invoices o on o.id = x.corrected_invoice_id
  ), ops as (   -- las del trimestre (y las rectificativas de facturas del mismo trimestre)
    select l.partner_id, l.op_key, sum(l.amount) as amount
    from l where l.posting_date between v_from and v_to
      and (l.corrected_invoice_id is null or l.original_date between v_from and v_to)
    group by 1, 2
  ), rect as (  -- rectificativas de facturas de un trimestre anterior
    select l.partner_id, l.op_key, extract(year from l.original_date)::int as y, extract(quarter from l.original_date)::int as q,
           sum(l.amount) as correction
    from l where l.posting_date between v_from and v_to and l.corrected_invoice_id is not null
      and l.original_date < v_from
    group by 1, 2, 3, 4
  )
  select 'operation', o.partner_id, bp.name, bp.vat_registration_no, o.op_key, o.amount, null::text, null::numeric
  from ops o join erp.business_partners bp on bp.id = o.partner_id where o.amount <> 0
  union all
  select 'rectification', r.partner_id, bp.name, bp.vat_registration_no, r.op_key,
         d.declared + r.correction, r.q || 'T ' || r.y, d.declared
  from rect r join erp.business_partners bp on bp.id = r.partner_id
  cross join lateral (
    select coalesce(sum(l.amount), 0) as declared from l
    where l.partner_id = r.partner_id and l.op_key = r.op_key
      and l.posting_date between erp.quarter_start(r.y, r.q) and erp.quarter_end(r.y, r.q)
      and (l.corrected_invoice_id is null or l.original_date between erp.quarter_start(r.y, r.q) and erp.quarter_end(r.y, r.q))
  ) d
  order by 1, 3, 5;
end $$;

revoke execute on function erp.form_347(uuid, int), erp.intra_eu_lines(uuid), erp.form_349_period(uuid, int, int),
  erp.form_349(uuid, int, int) from anon, public;
grant execute on function erp.form_347(uuid, int), erp.intra_eu_lines(uuid), erp.form_349_period(uuid, int, int),
  erp.form_349(uuid, int, int) to authenticated;
