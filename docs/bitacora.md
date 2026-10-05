# Bitácora del proyecto

Diario del proceso: qué se hizo, qué se aprendió y qué queda pendiente. Una entrada por sesión de trabajo.

---

## 2026-09-29 · Arranque del repositorio

- Se crea el repositorio Git desde el primer minuto, con la estructura de carpetas documentada en el README.
- Decisión de infraestructura: base de datos en un **schema `conta` dentro de un proyecto Supabase existente**
  (ver `docs/decisiones/0001-infraestructura.md`).

## 2026-09-29 · v0.1.0 · Base de datos contable

**Qué se hizo**
- 6 migraciones SQL en `database/migrations/` (núcleo, PGC, terceros/impuestos, asientos, informes, seguridad).
- Pruebas automáticas (`database/tests/test_fase1.sql`) ejecutadas en PostgreSQL 16 local: 31 comprobaciones OK.
- Datos de ejemplo con dos empresas para comparar IGIC (Canarias, servicios) e IVA (Península, retail).

**Lo que se aprende en esta fase**
- Plan de cuentas en dos niveles (plantilla PGC + cuentas de la empresa), como SAP (SKA1/SKB1) y BC.
- Cuentas de título (no admiten apuntes) frente a subcuentas (donde se apunta).
- Por qué un asiento contabilizado no se borra: se anula con un contraasiento y ambos quedan en el diario.
- El PGC solo nombra el IVA en 472/477: el IGIC usa esas cuentas con subcuentas propias (4721…, 4771…).
- Una factura de profesional en Canarias: gasto + IGIC soportado − retención IRPF (4751) = total a pagar.

**Decisiones**: ADR 0001 (infraestructura) y ADR 0002 (asientos) en `docs/decisiones/`.

**Siguiente paso**: ejecutar las migraciones en Supabase y empezar el frontend (v0.2.0).


## 2026-09-29 · Instalación en Supabase
   - Ejecutadas las migraciones 0001–0006 en Supabase.
   - Schema `conta` expuesto en la Data API.
   - Repositorio gestionado desde VS Code y publicado en GitHub.
   
## 2026-09-30 · Base de datos en inglés (schema erp)
   - Nombres técnicos en inglés al estilo BC / SAP, comentarios en español (ADR 0003).
   - Reset en Supabase: borrado `conta`, ejecutadas 0001–0006 de `erp`, expuesto `erp` en la Data API.
   - Comprobado: 11 tablas con RLS, 352 cuentas con nombre en inglés, 12 tipos IVA/IGIC.
   - Aprendido: `git switch -c` crea una rama; `git switch` solo cambia a una que ya existe.
   
## 2026-09-30 · Primera pantalla web (bilingüe)
- Frontend React + Vite en /frontend, conectado a Supabase (schema erp).
- Login con correo y contraseña, listado y alta de empresas (copia PGC + ejercicio automáticos).
- Interfaz en español / inglés con diccionarios en src/i18n; idioma guardado por usuario en erp.user_settings.
- Probado: registro, alta de empresa (352 cuentas, 12 periodos) y el idioma se mantiene al volver a entrar.
- Aprendido: componentes y Context de React, variables VITE_ en .env.local, merge entre ramas.

## 2026-09-30 · Web publicada en Cloudflare Pages
- Producción: https://minierp-6ty.pages.dev (se publica sola con cada push a main).
- Root directory = frontend; variables VITE_SUPABASE_URL / VITE_SUPABASE_KEY en Cloudflare.
- Supabase Auth: Site URL y Redirect URLs configuradas (producción, ramas y localhost).
- Probado en el móvil: mismo usuario, mismo idioma y mismas empresas que en el ordenador.


## 2026-09-30 · Primeros asientos desde la web
- Pantalla de empresa con pestañas: Nuevo asiento · Libro diario · Cuentas.
- Alta de subcuentas validada por la base de datos (longitud y cuenta PGC madre).
- Formulario de asiento con cuadre en vivo, cálculo en céntimos, botón "=" y contabilización con post_entry().
- Libro diario desde la vista v_general_journal, bilingüe y con formato de importes por idioma.
- Probado: constitución (572/100) y factura con IGIC (430/705/477).
- Aprendido: organizar en carpeta components/, props y comunicación padre-hijo en React.
  Error típico: crear un archivo fuera de src (Vite no lo encuentra).
  
## 2026-10-01 · Empresas demo y límites por usuario (v0.4.0)
- Migración 0007: perfiles de aplicación (owner sin límite / member con 1 empresa) y empresas demo.
- Una empresa demo la lee cualquier usuario registrado; solo sus miembros la editan (RLS).
- El límite de empresas y la publicación como demo se controlan con un trigger en la base de datos.
- Web: listas "Mis empresas" / "Empresas de demostración", etiqueta DEMO, modo solo lectura,
  botón "Publicar como demo" (solo owner) y aviso de límite.
