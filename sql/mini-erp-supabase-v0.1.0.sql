-- Mini ERP v0.1.0 · instalación completa en Supabase (migraciones 0001-0006 en un solo archivo)
-- Pegar entero en Supabase → SQL Editor → Run. Luego: Settings → API → Exposed schemas → añadir 'conta'.

-- >>>>>>>>>> 0001_nucleo.sql
-- =====================================================================
-- 0001 · NÚCLEO: empresas, usuarios por empresa, ejercicios y periodos
-- ---------------------------------------------------------------------
-- Equivalencias:
--   empresas          ≈ BC "Company"              ≈ SAP "Sociedad" (BUKRS, tabla T001)
--   usuarios_empresa  ≈ BC "User Permissions"      ≈ SAP autorizaciones por sociedad
--   ejercicios        ≈ BC "Accounting Periods"    ≈ SAP "Variante de ejercicio"
--   periodos          ≈ BC periodo contable        ≈ SAP periodos (OB52: abrir/cerrar)
-- Todo vive en el schema "conta" para no mezclarse con otras apps del proyecto.
-- =====================================================================

create schema if not exists conta;
comment on schema conta is 'Mini ERP · contabilidad general española (PGC, IVA, IGIC)';

create extension if not exists pgcrypto;  -- gen_random_uuid()

-- ---------------------------------------------------------------------
-- EMPRESAS
-- ---------------------------------------------------------------------
create table conta.empresas (
  id                 uuid primary key default gen_random_uuid(),
  nombre             text not null,
  nif                text,
  sector             text not null
                     check (sector in ('retail', 'industria', 'ecommerce', 'servicios')),
  -- Territorio fiscal de la empresa: decide si repercute IVA o IGIC.
  territorio         text not null
                     check (territorio in ('peninsula', 'canarias')),
  plan_contable      text not null default 'PGC'
                     check (plan_contable in ('PGC', 'PGC_PYMES')),
  -- Longitud fija de las subcuentas (las cuentas donde se apunta). Ej: 8 → 43000001
  digitos_subcuenta  smallint not null default 8 check (digitos_subcuenta between 5 and 12),
  moneda             char(3) not null default 'EUR',
  creado_por         uuid default auth.uid(),
  created_at         timestamptz not null default now()
);
comment on table conta.empresas is 'Sociedades. Cada una tiene su propio plan de cuentas y ejercicios.';

-- ---------------------------------------------------------------------
-- USUARIOS POR EMPRESA (multiusuario)
-- user_id es el id de Supabase Auth (auth.users.id)
-- ---------------------------------------------------------------------
create table conta.usuarios_empresa (
  empresa_id  uuid not null references conta.empresas(id) on delete cascade,
  user_id     uuid not null,
  rol         text not null default 'lectura'
              check (rol in ('admin', 'contable', 'lectura')),
  created_at  timestamptz not null default now(),
  primary key (empresa_id, user_id)
);
comment on table conta.usuarios_empresa is
  'Quién accede a cada empresa. admin: todo · contable: asientos y maestros · lectura: solo consultar.';

-- Quien crea la empresa pasa a ser su admin automáticamente.
-- Si se crea desde el SQL Editor (sin sesión), hay que indicar creado_por.
create or replace function conta.tg_empresa_alta_admin()
returns trigger language plpgsql security definer set search_path = conta, public as $$
begin
  if new.creado_por is null then
    raise exception 'Indica creado_por (id de auth.users) al crear una empresa sin sesión iniciada';
  end if;
  insert into conta.usuarios_empresa (empresa_id, user_id, rol)
  values (new.id, new.creado_por, 'admin');
  return new;
end $$;

create trigger empresa_alta_admin
  after insert on conta.empresas
  for each row execute function conta.tg_empresa_alta_admin();

-- ---------------------------------------------------------------------
-- EJERCICIOS Y PERIODOS
-- ---------------------------------------------------------------------
create table conta.ejercicios (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references conta.empresas(id) on delete cascade,
  anio          smallint not null,
  fecha_inicio  date not null,
  fecha_fin     date not null,
  estado        text not null default 'abierto' check (estado in ('abierto', 'cerrado')),
  unique (empresa_id, anio),
  check (fecha_fin > fecha_inicio)
);

create table conta.periodos (
  ejercicio_id  uuid not null references conta.ejercicios(id) on delete cascade,
  numero        smallint not null check (numero between 1 and 12),
  fecha_inicio  date not null,
  fecha_fin     date not null,
  estado        text not null default 'abierto' check (estado in ('abierto', 'cerrado')),
  primary key (ejercicio_id, numero)
);
comment on table conta.periodos is 'Meses del ejercicio. Un periodo cerrado no admite asientos (como OB52 en SAP).';

-- Crea un ejercicio natural (1 ene – 31 dic) con sus 12 periodos.
create or replace function conta.crear_ejercicio(p_empresa uuid, p_anio int)
returns uuid language plpgsql as $$
declare
  v_id uuid;
  m    int;
begin
  insert into conta.ejercicios (empresa_id, anio, fecha_inicio, fecha_fin)
  values (p_empresa, p_anio, make_date(p_anio, 1, 1), make_date(p_anio, 12, 31))
  returning id into v_id;

  for m in 1..12 loop
    insert into conta.periodos (ejercicio_id, numero, fecha_inicio, fecha_fin)
    values (v_id, m,
            make_date(p_anio, m, 1),
            (make_date(p_anio, m, 1) + interval '1 month - 1 day')::date);
  end loop;
  return v_id;
end $$;

