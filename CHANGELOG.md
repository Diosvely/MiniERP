# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado semántico.

## [0.46.0] - 2026-10-25
### Añadido
- **Pantalla «Casos»** (migraciones `0067_case_screen.sql` y `0068_case_labels.sql`):
  - en la lista de empresas, «Casos completos»: cargar «Taller Atlántico SL» en una empresa nueva, **completo** (con el
    cierre hecho) o **hasta el cierre** (el cierre lo hace quien estudia);
  - en la empresa del caso, «Caso»: las 19 operaciones con su fecha, su asiento, el porqué, su pantalla y sus asientos,
    y la comparación de las 97 cifras por grupos (igual, pendiente del cierre o diferencia), exportable a Excel;
  - en la base de datos: las operaciones de cada caso (`erp.case_steps`), los asientos de cada operación
    (`erp.case_entries`), `erp.create_case_company`, `erp.case_progress` y el estado de cada cifra en
    `erp.case_compare`.
- **Pruebas:** fase 62 (62 pruebas SQL) y 236 tests en la web.

## [0.45.0] - 2026-10-25
### Añadido
- **Caso completo «Taller Atlántico SL»** (migración `0066_complete_case.sql`): un ejercicio entero de una SL canaria,
  de la constitución a las cuentas anuales, calculado a mano y validado antes de programar.
  - `erp.load_case` lo carga en una empresa nueva con las funciones de cada módulo;
  - `erp.case_compare` compara 97 cifras: cuenta de resultados, balance, ECPN, EFE por los dos métodos, Impuesto sobre
    Sociedades y modelos 420 y 111;
  - catálogo de casos (`erp.cases`) y sus cifras esperadas (`erp.case_expected`).
- **Pruebas:** fase 61 (61 pruebas SQL).

### Corregido
- **Estado de flujos de efectivo:**
  - el pago o cobro de una factura se clasifica como lo que compró o vendió: la base de un inmovilizado, en inversión;
    la de los gastos de constitución (113), en financiación; el impuesto, en explotación. Una factura de inmovilizado sin
    pagar ya no sale como inversión;
  - los intereses devengados y no pagados (506, 527, 528), con los intereses y no en financiación;
  - el impuesto que se lleva a reservas, con el impuesto sobre beneficios y no en financiación;
  - el deterioro de clientes y de existencias, en los ajustes del resultado (A-2 b).

## [0.44.0] - 2026-10-25
### Añadido
- **Subvenciones** (pantalla en Contabilidad; migraciones `0064_grants.sql` y `0065_grants_integration.sql`):
  - de capital, vinculadas a su activo de Inmovilizado, y a la explotación;
  - reintegrables (522 / 172) y su paso a no reintegrables;
  - concesión con su efecto impositivo (8301 / 479) y cobro;
  - imputación en el cierre con la amortización del activo (840 / 746, 479 / 8301);
  - al dar de baja el activo, lo pendiente pasa a resultados;
  - «Deshacer» del último movimiento al primero.
- **Grupos 8 y 9** en el plan de cuentas, en el balance (A-2) y en el estado de flujos de efectivo. En el cierre del
  ejercicio se regularizan contra la 130.
- **Estado de cambios en el patrimonio neto** (Informes), para todas las empresas: parte A (ingresos y gastos
  reconocidos) y parte B (estado total por columnas), comprobado contra el balance. Se puede exportar a Excel.
- **Asistente de cierre:** paso nuevo, el 10 «Subvenciones»; el cierre pasa a ser el 13. Aviso del cierre si falta la
  imputación.
- **Auditor:** comprobación `grants_ledger`.
- **Cuentas controladas:** 94, 84, 83 y 4708.
- **Glosario:** subvención de capital, subvención reintegrable, grupos 8 y 9 y ECPN.
- **Practicar:** 22 supuestos.
- **Pruebas:** fases 59 y 60 (60 pruebas SQL) y 227 tests en la web.

## [0.43.0] - 2026-10-24
### Añadido
- **Financiación** (pantalla en Contabilidad; migraciones `0062_loans.sql` y `0063_financing_integration.sql`):
  - **préstamos** con sistema francés (mensual, trimestral, semestral o anual), a coste amortizado con el tipo de
    interés efectivo (NRV 9.ª): las comisiones van dentro de los intereses, no a gasto el primer día;
  - **arrendamiento financiero** (NRV 8.ª), por el menor del valor razonable y el valor actual de los pagos:
    - el alta crea la ficha del activo en Inmovilizado;
    - cada cuota se registra como factura recibida de la entidad, con su IVA / IGIC;
  - **deuda a corto y a largo plazo**, con la reclasificación del cierre (1700 → 5200, 1740 → 5240);
  - **intereses devengados al cierre**, con el tipo efectivo en base 30/360, a la 527 / 528. La cuota siguiente los
    salda;
  - cálculo en vivo del cuadro y del asiento antes de dar de alta;
  - «Deshacer» del último movimiento al primero. Deshacer la cuota del leasing emite la rectificativa completa.
- **Asistente de cierre:** paso nuevo, el 9, «Préstamos y leasing». El auditor pasa al 10, el Impuesto sobre Sociedades
  al 11 y el cierre al 12.
- **Auditor:** comprobación `financing_ledger` (las cuentas de los préstamos frente al módulo).
- **Cuentas controladas:** 170, 171, 174, 520, 521, 524, 527 y 528.
- **Glosario:** coste amortizado, tipo de interés efectivo, arrendamiento financiero y deuda a corto y a largo plazo.
- **Practicar:** 20 supuestos.
- **Pruebas:** fases 57 y 58 (58 pruebas SQL) y 214 tests en la web.

## [0.42.0] - 2026-10-21
### Añadido
- **Operaciones societarias** (pantalla en Contabilidad; migraciones `0060_equity_operations.sql` y
  `0061_equity_integration.sql`):
  - forma jurídica de la empresa (SA / SL);
  - constitución y ampliación de capital, con prima y con cargo a reservas, y dividendos pasivos;
  - reparto del resultado: propuesta con la reserva legal (arts. 274 y 4.2 LSC) y la comprobación del art. 273;
  - dividendo a cuenta con el límite del art. 277;
  - pago del dividendo con la retención del 19 % (47512, modelo 123);
  - pérdidas: compensarlas con reservas o reducir el capital;
  - historial con «Deshacer», de la última a la primera.
- Facturas recibidas a la **113** (gastos de constitución y de ampliación, NRV 9.ª). En el Impuesto sobre Sociedades
  son un ajuste deducible y su ahorro de impuesto va a reservas.
