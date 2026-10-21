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

## 2026-10-05 · v0.12.0 · K2 Libro diario con rango de fechas y anulación de asientos

**Qué se hizo**
- Migración `0014_journal_reverse.sql`: `reverse_entry` con fecha y motivo de anulación, permisos,
  fecha no anterior al original y bloqueo para asientos de liquidación (las facturas ya lo estaban).
- `v_general_journal` con origen del asiento (manual, factura, liquidación, anulación) y enlaces
  "anula al nº" / "anulado por el nº".
- Libro diario con filtro desde/hasta, búsqueda (concepto, documento, nº, cuenta), totales del filtro
  y botón "Anular asiento" con confirmación en dos pasos.
- Pruebas: `test_fase9_reverse.sql` y pruebas manuales (anulación de un cargo duplicado del banco).

**Lo que se aprende en esta fase**
- El diario no se altera: un error se corrige con un contraasiento enlazado (BC Reverse Transaction,
  SAP FB08, A3 Anular asiento), con fecha y motivo para la pista de auditoría.
- Cada operación se corrige por su circuito: asiento manual → anulación · factura → rectificativa ·
  liquidación → deshacer liquidación.
- Si el periodo original está cerrado, la anulación se fecha en el primer periodo abierto.

**Siguiente paso**: K3 · acceso a las empresas demo sin registrarse.


## 2026-10-06 · v0.13.0 · K3 Acceso a las demos sin registrarse

**Qué se hizo**
- Migración `0015_guest_access.sql`: los usuarios anónimos de Supabase son "invitados" (`is_anonymous`),
  con perfil `guest`, 0 empresas y `can_write` / `is_admin` siempre falsos; solo leen las empresas demo.
- Supabase: activados los "anonymous sign-ins" (después de la migración, nunca antes).
- Web: botón "Ver la demo sin registrarme", enlace directo `/?demo`, aviso de solo lectura
  y tarjeta "Compartir la demo" para el propietario.
- Pruebas: `test_fase10_guest.sql` (el invitado ve la demo, no ve las privadas y no puede escribir nada).

**Lo que se aprende en esta fase**
- Las empresas demo de los ERP (CRONUS en Business Central, IDES en SAP) se exploran sin tocar datos reales.
- La seguridad se decide en la base de datos: la pantalla solo oculta botones.
- El orden de despliegue importa: primero las reglas, después se abre la puerta.

**Decisiones**: ADR 0009 (acceso de invitados).

**Siguiente paso**: J5 · casos especiales de IVA/IGIC.

## 2026-10-06 · v0.13.1 · Detalles de UX y documentación

**Qué se hizo**
- `docs/guia-git.md`: guía de Git en formato plantilla (ciclo rama → commit → pull request → etiqueta,
  nombres de ramas, mensajes, versiones y problemas frecuentes). Sustituye a la carpeta `Codigo GIT`.
- Selector de idioma con bandera (SVG, porque Windows no muestra los emojis de banderas).
- Cabeceras de área del menú en banda gris no pulsable, como las secciones de navegación de BC / SAP Fiori.
- README actualizado a la v0.13.1.

**Lo que se aprende en esta fase**
- Documentar el proceso (Git incluido) es parte del proyecto: cualquiera puede repetirlo sin preguntar.
- En navegación, lo que agrupa no debe parecer un botón.

**Siguiente paso**: J5 · casos especiales de IVA/IGIC.

## 2026-10-06 · v0.14.0 · Bloque L Balance de situación y Pérdidas y Ganancias

**Qué se hizo**
- Migración `0016_financial_statements.sql`: estructura de los modelos PYMES del PGC (partidas ES/EN y
  jerarquía) y clasificación de cuentas por prefijo con doble destino según el saldo de cada subcuenta.
- `financial_statement` (importes del año y del anterior), `fs_line_accounts` (cuentas de cada partida).
- Pantallas: Informes › Balance de situación y Pérdidas y ganancias, con cuadre, fecha de corte,
  drill-down y negativos entre paréntesis.
- Importes con separador de miles siempre (2.900,00).
- Pruebas: `test_fase11_statements.sql` (balance cuadrado, saldos inversos en su masa, PyG y año anterior).

**Lo que se aprende en esta fase**
- El PGC prohíbe compensar: cada subcuenta va a su partida según su saldo (banco en descubierto al pasivo,
  anticipo de cliente a otros acreedores, anticipo a proveedor en existencias).
- Mientras no se cierra el ejercicio, el resultado (grupos 6 y 7) forma parte del patrimonio neto:
  el "D) Resultado del ejercicio" de la PyG es el "VII. Resultado del ejercicio" del balance.
- Los estados solo leen el diario: sirven igual para asientos manuales, facturas o diarios importados.

**Decisiones**: ADR 0010 (visión: laboratorio de práctica) y ADR 0011 (estados financieros e importación).

**Siguiente paso**: cierre del ejercicio (regularización, cierre y apertura).


## 2026-10-06 · v0.15.0 · Bloque M Cierre del ejercicio

**Qué se hizo**
- Migración `0017_year_closing.sql`: asistente de cierre (`year_closing_preview`, `close_fiscal_year`,
  `reopen_fiscal_year`) y tabla `year_closings` con el historial de cierres.
- Cuatro pasos: comprobaciones, regularización (6 y 7 contra la 129) a 31/12, cierre de las cuentas de balance
  a 31/12 y apertura del año siguiente a 01/01. El ejercicio queda cerrado.
- Reapertura con contraasientos, del año más reciente al más antiguo.
- Bloqueos: no se contabiliza en un año cerrado, el estado no se cambia a mano, los asientos del cierre
  no se anulan desde el diario y solo el administrador cierra.
- Balance y PyG excluyen regularización y cierre: se ven igual antes y después de cerrar.
- Pantalla Contabilidad › Cierre del ejercicio, y etiqueta 🔒 Cierre en el libro diario.
- Pruebas: `test_fase12_closing.sql`.

**Lo que se aprende en esta fase**
- La regularización convierte el resultado de la PyG en una cuenta de patrimonio neto, la 129.
- El cierre y la apertura son el mismo asiento con Debe y Haber cambiados: el balance final de un año
  es el balance inicial del siguiente (principio de uniformidad y continuidad).
- La 129 abre con el resultado pendiente de aplicar; la junta decide su destino (reservas, dividendos o la 121).
- Un ejercicio cerrado no se toca: si aparece un ajuste, se reabre y la traza queda en el diario.

**Decisiones**: ADR 0012 (cierre del ejercicio).

**Siguiente paso**: Modo auditor (importación de diarios, estado de flujos de efectivo y ratios).

## 2026-10-07 · v0.16.0 · Bloque J5 (parte 1) Retención IRPF y operaciones sin cuota

**Qué se hizo**
- Migración `0018_withholding_exempt.sql`:
  - tipos sin cuota con su causa del libro registro / SII: E1 exenta art. 20, E2 exportación,
    E5 entrega intracomunitaria y N2 no sujeta (IVA e IGIC);
  - reglas del motor de facturas: exportación e intracomunitaria solo en ventas; intracomunitaria solo a clientes
    de la UE; exportación y no sujeta solo con terceros de fuera del territorio de la empresa;
  - retenciones IRPF (15 %, 7 % y 19 %): 4751 en compras (modelos 111 / 115) y 473 en ventas;
    el tercero queda por base + cuota − retención;
  - configuración automática de las retenciones al configurar el IVA / IGIC (también en las empresas existentes);
  - `v_withholding_register` y `withholding_summary` (resumen trimestral por modelo).
- Factura: selector de retención, líquido a pagar / cobrar, tipos sin cuota con su causa y aviso de tercero de otro territorio.
- Nueva pantalla Impuestos › Retenciones IRPF (borrador de los modelos 111 y 115, soportadas y detalle por factura).
- Pruebas: `test_fase13_withholding.sql` (y recuentos actualizados en las fases 5 y 10).

**Lo que se aprende en esta fase**
- La retención se calcula sobre la base, nunca sobre el IVA o el IGIC; no es un gasto, es un impuesto del proveedor
  que la empresa adelanta a Hacienda.
- Las ventas desde la Península a Canarias son exportaciones (Canarias está fuera del territorio del IVA),
  y las de Canarias a la Península son exportaciones a efectos del IGIC.
- Una venta de bienes a otro país de la UE no es una exportación: es una entrega intracomunitaria.
- Exenta y no sujeta no son lo mismo: la exenta es una operación sujeta al impuesto que la ley libera;
  la no sujeta queda fuera porque, según las reglas de localización, no ocurre en el territorio.

**Decisiones**: ADR 0013 (retenciones y causas de exención).

**Siguiente paso**: J5 parte 2: inversión del sujeto pasivo y recargo de equivalencia.

## 2026-10-07 · v0.17.0 · Bloque J5 (parte 2) Inversión del sujeto pasivo y recargo de equivalencia