-- >>>>>>>>>> 0002_plan_cuentas_pgc.sql
-- =====================================================================
-- 0002 · PLAN DE CUENTAS (PGC 2007, grupos 1 a 7)
-- ---------------------------------------------------------------------
-- Dos niveles, igual que SAP y BC:
--   pgc_plantilla  ≈ SAP "Plan de cuentas" (SKA1)  → común a todas las empresas
--   cuentas        ≈ SAP cuenta a nivel sociedad (SKB1) ≈ BC "G/L Account"
--
-- Tipos de cuenta (como "Account Type" en BC):
--   titulo    → grupos, subgrupos y cuentas del PGC (1, 2, 3 o 4 dígitos). NO admiten apuntes.
--   auxiliar  → subcuentas de la empresa (ej. 43000001 Cliente X). SOLO aquí se apunta.
--
-- Grupos 8 y 9 (gastos/ingresos imputados al patrimonio neto) quedan para más adelante.
-- =====================================================================

create table conta.pgc_plantilla (
  codigo      text primary key check (codigo ~ '^[0-9]{1,4}$'),
  nombre      text not null,
  nivel       smallint generated always as (length(codigo)) stored,
  grupo       smallint generated always as (left(codigo, 1)::smallint) stored,
  -- Masa patrimonial / naturaleza, útil para balance y PyG:
  naturaleza  text not null default 'mixta'
              check (naturaleza in ('activo', 'pasivo', 'patrimonio_neto', 'gasto', 'ingreso', 'mixta'))
);

create table conta.cuentas (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references conta.empresas(id) on delete cascade,
  codigo      text not null check (codigo ~ '^[0-9]+$'),
  nombre      text not null,
  tipo        text not null check (tipo in ('titulo', 'auxiliar')),
  nivel       smallint generated always as (length(codigo)) stored,
  grupo       smallint generated always as (left(codigo, 1)::smallint) stored,
  -- Cuenta del PGC de la que cuelga (ej. '430' para 43000001)
  cuenta_pgc  text not null,
  naturaleza  text not null,
  bloqueada   boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (empresa_id, codigo)
);
create index cuentas_empresa_codigo on conta.cuentas (empresa_id, codigo text_pattern_ops);

