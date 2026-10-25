# ADR 0043 · Financiación: préstamos a coste amortizado y arrendamiento financiero

- **Fecha:** 2026-10-24
- **Versión:** v0.43.0
- **Estado:** aceptada

## Contexto

Las deudas con bancos y los leasings están en casi todas las empresas, y son de lo que más se pregunta en un examen
de contabilidad. Hasta ahora el ERP solo permitía registrarlos con asientos manuales, lo que planteaba cuatro
problemas:
- las comisiones de apertura iban a gasto el primer día, cuando la NRV 9.ª las reparte con el tipo de interés
  efectivo;
- nadie separaba la deuda a corto de la de largo al cierre;
- los intereses que corren desde la última cuota no se devengaban;
- el leasing se confundía con un alquiler.

La norma es el PGC 2007:
- **NRV 9.ª, apdo. 3.1:** pasivos financieros a coste amortizado, con el tipo de interés efectivo;
- **NRV 8.ª, apdo. 1.1:** arrendamiento financiero del arrendatario.

El IVA / IGIC de cada cuota del leasing lo pide la ley del impuesto: hasta que se ejerce la opción de compra, el
arrendamiento financiero es una prestación de servicios.

## Decisión

1. **Supuestos calculados a mano y validados antes de programar** (paso 225). Son cuatro, del F1 al F3, con el F1b
   de los intereses devengados.
   - El motor tiene que dar sus cifras **al céntimo**.
   - Al programarlo salió un error del propio documento: el F2 suponía cinco cuotas iguales, pero el banco cobra la
     última un céntimo menor. Se corrigió el documento.
2. **Un motor de financiación en la base de datos** (0062), con un cuadro de amortización por préstamo:
   - **sistema francés.** Cuota constante, mensual, trimestral, semestral o anual. La cuota sale del tipo nominal y la
     última cuota ajusta el redondeo;
   - **tipo de interés efectivo** por bisección, con 30 decimales, como la TIR de una hoja de cálculo.
     - Sin comisiones es el nominal.
     - Con comisiones, el que iguala lo recibido con las cuotas.
     - Los intereses de cada cuota son el TIE por lo pendiente. La comisión **nunca** va a gasto el primer día;
   - **leasing.** El activo y la deuda se registran por el **menor** del valor razonable y el valor actual de los
     pagos (cuotas y opción de compra) al tipo del contrato, si se da. El tipo implícito los iguala;
   - **corto y largo plazo.** A corto va lo que baja la deuda en las cuotas sin pagar que vencen en los 12 meses
     siguientes. El reparto se hace en el alta y se repite en cada cierre (1700 → 5200, 1740 → 5240);
   - **intereses devengados al cierre.** Se calculan como lo pendiente × ((1 + TIE)^f − 1), con f la parte del
     periodo que ha pasado en base 30/360. Van a la 527 (bancos) o a la 528 (otros), y la cuota siguiente los salda;
   - **cuentas por defecto según el prestamista.** Un banco usa 170 / 520 / 6623 / 527; otro prestamista, 171 / 521 /
     6624 / 528; el leasing, 174 / 524. Las cuentas se pueden compartir entre préstamos: lo que es de cada uno lo
     llevan sus movimientos.
3. **La cuota del leasing es una factura recibida** de la entidad, con su IVA / IGIC sobre la cuota entera (0063).
   - Las líneas salen del cuadro: 5240 (o 1740), 527 y 6623.
   - La 524 / 174 / 527 / 528 solo se aceptan en una factura que venga de Financiación. Una rectificativa manual no
     puede corregir una cuota.
   - Deshacer la cuota emite la rectificativa completa.
   - Así el IVA / IGIC entra en el libro registro y en el 303 / 420, y la entidad queda como acreedor en Cobros y
     pagos.
4. **El leasing crea la ficha del activo** en Inmovilizado, con su vida útil, y ese módulo lo amortiza como siempre.
   El alta no se deshace mientras haya amortizaciones.
5. **Módulo propio:**
   - los asientos no se anulan desde el diario y salen como «Préstamo o leasing»;
   - se deshacen desde la pantalla, del último movimiento al primero. El orden lo da un número de secuencia, no la
     hora.
6. **Integración** (0063):
   - el asistente de cierre tiene un paso nuevo, el 9, «Préstamos y leasing»;
   - el auditor tiene la comprobación `financing_ledger`, que compara las cuentas con el módulo;
   - ocho cuentas controladas nuevas;
   - cuatro términos en el glosario y dos supuestos en Practicar.
