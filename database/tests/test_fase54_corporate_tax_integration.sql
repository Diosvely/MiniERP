-- =====================================================================
-- PRUEBAS FASE 54 · Impuesto sobre Sociedades integrado (migración 0059 · v0.41.0)
-- ---------------------------------------------------------------------
--   · Cierre: sin el impuesto contabilizado, la vista previa avisa (guiado) o no deja cerrar (estricto); el asistente
--     tiene el paso 10 «Impuesto sobre Sociedades» y el cierre pasa al 11; después, la 473 tiene que quedar a cero.
--   · Invariante 10: 630 de la contabilidad = gasto de la declaración. Con la regularización:
--     la 129 = resultado antes de impuestos − (6300 + 6301). Supuesto: beneficio 40.000, pagos a cuenta 3.000,
--     tipo general 25 % → 6300 10.000 / 473 3.000 · 4752 7.000; la 129 = 40.000 − 10.000 = 30.000.
--   · Cuentas controladas: 630 y 474 (en estricto, un asiento manual a la 630 no se contabiliza).
--   · Conceptos de los ajustes sin importes con punto decimal; glosario, fuente y los dos supuestos nuevos.
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
create or replace function public.empresa(nombre text) returns uuid language plpgsql as $$
declare e uuid; c text;
begin
  insert into erp.companies (name, industry, tax_territory, created_by) values (nombre, 'services', 'mainland', auth.uid()) returning id into e;
  perform erp.create_fiscal_year(e, 2026); perform erp.create_fiscal_year(e, 2027);
  perform erp.setup_taxes(e);
  foreach c in array array['57200001:Banco', '70500001:Prestación de servicios', '62900001:Otros servicios',
                           '47300001:HP retenciones y pagos a cuenta', '21300001:Maquinaria', '63000001:Impuesto corriente',
                           '47520001:HP acreedora por IS'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  return e;
end $$;
create or replace function public.manual(e uuid, d date, l jsonb) returns void language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = extract(year from d)), d, 'Supuesto') returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit)
  select a, e, x.ord, (select id from erp.gl_accounts where company_id = e and account_no = x.v->>0), (x.v->>1)::numeric, (x.v->>2)::numeric
  from jsonb_array_elements(l) with ordinality as x(v, ord);
  perform erp.post_entry(a);
  execute 'set constraints all immediate';   -- la regla de las cuentas controladas es diferida: se comprueba aquí
  execute 'set constraints all deferred';
end $$;
create or replace function public.chk(e uuid, y int, c text) returns text language sql as $$
  select x->>'severity' from jsonb_array_elements(erp.year_closing_preview(e, y)->'checks') x where x->>'code' = c;
$$;
create or replace function public.saldo(e uuid, y int, cta text) returns numeric language sql as $$
  select coalesce(sum(l.credit - l.debit), 0) from erp.journal_lines l join erp.journal_entries j on j.id = l.entry_id
  join erp.gl_accounts g on g.id = l.gl_account_id join erp.fiscal_years f on f.id = j.fiscal_year_id
  where j.company_id = e and f.year = y and j.status = 'posted' and g.account_no like cta || '%' and j.entry_type <> 'closing';
$$;
create or replace function public.resp(t text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('account_no', p[1], 'debit', case p[2] when 'D' then p[3]::numeric else 0 end,
                                      'credit', case p[2] when 'H' then p[3]::numeric else 0 end) order by ord)
  from unnest(string_to_array(t, ' | ')) with ordinality u(x, ord), string_to_array(u.x, ' ') p;
$$;
grant execute on function public.falla(text, text), public.empresa(text), public.manual(uuid, date, jsonb),
  public.chk(uuid, int, text), public.saldo(uuid, int, text), public.resp(text) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Glosario, fuente, cuentas controladas y catálogo ----------
