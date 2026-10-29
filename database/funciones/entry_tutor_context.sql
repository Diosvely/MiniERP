-- =====================================================================
-- erp.entry_tutor_context · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0025_entry_tutor 0027_members 0033_withholding_rules   →   la vigente es la de 0033_withholding_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.entry_tutor_context(p_company uuid, p_language text DEFAULT 'es'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare
  en boolean := p_language = 'en';
  c  erp.companies;
begin
  if not erp.ai_allowed(p_company) then raise exception 'The AI tutor is not enabled for you in this company'; end if;
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
                       'code', w.withholding_code, 'kind', w.kind, 'rate_pct', w.rate_pct, 'form', w.form,
                       'description', case when en then coalesce(w.description_en, w.description) else w.description end,
                       'payable_account', w.payable_account_no, 'receivable_account', w.receivable_account_no)
                       order by w.withholding_code)
                     from erp.v_withholding_setup w where w.company_id = p_company and not w.blocked),
    -- Cuándo hay retención: reglas de la base de datos, no del texto de las instrucciones
    'withholding_rules', (select jsonb_agg(jsonb_build_object(
                            'expense_account', r.account_prefix, 'kind', r.kind, 'default_code', r.default_code,
                            'rule', case when en then r.rule_en else r.rule end, 'reference', r.legal_reference)
                            order by r.account_prefix)
                          from erp.withholding_rules r),
    'valuation_rules', (select jsonb_agg(jsonb_build_object('code', r.code,
                          'title', case when en then r.title_en else r.title end) order by r.sort)
                        from erp.valuation_rules r));
end $function$
;