7. **Pantalla «Financiación»** (paso 228):
   - la lista de préstamos y su ficha, con el cuadro;
   - la cuota siguiente o su factura, con el asiento antes de contabilizar;
   - el alta, con el cálculo en vivo de la base de datos;
   - el cierre y la opción de deshacer.

## Alternativas descartadas
- **Repartir la comisión de forma lineal** o llevarla a gasto el primer día. La NRV 9.ª pide el tipo efectivo; lo
  lineal solo sería aceptable si la diferencia no es significativa, y el laboratorio enseña la regla.
- **Devengar los intereses de forma lineal** (6.000 × 6/12 = 3.000). Muchos manuales lo hacen, pero no es coherente
  con el coste amortizado. Con el TIE salen 2.956,30. Diosvely lo validó así.
- **Pagar la cuota del leasing con un asiento directo.** El IVA / IGIC quedaría fuera del libro registro y de los
  modelos, igual que si se registrara a mano.
- **Una subcuenta por préstamo** (17000001, 17000002…). Llena el plan de cuentas, y el balance del PGC las agrega
  igual. El reparto lo llevan los movimientos de cada préstamo.
- **Calcular el cuadro en la web.** Igual que en las demás pantallas, la regla está en un solo sitio, la base de datos.
  La web pide el cálculo a `loan_calc` y solo dibuja el asiento, con tests que lo comparan con los supuestos.

## Consecuencias
- El balance separa bien la deuda a corto y a largo, y los intereses de cada año son los que corresponden. El leasing
  aparece como un activo amortizable y una deuda, no como un gasto de alquiler.
- **Limitaciones conocidas:**
  - **solo sistema francés:** no hay cuota de principal constante, carencia ni tipo variable (euríbor);
  - **la primera cuota se calcula como un periodo entero**, aunque el primer vencimiento caiga antes;
  - **no se modelan las amortizaciones anticipadas ni la cancelación del préstamo;**
  - **los intereses no se ajustan en el Impuesto sobre Sociedades.** No se aplica el límite del 30 % del beneficio
    operativo del art. 16 LIS: está por debajo del millón de euros, salvo empresas grandes;
  - **el arrendador** (quien da el leasing) **no está.**
- **Pruebas:** 58 de 58 en la base de datos (fases 57 y 58) y 214 tests en la web. **Lo que salió al probar:**
  - el céntimo del F2, en el documento de supuestos;
  - en la factura de Canarias, el IGIC soportado va a la 4721, no a la 4720;
  - ocho claves foráneas sin índice, que detectó la prueba de rendimiento;
  - un módulo nuevo sin nombre en los textos de la web, que detectó su test;
  - en la pantalla, la lista era demasiado ancha a 1366 px.

## Cómo explicarlo
- **Coste amortizado: la deuda es lo que recibiste, no lo que firmaste.** Si el banco presta 100.000 y cobra 1.000 de
  comisión, debes 99.000. Pagarás las mismas cuotas que sin comisión, así que el coste real es mayor que el 6 %: es el
  **tipo de interés efectivo** (6,3705 %). Con él se calculan los intereses de cada año, y la comisión se va
  «comiendo» poco a poco en vez de ir a gasto el primer día.
- **El TIE es la TIR de la deuda:** el tipo que iguala lo que entra hoy con lo que sale después. Es la misma idea que
  la TAE del recibo del banco: al anualizar una cuota mensual, un 4,5 % nominal es un 4,59 % efectivo.
- **Corto y largo plazo cuentan para la liquidez.** Un analista mira el pasivo corriente para saber qué hay que pagar
  este año. Por eso, al cierre, lo que vence en los 12 meses siguientes pasa del 170 al 520. El total de la deuda no
  cambia; solo su clasificación.
- **Intereses devengados: el tiempo corre aunque no pagues.** Si la cuota vence el 30/06, a 31/12 ya debes medio año de
  intereses. Van a la 527 y la cuota los salda. Así el gasto de cada año es el suyo (principio de devengo).
- **Leasing: es una compra a plazos disfrazada de alquiler.** Si es seguro que vas a quedarte el bien, lo registras
  como tuyo (213) y como deuda (174 / 524). Cada cuota baja la deuda y paga intereses. El bien se amortiza por su vida
  útil, no por la duración del contrato. El IVA / IGIC va en cada cuota, porque legalmente es un servicio hasta que
  compras.
- **En BC no hay módulo estándar de préstamos** (se usan asientos periódicos o extensiones). En SAP están Treasury and
  Risk Management y Lease Administration. Aquí el valor es ver el cuadro y el asiento antes, con la norma.