**Qué se hizo**
- Migración `0019_reverse_charge_surcharge.sql`:
  - tipos nuevos: adquisición intracomunitaria (VAT21/10/4_AIB), inversión del sujeto pasivo (VAT21/10_ISP, IGIC7_ISP)
    y venta del minorista en recargo (VAT_RE_INC);
  - subcuentas propias que se crean solas: 472/477 …8… (AIB), …9… (ISP) y 4770 7… (recargo repercutido);
  - régimen de IVA de la empresa (general / recargo de equivalencia, solo en la Península) y marca "cliente en recargo";
  - motor de facturas: ISP y AIB (472 Debe = 477 Haber, el proveedor cobra solo la base); venta a cliente en recargo
    (IVA + recargo); compra del minorista (IVA y recargo no deducibles a la cuenta del gasto);
  - liquidación 303/420: el ISP devenga y deduce, el recargo se ingresa, lo no deducible no cuenta; el cuadre se mantiene.
- Web: régimen de IVA en Impuestos, cliente en recargo en Terceros (insignia RE), totales de la factura con recargo
  y autorrepercutido, y casillas del borrador con recargo e ISP.
- Pruebas: `test_fase14_reverse_charge.sql` (y recuentos actualizados en las fases 5 y 10).

**Lo que se aprende en esta fase**
- En la inversión del sujeto pasivo el impuesto lo declara quien compra: se lo repercute (477) y se lo soporta (472).
  Si es deducible, el efecto es cero, pero queda declarado: así Hacienda controla las operaciones con el extranjero y las obras.
- Una compra de bienes a la UE no es una importación: es una adquisición intracomunitaria, y no hay aduana.
- El recargo de equivalencia traslada al mayorista la recaudación del IVA del minorista: el minorista paga más,   no deduce nada y a


## 2026-10-07 · v0.18.0 · Bloque J5 (parte 3) Prorrata general

**Qué se hizo**
- Migración `0020_pro_rata.sql`:
  - tabla `pro_rata` (empresa, impuesto, año, provisional, definitiva, ajuste y asiento);
  - motor de facturas: con prorrata, la cuota de las compras se reparte entre la 472 (parte deducible)
    y la cuenta de la compra (parte no deducible); en el ISP se devenga entera y se deduce el porcentaje;
  - libro registro con lo deducido de cada tipo (`deductible_amount`) y relleno de las facturas existentes;
  - `pro_rata_calc` y `post_pro_rata_regularization`: definitiva = con derecho / total, redondeada a la unidad
    superior; ajuste a 31/12 con 6341 / 6391 contra la 472; la definitiva pasa a ser la provisional del año siguiente;
  - la liquidación del 4T incluye la casilla de regularización de la prorrata y mantiene el cuadre.
- Nueva pantalla Impuestos › Prorrata (provisional, cálculo de la definitiva, asiento y historial).
- Pruebas: `test_fase15_pro_rata.sql`.

**Lo que se aprende en esta fase**
- Prorrata = operaciones con derecho a deducir / total de operaciones; las exentas del art. 20 no dan derecho.
- Durante el año se deduce con la provisional (la definitiva del año anterior) y en el 4T se ajusta a la real.
- El IVA no deducible no es un impuesto aparte: es más coste de lo que se compra.
- Un redondeo a la unidad superior a favor del contribuyente (60,004 % → 61 %) también es una regla que hay que conocer.

**Bloque J5 completo**: retenciones, operaciones sin cuota, ISP, adquisiciones intracomunitarias,
recargo de equivalencia y prorrata.

**Decisiones**: ADR 0015 (prorrata).

**Siguiente paso**: Modo auditor (importación de diarios, estado de flujos de efectivo y ratios).

## 2026-10-08 · v0.19.0 · Modo auditor (parte 1) Importación de diarios

**Qué se hizo**
- Migración `0021_journal_import.sql`:
  - lotes de importación (`import_batches`) y filas temporales (`import_lines`) con la plantilla del laboratorio;
  - `import_start` (empresa nueva con los dígitos del fichero), `import_preview` (controles de auditor),
    `import_prepare` (ejercicios y subcuentas), `import_post_month` (contabiliza un mes en bloque)
    e `import_finish` (cierra un ejercicio por llamada: con los asientos del fichero o con nuestro asistente);
  - 10 cuentas del PGC que faltaban en la plantilla (633, 638, 644, 259, 293, 297, 598, 673, 796, 799);
  - sumas y saldos y saldos anómalos sin el asiento de cierre (opción "excluir cierre").
- Web: convertidores Sage, Dynamics 365 Business Central y plantilla (`importers.js`) y pantalla Importar diario.
- Probado con 4 diarios reales (330.000 apuntes, 2019–2024): resultados y balances iguales a los del ERP de origen.
- Pruebas: `test_fase16_import.sql` (con datos inventados).

**Lo que se aprende en esta fase**
- Cada ERP exporta distinto: Sage trae aperturas, regularizaciones y cierres; Business Central solo la regularización,
  porque arrastra los saldos sin asientos de cierre ni de apertura.
- Controles de auditor al recibir una contabilidad: cuadre por asiento, importes negativos, cuentas fuera del PGC
  y, sobre todo, que cada apertura coincida con el cierre anterior (en un diario real apareció una reclasificación
  de 7.000 € hecha directamente en la apertura).
- Un saldo inverso histórico (caja acreedora) no se corrige al importar: se documenta.

**Decisiones**: ADR 0016 (importación de diarios).

**Siguiente paso**: estado de flujos de efectivo (método directo e indirecto).

## 2026-10-08 · v0.20.0 · Estado de flujos de efectivo (directo e indirecto)

**Qué se hizo**
- Migración `0022_cash_flow.sql`:
  - catálogo de líneas del EFE (`cf_lines`: modelo normal del PGC y NIC 7);
  - clasificación de cuentas (`cf_mapping`);
  - funciones `cash_flow_statement`, `cf_line_accounts` y `cash_flow_check`.
- Pantalla **Informes › Flujos de efectivo**:
  - pestañas Indirecto / Directo, con la columna del año anterior y detalle por cuentas;
  - banda de cuadre con la 57;
  - comparación por actividades y los asientos que explican la diferencia.
- Prueba `test_fase17_cash_flow.sql` con datos inventados: préstamo, compra, amortización y venta con beneficio
  de un inmovilizado, nómina, intereses, impuesto, dividendo y ampliación de capital. Pasan las 17 fases.
- **Validado con las 4 contabilidades reales**, 11 ejercicios: directo = indirecto = variación de la 57 en todos.

**Lo que se aprende en esta fase**
- Por qué los dos métodos dan el mismo total: cada asiento cuadra, así que lo que no es 57 explica la 57.
- El indirecto mira **variaciones de saldo**; el directo mira **cobros y pagos**. Por actividades solo difieren
  por los asientos sin dinero que mezclan actividades.
- La importancia de la **523 "Proveedores de inmovilizado"**:
  - Empresa 3 compró inmovilizado a proveedores normales, y por eso el directo no ve inversión (0 €) donde el
    indirecto ve (7.011,19 €).
  - Empresa 2 paga proveedores con la póliza de crédito: es explotación para el indirecto y financiación para
    el directo.
- La línea 1 del indirecto es el **resultado antes de impuestos**. El impuesto (630) va al punto 4 por lo
  realmente pagado (4752).
- El EFE explica la caja, no el resultado. Una empresa con beneficio puede quedarse sin efectivo
  (Empresa 1 en 2022: −799.190,42 €).

**Decisiones:** ADR del estado de flujos de efectivo en `docs/decisiones/`.

**Siguiente paso:** Modo auditor 3, ratios (liquidez, solvencia, endeudamiento, rentabilidad, PMC y PMP).


## 2026-10-08 · v0.21.0 · Ratios financieros (Modo auditor completo)

**Qué se hizo**
- Migración `0023_financial_ratios.sql`:
  - catálogo `ratio_defs` con 21 ratios en 5 grupos, cada uno con fórmula, explicación y zona de referencia (es / en);
  - función `financial_ratios`, que devuelve el valor, el año anterior, el numerador, el denominador y la valoración.
- Pantalla **Informes › Ratios**:
  - una tarjeta por grupo, con semáforo y evolución frente al año anterior;
  - al pulsar un ratio, la fórmula con los importes reales, la zona de referencia y su significado.
- Prueba `test_fase18_ratios.sql`: cada ratio esperado está calculado a mano a partir del balance de la empresa
  de prueba. Pasan las 18 fases.
- Validado con las 4 contabilidades reales (11 ejercicios).

**Lo que se aprende en esta fase**
- **Liquidez:**
  - fondo de maniobra, liquidez general, prueba ácida y disponibilidad;
  - por qué las existencias separan la liquidez general de la prueba ácida (Empresa 3: 1,99 frente a 0,54,
    con 342 días de existencias).
- **Endeudamiento:** endeudamiento, autonomía y garantía son la misma información vista desde tres lados.
- **Rentabilidad:**
  - ROA ≈ margen × rotación;
  - Empresa 1 gana por **rotación** (3,9 veces su activo, con un margen del 2 %);
  - el ROE sube con la deuda si el ROA supera el coste de la deuda (apalancamiento).
- **Periodos medios:** la Ley 15/2010 fija 60 días entre empresas. Empresa 2 cobra a 71 días; BC paga a 139.
- **Calidad del resultado** (flujo de explotación / beneficio): mide si el beneficio llega al banco.
  BC tuvo beneficio en 2023, pero su flujo de explotación fue de −247.118 €.