- **Cierre:** aviso si el resultado del año anterior sigue sin repartir.
- **Cuentas controladas:** 190, 194, 1030, 5580, 526 y 557.
- **Glosario:** reserva legal, dividendo a cuenta, prima de emisión y desembolsos pendientes.
- **Fuentes:** la LSC.
- **Practicar:** 18 supuestos.
- El subgrupo 19 del PGC en la plantilla.
- **Pruebas:** fases 55 y 56 (56 pruebas SQL) y 200 tests en la web.
### Corregido
- La comprobación de la 4751 con el 111 / 115 ya no cuenta la retención de dividendos (47512).

## [0.41.2] - 2026-10-21
### Añadido
- **Panel de IA:** botón «✨ IA» abajo a la derecha, con el **Tutor de asientos** como conversación y el **Analista IA**
  del ejercicio que estés viendo (EFE, Ratios).
  - «Pasar al asiento» lleva la propuesta a Nuevo asiento desde cualquier pantalla.
  - En el PC ancho el panel va al lado y no tapa nada.
  - La conversación no se guarda.
### Cambiado
- Nuevo asiento ya no tiene el Tutor encima. El EFE y los Ratios abren el Analista desde un botón.
- Tests: 30 s por test y la mitad de los núcleos, para que en Windows no se agote el tiempo por saturación.
### Corregido
- Contraste de «Dentro de la zona» y «Por debajo» en los Ratios (modo claro).

## [0.41.1] - 2026-10-21
### Añadido
- **Pantalla ancha en el PC:**
  - el contenido llega hasta 1.600 px;
  - las tarjetas pequeñas van de dos en dos y Cierre muestra el asistente al lado;
  - letra de 14 px y menos relleno desde 900 px.
- **Menú en acordeón:** una sola área abierta (la de la pantalla actual), flechas del teclado y área «Empresa».
- **Asientos en una línea:**
  - Enter avanza y crea la línea nueva;
  - lo que falta para cuadrar sale en gris (Enter o «=» lo ponen);
  - línea vacía + Enter lleva a Contabilizar;
  - Ctrl + Supr o la papelera borran la línea;
  - fecha, documento y concepto van en una fila.
### Quitado
- Los botones «=» y «✕» de cada línea del asiento.
### Corregido
- Móvil: Clientes y proveedores se salía 90 px de la pantalla, y la fecha de Nuevo asiento, 5 px.
- Modo Auditor: hueco gris bajo la ruta cuando el menú era más alto que el contenido.
- Aviso de cuentas controladas: faltaba el nombre del módulo Nóminas.
- Contraste de la etiqueta «Factura» del Libro diario.

## [0.41.0] - 2026-10-20
### Añadido
- **Impuesto sobre Sociedades** (pantalla en Contabilidad; migraciones `0057_corporate_tax.sql`,
  `0058_corporate_tax_posting.sql` y `0059_corporate_tax_integration.sql`):
  - del resultado contable a la cuota diferencial, en el orden del modelo 200;
  - régimen sugerido por la cifra de negocios del año anterior (general, reducida dimensión, microempresa, nueva
    creación), con los tipos y tramos por año;
  - ajustes propuestos con su artículo de la LIS (amortización, deterioros, provisiones) y ajustes manuales;
  - bases negativas: las más antiguas primero, con el límite del 70 % y el millón (art. 26);
  - crédito fiscal (4745) opcional, desmarcado por defecto (NRV 13.ª);
  - dos asientos del módulo, el corriente (6300 / 473 / 4752 o 4709) y el diferido (4740 / 4745 / 6301), que se
    deshacen desde la pantalla;
  - vista previa de los asientos, Excel e Imprimir.
- **Cierre:** el paso 10 del asistente, «Impuesto sobre Sociedades». La vista previa avisa si falta (modo guiado) o no
  deja cerrar (modo estricto), y avisa si la 473 no queda a cero.
- **Invariante 10:** gasto por impuesto (630) = el de la declaración.
- **Cuentas controladas:** la 630 y la 474.
- **Glosario:** base imponible, diferencia temporaria, impuesto corriente e impuesto diferido.
- **Fuentes:** la Ley 27/2014 con todos los artículos que se usan.
- **Practicar:** 16 supuestos (+ impuesto corriente y diferido). Catálogo de operaciones: 18.
- Pruebas: fases 52, 53 y 54 (54 pruebas SQL) y 159 tests en la web.
### Corregido
- El aviso de cuenta controlada de Nóminas mostraba la clave «ctl.module.payroll» en lugar del nombre del módulo.

## [0.40.1] - 2026-10-20
### Corregido
- **Corrector de supuestos** (migración `0056_grader_fixes.sql`, prueba `test_fase51_grader_fixes.sql`):
  - una cuenta de la respuesta solo vale si son dígitos y existe en el PGC (o, si es una subcuenta, su cuenta de 3
    dígitos);
  - las cuentas de 4 dígitos con otro significado (4009, 4109, 4309, 4409) ya no casan con su cuenta madre, y se
    explica la diferencia en las pistas;
  - se aplica igual a la persona y a la IA.
- **Practicar:** cada cuenta rechazada enseña su motivo («no es una cuenta» o «no existe en el PGC»).
- **ADR 0023:** se había guardado con el texto del Pull Request; ahora tiene su formato. Los ADR 0017 a 0021 llevan
  su número en el título.
### Añadido
- `erp.pgc_distinct_accounts`, `erp.pgc_account_problem` y `erp.account_matches`.
- Regla de trabajo: cada arreglo lleva una prueba que falla sin él. Cada ADR, desde el 0039, tiene una sección
  «Cómo explicarlo».
- 149 tests en la web.

## [0.40.0] - 2026-10-19
### Añadido
- **Catálogo de operaciones y supuestos autocorregidos** (migración `0054_operations_exercises.sql`, prueba
  `test_fase49_operations_exercises.sql`):
  - `erp.operations`: 17 operaciones con su pantalla y su asiento modelo; `erp.operation_for_lines` dice a qué
    operación se parece un asiento;
  - `erp.exercises`: 14 supuestos (5 básicos, 6 intermedios, 3 avanzados) con el asiento esperado, la explicación,
    los errores frecuentes, el concepto del glosario y sus fuentes;
  - `erp.grade_exercise`: corrige línea a línea por grupo o subgrupo del PGC, lado e importe, con alternativas y
    errores frecuentes;
  - `erp.submit_exercise` y `erp.v_exercise_progress`: intentos y progreso de cada usuario;
  - seis fuentes nuevas en la base documental: PGC, LIS, LIRPF, RIRPF, LGSS y la Orden de cotización 2026.
