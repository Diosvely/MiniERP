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