- Un ratio fuera de la zona de referencia es una **pregunta**, no una conclusión: depende del sector.

**Decisiones:** ADR de los ratios financieros en `docs/decisiones/`.

**Siguiente paso:** según el plan, el **Inmovilizado**: fichas de activos, plan de amortización y asiento resumen
mensual a contabilidad, como el módulo de Activos Fijos de BC o AA de SAP.

## 2026-10-08 · v0.22.0 · Analista IA (Cloudflare Workers AI, open source)

**Qué se hizo**
- Migración `0024_ai_context.sql`:
  - `can_use_ai()`, que permite usar la IA solo al owner;
  - `ai_context(empresa, año, idioma)`: resumen compacto con el balance, la PyG, el EFE, el cuadre del auditor y
    los ratios, redondeados y con `lower_is_safer`;
  - corrección de los ratios: calidad del resultado y ROE sin valor con pérdidas o con patrimonio neto negativo.
- **Pages Function `frontend/functions/api/ai.js`**:
  - usa la sesión del usuario y el binding `AI` de Workers AI (sin claves);
  - modelo Mistral Small 3.1, que se puede cambiar con `AI_MODEL`;
  - instrucciones de auditor en español e inglés y respuesta en JSON.
- Botón **Analizar con IA** en Informes › Ratios y en Flujos de efectivo, con resumen, fortalezas, alertas,
  preguntas del auditor y "Para aprender".
- Configuración en Cloudflare: binding `AI` en **Production y Preview**. Ojo: el selector de entorno está arriba
  a la derecha, y los bindings solo se aplican a los despliegues nuevos.
- Prueba `test_fase19_ai_context.sql`: quién puede usarla, qué recibe la IA (nunca el nombre ni los conceptos)
  y el caso con pérdidas. Pasan las 19 fases.

**Lo que se aprende en esta fase**
- Cómo integrar IA en un ERP sin perder el control: los cálculos en la base de datos y la interpretación en el modelo.
- Con datos reales, la IA no inventó cifras, pero una mala definición nuestra la llevó a una conclusión falsa:
  "calidad del resultado buena" con pérdidas y caja negativa. **Un ratio con dos negativos puede engañar**,
  y eso vale también para un analista humano.
- "Fuera de la zona de referencia" no siempre significa "malo": un endeudamiento bajo es menos riesgo.
- Cloudflare Pages Functions: carpeta `functions/`, bindings por entorno y redespliegue tras configurar.

**Decisiones:** ADR del Analista IA en `docs/decisiones/`.

**Siguiente paso:** módulo de **Inmovilizado** (fichas, plan de amortización y asiento mensual a contabilidad).
Después, inventario y nóminas.


## 2026-10-09 · v0.23.0 · Tutor de asientos con IA

**Qué se hizo**
- Migración `0025_entry_tutor.sql`:
  - tabla `valuation_rules` con las 23 NRV;
  - `entry_tutor_context`: el PGC, los impuestos vigentes, las retenciones y las NRV (sin datos de la empresa);
  - `validate_proposed_entry`: subcuentas, tercero, impuesto calculado por el ERP y cuadre.
- Migración `0026_tutor_checks.sql`:
  - **reglas de criterio** (la misma cuenta en los dos lados, amortización ↔ elemento, baja de inmovilizado,
    523 sin inmovilizado y NRV que no encaja);
  - cuentas **2800–2806 y 2811–2819** del PGC.
- Función **`/api/tutor`**:
  - modelo `gpt-oss-120b`, con Mistral Small de respaldo;
  - guía de cuentas en las instrucciones;
  - segunda vuelta cuando el ERP encuentra errores o avisos de criterio.
- Pantalla **Contabilidad › Asiento**: el cuadro "Describe la operación", con la propuesta, los supuestos, la NRV,
  el porqué de cada línea, las comprobaciones del ERP, una pregunta de repaso y **Cargar en el asiento** (crea las
  subcuentas nuevas y rellena el formulario sin contabilizar).
- Mensaje claro cuando falta ejecutar una migración en Supabase, en lugar de "no tienes permiso".
- Pruebas: la fase 20, con 13 casos. Pasan las 20 fases.

**Lo que se aprende en esta fase**
- **Cuadrar no es estar bien.** El primer intento de la furgoneta cuadraba (24.680 = 24.680), pero tenía una pérdida
  de 7.000 € en lugar de un beneficio de 3.000 €.
- **Baja de inmovilizado:**
  - se abona el elemento por su **coste** (218 por 20.000);
  - se carga **su** amortización acumulada (2818 por 15.000);
  - precio de venta − valor neto contable = resultado: 8.000 − 5.000 = **3.000 de beneficio en la 771**.
- **400, 410 y 523:** la 400 es para mercaderías y materias, la 410 para servicios (abogados, suministros) y la
  523 / 173 solo para inmovilizado.
- **La retención** del profesional se calcula sobre la base, sin el impuesto, y va a la 4751 (modelo 111).
- **No todo tiene NRV:** un gasto corriente de servicios no tiene una norma de valoración específica.
- **El modelo importa:** con las mismas reglas, Mistral Small acertó 1 de 3 y gpt-oss-120b, 3 de 3.

**Decisiones:** ADR del Tutor de asientos en `docs/decisiones/`.

**Siguiente paso:** v0.24.0 "Accesos y titulares de datos" (el rol *Miembro* para quien cede su dataset, con publicación de su demo y, quizá, el Analista IA en su empresa). Después, el módulo de Inmovilizado.

## 2026-10-10 · v0.24.0 · Accesos y titulares de los datos (Miembro)

**Qué se hizo**
- Migración `0027_members.sql`:
  - `company_users.data_owner` (el titular de los datos) y `companies.data_credit` (la mención de la demo);
  - `grant_company_access`, `revoke_company_access` y `company_access` (solo el owner, por email);
  - `set_company_demo`, para que el owner o el titular publiquen con su mención;
  - IA para el owner y el titular: `ai_allowed`, `ai_status` y `ai_consume`, con cuota diaria de 10
    (`app_profiles.ai_daily_limit`);
  - `ai_feedback`: opiniones sobre las respuestas de la IA.
- `/api/ai` y `/api/tutor` gastan una consulta de la cuota antes de llamar al modelo; la segunda vuelta del tutor
  no cuenta aparte.
- Pantallas:
  - **Datos maestros › Accesos** (solo el owner): usuarios, roles, consultas de IA de hoy y el buzón de opiniones;
  - aviso para el titular;
  - **Publicar como demo** con mención y aceptación;
  - "¿Es correcta esta respuesta?" en el Tutor y el Analista;
  - cuota restante de IA;
  - **Cambiar contraseña**.
- Pruebas: la fase 21 (25 comprobaciones con tres usuarios: owner, amigo y curioso). Pasan las 21 fases.

**Lo que se aprende en esta fase**
- **Roles en dos niveles**, como en Power BI / Fabric y en BC: rol de aplicación (owner / member) y rol por
  empresa (admin / contable / solo lectura), más un atributo de negocio (titular de los datos).
- **La seguridad en la base de datos manda:** la web solo enseña u oculta botones; quién puede publicar, usar la
  IA o ver una empresa lo decide PostgreSQL (RLS y funciones `security definer` con comprobación explícita).
- **Una cuota se cuenta antes de gastar:** la llamada rechazada no suma (la transacción se deshace).
- **Privacidad:** los datos ajenos se publican solo con el permiso de su titular, que es quien los publica.

**Decisiones:** ADR de Accesos y titulares de los datos en `docs/decisiones/`.

**Siguiente paso:** dar de alta a los dos compañeros del curso y recoger sus primeras opiniones sobre la IA.
Después, el módulo de **Inmovilizado**.

## 2026-10-10 · v0.25.0 · Navegación, Inicio guiado y modo Básico / Auditor

**Qué se hizo**
- **Integración continua** (`.github/workflows/ci.yml` y `scripts/test-db.sh`):
  - en cada PR, PostgreSQL 16 con las 21 pruebas SQL, cada una en una base limpia;
  - lint, build y `npm audit` de la web;
  - la rama `main` queda protegida: sin los checks en verde no se puede fusionar.
- **Rutas** `#/empresa/<id>/<pantalla>` (`router.js`, `Link.jsx`): atrás, recargar y compartir funcionan. Las
  empresas de la lista son enlaces que se abren con el teclado.
- **Inicio** (`Home.jsx`):
  - ruta guiada "Tu primer trimestre, paso a paso", en 6 pasos que se marcan solos y con barra de progreso;
  - **Modo auditor** para las empresas importadas y las demos;
  - accesos rápidos y últimos movimientos.
- **Modo Básico / Auditor:** menú corto de 8 entradas en lenguaje sencillo, o el completo. Se guarda en el navegador
  y cambiar de modo no saca de la pantalla.
- **"Cargando…" global** (`activity.js`, `BusyBar.jsx`) y **estados vacíos con botón** (`Empty.jsx`) en
  Liquidación, Prorrata, Diario, Sumas y saldos, Facturas, el formulario de factura, el asiento y Empresas.
  "Ver en el diario" tras contabilizar.
