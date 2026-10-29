-- =====================================================================
-- erp.validate_proposed_entry · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0025_entry_tutor 0026_tutor_checks 0033_withholding_rules   →   la vigente es la de 0033_withholding_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.validate_proposed_entry(p_company uuid, p_proposal jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
AS $function$
declare
  v_lines    jsonb := '[]';
  v_checks   jsonb := '[]';
  v_digits   int;
  v_p_name   text;           -- tercero encontrado: nombre, subcuenta, su nombre y su cuenta del PGC
  v_p_no     text;
  v_p_acc    text;
  v_p_tpl    text;
  v_p_legal  text;           -- …su forma jurídica y su retención por defecto
  v_p_wh     text;
  v_has_tax  boolean;
  v_has_wh_setup boolean;
  l          record;
  v_acc      record;
  v_tax      record;
  v_wh       record;
  v_rule     record;
  v_rule_code text;          -- retención de la regla del gasto (623 → IRPF15) y su base (el importe del gasto)
  v_rule_base numeric;
  v_code     text;
  v_base     numeric;
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
  v_fixed    boolean := false;  -- el ERP ha corregido algún importe (impuesto o retención)
  v_has_wh   boolean;
  v_prof_wh  boolean := false;  -- hay una retención de profesionales
  v_idx      int;
  v_n        int;
  v_old      numeric;
  v_side     text;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select posting_account_digits into v_digits from erp.companies where id = p_company;
  -- Empresas importadas: sin configuración de impuestos, las líneas de IVA / IGIC se tratan como cuentas normales
  v_has_tax := exists (select 1 from erp.v_tax_setup s where s.company_id = p_company);
  v_has_wh_setup := exists (select 1 from erp.v_withholding_setup s where s.company_id = p_company);
  if not v_has_tax then
    v_checks := v_checks || jsonb_build_object('level', 'info', 'code', 'no_tax_setup', 'detail', '');
  end if;

  if jsonb_typeof(p_proposal->'lines') <> 'array' or jsonb_array_length(p_proposal->'lines') < 2 then
    return jsonb_build_object('ok', false, 'lines', '[]'::jsonb, 'debit', 0, 'credit', 0,
      'checks', jsonb_build_array(jsonb_build_object('level', 'error', 'code', 'too_few_lines', 'detail', '')));
  end if;

  -- Tercero que el usuario nombró: se busca entre los de la empresa (no se ha enviado ninguno a la IA)
  if coalesce(trim(p_proposal->>'partner_name'), '') <> '' then
    select p.name, g.account_no, g.name, g.template_account, p.legal_form, p.withholding_code
    into v_p_name, v_p_no, v_p_acc, v_p_tpl, v_p_legal, v_p_wh
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

  -- Regla de retención del gasto del asiento (si lo hay): su código por defecto y su base
  select r.default_code, sum(case when (x->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' then (x->>'amount')::numeric end)
  into v_rule_code, v_rule_base
  from jsonb_array_elements(p_proposal->'lines') x
  join erp.withholding_rules r on regexp_replace(coalesce(x->>'account', ''), '\D', '', 'g') like r.account_prefix || '%'
  where x->>'side' = 'debit'
  group by r.default_code, r.account_prefix
  order by r.account_prefix desc limit 1;

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
            v_fixed := true;
          end if;
        end if;
      end if;
    end if;

    -- Retenciones: el código lo decide la ficha del tercero (o la regla del gasto); la cuenta y el importe, el ERP
    if l.v->>'role' = 'withholding' and v_has_wh_setup then
      v_code := coalesce(nullif(trim(l.v->>'withholding_code'), ''), v_p_wh, v_rule_code);
      if v_p_wh is not null and v_code <> v_p_wh then
        v_checks := v_checks || jsonb_build_object('level', 'warning', 'code', 'withholding_code_fixed',
                                                   'detail', v_code || ' → ' || v_p_wh);
        v_code := v_p_wh;
      end if;
      select s.* into v_wh from erp.v_withholding_setup s
      where s.company_id = p_company and s.withholding_code = v_code and not s.blocked;
      if v_wh.withholding_code is null then
        v_checks := v_checks || jsonb_build_object('level', 'error', 'code', 'unknown_withholding_code',
                                                   'detail', coalesce(v_code, '?'));
        continue;
      end if;
      -- Retención practicada (compras) al Haber → 4751 · soportada (ventas) al Debe → 473
      v_no := case when l.v->>'side' = 'credit' then v_wh.payable_account_no else v_wh.receivable_account_no end;
      v_name := case when l.v->>'side' = 'credit' then v_wh.payable_account_name else v_wh.receivable_account_name end;
      v_source := 'withholding';
      v_prof_wh := v_prof_wh or v_wh.kind = 'professional';
      v_base := case when (l.v->>'tax_base') ~ '^[0-9]+(\.[0-9]+)?$' then (l.v->>'tax_base')::numeric else v_rule_base end;
      if v_base is not null then
        v_expected := round(v_base * v_wh.rate_pct / 100, 2);
        if v_expected <> v_amount then
          v_checks := v_checks || jsonb_build_object('level', 'warning', 'code', 'withholding_amount_fixed',
            'detail', v_wh.withholding_code || ': ' || v_amount || ' → ' || v_expected);
          v_amount := v_expected;
          v_fixed := true;
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
      'role', coalesce(l.v->>'role', 'other'), 'new_account', v_source = 'new',
      'debit', case when l.v->>'side' = 'debit' then v_amount else 0 end,
      'credit', case when l.v->>'side' = 'credit' then v_amount else 0 end,
      'description', left(coalesce(l.v->>'description', ''), 200));
  end loop;

  -- Si el ERP ha corregido un impuesto o una retención, el tercero se ajusta para que cuadre (como en una factura:
  -- el tercero queda por base + cuota − retención). Solo con una única línea de tercero; si no, lo decide el usuario.
  if v_fixed and v_debit <> v_credit then
    select count(*), min(t.ord - 1) into v_n, v_idx
    from jsonb_array_elements(v_lines) with ordinality t(x, ord) where t.x->>'role' = 'partner';
    if v_n = 1 then
      v_side := case when (v_lines->v_idx->>'credit')::numeric > 0 then 'credit' else 'debit' end;
      v_old := (v_lines->v_idx->>v_side)::numeric;
      v_expected := v_old + case v_side when 'credit' then v_debit - v_credit else v_credit - v_debit end;
      if v_expected > 0 then
        v_lines := jsonb_set(v_lines, array[v_idx::text, v_side], to_jsonb(v_expected));
        if v_side = 'credit' then v_credit := v_debit; else v_debit := v_credit; end if;
        v_checks := v_checks || jsonb_build_object('level', 'info', 'code', 'partner_amount_fixed',
                                                   'detail', v_old || ' → ' || v_expected);
      end if;
    end if;
  end if;

  -- Reglas de retención (0033): un gasto que la lleva, sin ella; o retención de profesionales a una sociedad
  v_has_wh := exists (select 1 from jsonb_array_elements(v_lines) x
                      where x->>'account_no' like '4751%' and (x->>'credit')::numeric > 0);
  for v_rule in select distinct r.* from erp.withholding_rules r, jsonb_array_elements(v_lines) x
                where x->>'account_no' like r.account_prefix || '%' and (x->>'debit')::numeric > 0
                order by r.account_prefix loop
    if not v_has_wh then
      if v_p_wh is not null then
        v_checks := v_checks || jsonb_build_object('level', 'warning', 'code', 'partner_withholding_missing',
                                                   'detail', v_p_wh);
      elsif v_p_no is not null and v_p_legal = 'company' and v_rule.kind = 'professional' then
        null;   -- profesional que es una sociedad: correcto sin retención
      else
        v_checks := v_checks || jsonb_build_object('level', v_rule.check_level, 'code', 'withholding_missing',
                                                   'detail', v_rule.account_prefix || ' → ' || v_rule.default_code);
      end if;
    end if;
  end loop;
  if v_prof_wh and v_p_legal = 'company' then
    v_checks := v_checks || jsonb_build_object('level', 'warning', 'code', 'withholding_not_applicable',
                                               'detail', v_p_name);
  end if;

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
end $function$
;
