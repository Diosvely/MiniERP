-- =====================================================================
-- DATOS DE EJEMPLO (opcional) · dos empresas para comparar IGIC e IVA
--   A) Demo Asesoría Canarias SL  → servicios · Canarias  · IGIC + retención IRPF
--   B) Demo Tienda Península SL   → retail    · Península · IVA
--
-- Se ejecuta en el SQL Editor de Supabase DESPUÉS de las migraciones.
-- Asigna las empresas al primer usuario registrado en Authentication → Users
-- (regístrate antes en tu web o créalo en el panel de Supabase).
--
-- Convención de subcuentas (8 dígitos) para impuestos:
--   4720xxxx IVA soportado    4721xxxx IGIC soportado     (xx = tipo: 21, 10, 07…)
--   4770xxxx IVA repercutido  4771xxxx IGIC repercutido
-- =====================================================================
do $$
declare
  v_user uuid := (select id from auth.users order by created_at limit 1);
  e uuid; ej uuid; a uuid; t_cli uuid; t_prov uuid;
begin
  if v_user is null then
    raise exception 'No hay usuarios en auth.users: crea uno antes de cargar la demo';
  end if;

  -- ═════════════ A) CANARIAS · SERVICIOS · IGIC ═════════════
  insert into conta.empresas (nombre, nif, sector, territorio, creado_por)
  values ('Demo Asesoría Canarias SL', 'B35000001', 'servicios', 'canarias', v_user)
  returning id into e;
  ej := conta.crear_ejercicio(e, 2026);

  perform conta.crear_subcuenta(e, s.codigo, s.nombre)
  from (values ('10000001','Capital social'),
               ('57200001','Banco c/c'),
               ('43000001','Cliente Hotel Atlántico SL'),
               ('41000001','Acreedor Gestoría Martín'),
               ('62300001','Servicios de profesionales independientes'),
               ('70500001','Prestación de servicios de asesoría'),
               ('47210007','IGIC soportado 7%'),
               ('47710007','IGIC repercutido 7%'),
               ('47510001','HP acreedora por retenciones IRPF profesionales')) as s(codigo, nombre);

  insert into conta.terceros (empresa_id, tipo, nif, nombre, territorio, cuenta_id)
  values (e, 'cliente', 'B35999999', 'Hotel Atlántico SL', 'canarias',
          (select id from conta.cuentas where empresa_id = e and codigo = '43000001'))
  returning id into t_cli;
  insert into conta.terceros (empresa_id, tipo, nif, nombre, territorio, cuenta_id)
  values (e, 'acreedor', '42000000X', 'Gestoría Martín', 'canarias',
          (select id from conta.cuentas where empresa_id = e and codigo = '41000001'))
  returning id into t_prov;

  -- 1. Constitución: aportación de capital al banco
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, tipo)
  values (e, ej, '2026-01-02', 'Constitución de la sociedad', 'apertura') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe, haber)
  select a, (select id from conta.cuentas where empresa_id = e and codigo = x.cod), x.d, x.h
  from (values ('57200001', 3000, 0), ('10000001', 0, 3000)) as x(cod, d, h);
  perform conta.contabilizar(a);

  -- 2. Factura de un profesional: IGIC soportado 7% y retención IRPF 15%
  --    500 + 35 IGIC − 75 retención = 460 a pagar
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, documento)
  values (e, ej, '2026-01-20', 'Factura gestoría enero', 'GM-2026-01') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe, haber, tercero_id, impuesto_tipo_id, base_imponible)
  select a, (select id from conta.cuentas where empresa_id = e and codigo = x.cod), x.d, x.h,
         t_prov, x.imp, x.base
  from (values ('62300001', 500, 0, null, null),
               ('47210007',  35, 0, 'IGIC7', 500),
               ('47510001',   0, 75, null, null),
               ('41000001',   0, 460, null, null)) as x(cod, d, h, imp, base);
  perform conta.contabilizar(a);

  -- 3. Factura de venta: IGIC repercutido 7%
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, documento)
  values (e, ej, '2026-01-31', 'Factura asesoría enero', 'F-2026-001') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe, haber, tercero_id, impuesto_tipo_id, base_imponible)
  select a, (select id from conta.cuentas where empresa_id = e and codigo = x.cod), x.d, x.h,
         t_cli, x.imp, x.base
  from (values ('43000001', 1070, 0, null, null),
               ('70500001', 0, 1000, null, null),
               ('47710007', 0,   70, 'IGIC7', 1000)) as x(cod, d, h, imp, base);
  perform conta.contabilizar(a);

  -- 4. Cobro de la factura
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, documento)
  values (e, ej, '2026-02-15', 'Cobro F-2026-001', 'F-2026-001') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe, haber, tercero_id)
  select a, (select id from conta.cuentas where empresa_id = e and codigo = x.cod), x.d, x.h, t_cli
  from (values ('57200001', 1070, 0), ('43000001', 0, 1070)) as x(cod, d, h);
  perform conta.contabilizar(a);

  -- ═════════════ B) PENÍNSULA · RETAIL · IVA ═════════════
  insert into conta.empresas (nombre, nif, sector, territorio, creado_por)
  values ('Demo Tienda Península SL', 'B28000002', 'retail', 'peninsula', v_user)
  returning id into e;
  ej := conta.crear_ejercicio(e, 2026);

  perform conta.crear_subcuenta(e, s.codigo, s.nombre)
  from (values ('10000001','Capital social'),
               ('57200001','Banco c/c'),
               ('43000001','Clientes contado'),
               ('40000001','Proveedor Distribuciones Norte SA'),
               ('60000001','Compras de mercaderías'),
               ('70000001','Ventas de mercaderías'),
               ('47200021','IVA soportado 21%'),
               ('47700021','IVA repercutido 21%')) as s(codigo, nombre);

  insert into conta.terceros (empresa_id, tipo, nif, nombre, territorio, cuenta_id)
  values (e, 'proveedor', 'A28888888', 'Distribuciones Norte SA', 'peninsula',
          (select id from conta.cuentas where empresa_id = e and codigo = '40000001'))
  returning id into t_prov;

  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, tipo)
  values (e, ej, '2026-01-02', 'Constitución de la sociedad', 'apertura') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe, haber)
  select a, (select id from conta.cuentas where empresa_id = e and codigo = x.cod), x.d, x.h
  from (values ('57200001', 5000, 0), ('10000001', 0, 5000)) as x(cod, d, h);
  perform conta.contabilizar(a);

  -- Compra de mercaderías con IVA 21%
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, documento)
  values (e, ej, '2026-01-10', 'Compra mercaderías', 'DN-1450') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe, haber, tercero_id, impuesto_tipo_id, base_imponible)
  select a, (select id from conta.cuentas where empresa_id = e and codigo = x.cod), x.d, x.h,
         t_prov, x.imp, x.base
  from (values ('60000001', 1000, 0, null, null),
               ('47200021',  210, 0, 'IVA21', 1000),
               ('40000001', 0, 1210, null, null)) as x(cod, d, h, imp, base);
  perform conta.contabilizar(a);

  -- Ventas de contado de la semana con IVA 21%
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, documento)
  values (e, ej, '2026-01-17', 'Ventas de caja semana 3', 'Z-003') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe, haber, impuesto_tipo_id, base_imponible)
  select a, (select id from conta.cuentas where empresa_id = e and codigo = x.cod), x.d, x.h, x.imp, x.base
  from (values ('57200001', 1815, 0, null, null),
               ('70000001', 0, 1500, null, null),
               ('47700021', 0,  315, 'IVA21', 1500)) as x(cod, d, h, imp, base);
  perform conta.contabilizar(a);

  -- Pago al proveedor
  insert into conta.asientos (empresa_id, ejercicio_id, fecha, concepto, documento)
  values (e, ej, '2026-02-10', 'Pago DN-1450', 'DN-1450') returning id into a;
  insert into conta.apuntes (asiento_id, cuenta_id, debe, haber, tercero_id)
  select a, (select id from conta.cuentas where empresa_id = e and codigo = x.cod), x.d, x.h, t_prov
  from (values ('40000001', 1210, 0), ('57200001', 0, 1210)) as x(cod, d, h);
  perform conta.contabilizar(a);

  raise notice 'Demo cargada: 2 empresas con 4 asientos cada una, asignadas al usuario %', v_user;
end $$;