- **Asiento:** el "−" solo borra la línea desde el campo de cuenta vacío, con **Deshacer** durante 5 s. En los
  importes se escribe como signo.
- **Corregido:** la pantalla "Importar subcuentas" mostraba el texto del diario por una clave i18n duplicada.

**Lo que se aprende en esta fase**
- **El CI paga desde el primer día:** en su primera ejecución encontró dos fallos que llevaban semanas en
  producción, y después paró en el PR un comentario CSS roto antes de que llegara a la web.
- **Rutas con almohadilla:** en una SPA alojada como ficheros estáticos, `#/…` no llega al servidor, así que no
  hace falta configurar redirecciones.
- **Una pieza transversal mejor que veinte parches:** contar las peticiones en el cliente de Supabase da el
  "Cargando…" a todas las pantallas.
- **Diseño por perfiles (BC):** el mismo ERP con dos menús. El principiante ve 8 entradas y el auditor 17; los
  permisos no cambian.
- **Git en Windows:** los avisos LF/CRLF no son errores. `git diff --stat --ignore-cr-at-eol` muestra solo los
  cambios reales, y `git config --global core.pager ""` evita quedarse atrapado en el visor `(END)`.

**Decisiones:** ADR 0022 · Navegación con rutas, pantalla de Inicio y modo Básico / Auditor.

**Siguiente paso:** v0.26.0. Errores en lenguaje claro (`friendlyError`), pantalla de entrada y plantillas de
asientos frecuentes.

## 2026-10-10 · v0.26.0 · Errores claros, pantalla de entrada y plantillas de asientos

**Qué se hizo**
- **Errores en lenguaje claro** (`errors.js` y `ErrorBox.jsx`):
  - 85 reglas traducen los mensajes de la base de datos a qué ha pasado y qué hacer, con un botón "Ir a…" a la
    pantalla donde se arregla y el detalle técnico plegado;
  - se aplicaron a las 27 cajas de error con un script, sin sustituir pantallas.
- **Pantalla de entrada** (`Landing.jsx`):
  - qué es el proyecto, en tres puntos;
  - la demo, arriba y en grande;
  - pestañas de acceso y registro con etiquetas, mostrar contraseña, requisito visible y aviso de confirmación por
    correo;
  - pie con GitHub.
- **Asientos para principiantes:**
  - 5 plantillas "¿Qué ha pasado?" (compra, venta, cobro, pago, nómina) que rellenan las subcuentas de la empresa y
    marcan el lado de cada importe;
  - buscador de cuentas por número o nombre, con teclado;
  - explicaciones plegables de Debe/Haber y de borrador frente a contabilizar.

**Lo que se aprende en esta fase**
- **Un error es una oportunidad de enseñar:** "El asiento no cuadra: falta 210,00; pulsa =" ayuda más que
  `Unbalanced entry`. En un ERP de formación, el mensaje de error es parte del temario.
- **Capas:** la base de datos decide (reglas y mensajes estables, probados por los tests) y la web explica
  (traducción, pistas, navegación). Si un patrón deja de coincidir, se muestra el mensaje original: falla de forma
  segura.
- **Cambios masivos con un script** en lugar de sustituir ficheros: toca solo lo necesario sobre la versión real de
  cada pantalla, y `git diff --stat` lo confirma.
- **Accesibilidad básica:** cada campo con su `label for`, los roles `tablist` / `combobox` / `listbox` y el uso
  completo con teclado.
- **La partida doble en cinco plantillas:** compra (600 + 472 a 400), venta (430 a 700 + 477), cobro (572 a 430),
  pago (400 a 572) y nómina (640 + 642 a 476 + 4751 + 572).

**Decisiones:** ADR 0023 · Errores en lenguaje claro, pantalla de entrada y plantillas de asientos.

**Siguiente paso:** v0.27.0. Glosario dentro de la app, accesibilidad, colores e iconos, y capturas en el README.

## 2026-10-10 · v0.27.0 · Glosario en la app, accesibilidad y acabado

**Qué se hizo**
- **Glosario** (`glossary.js`, `Term.jsx` y `Glossary.jsx`):
  - 36 términos en español e inglés con su nombre en Business Central y SAP;
  - un ⓘ con globo junto a la ruta de cada pantalla y en Debe/Haber;
  - página `#/glosario` con buscador, enlazada desde la cabecera.
- **Accesibilidad:**
  - medida con axe-core en entrada, empresas, Inicio, asiento, factura y balance, en modo claro y oscuro: 0 fallos
    (antes, 20 y 31);
  - `lang` que sigue al idioma, título de la página, etiquetas visibles en el alta de empresa, nombres accesibles en
    la factura y foco visible común.
- **Colores:** `--exito`, `--alerta` y `--sobre-color` con versión oscura sustituyen a 32 colores escritos a mano.
- **Iconos `lucide-react`** en la cabecera, la entrada, el Inicio, los errores, los estados vacíos y las plantillas.
- **Capturas** de la app en `docs/capturas/` y en el README.

**Lo que se aprende en esta fase**
- **Accesibilidad = medir:** axe-core da una lista concreta (falta `lang`, un select sin nombre, contraste 3,1:1) y un
  objetivo verificable (0 fallos). Lighthouse usa el mismo motor.
- **Contraste:** el blanco sobre `#1f5eff` da 5,2:1 (vale), pero sobre el `#6d8dff` del modo oscuro solo 3,1:1. En
  oscuro, el texto sobre color tiene que ser oscuro.
- **Variables CSS como sistema de diseño:** cambiar un color de estado es tocar una línea, y el modo oscuro sale solo.
- **El vocabulario como puente profesional:** contraasiento = *Reverse Transaction* (BC) = *FB08* (SAP). El glosario
  enseña contabilidad y, a la vez, a hablar el idioma de los ERP del mercado.

**Decisiones:** ADR 0024 · Glosario en la app, accesibilidad medida y colores con variables.

**Siguiente paso:** v0.28.0. Seguridad: cabeceras HTTP, endurecer `/api/ai` y `/api/tutor`, CAPTCHA, limpieza de invitados y tests de la web con Vitest.

## 2026-10-11 · v0.28.0 · Seguridad: cabeceras, IA endurecida, CAPTCHA, limpieza de invitados y tests

**Qué se hizo**
- **Cabeceras HTTP** (`public/_headers`):
  - CSP ajustada al código real (solo el propio dominio, Supabase y Turnstile);
  - anti-iframe, `nosniff`, `Referrer-Policy`, `Permissions-Policy`, HSTS y COOP;
  - comprobado sirviendo la build: ninguna violación de la CSP.
- **`/api/ai` y `/api/tutor`:** sin detalles internos en la respuesta (van a `console.error`), `company_id` validado
  como UUID antes de llamar a Supabase y cuerpo limitado (413).
- **CAPTCHA Cloudflare Turnstile** en la demo, el registro y el acceso. El enlace `?demo` ya no crea invitados al
  cargar.
- **Migración 0028:** `erp.cleanup_guests(7)` y tarea diaria con `pg_cron`. Borra los invitados de más de 7 días sin
  dejar filas huérfanas. Prueba fase 22.
- **Vitest:** 47 tests de la web en la CI.
- `frontend/.env.example` con las variables necesarias, sin valores reales.
- Fuera de la versión: **plantilla del laboratorio** (Excel y CSV) y su especificación, para preparar datasets que se
  importan a la primera.

**Lo que se aprende en esta fase**
- **Defensa en capas:** la base de datos ya decidía los permisos (RLS). Ahora además el borde (cabeceras, CAPTCHA) y
  las funciones (validación y errores opacos) reducen lo que un atacante puede intentar y lo que puede aprender.
- **Un error interno es información para el atacante:** "permission denied for table journal_entries" le dice qué
  tablas hay. Al usuario, un código; al registro, el detalle.
- **El orden de despliegue importa:** el CAPTCHA se activa en Supabase *después* de que producción tenga el widget, o
  nadie podría entrar. El interruptor de Supabase es el plan de vuelta atrás.
- **Las claves foráneas que no existen también importan:** sin FK hacia `auth.users`, borrar un usuario deja filas
  huérfanas. Se revisa antes de escribir el `delete`, y un test lo vigila.
- **Un test que nunca falla no prueba nada:** cada prueba nueva se valida rompiendo el código a propósito.
- **Los tests no van en `functions/`:** Cloudflare convierte en ruta todo lo que hay en esa carpeta.

**Decisiones:** ADR 0025 · Seguridad: cabeceras HTTP, IA endurecida, CAPTCHA, limpieza de invitados y tests de la web.

**Siguiente paso:** el módulo de **Inmovilizado**: fichas de activos, plan de amortización y asiento mensual a  contabilidad.

## 2026-10-11 · v0.29.0 · Rendimiento con muchos datos, borrar empresas, fecha de trabajo y rastro contable

**Qué se hizo**
- **Libro mayor rápido:** función `erp.general_ledger` (migración 0029). Primero filtra y después calcula el saldo:
  de 6,9 s (timeout en Supabase) a 0,2 s con 120.000 apuntes.
