-- =====================================================================
-- 0004 · ASIENTOS Y APUNTES
-- ---------------------------------------------------------------------
-- Equivalencias:
--   asientos (cabecera)  ≈ SAP BKPF  ≈ BC "Document No." agrupando G/L Entries
--   apuntes  (líneas)    ≈ SAP BSEG  ≈ BC "G/L Entry"
--
-- Ciclo de vida (ver docs/decisiones/0002-asientos.md):
--   borrador ──contabilizar()──► contabilizado ──anular()──► genera contraasiento
--
-- Reglas que garantiza la base de datos (no la web):
--   1. Un asiento contabilizado es INMUTABLE: ni se edita ni se borra.
--   2. Solo se contabiliza si Debe = Haber, con ≥ 2 apuntes y en periodo abierto.
--   3. Solo se apunta en subcuentas (tipo 'auxiliar') de la misma empresa y no bloqueadas.
--   4. Numeración correlativa por ejercicio, asignada al contabilizar (sin huecos).
-- =====================================================================

create table conta.asientos (
  id               uuid primary key default gen_random_uuid(),
  empresa_id       uuid not null references conta.empresas(id) on delete cascade,
  ejercicio_id     uuid not null references conta.ejercicios(id),
  numero           integer,                 -- se asigna al contabilizar
  fecha            date not null,
  concepto         text not null,
  documento        text,                    -- nº de factura, recibo…
  tipo             text not null default 'normal'
                   check (tipo in ('apertura', 'normal', 'regularizacion', 'cierre')),
  estado           text not null default 'borrador'
                   check (estado in ('borrador', 'contabilizado')),
  anula_a          uuid references conta.asientos(id),   -- si es un contraasiento
  anulado_por      uuid references conta.asientos(id),   -- si fue anulado
  creado_por       uuid default auth.uid(),
  created_at       timestamptz not null default now(),
  contabilizado_at timestamptz,
  unique (ejercicio_id, numero)
);
create index asientos_empresa_fecha on conta.asientos (empresa_id, fecha);

create table conta.apuntes (
  id                uuid primary key default gen_random_uuid(),
  asiento_id        uuid not null references conta.asientos(id) on delete cascade,
  empresa_id        uuid not null references conta.empresas(id) on delete cascade,
  linea             smallint not null,
  cuenta_id         uuid not null references conta.cuentas(id),
  debe              numeric(15,2) not null default 0 check (debe  >= 0),
  haber             numeric(15,2) not null default 0 check (haber >= 0),
  concepto          text,
  tercero_id        uuid references conta.terceros(id),
  -- Solo en apuntes de cuotas de impuesto (472 / 477): alimentan el libro registro
  impuesto_tipo_id  text references conta.impuestos_tipos(id),
  base_imponible    numeric(15,2),
  -- Cada apunte va al Debe O al Haber, nunca a los dos ni a ninguno
  check ((debe > 0 and haber = 0) or (haber > 0 and debe = 0)),
  unique (asiento_id, linea)
);
create index apuntes_cuenta on conta.apuntes (cuenta_id);
create index apuntes_asiento on conta.apuntes (asiento_id);

-- ---------------------------------------------------------------------
-- Validación de la cabecera: la fecha debe caer en el ejercicio indicado
-- ---------------------------------------------------------------------
create or replace function conta.tg_asiento_validar()
returns trigger language plpgsql as $$
declare
  v_ej conta.ejercicios;
begin
  if tg_op = 'UPDATE' and old.estado = 'contabilizado' then
    -- Único cambio permitido sobre un asiento contabilizado: marcarlo como anulado.
    if (to_jsonb(new) - 'anulado_por') <> (to_jsonb(old) - 'anulado_por')
       or old.anulado_por is not null then
      raise exception 'El asiento % está contabilizado: no se puede modificar. Anúlalo con un contraasiento.', old.numero;
    end if;
    return new;
  end if;

  select * into v_ej from conta.ejercicios where id = new.ejercicio_id;
  if v_ej.empresa_id <> new.empresa_id then
    raise exception 'El ejercicio no pertenece a la empresa del asiento';
  end if;
  if new.fecha not between v_ej.fecha_inicio and v_ej.fecha_fin then
    raise exception 'La fecha % está fuera del ejercicio %', new.fecha, v_ej.anio;
  end if;
  return new;
