-- =====================================================================
-- PRUEBAS FASE 83 · Revisión ética: ningún texto de la base de datos nombra un programa comercial (v0.60.1 · 0090)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (diseno-v0.60.1.md, 08-11-2026). Se comprueba:
--   · ningún concepto (erp.concepts), ficha del PGC (erp.pgc_cards) ni comprobación del auditor (erp.audit_checks)
--     nombra un programa contable comercial (lista de mini-erp/docs/revision-etica.md);
--   · el concepto «Modo estricto o guiado» explica los modos por lo que hacen (antes / después);
--   · el ejemplo de la cuenta 112 es el inventado y cuadra (debe = haber; reserva legal = 10 % del beneficio).
-- Regresión (regla A1): si se vuelve a poner «ContaSol» en una ficha, la prueba falla (se comprueba abajo).
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

create or replace function public.nombres_comerciales() returns int language sql as $$
  with t(txt) as (
    select concat_ws(' ', term, definition, example, term_en, definition_en, example_en) from erp.concepts
    union all
    select concat_ws(' ', usage, debits::text, credits::text, balance, example_text, example_lines::text, warning) from erp.pgc_cards
    union all
    select concat_ws(' ', a::text) from erp.audit_checks a
  )
  select count(*)::int from t
  where txt ~* '\m(contasol|sage|a3|a3eco|contaplus|versat|delsol)\M' or txt ~* 'erp(s)? español(es)?|spanish erps?'
$$;

-- ---------- 1. Ningún nombre comercial ----------
do $$
begin
  assert public.nombres_comerciales() = 0, 'hay textos de la base de datos con nombres de programas comerciales';
  raise notice 'OK  · conceptos, fichas del PGC y comprobaciones sin nombres de programas comerciales';
end $$;

-- ---------- 2. Los modos de control, por lo que hacen ----------
do $$
declare d text := (select definition from erp.concepts where key = 'controlMode');
begin
  assert d ilike '%antes de contabilizar%' and d ilike '%control posterior%', 'el modo estricto o guiado se explica por lo que hace';
  assert d not ilike '%como SAP%' and d not ilike '%como los%', 'sin «como SAP» ni «como los ERP…»';
  raise notice 'OK  · «Modo estricto o guiado»: control antes o después';
end $$;

-- ---------- 3. Ejemplo de la cuenta 112 ----------
do $$
declare l jsonb := (select example_lines from erp.pgc_cards where code = '112');
  debe numeric; haber numeric;
begin
  select sum((x->>'debe')::numeric), sum((x->>'haber')::numeric) into debe, haber from jsonb_array_elements(l) x;
  assert debe = 80000 and haber = 80000, 'el ejemplo de la 112 cuadra (80.000 = 80.000)';
  assert (select (x->>'haber')::numeric from jsonb_array_elements(l) x where x->>'subcuenta' = '11200000') = 8000,
    'reserva legal = 10 % del beneficio';
  raise notice 'OK  · ficha 112: ejemplo inventado que cuadra (10 %% a reserva legal)';
end $$;

-- ---------- 4. Regresión: un nombre comercial se detecta ----------
do $$
begin
  update erp.pgc_cards set warning = 'Como en ContaSol.' where code = '112';
  assert public.nombres_comerciales() = 1, 'la prueba detecta un nombre comercial';
  raise exception 'deshacer' using errcode = 'P0001';
exception when sqlstate 'P0001' then
  raise notice 'OK  · regresión: si vuelve un nombre comercial, la prueba falla';
end $$;
do $$ begin assert public.nombres_comerciales() = 0, 'la regresión no deja rastro'; end $$;
