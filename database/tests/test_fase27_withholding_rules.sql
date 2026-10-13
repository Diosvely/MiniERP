-- =====================================================================
-- PRUEBAS FASE 27 · Retenciones guiadas por reglas (migración 0033)
-- El caso que lo originó: "factura de una abogada autónoma por 1.000 € en Canarias".
-- Asiento correcto: 623 1.000 + 472 IGIC 7 % 70 = 4751 retención 15 % 150 + 410 abogada 920.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local');
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
create or replace function public.aviso(v jsonb, codigo text) returns text language sql as $$
  select c->>'level' from jsonb_array_elements(v->'checks') c where c->>'code' = codigo limit 1;
$$;
create or replace function public.detalle(v jsonb, codigo text) returns text language sql as $$
  select c->>'detail' from jsonb_array_elements(v->'checks') c where c->>'code' = codigo limit 1;
$$;
create or replace function public.linea(v jsonb, n int) returns jsonb language sql as $$
  select x from jsonb_array_elements(v->'lines') x where (x->>'line_no')::int = n;
$$;
grant execute on function public.falla(text, text), public.aviso(jsonb, text), public.detalle(jsonb, text),
  public.linea(jsonb, int) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; k jsonb; v jsonb; abogada uuid; bufete uuid; casero uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Retenciones Canarias SL', 'services', 'canary_islands', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  select partner_id into abogada from erp.create_partner(e, 'creditor', 'Abogada Pérez', '12345678Z');
  select partner_id into bufete  from erp.create_partner(e, 'creditor', 'Bufete Legal SL', 'B12345674');
  select partner_id into casero  from erp.create_partner(e, 'creditor', 'Casero Martín', 'X1234567L');

  -- ---------- 1. La forma jurídica sale del NIF ----------
  assert (select legal_form from erp.business_partners where id = abogada) = 'individual', 'NIF → persona física';
  assert (select legal_form from erp.business_partners where id = bufete) = 'company', 'CIF → entidad';
  assert (select legal_form from erp.business_partners where id = casero) = 'individual', 'NIE → persona física';
  raise notice 'OK  · forma jurídica a partir del NIF / NIE / CIF';

  -- ---------- 2. La ficha: qué retención admite cada tercero ----------
  assert public.falla(format('update erp.business_partners set withholding_code = %L where id = %L', 'IRPF15', bufete),
                      'does not apply to companies'), 'una SL no lleva retención de profesionales';
  update erp.business_partners set withholding_code = 'IRPF19' where id = bufete;   -- alquiler: sí, aunque sea una SL
  update erp.business_partners set withholding_code = null where id = bufete;
  perform erp.create_partner(e, 'customer', 'Cliente Gómez', '87654321X');
  assert public.falla(format('update erp.business_partners set withholding_code = %L where company_id = %L and name = %L',
                             'IRPF15', e, 'Cliente Gómez'), 'only applies to vendors and creditors'), 'un cliente no';
  raise notice 'OK  · la ficha solo admite retenciones que tienen sentido';

  -- ---------- 3. Lo que recibe la IA: las reglas salen de la base de datos ----------
  k := erp.entry_tutor_context(e);
  assert k->'company'->>'tax' = 'IGIC';
  assert exists (select 1 from jsonb_array_elements(k->'withholding_rules') r
                 where r->>'expense_account' = '623' and r->>'default_code' = 'IRPF15' and r->>'rule' like '%persona física%'),
         'la regla de los profesionales';
  assert exists (select 1 from jsonb_array_elements(k->'withholdings') w where w->>'code' = 'IRPF15' and w->>'kind' = 'professional'),
         'el tipo de cada retención';
  assert position('Abogada' in k::text) = 0, 'sin terceros';
  raise notice 'OK  · el tutor recibe las reglas de retención';

  -- ---------- 4. El caso real: la IA no pone la retención ----------
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "623", "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "472", "side": "debit",  "amount": 70,   "role": "tax", "tax_code": "IGIC7", "tax_base": 1000},
    {"account": "410", "side": "credit", "amount": 1070, "role": "partner"}]}');
  assert public.aviso(v, 'withholding_missing') = 'warning' and public.detalle(v, 'withholding_missing') = '623 → IRPF15',
         'avisa: 623 sin retención';
  raise notice 'OK  · 623 sin retención → aviso (la IA hace la segunda vuelta)';

  -- ---------- 5. La IA pone la retención mal: el ERP la calcula y ajusta al tercero ----------
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "623",  "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "472",  "side": "debit",  "amount": 70,   "role": "tax", "tax_code": "IGIC7", "tax_base": 1000},
    {"account": "4751", "side": "credit", "amount": 100,  "role": "withholding"},
    {"account": "410",  "side": "credit", "amount": 970,  "role": "partner"}]}');
  assert (v->>'ok')::boolean, 'cuadra tras corregir';
  assert (public.linea(v, 3)->>'credit')::numeric = 150, 'retención 15 % de 1.000';
  assert public.linea(v, 3)->>'account_no' = (select payable_account_no from erp.v_withholding_setup
                                              where company_id = e and withholding_code = 'IRPF15'), 'su cuenta 4751';
  assert (public.linea(v, 4)->>'credit')::numeric = 920, 'la abogada queda por 920';
  assert public.aviso(v, 'withholding_amount_fixed') = 'warning' and public.aviso(v, 'partner_amount_fixed') = 'info';
  assert public.aviso(v, 'withholding_missing') is null;
  assert (v->>'debit')::numeric = 1070 and (v->>'credit')::numeric = 1070;
  raise notice 'OK  · 1.000 + 70 − 150 = 920, calculado por el ERP';

  -- ---------- 6. La ficha manda ----------
  update erp.business_partners set withholding_code = 'IRPF15' where id = abogada;
  v := erp.validate_proposed_entry(e, '{"partner_name": "Abogada Pérez", "lines": [
    {"account": "623", "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "472", "side": "debit",  "amount": 70,   "role": "tax", "tax_code": "IGIC7", "tax_base": 1000},
    {"account": "410", "side": "credit", "amount": 1070, "role": "partner"}]}');
  assert public.aviso(v, 'partner_withholding_missing') = 'warning' and public.detalle(v, 'partner_withholding_missing') = 'IRPF15',
         'la ficha dice IRPF15 y el asiento no la lleva';
  v := erp.validate_proposed_entry(e, '{"partner_name": "Abogada Pérez", "lines": [
    {"account": "623",  "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "472",  "side": "debit",  "amount": 70,   "role": "tax", "tax_code": "IGIC7", "tax_base": 1000},
    {"account": "4751", "side": "credit", "amount": 70,   "role": "withholding", "withholding_code": "IRPF7", "tax_base": 1000},
    {"account": "410",  "side": "credit", "amount": 1000, "role": "partner"}]}');
  assert public.aviso(v, 'withholding_code_fixed') = 'warning' and public.detalle(v, 'withholding_code_fixed') = 'IRPF7 → IRPF15';
  assert (public.linea(v, 3)->>'credit')::numeric = 150 and (public.linea(v, 4)->>'credit')::numeric = 920;
  assert public.linea(v, 4)->>'account_no' = (select g.account_no from erp.business_partners p join erp.gl_accounts g on g.id = p.gl_account_id
                                              where p.id = abogada), 'la subcuenta de la abogada';
  assert (v->>'ok')::boolean;
  raise notice 'OK  · la retención de la ficha del tercero manda sobre la de la IA';

  -- ---------- 7. Una sociedad no lleva retención de profesionales ----------
  v := erp.validate_proposed_entry(e, '{"partner_name": "Bufete Legal SL", "lines": [
    {"account": "623", "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "472", "side": "debit",  "amount": 70,   "role": "tax", "tax_code": "IGIC7", "tax_base": 1000},
    {"account": "410", "side": "credit", "amount": 1070, "role": "partner"}]}');
  assert public.aviso(v, 'withholding_missing') is null and (v->>'ok')::boolean, 'una SL sin retención está bien';
  v := erp.validate_proposed_entry(e, '{"partner_name": "Bufete Legal SL", "lines": [
    {"account": "623",  "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "472",  "side": "debit",  "amount": 70,   "role": "tax", "tax_code": "IGIC7", "tax_base": 1000},
    {"account": "4751", "side": "credit", "amount": 150,  "role": "withholding", "withholding_code": "IRPF15"},
    {"account": "410",  "side": "credit", "amount": 920,  "role": "partner"}]}');
  assert public.aviso(v, 'withholding_not_applicable') = 'warning', 'retención de profesionales a una SL';
  raise notice 'OK  · sociedad: sin retención de profesionales';

  -- ---------- 8. Alquiler: solo un recordatorio (un renting de una furgoneta no lleva retención) ----------
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "621", "side": "debit",  "amount": 800, "role": "base"},
    {"account": "410", "side": "credit", "amount": 800, "role": "partner"}]}');
  assert public.aviso(v, 'withholding_missing') = 'info' and public.detalle(v, 'withholding_missing') = '621 → IRPF19';
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "629", "side": "debit",  "amount": 50, "role": "base"},
    {"account": "572", "side": "credit", "amount": 50, "role": "cash"}]}');
  assert public.aviso(v, 'withholding_missing') is null, 'otros gastos: nada';
  raise notice 'OK  · alquiler → recordatorio; otros gastos → nada';

  -- ---------- 9. Al corregir el impuesto también se ajusta el tercero ----------
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "629", "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "472", "side": "debit",  "amount": 60,   "role": "tax", "tax_code": "IGIC7", "tax_base": 1000},
    {"account": "410", "side": "credit", "amount": 1060, "role": "partner"}]}');
  assert (public.linea(v, 2)->>'debit')::numeric = 70 and (public.linea(v, 3)->>'credit')::numeric = 1070 and (v->>'ok')::boolean;
  -- …pero si hay dos líneas de tercero, no se adivina cuál: descuadre y segunda vuelta
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "629", "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "472", "side": "debit",  "amount": 60,   "role": "tax", "tax_code": "IGIC7", "tax_base": 1000},
    {"account": "410", "side": "credit", "amount": 530,  "role": "partner"},
    {"account": "410", "side": "credit", "amount": 530,  "role": "partner"}]}');
  assert public.aviso(v, 'unbalanced') = 'error' and public.aviso(v, 'partner_amount_fixed') is null;
  -- …y si el ERP no ha corregido nada, un descuadre de la IA no se tapa
  v := erp.validate_proposed_entry(e, '{"lines": [
    {"account": "629", "side": "debit",  "amount": 1000, "role": "base"},
    {"account": "410", "side": "credit", "amount": 900,  "role": "partner"}]}');
  assert public.aviso(v, 'unbalanced') = 'error' and public.aviso(v, 'partner_amount_fixed') is null;
  raise notice 'OK  · el tercero se ajusta solo cuando el ERP corrige un importe y no hay duda de cuál es';
end $$;

-- Las reglas se leen con sesión; sin sesión, no
reset role;
do $$ begin
  begin
    set local role anon;
    perform 1 from erp.withholding_rules;
    raise exception 'FALLO: anon lee las reglas';
  exception when insufficient_privilege then
    raise notice 'OK  · anon no lee las reglas de retención';
  end;
end $$;

\echo '✔ FASE 27 OK · retenciones guiadas por reglas'
