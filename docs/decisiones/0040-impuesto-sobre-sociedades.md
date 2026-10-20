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
- **Un solo asiento** que mezcle corriente y diferido. Se ven peor las dos piezas del gasto que pide la NRV 13.ª, y
  BC y SAP también las separan.
- **Controlar también la 4752 y la 473.** Obligaría a pagar a Hacienda desde esta pantalla. En la práctica se paga con
  un asiento de banco, como en los ERP del mercado español.
- **La RIC y la ZEC** (fiscalidad canaria). Se dejan para un bloque propio, porque tienen sus propias reglas y sus
  propios ajustes.

## Consecuencias
- El cierre ya da el **resultado después de impuestos**, y el modo estricto no deja cerrar sin el impuesto.
- **Limitaciones conocidas:**
  - Las diferencias temporarias y el crédito se valoran al **tipo marginal del propio ejercicio**. La NRV 13.ª pide
    el tipo esperado cuando reviertan. Es lo mismo mientras el tipo no cambie, pero en reducida dimensión y en
    microempresa el tipo baja cada año hasta 2029, y ahí la cifra es aproximada.
  - No hay deducciones en cuota (I+D, empleo…), ni pagos fraccionados calculados (modelo 202), ni la reserva de
    capitalización (art. 25), ni la RIC o la ZEC.
  - Las diferencias permanentes que el ERP no conoce se añaden a mano.
- **Pruebas:** 54 de 54 en la base de datos y 159 tests en la web. Los supuestos de referencia se calcularon a mano
  desde la LIS y el PGC antes de ejecutar el ERP, y salieron iguales a la primera:
  - fase 52: microempresa y régimen general;
  - fase 53: los asientos, las bases negativas (con y sin crédito, y el límite del 70 %), una devolución y las
    reversiones;
  - fase 54: el cierre, el invariante, la 129 y los supuestos de Practicar.
- **Pendiente de validar por Diosvely:**
  - los tipos de 2026 y los de reducida dimensión de 2025 a 2029, en el BOE;
  - qué provisiones vienen marcadas por defecto.

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
- **Business Central y SAP** no calculan el impuesto de sociedades: el asiento lo prepara el asesor fiscal y se
  registra a mano (BC, diario general; SAP, con la herramienta de impuestos diferidos o un asiento manual). Aquí se
  calcula para aprender de dónde sale cada cifra.
