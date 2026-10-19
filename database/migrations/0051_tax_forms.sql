-- =====================================================================
-- 0051 · MODELOS DE IVA / IGIC CON SUS CASILLAS: 303 y 420 trimestrales, 390 y 425 anuales · v0.39.0
-- ---------------------------------------------------------------------
-- La liquidación (0012) ya calcula la cuota del trimestre y la cuadra con la contabilidad. Aquí se reparte en las
-- CASILLAS OFICIALES de cada modelo, desde el libro registro de facturas, como el borrador de A3 / Sage o el
-- «VAT statement» de Business Central:
--   · 303 (IVA, trimestral)      · instrucciones de la AEAT de 2026
--   · 420 (IGIC, trimestral)     · instrucciones de la Agencia Tributaria Canaria
--   · 390 (IVA, resumen anual)   · instrucciones y Manual práctico de IVA de la AEAT (2025)
--   · 425 (IGIC, resumen anual)  · instrucciones de la Agencia Tributaria Canaria
-- Reglas de clasificación (todas desde la factura, sin datos nuevos):
--   · las rectificativas no van en su tipo: van en «modificación de bases y cuotas» (devengado) y en «rectificación de
--     deducciones» (deducible);
--   · BIENES DE INVERSIÓN: la línea de la factura recibida a una cuenta 21 / 22 de al menos 3.005,06 € (art. 108 LIVA;
--     art. 40.Nueve.6.º Ley 20/1991 en el IGIC: 500.000 pesetas); el resto, corrientes;
--   · adquisición intracomunitaria de SERVICIOS: la línea a una cuenta 62; si no, de bienes;
--   · cuota deducible tras la prorrata (la del libro registro) y su base en la misma proporción.
-- Fuera de alcance: importaciones, regímenes especiales (simplificado, agricultura, criterio de caja), ventanilla única.
-- Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Las líneas del libro registro, clasificadas para los modelos
--   kind: out_rate · out_mod · out_aib_goods · out_aib_serv · out_isp · out_re · out_re_mod
--         in_cur · in_inv · in_aib_cur · in_aib_inv · in_aib_serv · in_mod
--         info_eu · info_exp · info_ns · info_exempt · info_re_retail · asset_sale · pro_rata
-- ---------------------------------------------------------------------
create or replace function erp.tax_form_lines(p_company uuid, p_tax_type text, p_from date, p_to date)
returns table (kind text, rate numeric, base numeric, quota numeric)
language sql stable as $$
  with t as (   -- cada línea de impuesto de las facturas del periodo
    select r.*, i.id as inv_id
    from erp.v_invoice_register r join erp.invoices i on i.id = r.invoice_id
    where r.company_id = p_company and r.tax_type = p_tax_type and r.posting_date between p_from and p_to
  ),
  cls as (      -- clase de cada línea de la factura: inversión · servicio · bienes (por su cuenta y su importe)
    select l.invoice_id, l.tax_code,
           case when g.account_no ~ '^2[12]' and l.amount >= 3005.06 then 'inv'
                when g.account_no ~ '^62' then 'serv' else 'cur' end as cl,
           sum(l.amount * l.sign) as amt
    from erp.invoice_lines l join erp.gl_accounts g on g.id = l.gl_account_id
    where l.company_id = p_company and l.invoice_id in (select inv_id from t)
    group by 1, 2, 3
  ),
  split as (    -- la base de cada clase y su parte de la cuota (la última clase se lleva el redondeo)
    select t.*, c.cl, c.amt,
           case when t.tax_base = 0 then 0 else round(t.tax_amount * c.amt / t.tax_base, 2) end as q,
           case when t.tax_base = 0 then 0 else round(t.deductible_amount * c.amt / t.tax_base, 2) end as dq,
           row_number() over (partition by t.invoice_id, t.tax_code order by c.cl desc) as rn,
           count(*) over (partition by t.invoice_id, t.tax_code) as n,
           sum(case when t.tax_base = 0 then 0 else round(t.tax_amount * c.amt / t.tax_base, 2) end)
             over (partition by t.invoice_id, t.tax_code) as q_sum,
           sum(case when t.tax_base = 0 then 0 else round(t.deductible_amount * c.amt / t.tax_base, 2) end)
             over (partition by t.invoice_id, t.tax_code) as dq_sum
    from t join cls c on c.invoice_id = t.invoice_id and c.tax_code = t.tax_code
  ),
  s as (
    select split.*, q + case when rn = 1 then tax_amount - q_sum else 0 end as quota_c,
                    dq + case when rn = 1 then deductible_amount - dq_sum else 0 end as ded_c
    from split
  )
  -- VENTAS
  select case when t.document_kind = 'credit_memo' then 'out_mod' else 'out_rate' end, t.rate_pct, t.tax_base, t.tax_amount
  from t where t.invoice_type = 'sale'
    and t.rate_category not in ('intra_eu', 'export', 'not_subject', 'exempt', 'retail_surcharge')
  union all
  select case when t.document_kind = 'credit_memo' then 'out_re_mod' else 'out_re' end, c.equivalence_surcharge_pct, t.tax_base, t.surcharge_amount
  from t join erp.tax_codes c on c.code = t.tax_code where t.invoice_type = 'sale' and t.surcharge_amount <> 0
  union all
  select case t.rate_category when 'intra_eu' then 'info_eu' when 'export' then 'info_exp' when 'not_subject' then 'info_ns'
                              when 'exempt' then 'info_exempt' else 'info_re_retail' end, t.rate_pct, t.tax_base, 0
  from t where t.invoice_type = 'sale' and t.rate_category in ('intra_eu', 'export', 'not_subject', 'exempt', 'retail_surcharge')
  union all
  -- entregas de bienes de inversión (venta de un activo: la línea a la cuenta 2x), para el volumen de operaciones
  select 'asset_sale', null, sum(l.amount * l.sign), 0
  from erp.invoice_lines l join erp.gl_accounts g on g.id = l.gl_account_id join t on t.inv_id = l.invoice_id and t.tax_code = l.tax_code
  where t.invoice_type = 'sale' and g.account_no like '2%'
  group by l.invoice_id, l.tax_code
  union all
  -- COMPRAS: la cuota que DEVENGA la empresa (adquisición intracomunitaria e inversión del sujeto pasivo)
  select case when s.document_kind = 'credit_memo' then 'out_mod'
              when s.rate_category = 'reverse_charge' then 'out_isp'
              when s.cl = 'serv' then 'out_aib_serv' else 'out_aib_goods' end, s.rate_pct, s.amt, s.quota_c
  from s where s.invoice_type = 'purchase' and s.rate_category in ('intra_eu_acquisition', 'reverse_charge')
  union all
  -- COMPRAS: la cuota DEDUCIBLE (tras la prorrata), con su base en la misma proporción
  select case when s.document_kind = 'credit_memo' then 'in_mod'
              when s.rate_category = 'intra_eu_acquisition' then case s.cl when 'inv' then 'in_aib_inv' when 'serv' then 'in_aib_serv' else 'in_aib_cur' end
              else case s.cl when 'inv' then 'in_inv' else 'in_cur' end end,
         s.rate_pct,
         case when s.quota_c = 0 then s.amt else round(s.amt * s.ded_c / s.quota_c, 2) end, s.ded_c
  from s where s.invoice_type = 'purchase' and s.ded_c <> 0
  union all
  -- regularización de la prorrata (4T)
  select 'pro_rata', pr.definitive_pct, null, pr.regularization_amount
  from erp.pro_rata pr join erp.journal_entries je on je.id = pr.entry_id
  where pr.company_id = p_company and pr.tax_type = p_tax_type and je.posting_date between p_from and p_to;