do $$
begin
  assert (select count(*) from erp.concepts where key in ('taxableBase', 'temporaryDifference', 'currentTax', 'deferredTax')) = 4, 'glosario';
  assert (select ref from erp.sources where key = 'lis') like '%26 (bases negativas)%', 'fuente: Ley 27/2014 con sus artículos';
  assert (select modules from erp.control_rules where account_prefix = '630') = '{corporate_tax}'
     and (select modules from erp.control_rules where account_prefix = '474') = '{corporate_tax}', 'cuentas controladas 630 y 474';
  assert not exists (select 1 from erp.control_rules where account_prefix in ('4752', '473', '4709')), 'el pago a Hacienda es manual';
  assert (select screen from erp.operations where key = 'corporate_tax') = 'corporate_tax', 'catálogo de operaciones';
  raise notice 'OK  · glosario (4 términos), fuente LIS, cuentas controladas 630 y 474, operación del catálogo';
end $$;

-- ---------- Supuestos de Practicar ----------
do $$
declare g jsonb;
begin
  g := erp.grade_exercise('corporate_tax_current', public.resp('6300 D 25000 | 473 H 8000 | 4752 H 17000'));
  assert (g->>'ok')::boolean and (g->>'score')::int = 100, g::text;
  g := erp.grade_exercise('corporate_tax_current', public.resp('6300 D 25000 | 473 H 8000 | 4750 H 17000'));
  assert not (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'tips') t where t->>'msg' like 'La 4750 es la deuda del IVA%'), g::text;
  g := erp.grade_exercise('corporate_tax_deferred', public.resp('4740 D 650 | 6301 H 650'));
  assert (g->>'ok')::boolean and (g->>'score')::int = 100, g::text;
  g := erp.grade_exercise('corporate_tax_deferred', public.resp('6301 D 650 | 479 H 650'));
  assert not (g->>'ok')::boolean and exists (select 1 from jsonb_array_elements(g->'tips') t where t->>'msg' like 'Pagas más impuesto ahora%'), g::text;
  raise notice 'OK  · Practicar: impuesto corriente (6300 / 473 · 4752) y diferido (4740 / 6301), con sus errores típicos';
end $$;

-- ---------- Cierre, invariante y la 129 ----------
do $$
declare e uuid := public.empresa('Cierre IS SL'); s uuid := public.empresa('Estricta SL'); z uuid := public.empresa('Sin actividad SL');
        p jsonb; v_ret uuid;