-- ---------------------------------------------------------------------
-- Datos del PGC
-- ---------------------------------------------------------------------
insert into conta.pgc_plantilla (codigo, nombre) values
-- GRUPO 1 ─ FINANCIACIÓN BÁSICA
('1','Financiación básica'),
('10','Capital'),
('100','Capital social'),('101','Fondo social'),('102','Capital'),
('103','Socios por desembolsos no exigidos'),('104','Socios por aportaciones no dinerarias pendientes'),
('108','Acciones o participaciones propias en situaciones especiales'),
('109','Acciones o participaciones propias para reducción de capital'),
('11','Reservas y otros instrumentos de patrimonio'),
('110','Prima de emisión o asunción'),('111','Otros instrumentos de patrimonio neto'),
('112','Reserva legal'),('113','Reservas voluntarias'),('114','Reservas especiales'),
('118','Aportaciones de socios o propietarios'),('119','Diferencias por ajuste del capital a euros'),
('12','Resultados pendientes de aplicación'),
('120','Remanente'),('121','Resultados negativos de ejercicios anteriores'),('129','Resultado del ejercicio'),
('13','Subvenciones, donaciones y ajustes por cambios de valor'),
('130','Subvenciones oficiales de capital'),('131','Donaciones y legados de capital'),
('132','Otras subvenciones, donaciones y legados'),('137','Ingresos fiscales a distribuir en varios ejercicios'),
('14','Provisiones'),
('140','Provisión por retribuciones a largo plazo al personal'),('141','Provisión para impuestos'),
('142','Provisión para otras responsabilidades'),
('143','Provisión por desmantelamiento, retiro o rehabilitación del inmovilizado'),
('145','Provisión para actuaciones medioambientales'),('146','Provisión para reestructuraciones'),
('15','Deudas a largo plazo con características especiales'),
('150','Acciones o participaciones a largo plazo consideradas como pasivos financieros'),
('16','Deudas a largo plazo con partes vinculadas'),
('160','Deudas a largo plazo con entidades de crédito vinculadas'),
('161','Proveedores de inmovilizado a largo plazo, partes vinculadas'),
('162','Acreedores por arrendamiento financiero a largo plazo, partes vinculadas'),
('163','Otras deudas a largo plazo con partes vinculadas'),
('17','Deudas a largo plazo por préstamos recibidos, empréstitos y otros conceptos'),
('170','Deudas a largo plazo con entidades de crédito'),('171','Deudas a largo plazo'),
('172','Deudas a largo plazo transformables en subvenciones, donaciones y legados'),
('173','Proveedores de inmovilizado a largo plazo'),
('174','Acreedores por arrendamiento financiero a largo plazo'),('175','Efectos a pagar a largo plazo'),
('177','Obligaciones y bonos'),
('18','Pasivos por fianzas, garantías y otros conceptos a largo plazo'),
('180','Fianzas recibidas a largo plazo'),
('181','Anticipos recibidos por ventas o prestaciones de servicios a largo plazo'),
('185','Depósitos recibidos a largo plazo'),
-- GRUPO 2 ─ ACTIVO NO CORRIENTE
('2','Activo no corriente'),
('20','Inmovilizaciones intangibles'),
('200','Investigación'),('201','Desarrollo'),('202','Concesiones administrativas'),
('203','Propiedad industrial'),('204','Fondo de comercio'),('205','Derechos de traspaso'),
('206','Aplicaciones informáticas'),('209','Anticipos para inmovilizaciones intangibles'),
('21','Inmovilizaciones materiales'),
('210','Terrenos y bienes naturales'),('211','Construcciones'),('212','Instalaciones técnicas'),
('213','Maquinaria'),('214','Utillaje'),('215','Otras instalaciones'),('216','Mobiliario'),
('217','Equipos para procesos de información'),('218','Elementos de transporte'),
('219','Otro inmovilizado material'),
('22','Inversiones inmobiliarias'),
('220','Inversiones en terrenos y bienes naturales'),('221','Inversiones en construcciones'),
('23','Inmovilizaciones materiales en curso'),
('231','Construcciones en curso'),('232','Instalaciones técnicas en montaje'),
('233','Maquinaria en montaje'),('237','Equipos para procesos de información en montaje'),
('239','Anticipos para inmovilizaciones materiales'),
('24','Inversiones financieras a largo plazo en partes vinculadas'),
('240','Participaciones a largo plazo en partes vinculadas'),
('241','Valores representativos de deuda a largo plazo de partes vinculadas'),
('242','Créditos a largo plazo a partes vinculadas'),
('25','Otras inversiones financieras a largo plazo'),
('250','Inversiones financieras a largo plazo en instrumentos de patrimonio'),
('251','Valores representativos de deuda a largo plazo'),('252','Créditos a largo plazo'),
('253','Créditos a largo plazo por enajenación de inmovilizado'),
('254','Créditos a largo plazo al personal'),('258','Imposiciones a largo plazo'),
('26','Fianzas y depósitos constituidos a largo plazo'),
('260','Fianzas constituidas a largo plazo'),('265','Depósitos constituidos a largo plazo'),
('28','Amortización acumulada del inmovilizado'),
('280','Amortización acumulada del inmovilizado intangible'),
('281','Amortización acumulada del inmovilizado material'),
('282','Amortización acumulada de las inversiones inmobiliarias'),
('29','Deterioro de valor de activos no corrientes'),
('290','Deterioro de valor del inmovilizado intangible'),
('291','Deterioro de valor del inmovilizado material'),
('292','Deterioro de valor de las inversiones inmobiliarias'),
-- GRUPO 3 ─ EXISTENCIAS
('3','Existencias'),
('30','Comerciales'),('300','Mercaderías'),
('31','Materias primas'),('310','Materias primas'),
('32','Otros aprovisionamientos'),
('320','Elementos y conjuntos incorporables'),('321','Combustibles'),('322','Repuestos'),
('325','Materiales diversos'),('326','Embalajes'),('327','Envases'),('328','Material de oficina'),
('33','Productos en curso'),('330','Productos en curso'),
('34','Productos semiterminados'),('340','Productos semiterminados'),
('35','Productos terminados'),('350','Productos terminados'),
('36','Subproductos, residuos y materiales recuperados'),
('360','Subproductos'),('365','Residuos'),('368','Materiales recuperados'),
('39','Deterioro de valor de las existencias'),
('390','Deterioro de valor de las mercaderías'),('391','Deterioro de valor de las materias primas'),
('392','Deterioro de valor de otros aprovisionamientos'),
('393','Deterioro de valor de los productos en curso'),
('394','Deterioro de valor de los productos semiterminados'),
('395','Deterioro de valor de los productos terminados'),
('396','Deterioro de valor de los subproductos, residuos y materiales recuperados'),
-- GRUPO 4 ─ ACREEDORES Y DEUDORES POR OPERACIONES COMERCIALES
('4','Acreedores y deudores por operaciones comerciales'),
('40','Proveedores'),
('400','Proveedores'),('401','Proveedores, efectos comerciales a pagar'),
('403','Proveedores, empresas del grupo'),('404','Proveedores, empresas asociadas'),
('405','Proveedores, otras partes vinculadas'),
('406','Envases y embalajes a devolver a proveedores'),('407','Anticipos a proveedores'),
('41','Acreedores varios'),
('410','Acreedores por prestaciones de servicios'),('411','Acreedores, efectos comerciales a pagar'),
('419','Acreedores por operaciones en común'),
('43','Clientes'),
('430','Clientes'),('431','Clientes, efectos comerciales a cobrar'),
('432','Clientes, operaciones de factoring'),('433','Clientes, empresas del grupo'),
('434','Clientes, empresas asociadas'),('435','Clientes, otras partes vinculadas'),
('436','Clientes de dudoso cobro'),('437','Envases y embalajes a devolver por clientes'),
('438','Anticipos de clientes'),
('44','Deudores varios'),
('440','Deudores'),('441','Deudores, efectos comerciales a cobrar'),
('446','Deudores de dudoso cobro'),('449','Deudores por operaciones en común'),
('46','Personal'),
('460','Anticipos de remuneraciones'),('465','Remuneraciones pendientes de pago'),
('466','Remuneraciones mediante sistemas de aportación definida pendientes de pago'),
('47','Administraciones públicas'),
('470','Hacienda Pública, deudora por diversos conceptos'),
('4700','Hacienda Pública, deudora por IVA'),
('4708','Hacienda Pública, deudora por subvenciones concedidas'),
('4709','Hacienda Pública, deudora por devolución de impuestos'),
('471','Organismos de la Seguridad Social, deudores'),
('472','Hacienda Pública, IVA soportado'),
('473','Hacienda Pública, retenciones y pagos a cuenta'),
('474','Activos por impuesto diferido'),
('475','Hacienda Pública, acreedora por conceptos fiscales'),
('4750','Hacienda Pública, acreedora por IVA'),
('4751','Hacienda Pública, acreedora por retenciones practicadas'),
('4752','Hacienda Pública, acreedora por impuesto sobre sociedades'),
('4758','Hacienda Pública, acreedora por subvenciones a reintegrar'),
('476','Organismos de la Seguridad Social, acreedores'),
('477','Hacienda Pública, IVA repercutido'),
('479','Pasivos por diferencias temporarias imponibles'),
('48','Ajustes por periodificación'),
('480','Gastos anticipados'),('485','Ingresos anticipados'),
('49','Deterioro de valor de créditos comerciales y provisiones a corto plazo'),
('490','Deterioro de valor de créditos por operaciones comerciales'),
('499','Provisiones por operaciones comerciales'),
-- GRUPO 5 ─ CUENTAS FINANCIERAS
('5','Cuentas financieras'),
('52','Deudas a corto plazo por préstamos recibidos y otros conceptos'),
('520','Deudas a corto plazo con entidades de crédito'),
('5200','Préstamos a corto plazo de entidades de crédito'),
('5201','Deudas a corto plazo por crédito dispuesto'),
('5208','Deudas por efectos descontados'),
('521','Deudas a corto plazo'),('523','Proveedores de inmovilizado a corto plazo'),
('524','Acreedores por arrendamiento financiero a corto plazo'),('525','Efectos a pagar a corto plazo'),
('526','Dividendo activo a pagar'),
('527','Intereses a corto plazo de deudas con entidades de crédito'),
('528','Intereses a corto plazo de deudas'),('529','Provisiones a corto plazo'),
('54','Otras inversiones financieras a corto plazo'),
('540','Inversiones financieras a corto plazo en instrumentos de patrimonio'),
('541','Valores representativos de deuda a corto plazo'),('542','Créditos a corto plazo'),
('543','Créditos a corto plazo por enajenación de inmovilizado'),
('544','Créditos a corto plazo al personal'),
('546','Intereses a corto plazo de valores representativos de deudas'),
('547','Intereses a corto plazo de créditos'),('548','Imposiciones a corto plazo'),
('55','Otras cuentas no bancarias'),
('550','Titular de la explotación'),('551','Cuenta corriente con socios y administradores'),
('552','Cuenta corriente con otras personas y entidades vinculadas'),
('555','Partidas pendientes de aplicación'),('557','Dividendo activo a cuenta'),
('558','Socios por desembolsos exigidos'),
('56','Fianzas y depósitos recibidos y constituidos a corto plazo y ajustes por periodificación'),
('560','Fianzas recibidas a corto plazo'),('561','Depósitos recibidos a corto plazo'),
('565','Fianzas constituidas a corto plazo'),('566','Depósitos constituidos a corto plazo'),
('567','Intereses pagados por anticipado'),('568','Intereses cobrados por anticipado'),
('57','Tesorería'),
('570','Caja, euros'),('571','Caja, moneda extranjera'),
('572','Bancos e instituciones de crédito c/c vista, euros'),
('573','Bancos e instituciones de crédito c/c vista, moneda extranjera'),
('574','Bancos e instituciones de crédito, cuentas de ahorro, euros'),
('576','Inversiones a corto plazo de gran liquidez'),
-- GRUPO 6 ─ COMPRAS Y GASTOS
('6','Compras y gastos'),
('60','Compras'),
('600','Compras de mercaderías'),('601','Compras de materias primas'),
('602','Compras de otros aprovisionamientos'),('606','Descuentos sobre compras por pronto pago'),
('607','Trabajos realizados por otras empresas'),
('608','Devoluciones de compras y operaciones similares'),('609','Rappels por compras'),
('61','Variación de existencias'),
('610','Variación de existencias de mercaderías'),('611','Variación de existencias de materias primas'),
('612','Variación de existencias de otros aprovisionamientos'),
('62','Servicios exteriores'),
('620','Gastos en investigación y desarrollo del ejercicio'),('621','Arrendamientos y cánones'),
('622','Reparaciones y conservación'),('623','Servicios de profesionales independientes'),
('624','Transportes'),('625','Primas de seguros'),('626','Servicios bancarios y similares'),
('627','Publicidad, propaganda y relaciones públicas'),('628','Suministros'),('629','Otros servicios'),
('63','Tributos'),
('630','Impuesto sobre beneficios'),('631','Otros tributos'),
('634','Ajustes negativos en la imposición indirecta'),('636','Devolución de impuestos'),
('639','Ajustes positivos en la imposición indirecta'),
('64','Gastos de personal'),
('640','Sueldos y salarios'),('641','Indemnizaciones'),
('642','Seguridad Social a cargo de la empresa'),
('643','Retribuciones a largo plazo mediante sistemas de aportación definida'),
('649','Otros gastos sociales'),
('65','Otros gastos de gestión'),
('650','Pérdidas de créditos comerciales incobrables'),('651','Resultados de operaciones en común'),
('659','Otras pérdidas en gestión corriente'),
('66','Gastos financieros'),
('660','Gastos financieros por actualización de provisiones'),('661','Intereses de obligaciones y bonos'),
('662','Intereses de deudas'),
('663','Pérdidas por valoración de instrumentos financieros por su valor razonable'),
('665','Intereses por descuento de efectos y operaciones de factoring'),
('666','Pérdidas en participaciones y valores representativos de deuda'),
('667','Pérdidas de créditos no comerciales'),('668','Diferencias negativas de cambio'),
('669','Otros gastos financieros'),
('67','Pérdidas procedentes de activos no corrientes y gastos excepcionales'),
('670','Pérdidas procedentes del inmovilizado intangible'),
('671','Pérdidas procedentes del inmovilizado material'),
('672','Pérdidas procedentes de las inversiones inmobiliarias'),
('678','Gastos excepcionales'),
('68','Dotaciones para amortizaciones'),
('680','Amortización del inmovilizado intangible'),('681','Amortización del inmovilizado material'),
('682','Amortización de las inversiones inmobiliarias'),
('69','Pérdidas por deterioro y otras dotaciones'),
('690','Pérdidas por deterioro del inmovilizado intangible'),
('691','Pérdidas por deterioro del inmovilizado material'),
('692','Pérdidas por deterioro de las inversiones inmobiliarias'),
('693','Pérdidas por deterioro de existencias'),
('694','Pérdidas por deterioro de créditos por operaciones comerciales'),
('695','Dotación a la provisión por operaciones comerciales'),
-- GRUPO 7 ─ VENTAS E INGRESOS
('7','Ventas e ingresos'),
('70','Ventas de mercaderías, de producción propia, de servicios, etc.'),
('700','Ventas de mercaderías'),('701','Ventas de productos terminados'),
('702','Ventas de productos semiterminados'),('703','Ventas de subproductos y residuos'),
('704','Ventas de envases y embalajes'),('705','Prestaciones de servicios'),
('706','Descuentos sobre ventas por pronto pago'),
('708','Devoluciones de ventas y operaciones similares'),('709','Rappels sobre ventas'),
('71','Variación de existencias'),
('710','Variación de existencias de productos en curso'),
('711','Variación de existencias de productos semiterminados'),
('712','Variación de existencias de productos terminados'),
('713','Variación de existencias de subproductos, residuos y materiales recuperados'),
('73','Trabajos realizados para la empresa'),
('730','Trabajos realizados para el inmovilizado intangible'),
('731','Trabajos realizados para el inmovilizado material'),
('732','Trabajos realizados en inversiones inmobiliarias'),
('733','Trabajos realizados para el inmovilizado material en curso'),
('74','Subvenciones, donaciones y legados'),
('740','Subvenciones, donaciones y legados a la explotación'),
('746','Subvenciones, donaciones y legados de capital transferidos al resultado del ejercicio'),
('747','Otras subvenciones, donaciones y legados transferidos al resultado del ejercicio'),
('75','Otros ingresos de gestión'),
('751','Resultados de operaciones en común'),('752','Ingresos por arrendamientos'),
('753','Ingresos de propiedad industrial cedida en explotación'),('754','Ingresos por comisiones'),
('755','Ingresos por servicios al personal'),('759','Ingresos por servicios diversos'),
('76','Ingresos financieros'),
('760','Ingresos de participaciones en instrumentos de patrimonio'),
('761','Ingresos de valores representativos de deuda'),('762','Ingresos de créditos'),
('763','Beneficios por valoración de instrumentos financieros por su valor razonable'),
('766','Beneficios en participaciones y valores representativos de deuda'),
('768','Diferencias positivas de cambio'),('769','Otros ingresos financieros'),
('77','Beneficios procedentes de activos no corrientes e ingresos excepcionales'),
('770','Beneficios procedentes del inmovilizado intangible'),
('771','Beneficios procedentes del inmovilizado material'),
('772','Beneficios procedentes de las inversiones inmobiliarias'),
('778','Ingresos excepcionales'),
('79','Excesos y aplicaciones de provisiones y de pérdidas por deterioro'),
('790','Reversión del deterioro del inmovilizado intangible'),
('791','Reversión del deterioro del inmovilizado material'),
('792','Reversión del deterioro de las inversiones inmobiliarias'),
('793','Reversión del deterioro de existencias'),
('794','Reversión del deterioro de créditos por operaciones comerciales'),
('795','Exceso de provisiones');

