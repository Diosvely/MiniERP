# ADR 0054 · Tablero «Tesorería y circulante»: entradas y salidas de caja y periodos medios a cualquier fecha

- **Fecha:** 2026-11-01
- **Versión:** v0.54.0
- **Estado:** aceptada

## Contexto

Segundo de los cinco tableros nuevos (`plan-tableros.md`). Responde a lo que más mira quien lleva una empresa: cuánto
dinero hay, cuánto deben los clientes, cuánto se debe a los proveedores y si llega para el corto plazo. El diseño se
validó antes de construir (`diseno-v0.54.0.md`), con tres decisiones de Diosvely:
- se enseñan **todas** las entradas y salidas de tesorería, no solo las de explotación;
- los periodos medios usan los **días transcurridos** del ejercicio;
- los importes **vencidos** quedan para la v0.57.0 (Calidad de la contabilidad).

## Decisión

1. **Tipo de métrica «movimiento de tesorería»** (`kind = 'cash'`, migración 0081). Es lo que entra (`flow = 'in'`) o
   sale (`'out'`) de las cuentas 57 desde el inicio del ejercicio hasta la fecha.
   - Se calcula **asiento a asiento**, como el EFE (`erp.cf_entry_cash`), sin la apertura ni el cierre.
   - Un traspaso entre cuentas de tesorería (572 → 570) suma cero en su asiento, así que no es ni entrada ni salida.
   - `erp.cash_moves_at` lo calcula para todas las fechas en una pasada, solo con los asientos de la empresa y con la
     regla de qué cuenta en un informe, también en la simulación.
2. **Tipo de métrica «días»** (`kind = 'days'`, unidad `days`): a / b × días transcurridos del ejercicio hasta la
   fecha, con un máximo de 365.
   - Al cierre es exactamente el periodo medio de la pantalla Ratios (× 365).
   - A mitad de año no se infla: con «hasta el 30/06», los clientes se comparan con las ventas de 181 días, no con las
     de un año.
3. **El tablero**, con 11 métricas nuevas (clientes, proveedores, existencias, entradas, salidas y variación de la
   tesorería, prueba ácida, disponibilidad y periodos medios de cobro y de pago) y 5 tarjetas:
   - **cifras clave:** tesorería, clientes, proveedores y fondo de maniobra;
   - **entradas y salidas de cada mes**, en barras;
   - **tesorería** y **fondo de maniobra** a fin de mes, en líneas;
   - **liquidez y plazos**, en una tabla con la zona de Ratios.
4. **Web:** la unidad «días» («65 días») y los enlaces a Cobros y pagos y al estado de flujos.

## Alternativas descartadas
- **Solo las entradas y salidas de explotación.** Más fino, pero obliga a clasificar cada asiento por meses con las
  reglas del EFE: más trabajo y más lento. Para separar por actividades ya está el EFE.
- **Sumar los apuntes de las cuentas 57 uno a uno.** Un traspaso contaría como entrada y como salida a la vez: inflaría
  las dos barras sin que entrara ni saliera dinero.
- **Periodos medios × 365 siempre, como Ratios.** A mitad de año el periodo de cobro saldría el doble de lo real.
- **El vencido de la antigüedad de saldos en este tablero.** Mezclaría el saldo contable con el de las facturas; va en la
  v0.57.0 con los terceros sin conciliar.

## Consecuencias
- **Cuadra con lo que ya había:** entradas − salidas acumuladas = tesorería a la fecha − tesorería de apertura (la
  variación de efectivo del EFE), y los ratios al cierre son los de la pantalla Ratios. Caso completo: entraron
  210.860 € y salieron 81.000 €; clientes 21.400 €, proveedores 16.050 €, periodo de cobro 65 días y de pago 158 días.
- **Los dos tipos nuevos quedan para los tableros siguientes:** el de Impuestos usará el movimiento por meses.
- **Limitaciones conocidas:**
  - un traspaso registrado en **dos asientos** (uno por cada banco) sí cuenta como salida y entrada; lo correcto es un
    asiento con las dos cuentas;
  - el periodo medio de cobro compara clientes **con IVA** con ventas **sin IVA**, igual que en Ratios (es la fórmula
    habitual de los manuales);
  - la «prueba ácida» resta solo las existencias, no los anticipos a proveedores (como en Ratios).
- **Pruebas:** 75 de 75 en la base de datos y 292 tests de la web. La fase 75 comprueba con el caso completo:
  - que las cifras cuadran con el Balance en los 12 fines de mes, y que entradas − salidas es la variación de la
    tesorería;
  - que un traspaso de 572 a 570 no cuenta y un pago sí (regresión: falla si se suman los apuntes uno a uno);
  - que los ratios al cierre son los de Ratios, y que a mitad de año el periodo de cobro usa 181 días (falla con 365);
  - «hasta» con el año anterior, la simulación con un borrador, que otra empresa no ve nada y 53 ms con una empresa
    de 30.000 asientos al lado.

## Cómo explicarlo
- **Tesorería no es resultado:** una empresa con beneficio puede quedarse sin caja si cobra tarde y paga pronto. Este
  tablero enseña el dinero, no el beneficio.
- **Fondo de maniobra:** lo que queda del corto plazo para trabajar (activo corriente − pasivo corriente). Si es
  negativo, parte del inmovilizado se financia con deudas a corto.
- **Liquidez general, prueba ácida y disponibilidad:** tres escalones de «¿puedo pagar lo que vence pronto?»: con todo
  el activo corriente, sin vender el almacén y solo con lo que hay en el banco.
- **Periodos medios de cobro y de pago:** los días que se tarda en cobrar y en pagar. Si se cobra más tarde de lo que se
  paga, la empresa financia a sus clientes con su propia caja. El límite legal de pago a proveedores es, en general, de
  60 días (Ley 3/2004 de morosidad). *(Pendiente de validar por Diosvely.)*
- **Por qué asiento a asiento:** un traspaso del banco a la caja no es dinero que entre ni que salga de la empresa; en
  su asiento, lo que sale de una cuenta 57 entra en otra y suma cero.
- **En BC y SAP:** Business Central tiene las *cues* de efectivo del *Role Center*, el *Cash Flow Forecast* y los
  periodos medios en *Account Schedules*; SAP S/4HANA, las *Fiori apps* «Cash Position», «Days Sales Outstanding» y
  «Days Payable Outstanding». *(Pendiente de validar por Diosvely.)*
