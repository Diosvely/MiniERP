-- =====================================================================
-- 0026 · TUTOR CHECKS · Reglas de criterio contable para el Tutor de asientos
-- ---------------------------------------------------------------------
-- La primera prueba real del tutor dio un asiento que CUADRABA pero estaba mal (venta de una furgoneta con
-- pérdida en vez de beneficio). Cuadrar no basta: estas reglas del PGC lo detectan y la IA hace la segunda vuelta.
--   same_account_both_sides     la misma subcuenta en el Debe y en el Haber
--   depreciation_mismatch       la amortización acumulada no es la de su inmovilizado (218 ↔ 2818, 217 ↔ 2817…)
--   disposal_depreciation_side  en una baja de inmovilizado la amortización acumulada va al DEBE
--   asset_supplier_misuse       523 / 173 (proveedores de inmovilizado) sin ningún inmovilizado en el asiento
--   valuation_rule_mismatch     la NRV citada no encaja con las cuentas (NRV 14ª sin ingresos…)
-- Se puede volver a ejecutar: añade las cuentas que falten y sustituye las funciones.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Cuentas de 4 dígitos de la amortización acumulada (PGC 2007): 2818 es la de la 218, 2817 la de la 217…
-- Sin ellas el tutor solo podía decir "281" y no se podía comprobar que la amortización fuera la de su elemento.
-- ---------------------------------------------------------------------
insert into erp.coa_template (account_no, name, name_en, account_category) values
('2800', 'Amortización acumulada de investigación', 'Accumulated amortisation of research', 'asset'),
('2801', 'Amortización acumulada de desarrollo', 'Accumulated amortisation of development', 'asset'),
('2802', 'Amortización acumulada de concesiones administrativas', 'Accumulated amortisation of administrative concessions', 'asset'),
('2803', 'Amortización acumulada de propiedad industrial', 'Accumulated amortisation of industrial property', 'asset'),
('2804', 'Amortización acumulada de fondo de comercio', 'Accumulated amortisation of goodwill', 'asset'),
('2805', 'Amortización acumulada de derechos de traspaso', 'Accumulated amortisation of leasehold rights', 'asset'),
('2806', 'Amortización acumulada de aplicaciones informáticas', 'Accumulated amortisation of computer software', 'asset'),
('2811', 'Amortización acumulada de construcciones', 'Accumulated depreciation of buildings', 'asset'),
('2812', 'Amortización acumulada de instalaciones técnicas', 'Accumulated depreciation of technical installations', 'asset'),
('2813', 'Amortización acumulada de maquinaria', 'Accumulated depreciation of machinery', 'asset'),
('2814', 'Amortización acumulada de utillaje', 'Accumulated depreciation of tools', 'asset'),
('2815', 'Amortización acumulada de otras instalaciones', 'Accumulated depreciation of other installations', 'asset'),
('2816', 'Amortización acumulada de mobiliario', 'Accumulated depreciation of furniture', 'asset'),
('2817', 'Amortización acumulada de equipos para procesos de información', 'Accumulated depreciation of IT equipment', 'asset'),
('2818', 'Amortización acumulada de elementos de transporte', 'Accumulated depreciation of vehicles', 'asset'),
('2819', 'Amortización acumulada de otro inmovilizado material', 'Accumulated depreciation of other property, plant and equipment', 'asset')
on conflict (account_no) do nothing;

create or replace function erp.tutor_criteria_checks(p_lines jsonb, p_rule text)
returns jsonb language plpgsql immutable as $$
declare
  v_out   jsonb := '[]';
  r       record;