-- Naturaleza de cada cuenta (qué masa patrimonial es)
update conta.pgc_plantilla set naturaleza = case
  when codigo = '1'                               then 'mixta'
  when codigo ~ '^1[0-3]'                         then 'patrimonio_neto'
  when codigo ~ '^1'                              then 'pasivo'
  when codigo ~ '^[23]'                           then 'activo'   -- 28x, 29x, 39x: correctoras de activo
  when codigo ~ '^(40|41|475|476|477|479|485|499)' then 'pasivo'
  when codigo ~ '^(43|44|460|470|471|472|473|474|480|490)' then 'activo'
  when codigo ~ '^(465|466)'                      then 'pasivo'
  when codigo ~ '^(52|560|561|568)'               then 'pasivo'
  when codigo ~ '^(54|57|565|566|567)'            then 'activo'
  when codigo ~ '^6'                              then 'gasto'
  when codigo ~ '^7'                              then 'ingreso'
  else 'mixta'                                    -- grupos/subgrupos 4, 5, 47, 55, 56…
end;

-- ---------------------------------------------------------------------
-- Al crear una empresa se copia el PGC como cuentas "titulo"
-- ---------------------------------------------------------------------
create or replace function conta.tg_empresa_copiar_pgc()
returns trigger language plpgsql security definer set search_path = conta, public as $$
begin
  insert into conta.cuentas (empresa_id, codigo, nombre, tipo, cuenta_pgc, naturaleza)
  select new.id, p.codigo, p.nombre, 'titulo', p.codigo, p.naturaleza
  from conta.pgc_plantilla p;
  return new;
