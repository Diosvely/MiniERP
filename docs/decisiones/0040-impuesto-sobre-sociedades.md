# ADR 0040 · Impuesto sobre Sociedades en el cierre

- **Fecha:** 2026-10-20
- **Versión:** v0.41.0
- **Estado:** aceptada

## Contexto

Hasta la v0.40.1 el cierre llevaba a la 129 el resultado **antes de impuestos**. La pantalla no calculaba el impuesto,
no pedía contabilizarlo y no avisaba de que faltaba. El resultado del ejercicio salía mal en cualquier sociedad con
beneficio. En una herramienta para aprender contabilidad española, falta el último asiento del año.

El impuesto se calcula con dos normas:
- la **Ley 27/2014 (LIS)**, que pasa del resultado contable a la base imponible y de ahí a la cuota;
- el **PGC, NRV 13.ª**, que dice cómo se contabiliza: gasto = impuesto corriente + impuesto diferido.

## Decisión

1. **Una pantalla propia, «Impuesto sobre Sociedades»**, en Contabilidad, antes de «Cierre del ejercicio». Sigue el
   orden del modelo 200:
   - resultado contable;
   - ± diferencias permanentes y temporarias;
   - − bases negativas de años anteriores;
   - = base imponible;
   - × tipo = cuota íntegra;
   - − retenciones y pagos fraccionados (473);
   - = cuota diferencial.
   Las funciones son `erp.corporate_tax_calc`, `_prepare`, `_post` y `_cancel` (0057 y 0058).
2. **El régimen lo elige la persona; el ERP sugiere uno.** La sugerencia sale de la cifra de negocios del año anterior
   (70x, `erp.corporate_tax_regime_hint`): reducida dimensión, menos de 10 millones (art. 101 LIS); microempresa,
   menos de 1 millón. Si el elegido no encaja, avisa. Los tipos van en una tabla por año (`erp.corporate_tax_rates`),
   con tramos:
   - **2026:** general 25 %, reducida dimensión 23 %, microempresa 19 % hasta 50.000 y 21 % después, nueva creación
     15 %;
   - también están cargados los de reducida dimensión hasta 2029.
3. **Ajustes propuestos con su artículo**, cada uno con una casilla para incluirlo o no:
   - amortización por encima del máximo de la tabla (art. 12.1.a): temporaria;
   - deterioro de clientes antes de los 6 meses (art. 13.1.a): temporaria, y revierte;
   - deterioro global en reducida dimensión (art. 104): temporaria;
   - provisiones (art. 14). Las comerciales vienen marcadas y las de responsabilidades e impuestos, desmarcadas,
     porque depende del caso;
   - los que el ERP no puede saber (una multa, art. 15.c; un donativo) se añaden a mano como permanentes.
4. **Bases negativas** (art. 26):
   - se compensan las más antiguas primero;
   - el límite es el 70 % de la base previa, con un mínimo de 1 millón que nunca pasa de la base.
5. **Crédito fiscal (4745): una casilla desmarcada por defecto.** NRV 13.ª: el crédito solo se registra si es probable
   que haya beneficios para compensarlo. Es un juicio, y por prudencia la casilla empieza desmarcada. La norma está
   escrita al lado de la casilla.
6. **Dos asientos, del propio módulo**, con fecha del 31/12:
   - corriente: 6300 al Debe; 473 al Haber por su saldo; la diferencia, a la 4752 (a pagar) o a la 4709 (a devolver);
   - diferido: 4740 por el neto de las diferencias temporarias, 4745 por el crédito o por lo que se usa, contra la 6301.
   No se anulan desde el diario: se deshacen desde su pantalla con contraasientos, y solo si no hay un año posterior
   contabilizado ni el año está cerrado.
7. **Integrado en el cierre** (0059):
   - el asistente tiene el paso 10, «Impuesto sobre Sociedades»;
   - la vista previa del cierre avisa si falta (modo guiado) o no deja cerrar (modo estricto);
   - avisa también si la 473 no queda a cero;
   - el **invariante 10** comprueba que la 630 sea igual al gasto de la declaración, así que la 129 = resultado antes
     de impuestos − (6300 + 6301);
   - la 630 y la 474 pasan a ser **cuentas controladas**. La 4752, la 4709 y la 473 no, porque el pago o el cobro de
     Hacienda y los pagos fraccionados son asientos normales.