- **Índices en todas las claves foráneas:** borrar una empresa grande pasa de 148 s a tandas de 0,5 s.
- **Lecturas de más de 1.000 filas** por páginas (`fetchAll`) en el diario, el mayor, sumas y saldos y las cuentas.
- **Borrar empresa:** zona de peligro con resumen de lo que se borra, confirmación escribiendo el nombre y barra de
  progreso. Solo el admin y nunca una demo publicada. Los Miembros pueden importar y borrar después.
- **Fecha de trabajo** de cada empresa (hoy, o la del último asiento si es histórica) en todos los filtros y
  formularios. Corregida de paso la fecha "de hoy", que se calculaba en UTC.
- **Rastro contable:** del mayor a la ficha del asiento, y de cada cuenta a su mayor, con "Volver" y el botón atrás.
- Prueba SQL fase 23 y 15 tests nuevos de la web (62 en total).

**Lo que se aprende en esta fase**
- **Probar con datos reales:** todo funcionaba con 20 asientos. Con 60.000 aparecieron el timeout, el límite de
  1.000 filas y el borrado lento. Ahora se prueba en local con un volumen grande antes de entregar.
- **El orden importa en SQL:** una función de ventana sobre una vista se calcula *antes* del `where`. Filtrar
  primero es la diferencia entre 7 s y 0,2 s.
- **Una clave foránea sin índice es un borrado lento:** PostgreSQL comprueba cada fila que apunta a la que se borra.
- **Un límite que no avisa es peor que un error:** Supabase corta a 1.000 filas en silencio y los totales salían
  mal sin que nada lo dijera.
- **Work Date (BC) / periodo abierto (SAP):** la fecha por defecto la decide la empresa, no el reloj.
- **El rastro contable** (mayor → asiento → otra cuenta) es la herramienta básica del auditor. Si cada paso tiene su
  dirección, el botón atrás funciona solo.

**Decisiones:** ADR 0026 · Rendimiento con muchos datos, borrar empresas, fecha de trabajo y rastro contable.

**Siguiente paso:** el módulo de **Inmovilizado**: fichas de activos, plan de amortización y asiento mensual a contabilidad.

## 2026-10-11 · v0.29.1 · Seguridad: titular de los datos, licencia MIT y dependencias

**Qué se hizo**
- **Corregido un fallo de seguridad** que encontró una revisión externa: cualquier usuario registrado podía
  nombrarse a sí mismo **titular de los datos** de su empresa y, con eso, usar la IA y publicar su empresa como demo
  pública. Migración 0030: un trigger hace que solo el propietario de la app pueda poner esa marca.
- Prueba SQL fase 24 (falla sin la corrección). 24 pruebas SQL en total.
- Revisión en producción de titulares y demos.
- **Licencia MIT**, **`SECURITY.md`** (avisos privados), **Dependabot** y la lista de comprobación
  `docs/seguridad-supabase.md`.

**Lo que se aprende en esta fase**
- **RLS protege filas, no columnas:** la política "el admin gestiona los usuarios de su empresa" era correcta hasta
  que la tabla ganó una columna que da poder. Cada columna nueva se revisa contra las políticas que ya existen.
- **Un trigger para las reglas de "antes → después":** quitar la marca sí, ponerla no. Eso no se expresa bien con
  RLS.
- **Una segunda mirada encuentra lo que no ves:** la revisión de otro agente detectó una regresión de la v0.24.0.
  Antes de corregir, se reproduce; y la prueba tiene que fallar sin la corrección.
- **Un repositorio público sin licencia no es libre:** legalmente nadie podía reutilizarlo. Con la MIT sí, citando
  la autoría.

**Decisiones:** ADR 0027 · Protección del titular de los datos, licencia MIT y dependencias.

**Siguiente paso:** probar el ERP con una contabilidad de verdad y pulir lo que salga. Después, el **Inmovilizado**.

## 2026-10-12 · v0.30.0 · Bloque visual: indicadores, estados comparativos, gráficos y exportación

**Qué se hizo**
- **Inicio con indicadores** (migración 0031):
  - tesorería, resultado, IVA/IGIC del trimestre, pendiente de cobro y de pago, y la tesorería a fin de mes;
  - según quién entra: el auditor ve las cifras arriba y quien empieza ve primero la ruta guiada.
- **Balance y PyG** con variación en importe y en % frente al año anterior. Corregido el Balance intermedio, que
  ahora se compara con el cierre anterior (migración 0032).
- **Cascada del EFE** y **evolución de cada ratio** en el tiempo. El gráfico del IVA se descartó por no aportar nada.
- **Excel e Imprimir** en los seis informes principales.
- **Pulido:** tarjetas en el móvil, fechas dd/mm/aaaa y números alineados.
- 26 pruebas SQL (fases 25 y 26 nuevas) y 75 tests de la web.

**Lo que se aprende en esta fase**
- **Menos es más:** un gráfico se justifica si responde a una pregunta mejor que la tabla. La cascada del EFE sí
  (30 líneas en 5 barras); el IVA trimestral no (4 cifras).
- **Honestidad visual:** con área, el eje empieza en 0; la variación no se colorea (un gasto que sube no siempre es
  malo); el signo se escribe, no se deja solo al color.
- **Indicadores que respetan la contabilidad:** sin regularización ni cierre, y sin el asiento de liquidación en el
  IVA del trimestre. Si no, las cifras engañan justo en las fechas clave.
- **Comparar bien es contabilidad (NIC 34):** el Balance es una foto, que se compara con la última foto aprobada; la
  PyG es una película, que se compara con el mismo tramo.
- **Rendimiento de verdad:** el *JIT* de PostgreSQL puede tardar más que la propia consulta, y comprobar permisos
  fila a fila multiplica el tiempo. Se mide antes de entregar.
- **Excel y las fechas:** un objeto `Date` cambia de día con la zona horaria; el número de serie de Excel no.

**Decisiones:** ADR 0028 · Bloque visual: indicadores, estados comparativos, gráficos con criterio y exportación.

**Siguiente paso:** usar el ERP con contabilidad real y pulir lo que salga. Después, el **Inmovilizado**.

## 2026-10-13 · v0.31.0 · IA guiada por reglas (retenciones) y panel de uso de la web

**Qué se hizo**
- **Retenciones guiadas por reglas** (migración 0033):
  - la ficha del tercero manda (forma jurídica y retención por defecto);
  - las reglas de cuándo hay retención están en la base de datos;
  - el ERP calcula la retención y lo que queda a pagar;
  - la IA corrige en una segunda vuelta si falta la retención.
- **Factura recibida** con la retención de la ficha del tercero.
- **Panel «Uso de la web»** (migración 0034): visitantes de la demo, registros y uso, solo para el propietario. Con
  la historia a salvo de la limpieza nocturna.
- 28 pruebas SQL (fases 27 y 28 nuevas) y 83 tests de la web.

**Lo que se aprende en esta fase**
- **Por qué alucina una IA en contabilidad:** acertaba el IGIC porque el ERP lo restringía y lo recalculaba, y fallaba
  el IRPF porque nadie lo hacía. Lo que no está en una regla queda al azar del modelo.
- **La IA clasifica, la base de datos contabiliza:** como los grupos contables de BC o la determinación de cuentas
  de SAP. La IA entiende la operación; las cuentas, los tipos y los importes salen de datos maestros y reglas.
- **La retención en la factura:** profesional persona física 15 % (7 % en inicio de actividad), alquiler de local
  19 %. Se calcula sobre la base, sin impuesto, y el tercero cobra base + impuesto − retención: 1.000 + 70 − 150 = 920.
  Una SL que presta servicios profesionales no lleva retención.
- **El NIF dice la forma jurídica:** un NIF o NIE es de una persona física; un CIF, de una entidad.
- **Medir sin rastrear:** los usuarios anónimos de la demo ya son el recuento. Al borrar datos, antes se guarda lo
  que se quiere seguir midiendo.

**Decisiones:** ADR 0029 · IA guiada por reglas (retenciones) y panel de uso de la web.

**Siguiente paso:** usar el ERP con contabilidad real y anotar cada fallo de la IA: cada uno será una regla o un caso
de prueba de las fases 2 a 4. Después, el **Inmovilizado**.

## 2026-10-14 · v0.32.0 · Cobros y pagos contra la factura (Tesorería I)

**Qué se hizo**
- **Pagos y cobros aplicados a facturas** (migración 0035): el ERP hace el asiento, se pueden anular y se pueden
  vincular los pagos que ya estaban hechos a mano.
- **Antigüedad de saldos** a una fecha, con el saldo contable al lado.
- **Días de pago, vencimiento y estado** de cada factura.
- 29 pruebas SQL (fase 29 nueva) y 89 tests de la web.

**Lo que se aprende en esta fase**
- **Partida abierta:** una factura sin pagar del todo. El pago se aplica contra ella; es la «liquidación» de BC y la
  «compensación» de SAP (F-53 para pagar, F-28 para cobrar).
- **Cuentas controladas:** en SAP y BC la 400/410 no se mueve a mano; se mueve desde Pagos. Es lo que en Versat se
  llamaba cuentas controladas. Los ERP españoles lo permiten, y controlan después con cuadres y punteo.
- **Pendiente real:** el total de la factura menos la retención (eso va a Hacienda, no al proveedor), menos las
  rectificativas, menos lo pagado.
