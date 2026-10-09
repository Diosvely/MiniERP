-- =====================================================================
-- PRUEBAS FASE 20 · Tutor de asientos con IA (migración 0025)
-- Se comprueba lo que recibe la IA y cómo el ERP valida y corrige sus propuestas de asiento.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
-- ¿Hay una comprobación con este código?
create or replace function public.aviso(v jsonb, codigo text) returns text language sql as $$
  select c->>'level' from jsonb_array_elements(v->'checks') c where c->>'code' = codigo limit 1;
$$;
create or replace function public.linea(v jsonb, n int) returns jsonb language sql as $$
  select x from jsonb_array_elements(v->'lines') x where (x->>'line_no')::int = n;
$$;
grant execute on function public.falla(text, text), public.aviso(jsonb, text), public.linea(jsonb, int) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; can uuid; imp uuid; k jsonb; v jsonb;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Tutor Madrid SL', 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.create_partner(e, 'creditor', 'Abogada Ruiz', '12345678Z');

  -- ---------- Lo que recibe la IA ----------
  k := erp.entry_tutor_context(e);
  assert k->'company'->>'tax' = 'IVA' and (k->>'tax_setup')::boolean;
  assert jsonb_array_length(k->'chart_of_accounts') = (select count(*) from erp.coa_template where level >= 3), 'el PGC';
  assert exists (select 1 from jsonb_array_elements_text(k->'chart_of_accounts') a where a like '523 %'), 'con la 523';
  assert exists (select 1 from jsonb_array_elements(k->'tax_codes') t where t->>'tax_code' = 'VAT21' and (t->>'rate_pct')::numeric = 21),
         'los tipos vigentes';
  assert jsonb_array_length(k->'valuation_rules') = 23, 'las 23 NRV';
  assert jsonb_array_length(k->'withholdings') > 0, 'las retenciones';
  assert position('Abogada' in k::text) = 0 and position('Tutor Madrid' in k::text) = 0, 'ni terceros ni el nombre de la empresa';

  -- ---------- 1. Ordenador de 1.200 € + IVA, mitad por banco y mitad a 60 días ----------
  v := erp.validate_proposed_entry(e, '{"valuation_rule": "NRV2", "lines": [
    {"account": "217", "side": "debit",  "amount": 1200, "role": "base", "description": "Ordenador"},
    {"account": "472", "side": "debit",  "amount": 252,  "role": "tax", "tax_code": "VAT21", "tax_base": 1200},
    {"account": "572", "side": "credit", "amount": 726,  "role": "cash"},
    {"account": "523", "side": "credit", "amount": 726,  "role": "other"}]}');
  assert (v->>'ok')::boolean, 'asiento correcto';
  assert (v->>'debit')::numeric = 1452 and (v->>'credit')::numeric = 1452;
  assert public.linea(v, 1)->>'account_no' = '21700001' and (public.linea(v, 1)->>'new_account')::boolean, 'subcuenta nueva de la 217';
  assert public.linea(v, 2)->>'account_no' = (select input_account_no from erp.v_tax_setup where company_id = e and tax_code = 'VAT21'),
         'el IVA va a la cuenta configurada, no a la que diga la IA';
  assert public.linea(v, 4)->>'account_no' = '52300001';
  assert public.aviso(v, 'new_subaccount') = 'info' and public.aviso(v, 'fixed_asset_supplier') is null;

  -- ---------- 2. El IVA lo calcula el ERP ----------
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "217", "side": "debit",  "amount": 1200, "role": "base"},
    {"account": "472", "side": "debit",  "amount": 250,  "role": "tax", "tax_code": "VAT21", "tax_base": 1200},
    {"account": "523", "side": "credit", "amount": 1452}]}');
  assert public.aviso(v, 'tax_amount_fixed') = 'warning' and (public.linea(v, 2)->>'debit')::numeric = 252, 'cuota corregida';
  assert (v->>'ok')::boolean, 'y entonces cuadra';

  -- ---------- 3. Criterio: inmovilizado a un 400 ----------
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "217", "side": "debit", "amount": 100}, {"account": "400", "side": "credit", "amount": 100, "role": "partner"}]}');
  assert (v->>'ok')::boolean and public.aviso(v, 'fixed_asset_supplier') = 'warning', 'mejor la 523';

  -- ---------- 4. Tercero conocido y retención ----------
  v := erp.validate_proposed_entry(e, '{"partner_name": "abogada ruiz", "lines": [
    {"account": "623", "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "472", "side": "debit",  "amount": 210,  "role": "tax", "tax_code": "VAT21", "tax_base": 1000},
    {"account": "4751", "side": "credit", "amount": 150, "role": "withholding"},
    {"account": "410", "side": "credit", "amount": 1060, "role": "partner"}]}');
  assert (v->>'ok')::boolean and public.aviso(v, 'partner_found') = 'info';
  assert public.linea(v, 4)->>'account_no' = (select g.account_no from erp.business_partners p join erp.gl_accounts g on g.id = p.gl_account_id
                                              where p.company_id = e and p.name = 'Abogada Ruiz'), 'la subcuenta de la abogada';
  v := erp.validate_proposed_entry(e, '{"partner_name": "Informática Pérez", "lines": [
    {"account": "629", "side": "debit", "amount": 10}, {"account": "410", "side": "credit", "amount": 10, "role": "partner"}]}');
  assert public.aviso(v, 'partner_not_found') = 'warning';
  assert not exists (select 1 from erp.business_partners p join erp.gl_accounts g on g.id = p.gl_account_id
                     where g.account_no = public.linea(v, 2)->>'account_no'), 'nunca la subcuenta de otro tercero';

  -- ---------- 5. Dos líneas de la misma cuenta nueva: la misma subcuenta ----------
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "572", "side": "debit", "amount": 50}, {"account": "572", "side": "credit", "amount": 50}]}');
  assert public.linea(v, 1)->>'account_no' = public.linea(v, 2)->>'account_no';

  -- ---------- 6. Errores ----------
  v := erp.validate_proposed_entry(e, '{"valuation_rule": "NRV99", "lines": [
    {"account": "999", "side": "debit", "amount": 100}, {"account": "570", "side": "credit", "amount": 90},
    {"account": "629", "side": "debit", "amount": -5}, {"account": "629", "side": "izquierda", "amount": 5},
    {"account": "477", "side": "credit", "amount": 21, "role": "tax", "tax_code": "VAT99"}]}');
  assert not (v->>'ok')::boolean;
  assert public.aviso(v, 'unknown_account') = 'error' and public.aviso(v, 'bad_amount') = 'error'
     and public.aviso(v, 'bad_side') = 'error' and public.aviso(v, 'unknown_tax_code') = 'error'
     and public.aviso(v, 'unbalanced') = 'error' and public.aviso(v, 'unknown_valuation_rule') = 'warning';
  assert public.aviso(erp.validate_proposed_entry(e, '{"lines": [{"account": "570", "side": "debit", "amount": 1}]}'), 'too_few_lines') = 'error';

  -- ---------- 7. Canarias: IGIC, no IVA ----------
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Tutor Canarias SL', 'services', 'canary_islands', auth.uid()) returning id into can;
  perform erp.create_fiscal_year(can, 2026);
  perform erp.setup_taxes(can);
  assert erp.entry_tutor_context(can)->'company'->>'tax' = 'IGIC';
  assert not exists (select 1 from jsonb_array_elements(erp.entry_tutor_context(can)->'tax_codes') t where t->>'tax' = 'VAT');
  v := erp.validate_proposed_entry(can, '{"lines": [
    {"account": "629", "side": "debit", "amount": 100}, {"account": "472", "side": "debit", "amount": 21, "role": "tax", "tax_code": "VAT21", "tax_base": 100},
    {"account": "410", "side": "credit", "amount": 121}]}');
  assert public.aviso(v, 'unknown_tax_code') = 'error', 'el IVA no existe en Canarias';

  -- ---------- 8. Empresa sin impuestos configurados (como las importadas) ----------
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Importada SL', 'services', 'mainland', auth.uid()) returning id into imp;
  v := erp.validate_proposed_entry(imp, '{"lines": [
    {"account": "629", "side": "debit", "amount": 100}, {"account": "472", "side": "debit", "amount": 21, "role": "tax", "tax_code": "VAT21", "tax_base": 100},
    {"account": "410", "side": "credit", "amount": 121}]}');
  assert (v->>'ok')::boolean and public.aviso(v, 'no_tax_setup') = 'info' and public.linea(v, 2)->>'account_no' like '472%';


  -- ---------- 10. Reglas de criterio (0026): el asiento de la furgoneta que CUADRABA pero estaba mal ----------
  v := erp.validate_proposed_entry(e, '{"valuation_rule": "NRV2", "lines": [
    {"account": "218",  "side": "credit", "amount": 8000},
    {"account": "477",  "side": "credit", "amount": 1680, "role": "tax", "tax_code": "VAT21", "tax_base": 8000},
    {"account": "572",  "side": "debit",  "amount": 9680},
    {"account": "2813", "side": "credit", "amount": 15000},
    {"account": "671",  "side": "debit",  "amount": 7000},
    {"account": "218",  "side": "debit",  "amount": 8000}]}');
  assert (v->>'ok')::boolean, 'cuadra (por eso antes pasaba)';
  assert public.aviso(v, 'same_account_both_sides') = 'warning', '218 en el Debe y en el Haber';
  assert public.aviso(v, 'depreciation_mismatch') = 'warning', '2813 no es la amortización de la 218';
  assert public.aviso(v, 'disposal_depreciation_side') = 'warning', 'en la baja la amortización va al Debe';
  -- El asiento correcto no da ningún aviso de criterio
  v := erp.validate_proposed_entry(e, '{"valuation_rule": "NRV2", "lines": [
    {"account": "572",  "side": "debit",  "amount": 9680},
    {"account": "2818", "side": "debit",  "amount": 15000},
    {"account": "218",  "side": "credit", "amount": 20000},
    {"account": "477",  "side": "credit", "amount": 1680, "role": "tax", "tax_code": "VAT21", "tax_base": 8000},
    {"account": "771",  "side": "credit", "amount": 3000}]}');
  assert (v->>'ok')::boolean and not exists (select 1 from jsonb_array_elements(v->'checks') c
    where c->>'code' in ('same_account_both_sides', 'depreciation_mismatch', 'disposal_depreciation_side',
                         'asset_supplier_misuse', 'valuation_rule_mismatch')), 'baja correcta: sin avisos';
  -- La abogada con la 523 y la NRV 14ª
  v := erp.validate_proposed_entry(e, '{"valuation_rule": "NRV14", "lines": [
    {"account": "623", "side": "debit", "amount": 1000}, {"account": "472", "side": "debit", "amount": 210, "role": "tax", "tax_code": "VAT21", "tax_base": 1000},
    {"account": "4751", "side": "credit", "amount": 150}, {"account": "523", "side": "credit", "amount": 1060}]}');
  assert public.aviso(v, 'asset_supplier_misuse') = 'warning' and public.aviso(v, 'valuation_rule_mismatch') = 'warning';
  -- Sin NRV citada no se comprueba
  v := erp.validate_proposed_entry(e, '{"lines": [{"account": "623", "side": "debit", "amount": 10}, {"account": "410", "side": "credit", "amount": 10}]}');
  assert public.aviso(v, 'valuation_rule_mismatch') is null and public.aviso(v, 'asset_supplier_misuse') is null;

  -- ---------- 9. Seguridad ----------
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true);
  assert public.falla(format('select erp.entry_tutor_context(%L)', e), 'only available to the application owner');
  assert public.falla(format($q$select erp.validate_proposed_entry(%L, '{"lines": []}')$q$, e), 'not allowed');
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);
end $$;

\echo '=========== TODAS LAS PRUEBAS DE LA FASE 20 (TUTOR DE ASIENTOS) PASARON ==========='
