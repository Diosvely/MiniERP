-- =====================================================================
-- 0025 · ENTRY TUTOR · Tutor de asientos con IA
-- ---------------------------------------------------------------------
-- Describes una operación ("compro un ordenador de 1.200 € más IVA…") y la IA propone el asiento.
-- La IA PROPONE, el ERP COMPRUEBA y el usuario DECIDE:
--   1. entry_tutor_context: lo que se le enseña a la IA. El PGC 2007 (público), los tipos de IVA / IGIC VIGENTES
--      de la empresa con sus cuentas, las retenciones y la lista cerrada de normas de registro y valoración.
--      NUNCA las subcuentas ni los terceros de la empresa (pueden llevar nombres reales).
--   2. validate_proposed_entry: comprueba la propuesta como un asiento más:
--      cuentas del PGC, Debe = Haber, IVA / IGIC con la cuenta y el importe que salen de nuestras tablas,
--      subcuentas de la empresa (existentes o nuevas) y avisos de criterio (523 para el inmovilizado…).
--   3. El asiento nunca se contabiliza solo: la web lo carga como BORRADOR en el formulario de asientos.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Normas de registro y valoración del PGC 2007 (Real Decreto 1514/2007, modificado por el RD 1/2021)
-- La IA solo puede citar una de esta lista: nada de artículos de memoria.
-- ---------------------------------------------------------------------
create table erp.valuation_rules (
  code      text primary key,
  sort      int  not null,
  title     text not null,
  title_en  text not null
);

insert into erp.valuation_rules (code, sort, title, title_en) values
('NRV1',  1,  'NRV 1ª Desarrollo del Marco Conceptual de la Contabilidad', '1st Development of the Conceptual Framework'),
('NRV2',  2,  'NRV 2ª Inmovilizado material', '2nd Property, plant and equipment'),
('NRV3',  3,  'NRV 3ª Normas particulares sobre el inmovilizado material', '3rd Specific rules on property, plant and equipment'),
('NRV4',  4,  'NRV 4ª Inversiones inmobiliarias', '4th Investment property'),
('NRV5',  5,  'NRV 5ª Inmovilizado intangible', '5th Intangible assets'),
('NRV6',  6,  'NRV 6ª Normas particulares sobre el inmovilizado intangible', '6th Specific rules on intangible assets'),
('NRV7',  7,  'NRV 7ª Activos no corrientes y grupos enajenables de elementos mantenidos para la venta', '7th Non-current assets held for sale'),
('NRV8',  8,  'NRV 8ª Arrendamientos y otras operaciones de naturaleza similar', '8th Leases'),
('NRV9',  9,  'NRV 9ª Instrumentos financieros', '9th Financial instruments'),
('NRV10', 10, 'NRV 10ª Existencias', '10th Inventories'),
('NRV11', 11, 'NRV 11ª Moneda extranjera', '11th Foreign currency'),
('NRV12', 12, 'NRV 12ª Impuesto sobre el Valor Añadido (IVA)', '12th Value Added Tax (VAT)'),
('NRV13', 13, 'NRV 13ª Impuestos sobre beneficios', '13th Income tax'),
('NRV14', 14, 'NRV 14ª Ingresos por ventas y prestación de servicios', '14th Revenue from sales and services'),
('NRV15', 15, 'NRV 15ª Provisiones y contingencias', '15th Provisions and contingencies'),
('NRV16', 16, 'NRV 16ª Pasivos por retribuciones a largo plazo al personal', '16th Long-term employee benefits'),
('NRV17', 17, 'NRV 17ª Transacciones con pagos basados en instrumentos de patrimonio', '17th Share-based payments'),
('NRV18', 18, 'NRV 18ª Subvenciones, donaciones y legados recibidos', '18th Grants, donations and bequests received'),
('NRV19', 19, 'NRV 19ª Combinaciones de negocios', '19th Business combinations'),
('NRV20', 20, 'NRV 20ª Negocios conjuntos', '20th Joint ventures'),
('NRV21', 21, 'NRV 21ª Operaciones entre empresas del grupo', '21st Transactions between group companies'),
('NRV22', 22, 'NRV 22ª Cambios en criterios contables, errores y estimaciones contables', '22nd Changes in accounting policies, errors and estimates'),
('NRV23', 23, 'NRV 23ª Hechos posteriores al cierre del ejercicio', '23rd Events after the reporting period');

alter table erp.valuation_rules enable row level security;
create policy read on erp.valuation_rules for select to authenticated using (true);
revoke all on erp.valuation_rules from anon, public;
grant select on erp.valuation_rules to authenticated;

