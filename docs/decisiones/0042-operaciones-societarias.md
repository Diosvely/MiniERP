# ADR 0042 · Operaciones societarias: capital, reparto del resultado, dividendos y pérdidas

- **Fecha:** 2026-10-21
- **Versión:** v0.42.0
- **Estado:** aceptada

## Contexto

Con el Impuesto sobre Sociedades (v0.41.0) el ERP ya llega al **resultado después de impuestos**. Faltaba lo que
viene después: la junta reparte ese resultado. También faltaba lo que hay antes de todo: la sociedad se constituye y
amplía su capital.

Sin esto, la 129 se quedaba con saldo año tras año, no había reserva legal ni dividendos, y el patrimonio neto del
balance no se podía explicar. Son operaciones que BC y SAP registran con asientos manuales en el diario general.

La norma es la **Ley de Sociedades de Capital** (RDLeg 1/2010, con la Ley 18/2022 «Crea y Crece»), con el PGC 2007
para los asientos.

## Decisión

1. **Forma jurídica en la ficha de la empresa** (SA / SL).
   - Decide el capital mínimo, si puede quedar capital sin desembolsar y la regla de la reserva legal.
   - Solo la cambia el admin, y solo antes de la primera operación.
2. **Una pantalla, «Operaciones societarias»**, con nueve operaciones. Cada una tiene su función en la base de datos,
   que comprueba la LSC **antes** de contabilizar:
   - **constitución y ampliación:** emisión (190 / 194), suscripción (572 + 1030 / 190) e inscripción (194 / 100).
     La SA necesita al menos 60.000 € y el 25 % desembolsado; la SL, al menos 1 € y todo desembolsado (arts. 4, 78 y
     79). En la ampliación, la prima (110) se desembolsa entera;
   - **ampliación con cargo a reservas o a la prima** (art. 303), y **dividendos pasivos** (1030 → 5580 → 572);
   - **reparto del resultado** (arts. 273 y 274):
     - primero las pérdidas pendientes (121);
     - después la reserva legal: el 10 % del beneficio hasta el 20 % del capital. En una SL de menos de 3.000 € es al
       menos el 20 %, hasta que capital y reserva sumen 3.000 (art. 4.2);
     - después el dividendo (526), con lo pagado a cuenta (557) incluido;
     - y el resto, a reservas voluntarias (113).
     - Si queda una pérdida, va a la 121.
     - No hay dividendo si el patrimonio neto quedaría por debajo del capital o si quedan pérdidas sin compensar;
   - **dividendo a cuenta** (art. 277): el límite es el resultado desde el cierre menos las pérdidas anteriores, el
     impuesto estimado (25 % por defecto) y la reserva legal, y además tiene que haber tesorería;
   - **pago del dividendo:** retención del 19 % a una subcuenta propia, la **47512** (modelo 123), para que no se
     mezcle con la 4751 del 111. Sin retención solo con su motivo;
   - **pérdidas:** compensarlas con reservas voluntarias, o reducir el capital (arts. 320 y 322). La reducción no se
     permite mientras haya reservas voluntarias.
3. **La propuesta de reparto la calcula la base de datos** (`equity_distribution_preview`). La pantalla la enseña con
   su asiento y desactiva «Contabilizar» si incumple la ley. La misma función comprueba al contabilizar.
4. **Módulo propio:**
   - los asientos no se anulan desde el diario y salen como «Operación societaria»;
   - se deshacen desde la pantalla, de la última a la primera;
   - el orden lo da el número de la operación (SOC-0001…), no la hora: dos operaciones de una misma transacción
     tienen la misma hora.
