-- =====================================================================
-- PRUEBAS FASE 4 · terceros (migración 0009)
-- Ejecutar en una base limpia: stub + migraciones 0001-0009.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
  ('00000000-0000-0000-0000-0000000000b2', 'lector@test.local');

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

-- ---------- Validación de NIF / NIE / CIF ----------
do $$ begin
  assert erp.valid_spanish_tax_id('12345678Z');
  assert erp.valid_spanish_tax_id('12.345.678-z'), 'debe normalizar puntos, guiones y minúsculas';
  assert not erp.valid_spanish_tax_id('12345678A'), 'letra de NIF incorrecta';
  assert erp.valid_spanish_tax_id('X1234567L');
  assert not erp.valid_spanish_tax_id('X1234567A');
  assert erp.valid_spanish_tax_id('B12345674');
  assert not erp.valid_spanish_tax_id('B12345675');
  assert erp.valid_spanish_tax_id('Q2826000H'), 'CIF de organismo con control letra';
  assert not erp.valid_spanish_tax_id('Q28260008'), 'Q exige letra de control';
  raise notice 'OK  · validación de NIF, NIE y CIF (letra y dígito de control)';
end $$;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

do $$
declare e uuid; ej uuid; r record; a uuid; banco uuid;
begin
  insert into erp.companies (name, industry, tax_territory, created_by)
  values ('Agrícola del Sur', 'manufacturing', 'canary_islands', auth.uid()) returning id into e;
  insert into public.ctx values ('empresa', e);
  insert into erp.company_users (company_id, user_id, role) values (e, '00000000-0000-0000-0000-0000000000b2', 'viewer');
  ej := erp.create_fiscal_year(e, 2026);

  -- Subcuenta automática: la primera libre de cada cuenta colectiva
  select * into r from erp.create_partner(e, 'customer', 'Hotel Atlántico SL', 'B12345674');
  assert r.account_no = '43000001', format('esperaba 43000001, salió %s', r.account_no);
  select * into r from erp.create_partner(e, 'customer', 'Juan Pérez', '12345678Z');
  assert r.account_no = '43000002';
  select * into r from erp.create_partner(e, 'creditor', 'Gestoría Martín', 'X1234567L');
  assert r.account_no = '41000001';
  assert (select name from erp.gl_accounts where company_id = e and account_no = '43000002') = 'Juan Pérez';
  assert (select tax_territory from erp.business_partners where id = r.partner_id) = 'canary_islands',
         'por defecto, territorio de la empresa';
  raise notice 'OK  · alta con subcuenta automática: 43000001, 43000002, 41000001';

  -- Vincular una subcuenta que ya existía (ej. importada por CSV)
  perform erp.create_posting_account(e, '40000005', 'Proveedor 5');
  select * into r from erp.create_partner(e, 'vendor', 'Distribuciones Norte SA', null, 'mainland', '40000005');
  assert r.account_no = '40000005';
  assert (select name from erp.gl_accounts where company_id = e and account_no = '40000005') = 'Distribuciones Norte SA';
  select * into r from erp.create_partner(e, 'vendor', 'Siguiente proveedor');
  assert r.account_no = '40000006', 'la siguiente libre va después de la mayor existente';
  raise notice 'OK  · vincula una subcuenta existente y numera después de la mayor';

  -- Errores
  perform public.debe_fallar(format('select * from erp.create_partner(%L, %L, %L, %L)', e, 'customer', 'Otro', '12345678A'),
                             'Invalid Spanish tax ID', 'NIF con letra incorrecta');
  perform public.debe_fallar(format('select * from erp.create_partner(%L, %L, %L, %L)', e, 'customer', 'Duplicado', '12345678Z'),
                             'already exists', 'NIF duplicado en clientes');
  perform public.debe_fallar(format('select * from erp.create_partner(%L, %L, %L, %L, %L, %L)', e, 'vendor', 'X', null, null, '43000009'),
                             'must start with 400', 'subcuenta de otra cuenta colectiva');
  perform public.debe_fallar(format('select * from erp.create_partner(%L, %L, %L, %L, %L, %L)', e, 'vendor', 'X', null, null, '40000005'),
                             'already belongs', 'subcuenta ya asignada a otro tercero');
  -- El mismo NIF sí puede ser cliente y proveedor; un NIF extranjero no se valida
  select * into r from erp.create_partner(e, 'vendor', 'Juan Pérez', '12345678Z');
  select * into r from erp.create_partner(e, 'customer', 'Tourist GmbH', 'DE123456789', 'eu');
  raise notice 'OK  · mismo NIF como cliente y proveedor; NIF extranjero sin validar formato español';

  -- Renombrar el tercero renombra su subcuenta
  update erp.business_partners set name = 'Hotel Atlántico Resort SL' where vat_registration_no = 'B12345674';
  assert (select name from erp.gl_accounts where company_id = e and account_no = '43000001') = 'Hotel Atlántico Resort SL';
  raise notice 'OK  · renombrar el tercero renombra su subcuenta';

  -- Apuntes en la subcuenta quedan vinculados al tercero, y su saldo aparece en v_partners
  banco := erp.create_posting_account(e, '70000000', 'Ventas');
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, ej, '2026-03-01', 'Venta') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)
  values (a, (select id from erp.gl_accounts where company_id = e and account_no = '43000001'), 1070);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, banco, 1070);
  perform erp.post_entry(a);
  assert (select partner_id is not null from erp.journal_lines where entry_id = a and debit > 0), 'debe vincular el tercero';
  assert (select balance from erp.v_partners where account_no = '43000001' and company_id = e) = 1070;
  raise notice 'OK  · el apunte se vincula al tercero y su saldo sale en v_partners';
end $$;

-- ---------- Un usuario de solo lectura no puede dar de alta terceros ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  assert (select count(*) from erp.v_partners where company_id = e) = 7, 'el lector ve los terceros';
  perform public.debe_fallar(format('select * from erp.create_partner(%L, %L, %L)', e, 'customer', 'X'),
                             'No permission', 'un viewer no crea terceros');
end $$;

reset role;
drop table public.ctx;
drop function public.debe_fallar(text, text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 4 (TERCEROS) PASARON ==========='