-- ---------------------------------------------------------------------
-- Lo que se le enseña a la IA (solo el owner, como el Analista IA)
-- ---------------------------------------------------------------------
create or replace function erp.entry_tutor_context(p_company uuid, p_language text default 'es')
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare
  en boolean := p_language = 'en';
  c  erp.companies;
begin
  if not erp.is_owner() then raise exception 'The AI tutor is only available to the application owner'; end if;
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into c from erp.companies where id = p_company;

  return jsonb_build_object(
    'language', case when en then 'en' else 'es' end,
    'today', current_date,
    'company', jsonb_build_object(
      'industry', c.industry, 'tax_territory', c.tax_territory,
      'tax', case c.tax_territory when 'canary_islands' then 'IGIC' else 'IVA' end,
      'vat_regime', c.vat_regime),
    -- PGC 2007: cuentas de 3 y 4 dígitos (las de 1 y 2 son títulos de grupo y subgrupo)
    'chart_of_accounts', (select jsonb_agg(t.account_no || ' ' || case when en then t.name_en else t.name end
                                           order by t.account_no)
                          from erp.coa_template t where t.level >= 3),
    -- Tipos vigentes de la empresa, con sus cuentas: la IA no decide ni el tipo ni la cuenta del impuesto
    'tax_codes', (select jsonb_agg(jsonb_build_object(
                    'tax_code', s.tax_code, 'tax', s.tax_type, 'category', s.rate_category, 'rate_pct', s.rate_pct,
                    'description', case when en then coalesce(s.description_en, s.description) else s.description end,
                    'input_account', s.input_account_no, 'output_account', s.output_account_no) order by s.tax_code)
                  from erp.v_tax_setup s where s.company_id = p_company and not s.blocked),
    'tax_setup', exists (select 1 from erp.v_tax_setup s where s.company_id = p_company),
    'withholdings', (select jsonb_agg(jsonb_build_object(
                       'code', w.withholding_code, 'rate_pct', w.rate_pct, 'form', w.form,
                       'description', case when en then coalesce(w.description_en, w.description) else w.description end,
                       'payable_account', w.payable_account_no, 'receivable_account', w.receivable_account_no)
                       order by w.withholding_code)
                     from erp.v_withholding_setup w where w.company_id = p_company and not w.blocked),
    'valuation_rules', (select jsonb_agg(jsonb_build_object('code', r.code,
                          'title', case when en then r.title_en else r.title end) order by r.sort)
                        from erp.valuation_rules r));
end $$;

-- ---------------------------------------------------------------------
-- Siguiente subcuenta libre de una cuenta del PGC: 217 → 21700001, 21700002…
-- ---------------------------------------------------------------------
create or replace function erp.next_subaccount_no(p_company uuid, p_template text)
returns text language sql stable as $$
  with d as (select posting_account_digits as n from erp.companies where id = p_company)
  select coalesce(
           (select lpad((max(g.account_no::numeric) + 1)::text, d.n, '0')
            from erp.gl_accounts g
            where g.company_id = p_company and g.account_no like p_template || '%' and length(g.account_no) = d.n
            having max(g.account_no::numeric) is not null),
           rpad(p_template, d.n - 1, '0') || '1')
  from d;
$$;