begin
  perform erp.set_control_mode(s, 'strict');
  foreach v_ret in array array[e, s] loop
    perform public.manual(v_ret, '2026-06-30', '[["57200001", 50000, 0], ["70500001", 0, 50000]]');
    perform public.manual(v_ret, '2026-07-31', '[["62900001", 10000, 0], ["57200001", 0, 10000]]');
    perform public.manual(v_ret, '2026-10-20', '[["47300001", 3000, 0], ["57200001", 0, 3000]]');
  end loop;
  -- sin el impuesto: aviso en guiado, error en estricto; el asistente lo deja pendiente
  assert public.chk(e, 2026, 'corporate_tax_missing') = 'warning', 'guiado: aviso';
  assert public.chk(s, 2026, 'corporate_tax_missing') = 'error' and not (erp.year_closing_preview(s, 2026)->>'can_close')::boolean, 'estricto: no se cierra';
  assert public.falla(format('select erp.close_fiscal_year(%L, 2026, true)', s), 'cannot be closed'), 'estricto: ni aceptando avisos';
  assert (select status from erp.closing_checklist(e, 2026) where code = 'corporate_tax') = 'pending'
     and (select step from erp.closing_checklist(e, 2026) where code = 'corporate_tax') = 10
     and (select step from erp.closing_checklist(e, 2026) where code = 'close') = 11, 'asistente: paso 10 pendiente; el cierre es el 11';
  assert (select status from erp.closing_checklist(z, 2026) where code = 'corporate_tax') = 'na' and public.chk(z, 2026, 'corporate_tax_missing') is null,
         'sin resultado no hace falta';
  assert (select status from erp.integrity_checks(e, 2026) where code = 'corporate_tax') = 'n/a';
  -- en estricto, un asiento manual a la 630 no se contabiliza
  assert public.falla(format('select public.manual(%L, %L, %L)', s, '2026-12-31', '[["63000001", 100, 0], ["57200001", 0, 100]]'), 'controlled'),
         'estricto: la 630 es del Impuesto sobre Sociedades';
  raise notice 'OK  · sin el impuesto: aviso en guiado, error en estricto; asistente paso 10 pendiente (na sin resultado)';

  -- se contabiliza: desaparece el aviso, el paso queda hecho y el invariante cuadra
  perform erp.corporate_tax_settings(erp.corporate_tax_prepare(e, 2026), 'general', false);
  perform erp.corporate_tax_post(e, 2026);
  assert public.chk(e, 2026, 'corporate_tax_missing') is null and public.chk(e, 2026, 'withholdings_left') is null, 'ya no avisa';
  assert (select status from erp.closing_checklist(e, 2026) where code = 'corporate_tax') = 'done';
  assert (select status from erp.integrity_checks(e, 2026) where code = 'corporate_tax') = 'ok';
  perform erp.corporate_tax_settings(erp.corporate_tax_prepare(s, 2026), 'general', false);
  perform erp.corporate_tax_post(s, 2026);
  execute 'set constraints all immediate';   -- el impuesto sí puede mover la 630 y la 474 en estricto
  execute 'set constraints all deferred';
  assert public.chk(s, 2026, 'corporate_tax_missing') is null and (erp.year_closing_preview(s, 2026)->>'can_close')::boolean, 'estricto: ya se puede cerrar';

  -- un pago a cuenta registrado después: la 473 no queda a cero (aviso) y el invariante sigue cuadrando
  perform public.manual(e, '2026-12-30', '[["47300001", 500, 0], ["57200001", 0, 500]]');
  assert public.chk(e, 2026, 'withholdings_left') = 'warning', 'la 473 no ha quedado a cero';
  perform public.manual(e, '2026-12-30', '[["57200001", 500, 0], ["47300001", 0, 500]]');
  -- un asiento manual a la 630 (guiado lo deja) rompe el invariante
  perform public.manual(e, '2026-12-31', '[["63000001", 100, 0], ["57200001", 0, 100]]');
  assert (select status from erp.integrity_checks(e, 2026) where code = 'corporate_tax') = 'fail', 'manual a la 630: no cuadra';
  perform public.manual(e, '2026-12-31', '[["57200001", 100, 0], ["63000001", 0, 100]]');
  assert (select status from erp.integrity_checks(e, 2026) where code = 'corporate_tax') = 'ok';
  raise notice 'OK  · contabilizado: paso hecho, invariante ok; aviso si la 473 no queda a cero; un manual a la 630 lo rompe';

  -- la 129 = resultado antes de impuestos − gasto por impuesto
  perform erp.close_fiscal_year(e, 2026, true);
  assert public.saldo(e, 2026, '129') = 30000, 'la 129: ' || public.saldo(e, 2026, '129');
  assert public.saldo(e, 2026, '4752') = 7000;
  assert not exists (select 1 from erp.integrity_checks(e, 2026) where status = 'fail'),
         (select string_agg(code, ', ') from erp.integrity_checks(e, 2026) where status = 'fail');
  raise notice 'OK  · cerrado: la 129 = 40.000 − 10.000 = 30.000; 4752 7.000; todos los invariantes cuadran';
end $$;

-- ---------- Conceptos de los ajustes sin importes ----------
do $$
declare e uuid := public.empresa('Conceptos SL');
begin
  perform public.manual(e, '2026-06-30', '[["57200001", 50000, 0], ["70500001", 0, 50000]]');
  perform erp.create_fixed_asset(jsonb_build_object('company_id', e, 'name', 'Máquina',
    'asset_account_no', '21300001', 'cost', 20000, 'start_date', '2026-01-01', 'useful_life_months', 48, 'class_code', 'MAQUINARIA'));
  perform erp.post_depreciation(e, '2026-12-31');
  perform erp.corporate_tax_prepare(e, 2026);
  assert exists (select 1 from erp.corporate_tax_adjustments where company_id = e and origin = 'depreciation'), 'propone el ajuste';
  assert not exists (select 1 from erp.corporate_tax_adjustments where company_id = e and concept ~ '\d\.\d\d'),
         (select string_agg(concept, ' / ') from erp.corporate_tax_adjustments where company_id = e);
  assert (select concept from erp.corporate_tax_adjustments where company_id = e and origin = 'depreciation') like '%máximo de la tabla: 12 \%%',
         (select concept from erp.corporate_tax_adjustments where company_id = e and origin = 'depreciation');
  raise notice 'OK  · el concepto de los ajustes ya no lleva importes (van en su columna)';
end $$;