- **Evaluar la IA** (migración `0055_practice_integration.sql`, prueba `test_fase50_practice_integration.sql`):
  - los intentos de la IA guardan el modelo que contestó;
  - el progreso enseña su último intento;
  - glosario: «Supuesto práctico» y «Catálogo de operaciones».
- **Web:**
  - pantalla **Practicar** (🎓): supuestos por nivel, corrección línea a línea, solución, 📘 y «dónde se registra»;
  - «Evaluar la IA»;
  - «📍 Dónde se registra» en el Tutor de asientos;
  - 148 tests en total.
- **Diagnóstico de Supabase:** `scripts/generar-diagnostico.sh` genera `database/diagnostico-supabase.sql`, una
  consulta de solo lectura que dice qué le falta o sobra a una base de datos frente al repositorio.
### Cambiado
- La 0054 repone el glosario completo antes de usarlo: una base de datos a la que le faltaban conceptos de migraciones
  antiguas ya no falla.
- El test del glosario solo lee las filas de `insert into erp.concepts`.
- La prueba de conceptos (fase 32) cuenta 54 términos.
### Corregido
- Practicar: el aviso «No cuadra» va debajo del total y ya no se sale de la línea.

## [0.39.0] - 2026-10-19
### Añadido
- **Casillas de los modelos** (migración `0051_tax_forms.sql`, prueba `test_fase46_tax_forms.sql`):
  - 303 y 420 trimestrales y resúmenes anuales 390 y 425, desde el libro registro de facturas;
  - rectificativas en «modificación de bases» y «rectificación de deducciones»;
  - bienes de inversión desde 3.005,06 € (art. 108 LIVA; art. 40 Ley 20/1991);
  - compensación de periodos anteriores y volumen de operaciones.
- **Modelos 347 y 349** (migración `0052_forms_347_349.sql`, prueba `test_fase47_forms_347_349.sql`):
  - 347: terceros de más de 3.005,06 € por trimestres, claves A y B, sin operaciones intracomunitarias, exportaciones
    ni facturas con retención;
  - 349: claves E, S, A e I por NIF-IVA, rectificaciones de periodos anteriores y aviso de presentación mensual.
- **Base documental e integración** (migración `0053_forms_integration.sql`, prueba `test_fase48_forms_integration.sql`):
  - `erp.sources`: fuentes oficiales con su enlace, el artículo y la fecha de comprobación (copia de `src/sources.js`);
  - comprobaciones «modelos trimestrales frente a las liquidaciones», «terceros del 347 sin NIF» y «fuentes sin revisar
    en más de un año»;
  - las comprobaciones citan sus fuentes;
  - términos «Modelo tributario (casillas)» y «Modelo 347» en el glosario.
- **Web:**
  - pantalla **Modelos** (303/420, 390/425, 347, 349) con Excel e Imprimir;
  - botón **📘 Fuentes** en cada modelo y en Comprobaciones;
  - 134 tests en total.
### Cambiado
- El test del glosario y el nuevo de las fuentes admiten finales de línea de Windows (CRLF).
- La prueba de operaciones al azar (fase 34) comprueba que el resumen anual es la suma de los trimestres.

## [0.38.0] - 2026-10-18
### Añadido
- **Nóminas** (migración `0049_payroll.sql`, prueba `test_fase44_payroll.sql`):
  - tipos de cotización por año, los de 2026 según la Orden PJC/297/2026, con la base máxima y la cotización adicional de
    solidaridad;
  - ficha del empleado (ficticio, sin datos personales): contrato, salario, pagas extra prorrateadas o no, % de IRPF y
    % de AT / EP;
  - cálculo del recibo (`erp.payslip_calc`): base de cotización con la prorrata de las pagas (art. 147 LGSS), cuotas de la
    empresa y del trabajador, IRPF y líquido;
  - asiento de la nómina del mes: 640 / 642 contra 476, 4751 y 465, con la paga extra devengada cada mes y pagada en su
    mes;
  - pago del líquido (465 / 57x) y de los seguros sociales (476 / 57x), y deshacer.
- **Integración** (migración `0050_payroll_integration.sql`, prueba `test_fase45_payroll_integration.sql`):
  - comprobación «Nóminas frente a la contabilidad (465 / 476)»;
  - el modelo 111 incluye las nóminas en las casillas 01 a 03;
  - términos «Nómina» y «Seguridad Social a cargo de la empresa» en el glosario.
- **Web:**
  - pantalla **Nóminas**: nómina del mes con su vista previa, nóminas contabilizadas con sus pagos, recibos de salarios y
    ficha del empleado;
  - en Retenciones IRPF, la fila de nóminas del modelo 111;
  - 126 tests en total.
### Cambiado
- La 465 y la 476 pasan a ser cuentas controladas (por Nóminas).
- La comprobación de retenciones (4751) suma el IRPF de las nóminas.
- La prueba de operaciones al azar (fase 34) añade doce meses de nóminas con sus pagos.

## [0.37.0] - 2026-10-18
### Añadido
- **Provisiones** (migración `0045_provisions.sql`, prueba `test_fase40_provisions.sql`):
  - de impuestos (141 / 5292), responsabilidades (142 / 5293) y operaciones comerciales (4999);
  - dotación, revisión (más gasto o exceso a 795x; las comerciales revierten la anterior y dotan la nueva),
    reclasificación a corto plazo, aplicación al pagar y deshacer;
  - la 633 / 638 en la plantilla del PGC.
- **Deterioro del inmovilizado** (migración `0046_asset_impairment.sql`, prueba `test_fase41_asset_impairment.sql`):
  - deterioro (69x / 29x) y reversión con su límite (29x / 79x);
  - amortización recalculada por tramos en la vida útil que queda;
  - la baja cancela la 29x.
  - La **rectificativa de una compra de inmovilizado** ajusta el coste de la ficha (hallazgo de la v0.35.0).
- **Existencias por inventario y asistente de cierre** (migración `0047_inventory_closing.sql`, prueba
  `test_fase42_inventory_closing.sql`):
  - regularización 61x / 71x con el recuento del cierre;
  - deterioro 693 / 39x y reversión 793;
  - `erp.closing_checklist` con los diez pasos del cierre.
- **Integración** (migración `0048_closing_integration.sql`, prueba `test_fase43_closing_integration.sql`):
  - comprobaciones «provisiones frente a la contabilidad», «provisiones sin revisar en el cierre» y «existencias frente a
    los inventarios»;
  - avisos del cierre;
  - términos «Provisión», «Deterioro del inmovilizado» y «Variación de existencias» en el glosario.