- **Antigüedad de saldos:** la herramienta del controller para cobrar. Lo vencido hace más de 90 días es un riesgo de
  impago (y, en contabilidad, un posible deterioro de créditos: cuentas 490 y 694).
- **El saldo contable y las facturas tienen que cuadrar.** Si no cuadran, hay pagos sin vincular o saldos importados.

**Decisiones:** ADR 0030 · Cobros y pagos contra la factura.

**Siguiente paso:** v0.33.0 · cuentas controladas (modo estricto estilo SAP/BC o guiado estilo español) y controles
de auditor en una pantalla «Comprobaciones».

## 2026-10-15 · v0.33.0 · Cuentas controladas y comprobaciones del auditor

**Qué se hizo**
- **Cuentas controladas** con un interruptor por empresa (migración 0036):
  - **estricto** como SAP/BC: un asiento manual sobre la 410, la 430 o la 472 no se contabiliza;
  - **guiado** como un ERP español: avisa y lo deja revisar.
- **Comprobaciones del auditor** a una fecha (0037), en una pantalla nueva con el detalle enlazado.
- **Conceptos**: el glosario también en la base de datos (0038), con sus cuentas del PGC.
- 32 pruebas SQL (fases 30, 31 y 32 nuevas) y 98 tests de la web.

**Lo que se aprende en esta fase**
- **Controlar antes o después:**
  - SAP y BC impiden el error (cuenta asociada, sin registro directo);
  - los ERP españoles lo detectan con cuadres;
  - un auditor hace estos mismos cuadres en cualquier empresa.
- **El cuadre del IVA:** la 472/477, sin la liquidación, debe salir entera de las facturas. Lo que sobra es un
  asiento manual que no está en el libro registro ni en el 303/420.
- **La 4751 frente al 111:** la retención de un profesional sale de su factura. Una anotada a mano no estará en el
  resumen, salvo las de nómina, que el ERP aún no gestiona.
- **Por qué existen las cuentas controladas:** no es burocracia, es que la factura sepa si está pagada y el libro de
  IVA cuadre con la contabilidad.
- **Restricciones diferidas en PostgreSQL:** la regla se comprueba al final de la transacción, cuando el documento ya
  existe (`DEFERRABLE INITIALLY DEFERRED`).

**Decisiones:** ADR 0031 · Cuentas controladas (modo estricto o guiado) y comprobaciones del auditor.

**Siguiente paso:** v0.34.0 · catálogo de operaciones y Tutor «dónde se registra»: la IA clasifica la operación y el
ERP dice en qué pantalla se hace y con qué asiento.

## 2026-10-15 · v0.33.1 · Arreglos de una revisión externa

**Qué pasó**
Una IA externa revisó el proyecto (sobre la v0.32.0) para medir su impacto frente a otros ERP como herramienta para
aprender contabilidad española. Su valoración: 8,5 como portafolio técnico, 7 para aprender a manejar un ERP y 4,5
en cobertura de contabilidad española. Encontró dos fallos reales y una debilidad de fondo.

**Qué se hizo**
- **Fallo 1:** una 477 sin configurar se saltaba el cuadre del 303. Ahora la liquidación la incluye (0039).
- **Fallo 2:** una cuota incoherente (base 100 × 21 % con cuota 500) se aceptaba sin aviso. Ahora es una comprobación
  del auditor, y en modo estricto ese asiento ya no se contabilizaba (v0.33.0).
- Pruebas de regresión (fase 33): fallan sin el arreglo y pasan con él. 33 pruebas SQL y 98 tests de la web.
- ADR en UTF-8, la ADR 0010 matizada sobre contabilidades reales y el volcado de las 145 funciones en
  `database/funciones/` para estudiarlas.

**Lo que se aprende**
- **La debilidad de fondo:** las pruebas las escribió la misma IA que escribió el código. Comprueban lo que hace el
  código, no lo que dice la contabilidad. Por eso la próxima versión trae supuestos de referencia externos (libros de
  FP, oposiciones) e invariantes contables.
- **Una prueba de regresión tiene que fallar sin el arreglo.** Si no, no protege de nada.
- **Un ADR no se reescribe:** se matiza con una actualización fechada, para que se vea cómo cambió la decisión.

**Plan reordenado** (`plan-ejecucion.md`): fiabilidad contable → Inmovilizado → fin de ejercicio → nóminas → supuestos
autocorregidos → ontología y chat. Regla nueva: no se empieza una versión hasta poder explicar la anterior.

**Siguiente paso:** v0.34.0 · fiabilidad contable: invariantes con operaciones al azar y los primeros supuestos de
referencia, escritos por mí.

## 2026-10-16 · v0.34.0 · Fiabilidad contable: invariantes y supuestos de referencia

**Qué se hizo**
- **Nueve invariantes contables** como función de la base de datos (0040).
- **Unas 300 operaciones al azar** por empresa (Madrid con IVA, Canarias con IGIC):
  - 392 facturas, 54 rectificativas, 82 con IRPF, 47 AIB/ISP y 28 con recargo;
  - 133 cobros y pagos, 40 contraasientos, 10 liquidaciones y el cierre.

  Todo en verde, también con otras tres semillas.
- **Cinco supuestos de referencia** calculados a mano desde la norma: el ERP coincide al céntimo.
- 35 pruebas SQL y 98 tests de la web.

**Lo que se aprende**
- **Un invariante vale más que cien ejemplos:** «Activo = PN + Pasivo» no depende de quién programe. Si falla, el
  error es del ERP.
- **La prorrata se redondea al entero superior** (art. 104.Dos.2.º LIVA): 6.000 / 8.500 = 70,59 % → 71 %. La diferencia
  con la provisional se regulariza en la última declaración del año (6341 o 6391).
- **El IVA no deducible es mayor gasto** (NRV 12.ª): 1.000 de reparación con un 20 % no deducible → 622 = 1.042.
- **La autorrepercusión es neutra:** en la AIB y la ISP la empresa devenga y deduce la misma cuota; solo cambia quién
  la declara.
- **Contar lo que hace el azar:** la primera vez el recargo salía 0 por un fallo de la propia prueba. Sin el recuento
  no se habría visto.

**Hallazgo:** el borrador del 303 no numera las casillas oficiales (10–11 AIB, 12–13 ISP, 28–29 deducible…). Pasa al
backlog.

**Decisiones:** ADR 0032 · Fiabilidad contable: invariantes y supuestos de referencia.

**Siguiente paso:** v0.35.0 · Inmovilizado: ficha del activo, cuadro de amortización, asiento mensual (68x/28x) y
baja con resultado (671/771), con su supuesto de referencia.

## 2026-10-16 · v0.35.0 · Inmovilizado: ficha, amortización, baja y venta

**Qué se hizo**
- **Fichas de activos** dadas de alta desde la factura recibida, con su **cuadro de amortización** y el asiento
  68x/28x hasta la fecha que se elija (migración 0041).
- **Baja y venta:** la factura emitida va a la cuenta del activo, y la baja lleva el resultado a la 671 o la 771.
- **Tabla fiscal** del Impuesto sobre Sociedades, con aviso.
- **Integración** (0042): comprobaciones, aviso del cierre, prorrata sin las ventas de inmovilizado y glosario.
- **Pantalla Inmovilizado.** 37 pruebas SQL y 104 tests de la web.

**Lo que se aprende**
- **Se amortiza desde la puesta en funcionamiento, no desde la compra** (NRV 2.ª), y sobre el coste menos el valor
  residual.
- **El supuesto, al céntimo:** furgoneta de 18.000, residual 2.000, 8 años, desde el 15/03.
  - 2026: 9 meses + 17/31 = 1.591,40.
  - Vendida el 30/06/2027 por 14.000: amortización acumulada 2.588,89, valor neto 15.411,11, pérdida 1.411,11 (671).
- **La venta de un activo es una entrega con IVA:** por eso se factura a su cuenta (21x) y no a una 7xx. El precio no
  es ingreso; el resultado es la diferencia con el valor neto.
- **Amortización contable y fiscal:** la contable sigue la vida útil real; la tabla del art. 12.1.a LIS solo limita lo
  deducible en el Impuesto sobre Sociedades. Por ejemplo, un ordenador a 2 años es un 50 % frente al máximo fiscal del
  25 %: hay una diferencia temporaria.
- **Prorrata:** vender un bien de inversión no altera el porcentaje (art. 104.Tres.2.º LIVA). Con esta regla un
  servidor de 10.000 no la sube del 71 % al 87 %.
- **La comprobación nueva encontró dos cosas** en las operaciones al azar: amortizaciones hechas a mano y
  rectificativas de compras de activo que la ficha no recoge. Esta última pasa al backlog.

**Decisiones:** ADR 0033 · Inmovilizado: ficha, amortización lineal, baja y venta con resultado.

**Siguiente paso:** v0.36.0 · Fin de ejercicio I: periodificaciones (480/485), deterioro de clientes desde la
antigüedad de saldos (490/694/794), provisiones, regularización de existencias y un asistente de cierre.

## 2026-10-18 · v0.36.0 · Ajustes de cierre I: periodificaciones y deterioro de clientes

**Qué se hizo**
- Se incorporó una segunda revisión externa («Hoja de ruta: carencias»), con sus cuentas corregidas al PGC 2007. El cierre
  pasa a dos versiones, los modelos anuales se adelantan y la analítica y el presupuesto entran en el plan.