end $$;

create trigger empresa_copiar_pgc
  after insert on conta.empresas
  for each row execute function conta.tg_empresa_copiar_pgc();

-- ---------------------------------------------------------------------
-- Alta de subcuentas: comprueba longitud y cuelga de la cuenta PGC más larga que sea prefijo.
-- Ej (8 dígitos): 43000001 → 430 · 47510001 → 4751 · 57200001 → 572
-- ---------------------------------------------------------------------
create or replace function conta.tg_cuenta_validar()
returns trigger language plpgsql as $$
declare
  v_digitos smallint;
  v_padre   conta.pgc_plantilla;
begin
  if new.tipo = 'titulo' then
    return new;  -- las copia el sistema desde la plantilla
  end if;

  select digitos_subcuenta into v_digitos from conta.empresas where id = new.empresa_id;
  if length(new.codigo) <> v_digitos then
    raise exception 'La subcuenta % debe tener % dígitos', new.codigo, v_digitos;
  end if;

  select * into v_padre
  from conta.pgc_plantilla
  where new.codigo like codigo || '%' and nivel >= 3
  order by nivel desc
  limit 1;

  if v_padre is null then
    raise exception 'La subcuenta % no cuelga de ninguna cuenta del PGC (3 o 4 dígitos)', new.codigo;
  end if;

  new.cuenta_pgc := v_padre.codigo;
  new.naturaleza := v_padre.naturaleza;
  return new;