- **Web:**
  - Ajustes de cierre con provisiones e inventario;
  - deterioro y sucesos en la ficha del activo;
  - asistente en Cierre del ejercicio.
  - 118 tests en total.
### Cambiado
- La 141, 142, 5292, 5293, 499, 290-292, 30-36 y 39 pasan a ser cuentas controladas.
- La prueba de operaciones al azar (fase 34) añade provisiones, deterioro de activos, rectificativas de compras de
  activos e inventario.

## [0.36.0] - 2026-10-18
### Añadido
- **Periodificaciones** (migración `0043_year_end_adjustments.sql`, prueba `test_fase38_year_end_adjustments.sql`):
  - gasto o ingreso anticipado (480 / 485) y devengado sin factura (4009 / 4309), contra la propia cuenta de gasto o
    ingreso;
  - importe directo o calculado por meses;
  - reversión con un asiento nuevo en el ejercicio siguiente, una a una o todas a la vez.
- **Deterioro de clientes** (misma migración):
  - individual sobre lo pendiente y global por tramos de antigüedad (694 / 490);
  - reversión (490 / 794) e insolvencia firme (650 / 430, aplicando el deterioro), que cierra la partida abierta;
  - avisos fiscales de los arts. 13.1 y 104 LIS.
- **Integración** (migración `0044_adjustments_integration.sql`, prueba `test_fase39_adjustments_integration.sql`):
  - comprobaciones «periodificaciones y deterioros frente a la contabilidad», «periodificaciones del año anterior sin
    revertir» y «deterioros de facturas ya cobradas»;
  - aviso en el cierre del ejercicio;
  - términos «Periodificación» y «Deterioro de clientes» en el glosario.
- Pantalla **Ajustes de cierre** (menú Auditor › Contabilidad, y enlace desde Cierre del ejercicio). `src/adjustments.js`
  con sus tests (112 en total).
### Cambiado
- La 480, la 485, la 4009, la 4309 y la 490 pasan a ser cuentas controladas.
- La prueba de operaciones al azar (fase 34) hace los ajustes de cierre, los revierte, cobra e incluye insolvencias.
### Corregido
- En Comprobaciones y en el aviso de cuenta controlada faltaban los nombres del módulo Inmovilizado (v0.35.0).

## [0.35.0] - 2026-10-16
### Añadido
- **Inmovilizado** (migración `0041_fixed_assets.sql`, prueba `test_fase36_fixed_assets.sql`):
  - ficha del activo, dada de alta desde la factura recibida o sin factura;
  - amortización lineal por meses (el primer mes, por días) con cuadro de amortización y asiento 68x/28x hasta la fecha
    que se elija;
  - baja o venta con su factura emitida a la cuenta del activo, y resultado en 67x/77x; se puede deshacer;
  - tabla fiscal del art. 12.1.a LIS, con aviso si la amortización contable supera el máximo;
  - las cuentas 20x/21x/22x y 28x pasan a ser controladas por el módulo.
- **Integración** (migración `0042_assets_integration.sql`, prueba `test_fase37_assets_integration.sql`):
  - comprobaciones «inmovilizado frente a sus fichas» y «amortización pendiente»;
  - aviso en el cierre del ejercicio;
  - términos «Inmovilizado» y «Valor neto contable» en el glosario.
- Pantalla **Inmovilizado** (menú Auditor › Contabilidad y acceso desde el Inicio). `src/assets.js` con sus tests
  (104 en total).
### Cambiado
- Las facturas emitidas admiten líneas a la cuenta del activo (20x/21x/22x) para vender inmovilizado.
- La prueba de operaciones al azar (fase 34) compra, amortiza y vende activos.
### Corregido
- La **prorrata** ya no computa las ventas de bienes de inversión (art. 104.Tres.2.º LIVA).
- `scripts/volcar-funciones.sh` reconoce también las redefiniciones en mayúsculas (`CREATE OR REPLACE FUNCTION`).

## [0.34.0] - 2026-10-16
### Añadido
- **Invariantes contables** (`erp.integrity_checks`, migración `0040_integrity_checks.sql`): asientos y sumas y
  saldos que cuadran, Activo = PN + Pasivo, 129 = resultado de la PyG, apertura = cierre, asiento + contraasiento = 0,
  tercero de la factura = total − retención, 472/477 = libro registro, y variación de la 57 = EFE directo = indirecto.
- **Prueba con operaciones al azar** (`test_fase34_invariants.sql`): dos empresas (IVA e IGIC), unas 300 operaciones de
  todos los tipos, liquidaciones sin diferencias, cierre y año siguiente; los invariantes se exigen cada 25 operaciones.
- **Supuestos de referencia** (`test_fase35_reference_cases.sql`): cinco casos con la solución calculada a mano desde la
  norma y el artículo de cada cifra (IRPF y 111/115, IGIC y 420, AIB e ISP, recargo de equivalencia, prorrata con
  redondeo al entero superior). El ERP coincide al céntimo en balance, PyG y modelos.
- `erp.integrity_checks` en el volcado de funciones (146).

## [0.33.1] - 2026-10-15
### Corregido
Fallos encontrados por una revisión externa del proyecto, con pruebas de regresión (`test_fase33_review_fixes.sql`,
que falla sin el arreglo):
- La **liquidación de IVA / IGIC** incluye también las 472/477 que no están configuradas en Impuestos, en el impuesto
  del territorio. Antes, un apunte en una 47700001 sin configurar se saltaba el cuadre del 303/420. Migración
  `0039_review_fixes.sql`.
- Los **ADR 0006–0011** y la **guía de Git** pasan a UTF-8 (en GitHub se veían con «�») y recuperan las flechas «→»
  que se habían perdido.
### Añadido
- Comprobación del auditor **«cuota que no corresponde a base × tipo»**: un apunte manual en la 472/477 con base 100
  al 21 % y cuota 500 sale señalado (debería ser 21). En modo estricto, ese asiento ya no se podía contabilizar.
- **`database/funciones/`**: la versión vigente de cada una de las 145 funciones, con su índice y las migraciones
  donde se definió, para estudiarlas sin rastrear migraciones. Lo genera `scripts/volcar-funciones.sh`.
### Cambiado
- La ADR 0010 se matiza (con la 0016 y la 0021): el ERP no es el programa oficial de una empresa, pero sí se pueden
  **estudiar** contabilidades reales, en privado y nunca en el repositorio.

## [0.33.0] - 2026-10-15
### Añadido
- **Cuentas controladas** (como SAP, Business Central o Versat):
  - reglas por prefijo en la base de datos (400/410/430/440, 472/477, 4750, 4700);
  - **modo estricto o guiado** por empresa;
  - en estricto, un asiento manual sobre esas cuentas no se contabiliza;
  - migración `0036_controlled_accounts.sql` y prueba `test_fase30_controlled_accounts.sql`.
