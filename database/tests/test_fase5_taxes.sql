-- =====================================================================
-- PRUEBAS FASE 5 · configuración de impuestos (migración 0010)
-- Ejecutar en una base limpia: stub + migraciones 0001-0010.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'contable@test.local'),
  ('00000000-0000-0000-0000-0000000000c3', 'ajeno@test.local');

create or replace function public.debe_fallar(p_sql text, p_texto text, p_prueba text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm ilike '%' || p_texto || '%' then
      raise notice 'OK  · %  →  %', p_prueba, sqlerrm;
      return;
    end if;
    raise exception 'FALLO · % · error inesperado: %', p_prueba, sqlerrm;
  end;
  raise exception 'FALLO · % · debía dar error y no lo dio', p_prueba;
end $$;
grant execute on function public.debe_fallar(text, text, text) to authenticated;
create table public.ctx (clave text primary key, valor uuid);
grant all on public.ctx to authenticated;
-- El admin de la prueba es owner (sin límite de empresas)
insert into erp.app_profiles (user_id, app_role, max_companies)
values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; p uuid; ej uuid; a uuid; n int; r record;
begin
  -- ---------- Empresa canaria: el asistente configura IGIC ----------
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Asesoría Canarias', 'services', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('canarias', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'accountant');
  ej := erp.create_fiscal_year(e, 2026);

  -- Una subcuenta que ya existía se reutiliza (no se duplica)
  perform erp.create_posting_account(e, '47210007', 'IGIC soportado general');

  select count(*) into n from erp.setup_taxes(e);
  assert (select count(*) from erp.tax_setup where company_id = e) = 11, 'los 8 tipos de IGIC vigentes + 3 sin cuota (0018)';
  assert (select input_account_no from erp.v_tax_setup where company_id = e and tax_code = 'IGIC7') = '47210007';
  assert (select name from erp.gl_accounts where company_id = e and account_no = '47210007') = 'IGIC soportado general',
         'la subcuenta existente conserva su nombre';
  assert (select output_account_no from erp.v_tax_setup where company_id = e and tax_code = 'IGIC7') = '47710007';
  assert (select input_account_no from erp.v_tax_setup where company_id = e and tax_code = 'IGIC9_5') = '47210095';
  assert (select name from erp.gl_accounts where company_id = e and account_no = '47710095') = 'IGIC repercutido 9,5%';
  assert (select name_en from erp.gl_accounts where company_id = e and account_no = '47710095') = 'Output IGIC 9.5%';
  assert (select input_account_id is null and output_account_id is null from erp.tax_setup
          where company_id = e and tax_code = 'IGIC0'), 'el tipo cero no lleva cuentas de cuota';
  assert (select payable_account_no || '/' || receivable_account_no from erp.v_tax_settlement_setup
          where company_id = e and tax_type = 'IGIC') = '47500002/47000002';
  raise notice 'OK  · asistente IGIC: 8 tipos, 4721xxxx / 4771xxxx, liquidación 47500002 / 47000002, reutiliza 47210007';

  -- Repetir el asistente no duplica nada
  select count(*) into n from erp.setup_taxes(e) s where s.status = 'existing';
  assert n = 12, format('esperaba 12 filas existing (11 tipos + liquidación), salen %s', n);
  assert (select count(*) from erp.gl_accounts where company_id = e and account_no like '47%' and account_type = 'posting') = 19,
         '7 tipos con cuota × 2 + 2 de liquidación + 4751 (111 y 115) y 473 (0018)';
  raise notice 'OK  · ejecutar el asistente otra vez no duplica';

  -- Una empresa canaria también puede añadir el IVA (ej. si opera en la Península)
  perform erp.setup_taxes(e, 'VAT');
  assert (select output_account_no from erp.v_tax_setup where company_id = e and tax_code = 'VAT21') = '47700021';
  assert exists (select 1 from erp.tax_settlement_setup where company_id = e and tax_type = 'VAT');
  raise notice 'OK  · se puede añadir el IVA a una empresa canaria';

  -- ---------- Reglas contables de la configuración ----------
  perform public.debe_fallar(format(
    'update erp.tax_setup set input_account_id = (select id from erp.gl_accounts where company_id = %L and account_no = %L) where company_id = %L and tax_code = %L',
    e, '47710007', e, 'IGIC7'), 'must start with 472', 'soportado en una cuenta 477');
  perform public.debe_fallar(format(
    'update erp.tax_setup set output_account_id = (select id from erp.gl_accounts where company_id = %L and account_no = %L) where company_id = %L and tax_code = %L',
    e, '477', e, 'IGIC7'), 'must be a posting account', 'cuenta de título');
  perform public.debe_fallar(format(
    'update erp.tax_setup set output_account_id = null where company_id = %L and tax_code = %L', e, 'IGIC7'),
    'needs an input', 'tipo con cuota sin cuenta');
  perform public.debe_fallar(format(
    'update erp.tax_settlement_setup set payable_account_id = receivable_account_id where company_id = %L', e),
    'must start with 4750', 'liquidación a pagar en una 4700');
  -- Bloquear un tipo que no se usa sí permite dejarlo sin cuentas
  update erp.tax_setup set blocked = true, input_account_id = null, output_account_id = null
  where company_id = e and tax_code = 'IGIC20';

  -- Cuenta de otra empresa
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Tienda Península', 'retail', 'mainland', auth.uid()) returning id into p;
  insert into public.ctx values ('peninsula', p);
  select count(*) into n from erp.setup_taxes(p);
  assert (select count(*) from erp.tax_setup where company_id = p) = 8, 'IVA: 21, 10, 4 y 0 + 4 sin cuota (0018)';
  assert (select input_account_no from erp.v_tax_setup where company_id = p and tax_code = 'VAT4') = '47200004';
  perform public.debe_fallar(format(
    'update erp.tax_setup set input_account_id = (select id from erp.gl_accounts where company_id = %L and account_no = %L) where company_id = %L and tax_code = %L',
    p, '47200021', e, 'VAT21'), 'does not belong', 'cuenta de otra empresa');
  raise notice 'OK  · empresa peninsular: 4 tipos de IVA, 47200004 / 47700004…';

  -- ---------- El apunte en una cuenta de impuesto toma su tipo ----------
  perform erp.create_posting_account(e, '70500001', 'Servicios');
  perform erp.create_posting_account(e, '43000001', 'Cliente');
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (e, ej, '2026-03-01', 'Factura', 'F-1') returning id into a;
  insert into erp.journal_lines (entry_id, line_no, gl_account_id, debit, credit) values
    (a, 1, (select id from erp.gl_accounts where company_id = e and account_no = '43000001'), 1070, 0),
    (a, 2, (select id from erp.gl_accounts where company_id = e and account_no = '70500001'), 0, 1000),
    (a, 3, (select id from erp.gl_accounts where company_id = e and account_no = '47710007'), 0, 70);
  assert (select tax_code from erp.journal_lines where entry_id = a and line_no = 3) = 'IGIC7';
  assert (select tax_code from erp.journal_lines where entry_id = a and line_no = 2) is null;
  perform erp.post_entry(a);
  assert (select tax_class || ' ' || tax_amount from erp.v_tax_book where company_id = e) = 'output 70.00';
  raise notice 'OK  · el apunte en 47710007 toma el tipo IGIC7 y sale en el libro registro';
end $$;

-- ---------- Un contable (no admin) consulta pero no configura ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'canarias');
begin
  assert (select count(*) from erp.v_tax_setup where company_id = e) = 19, 'el contable ve la configuración (11 IGIC + 8 IVA)';
  perform public.debe_fallar(format('select * from erp.setup_taxes(%L)', e), 'Only the company admin', 'el contable no ejecuta el asistente');
  update erp.tax_setup set blocked = true where company_id = e;   -- RLS: no actualiza nada
  assert (select count(*) from erp.tax_setup where company_id = e and blocked) = 1, 'el contable no modifica la configuración';
  raise notice 'OK  · el contable consulta pero no configura';
end $$;

-- ---------- Un usuario ajeno a la empresa tampoco ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'canarias');
begin
  perform public.debe_fallar(format('select * from erp.setup_taxes(%L)', e), 'Only the company admin', 'un usuario ajeno no ejecuta el asistente');
  perform public.debe_fallar(format('select * from erp.create_partner(%L, %L, %L)', e, 'customer', 'X'),
                             'No permission', 'un usuario ajeno no crea terceros');
end $$;

-- ---------- Borrar la empresa borra su configuración ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'peninsula');
begin
  perform erp.delete_company(e);
  assert not exists (select 1 from erp.tax_setup where company_id = e);
  raise notice 'OK  · borrar la empresa borra su configuración de impuestos';
end $$;

reset role;
drop table public.ctx;
drop function public.debe_fallar(text, text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 5 (IMPUESTOS) PASARON ==========='