end $$;

create trigger cuenta_validar
  before insert or update of codigo, tipo on conta.cuentas
  for each row execute function conta.tg_cuenta_validar();

-- Atajo: crea una subcuenta y devuelve su id
create or replace function conta.crear_subcuenta(p_empresa uuid, p_codigo text, p_nombre text)
returns uuid language sql as $$
  insert into conta.cuentas (empresa_id, codigo, nombre, tipo, cuenta_pgc, naturaleza)
  values (p_empresa, p_codigo, p_nombre, 'auxiliar', '', '')   -- el trigger rellena cuenta_pgc y naturaleza
  returning id;
$$;

-- >>>>>>>>>> 0003_terceros_impuestos.sql
-- =====================================================================
-- 0003 · TERCEROS E IMPUESTOS (catálogo IVA / IGIC)
-- ---------------------------------------------------------------------
-- Equivalencias:
--   terceros          ≈ BC "Customer" / "Vendor"   ≈ SAP deudores (KNA1) / acreedores (LFA1)
--   impuestos_tipos   ≈ BC "VAT Product Posting Group" + % ≈ SAP "Indicador de IVA" (MWSKZ)
--
-- Fase 1: catálogo de tipos con vigencia + cada apunte puede llevar su tipo y base imponible
--         → de ahí sale el libro registro de IVA/IGIC.
-- Fase 3: matriz completa (territorio empresa × territorio tercero × categoría) con
--         cálculo automático de cuotas, recargo de equivalencia y retenciones IRPF.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TERCEROS (clientes, proveedores, acreedores, deudores)
-- ---------------------------------------------------------------------
create table conta.terceros (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references conta.empresas(id) on delete cascade,
  tipo        text not null check (tipo in ('cliente', 'proveedor', 'acreedor', 'deudor')),
  nif         text,
  nombre      text not null,
  -- Dónde está el tercero: junto con el territorio de la empresa decide el impuesto.
  -- Ej: empresa canaria que vende a cliente peninsular → exportación, sin IGIC.
  territorio  text not null default 'peninsula'
              check (territorio in ('peninsula', 'canarias', 'ceuta_melilla', 'ue', 'extranjero')),
  -- Subcuenta contable del tercero (ej. 43000001)
  cuenta_id   uuid references conta.cuentas(id),
  created_at  timestamptz not null default now()
);
create index terceros_empresa on conta.terceros (empresa_id);

-- ---------------------------------------------------------------------
-- TIPOS DE IMPUESTO con fechas de vigencia (los tipos cambian por ley:
-- nunca se escriben fijos en el código).
-- ⚠ Revisar contra la normativa vigente antes de usarlos en serio.
--   Los porcentajes son los de 2026; algunas fechas "vigente_desde" antiguas son orientativas.
-- ---------------------------------------------------------------------
create table conta.impuestos_tipos (
  id                    text primary key,       -- ej. 'IVA21', 'IGIC7'
  impuesto              text not null check (impuesto in ('IVA', 'IGIC')),
  categoria             text not null,          -- general, reducido, superreducido…
  porcentaje            numeric(5,2) not null check (porcentaje >= 0),
  -- Recargo de equivalencia (solo IVA, comercio minorista persona física)
  recargo_equivalencia  numeric(5,2),
  vigente_desde         date not null,
  vigente_hasta         date,
  descripcion           text
);

insert into conta.impuestos_tipos
  (id, impuesto, categoria, porcentaje, recargo_equivalencia, vigente_desde, descripcion) values
-- IVA · Península y Baleares (Ley 37/1992)
('IVA21', 'IVA', 'general',        21.00, 5.20, '2012-09-01', 'Tipo general'),
('IVA10', 'IVA', 'reducido',       10.00, 1.40, '2012-09-01', 'Hostelería, transporte de viajeros, ciertos alimentos…'),
('IVA4',  'IVA', 'superreducido',   4.00, 0.50, '1995-01-01', 'Pan, leche, libros, medicamentos…'),
('IVA0',  'IVA', 'exento',          0.00, null, '1993-01-01', 'Operaciones exentas o no sujetas'),
-- IGIC · Canarias (texto refundido, Decreto Legislativo 1/2025)
('IGIC0',   'IGIC', 'cero',                   0.00, null, '2012-01-01', 'Tipo cero: bienes y servicios enumerados'),
('IGIC1',   'IGIC', 'especifico',             1.00, null, '2026-01-01', 'Petróleo y derivados del refino (nuevo en 2026)'),
('IGIC3',   'IGIC', 'superreducido',          3.00, null, '2012-01-01', 'Bienes de primera necesidad enumerados'),
('IGIC5',   'IGIC', 'reducido',               5.00, null, '2012-01-01', 'Bienes enumerados (p. ej. ciertos refrescos)'),
('IGIC7',   'IGIC', 'general',                7.00, null, '2012-07-01', 'Tipo general'),
('IGIC9_5', 'IGIC', 'incrementado',           9.50, null, '2012-01-01', 'Bienes enumerados'),
('IGIC15',  'IGIC', 'incrementado_especial', 15.00, null, '2012-01-01', 'Bienes enumerados (p. ej. bebidas energéticas)'),
('IGIC20',  'IGIC', 'especial',              20.00, null, '2012-01-01', 'Labores del tabaco');