- **Periodificaciones** con reversión en el ejercicio siguiente, y **deterioro de clientes** individual y global, con su
  reversión y la insolvencia firme (migración 0043).
- **Integración** (0044): tres comprobaciones, aviso del cierre, glosario y la prueba al azar.
- **Pantalla Ajustes de cierre.** 39 pruebas SQL y 112 tests de la web.

**Lo que se aprende**
- **Periodificar es aplicar el devengo:** se ajusta contra la propia cuenta de gasto o ingreso, no contra una cuenta
  puente.
  - Seguro anual de 1.200 pagado el 01/10: al cierre, 9/12 = 900 son del año siguiente → 480 D 900 / 625 H 900.
    El gasto de 2026 queda en 300.
  - Alquiler de un semestre (6.000) cobrado el 01/11: 4.000 son del año siguiente → 752 D 4.000 / 485 H 4.000.
- **La reversión no es una anulación.** El 01/01 se hace un asiento nuevo al revés. En los devengados (4009 / 4309), la
  reversión deja el gasto en negativo y la factura que llega lo compensa: en el año nuevo solo queda lo que es suyo.
- **El deterioro no toca la deuda:** la 430 sigue reclamando y la 490 corrige su valor en el balance.
  - Moroso con 2.420 vencidos hace 9 meses: 694 / 490 por 2.420, deducible.
  - Dudoso con 800 pendientes y vencidos hace 3 meses, al 50 %: 400, no deducible hasta el 01/04/2027 (art. 13.1.a LIS).
    Es una diferencia temporaria.
- **El global se estima de nuevo cada año** (25 % de 605 + 10 % de 1.210 = 272,25). Fiscalmente solo lo deduce una
  empresa de reducida dimensión, y como mucho el 1 % de los deudores (art. 104 LIS).
- **Insolvencia firme:** la pérdida va a la 650 y el deterioro dotado se aplica a la 794. La partida abierta se cierra
  como un cobro sin banco, como compensa SAP las partidas.
- **Una revisión externa también se revisa.** El documento usaba la 693 para clientes (es la de existencias), la 680 para
  periodificar (es la amortización del intangible) y la 472 en la nómina (es la 4751).

**Decisiones:** ADR 0034 · Ajustes de cierre I: periodificaciones y deterioro de clientes.

**Siguiente paso:** v0.37.0 · Fin de ejercicio II:
- provisiones (141 / 142 / 499 y 795);
- deterioro del inmovilizado (691 / 291 / 791) y rectificativa de compra de activo que ajuste su ficha;
- regularización de existencias por inventario (610 / 71x);
- asistente de cierre.

## 2026-10-18 · v0.37.0 · Ajustes de cierre II: provisiones, deterioro del inmovilizado, existencias y asistente

**Qué se hizo**
- **Provisiones** con su ficha y sus movimientos (0045).
- **Deterioro del inmovilizado** con la amortización recalculada, y la rectificativa de compra que ajusta la ficha (0046).
- **Inventario del cierre** y **asistente de cierre** (0047).
- **Integración:** comprobaciones, avisos y glosario (0048).
- **Web:** Ajustes de cierre, ficha del activo y Cierre del ejercicio.
- **Pruebas:** 43 SQL y 118 tests de la web.

**Lo que se aprende**
- **Una provisión es una obligación de hoy con importe incierto.**
  - Litigio: 12.000 → revisado a 15.000 → pasado a corto plazo (5293) → sentencia de 14.000. El asiento final es
    5293 D 15.000 / 572 H 14.000 · **7953 H 1.000** de exceso.
  - Las garantías (499) no se ajustan por la diferencia: se revierte la del año anterior (7954) y se dota la nueva (6959).
- **El deterioro del inmovilizado cambia la amortización futura** (NRV 2.ª).
  - Máquina de 60.000 a 10 años: en 2027 su valor neto es 48.000 y el recuperable 40.000 → deterioro de 8.000.
  - Desde ahí se amortiza 40.000 / 96 meses = 5.000 al año.
  - En 2029 el recuperable sube a 38.000, pero la reversión tiene un límite: el valor sin deterioro, 36.000. Se revierten
    6.000, y la amortización vuelve a ser de 6.000 al año.
- **La rectificativa de una compra baja el coste.** Ordenador de 1.200 con 240 de descuento: coste 960. Lo pendiente se
  reparte en la vida que queda (2027 = 235,61) y en total se amortizan 960, al céntimo.
- **Variación de existencias:** el gasto es lo consumido, no lo comprado. Inicial 8.000 + compras 40.000 − final 6.000 =
  42.000 (600 + 610). El deterioro de existencias se revierte y se vuelve a dotar en cada cierre.
- **El cierre tiene un orden:** liquidaciones, reversiones, amortización, deterioros, periodificaciones, clientes,
  provisiones, inventario, comprobaciones y cierre. Algunos pasos solo los puede valorar la empresa: el asistente los
  marca como «revisar».
- **La prueba al azar volvió a encontrar un caso:** la rectificativa de la **venta** de un activo no corrige el resultado
  de la baja. Pasa al backlog.

**Decisiones:** ADR 0035 · Ajustes de cierre II.

**Siguiente paso:** v0.38.0 · Nóminas: empleado ficticio, devengos, cuotas de la Seguridad Social desde una tabla de
tipos, IRPF, pagas extra periodificadas, asiento 640/642 contra 4751/476/465 y su pago; la 4751 de nómina cuadrará con
el 111.

## 2026-10-18 · v0.38.0 · Nóminas

**Qué se hizo**
- **Nóminas** con tipos de cotización del año, ficha del empleado, recibo, asiento, pagas extra y pagos (0049).
- **Integración:** comprobación de la 465 / 476, la 4751 y el modelo 111 con las nóminas, y glosario (0050).
- **Web:** pantalla Nóminas y la fila de nóminas en Retenciones IRPF.
- **Pruebas:** 45 SQL y 126 tests de la web.

**Lo que se aprende**
- **La base de cotización no es el salario del mes.** Ana cobra 2.000 al mes y dos pagas de 2.000: cotiza por
  2.000 + 2.000 × 2 / 12 = **2.333,33** todos los meses, también en junio, aunque ese mes cobre 4.000 (art. 147 LGSS).
- **La empresa paga casi un tercio más del sueldo.** Sobre esos 2.333,33, la empresa cotiza 738,50 (23,60 + 5,50 +
  0,20 + 0,60 + 0,75 + 1,00 de AT = 31,65 %) y la trabajadora 151,67 (6,50 %). Coste del mes: 2.333,33 + 738,50.
- **El asiento de enero:** 640 D 2.000 · 640 D 333,33 (paga devengada) · 642 D 738,50 / 476 H 890,17 · 4751 H 240 ·
  465 H 1.608,33 (líquido) · 465 H 333,33 (paga). En junio la 465 se carga con los 2.000 de la paga, que se cobra con
  la nómina y paga su IRPF (480), pero no cotiza otra vez.
- **El redondeo se cuadra en el mes de la paga:** 5 × 333,33 + 333,35 = 2.000, al céntimo.
- **Temporal o indefinido cambia el desempleo:** Luis (temporal) paga 1,60 % y la empresa 6,70 %, frente a 1,55 % y
  5,50 % de un indefinido.
- **Por encima de la base máxima** (5.101,20) no se cotiza más, salvo la cotización adicional de solidaridad: una
  remuneración de 7.000 paga 4,90 + 14,44 la empresa y 0,97 + 2,92 la trabajadora.
- **La 476 al cierre es la Seguridad Social de diciembre**, que se paga en enero. La 465 a cero dice que se ha pagado
  todo el líquido y todas las pagas.
- **La 4751 junta dos orígenes** que van al mismo modelo 111: nóminas (casillas 01 a 03) y profesionales (07 a 09).

**Decisiones:** ADR 0036 · Nóminas.

**Siguiente paso:** v0.39.0 · Modelos anuales: 390 / 425 (resumen anual del IVA / IGIC), 347 (operaciones con terceros
de más de 3.005,06 €), 349 (operaciones intracomunitarias, solo con IVA) y las casillas del 303 / 420.

## 2026-10-19 · v0.39.0 · Modelos tributarios y base documental

**Qué se hizo**
- **Casillas** del 303 / 420 y de los resúmenes anuales 390 / 425 (0051).
- **Modelos 347 y 349** (0052).
- **Base documental**, comprobaciones de los modelos y glosario (0053).
- **Web:** pantalla Modelos y el botón 📘 Fuentes.
- **Pruebas:** 48 SQL y 134 tests de la web.

**Lo que se aprende**
- **El modelo sale del libro registro; la liquidación, de la contabilidad.** Si coinciden, el asiento manual no ha
  tocado la 472 / 477. En el supuesto, un asiento de 50 en la 477 deja el 303 en 210 y la liquidación en 260.
- **Una rectificativa no va en su tipo:** −1.000 al 21 % van a las casillas 14 / 15, no restados de la 07 / 09.
- **Bien de inversión no es lo mismo que inmovilizado.** La máquina de 6.000 va a la 30 / 31; el ordenador de 800, a
  la 28 / 29, porque no llega a 3.005,06 € (art. 108 LIVA). Para el IGIC, el mismo límite en pesetas: 500.000.
