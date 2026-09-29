-- =====================================================================
-- PRUEBAS FASE 1 · se ejecutan contra una base local con supabase_stub.sql
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
  insert into conta.empresas (nombre, nif, sector, territorio)
  values ('Pruebas Servicios Canarias SL', 'B00000000', 'servicios', 'canarias')
  returning id into e;
  assert (select count(*) from conta.cuentas where empresa_id = e) = 352, 'el PGC no se copió completo';
  assert conta.mi_rol(e) = 'admin', 'la creadora no es admin';
  raise notice 'OK  · alta de empresa: PGC copiado (352 cuentas) y creadora como admin';

  ej := conta.crear_ejercicio(e, 2026);
  assert (select count(*) from conta.periodos where ejercicio_id = ej) = 12;
  assert (select fecha_fin from conta.periodos where ejercicio_id = ej and numero = 2) = '2026-02-28';
  raise notice 'OK  · ejercicio 2026 con 12 periodos';

  -- Subcuentas
  c_cli    := conta.crear_subcuenta(e, '43000001', 'Cliente Uno SL');
  c_ing    := conta.crear_subcuenta(e, '70500001', 'Servicios de consultoría');
  c_igic   := conta.crear_subcuenta(e, '47710007', 'IGIC repercutido 7%');
  c_igic_s := conta.crear_subcuenta(e, '47210007', 'IGIC soportado 7%');
  c_banco  := conta.crear_subcuenta(e, '57200001', 'Banco c/c');
  c_gasto  := conta.crear_subcuenta(e, '62900001', 'Otros servicios');
  c_prov   := conta.crear_subcuenta(e, '41000001', 'Acreedor Uno');
  assert (select cuenta_pgc from conta.cuentas where id = c_cli) = '430';
  assert (select naturaleza from conta.cuentas where id = c_igic) = 'pasivo';
  assert (select cuenta_pgc from conta.cuentas where codigo = '47510001' and empresa_id = e) is null;
  perform conta.crear_subcuenta(e, '47510001', 'Retenciones IRPF profesionales');
  assert (select cuenta_pgc from conta.cuentas where codigo = '47510001' and empresa_id = e) = '4751',
         'debía colgar de la cuenta de 4 dígitos 4751';
  raise notice 'OK  · subcuentas cuelgan de su cuenta PGC (430, 4751…)';

  insert into conta.terceros (empresa_id, tipo, nif, nombre, territorio, cuenta_id)
  values (e, 'cliente', 'B11111111', 'Cliente Uno SL', 'canarias', c_cli) returning id into t;

  -- Asiento 1: factura de venta con IGIC 7%
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, documento)
  values (e, ej, '2026-03-15', 'Factura venta F-001', 'F-001') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe, tercero_id) values (a, c_cli, 107, t);
  insert into conta.apuntes (asiento_id, cuenta_id, haber) values (a, c_ing, 100);
  insert into conta.apuntes (asiento_id, cuenta_id, haber, tercero_id, impuesto_tipo_id, base_imponible)
  values (a, c_igic, 7, t, 'IGIC7', 100);
  n := conta.contabilizar(a);
  assert n = 1, 'el primer asiento debía ser el nº 1';
  raise notice 'OK  · asiento 1 (venta con IGIC) contabilizado';

  -- Asiento 2: cobro
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto)
  values (e, ej, '2026-03-30', 'Cobro F-001') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe)  values (a, c_banco, 107);
  insert into conta.apuntes (asiento_id, cuenta_id, haber) values (a, c_cli, 107);
  assert conta.contabilizar(a) = 2;

  -- Asiento 3: gasto con IGIC soportado
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, documento)
  values (e, ej, '2026-04-02', 'Factura asesoría', 'A-77') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe)  values (a, c_gasto, 200);
  insert into conta.apuntes (asiento_id, cuenta_id, debe, impuesto_tipo_id, base_imponible)
  values (a, c_igic_s, 14, 'IGIC7', 200);
  insert into conta.apuntes (asiento_id, cuenta_id, haber) values (a, c_prov, 214);
  assert conta.contabilizar(a) = 3;
  raise notice 'OK  · asientos 2 y 3 contabilizados con numeración correlativa';

  insert into public.ctx values ('empresa', e), ('ejercicio', ej), ('asiento3', a),
                                ('banco', c_banco), ('cliente', c_cli), ('titulo_430',
                                 (select id from conta.cuentas where empresa_id = e and codigo = '430'));
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
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto)
  values (e, ej, '2026-05-01', 'Descuadrado') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe)  values (a, cb, 100);
  insert into conta.apuntes (asiento_id, cuenta_id, haber) values (a, cc, 99.99);
  perform public.debe_fallar(format('select conta.contabilizar(%L)', a), 'descuadrado', 'no contabiliza si Debe ≠ Haber');
  delete from conta.asientos where id = a;   -- un borrador sí se puede borrar
  raise notice 'OK  · un borrador se borra sin problema';

  -- Un solo apunte
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto)
  values (e, ej, '2026-05-01', 'Cojo') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe) values (a, cb, 10);
  perform public.debe_fallar(format('select conta.contabilizar(%L)', a), 'al menos 2', 'exige 2 apuntes');
  -- Debe y Haber a la vez / importe cero
  perform public.debe_fallar(format('insert into conta.apuntes (asiento_id, cuenta_id, debe, haber) values (%L,%L,5,5)', a, cb),
                             'check', 'un apunte no puede ir a Debe y Haber');
  perform public.debe_fallar(format('insert into conta.apuntes (asiento_id, cuenta_id) values (%L,%L)', a, cb),
                             'check', 'un apunte no puede ser cero');
  -- Cuenta de título
  perform public.debe_fallar(format('insert into conta.apuntes (asiento_id, cuenta_id, debe) values (%L,%L,5)', a, ct),
                             'es de título', 'no se apunta en una cuenta de 3 dígitos');
  delete from conta.asientos where id = a;

  -- Subcuentas mal formadas
  perform public.debe_fallar(format('select conta.crear_subcuenta(%L, %L, %L)', e, '4300001', 'x'),
                             'debe tener 8', 'subcuenta con longitud incorrecta');
  perform public.debe_fallar(format('select conta.crear_subcuenta(%L, %L, %L)', e, '99900001', 'x'),
                             'no cuelga', 'subcuenta sin cuenta PGC');

  -- Fecha fuera del ejercicio
  perform public.debe_fallar(format('insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto) values (%L,%L,%L,%L)',
                                    e, ej, '2025-12-31', 'x'), 'fuera del ejercicio', 'fecha fuera de ejercicio');

  -- Inmutabilidad
  perform public.debe_fallar(format('update conta.asientos set concepto = %L where id = %L', 'cambiado', a3),
                             'contabilizado', 'no se edita un asiento contabilizado');
  perform public.debe_fallar(format('update conta.apuntes set debe = 1 where asiento_id = %L and debe > 0', a3),
                             'contabilizado', 'no se editan sus apuntes');
  perform public.debe_fallar(format('delete from conta.apuntes where asiento_id = %L', a3),
                             'contabilizado', 'no se borran sus apuntes');
  perform public.debe_fallar(format('delete from conta.asientos where id = %L', a3),
                             'contabilizado', 'no se borra un asiento contabilizado');
  perform public.debe_fallar(format('select conta.contabilizar(%L)', a3), 'ya está contabilizado', 'no se contabiliza dos veces');

  -- Periodo cerrado (lo cierra la admin)
  update conta.periodos set estado = 'cerrado' where ejercicio_id = ej and numero = 6;
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto)
  values (e, ej, '2026-06-10', 'En junio') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe)  values (a, cb, 1);
  insert into conta.apuntes (asiento_id, cuenta_id, haber) values (a, cc, 1);
  perform public.debe_fallar(format('select conta.contabilizar(%L)', a), 'periodo 6', 'no contabiliza en periodo cerrado');
  delete from conta.asientos where id = a;
  update conta.periodos set estado = 'abierto' where ejercicio_id = ej and numero = 6;