end $$;

create trigger asiento_validar
  before insert or update on conta.asientos
  for each row execute function conta.tg_asiento_validar();

create or replace function conta.tg_asiento_no_borrar()
returns trigger language plpgsql as $$
begin
  if old.estado = 'contabilizado' and coalesce(current_setting('conta.borrando_empresa', true), '') <> 'on' then
    raise exception 'El asiento % está contabilizado: no se puede borrar. Anúlalo con un contraasiento.', old.numero;
  end if;
  return old;
end $$;

create trigger asiento_no_borrar
  before delete on conta.asientos
  for each row execute function conta.tg_asiento_no_borrar();

-- ---------------------------------------------------------------------
-- Validación de apuntes
-- ---------------------------------------------------------------------
create or replace function conta.tg_apunte_validar()
returns trigger language plpgsql as $$
declare
  v_asiento conta.asientos;
  v_cuenta  conta.cuentas;
begin
  -- 1) El asiento debe estar en borrador (vale para INSERT, UPDATE y DELETE)
  select * into v_asiento from conta.asientos
  where id = case when tg_op = 'DELETE' then old.asiento_id else new.asiento_id end;

  if coalesce(current_setting('conta.borrando_empresa', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  if v_asiento.estado = 'contabilizado' then
    raise exception 'El asiento % está contabilizado: sus apuntes no se pueden tocar', v_asiento.numero;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  -- 2) La empresa del apunte es siempre la del asiento
  new.empresa_id := v_asiento.empresa_id;

  -- 3) La cuenta: de la misma empresa, subcuenta y no bloqueada
  select * into v_cuenta from conta.cuentas where id = new.cuenta_id;
  if v_cuenta.empresa_id <> new.empresa_id then
    raise exception 'La cuenta % no pertenece a esta empresa', v_cuenta.codigo;
  end if;
  if v_cuenta.tipo <> 'auxiliar' then
    raise exception 'La cuenta % (%) es de título: apunta en una subcuenta', v_cuenta.codigo, v_cuenta.nombre;
  end if;
  if v_cuenta.bloqueada then
    raise exception 'La cuenta % está bloqueada', v_cuenta.codigo;
  end if;

  -- 4) Número de línea automático si no se indica
  if new.linea is null then
    select coalesce(max(linea), 0) + 1 into new.linea from conta.apuntes where asiento_id = new.asiento_id;
  end if;
  return new;
end $$;

create trigger apunte_validar
  before insert or update or delete on conta.apuntes
  for each row execute function conta.tg_apunte_validar();

-- ---------------------------------------------------------------------
-- CONTABILIZAR: valida cuadre y periodo, asigna número y bloquea el asiento
-- ---------------------------------------------------------------------
create or replace function conta.contabilizar(p_asiento uuid)
returns integer language plpgsql as $$
declare
  v_a        conta.asientos;
  v_debe     numeric(15,2);
  v_haber    numeric(15,2);
  v_lineas   int;
  v_periodo  conta.periodos;
  v_ej       conta.ejercicios;
  v_numero   int;
