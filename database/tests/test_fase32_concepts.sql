-- =====================================================================
-- PRUEBAS FASE 32 · Conceptos: el glosario en la base de datos (migración 0038)
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'usuario@test.local');

-- Sin sesión (anon) no se ve: el glosario público lo da la web desde su propio fichero
set role anon;
do $$
begin
  perform 1 from erp.concepts;
  raise exception 'anon no debería leer erp.concepts';
exception when insufficient_privilege then
  raise notice 'OK  · sin sesión no se lee (la web lleva su copia)';
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset
do $$
declare v text;
begin
  assert (select count(*) from erp.concepts) = 54, 'los 54 términos del glosario (41 + 2 del inmovilizado, 0042, + 2 de los ajustes de cierre, 0044, + 3 del cierre II, 0048, + 2 de nóminas, 0050, + 2 de modelos, 0053, + 2 de practicar, 0055): ' || (select count(*) from erp.concepts);
  assert (select term from erp.concepts where key = 'controlledAccount') = 'Cuenta controlada';
  assert (select sap from erp.concepts where key = 'controlledAccount') = 'Reconciliation account';
  assert (select pgc from erp.concepts where key = 'inputTax') = '{472}';
  assert (select example from erp.concepts where key = 'doubleEntry') is null, 'sin ejemplo: null';
  raise notice 'OK  · 48 conceptos con su definición, BC, SAP y cuentas del PGC';

  -- Conceptos de una subcuenta
  select string_agg(key, ',' order by key) into v from erp.concepts_for_account('41000001');
  assert v = 'aging,controlledAccount,openItem,partner,thirdPartyReturn', v;
  assert (select key from erp.concepts_for_account('47500001') limit 1) = 'settlement', 'la 4750 gana a la 47x';
  assert (select count(*) from erp.concepts_for_account('62300001')) = 0, 'la 623 no tiene concepto (todavía)';
  raise notice 'OK  · la 41000001 → tercero, partida abierta, antigüedad y cuenta controlada';

  -- Cada comprobación del auditor, con su concepto
  assert not exists (select 1 from erp.audit_checks where concept is null), 'todas con concepto';
  assert (select c.term from erp.audit_checks a join erp.concepts c on c.key = a.concept where a.code = 'vat_input')
         = 'IVA / IGIC soportado (472)';
  raise notice 'OK  · cada comprobación enlaza con su concepto (472 → IVA / IGIC soportado)';

  -- Nadie lo modifica desde la web
  begin
    update erp.concepts set term = 'X' where key = 'debit';
    assert not found, 'sin permiso de escritura';
  exception when insufficient_privilege then null;
  end;
  assert (select term from erp.concepts where key = 'debit') = 'Debe';
  raise notice 'OK  · solo lectura';
end $$;

\echo '✔ FASE 32 OK · conceptos'
