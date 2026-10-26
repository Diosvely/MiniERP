-- =====================================================================
-- PRUEBAS FASE 63 · Contabilidad mes a mes (migración 0069 · v0.47.0)
-- ---------------------------------------------------------------------
-- Mejora de uso 7 (mejoras-de-uso.md), validada por Diosvely:
--   · Fecha de inicio al crear la empresa; en el modo mes a mes, los meses anteriores quedan cerrados.
--   · Mes de trabajo = el primer mes abierto: solo se contabiliza en él (ni antes de la fecha de inicio ni en un mes
--     posterior); la fecha que se propone es la del último asiento del mes o el día 1.
--   · Cerrar el mes, con avisos (borradores, nómina del mes y liquidación del trimestre), y reabrir el último cerrado.
--   · Diciembre lo cierra el Cierre del ejercicio, y el mes de trabajo pasa a enero del año siguiente.
--   · Las empresas sin el modo mes a mes no cambian.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a1', 'admin@test.local'),
                                          ('00000000-0000-0000-0000-0000000000b2', 'otro@test.local');
insert into erp.app_profiles (user_id, app_role, max_companies) values ('00000000-0000-0000-0000-0000000000a1', 'owner', null);
create table public.ctx (k text primary key, e uuid);
grant all on public.ctx to authenticated;

create or replace function public.falla(sql text, texto text) returns boolean language plpgsql as $$
begin
  execute sql;
  return false;
exception when others then
  if sqlerrm ilike '%' || texto || '%' then return true; end if;
  raise notice 'error inesperado: %', sqlerrm;
  return false;
end $$;
-- Empresa canaria, en modo guiado, con la fecha de inicio (o sin el modo mes a mes)
create or replace function public.empresa(nombre text, inicio date, mensual boolean) returns uuid language plpgsql as $$
declare e uuid; c text;
begin
  insert into erp.companies (name, industry, tax_territory, control_mode, created_by) values (nombre, 'services', 'canary_islands', 'guided', auth.uid()) returning id into e;
  perform erp.start_accounting(e, inicio, mensual);
  foreach c in array array['57200001:Banco', '70500001:Prestación de servicios', '62900001:Otros servicios', '10000001:Capital'] loop
    perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
  end loop;
  return e;
end $$;
-- Asiento manual (contabilizado o en borrador)
create or replace function public.asiento(e uuid, d date, importe numeric, contabilizar boolean default true) returns uuid language plpgsql as $$
declare a uuid;
begin
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, (select id from erp.fiscal_years where company_id = e and year = extract(year from d)), d, 'Prueba') returning id into a;
  insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
    (a, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), importe, 0),
    (a, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '70500001'), 0, importe);
  if contabilizar then perform erp.post_entry(a); end if;
  return a;
end $$;
create or replace function public.mes(e uuid) returns text language sql as $$
  select (erp.work_month(e)->>'year') || '-' || lpad(erp.work_month(e)->>'month', 2, '0') $$;
grant execute on function public.falla(text, text), public.empresa(text, date, boolean), public.asiento(uuid, date, numeric, boolean), public.mes(uuid) to authenticated;

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \gset

-- ---------- Empezar el 01/01/2026, mes a mes ----------
do $$
declare e uuid := public.empresa('Mes a Mes SL', '2026-01-01', true); w jsonb;
begin
  insert into public.ctx values ('m', e);
  assert (select start_date || '/' || monthly from erp.v_my_companies where id = e) = '2026-01-01/true', 'mis empresas: inicio y modo';
  assert (select count(*) from erp.accounting_periods p join erp.fiscal_years fy on fy.id = p.fiscal_year_id where fy.company_id = e and p.status = 'open') = 12,
         'los 12 meses, abiertos';
  w := erp.work_month(e);
  assert public.mes(e) = '2026-01' and w->>'work_date' = '2026-01-01' and not (w->>'december')::boolean, 'mes de trabajo: enero, propone el día 1: ' || w::text;
  perform public.asiento(e, '2026-01-10', 100);
  assert erp.work_month(e)->>'work_date' = '2026-01-10', 'propone la fecha del último asiento del mes';
  assert public.falla(format('select public.asiento(%L, %L, 50)', e, '2026-02-03'), 'the open month is 01/2026'), 'febrero, todavía no';
  perform erp.create_fiscal_year(e, 2027);
  assert public.falla(format('select public.asiento(%L, %L, 50)', e, '2027-01-03'), 'the open month is 01/2026'), 'ni el año siguiente';
  raise notice 'OK  · inicio el 01/01/2026: mes de trabajo enero; un asiento de febrero se rechaza hasta cerrar enero';