end $$;

-- ---------- Anulación con contraasiento ----------
do $$
declare
  a3 uuid := (select valor from public.ctx where clave = 'asiento3');
  n  int;
begin
  n := conta.anular(a3, '2026-04-10');
  assert n = 4, 'el contraasiento debía ser el nº 4';
  assert (select anulado_por is not null from conta.asientos where id = a3);
  assert (select sum(debe) - sum(haber) from conta.v_libro_mayor where cuenta = '62900001') = 0,
         'tras anular, la 629 debía quedar a cero';
  perform public.debe_fallar(format('select conta.anular(%L)', a3), 'ya está anulado', 'no se anula dos veces');
  raise notice 'OK  · anulación: contraasiento nº 4 deja las cuentas a cero y conserva el original';
end $$;

-- ---------- Informes ----------
do $$
declare
  e uuid := (select valor from public.ctx where clave = 'empresa');
  r record;
begin
  select sum(suma_debe) d, sum(suma_haber) h into r from conta.sumas_saldos(e, 2026);
  assert r.d = r.h, 'sumas y saldos descuadrado';
  assert r.d = 107 + 107 + 214 + 214, format('suma Debe inesperada: %s', r.d);
  assert (select saldo_deudor from conta.sumas_saldos(e, 2026, 3) where cuenta = '572') = 107;
  assert (select saldo_acreedor from conta.sumas_saldos(e, 2026, 1) where cuenta = '7') = 100;
  assert (select nombre from conta.sumas_saldos(e, 2026, 2) where cuenta = '57') = 'Tesorería';
  raise notice 'OK  · sumas y saldos cuadra y agrupa por grupo / subgrupo / cuenta';

  assert (select count(*) from conta.v_libro_diario where empresa_id = e) = 11;  -- 3+2+3+3 apuntes
  assert (select saldo from conta.v_libro_mayor where cuenta = '43000001' order by fecha desc, numero desc limit 1) = 0;
  raise notice 'OK  · libro diario y libro mayor (saldo acumulado)';

  assert (select cuota from conta.v_libro_impuestos where clase = 'repercutido' and asiento = 1) = 7;
  assert (select sum(cuota) from conta.v_libro_impuestos where clase = 'soportado') = 0, 'soportado anulado debía sumar 0';
  raise notice 'OK  · libro registro IGIC (repercutido 7 €, soportado anulado)';