- **Comprobaciones del auditor** a una fecha: 472/477 frente al libro registro, 4751 frente al 111/115, terceros
  frente a sus facturas, saldos anómalos, impuesto del otro territorio y asientos manuales sobre cuentas controladas.
  Migración `0037_audit_checks.sql` y prueba `test_fase31_audit_checks.sql`.
- Pantalla **Comprobaciones** (menú Auditor) con el modo de control, cifras, casos enlazados y la pantalla donde se
  arregla.
- **Aviso en el formulario de asiento** antes de contabilizar sobre una cuenta controlada, y error traducido con
  enlace a su módulo.
- **Conceptos** en la base de datos (`erp.concepts`), con sus cuentas del PGC: migración `0038_concepts.sql` y prueba
  `test_fase32_concepts.sql`.
- Glosario: 4 términos nuevos (cuenta controlada, modo estricto o guiado, antigüedad de saldos, comprobación) y las
  cuentas del PGC de cada término; el buscador encuentra por cuenta.
- `src/controlled.js` con sus tests, y `tests/glossary.test.js`, que falla si el glosario y `erp.concepts` se separan
  (98 tests en total).
### Cambiado
- Las empresas nuevas se crean en modo estricto (se elige al darlas de alta); las existentes y las importadas siguen
  en guiado.
### Corregido
- Contraste del «✓ Cuadra» de los totales del asiento (WCAG AA).

## [0.32.0] - 2026-10-14
### Añadido
- **Cobros y pagos contra la factura:**
  - pagar o cobrar una o varias facturas, entera o en parte; el ERP hace el asiento;
  - vista previa del asiento, anulación con contraasiento, y vinculación de pagos hechos a mano sin asiento nuevo;
  - migración `0035_payments.sql` y prueba `test_fase29_payments.sql`.
- **Antigüedad de saldos** de proveedores y clientes a una fecha, por tramos, con el saldo contable para detectar
  movimientos sin vincular; con Excel e imprimir.
- **Días de pago** en la ficha del tercero y **vencimiento** de las facturas nuevas.
- **Estado de cada factura** (pagada, en parte o pendiente, vencida) en el libro registro, con enlace a pagar o cobrar.
- Término «Partida abierta» en el glosario; `src/payments.js` con sus tests (89 en total).
### Cambiado
- El nº de asiento de las facturas y de los pagos lleva a la ficha del asiento.
- El diario marca los asientos de pagos y cobros.
- El menú Básico tiene 9 entradas.

## [0.31.0] - 2026-10-13
### Añadido
- **Retenciones guiadas por reglas:**
  - ficha del tercero con **forma jurídica** (sale del NIF) y **retención por defecto**;
  - reglas de retención en la base de datos (`erp.withholding_rules`: 623 profesionales, 621 alquiler);
  - el ERP calcula en el Tutor la retención y lo que queda a pagar al tercero;
  - avisos de retención que falta o que no procede;
  - migración `0033_withholding_rules.sql` y prueba `test_fase27_withholding_rules.sql`.
- La **factura recibida** toma la retención de la ficha del tercero.
- **Panel «Uso de la web»** solo para el propietario: visitantes de la demo, registros, activos, empresas,
  importaciones y consultas a la IA, con barras por día. Migración `0034_web_usage.sql` y prueba
  `test_fase28_web_usage.sql`.
- `src/partnerTax.js` y `barPath` en `src/chart.js`, con sus tests (83 en total).
### Cambiado
- **Tutor de asientos:**
  - instrucciones con las reglas de retención y un ejemplo resuelto;
  - la IA indica el código de la retención;
  - los avisos informativos ya no provocan una segunda vuelta.
### Corregido
- La limpieza nocturna de invitados ya no hace perder la historia de visitas a la demo (`erp.guest_history`).
- Dos desplegables sin etiqueta en Terceros, y el territorio, que se salía de la tarjeta en el móvil.

## [0.30.0] - 2026-10-12
### Añadido
- **Inicio con indicadores** a la fecha de trabajo:
  - tesorería, resultado frente al año anterior, IVA/IGIC del trimestre, pendiente de cobro y de pago;
  - gráfico de tesorería a fin de mes, con "Ver como tabla";
  - se muestran según el tipo de empresa y el avance de la ruta guiada;
  - migración `0031_home_kpis.sql` (`erp.home_kpis`) y prueba `test_fase25_home_kpis.sql`.
- **Análisis horizontal** en el Balance y la PyG: variación en importe y en %, y el año anterior también al
  desplegar una partida.
- **Cascada del EFE** (de dónde viene y a dónde va el dinero) y **evolución de cada ratio** en todos los ejercicios.
- **Exportar a Excel** e **Imprimir / guardar en PDF** en el Balance, la PyG, el EFE, sumas y saldos, el mayor y el
  diario.
- Mayor y sumas y saldos en **tarjetas** en el móvil.
- `src/chart.js`, `src/compare.js` y `src/exportXlsx.js`, con sus tests (75 en total).
### Cambiado
- Fechas en formato dd/mm/aaaa en el diario y el mayor; cifras con `tabular-nums` en todas las tablas.
- En la ruta guiada completa, los pasos se pliegan bajo los indicadores.
### Corregido
- **Balance a mitad de ejercicio:** ahora se compara con el cierre del ejercicio anterior, no con la misma fecha del
  año anterior (migración `0032_comparative_statements.sql`, prueba `test_fase26_comparative.sql`).
- Contraste insuficiente en los pasos pendientes del recorrido del auditor.
- La tabla del Balance y la PyG con desplazamiento horizontal ahora se puede mover con el teclado.

## [0.29.1] - 2026-10-11
### Seguridad
- **Corregido:** un admin de su propia empresa podía marcarse como titular de los datos
  (`erp.company_users.data_owner`) y, con eso, usar la IA y publicar su empresa como demo con cualquier mención.
  Migración `0030_protect_data_owner.sql`: solo el propietario de la app pone esa marca. Regresión desde la v0.24.0
  (migración 0027), encontrada en una revisión de seguridad externa.
- Prueba `test_fase24_data_owner.sql`.
- `SECURITY.md`: cómo avisar de un fallo en privado.
- Dependabot (`.github/dependabot.yml`) para npm y GitHub Actions.
- `docs/seguridad-supabase.md`: lista de ajustes del panel de Supabase y consultas de revisión.
### Añadido
- Licencia **MIT** (`LICENSE`).

