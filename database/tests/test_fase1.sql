-- =====================================================================
-- PRUEBAS FASE 1 (tests) · se ejecutan contra una base local con supabase_stub.sql
-- Cada bloque imprime OK o se detiene con el error.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

-- ---------- Preparación (como postgres) ----------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@test.local'),    -- creadora de la empresa
  ('00000000-0000-0000-0000-00000000000b', 'beto@test.local');   -- otro usuario

-- Ayuda: ejecuta una sentencia y exige que falle con un mensaje que contenga p_texto
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

-- ---------- Sesión de Ana ----------
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \gset

do $$
declare
  e uuid; ej uuid; t uuid; a uuid; n int;
  c_cli uuid; c_ing uuid; c_igic uuid; c_banco uuid; c_gasto uuid; c_igic_s uuid; c_prov uuid;
begin
  -- Empresa + PGC + rol admin automático
  insert into erp.companies (name, vat_registration_no, industry, tax_territory)
  values ('Pruebas Servicios Canarias SL', 'B00000000', 'services', 'canary_islands')
  returning id into e;
  assert (select count(*) from erp.gl_accounts where company_id = e) = 352, 'el PGC no se copió completo';
  assert erp.my_role(e) = 'admin', 'la creadora no es admin';
  raise notice 'OK  · alta de empresa: PGC copiado (352 cuentas) y creadora como admin';

  ej := erp.create_fiscal_year(e, 2026);
  assert (select count(*) from erp.accounting_periods where fiscal_year_id = ej) = 12;
  assert (select ending_date from erp.accounting_periods where fiscal_year_id = ej and period_no = 2) = '2026-02-28';
  raise notice 'OK  · ejercicio 2026 con 12 periodos';

  -- Subcuentas
  c_cli    := erp.create_posting_account(e, '43000001', 'Cliente Uno SL');
  c_ing    := erp.create_posting_account(e, '70500001', 'Servicios de consultoría');
  c_igic   := erp.create_posting_account(e, '47710007', 'IGIC repercutido 7%');
  c_igic_s := erp.create_posting_account(e, '47210007', 'IGIC soportado 7%');
  c_banco  := erp.create_posting_account(e, '57200001', 'Banco c/c');
  c_gasto  := erp.create_posting_account(e, '62900001', 'Otros servicios');
  c_prov   := erp.create_posting_account(e, '41000001', 'Acreedor Uno');
  assert (select template_account from erp.gl_accounts where id = c_cli) = '430';
  assert (select account_category from erp.gl_accounts where id = c_igic) = 'liability';
  assert (select template_account from erp.gl_accounts where account_no = '47510001' and company_id = e) is null;
  perform erp.create_posting_account(e, '47510001', 'Retenciones IRPF profesionales', 'Withholdings payable – professionals');
  assert (select template_account from erp.gl_accounts where account_no = '47510001' and company_id = e) = '4751',
         'debía colgar de la cuenta de 4 dígitos 4751';
  raise notice 'OK  · subcuentas cuelgan de su cuenta PGC (430, 4751…)';

  insert into erp.business_partners (company_id, partner_type, vat_registration_no, name, tax_territory, gl_account_id)
  values (e, 'customer', 'B11111111', 'Cliente Uno SL', 'canary_islands', c_cli) returning id into t;

  -- Asiento 1: factura de venta con IGIC 7%
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (e, ej, '2026-03-15', 'Factura venta F-001', 'F-001') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit, partner_id) values (a, c_cli, 107, t);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, c_ing, 100);
  insert into erp.journal_lines (entry_id, gl_account_id, credit, partner_id, tax_code, tax_base)
  values (a, c_igic, 7, t, 'IGIC7', 100);
  n := erp.post_entry(a);
  assert n = 1, 'el primer asiento debía ser el nº 1';
  raise notice 'OK  · asiento 1 (venta con IGIC) contabilizado';

  -- Asiento 2: cobro
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, ej, '2026-03-30', 'Cobro F-001') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)  values (a, c_banco, 107);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, c_cli, 107);
  assert erp.post_entry(a) = 2;

  -- Asiento 3: gasto con IGIC soportado
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (e, ej, '2026-04-02', 'Factura asesoría', 'A-77') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)  values (a, c_gasto, 200);
  insert into erp.journal_lines (entry_id, gl_account_id, debit, tax_code, tax_base)
  values (a, c_igic_s, 14, 'IGIC7', 200);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, c_prov, 214);
  assert erp.post_entry(a) = 3;
  raise notice 'OK  · asientos 2 y 3 contabilizados con numeración correlativa';

  insert into public.ctx values ('empresa', e), ('ejercicio', ej), ('asiento3', a),
                                ('banco', c_banco), ('cliente', c_cli), ('titulo_430',
                                 (select id from erp.gl_accounts where company_id = e and account_no = '430'));