begin
  select * into v_a from conta.asientos where id = p_asiento for update;
  if not found then
    raise exception 'Asiento no encontrado (o sin permiso)';
  end if;
  if v_a.estado <> 'borrador' then
    raise exception 'El asiento ya está contabilizado con el número %', v_a.numero;
  end if;

  select coalesce(sum(debe), 0), coalesce(sum(haber), 0), count(*)
  into v_debe, v_haber, v_lineas
  from conta.apuntes where asiento_id = p_asiento;

  if v_lineas < 2 then
    raise exception 'Un asiento necesita al menos 2 apuntes (tiene %)', v_lineas;
  end if;
  if v_debe <> v_haber then
    raise exception 'Asiento descuadrado: Debe % ≠ Haber % (diferencia %)', v_debe, v_haber, v_debe - v_haber;
  end if;

  -- Bloqueo por ejercicio: si dos usuarios contabilizan a la vez, uno espera → numeración sin huecos ni duplicados
  perform pg_advisory_xact_lock(hashtext(v_a.ejercicio_id::text));
  select * into v_ej from conta.ejercicios where id = v_a.ejercicio_id;
  if v_ej.estado <> 'abierto' then
    raise exception 'El ejercicio % está cerrado', v_ej.anio;
  end if;

  select * into v_periodo from conta.periodos
  where ejercicio_id = v_a.ejercicio_id and v_a.fecha between fecha_inicio and fecha_fin;
  if v_periodo.estado <> 'abierto' then
    raise exception 'El periodo % de % está cerrado', v_periodo.numero, v_ej.anio;
  end if;

  select coalesce(max(numero), 0) + 1 into v_numero
  from conta.asientos where ejercicio_id = v_a.ejercicio_id;

  update conta.asientos
  set estado = 'contabilizado', numero = v_numero, contabilizado_at = now()
  where id = p_asiento;

  return v_numero;
end $$;

-- ---------------------------------------------------------------------
-- ANULAR: crea y contabiliza un contraasiento (Debe ↔ Haber). El original se conserva.
-- ---------------------------------------------------------------------
create or replace function conta.anular(p_asiento uuid, p_fecha date default null)
returns integer language plpgsql as $$
declare
  v_a      conta.asientos;
  v_fecha  date;
  v_ej     uuid;
  v_nuevo  uuid;
  v_num    int;
begin
  select * into v_a from conta.asientos where id = p_asiento;
  if not found then raise exception 'Asiento no encontrado (o sin permiso)'; end if;
  if v_a.estado <> 'contabilizado' then
    raise exception 'Solo se anulan asientos contabilizados; un borrador simplemente se borra';
  end if;
  if v_a.anulado_por is not null then raise exception 'El asiento % ya está anulado', v_a.numero; end if;
  if v_a.anula_a is not null then raise exception 'No se anula un contraasiento'; end if;

  v_fecha := coalesce(p_fecha, v_a.fecha);
  select id into v_ej from conta.ejercicios
  where empresa_id = v_a.empresa_id and v_fecha between fecha_inicio and fecha_fin;
  if v_ej is null then raise exception 'No hay ejercicio para la fecha %', v_fecha; end if;

  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, documento, tipo, anula_a)
  values (v_a.empresa_id, v_ej, v_fecha, 'ANULACIÓN asiento ' || v_a.numero || ': ' || v_a.concepto,
          v_a.documento, v_a.tipo, v_a.id)
  returning id into v_nuevo;

  insert into conta.apuntes (asiento_id, empresa_id, linea, cuenta_id, debe, haber, concepto,
                             tercero_id, impuesto_tipo_id, base_imponible)
  select v_nuevo, empresa_id, linea, cuenta_id, haber, debe, concepto,
         tercero_id, impuesto_tipo_id, -base_imponible
  from conta.apuntes where asiento_id = v_a.id;

  v_num := conta.contabilizar(v_nuevo);
  update conta.asientos set anulado_por = v_nuevo where id = v_a.id;
  return v_num;
end $$;

-- ---------------------------------------------------------------------
-- ELIMINAR EMPRESA COMPLETA (solo su admin). Es la única vía para borrar asientos
-- contabilizados: pensado para empresas de práctica que ya no se usan.
-- ---------------------------------------------------------------------
create or replace function conta.eliminar_empresa(p_empresa uuid)
returns void language plpgsql security definer set search_path = conta, public as $$
begin
  if not exists (select 1 from conta.usuarios_empresa
                 where empresa_id = p_empresa and user_id = auth.uid() and rol = 'admin') then
    raise exception 'Solo el administrador de la empresa puede eliminarla';
  end if;
  perform set_config('conta.borrando_empresa', 'on', true);   -- solo dura esta transacción
  delete from conta.empresas where id = p_empresa;
  perform set_config('conta.borrando_empresa', 'off', true);
end $$;