$$;

-- Tipo en texto: 5,2 (español) · 5.2 (inglés), sin ceros sobrantes (7.00 → 7)
create or replace function erp.pct_text(p numeric, p_lang text default 'es')
returns text language sql immutable as $$
  select case p_lang when 'en' then trim_scale(p)::text else replace(trim_scale(p)::text, '.', ',') end;
$$;

-- fila de una casilla (la función de abajo las va juntando)
create or replace function erp.tf_row(p_sort int, p_section text, p_box text, p_concept text, p_concept_en text, p_kind text, p_amount numeric)
returns jsonb language sql immutable as $$
  select jsonb_build_object('sort', p_sort, 'section', p_section, 'box', p_box, 'concept', p_concept, 'concept_en', p_concept_en,
                            'kind', p_kind, 'amount', coalesce(p_amount, 0));
$$;

-- ---------------------------------------------------------------------
-- 2) Casillas del modelo: erp.tax_form_boxes(empresa, año, trimestre)
--    trimestre 1-4 → 303 / 420 · trimestre null → resumen anual 390 / 425 (el impuesto, el del territorio)
--    kind: base · rate · quota · amount · pct (para dar formato) · section: devengado · deducible · resultado ·
--          informacion · volumen
-- ---------------------------------------------------------------------
create or replace function erp.tax_form_boxes(p_company uuid, p_year int, p_quarter int default null)
returns table (sort int, form text, section text, box text, concept text, concept_en text, kind text, amount numeric)
language plpgsql stable as $$
#variable_conflict use_column
declare
  v_type text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
  v_from date; v_to date; v_form text; v_annual boolean := p_quarter is null;
  v_n int := 0;
  r record; v_slot int; v_dev numeric; v_ded numeric; v_res numeric; v_carry numeric; v_applied numeric; v_set erp.tax_settlements;
  v_x numeric; v_y numeric; v_l jsonb; v_out jsonb := '[]';