comment on table conta.impuestos_tipos is
  'Catálogo global de tipos IVA/IGIC con vigencia. Verificar siempre contra la normativa vigente.';

-- >>>>>>>>>> 0004_asientos.sql
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

-- >>>>>>>>>> 0005_informes.sql
-- =====================================================================
-- 0005 · INFORMES: libro diario, libro mayor, sumas y saldos, libro registro IVA/IGIC
-- ---------------------------------------------------------------------
-- Solo cuentan los asientos CONTABILIZADOS. Los borradores no existen para los informes.
-- Las vistas usan security_invoker: cada usuario solo ve lo que le permite RLS.
-- =====================================================================

-- ---------------------------------------------------------------------
-- LIBRO DIARIO: asientos en orden cronológico, con sus apuntes
-- ---------------------------------------------------------------------
create or replace view conta.v_libro_diario with (security_invoker = true) as
select a.empresa_id,
       e.anio          as ejercicio,
       a.numero,
       a.fecha,
       a.concepto      as concepto_asiento,
       a.documento,
       a.tipo,
       p.linea,
       c.codigo        as cuenta,
       c.nombre        as nombre_cuenta,
       p.debe,
       p.haber,
       coalesce(p.concepto, a.concepto) as concepto,
       a.id            as asiento_id
from conta.asientos a
join conta.ejercicios e on e.id = a.ejercicio_id
join conta.apuntes   p on p.asiento_id = a.id
join conta.cuentas   c on c.id = p.cuenta_id
where a.estado = 'contabilizado';

-- ---------------------------------------------------------------------
-- LIBRO MAYOR: movimientos de cada subcuenta con saldo acumulado
-- (saldo positivo = deudor, negativo = acreedor)
-- ---------------------------------------------------------------------
create or replace view conta.v_libro_mayor with (security_invoker = true) as
select a.empresa_id,
       e.anio          as ejercicio,
       c.codigo        as cuenta,
       c.nombre        as nombre_cuenta,
       a.fecha,
       a.numero,
       coalesce(p.concepto, a.concepto) as concepto,
       p.debe,
       p.haber,
       sum(p.debe - p.haber) over (
         partition by p.cuenta_id, a.ejercicio_id
         order by a.fecha, a.numero, p.linea
         rows between unbounded preceding and current row
       ) as saldo
from conta.asientos a
join conta.ejercicios e on e.id = a.ejercicio_id
join conta.apuntes   p on p.asiento_id = a.id
join conta.cuentas   c on c.id = p.cuenta_id
where a.estado = 'contabilizado';

-- ---------------------------------------------------------------------
-- BALANCE DE SUMAS Y SALDOS
--   p_nivel: 1 = grupo, 2 = subgrupo, 3 = cuenta, null = subcuenta
--   p_hasta: fecha de corte (por defecto, todo el ejercicio)
-- Uso: select * from conta.sumas_saldos('<empresa>', 2026, 3);
-- ---------------------------------------------------------------------
create or replace function conta.sumas_saldos(
  p_empresa uuid, p_anio int, p_nivel int default null, p_hasta date default null)
returns table (cuenta text, nombre text, suma_debe numeric, suma_haber numeric,
               saldo_deudor numeric, saldo_acreedor numeric)
language sql stable as $$
  with mov as (
    select case when p_nivel is null then c.codigo else left(c.codigo, p_nivel) end as cuenta,
           p.debe, p.haber
    from conta.apuntes p
    join conta.asientos   a on a.id = p.asiento_id
    join conta.ejercicios e on e.id = a.ejercicio_id
    join conta.cuentas    c on c.id = p.cuenta_id
    where a.empresa_id = p_empresa
      and e.anio = p_anio
      and a.estado = 'contabilizado'
      and (p_hasta is null or a.fecha <= p_hasta)
  )
  select m.cuenta,
         c.nombre,
         sum(m.debe),
         sum(m.haber),
         greatest(sum(m.debe) - sum(m.haber), 0),
         greatest(sum(m.haber) - sum(m.debe), 0)
  from mov m
  left join conta.cuentas c on c.empresa_id = p_empresa and c.codigo = m.cuenta
  group by m.cuenta, c.nombre
  order by m.cuenta;
$$;

-- ---------------------------------------------------------------------
-- LIBRO REGISTRO DE IVA / IGIC
-- Sale de los apuntes de cuotas (cuentas 472 soportado / 477 repercutido)
-- que llevan tipo de impuesto y base imponible.
-- ---------------------------------------------------------------------
create or replace view conta.v_libro_impuestos with (security_invoker = true) as
select a.empresa_id,
       e.anio         as ejercicio,
       a.fecha,
       a.numero       as asiento,
       a.documento,
       case c.cuenta_pgc when '472' then 'soportado' when '477' then 'repercutido' end as clase,
       t.impuesto,
       t.porcentaje,
       tr.nif,
       tr.nombre      as tercero,
       p.base_imponible,
       case c.cuenta_pgc when '472' then p.debe - p.haber else p.haber - p.debe end as cuota
from conta.apuntes p
join conta.asientos         a  on a.id = p.asiento_id
join conta.ejercicios       e  on e.id = a.ejercicio_id
join conta.cuentas          c  on c.id = p.cuenta_id
join conta.impuestos_tipos  t  on t.id = p.impuesto_tipo_id
left join conta.terceros    tr on tr.id = p.tercero_id
where a.estado = 'contabilizado'
  and c.cuenta_pgc in ('472', '477');