8. **Glosario, fuentes y Practicar:**
   - cuatro términos nuevos: base imponible, diferencia temporaria, impuesto corriente e impuesto diferido;
   - la LIS aparece con todos los artículos que se usan;
   - dos supuestos avanzados nuevos, el impuesto corriente y el diferido.

## Alternativas descartadas
- **Elegir el régimen automáticamente por la cifra de negocios.** La reducida dimensión tiene más condiciones
  (grupo, entidad patrimonial) que el ERP no conoce. Se sugiere y se avisa, pero decide la persona.
- **Registrar siempre el crédito por bases negativas.** Contradice la NRV 13.ª. La probabilidad de recuperarlo es un
  juicio que tiene que hacer quien firma las cuentas.
- **Un solo asiento** que mezcle corriente y diferido. Se ven peor las dos piezas del gasto que pide la NRV 13.ª.
- **Controlar también la 4752 y la 473.** Obligaría a pagar a Hacienda desde esta pantalla. En la práctica, el pago a Hacienda y
  los pagos fraccionados se registran con un asiento de banco.
- **La RIC y la ZEC** (fiscalidad canaria). Se dejan para un bloque propio, porque tienen sus propias reglas y sus
  propios ajustes.

## Consecuencias
- El cierre ya da el **resultado después de impuestos**, y el modo estricto no deja cerrar sin el impuesto.
- **Limitaciones conocidas:**
  - Las diferencias temporarias y el crédito se valoran al **tipo marginal del propio ejercicio**. La NRV 13.ª pide
    el tipo esperado cuando reviertan. Es lo mismo mientras el tipo no cambie, pero el tipo baja cada año: en
    reducida dimensión hasta 2029 y en microempresa hasta 2027. Ahí la cifra es aproximada.
  - No hay deducciones en cuota (I+D, empleo…), ni pagos fraccionados calculados (modelo 202), ni la reserva de
    capitalización (art. 25), ni la RIC o la ZEC.
  - Las diferencias permanentes que el ERP no conoce se añaden a mano.
- **Pruebas:** 54 de 54 en la base de datos y 159 tests en la web. Los supuestos de referencia se calcularon a mano
  desde la LIS y el PGC antes de ejecutar el ERP, y salieron iguales a la primera:
  - fase 52: microempresa y régimen general;
  - fase 53: los asientos, las bases negativas (con y sin crédito, y el límite del 70 %), una devolución y las
    reversiones;
  - fase 54: el cierre, el invariante, la 129 y los supuestos de Practicar.
- **Pendiente de validar por Diosvely:** qué provisiones vienen marcadas por defecto.
- **Tipos validados** (auditoría fiscal, 08-11-2026): los de 2026 y los de reducida dimensión de 2025 a 2029 coinciden
  con el art. 29.1 y la DT 44.ª de la LIS, en la redacción de la Ley 7/2024, DF 8.ª (BOE núm. 307, de 21-12-2024).
  Los de la microempresa de 2025 y desde 2027 se corrigen en la v0.60.2.

## Cómo explicarlo
- **El impuesto también es un gasto del año.** Si el cierre lleva a la 129 el resultado antes de impuestos, el
  beneficio que ven los socios está inflado. Por eso el impuesto va antes de la regularización.
- **La contabilidad y Hacienda miden distinto.** El resultado contable sigue el PGC; la base imponible sigue la LIS.
  Los ajustes son la traducción entre las dos:
  - **permanente**, si Hacienda no lo acepta nunca (una multa);
  - **temporaria**, si lo acepta otro año (la amortización por encima de la tabla).
- **Impuesto corriente e impuesto diferido.** El corriente (6300) es lo que se paga por este año. El diferido (6301)
  corrige el momento: una diferencia temporaria hace pagar hoy de más (4740) o de menos (479), y se compensa cuando
  revierte. Así el gasto del año queda proporcionado al resultado contable.