begin
  if v_type is null then return; end if;
  if p_quarter is not null and p_quarter not between 1 and 4 then raise exception 'Invalid quarter: %', p_quarter; end if;
  v_from := erp.quarter_start(p_year, coalesce(p_quarter, 1));
  v_to := erp.quarter_end(p_year, coalesce(p_quarter, 4));
  v_form := case when v_type = 'VAT' then case when v_annual then '390' else '303' end else case when v_annual then '425' else '420' end end;
  -- las líneas clasificadas, una vez (las sumas de cada casilla se hacen sobre ellas)
  v_l := coalesce((select jsonb_agg(to_jsonb(x)) from erp.tax_form_lines(p_company, v_type, v_from, v_to) x), '[]');

  if v_form in ('303', '390') then
    -- ===================== IVA devengado =====================
    for r in select * from (values
        (0::numeric,  '150', '151', '152', '700', '701'),
        (4::numeric,  '01',  '02',  '03',  '01',  '02'),
        (10::numeric, '04',  '05',  '06',  '03',  '04'),
        (21::numeric, '07',  '08',  '09',  '05',  '06')) as x(rate, b303, t303, q303, b390, q390) loop
      select coalesce(sum(l.base), 0), coalesce(sum(l.quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as l(kind text, rate numeric, base numeric, quota numeric) where l.kind = 'out_rate' and l.rate = r.rate;
      if r.rate = 0 and v_x = 0 then continue; end if;
      v_n := v_n + 1;
      if v_form = '303' then
        v_out := v_out || jsonb_build_array(erp.tf_row(v_n * 10, 'devengado', r.b303, 'Régimen general al ' || erp.pct_text(r.rate, 'es') || ' %: base imponible', 'General regime at ' || erp.pct_text(r.rate, 'en') || ' %: tax base', 'base', v_x), erp.tf_row(v_n * 10 + 1, 'devengado', r.t303, 'Tipo', 'Rate', 'rate', r.rate), erp.tf_row(v_n * 10 + 2, 'devengado', r.q303, 'Cuota', 'Tax', 'quota', v_y));
      else
        v_out := v_out || jsonb_build_array(erp.tf_row(v_n * 10, 'devengado', r.b390, 'Régimen ordinario al ' || erp.pct_text(r.rate, 'es') || ' %: base imponible', 'Ordinary regime at ' || erp.pct_text(r.rate, 'en') || ' %: tax base', 'base', v_x), erp.tf_row(v_n * 10 + 2, 'devengado', r.q390, 'Cuota', 'Tax', 'quota', v_y));
      end if;
    end loop;
    -- adquisiciones intracomunitarias e inversión del sujeto pasivo
    if v_form = '303' then
      select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind in ('out_aib_goods', 'out_aib_serv');
      v_out := v_out || jsonb_build_array(erp.tf_row(100, 'devengado', '10', 'Adquisiciones intracomunitarias de bienes y servicios: base', 'Intra-EU acquisitions of goods and services: base', 'base', v_x), erp.tf_row(101, 'devengado', '11', 'Adquisiciones intracomunitarias: cuota', 'Intra-EU acquisitions: tax', 'quota', v_y));
      select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'out_isp';
      v_out := v_out || jsonb_build_array(erp.tf_row(102, 'devengado', '12', 'Otras operaciones con inversión del sujeto pasivo: base', 'Other reverse-charge operations: base', 'base', v_x), erp.tf_row(103, 'devengado', '13', 'Inversión del sujeto pasivo: cuota', 'Reverse charge: tax', 'quota', v_y));
      select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'out_mod';
      v_out := v_out || jsonb_build_array(erp.tf_row(104, 'devengado', '14', 'Modificación de bases y cuotas (rectificativas): base', 'Modified bases and taxes (credit memos): base', 'base', v_x), erp.tf_row(105, 'devengado', '15', 'Modificación de bases y cuotas: cuota', 'Modified bases and taxes: tax', 'quota', v_y));
    else
      for r in select * from (values (4::numeric, '21', '22', '545', '546'), (10::numeric, '23', '24', '547', '548'), (21::numeric, '25', '26', '551', '552'))
                              as x(rate, bg, qg, bs, qs) loop
        select coalesce(sum(base) filter (where kind = 'out_aib_goods'), 0), coalesce(sum(quota) filter (where kind = 'out_aib_goods'), 0)
          into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where rate = r.rate;
        if v_x <> 0 or v_y <> 0 then
          v_out := v_out || jsonb_build_array(erp.tf_row(110 + r.rate::int, 'devengado', r.bg, 'Adquisiciones intracomunitarias de bienes al ' || erp.pct_text(r.rate, 'es') || ' %: base', 'Intra-EU acquisitions of goods at ' || erp.pct_text(r.rate, 'en') || ' %: base', 'base', v_x), erp.tf_row(110 + r.rate::int, 'devengado', r.qg, 'Cuota', 'Tax', 'quota', v_y));
        end if;
        select coalesce(sum(base) filter (where kind = 'out_aib_serv'), 0), coalesce(sum(quota) filter (where kind = 'out_aib_serv'), 0)
          into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where rate = r.rate;
        if v_x <> 0 or v_y <> 0 then
          v_out := v_out || jsonb_build_array(erp.tf_row(140 + r.rate::int, 'devengado', r.bs, 'Adquisiciones intracomunitarias de servicios al ' || erp.pct_text(r.rate, 'es') || ' %: base', 'Intra-EU acquisitions of services at ' || erp.pct_text(r.rate, 'en') || ' %: base', 'base', v_x), erp.tf_row(140 + r.rate::int, 'devengado', r.qs, 'Cuota', 'Tax', 'quota', v_y));
        end if;
      end loop;
      select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'out_isp';
      v_out := v_out || jsonb_build_array(erp.tf_row(170, 'devengado', '27', 'Otros supuestos de inversión del sujeto pasivo: base', 'Other reverse-charge cases: base', 'base', v_x), erp.tf_row(171, 'devengado', '28', 'Cuota', 'Tax', 'quota', v_y));
      select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'out_mod';
      v_out := v_out || jsonb_build_array(erp.tf_row(172, 'devengado', '29', 'Modificación de bases y cuotas: base', 'Modified bases and taxes: base', 'base', v_x), erp.tf_row(173, 'devengado', '30', 'Cuota', 'Tax', 'quota', v_y));
    end if;
    -- recargo de equivalencia
    for r in select * from (values (0.5::numeric, '168', '170', '35', '36'), (1.4::numeric, '19', '21', '599', '600'),
                                   (5.2::numeric, '22', '24', '601', '602'), (1.75::numeric, '156', '158', '41', '42')) as x(rate, b303, q303, b390, q390) loop
      select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'out_re' and rate = r.rate;
      if v_x = 0 and v_y = 0 then continue; end if;
      v_out := v_out || jsonb_build_array(erp.tf_row(200 + (r.rate * 10)::int, 'devengado', case v_form when '303' then r.b303 else r.b390 end,
                                 'Recargo de equivalencia al ' || erp.pct_text(r.rate, 'es') || ' %: base', 'Equivalence surcharge at ' || erp.pct_text(r.rate, 'en') || ' %: base', 'base', v_x), erp.tf_row(201 + (r.rate * 10)::int, 'devengado', case v_form when '303' then r.q303 else r.q390 end, 'Cuota', 'Tax', 'quota', v_y));
    end loop;
    select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'out_re_mod';
    if v_x <> 0 or v_y <> 0 then
      v_out := v_out || jsonb_build_array(erp.tf_row(290, 'devengado', case v_form when '303' then '25' else '43' end, 'Modificación de recargo de equivalencia: base', 'Modified equivalence surcharge: base', 'base', v_x), erp.tf_row(291, 'devengado', case v_form when '303' then '26' else '44' end, 'Cuota', 'Tax', 'quota', v_y));
    end if;
    select coalesce(sum(quota), 0) into v_dev from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind in ('out_rate', 'out_mod', 'out_aib_goods', 'out_aib_serv', 'out_isp', 'out_re', 'out_re_mod');
    v_out := v_out || jsonb_build_array(erp.tf_row(299, 'devengado', case v_form when '303' then '27' else '47' end, 'Total cuota devengada', 'Total output tax', 'amount', v_dev));

    -- ===================== IVA deducible =====================
    if v_form = '303' then
      for r in select * from (values (300, 'in_cur', '28', '29', 'Operaciones interiores corrientes', 'Domestic current purchases'),
                                     (302, 'in_inv', '30', '31', 'Operaciones interiores con bienes de inversión', 'Domestic capital goods'),
                                     (304, 'imp_cur', '32', '33', 'Importaciones de bienes corrientes', 'Imports of current goods'),
                                     (306, 'imp_inv', '34', '35', 'Importaciones de bienes de inversión', 'Imports of capital goods'),
                                     (308, 'aib_cur', '36', '37', 'Adquisiciones intracomunitarias de bienes y servicios corrientes', 'Intra-EU acquisitions of current goods and services'),
                                     (310, 'in_aib_inv', '38', '39', 'Adquisiciones intracomunitarias de bienes de inversión', 'Intra-EU acquisitions of capital goods'),
                                     (312, 'in_mod', '40', '41', 'Rectificación de deducciones', 'Corrected deductions')) as x(s, k, b, q, c, ce) loop
        select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric)
        where kind = r.k or (r.k = 'aib_cur' and kind in ('in_aib_cur', 'in_aib_serv'));
        v_out := v_out || jsonb_build_array(erp.tf_row(r.s, 'deducible', r.b, r.c || ': base', r.ce || ': base', 'base', v_x), erp.tf_row(r.s + 1, 'deducible', r.q, r.c || ': cuota deducible', r.ce || ': deductible tax', 'quota', v_y));
      end loop;
      select coalesce(sum(quota), 0) into v_x from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'pro_rata';
      v_out := v_out || jsonb_build_array(erp.tf_row(344, 'deducible', '44', 'Regularización por la prorrata definitiva', 'Final pro rata adjustment', 'quota', v_x));
    else
      -- 390: por tipo (como el impreso) y los totales
      for r in select * from (values
          ('in_cur',      4::numeric, '190', '191'), ('in_cur', 10, '603', '604'), ('in_cur', 21, '605', '606'),
          ('in_inv',      4, '196', '197'), ('in_inv', 10, '611', '612'), ('in_inv', 21, '613', '614'),
          ('in_aib_cur',  4, '214', '215'), ('in_aib_cur', 10, '627', '628'), ('in_aib_cur', 21, '629', '630'),
          ('in_aib_inv',  4, '220', '221'), ('in_aib_inv', 10, '631', '632'), ('in_aib_inv', 21, '633', '634'),
          ('in_aib_serv', 4, '587', '588'), ('in_aib_serv', 10, '635', '636'), ('in_aib_serv', 21, '637', '638')) as x(k, rate, b, q) loop
        select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = r.k and rate = r.rate;
        if v_x = 0 and v_y = 0 then continue; end if;
        v_out := v_out || jsonb_build_array(erp.tf_row(300 + v_n, 'deducible', r.b, (select case r.k when 'in_cur' then 'Interiores corrientes' when 'in_inv' then 'Interiores, bienes de inversión'
            when 'in_aib_cur' then 'Adquisiciones intracomunitarias de bienes corrientes' when 'in_aib_inv' then 'Adquisiciones intracomunitarias de bienes de inversión'
            else 'Adquisiciones intracomunitarias de servicios' end) || ' al ' || erp.pct_text(r.rate, 'es') || ' %: base',
            (select case r.k when 'in_cur' then 'Domestic current' when 'in_inv' then 'Domestic capital goods' when 'in_aib_cur' then 'Intra-EU current goods'
            when 'in_aib_inv' then 'Intra-EU capital goods' else 'Intra-EU services' end) || ' at ' || erp.pct_text(r.rate, 'en') || ' %: base', 'base', v_x), erp.tf_row(301 + v_n, 'deducible', r.q, 'Cuota deducible', 'Deductible tax', 'quota', v_y));
        v_n := v_n + 2;
      end loop;
      for r in select * from (values (360, 'in_cur', '48', '49', 'Total operaciones interiores corrientes', 'Total domestic current purchases'),
                                     (362, 'in_inv', '50', '51', 'Total operaciones interiores con bienes de inversión', 'Total domestic capital goods'),
                                     (364, 'in_aib_cur', '56', '57', 'Total adquisiciones intracomunitarias de bienes corrientes', 'Total intra-EU current goods'),
                                     (366, 'in_aib_inv', '58', '59', 'Total adquisiciones intracomunitarias de bienes de inversión', 'Total intra-EU capital goods'),
                                     (368, 'in_aib_serv', '597', '598', 'Total adquisiciones intracomunitarias de servicios', 'Total intra-EU services'),
                                     (370, 'in_mod', '639', '62', 'Rectificación de deducciones', 'Corrected deductions')) as x(s, k, b, q, c, ce) loop
        select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = r.k;
        v_out := v_out || jsonb_build_array(erp.tf_row(r.s, 'deducible', r.b, r.c || ': base', r.ce || ': base', 'base', v_x), erp.tf_row(r.s + 1, 'deducible', r.q, 'Cuota deducible', 'Deductible tax', 'quota', v_y));
      end loop;
      select coalesce(sum(quota), 0) into v_x from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'pro_rata';
      v_out := v_out || jsonb_build_array(erp.tf_row(380, 'deducible', '522', 'Regularización por la prorrata definitiva', 'Final pro rata adjustment', 'quota', v_x));
    end if;
    select coalesce(sum(quota), 0) into v_ded from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind like 'in\_%' or kind = 'pro_rata';
    v_res := v_dev - v_ded;
    v_out := v_out || jsonb_build_array(erp.tf_row(399, 'deducible', case v_form when '303' then '45' else '64' end, 'Total a deducir', 'Total deductible', 'amount', v_ded), erp.tf_row(400, 'resultado', case v_form when '303' then '46' else '65' end, 'Resultado del régimen general', 'General regime result', 'amount', v_res));
  else
    -- ===================== IGIC (420 / 425) =====================
    v_slot := 0;
    for r in select l.rate, sum(l.base) as b, sum(l.quota) as q from jsonb_to_recordset(v_l) as l(kind text, rate numeric, base numeric, quota numeric) where l.kind = 'out_rate' group by l.rate order by l.rate loop
      v_slot := v_slot + 1;
      v_out := v_out || jsonb_build_array(erp.tf_row(v_slot * 10, 'devengado', case when v_slot <= 6 then lpad((v_slot * 3 - 2)::text, 2, '0') else '—' end, 'Régimen general al ' || erp.pct_text(r.rate, 'es') || ' %: base imponible', 'General regime at ' || erp.pct_text(r.rate, 'en') || ' %: tax base', 'base', r.b), erp.tf_row(v_slot * 10 + 1, 'devengado', case when v_slot <= 6 then lpad((v_slot * 3 - 1)::text, 2, '0') else '—' end, 'Tipo', 'Rate', 'rate', r.rate), erp.tf_row(v_slot * 10 + 2, 'devengado', case when v_slot <= 6 then lpad((v_slot * 3)::text, 2, '0') else '—' end, 'Cuota', 'Tax', 'quota', r.q));
    end loop;
    if v_annual then
      select coalesce(sum(base), 0) into v_x from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'out_rate';
      v_out := v_out || jsonb_build_array(erp.tf_row(95, 'devengado', '74', 'Total bases imponibles del régimen general', 'Total general regime tax bases', 'base', v_x));
    end if;
    select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind in ('out_isp', 'out_aib_goods', 'out_aib_serv');
    v_out := v_out || jsonb_build_array(erp.tf_row(100, 'devengado', case when v_annual then '75' else '19' end, 'Adquisiciones con inversión del sujeto pasivo: base', 'Reverse-charge acquisitions: base', 'base', v_x), erp.tf_row(101, 'devengado', case when v_annual then '76' else '20' end, 'Cuota', 'Tax', 'quota', v_y));
    select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'out_mod';
    v_out := v_out || jsonb_build_array(erp.tf_row(102, 'devengado', case when v_annual then '70' else '21' end, 'Modificación de bases y cuotas (rectificativas): base', 'Modified bases and taxes (credit memos): base', 'base', v_x), erp.tf_row(103, 'devengado', case when v_annual then '71' else '22' end, 'Cuota', 'Tax', 'quota', v_y));
    select coalesce(sum(quota), 0) into v_dev from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind in ('out_rate', 'out_mod', 'out_isp', 'out_aib_goods', 'out_aib_serv');
    v_out := v_out || jsonb_build_array(erp.tf_row(199, 'devengado', case when v_annual then '79' else '25' end, 'Total cuotas devengadas', 'Total output tax', 'amount', v_dev));
    for r in select * from (values (300, array['in_cur', 'in_aib_cur', 'in_aib_serv'], '26', '27', '80', '81', 'Adquisiciones interiores de bienes y servicios corrientes', 'Domestic current purchases'),
                                   (302, array['in_inv', 'in_aib_inv'], '28', '29', '82', '83', 'Adquisiciones interiores de bienes de inversión', 'Domestic capital goods'),
                                   (304, array['imp_cur'], '30', '31', '84', '85', 'Importaciones de bienes corrientes', 'Imports of current goods'),
                                   (306, array['imp_inv'], '32', '33', '86', '87', 'Importaciones de bienes de inversión', 'Imports of capital goods'),
                                   (308, array['in_mod'], '34', '35', '88', '89', 'Rectificación de deducciones', 'Corrected deductions')) as x(s, ks, b, q, ba, qa, c, ce) loop
      select coalesce(sum(base), 0), coalesce(sum(quota), 0) into v_x, v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = any (r.ks);
      v_out := v_out || jsonb_build_array(erp.tf_row(r.s, 'deducible', case when v_annual then r.ba else r.b end, r.c || ': base', r.ce || ': base', 'base', v_x), erp.tf_row(r.s + 1, 'deducible', case when v_annual then r.qa else r.q end, r.c || ': cuota deducible', r.ce || ': deductible tax', 'quota', v_y));
    end loop;
    select coalesce(sum(quota), 0) into v_x from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'pro_rata';
    v_out := v_out || jsonb_build_array(erp.tf_row(344, 'deducible', case when v_annual then '93' else '39' end, 'Regularización por la prorrata definitiva', 'Final pro rata adjustment', 'quota', v_x));
    select coalesce(sum(quota), 0) into v_ded from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind like 'in\_%' or kind = 'pro_rata';
    v_res := v_dev - v_ded;
    v_out := v_out || jsonb_build_array(erp.tf_row(399, 'deducible', case when v_annual then '94' else '40' end, 'Total cuotas deducibles', 'Total deductible tax', 'amount', v_ded), erp.tf_row(400, 'resultado', case when v_annual then '95' else '41' end, 'Diferencia (devengadas − deducibles)', 'Difference (output − deductible)', 'amount', v_res));
  end if;

  -- ===================== Resultado y compensación =====================
  -- cuotas a compensar de periodos anteriores, como la liquidación (0012)
  select coalesce(sum(case when s.outcome = 'carry_forward' then -s.final_result else 0 end), 0) - coalesce(sum(s.carry_applied), 0)
    into v_carry
  from erp.tax_settlements s
  where s.company_id = p_company and s.tax_type = v_type and s.status = 'posted' and (s.year, s.quarter) < (p_year, coalesce(p_quarter, 1));
  if not v_annual then
    select * into v_set from erp.tax_settlements s where s.company_id = p_company and s.tax_type = v_type and s.year = p_year
      and s.quarter = p_quarter and s.status = 'posted';
    v_applied := case when v_set.id is not null then v_set.carry_applied else least(greatest(v_res, 0), v_carry) end;
    if v_form = '303' then
      v_out := v_out || jsonb_build_array(erp.tf_row(410, 'resultado', '64', 'Suma de resultados', 'Sum of results', 'amount', v_res), erp.tf_row(411, 'resultado', '65', '% atribuible a la Administración del Estado', '% attributable to the State', 'pct', 100), erp.tf_row(412, 'resultado', '66', 'Atribuible a la Administración del Estado', 'Attributable to the State', 'amount', v_res), erp.tf_row(413, 'resultado', '110', 'Cuotas a compensar pendientes de periodos anteriores', 'Credit pending from previous periods', 'amount', v_carry), erp.tf_row(414, 'resultado', '78', 'Cuotas a compensar aplicadas en este periodo', 'Credit applied in this period', 'amount', v_applied), erp.tf_row(415, 'resultado', '87', 'Cuotas a compensar pendientes para periodos posteriores', 'Credit carried to later periods', 'amount', v_carry - v_applied), erp.tf_row(416, 'resultado', '69', 'Resultado', 'Result', 'amount', v_res - v_applied), erp.tf_row(417, 'resultado', '71', 'Resultado de la liquidación (a ingresar si es positivo; a compensar o devolver si es negativo)', 'Return result (payable if positive; to carry forward or refund if negative)', 'amount', v_res - v_applied));
    else
      v_out := v_out || jsonb_build_array(erp.tf_row(413, 'resultado', '43', 'Cuotas a compensar de periodos anteriores (aplicadas)', 'Credit from previous periods (applied)', 'amount', v_applied), erp.tf_row(416, 'resultado', '45', 'Resultado de la autoliquidación (a ingresar si es positivo; a compensar o devolver si es negativo)', 'Return result (payable if positive; to carry forward or refund if negative)', 'amount', v_res - v_applied));
    end if;
    -- información adicional
    for r in select * from (values ('info_eu', '59', '—', 'Entregas intracomunitarias exentas', 'Exempt intra-EU supplies'),
                                   ('info_exp', '60', '46', 'Exportaciones y operaciones asimiladas', 'Exports and similar operations'),
                                   ('info_ns', '120', '47', 'Operaciones no sujetas por reglas de localización', 'Not subject (place-of-supply rules)')) as x(k, b303, b420, c, ce) loop
      select coalesce(sum(base), 0) into v_x from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = r.k;
      if v_x = 0 or (v_form = '420' and r.b420 = '—') then continue; end if;
      v_out := v_out || jsonb_build_array(erp.tf_row(500 + v_n, 'informacion', case v_form when '303' then r.b303 else r.b420 end, r.c, r.ce, 'base', v_x));
      v_n := v_n + 1;
    end loop;
  else
    -- resumen anual: compensación del ejercicio anterior, resultado y lo ya liquidado en los trimestres
    v_out := v_out || jsonb_build_array(erp.tf_row(410, 'resultado', case v_form when '390' then '84' else '113' end, 'Suma de resultados', 'Sum of results', 'amount', v_res), erp.tf_row(411, 'resultado', case v_form when '390' then '85' else '114' end, 'Compensación de cuotas del ejercicio anterior', 'Credit from the previous year', 'amount', v_carry), erp.tf_row(412, 'resultado', case v_form when '390' then '86' else '115' end, 'Resultado de la liquidación anual', 'Annual return result', 'amount', v_res - v_carry));
    select coalesce(sum(s.final_result) filter (where s.outcome = 'payable'), 0),
           coalesce(-sum(s.final_result) filter (where s.quarter = 4 and s.outcome = 'carry_forward'), 0),
           coalesce(-sum(s.final_result) filter (where s.quarter = 4 and s.outcome = 'refund'), 0)
      into v_x, v_y, v_applied
    from erp.tax_settlements s where s.company_id = p_company and s.tax_type = v_type and s.year = p_year and s.status = 'posted';
    v_out := v_out || jsonb_build_array(erp.tf_row(420, 'resultado', case v_form when '390' then '95' else '116' end, 'Total de ingresos de las autoliquidaciones del año', 'Total paid in the year''s returns', 'amount', v_x), erp.tf_row(421, 'resultado', case v_form when '390' then '97' else '118' end, 'A compensar (última autoliquidación)', 'To carry forward (last return)', 'amount', v_y), erp.tf_row(422, 'resultado', case v_form when '390' then '98' else '119' end, 'A devolver (última autoliquidación)', 'To refund (last return)', 'amount', v_applied));
    -- volumen de operaciones
    select coalesce(sum(base) filter (where kind in ('out_rate', 'out_mod')), 0) into v_x from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric);
    v_out := v_out || jsonb_build_array(erp.tf_row(600, 'volumen', case v_form when '390' then '99' else '120' end, 'Operaciones en régimen general', 'Operations under the general regime', 'base', v_x));
    for r in select * from (values ('info_eu', '103', '—', 'Entregas intracomunitarias exentas', 'Exempt intra-EU supplies'),
                                   ('info_exp', '104', '122', 'Exportaciones y otras operaciones exentas con derecho a deducción', 'Exports and other exempt operations with deduction'),
                                   ('info_exempt', '105', '126', 'Operaciones exentas sin derecho a deducción', 'Exempt operations without deduction'),
                                   ('info_re_retail', '102', '—', 'Operaciones en régimen especial del recargo de equivalencia', 'Operations under the equivalence surcharge regime'),
                                   ('info_ns', '110', '—', 'Operaciones no sujetas por reglas de localización', 'Not subject (place-of-supply rules)')) as x(k, b390, b425, c, ce) loop
      select coalesce(sum(base), 0) into v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = r.k;
      if v_y = 0 or (v_form = '425' and r.b425 = '—') then continue; end if;
      v_out := v_out || jsonb_build_array(erp.tf_row(610 + v_n, 'volumen', case v_form when '390' then r.b390 else r.b425 end, r.c, r.ce, 'base', v_y));
      v_n := v_n + 1; v_x := v_x + v_y;
    end loop;
    select coalesce(sum(base), 0) into v_y from jsonb_to_recordset(v_l) as tf_lines(kind text, rate numeric, base numeric, quota numeric) where kind = 'asset_sale';
    v_out := v_out || jsonb_build_array(erp.tf_row(690, 'volumen', case v_form when '390' then '107' else '133' end, 'Entregas de bienes de inversión (se restan)', 'Supplies of capital goods (subtracted)', 'base', v_y), erp.tf_row(699, 'volumen', case v_form when '390' then '108' else '134' end, 'Total volumen de operaciones', 'Total turnover', 'base', v_x - v_y));
  end if;

  return query select o.sort, v_form, o.section, o.box, o.concept, o.concept_en, o.kind, o.amount
  from jsonb_to_recordset(v_out) as o(sort int, section text, box text, concept text, concept_en text, kind text, amount numeric)
  order by o.sort, o.box;
end $$;

revoke execute on function erp.tax_form_lines(uuid, text, date, date), erp.tax_form_boxes(uuid, int, int), erp.tf_row(int, text, text, text, text, text, numeric), erp.pct_text(numeric, text) from anon, public;
grant execute on function erp.tax_form_lines(uuid, text, date, date), erp.tax_form_boxes(uuid, int, int), erp.tf_row(int, text, text, text, text, text, numeric), erp.pct_text(numeric, text) to authenticated;