end $$;

-- ---------- Cerrar enero: avisos ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'm'); p jsonb; r jsonb; b uuid;
begin
  b := public.asiento(e, '2026-01-20', 70, false);                       -- un borrador de enero
  perform erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Ana Ficticia', 'contract_type', 'temporary',
    'hire_date', '2026-01-01', 'end_date', '2026-01-31', 'monthly_salary', 1500, 'extra_payments', 2, 'extra_prorated', true, 'irpf_pct', 10));
  p := erp.month_close_preview(e);
  assert p->>'month' = '1' and (p->>'entries')::int = 1, 'vista previa: ' || p::text;
  assert (select string_agg(x->>'code', ',' order by x->>'code') from jsonb_array_elements(p->'warnings') x) = 'drafts,payroll', 'avisos: ' || (p->'warnings')::text;
  assert public.falla(format('select erp.close_month(%L)', e), 'accept the warnings'), 'con avisos, hay que aceptarlos';
  delete from erp.journal_lines where entry_id = b; delete from erp.journal_entries where id = b;
  r := erp.close_month(e, true);
  assert r->'closed' = '{"year": 2026, "month": 1}'::jsonb and public.mes(e) = '2026-02', 'enero cerrado: ' || r::text;
  assert erp.work_month(e)->>'work_date' = '2026-02-01', 'febrero propone el día 1';
  assert public.falla(format('select public.asiento(%L, %L, 50)', e, '2026-01-31'), 'Period 1 of 2026 is closed'), 'enero, cerrado';
  perform public.asiento(e, '2026-02-03', 50);
  raise notice 'OK  · cerrar enero: avisa del borrador y de la nómina; cerrado, enero no admite asientos y febrero sí';
end $$;

-- ---------- El trimestre: la liquidación ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'm'); p jsonb;
begin
  perform erp.close_month(e);                                             -- febrero, sin avisos (Ana, de baja el 31/01)
  assert public.mes(e) = '2026-03', 'marzo';
  perform erp.setup_taxes(e);
  p := erp.month_close_preview(e);
  assert (select x->>'code' || '/' || (x->>'quarter') || '/' || (x->>'tax') from jsonb_array_elements(p->'warnings') x) = 'settlement/1/IGIC', 'aviso de la liquidación: ' || p::text;
  perform erp.post_tax_settlement(e, 'IGIC', 2026, 1);
  assert jsonb_array_length(erp.month_close_preview(e)->'warnings') = 0, 'liquidado, sin avisos';
  perform erp.close_month(e);
  raise notice 'OK  · cerrar marzo: avisa de la liquidación del 1T del IGIC; liquidada, se cierra sin avisos';
end $$;

-- ---------- Reabrir ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'm');
begin
  assert public.mes(e) = '2026-04', 'abril';
  perform erp.reopen_month(e);
  assert public.mes(e) = '2026-03', 'marzo reabierto';
  perform erp.reopen_month(e); perform erp.reopen_month(e);
  assert public.mes(e) = '2026-01', 'hasta enero';
  assert public.falla(format('select erp.reopen_month(%L)', e), 'no closed month'), 'antes del inicio no hay nada';
  perform erp.close_month(e, true); perform erp.close_month(e, true); perform erp.close_month(e, true);
  assert public.mes(e) = '2026-04', 'otra vez en abril';
  raise notice 'OK  · reabrir el último mes cerrado, hasta el mes de inicio';