## [0.29.0] - 2026-10-11
### Añadido
- **Borrar la empresa entera** (zona de peligro): resumen de lo que se borra, confirmación escribiendo el nombre y
  progreso por tandas. Solo el admin; no se puede borrar una demo publicada.
- **Fecha de trabajo** de cada empresa (`src/workDate.js`): hoy, o la del último asiento si la empresa es histórica
  o importada. Es el año, el trimestre y la fecha por defecto de todas las pantallas, y se muestra en el Inicio.
- **Rastro contable:** ficha del asiento (`#/empresa/<id>/asiento/<año>/<nº>`) desde el libro mayor; cada cuenta de
  la ficha y del diario abre su libro mayor (`…/reports/mayor/<cuenta>/<año>`).
- Migración `0029_performance.sql`:
  - `erp.general_ledger(empresa, año, cuenta, hasta)`;
  - `erp.delete_company_step(empresa)`;
  - índices en las claves foráneas que no los tenían.
- Prueba `test_fase23_performance.sql`.
- Tests de la web: lectura por páginas, borrado por tandas, fecha de trabajo y rutas del rastro (62 en total).
- Error en lenguaje claro para *statement timeout*.
### Cambiado
- El libro mayor usa `erp.general_ledger` en lugar de la vista `v_general_ledger` (que se mantiene).
- El diario, el mayor, sumas y saldos y las listas de cuentas se leen por páginas (`src/paging.js`).
- "Descartar" en la importación borra la empresa por tandas.
### Corregido
- El libro mayor daba *statement timeout* con empresas de varios años.
- Las listas de más de 1.000 filas se cortaban sin aviso y los totales salían mal.
- Borrar una empresa grande tardaba minutos (claves foráneas sin índice).
- La fecha "de hoy" se calculaba en UTC.

## [0.28.0] - 2026-10-11
### Añadido
- **Cabeceras de seguridad** (`frontend/public/_headers`): Content-Security-Policy, X-Frame-Options,
  X-Content-Type-Options, Referrer-Policy, Permissions-Policy, Strict-Transport-Security y
  Cross-Origin-Opener-Policy.
- **CAPTCHA con Cloudflare Turnstile** en "Ver la demo", "Crear cuenta" e "Iniciar sesión"
  (`VITE_TURNSTILE_SITE_KEY`).
- **Limpieza automática de invitados:** migración `0028_guest_cleanup.sql` con `erp.cleanup_guests(días)` y tarea
  diaria de `pg_cron`. Prueba `test_fase22_guest_cleanup.sql`.
- **Tests de la web con Vitest** (47) en `frontend/tests/`, ejecutados en la CI (`npm test`).
- `frontend/.env.example` con las variables de entorno.
- Error en lenguaje claro para el CAPTCHA.
### Cambiado
- El enlace `?demo` ya no crea un invitado al cargar la página: abre la entrada con el botón de la demo destacado.
- `/api/ai` y `/api/tutor` responden solo con un código de error, sin el texto interno de PostgreSQL ni del modelo;
  el detalle queda en el registro de Cloudflare.
- `/api/ai` y `/api/tutor` validan que `company_id` sea un UUID (400) y limitan el tamaño de la petición (413).
- Simulador de Supabase de las pruebas: `auth.users.is_anonymous`.
### Seguridad
- Un robot ya no puede crear usuarios anónimos sin resolver el CAPTCHA, ni leer mensajes internos de la base de datos
  a través de la IA.

## [0.27.0] - 2026-10-10
### Añadido
- **Glosario en la app:**
  - 36 términos (español / inglés) con su equivalente en Business Central y SAP;
  - **ⓘ con globo** junto a la ruta de cada pantalla y en Debe/Haber;
  - página **Glosario** con buscador (`#/glosario`), enlazada desde la cabecera.
- **Iconos `lucide-react`** en la cabecera, la entrada, el Inicio, los errores, los estados vacíos y las plantillas.
- Variables de color `--exito`, `--alerta`, `--alerta-fondo`, `--error` y `--sobre-color`, con versión oscura.
- Foco visible común (`:focus-visible`) en botones, enlaces y campos.
- **Capturas** de la app en `docs/capturas/` y en el README.
### Cambiado
- `<html lang>` sigue al idioma elegido, y la página tiene título ("Mini ERP · Contabilidad española").
- Alta de empresa con etiquetas visibles.
- En modo oscuro, el texto sobre los botones y las etiquetas de color es oscuro, para tener contraste suficiente.
- Las plantillas de asientos llevan icono en lugar de emoji en su texto.
### Corregido
- Accesibilidad: 0 fallos con axe-core (WCAG 2 A/AA) en seis pantallas y en los dos modos. Antes había 20 en claro
  y 31 en oscuro: contraste, `lang`, título, selects sin nombre y enlace sin subrayar dentro de un texto.

## [0.26.0] - 2026-10-10
### Añadido
- **Errores en lenguaje claro:**
  - qué ha pasado, qué hacer y un botón **"Ir a…"** a la pantalla donde se arregla;
  - el mensaje original queda en "Detalle técnico";
  - 85 reglas (`src/errors.js`) para asientos, facturas, impuestos, ejercicios, permisos, IA, importación e inicio
    de sesión.
- **Pantalla de entrada:** propuesta de valor, **"Ver la demo sin registrarme"** destacado, pestañas Iniciar sesión /
  Crear cuenta, mostrar u ocultar la contraseña, requisito visible, aviso de confirmación por correo y pie con GitHub.
- **Plantillas de asientos "¿Qué ha pasado?":** he comprado mercaderías, he vendido, he cobrado a un cliente, he
  pagado a un proveedor y nómina.
- **Buscador de cuentas por número o nombre** (sin acentos, con ↑ ↓ Enter Escape).
- Explicaciones plegables **"¿Qué es el Debe y el Haber?"** y **"¿Guardar borrador o contabilizar?"**.
### Cambiado
- Todas las cajas de error usan `ErrorBox`.
- El acceso deja de ser un formulario dentro de `App.jsx` y pasa a ser el componente `Landing`.
- La contraseña nueva pide al menos 8 caracteres, igual que "Cambiar contraseña".
- La lista de cuentas del asiento ya no usa el `datalist` del navegador.

## [0.25.0] - 2026-10-10
### Añadido
- **Pantalla de Inicio** en cada empresa:
  - ruta guiada de 6 pasos para llevar un trimestre, que se marcan solos, con barra de progreso;
  - **Modo auditor** (recorrido por las cuentas) para las empresas importadas y las demos;
  - accesos rápidos y últimos movimientos.