end $$;

-- ---------- Reglas que deben bloquear ----------
do $$
declare
  e  uuid := (select valor from public.ctx where clave = 'empresa');
  ej uuid := (select valor from public.ctx where clave = 'ejercicio');
  a3 uuid := (select valor from public.ctx where clave = 'asiento3');
  cb uuid := (select valor from public.ctx where clave = 'banco');
  cc uuid := (select valor from public.ctx where clave = 'cliente');
  ct uuid := (select valor from public.ctx where clave = 'titulo_430');
  a  uuid;
begin
  -- Descuadrado
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, ej, '2026-05-01', 'Descuadrado') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)  values (a, cb, 100);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, cc, 99.99);
  perform public.debe_fallar(format('select erp.post_entry(%L)', a), 'Unbalanced', 'no contabiliza si Debe ≠ Haber');
  delete from erp.journal_entries where id = a;   -- un borrador sí se puede borrar
  raise notice 'OK  · un borrador se borra sin problema';

  -- Un solo apunte
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, ej, '2026-05-01', 'Cojo') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit) values (a, cb, 10);
  perform public.debe_fallar(format('select erp.post_entry(%L)', a), 'at least 2', 'exige 2 apuntes');
  -- Debe y Haber a la vez / importe cero
  perform public.debe_fallar(format('insert into erp.journal_lines (entry_id, gl_account_id, debit, credit) values (%L,%L,5,5)', a, cb),
                             'check', 'un apunte no puede ir a Debe y Haber');
  perform public.debe_fallar(format('insert into erp.journal_lines (entry_id, gl_account_id) values (%L,%L)', a, cb),
                             'check', 'un apunte no puede ser cero');
  -- Cuenta de título
  perform public.debe_fallar(format('insert into erp.journal_lines (entry_id, gl_account_id, debit) values (%L,%L,5)', a, ct),
                             'heading account', 'no se apunta en una cuenta de 3 dígitos');
  delete from erp.journal_entries where id = a;

  -- Subcuentas mal formadas
  perform public.debe_fallar(format('select erp.create_posting_account(%L, %L, %L)', e, '4300001', 'x'),
                             'must have 8', 'subcuenta con longitud incorrecta');
  perform public.debe_fallar(format('select erp.create_posting_account(%L, %L, %L)', e, '99900001', 'x'),
                             'does not belong', 'subcuenta sin cuenta PGC');

  -- Fecha fuera del ejercicio
  perform public.debe_fallar(format('insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (%L,%L,%L,%L)',
                                    e, ej, '2025-12-31', 'x'), 'outside fiscal year', 'fecha fuera de ejercicio');

  -- Inmutabilidad
  perform public.debe_fallar(format('update erp.journal_entries set description = %L where id = %L', 'cambiado', a3),
                             'posted', 'no se edita un asiento contabilizado');
  perform public.debe_fallar(format('update erp.journal_lines set debit = 1 where entry_id = %L and debit > 0', a3),
                             'posted', 'no se editan sus apuntes');
  perform public.debe_fallar(format('delete from erp.journal_lines where entry_id = %L', a3),
                             'posted', 'no se borran sus apuntes');
  perform public.debe_fallar(format('delete from erp.journal_entries where id = %L', a3),
                             'posted', 'no se borra un asiento contabilizado');
  perform public.debe_fallar(format('select erp.post_entry(%L)', a3), 'already posted', 'no se contabiliza dos veces');

  -- Periodo cerrado (lo cierra la admin)
  update erp.accounting_periods set status = 'closed' where fiscal_year_id = ej and period_no = 6;
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (e, ej, '2026-06-10', 'En junio') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit)  values (a, cb, 1);
  insert into erp.journal_lines (entry_id, gl_account_id, credit) values (a, cc, 1);
  perform public.debe_fallar(format('select erp.post_entry(%L)', a), 'Period 6', 'no contabiliza en periodo cerrado');
  delete from erp.journal_entries where id = a;
  update erp.accounting_periods set status = 'open' where fiscal_year_id = ej and period_no = 6;
end $$;

-- ---------- Anulación con contraasiento ----------
do $$
declare
  a3 uuid := (select valor from public.ctx where clave = 'asiento3');
  n  int;
begin
  n := erp.reverse_entry(a3, '2026-04-10');
  assert n = 4, 'el contraasiento debía ser el nº 4';
  assert (select reversed_by is not null from erp.journal_entries where id = a3);
  assert (select sum(debit) - sum(credit) from erp.v_general_ledger where account_no = '62900001') = 0,
         'tras anular, la 629 debía quedar a cero';
  perform public.debe_fallar(format('select erp.reverse_entry(%L)', a3), 'already reversed', 'no se anula dos veces');
  raise notice 'OK  · anulación: contraasiento nº 4 deja las cuentas a cero y conserva el original';