- Probado con un segundo usuario en ventana de incógnito.
- Aprendido: perfiles de aplicación frente a roles por empresa; redefinir una función (can_read)
  cambia la seguridad de todas las tablas que la usan

## 2026-10-02 · Importación de subcuentas desde CSV (v0.5.0)
- Migración 0008: función import_posting_accounts(empresa, filas, dry_run).
  Vista previa (dry_run) → valida cada fila sin guardar; importación real → todo o nada.
  Estados: nueva / actualiza (renombra) / error (longitud, sin cuenta PGC, duplicada, sin nombre, letras).
- Web: csv.js reutilizable (BOM de Excel, ; o , como separador, UTF-8 o Windows-1252) y pantalla
  de importación con plantilla descargable.
- Probado con el plan de Agrícola del Sur: 62 subcuentas importadas, errores detectados y reimportación.
- Referencia ERP: crear o actualizar como los Configuration Packages de Business Central;
  validación previa y todo o nada como el Migration Cockpit de SAP.
  
 ## 2026-10-03 · v0.6.0 · J1 Terceros

**Qué se hizo**
- Migración `0009_partners.sql`: ficha de tercero ampliada (email, dirección, país, bloqueado),
  validación de NIF/NIE/CIF con letra o dígito de control, alta con subcuenta automática o vinculada,
  control de duplicados por NIF + tipo, vínculo automático apunte → tercero y vista `v_partners` con saldo.
- Pantalla **Terceros** (ES/EN): alta, filtros por tipo, búsqueda y saldo deudor/acreedor.
- Pruebas: `test_fase4_partners.sql` (11 comprobaciones) y pruebas manuales en la web.

**Lo que se aprende en esta fase**
- Cliente 430 (actividad principal), proveedor 400 (mercaderías, grupo 60),
  acreedor 410 (servicios, grupo 62) y deudor 440 (operaciones ajenas a la actividad).
- Subcuenta por tercero (A3, Sage, ContaPlus) frente a la cuenta colectiva con detalle aparte
  (BC posting groups, SAP reconciliation account).
- Un mismo NIF puede ser cliente y proveedor; dos veces cliente, no (duplicaría saldos y el modelo 347).
- Solo los asientos contabilizados mueven saldos; los borradores no.

**Decisiones**: ADR 0005 (registro de facturas desde contabilidad, modelo gestoría).

**Siguiente paso**: J2 · configuración de impuestos (cuentas 472/477 por tipo de IVA/IGIC).

## 2026-10-04 · v0.7.0 · J2 Configuración de impuestos

**Qué se hizo**
- Migración `0010_tax_setup.sql`: tablas `tax_setup` (subcuenta 472/477 por tipo) y
  `tax_settlement_setup` (4750/4700 por impuesto), asistente `setup_taxes`, vínculo automático
  apunte → tipo de impuesto y vistas para la web.
- Reglas contables en la base de datos: soportado solo en 472, repercutido en 477,
  liquidación en 4750 / 4700; un tipo en uso no puede quedarse sin cuentas.
- Corrección de seguridad: `can_write` e `is_admin` devuelven siempre true/false (nunca null).
- Pantalla **Impuestos** (ES/EN), solo editable por el administrador de la empresa.
- Pruebas: `test_fase5_taxes.sql` (14 comprobaciones) y pruebas manuales en la web.

**Lo que se aprende en esta fase**
- El IVA/IGIC no es gasto ni ingreso: el soportado (472) es un derecho frente a Hacienda
  y el repercutido (477) una deuda.
- Liquidación trimestral: 477 − 472 → 4750 si sale a pagar · 4700 si sale a devolver o compensar.
- Una subcuenta por tipo (4721xxxx IGIC, 4720xxxx IVA): el mayor ya separa las cuotas por tipo.
- Equivalencias: BC VAT Posting Setup · SAP OB40 · tabla de tipos de A3 / Sage / ContaPlus.

**Decisiones**: ADR 0006 (configuración de impuestos).

**Siguiente paso**: J3 · registro de facturas recibidas y emitidas.

## 2026-10-05 · v0.8.0 · J3 Registro de facturas

**Qué se hizo**
- Migración `0011_invoices.sql`: facturas recibidas y emitidas (normales y rectificativas) con su asiento
  contabilizado, libro registro por tipo de impuesto y numeración correlativa sin huecos
  (F / R emitidas · C / CR nº de registro de recibidas).
- Motor único en la base de datos: `preview_invoice` (vista previa sin guardar) y `post_invoice` (todo o nada).
- Controles: factura duplicada del proveedor, rectificativa con factura de origen, cuentas por grupo
  (compras 6/2 · ventas 7), tercero del tipo correcto, tipo de impuesto configurado, fechas y total negativo.
- Facturas inmutables: se corrigen con rectificativa; su asiento no se puede anular suelto.
- Pantalla **Facturas** (ES/EN): Recibidas / Emitidas, "Ver asiento" obligatorio antes de registrar.
- Pruebas: `test_fase6_invoices.sql` (24 comprobaciones) y pruebas manuales en la web.