-- ---------------------------------------------------------------------
-- COMPROBACIÓN DE LA PROPUESTA
--   p_proposal = { "partner_name": "…" opcional,
--                  "lines": [ { "account": "217" | "21700001", "side": "debit" | "credit", "amount": 1200,
--                               "description": "…", "role": "base" | "tax" | "partner" | "cash" | "withholding" | "other",
--                               "tax_code": "VAT21" (en las líneas de impuesto), "tax_base": 1200 } ] }
--   Devuelve { ok, lines (resueltas a subcuentas de la empresa), checks [{level, code, detail}], debit, credit }
--   level: error (no se puede cargar) · warning (revísalo) · info
-- ---------------------------------------------------------------------
create or replace function erp.validate_proposed_entry(p_company uuid, p_proposal jsonb)
returns jsonb language plpgsql stable as $$
declare
  v_lines    jsonb := '[]';
  v_checks   jsonb := '[]';
  v_digits   int;
  v_p_name   text;           -- tercero encontrado: nombre, subcuenta, su nombre y su cuenta del PGC
  v_p_no     text;
  v_p_acc    text;
  v_p_tpl    text;
  v_has_tax  boolean;
  l          record;
  v_acc      record;
  v_tax      record;
  v_no       text;
  v_name     text;
  v_tpl      text;
  v_source   text;
  v_amount   numeric;
  v_expected numeric;
  v_debit    numeric := 0;
  v_credit   numeric := 0;
  v_new      jsonb := '{}';     -- subcuentas nuevas ya numeradas (dos líneas con la misma cuenta del PGC)
  v_has_fixed boolean := false;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select posting_account_digits into v_digits from erp.companies where id = p_company;
  -- Empresas importadas: sin configuración de impuestos, las líneas de IVA / IGIC se tratan como cuentas normales
  v_has_tax := exists (select 1 from erp.v_tax_setup s where s.company_id = p_company);
  if not v_has_tax then
    v_checks := v_checks || jsonb_build_object('level', 'info', 'code', 'no_tax_setup', 'detail', '');
  end if;

  if jsonb_typeof(p_proposal->'lines') <> 'array' or jsonb_array_length(p_proposal->'lines') < 2 then
    return jsonb_build_object('ok', false, 'lines', '[]'::jsonb, 'debit', 0, 'credit', 0,
      'checks', jsonb_build_array(jsonb_build_object('level', 'error', 'code', 'too_few_lines', 'detail', '')));
  end if;

  -- Tercero que el usuario nombró: se busca entre los de la empresa (no se ha enviado ninguno a la IA)
  if coalesce(trim(p_proposal->>'partner_name'), '') <> '' then
    select p.name, g.account_no, g.name, g.template_account into v_p_name, v_p_no, v_p_acc, v_p_tpl
    from erp.business_partners p join erp.gl_accounts g on g.id = p.gl_account_id
    where p.company_id = p_company and not p.blocked
      and (p.name ilike '%' || trim(p_proposal->>'partner_name') || '%' or trim(p_proposal->>'partner_name') ilike '%' || p.name || '%')
    order by length(p.name) limit 1;
    if v_p_no is null then
      v_checks := v_checks || jsonb_build_object('level', 'warning', 'code', 'partner_not_found',
                                                 'detail', p_proposal->>'partner_name');
    else
      v_checks := v_checks || jsonb_build_object('level', 'info', 'code', 'partner_found',
                                                 'detail', v_p_name || ' → ' || v_p_no);
    end if;
  end if;

  for l in select x.ord as line_no, x.v from jsonb_array_elements(p_proposal->'lines') with ordinality x(v, ord) loop
    v_no := regexp_replace(coalesce(l.v->>'account', ''), '\D', '', 'g');
    v_amount := round(case when (l.v->>'amount') ~ '^-?[0-9]+(\.[0-9]+)?$' then (l.v->>'amount')::numeric end, 2);
    v_name := null; v_tpl := null; v_source := null;

    if v_amount is null or v_amount <= 0 then
      v_checks := v_checks || jsonb_build_object('level', 'error', 'code', 'bad_amount', 'detail', l.line_no);
      continue;
    end if;
    if l.v->>'side' not in ('debit', 'credit') then
      v_checks := v_checks || jsonb_build_object('level', 'error', 'code', 'bad_side', 'detail', l.line_no);
      continue;
    end if;

    -- Línea del tercero con un tercero conocido: su subcuenta
    if l.v->>'role' = 'partner' and v_p_no is not null and left(v_no, 3) = left(v_p_tpl, 3) then
      v_no := v_p_no; v_name := v_p_acc; v_source := 'partner';
    end if;

    -- Impuestos: la cuenta y el importe salen de nuestras tablas, no de la IA
    if l.v->>'role' = 'tax' and v_has_tax then
      select s.* into v_tax from erp.v_tax_setup s
      where s.company_id = p_company and s.tax_code = l.v->>'tax_code' and not s.blocked;
      if v_tax.tax_code is null then
        v_checks := v_checks || jsonb_build_object('level', 'error', 'code', 'unknown_tax_code',
                                                   'detail', coalesce(l.v->>'tax_code', '?'));
      else
        v_no := case when l.v->>'side' = 'debit' then v_tax.input_account_no else v_tax.output_account_no end;
        v_name := case when l.v->>'side' = 'debit' then v_tax.input_account_name else v_tax.output_account_name end;
        v_source := 'tax';
        if (l.v->>'tax_base') ~ '^[0-9]+(\.[0-9]+)?$' then
          v_expected := round((l.v->>'tax_base')::numeric * v_tax.rate_pct / 100, 2);
          if v_expected <> v_amount then
            v_checks := v_checks || jsonb_build_object('level', 'warning', 'code', 'tax_amount_fixed',
              'detail', v_tax.tax_code || ': ' || v_amount || ' → ' || v_expected);
            v_amount := v_expected;
          end if;
        end if;
      end if;
    end if;

    -- Cuenta: subcuenta de la empresa que ya existe…
    if v_source is null then
      select g.account_no, g.name, g.template_account, g.account_type into v_acc
      from erp.gl_accounts g where g.company_id = p_company and g.account_no = v_no;
      if v_acc.account_no is not null and v_acc.account_type = 'posting' then
        v_name := v_acc.name; v_source := 'existing';
      -- …o una cuenta del PGC: su primera subcuenta, o una nueva
      elsif exists (select 1 from erp.coa_template t where t.account_no = v_no and t.level >= 3) then
        v_tpl := v_no;
        select g.account_no, g.name into v_acc from erp.gl_accounts g
        where g.company_id = p_company and g.account_type = 'posting' and g.template_account = v_tpl
          and not g.blocked
          -- las subcuentas de terceros (430…, 400…) no se usan para otro: mejor una genérica nueva
          and not exists (select 1 from erp.business_partners p where p.gl_account_id = g.id)
        order by g.account_no limit 1;
        if v_acc.account_no is not null then
          v_no := v_acc.account_no; v_name := v_acc.name; v_source := 'subaccount';
        else
          v_no := coalesce(v_new->>v_tpl, erp.next_subaccount_no(p_company, v_tpl));
          v_new := v_new || jsonb_build_object(v_tpl, v_no);
          select t.name into v_name from erp.coa_template t where t.account_no = v_tpl;
          v_source := 'new';
          v_checks := v_checks || jsonb_build_object('level', 'info', 'code', 'new_subaccount',
                                                     'detail', v_no || ' ' || v_name);
        end if;
      else
        v_checks := v_checks || jsonb_build_object('level', 'error', 'code', 'unknown_account',
                                                   'detail', coalesce(nullif(l.v->>'account', ''), '?'));
        continue;
      end if;
    end if;

    if left(v_no, 1) = '2' and l.v->>'side' = 'debit' and left(v_no, 2) not in ('28', '29') then
      v_has_fixed := true;
    end if;
    if l.v->>'side' = 'debit' then v_debit := v_debit + v_amount; else v_credit := v_credit + v_amount; end if;

    v_lines := v_lines || jsonb_build_object(
      'line_no', l.line_no, 'account_no', v_no, 'account_name', v_name, 'source', v_source,
      'new_account', v_source = 'new',
      'debit', case when l.v->>'side' = 'debit' then v_amount else 0 end,
      'credit', case when l.v->>'side' = 'credit' then v_amount else 0 end,
      'description', left(coalesce(l.v->>'description', ''), 200));
  end loop;

  -- Criterio: el inmovilizado se compra a un proveedor de inmovilizado (523 / 173), no a un 400 / 410
  if v_has_fixed and exists (select 1 from jsonb_array_elements(v_lines) x
                             where x->>'account_no' ~ '^(40|41)' and (x->>'credit')::numeric > 0) then
    v_checks := v_checks || jsonb_build_object('level', 'warning', 'code', 'fixed_asset_supplier', 'detail', '');
  end if;
  if v_debit <> v_credit then
    v_checks := v_checks || jsonb_build_object('level', 'error', 'code', 'unbalanced',
                                               'detail', v_debit || ' / ' || v_credit);
  end if;
  if p_proposal ? 'valuation_rule'
     and not exists (select 1 from erp.valuation_rules r where r.code = p_proposal->>'valuation_rule') then
    v_checks := v_checks || jsonb_build_object('level', 'warning', 'code', 'unknown_valuation_rule',
                                               'detail', p_proposal->>'valuation_rule');
  end if;

  return jsonb_build_object(
    'ok', not exists (select 1 from jsonb_array_elements(v_checks) c where c->>'level' = 'error'),
    'lines', v_lines, 'checks', v_checks, 'debit', v_debit, 'credit', v_credit);
end $$;

revoke execute on function erp.entry_tutor_context(uuid, text), erp.next_subaccount_no(uuid, text),
  erp.validate_proposed_entry(uuid, jsonb) from anon, public;
grant execute on function erp.entry_tutor_context(uuid, text), erp.next_subaccount_no(uuid, text),
  erp.validate_proposed_entry(uuid, jsonb) to authenticated;