begin
  -- 1. La misma subcuenta en los dos lados
  for r in select x->>'account_no' as acc from jsonb_array_elements(p_lines) x
           group by 1 having sum((x->>'debit')::numeric) > 0 and sum((x->>'credit')::numeric) > 0 loop
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'same_account_both_sides', 'detail', r.acc);
  end loop;

  -- 2. Amortización acumulada que no corresponde a su inmovilizado: 281d ↔ 21d · 280d ↔ 20d
  for r in select distinct left(d->>'account_no', 4) as dep
           from jsonb_array_elements(p_lines) d
           where d->>'account_no' ~ '^28[01][0-9]'
             -- hay inmovilizado del mismo subgrupo (20 / 21) en el asiento…
             and exists (select 1 from jsonb_array_elements(p_lines) a
                         where left(a->>'account_no', 2) = '2' || substr(d->>'account_no', 3, 1))
             -- …pero ninguno es el que corresponde a esta amortización (2818 → 218)
             and not exists (select 1 from jsonb_array_elements(p_lines) a
                             where left(a->>'account_no', 3) = '2' || substr(d->>'account_no', 3, 2)) loop
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'depreciation_mismatch',
                                         'detail', r.dep || ' ↔ 2' || substr(r.dep, 3, 2));
  end loop;

  -- 3. Baja: se abona el inmovilizado y la amortización acumulada también va al Haber
  if exists (select 1 from jsonb_array_elements(p_lines) a
             where a->>'account_no' ~ '^2[0-3]' and (a->>'credit')::numeric > 0)
     and exists (select 1 from jsonb_array_elements(p_lines) d
                 where d->>'account_no' ~ '^28' and (d->>'credit')::numeric > 0) then
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'disposal_depreciation_side', 'detail', '');
  end if;

  -- 4. Proveedor de inmovilizado sin inmovilizado
  if exists (select 1 from jsonb_array_elements(p_lines) x
             where x->>'account_no' ~ '^(523|173)' and (x->>'credit')::numeric > 0)
     and not exists (select 1 from jsonb_array_elements(p_lines) x
                     where x->>'account_no' ~ '^2[0-5]' and (x->>'debit')::numeric > 0) then
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'asset_supplier_misuse', 'detail', '');
  end if;

  -- 5. NRV que no encaja con las cuentas del asiento
  if p_rule is not null and p_rule <> '' and not exists (
       select 1 from jsonb_array_elements(p_lines) x
       where x->>'account_no' ~ case p_rule
               when 'NRV2'  then '^(21|23|281|291|671|771)'
               when 'NRV3'  then '^(21|23|281|291|671|771)'
               when 'NRV4'  then '^(22|282|292|672|772)'
               when 'NRV5'  then '^(20|280|290|670|770)'
               when 'NRV6'  then '^(20|280|290|670|770)'
               when 'NRV10' then '^(3|60|61|39|693|793)'
               when 'NRV12' then '^(472|477|631|634|639)'
               when 'NRV13' then '^(630|633|638|4752|473|474|479)'
               when 'NRV14' then '^(70|71|72|73|74|75)'
               when 'NRV18' then '^(13|74|94)'
               else '.' end) then
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'valuation_rule_mismatch', 'detail', p_rule);
  end if;
  return v_out;
end $$;

-- La comprobación de la 0025, igual, más las reglas de criterio al final
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
        where g.company_id = p_company and g.account_type = 'posting'
          -- su cuenta del PGC, o una subcuenta que empiece igual (empresas importadas: 28130000 se creó con la 281)
          and (g.template_account = v_tpl or g.account_no like v_tpl || '%')
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

  -- Reglas de criterio contable (0026)
  v_checks := v_checks || erp.tutor_criteria_checks(v_lines, p_proposal->>'valuation_rule');

  return jsonb_build_object(
    'ok', not exists (select 1 from jsonb_array_elements(v_checks) c where c->>'level' = 'error'),
    'lines', v_lines, 'checks', v_checks, 'debit', v_debit, 'credit', v_credit);
end $$;

revoke execute on function erp.tutor_criteria_checks(jsonb, text) from anon, public;
grant execute on function erp.tutor_criteria_checks(jsonb, text) to authenticated;