- **El crédito por pérdidas es un juicio.** Una pérdida da derecho a pagar menos en el futuro. Solo es un activo
  (4745) si es probable que haya beneficios con los que usarlo. Por eso la casilla empieza desmarcada.
- Aquí se calcula para aprender de dónde sale cada cifra.

## Actualización (v0.60.2, 2026-11-09)

Dos hallazgos del chat de auditoría fiscal (AF-02 y AF-03), aprobados por Diosvely y corregidos en la migración 0091:

1. **Tipos de la microempresa que faltaban.** Solo estaban los de 2026, así que en 2025 el cálculo daba error y desde
   2027 aplicaba los de 2026. Ahora: **2025, 21 % / 22 %** (DT 44.ª LIS) y **desde 2027, 17 % / 20 %** (art. 29.1 LIS),
   en la redacción de la Ley 7/2024, DF 8.ª (BOE núm. 307, de 21-12-2024). Con una base de 100.000 € en 2027, la cuota
   pasa de 20.000 € a 18.500 €.
2. **Período impositivo de menos de un año.** El art. 29.1 reparte el tramo de 50.000 € por días (50.000 × días / 365).
   El ejercicio del ERP va de enero a diciembre, así que la declaración guarda dónde empieza el período impositivo
   (`period_start`; vacío = el ejercicio entero) y la pantalla deja cambiarlo mientras es un borrador. La fecha de
   inicio de la contabilidad de la empresa solo se **sugiere** (puede no ser la de constitución). Ejemplo: del 01-07 al
   31-12 (184 días), base de 40.000 € en 2026 → 25.205,48 × 19 % + 14.794,52 × 21 % = 7.895,89 €.
   - **Revisado por auditoría fiscal (AF-24, v0.60.9):** el art. 27 LIS dice que el período coincide con el ejercicio
     económico y no pasa de 12 meses; no fija el inicio del primer período. Si a la fecha del devengo la sociedad no
     está inscrita en el Registro Mercantil, ese período no tributa por el IS y sus rentas se atribuyen a los socios
     (STS 1069/2024, de 17-06-2024). *Pendiente de validar por Diosvely: si el primer período empieza en la escritura o
     en la inscripción (criterio de la DGT).*
   - **Validado (AF-26, v0.60.9):** cuentan el primer y el último día; el divisor es 365 también en año bisiesto (art. 28
     y 29.1 LIS, BOE consolidado).
   - **Limitación (AF-25, opción a, v0.60.9):** el ERP calcula períodos que terminan en el cierre del ejercicio. Los que
     terminan antes (extinción, cambio de residencia, transformación, art. 27.2 LIS) no se calculan; la pantalla lo dice.
   - **La cifra de negocios de un año corto se eleva al año (AF-27, v0.60.9, migración 0098):** para sugerir el régimen,
     si el período del año anterior duró menos de un año, cifra × 365 / días (art. 101.2 LIS). Sin año anterior (la
     sociedad nueva usa su primer período) no se eleva: *pendiente de validar por Diosvely* si la segunda frase del
     art. 101.2 lo exigiría.

**Pruebas:** fase 52 con la regresión de los dos hallazgos (falla sin la 0091). 83 de 83 en la base de datos y 341 tests
de la web.

### Cómo explicarlo (actualización)
- **Un período corto, un tramo corto.** El tipo reducido es una ayuda pensada para un año de actividad. Si la sociedad
  solo ha existido medio año, recibe media ayuda: los primeros 25.205,48 € al tipo reducido en lugar de 50.000 €.
- **Ejercicio contable y período impositivo no son siempre lo mismo.** Casi siempre coinciden, pero el primer año de
  una sociedad empieza el día que nace la sociedad (y se comprueba en la escritura y los estatutos).

*Corrección (v0.60.9, 2026-11-18): el primer período impositivo, el cómputo de días, los períodos que terminan antes y
la cifra de negocios elevada al año (AF-24 a AF-27 de auditoría fiscal); el tipo de la microempresa (v0.60.8, H-69). La
decisión no cambia.*

*Revisión ética (v0.60.8, 2026-11-17): se quitan una comparación con programas comerciales y una frase sin fuente (H-64, H-65).*
