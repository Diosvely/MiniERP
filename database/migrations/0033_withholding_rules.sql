-- =====================================================================
-- 0033 · RETENCIONES GUIADAS POR REGLAS (v0.31.0 · IA guiada por reglas, fase 1)
-- ---------------------------------------------------------------------
-- Al probar el tutor con "factura de una abogada autónoma por 1.000 € en Canarias", la IA nunca practicaba la
-- retención del 15 %. El IVA / IGIC sí lo acertaba, porque el ERP le da los tipos de la empresa y recalcula la cuota.
-- Con las retenciones no había ni regla ni recálculo: quedaban a criterio del modelo.
--
-- Principio (ver ideas-pendientes.md): LA IA CLASIFICA, LA BASE DE DATOS CONTABILIZA.
--
-- 1) La FICHA DEL TERCERO manda, como el maestro del acreedor en SAP (tipo de retención) o la ficha del proveedor
--    en la localización española de Business Central:
--      legal_form        persona física (individual) o entidad (company). Si no se indica, sale del NIF:
--                        NIF / NIE → persona física · CIF → entidad.
--      withholding_code  retención que se le practica por defecto (IRPF15, IRPF7, IRPF19). Solo proveedores y
--                        acreedores; la de profesionales, solo a personas físicas.
--
-- 2) REGLAS DE RETENCIÓN como datos (erp.withholding_rules): qué gastos llevan retención y cuándo.
--      623 Servicios de profesionales independientes → IRPF15 (7 % en inicio de actividad) si es persona física
--      621 Arrendamientos                              → IRPF19 si es un local o inmueble urbano
--    Una regla nueva es una fila nueva, no código nuevo. La IA las recibe en su contexto y el ERP las comprueba.
--
-- 3) EL ERP CALCULA LA RETENCIÓN en las propuestas del tutor (erp.validate_proposed_entry), como ya hacía con el IVA:
--      · el código: el de la ficha del tercero; si no, el de la línea; si no, el de la regla del gasto
--      · la cuenta: la 4751 / 473 configurada · el importe: base × tipo (la base: la de la línea o la del gasto)
--      · si el ERP corrige un importe, ajusta la línea del tercero para que el asiento cuadre: 1.000 + 70 − 150 = 920
--    Y avisa:
--      withholding_missing          gasto con retención (623…) sin retención y sin saber si es persona física
--      partner_withholding_missing  la ficha del tercero tiene retención y el asiento no la lleva
--      withholding_not_applicable   retención de profesionales a una entidad (una SL no lleva IRPF)
--      withholding_code_fixed       el código de la línea no es el de la ficha del tercero
--      withholding_amount_fixed     el importe no era base × tipo
--      partner_amount_fixed         el ERP ha ajustado el importe del tercero tras corregir impuestos o retenciones
-- Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Ficha del tercero
-- ---------------------------------------------------------------------
alter table erp.business_partners
  add column if not exists legal_form       text check (legal_form in ('individual', 'company')),
  add column if not exists withholding_code text references erp.withholding_codes(code);

comment on column erp.business_partners.legal_form is
  'individual = natural person (NIF / NIE), company = legal entity (CIF). Derived from the tax ID when empty.';
comment on column erp.business_partners.withholding_code is
  'IRPF withholding applied by default to this vendor / creditor (like the withholding tax type of the SAP vendor master).';

-- Forma jurídica que se deduce del NIF: 12345678Z / X1234567L → persona física · B12345674 → entidad
create or replace function erp.legal_form_from_tax_id(p text)
returns text language sql immutable as $$
  select case
    when erp.normalize_tax_id(p) ~ '^([0-9]{8}|[KLMXYZ][0-9]{7})[A-Z]$' then 'individual'
    when erp.normalize_tax_id(p) ~ '^[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]$' then 'company'
  end;
$$;

create or replace function erp.tg_partner_withholding_validate()
returns trigger language plpgsql as $$
begin
  -- Se ejecuta después de partner_validate (orden alfabético), con el NIF ya normalizado
  if new.legal_form is null and new.tax_territory in ('mainland', 'canary_islands', 'ceuta_melilla') then
    new.legal_form := erp.legal_form_from_tax_id(new.vat_registration_no);
  end if;
  if new.withholding_code is not null then
    if new.partner_type not in ('vendor', 'creditor') then
      raise exception 'Withholding only applies to vendors and creditors';
    end if;
    if new.legal_form = 'company'
       and (select kind from erp.withholding_codes where code = new.withholding_code) = 'professional' then
      raise exception 'Professional withholding (IRPF) does not apply to companies';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists partner_withholding_validate on erp.business_partners;