- **Modo Básico / Auditor:** menú corto de 8 entradas o completo, con nombres sencillos y el término técnico debajo.
- **Rutas** `#/empresa/<id>/<pantalla>`: el botón atrás, recargar y compartir el enlace de una pantalla funcionan.
- **Aviso "Cargando…" global** mientras llegan datos de Supabase.
- **Estados vacíos con la siguiente acción** (Configurar impuestos, Hacer un asiento, Dar de alta un tercero, Abrir
  el plan de cuentas) y enlace **"Ver en el diario"** tras contabilizar.
- **Deshacer** al borrar una línea del asiento.
- **Integración continua** con GitHub Actions: pruebas SQL, lint, build y `npm audit` en cada PR; `main` protegida.
- `scripts/test-db.sh`: ejecuta todas las pruebas SQL, cada una en una base limpia.
### Cambiado
- El atajo "−" del asiento solo borra la línea desde el campo de cuenta vacío; en los importes se escribe como signo.
- Nombres del menú en lenguaje sencillo: "Clientes y proveedores", "Revisión de saldos", "Liquidar IVA/IGIC",
  "Cuenta de resultados".
- Las empresas de la lista son enlaces: se abren con el teclado o en otra pestaña.
- `package.json`: nombre `minierp-frontend`.
- Lint: las reglas nuevas de React 19 (`set-state-in-effect`) pasan a aviso hasta refactorizar la carga de datos.
### Corregido
- "Importar subcuentas (CSV)" mostraba como título el texto del importador del diario (clave i18n duplicada).
- Carácter invisible (BOM) escrito tal cual en `importers.js`.
- `tutor.js` reasignaba la variable del error en el `catch` (lint `no-ex-assign`).

## [0.24.0] - 2026-10-10
### Añadido
- **Rol Miembro (titular de los datos):** quien cede su dataset entra solo en su empresa, trabaja en ella como
  contable, usa el Analista y el Tutor de IA con una cuota diaria y decide si la publica como demo, con su mención.
- **Datos maestros › Accesos** (solo el propietario): dar y quitar acceso por email, ver roles y consumo de IA, y
  leer las **opiniones sobre la IA**.
- **Opiniones sobre la IA:** "¿Es correcta esta respuesta?" (correcta, a medias o incorrecta, con comentario) en
  el Tutor y el Analista.
- **Cambiar contraseña** desde la web.
- Migración `0027`: `data_owner`, `data_credit`, `grant_company_access`, `revoke_company_access`,
  `company_access`, `set_company_demo`, `ai_allowed`, `ai_status`, `ai_consume`, `ai_usage`, `ai_feedback` y
  `app_profiles.ai_daily_limit`.
- Prueba `test_fase21_members.sql`.
### Cambiado
- La IA ya no es exclusiva del propietario: también la usa el titular de los datos en su empresa, con cuota diaria.
- Una empresa demo la puede publicar su titular de los datos, no solo el propietario.

## [0.23.0] - 2026-10-09
### Añadido
- **Tutor de asientos con IA** (Contabilidad › Asiento):
  - describes una operación y la IA propone el asiento según el PGC, con la NRV aplicable, los supuestos, el porqué
    de cada línea y una pregunta de repaso;
  - el ERP la comprueba (subcuentas, impuesto vigente calculado por el ERP, cuadre y reglas de criterio) y la carga
    en el formulario sin contabilizar.
- Migración `0025`: `valuation_rules` (las 23 NRV), `entry_tutor_context`, `validate_proposed_entry` y
  `next_subaccount_no`.
- Migración `0026`: reglas de criterio contable y cuentas 2800–2806 y 2811–2819 del PGC.
- Pages Function `functions/api/tutor.js`: modelo `gpt-oss-120b` con Mistral Small de respaldo y segunda vuelta
  con los avisos del ERP.
- Prueba `test_fase20_entry_tutor.sql`.
### Cambiado
- El PGC de la plantilla pasa de 362 a 378 cuentas.
- `/api/ai` y `/api/tutor` avisan de forma clara cuando falta ejecutar una migración en Supabase.

## [0.22.0] - 2026-10-08
### Añadido
- **Analista IA** con un modelo open source de Cloudflare Workers AI (gratuito y sin clave de API):
  - comenta como un auditor los estados financieros, el EFE y los ratios del ejercicio, con resumen, puntos
    fuertes, alertas, preguntas del auditor y una idea para aprender;
  - botón en Informes › Ratios y en Flujos de efectivo;
  - solo para el propietario de la aplicación.
- Migración `0024`: `can_use_ai()` y `ai_context()`. La IA solo recibe cifras agregadas: nunca nombres,
  terceros ni conceptos.
- Pages Function `functions/api/ai.js` (POST para el análisis, GET para comprobar la configuración).
- Prueba `test_fase19_ai_context.sql`.
### Corregido
- La **calidad del resultado** (con pérdidas) y el **ROE** (con patrimonio neto negativo) ya no muestran un
  valor positivo engañoso: quedan sin calcular.

## [0.21.0] - 2026-10-08
### Añadido
- **Ratios financieros** (migración `0023`): 21 ratios de liquidez, solvencia y endeudamiento, rentabilidad,
  actividad (periodos medios de cobro, pago y existencias) y flujos de caja. Cada uno trae su fórmula, su
  explicación, su zona de referencia, el año anterior y su numerador y denominador.
- Pantalla **Informes › Ratios** (es / en):
  - semáforo frente a la zona de referencia y evolución ↑↓;
  - detalle con la fórmula y los importes reales de la empresa.
- Prueba `test_fase18_ratios.sql`.

## [0.20.0] - 2026-10-08
### Añadido
- **Estado de flujos de efectivo** por el método indirecto (modelo normal del PGC) y el directo (NIC 7),
  con columna del ejercicio anterior y detalle por cuentas en cada línea (migración `0022`).
- **Cuadre del auditor**:
  - efectivo inicial + flujos = efectivo final;
  - directo = indirecto = variación del subgrupo 57;
  - comparación por actividades con la lista de asientos sin dinero que explican la diferencia.
- Pantalla **Informes › Flujos de efectivo** (es / en).
- Prueba `test_fase17_cash_flow.sql`.

## [0.19.0] · 2026-10-08
### Añadido
- Importar diario de otro ERP (Sage, Dynamics 365 Business Central o plantilla del laboratorio) en una empresa nueva,
  con todos sus ejercicios, vista previa con controles de auditor e importación por lotes.
- 10 cuentas del PGC en la plantilla del plan de cuentas.
### Cambiado
- Sumas y saldos y saldos anómalos no incluyen el asiento de cierre.

## [0.18.0] · 2026-10-07
### Añadido
- Prorrata general del IVA / IGIC: porcentaje provisional por año, reparto de la cuota entre deducible y no deducible
  en las facturas recibidas, y regularización con la prorrata definitiva en el 4T.