- **El 420 no tiene casillas por tipo:** cada grupo de tres (base, tipo, cuota) lleva el tipo que toque, del más bajo
  al más alto (0, 3, 7 y 15 % en el supuesto).
- **El resumen anual es la suma de los trimestres:** 189 − 1.680 + 0 + 4.200 = 2.709 en la casilla 65 del 390, igual
  que lo ingresado en el año (95), porque los 1.680 del 2T se compensaron en el 4T.
- **En el 347 el IVA va incluido, salvo en la inversión del sujeto pasivo.** Un cliente con 2.420 + 1.210 = 3.630 se
  declara; otro con 3.300 − 550 de rectificativa = 2.750, no. La abogada con retención tampoco: ya está en el 190.
- **En el 349, el límite de 50.000 € decide si es mensual,** y una rectificativa de otro trimestre se declara como
  rectificación de aquel trimestre (28.000 frente a 30.000).
- **Cada regla tiene su fuente, y las fuentes caducan:** por eso cada una guarda la fecha en que se comprobó.

**Decisiones:** ADR 0037 · Modelos tributarios y base documental.

**Siguiente paso:** v0.40.0 · Catálogo de operaciones y supuestos autocorregidos: dónde se registra cada operación y su
asiento modelo; el alumno hace el asiento y el ERP lo corrige, con la norma citada en la base documental.

## 2026-10-19 · v0.40.0 · Catálogo de operaciones, supuestos autocorregidos y evaluación de la IA

**Qué se hizo**
- **Catálogo de operaciones y 14 supuestos** con su corrección en la base de datos (0054).
- **Evaluar la IA** y glosario (0055).
- **Web:** pantalla Practicar, «Dónde se registra» en el Tutor y «Evaluar la IA».
- **Diagnóstico de Supabase:** una consulta que dice qué le falta a la base de datos real.
- **Pruebas:** 50 SQL y 148 tests de la web.

**Lo que se aprende**
- **En un ERP casi nada se registra con un asiento manual.** La factura de un proveedor va en Facturas y el ERP elige
  las cuentas: 600 / 472 a 400. En Business Central lo deciden los *posting groups*; en SAP, la determinación de
  cuentas (OBYC). El asiento manual queda para lo que no tiene módulo, como un gasto bancario.
- **Lo que se aprende es la cuenta del PGC, no la subcuenta.** `600` y `60000001` son la misma respuesta.
- **Los errores frecuentes tienen nombre:**
  - el IVA soportado al Haber (es un derecho, va al Debe);
  - la 410 para un proveedor de mercaderías (es la 400);
  - la 485 para un gasto pagado por adelantado (es la 480);
  - la 5293 para un litigio que durará dos años (es la 142, a largo plazo);
  - un cobro que se registra como venta (la venta ya entró con la factura).
- **La variación de existencias no se hace por el neto.** Se da de baja la inicial (610 / 300 por 8.000) y de alta la
  final (300 / 610 por 6.000). Un único 610 / 300 por 2.000 deja la cifra bien, pero el asiento mal: nota 0.
- **Para medir una IA hacen falta casos con solución conocida y la misma regla que para una persona.** Un supuesto de
  IGIC en una empresa de la Península saldría mal por el territorio, no por la contabilidad, así que no se evalúa.
- **Una base de datos de verdad puede no coincidir con el repositorio.** En Supabase faltaban la 0039, la 0040 y la
  0042. Repetirlas habría estropeado funciones que se cambiaron después. Lo correcto es diagnosticar, poner solo lo
  que falta en su versión vigente, y que cada migración nueva se proteja de lo que puede faltar.

**Decisiones:** ADR 0038 · Catálogo de operaciones, supuestos autocorregidos y evaluación de la IA.

**Siguiente paso:** v0.41.0 · Contabilidad analítica: dimensiones por línea de asiento (centro de coste, proyecto,
línea de negocio), reparto de indirectos y la comprobación analítico = contable.

## 2026-10-20 · v0.40.1 · Corrector de supuestos: solo cuentas válidas del PGC

**Qué se hizo**
- **Arreglo del corrector** (0056), con su prueba de regresión (fase 51), que falló antes del arreglo.
- **Web:** cada cuenta rechazada enseña su motivo.
- **Pruebas:** 51 SQL y 149 tests de la web.
- **Orden de la documentación:** ADR 0023 rehecho y número en los títulos de los ADR 0017 a 0021.

**Lo que se aprende**
- **La 4009 no es una 400 más larga.** Es la compra devengada cuya factura no ha llegado al cierre. Cuando llega la
  factura, la deuda pasa a la 400. Lo mismo pasa con la 4309 y la 430 en las ventas.
- **Un corrector que aprueba un error enseña ese error.** Por eso la regla mira el significado de la cuenta, no solo
  sus primeros dígitos.
- **Una revisión externa también se revisa.** Pedía rechazar toda cuenta de 4 dígitos distinta de su madre, lo que
  habría rechazado la 4000 («Proveedores, euros»), y citaba cuentas (4069, 4319, 4759) que no están en el cuadro de
  cuentas del PGC 2007.
- **Una prueba que no ha fallado nunca no demuestra nada.** Desde esta versión, la prueba de cada arreglo se ejecuta
  primero sin el arreglo.

**Decisiones:** ADR 0039 · Corrector de supuestos: solo cuentas válidas del PGC.

**Siguiente paso:** fichas de estudio por pantalla (qué problema resuelve, norma, criterio, BC / SAP, guion de vídeo)
y, después, la v0.41.0 · Impuesto sobre Sociedades en el cierre.

## 2026-10-20 · v0.41.0 · Impuesto sobre Sociedades en el cierre

**Qué se hizo**
- **Cálculo** (0057): del resultado contable a la cuota diferencial, con el régimen sugerido, los ajustes propuestos
  con su artículo y las bases negativas.
- **Asientos** (0058): el corriente y el diferido, como módulo propio, que se deshacen desde su pantalla.
- **Integración** (0059): paso 10 del asistente de cierre, el aviso o error del cierre, el invariante 10, las cuentas
  controladas 630 y 474, el glosario, las fuentes y dos supuestos en Practicar.
- **Web:** la pantalla «Impuesto sobre Sociedades».
- **Pruebas:** 54 SQL y 159 tests de la web. Los cuatro supuestos de referencia se calcularon a mano y coincidieron
  a la primera.

**Lo que se aprende**
- **El resultado del ejercicio es después de impuestos.** El impuesto se contabiliza antes de la regularización.
- **Resultado contable ≠ base imponible.** Las diferencias permanentes no vuelven nunca; las temporarias, sí. Las
  temporarias son las que generan impuesto diferido.
- **Gasto por impuesto = corriente + diferido** (NRV 13.ª). El diferido no cambia lo que se paga, sino el año en que
  se reconoce el gasto.
- **El crédito por pérdidas exige un juicio** (probabilidad de beneficios). Por eso es una casilla y empieza
  desmarcada.
- **Al escribir la prueba de integración apareció un fallo antiguo:** al aviso de cuentas controladas de Nóminas le
  faltaba su nombre. La prueba que lo comprueba falló antes del arreglo.

**Decisiones:** ADR 0040 · Impuesto sobre Sociedades en el cierre.

**Pendiente de validar por Diosvely:** los tipos de 2026 (y los de reducida dimensión de 2025 a 2029) en el BOE, y
qué provisiones vienen marcadas por defecto.

**Siguiente paso:** v0.42.0 · operaciones societarias (constitución, ampliación y reducción de capital, reparto del
resultado y dividendos).

## 2026-10-21 · v0.41.1 · v0.41.2 · Mejoras de uso (contabilizando de verdad)

**Qué se hizo**
- **Pantalla ancha y densidad** (215, 215b, 215c), **menú en acordeón** (216), **asientos en una línea** (217) y
  **panel de IA** (218, 218b).
- Las ideas salieron de usar el ERP a diario con ContaSol al lado. Se apuntan en un documento privado
  (`mejoras-de-uso.md`) y se meten entre versiones.
- **Pruebas:** 187 tests de la web. axe-core sin fallos en modo claro y oscuro, en PC y en móvil.

**Lo que se aprende**
- **La usabilidad también es contabilidad:** un asiento que se mete solo con el teclado ahorra horas al mes. Por eso
  ContaSol y A3 proponen el importe que falta para cuadrar.
- **Probar como lo usa la persona.** El hueco gris del modo Auditor no salía en mis capturas, que eran del modo
  Básico, con un menú más corto. Ahora se prueban los dos modos.
- **Un fallo que solo pasa en un PC sigue siendo un fallo.** Los tests superaban los 5 s en Windows por saturación,
  no por el código. Se arregla con margen y menos procesos a la vez, y queda un test que lo vigila.

**Decisiones:** ADR 0041 · Mejoras de uso: pantalla ancha, menú en acordeón, asientos en una línea y panel de IA.

**Siguiente paso:** v0.42.0 · operaciones societarias (constitución, ampliación y reducción de capital, reparto del
resultado, dividendos y compensación de pérdidas).