end $$;

-- ---------- Multiusuario: Beto ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  assert (select count(*) from conta.empresas) = 0, 'Beto NO debería ver la empresa de Ana';
  assert (select count(*) from conta.apuntes) = 0, 'Beto NO debería ver apuntes';
  assert (select count(*) from conta.v_libro_diario) = 0, 'las vistas deben respetar RLS';
  assert (select count(*) from conta.sumas_saldos(e, 2026)) = 0, 'sumas y saldos debe respetar RLS';
  assert (select count(*) from conta.pgc_plantilla) = 352, 'el PGC plantilla sí es visible';
  perform public.debe_fallar(format('insert into conta.usuarios_empresa (empresa_id, user_id, rol) values (%L, auth.uid(), %L)', e, 'admin'),
                             'row-level security', 'Beto no puede autoinvitarse');
  raise notice 'OK  · aislamiento: Beto no ve nada de la empresa de Ana';
end $$;

-- Ana invita a Beto como "lectura"
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \gset
insert into conta.usuarios_empresa (empresa_id, user_id, rol)
select valor, '00000000-0000-0000-0000-00000000000b', 'lectura' from public.ctx where clave = 'empresa';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false) \gset
do $$
declare
  e  uuid := (select valor from public.ctx where clave = 'empresa');
  ej uuid := (select valor from public.ctx where clave = 'ejercicio');
begin
  assert (select count(*) from conta.empresas) = 1, 'con rol lectura Beto debe ver la empresa';
  assert (select count(*) from conta.v_libro_diario) = 11;
  perform public.debe_fallar(format('insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto) values (%L,%L,%L,%L)',
                                    e, ej, '2026-05-01', 'x'), 'row-level security', 'lectura no crea asientos');
  perform public.debe_fallar(format('select conta.eliminar_empresa(%L)', e), 'Solo el administrador', 'lectura no elimina la empresa');
  raise notice 'OK  · rol lectura: consulta sí, escribe no';
end $$;

-- ---------- Eliminar empresa de práctica (Ana, admin) ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false) \gset
do $$
declare e uuid := (select valor from public.ctx where clave = 'empresa');
begin
  perform conta.eliminar_empresa(e);
end $$;

reset role;
do $$ begin
  assert (select count(*) from conta.asientos) = 0 and (select count(*) from conta.cuentas) = 0;
  raise notice 'OK  · eliminar_empresa borra todo, incluidos asientos contabilizados';
end $$;

drop table public.ctx;
drop function public.debe_fallar(text, text, text);
\echo '=========== TODAS LAS PRUEBAS DE LA FASE 1 PASARON ==========='