create trigger partner_withholding_validate
  before insert or update on erp.business_partners
  for each row execute function erp.tg_partner_withholding_validate();

-- La vista de la web, con los dos datos nuevos al final (una vista solo admite columnas nuevas al final)
create or replace view erp.v_partners with (security_invoker = true) as
select bp.id, bp.company_id, bp.partner_type, bp.vat_registration_no, bp.name, bp.tax_territory,
       bp.email, bp.blocked, bp.created_at,
       g.account_no,
       coalesce((select sum(l.debit - l.credit)
                 from erp.journal_lines l
                 join erp.journal_entries e on e.id = l.entry_id
                 where l.gl_account_id = bp.gl_account_id and e.status = 'posted'), 0) as balance,
       bp.equivalence_surcharge,
       bp.legal_form,
       bp.withholding_code
from erp.business_partners bp
left join erp.gl_accounts g on g.id = bp.gl_account_id;

-- Los terceros que ya existen: forma jurídica a partir de su NIF
update erp.business_partners
set legal_form = erp.legal_form_from_tax_id(vat_registration_no)
where legal_form is null and erp.legal_form_from_tax_id(vat_registration_no) is not null;

-- ---------------------------------------------------------------------
-- 2) Reglas de retención (catálogo común, como los tipos de impuesto)
-- ---------------------------------------------------------------------
create table if not exists erp.withholding_rules (
  account_prefix  text primary key,                       -- cuenta de gasto del PGC: 623, 621…
  kind            text not null check (kind in ('professional', 'rent')),
  default_code    text not null references erp.withholding_codes(code),
  check_level     text not null check (check_level in ('warning', 'info')),   -- warning: la IA lo revisa
  rule            text not null,
  rule_en         text not null,
  legal_reference text not null
);
comment on table erp.withholding_rules is
  'Which expenses carry IRPF withholding and when. Data, not code: the AI tutor receives them and the ERP checks them.';

insert into erp.withholding_rules (account_prefix, kind, default_code, check_level, rule, rule_en, legal_reference) values
('623', 'professional', 'IRPF15', 'warning',
 'Servicios de profesionales independientes (abogados, asesores, arquitectos, notarios…). Si el profesional es persona física (autónomo): retención del 15 % sobre la base (IRPF7, el 7 %, en su año de alta y los dos siguientes). Si es una sociedad (SL, SA…): sin retención.',
 'Independent professional services (lawyers, advisers, architects, notaries…). If the professional is a natural person (self-employed): 15 % withholding on the taxable base (IRPF7, 7 %, in their first year of activity and the next two). If it is a company (SL, SA…): no withholding.',
 'Art. 101.5 Ley IRPF · art. 95.1 Reglamento IRPF'),
('621', 'rent', 'IRPF19', 'info',
 'Alquiler de locales e inmuebles urbanos: retención del 19 % sobre la base, sea el arrendador persona física o sociedad (salvo las excepciones del reglamento). El alquiler de maquinaria, vehículos o equipos NO lleva retención.',
 'Rent of urban premises: 19 % withholding on the taxable base, whether the landlord is a person or a company (except the cases in the regulation). Renting machinery, vehicles or equipment has NO withholding.',
 'Art. 100 y 75.3 Reglamento IRPF')
on conflict (account_prefix) do update set
  kind = excluded.kind, default_code = excluded.default_code, check_level = excluded.check_level,
  rule = excluded.rule, rule_en = excluded.rule_en, legal_reference = excluded.legal_reference;

alter table erp.withholding_rules enable row level security;
drop policy if exists read on erp.withholding_rules;
create policy read on erp.withholding_rules for select to authenticated using (true);
revoke all on erp.withholding_rules from anon, public;
grant select on erp.withholding_rules to authenticated;

-- ---------------------------------------------------------------------
-- 3) Contexto del tutor: el de la 0027 + el tipo de cada retención y las reglas
-- ---------------------------------------------------------------------
create or replace function erp.entry_tutor_context(p_company uuid, p_language text default 'es')
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
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
end $$;

-- ---------------------------------------------------------------------
-- 4) Comprobación de la propuesta: la de la 0026 + retenciones calculadas por el ERP
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
end $$;

revoke execute on function erp.legal_form_from_tax_id(text), erp.tg_partner_withholding_validate() from anon, public;
grant execute on function erp.legal_form_from_tax_id(text) to authenticated;