5. **Integración** (0061):
   - **Facturas recibidas a la 113:** los gastos de constitución y de ampliación van contra reservas (NRV 9.ª, apdo.
     4). El Impuesto sobre Sociedades los propone como ajuste deducible (LIS art. 11.3), y el ahorro de impuesto va
     también a la 113;
   - **cierre:** aviso si el resultado del año anterior sigue sin repartir;
   - **auditor:** la 47512 queda fuera de la comprobación del 111;
   - **cuentas controladas:** 190, 194, 1030, 5580, 526 y 557;
   - **glosario:** cuatro términos nuevos;
   - **fuentes:** la LSC;
   - **Practicar:** dos supuestos nuevos.
   - El subgrupo 19 del PGC entra en la plantilla.

## Alternativas descartadas
- **Controlar también la 100, la 112 y la 113.** El asiento de apertura de una empresa que ya existía (o importada)
  necesita moverlas a mano, y en modo estricto no se podría.
- **Un módulo de gastos de constitución aparte**, con su propio IVA. Duplicaría el libro registro. Es más sencillo
  dejar que la factura recibida acepte la 113.
- **Mezclar la retención de dividendos en la 47510.** La comprobación del 111 daría una diferencia falsa de 5.700 €,
  como se vio en la prueba antes del arreglo.
- **Calcular el reparto en la web.** La regla tiene que estar en un solo sitio, la base de datos. La web solo dibuja
  el asiento, con la misma regla y con tests que la comparan con los supuestos.
- **Elegir la forma jurídica automáticamente por el capital.** Una SL puede tener más de 60.000 € de capital: la forma
  la dice la escritura, no la cifra.

## Consecuencias
- El balance ya explica el patrimonio neto completo: capital, prima, reservas, pérdidas, resultado y dividendo a
  cuenta. Además, la 129 se reparte.
- **Limitaciones conocidas:**
  - no hay acciones propias (108 / 109), ni reducción con devolución a los socios, ni aportaciones de socios (118);
  - el modelo 123 no se genera: solo queda la 47512 para cuadrarlo;
  - la reserva legal se calcula sobre el beneficio del ejercicio aunque haya pérdidas pendientes (**pendiente de
    validar por Diosvely** con la doctrina del ICAC);
  - el patrimonio neto del art. 273 es el del balance aprobado, sin ajustes por cambios de valor.
- **Pruebas:** 56 de 56 en la base de datos y 200 tests en la web. Los seis supuestos de referencia (S1 a S6) se
  calcularon a mano antes de programar y coincidieron. **Fallos que salieron al probar:**
  - deshacer elegía mal entre dos operaciones registradas a la misma hora;
  - el patrimonio neto a mitad de año no contaba el resultado del ejercicio en curso;
  - la función de saldos era *security definer* sin comprobar la empresa (corregido en la 0061);
  - en el móvil, el historial desbordaba la pantalla.

## Cómo explicarlo
- **El resultado no es de la empresa hasta que la junta decide.** Al cerrar, el beneficio queda en la 129, que es un
  saldo pendiente de destino. La junta lo reparte: primero lo que obliga la ley (compensar pérdidas, la reserva
  legal), después lo que decide (dividendos) y el resto se queda en la empresa como reservas voluntarias.
- **La reserva legal es un colchón para los acreedores:** la sociedad responde solo con su patrimonio, así que la ley
  obliga a guardar una parte del beneficio, el 10 % hasta el 20 % del capital. Por eso el art. 273 impide repartir si
  el patrimonio neto queda por debajo del capital.
- **Dividendo a cuenta: adelantar con prudencia.** Se reparte antes de saber el beneficio final, por eso se le restan
  el impuesto y la reserva legal y se exige tesorería. La 557 resta del patrimonio neto hasta que la junta la aplica.
- **Los gastos de constitución no son un gasto del año:** son el coste de conseguir fondos propios, así que van contra
  reservas (113). Fiscalmente sí se deducen, y el impuesto que ahorran también va a reservas.
- **BC y SAP** registran todo esto con asientos manuales en el diario general. El valor de esta pantalla es que la ley
  se comprueba antes, como haría el asesor que prepara la junta.
