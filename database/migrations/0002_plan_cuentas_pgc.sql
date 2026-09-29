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