end $$;

-- ---------- Diciembre y el año siguiente ----------
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'm'); r record;
begin
  while (erp.work_month(e)->>'month')::int < 12 loop perform erp.close_month(e, true); end loop;
  assert public.mes(e) = '2026-12' and (erp.work_month(e)->>'december')::boolean, 'diciembre';
  assert public.falla(format('select erp.close_month(%L, true)', e), 'year-end closing'), 'diciembre, con el cierre del ejercicio';
  perform public.asiento(e, '2026-12-15', 30);
  select * into r from erp.close_fiscal_year(e, 2026, true);
  assert public.mes(e) = '2027-01', 'tras el cierre, enero de 2027';
  assert erp.work_month(e)->>'last_entry_date' is null and erp.work_month(e)->>'work_date' = '2027-01-01', 'la apertura no cuenta como último asiento';
  perform public.asiento(e, '2027-01-08', 20);
  assert public.falla(format('select erp.reopen_month(%L)', e), 'reopen the fiscal year first'), 'diciembre está en un ejercicio cerrado';
  raise notice 'OK  · diciembre se cierra con el cierre del ejercicio (regularización, cierre y apertura) y el mes de trabajo pasa a enero de 2027';
end $$;

-- ---------- Empezar a mitad de año ----------
do $$
declare e uuid := public.empresa('Marzo SL', '2026-03-15', true);
begin
  assert (select string_agg(p.period_no || '=' || p.status, ' ' order by p.period_no) from erp.accounting_periods p join erp.fiscal_years fy on fy.id = p.fiscal_year_id
          where fy.company_id = e and p.period_no <= 4) = '1=closed 2=closed 3=open 4=open', 'enero y febrero, cerrados';
  assert public.mes(e) = '2026-03' and erp.work_month(e)->>'work_date' = '2026-03-15', 'mes de trabajo marzo, desde el 15';
  assert public.falla(format('select public.asiento(%L, %L, 10)', e, '2026-03-10'), 'starts on 15/03/2026'), 'antes del inicio, no';
  perform public.asiento(e, '2026-03-15', 10);
  assert public.falla(format('select erp.start_accounting(%L, %L)', e, '2026-01-01'), 'already has entries'), 'la fecha de inicio no se cambia con asientos';
  raise notice 'OK  · inicio el 15/03/2026: enero y febrero cerrados; nada antes del 15';
end $$;

-- ---------- Sin el modo mes a mes, todo igual ----------
do $$
declare e uuid := public.empresa('Libre SL', '2026-01-01', false);
begin
  perform public.asiento(e, '2026-11-30', 10);
  perform public.asiento(e, '2026-02-01', 10);
  assert public.falla(format('select erp.close_month(%L)', e), 'does not use monthly accounting'), 'sin modo mes a mes, no se cierran meses';
  assert (erp.work_month(e)->>'monthly')::boolean = false, 'work_month lo dice';
  raise notice 'OK  · sin el modo mes a mes, cualquier mes abierto admite asientos';
end $$;

-- ---------- Permisos ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false) \gset
do $$
declare e uuid := (select c.e from public.ctx c where c.k = 'm');
begin
  assert public.falla(format('select erp.close_month(%L)', e), 'No permission'), 'otro usuario no cierra meses';
  assert public.falla(format('select erp.reopen_month(%L)', e), 'No permission'), 'ni los reabre';
  assert public.falla(format('select erp.work_month(%L)', e), 'Not allowed'), 'ni ve el mes de trabajo';
  assert public.falla(format('select erp.start_accounting(%L, %L)', e, '2026-01-01'), 'No permission'), 'ni cambia el inicio';
  raise notice 'OK  · otro usuario no ve ni toca los meses de una empresa ajena';
end $$;
reset role;