- Impuestos › Prorrata: cálculo de la definitiva, asiento de regularización e historial.
### Cambiado
- El libro registro guarda lo deducido de cada tipo; la liquidación usa esa cifra e incluye la regularización de la prorrata.


## [0.17.0] · 2026-10-07
### Añadido
- Inversión del sujeto pasivo (IVA e IGIC) y adquisiciones intracomunitarias de bienes, con autorrepercusión 472/477.
- Recargo de equivalencia: clientes en recargo (venta con IVA + recargo) y régimen de la empresa minorista
  (compras no deducibles, ventas con IVA incluido).
- Régimen de IVA de la empresa en Impuestos y marca "cliente en recargo de equivalencia" en Terceros.
### Cambiado
- La liquidación 303/420 incluye el recargo repercutido y el ISP en devengado y deducible, y excluye lo no deducible.

## [0.16.0] · 2026-10-07
### Añadido
- Retención IRPF en facturas recibidas y emitidas (profesionales 15 % / 7 %, alquileres 19 %), con líquido a pagar o cobrar.
- Impuestos › Retenciones IRPF: borrador trimestral de los modelos 111 y 115 y retenciones soportadas.
- Operaciones sin cuota con su causa: exenta (E1), exportación (E2), entrega intracomunitaria (E5) y no sujeta (N2).
### Cambiado
- El motor de facturas valida cada causa de exención según el tipo de factura y el territorio del tercero.
- El borrador del 303/420 muestra las bases sin cuota con su causa en lugar de "0 %".

## [0.15.0] · 2026-10-06
### Añadido
- Cierre del ejercicio: comprobaciones, regularización, cierre, apertura del año siguiente y reapertura.
- Etiqueta "Cierre" en el libro diario para los asientos del cierre.
### Cambiado
- Balance y PyG no incluyen los asientos de regularización y cierre.

## [0.14.0] · 2026-10-06
### Añadido
- Balance de situación y Cuenta de Pérdidas y Ganancias (modelo PYMES del PGC) con ejercicio anterior,
  fecha de corte y detalle de cuentas por partida.
### Cambiado
- Los importes muestran siempre separador de miles.

## [0.13.1] · 2026-10-06
### Añadido
- Guía de Git del proyecto (`docs/guia-git.md`).
### Cambiado
- Selector de idioma con banderas.
- Cabeceras de área del menú diferenciadas de las opciones.
- README actualizado.
### Eliminado
- Carpeta `Codigo GIT` (sustituida por la guía en `docs`).

## [0.13.0] · 2026-10-06
### Añadido
- Acceso como invitado (sin registro) a las empresas demo, solo lectura.
- Enlace directo para compartir la demo.
### Corregido
- La lista de empresas no muestra separadores vacíos cuando falta el NIF.

## [0.12.0] · 2026-10-05
### Añadido
- Anulación de asientos con contraasiento, fecha y motivo.
- Libro diario con rango de fechas, búsqueda y totales del filtro.
- Etiquetas de origen del asiento (factura, liquidación) y de anulación.

## [0.11.0] · 2026-10-05
### Cambiado
- Menú de la empresa agrupado por áreas (barra lateral en ordenador, menú desplegable en móvil).
- La aplicación recuerda la última pantalla abierta de cada empresa.

## [0.10.0] · 2026-10-05
### Añadido
- Informes: sumas y saldos por nivel y fecha de corte, libro mayor con saldo acumulado y drill-down.
- Informe de saldos anómalos con explicación y cuenta de reclasificación.
- Bloqueo de saldo inverso por subcuenta (caja bloqueada por defecto).

## [0.9.0] · 2026-10-05
### Añadido
- Liquidación trimestral de IVA (modelo 303) e IGIC (modelo 420) con borrador por tipo.
- Compensación automática de cuotas de periodos anteriores y devolución en el 4T.
- Cuadre libro registro ↔ contabilidad antes de liquidar.
- Bloqueo del trimestre liquidado y deshacer la última liquidación.

## [0.8.0] · 2026-10-05
### Añadido
- Registro de facturas recibidas y emitidas, normales y rectificativas, con asiento automático.
- Regla del lado: devoluciones, rappels y descuentos por pronto pago reducen base y cuota.
- Vista previa del asiento antes de registrar.
- Libro registro de facturas emitidas y recibidas.
- Control de facturas duplicadas y numeración correlativa por serie.

## [Sin publicar]
### Cambiado
- Base de datos renombrada al inglés al estilo Business Central / SAP: schema `erp`, tablas, columnas,
  funciones, vistas, estados y mensajes de error (ADR 0003).
### Añadido
- Nombres en inglés (`name_en`) para las 352 cuentas del PGC y descripciones de los tipos IVA / IGIC.
- Tabla `user_settings` para el idioma de la interfaz (es / en) por usuario.
- `docs/glosario.md` y script `database/reset/0000_drop_conta.sql`.

## [0.7.0] · 2026-10-04
### Añadido
- Configuración de impuestos: subcuentas 472/477 por tipo de IVA/IGIC y 4750/4700 de liquidación.
- Asistente para configurar IGIC o IVA en un clic.
- El apunte en una cuenta de impuesto toma su tipo y aparece en el libro registro.
### Corregido
- Comprobación de permisos para usuarios que no son miembros de la empresa.

|
## [0.6.0] · 2026-10-03
### Añadido
- Terceros: clientes, proveedores, acreedores y deudores con su subcuenta (430/400/410/440).
- Validación de NIF/NIE/CIF españoles y control de duplicados.
- Saldo de cada tercero con su naturaleza (deudor/acreedor).


## [0.1.0] - 2026-09-29
### Añadido
- Schema `conta` en PostgreSQL/Supabase con 6 migraciones.
- Empresas multisector (retail, industria, e-commerce, servicios) y multiterritorio (Península / Canarias).
- Plan General Contable 2007, grupos 1 a 7 (352 cuentas), copiado automáticamente a cada empresa.
- Subcuentas con longitud fija y enlace automático a su cuenta PGC.
- Terceros y catálogo de tipos IVA / IGIC 2026 con fechas de vigencia.
- Asientos: borrador → contabilizado, validación Debe = Haber, numeración correlativa, periodos cerrables,
  anulación por contraasiento.
- Informes: libro diario, libro mayor, sumas y saldos por niveles, libro registro de IVA/IGIC.
- Multiusuario con roles (admin, contable, lectura) mediante Row Level Security.
- 31 pruebas automáticas y datos de ejemplo (2 empresas).