end $$;

-- ---------- Informes ----------
do $$
declare
  e uuid := (select valor from public.ctx where clave = 'empresa');
  r record;
begin
  select sum(total_debit) d, sum(total_credit) h into r from erp.trial_balance(e, 2026);
  assert r.d = r.h, 'sumas y saldos descuadrado';
  assert r.d = 107 + 107 + 214 + 214, format('suma Debe inesperada: %s', r.d);
  assert (select debit_balance from erp.trial_balance(e, 2026, 3) where account_no = '572') = 107;
  assert (select credit_balance from erp.trial_balance(e, 2026, 1) where account_no = '7') = 100;
  assert (select name from erp.trial_balance(e, 2026, 2) where account_no = '57') = 'Tesorería';
  assert (select name_en from erp.trial_balance(e, 2026, 2) where account_no = '57') = 'Cash and cash equivalents';
  raise notice 'OK  · sumas y saldos cuadra y agrupa por grupo / subgrupo / cuenta';

  assert (select count(*) from erp.v_general_journal where company_id = e) = 11;  -- 3+2+3+3 apuntes
  assert (select running_balance from erp.v_general_ledger where account_no = '43000001' order by posting_date desc, entry_no desc limit 1) = 0;
  raise notice 'OK  · libro diario y libro mayor (saldo acumulado)';

  assert (select tax_amount from erp.v_tax_book where tax_class = 'output' and entry_no = 1) = 7;
  assert (select sum(tax_amount) from erp.v_tax_book where tax_class = 'input') = 0, 'soportado anulado debía sumar 0';
  raise notice 'OK  · libro registro IGIC (repercutido 7 €, soportado anulado)';
end $$;

-- ---------- Multiusuario: Beto ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  assert (select count(*) from erp.companies) = 0, 'Beto NO debería ver la empresa de Ana';
  assert (select count(*) from erp.journal_lines) = 0, 'Beto NO debería ver apuntes';
  assert (select count(*) from erp.v_general_journal) = 0, 'las vistas deben respetar RLS';
  assert (select count(*) from erp.trial_balance(e, 2026)) = 0, 'sumas y saldos debe respetar RLS';
  assert (select count(*) from erp.coa_template) = 352, 'el PGC plantilla sí es visible';
  perform public.debe_fallar(format('insert into erp.company_users (company_id, user_id, role) values (%L, auth.uid(), %L)', e, 'admin'),
                             'row-level security', 'Beto no puede autoinvitarse');
  raise notice 'OK  · aislamiento: Beto no ve nada de la empresa de Ana';
end $$;

-- Ana invita a Beto como "lectura"
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \gset
insert into erp.company_users (company_id, user_id, role)
select valor, '00000000-0000-0000-0000-00000000000b', 'viewer' from public.ctx where clave = 'empresa';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \gset
do $$
declare
  e  uuid := (select valor from public.ctx where clave = 'empresa');
  ej uuid := (select valor from public.ctx where clave = 'ejercicio');
begin
  assert (select count(*) from erp.companies) = 1, 'con rol lectura Beto debe ver la empresa';
  assert (select count(*) from erp.v_general_journal) = 11;
  perform public.debe_fallar(format('insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description) values (%L,%L,%L,%L)',
                                    e, ej, '2026-05-01', 'x'), 'row-level security', 'lectura no crea asientos');
  perform public.debe_fallar(format('select erp.delete_company(%L)', e), 'Only the company admin', 'lectura no elimina la empresa');
  raise notice 'OK  · rol lectura: consulta sí, escribe no';
end $$;

-- ---------- Preferencia de idioma (user_settings) ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \gset
insert into erp.user_settings (language) values ('en');   -- user_id = auth.uid() por defecto
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \gset
do $$ begin
  assert (select count(*) from erp.user_settings) = 0, 'Beto NO debe ver las preferencias de Ana';
  insert into erp.user_settings (language) values ('es');
  perform public.debe_fallar('update erp.user_settings set language = ''fr''', 'check', 'solo es / en');
  assert (select language from erp.user_settings) = 'es';
  raise notice 'OK  · idioma por usuario: cada uno ve y cambia solo el suyo';
end $$;

-- ---------- Eliminar empresa de práctica (Ana, admin) ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  perform erp.delete_company(e);
end $$;

reset role;
do $$ begin
  assert (select count(*) from erp.journal_entries) = 0 and (select count(*) from erp.gl_accounts) = 0;
  raise notice 'OK  · eliminar_empresa borra todo, incluidos asientos contabilizados';
end $$;

drop table public.ctx;
drop function public.debe_fallar(text, text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 1 PASARON ==========='