-- >>>>>>>>>> 0006_seguridad_rls.sql
-- =====================================================================
-- 0006 · SEGURIDAD: permisos y Row Level Security (multiusuario)
-- ---------------------------------------------------------------------
-- Idea: cada fila lleva empresa_id; un usuario solo ve/toca las empresas
-- en las que figura en usuarios_empresa, según su rol:
--   lectura   → consultar
--   contable  → + cuentas, terceros y asientos
--   admin     → + ejercicios, periodos, usuarios y la propia empresa
-- En SAP esto serían objetos de autorización por sociedad; en BC, permission sets.
-- =====================================================================

-- Rol del usuario actual en una empresa (null si no tiene acceso).
-- security definer: consulta usuarios_empresa sin quedar atrapada en su propia RLS.
create or replace function conta.mi_rol(p_empresa uuid)
returns text language sql stable security definer set search_path = conta, public as $$
  select rol from conta.usuarios_empresa where empresa_id = p_empresa and user_id = auth.uid();
$$;

create or replace function conta.puede_leer(p_empresa uuid)
returns boolean language sql stable as $$ select conta.mi_rol(p_empresa) is not null $$;

create or replace function conta.puede_escribir(p_empresa uuid)
returns boolean language sql stable as $$ select conta.mi_rol(p_empresa) in ('admin', 'contable') $$;

create or replace function conta.es_admin(p_empresa uuid)
returns boolean language sql stable as $$ select conta.mi_rol(p_empresa) = 'admin' $$;

create or replace function conta.empresa_de_ejercicio(p_ejercicio uuid)
returns uuid language sql stable security definer set search_path = conta, public as $$
  select empresa_id from conta.ejercicios where id = p_ejercicio;
$$;

-- ---------------------------------------------------------------------
-- Activar RLS en todas las tablas
-- ---------------------------------------------------------------------
alter table conta.empresas         enable row level security;
alter table conta.usuarios_empresa enable row level security;
alter table conta.ejercicios       enable row level security;
alter table conta.periodos         enable row level security;
alter table conta.pgc_plantilla    enable row level security;
alter table conta.cuentas          enable row level security;
alter table conta.terceros         enable row level security;
alter table conta.impuestos_tipos  enable row level security;
alter table conta.asientos         enable row level security;
alter table conta.apuntes          enable row level security;

-- Catálogos globales: todos los usuarios con sesión los leen, nadie los modifica desde la web
create policy leer on conta.pgc_plantilla   for select to authenticated using (true);
create policy leer on conta.impuestos_tipos for select to authenticated using (true);

-- Empresas (creado_por en el SELECT: permite leer la fila recién creada en el mismo INSERT … RETURNING)
create policy leer     on conta.empresas for select to authenticated
  using (conta.puede_leer(id) or creado_por = auth.uid());
create policy crear    on conta.empresas for insert to authenticated with check (creado_por = auth.uid());
create policy editar   on conta.empresas for update to authenticated
  using (conta.es_admin(id)) with check (conta.es_admin(id));
create policy borrar   on conta.empresas for delete to authenticated using (conta.es_admin(id));

-- Usuarios por empresa: los miembros ven al equipo; solo el admin lo gestiona
create policy leer     on conta.usuarios_empresa for select to authenticated using (conta.puede_leer(empresa_id));
create policy gestionar on conta.usuarios_empresa for all to authenticated
  using (conta.es_admin(empresa_id)) with check (conta.es_admin(empresa_id));

-- Ejercicios y periodos: leer miembros, gestionar admin
create policy leer      on conta.ejercicios for select to authenticated using (conta.puede_leer(empresa_id));
create policy gestionar on conta.ejercicios for all to authenticated
  using (conta.es_admin(empresa_id)) with check (conta.es_admin(empresa_id));

create policy leer      on conta.periodos for select to authenticated
  using (conta.puede_leer(conta.empresa_de_ejercicio(ejercicio_id)));
create policy gestionar on conta.periodos for all to authenticated
  using (conta.es_admin(conta.empresa_de_ejercicio(ejercicio_id)))
  with check (conta.es_admin(conta.empresa_de_ejercicio(ejercicio_id)));

-- Cuentas, terceros, asientos y apuntes: leer miembros, escribir admin y contable
create policy leer     on conta.cuentas  for select to authenticated using (conta.puede_leer(empresa_id));
create policy escribir on conta.cuentas  for all to authenticated
  using (conta.puede_escribir(empresa_id)) with check (conta.puede_escribir(empresa_id));

create policy leer     on conta.terceros for select to authenticated using (conta.puede_leer(empresa_id));
create policy escribir on conta.terceros for all to authenticated
  using (conta.puede_escribir(empresa_id)) with check (conta.puede_escribir(empresa_id));

create policy leer     on conta.asientos for select to authenticated using (conta.puede_leer(empresa_id));
create policy escribir on conta.asientos for all to authenticated
  using (conta.puede_escribir(empresa_id)) with check (conta.puede_escribir(empresa_id));

create policy leer     on conta.apuntes  for select to authenticated using (conta.puede_leer(empresa_id));
create policy escribir on conta.apuntes  for all to authenticated
  using (conta.puede_escribir(empresa_id)) with check (conta.puede_escribir(empresa_id));

-- ---------------------------------------------------------------------
-- Permisos de la API (Supabase usa los roles anon y authenticated)
-- anon (sin sesión) no ve NADA del ERP.
-- ---------------------------------------------------------------------
revoke all on schema conta from anon, public;
revoke all on all tables in schema conta from anon, public;
revoke execute on all functions in schema conta from anon, public;

grant usage on schema conta to authenticated;
grant select on all tables in schema conta to authenticated;
grant insert, update, delete on
  conta.empresas, conta.usuarios_empresa, conta.ejercicios, conta.periodos,
  conta.cuentas, conta.terceros, conta.asientos, conta.apuntes
  to authenticated;
grant execute on all functions in schema conta to authenticated;