**Lo que se aprende en esta fase**
- Regla del lado: la base de una compra va al Debe y la de una venta al Haber; la cuota va al mismo lado
  que su base; el tercero, al contrario por el total.
- Las cuentas 606/608/609 y 706/708/709 restan: van al lado contrario y reducen también la cuota.
- La rectificativa invierte todo y reduce el IVA/IGIC deducido o repercutido.
- La cuota se calcula por factura y tipo (no línea a línea) y el 0 % / exento va igualmente al libro registro.

**Decisiones**: ADR 0005 (registro de facturas desde contabilidad), fase A completada.

**Siguiente paso**: J4 · liquidación trimestral (477 − 472 → 4750 / 4700) y borradores de los modelos 420 / 303.

## 2026-10-05 · v0.9.0 · J4 Liquidación trimestral de IVA / IGIC

**Qué se hizo**
- Migración `0012_tax_settlement.sql`: borrador del modelo 303 / 420 por tipo, liquidación con asiento
  (477 − 472 → 4750 / 4700), compensación automática de cuotas de periodos anteriores, devolución en el 4T,
  bloqueo del trimestre liquidado y "deshacer" la última liquidación con contraasiento.
- Control auditor: cuadre libro registro ↔ saldo de las 472/477; si no cuadra hay que aceptarlo
  expresamente y la diferencia queda guardada.
- Pantalla **Liquidación** (ES/EN).
- Pruebas: `test_fase7_settlement.sql` (14 comprobaciones) y empresa de prueba con 1T a compensar y 2T a ingresar.
- Incidencia de Git: los PR de v0.6.0–v0.8.0 solo llevaron el frontend (`git add .` desde `frontend`);
  corregido con un commit `chore` desde la raíz. Desde ahora: `git add -A` desde la raíz.

**Lo que se aprende en esta fase**
- El IVA/IGIC soportado y repercutido se saldan cada trimestre; la diferencia es una deuda (4750)
  o un derecho (4700) frente a Hacienda.
- Un resultado negativo se compensa en los trimestres siguientes; la devolución se pide en el último periodo.
- Lo que se declara sale del libro registro; si la contabilidad no coincide hay asientos manuales que revisar.
- Un trimestre declarado no se toca: la factura que llega tarde se registra en el periodo siguiente.

**Decisiones**: ADR 0007 (liquidación trimestral).

**Siguiente paso**: decidir entre J5 (casos especiales de IVA/IGIC) o el bloque I (mayor, sumas y saldos y saldos anómalos).

## 2026-10-05 · v0.10.0 · Bloque I · Informes y saldos anómalos

**Qué se hizo**
- Migración `0013_balance_rules.sql`: catálogo de naturaleza de saldos por prefijo PGC (~70 reglas con
  reclasificación, gravedad y explicación ES/EN), informe `balance_anomalies` y bloqueo opcional de saldo
  inverso por subcuenta (caja 570/571 bloqueada por defecto).
- Pantalla **Informes** (ES/EN): sumas y saldos por nivel y fecha de corte, libro mayor con saldo D/H
  y drill-down, y listado de saldos anómalos.
- Pruebas: `test_fase8_balances.sql` y pruebas manuales (banco en descubierto, caja bloqueada).

**Lo que se aprende en esta fase**
- Naturaleza del saldo: activos y gastos deudores; patrimonio, pasivos e ingresos acreedores;
  las correctoras (28, 29, 39, 49, 59, 606/608/609, 706/708/709) al revés.
- Un saldo inverso no siempre es error, pero se revisa y se reclasifica al cierre:
  572 → 5201 · 430 → 438 · 400 → 407 · 4750 ↔ 4700. La caja acreedora es imposible.
- El PGC no permite compensar activos con pasivos: un descubierto es una deuda, no un banco negativo.

**Decisiones**: ADR 0008 (naturaleza de saldos).

**Siguiente paso**: J5 · casos especiales de IVA/IGIC.

## 2026-10-05 · v0.11.0 · K1 Menú por áreas

**Qué se hizo**
- Navegación de la empresa reorganizada en 5 áreas: Contabilidad · Facturas · Impuestos · Informes ·
  Datos maestros (antes, 8 pestañas en fila).
- Ordenador: barra lateral fija y ruta "Área › Pantalla"; móvil: botón ☰ con menú desplegable.
- Recuerda la última pantalla abierta de cada empresa; las pantallas de escritura se ocultan en solo lectura.
- Textos de ayuda actualizados ("pestaña X" → "Área › Pantalla").

**Lo que se aprende en esta fase**
- Los ERP organizan la navegación por áreas funcionales: Role Center de Business Central,
  Launchpad de SAP Fiori, menús de A3 / Sage. "Datos maestros" (master data) agrupa lo que no es movimiento:
  plan de cuentas y terceros.

**Siguiente paso**: K2 · libro diario con rango de fechas y anulación de asientos.