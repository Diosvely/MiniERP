# ADR 0044 · Subvenciones, grupos 8 y 9 y estado de cambios en el patrimonio neto

- **Fecha:** 2026-10-25
- **Versión:** v0.44.0
- **Estado:** aceptada

## Contexto

Con el resultado repartido (v0.42.0) y la financiación (v0.43.0), al ERP le faltaba la última pieza de las cuentas
anuales del PGC: el **estado de cambios en el patrimonio neto** (ECPN).

Lo que más mueve ese estado en una pyme son las **subvenciones de capital**. No son ingresos del año en que se cobran:
van al patrimonio neto a través de los **grupos 8 y 9**, que el ERP aún no tenía en la plantilla.

En Canarias son frecuentes (Gobierno de Canarias, cabildos, Servicio Canario de Empleo) y salen en casi todos los
exámenes.

Las normas que se aplican son:
- **PGC 2007, NRV 18.ª:** subvenciones, donaciones y legados;
- **NRV 13.ª:** el efecto impositivo;
- **3.ª parte:** el ECPN;
- **5.ª parte:** los grupos 8 y 9.

## Decisión

1. **Supuestos calculados a mano y validados antes de programar** (paso 230): del S1 al S4. El motor tiene que dar sus
   cifras **al céntimo**.
2. **Plantilla.**
   - Se añaden los grupos 8 y 9 y la 522, con los títulos y subgrupos que se usan: 830 / 8301, 84x y 94x. Se añaden
     también, como cuentas de título, a las empresas que ya existen.
   - **Balance.** Durante el año, el saldo de los grupos 8 y 9 ya es patrimonio neto (A-2 Subvenciones), igual que el
     de los grupos 6 y 7 es el resultado del ejercicio. Sin esto, el balance no cuadraba.
   - **Estado de flujos de efectivo.**
     - Los grupos 8 y 9 y la 4708 de capital van a financiación (cobros por subvenciones, C-9 e).
     - La 83 va con los impuestos, como la 479 con la que se compensa.
     - La 4708 de las subvenciones a la explotación es **otra subcuenta** (47089…), que va a explotación. El cobro de
       una de capital es un flujo de financiación y el de una a la explotación, de explotación, y el EFE clasifica por
       cuenta.
3. **Un módulo de subvenciones** (0064), con una ficha por subvención:
   - **Tipos.** De capital (vinculada a un activo de Inmovilizado) o a la explotación.
   - **Reintegrable o no.**
     - **Concesión.** Una de capital no reintegrable va a 4708 / 940, más el efecto impositivo 8301 / 479. Una a la
       explotación, a 4708 / 740. Una reintegrable, a 522 (si la condición vence en 12 meses) o a 172.
     - **Si ya está cobrada,** el cargo va al banco en lugar de a la 4708.
   - **Cobro:** 572 / 4708.
   - **Cuando se cumple la condición,** la reintegrable pasa a 940 (con su efecto impositivo) o a 740.
   - **Imputación en el cierre.** Se calcula como la subvención × lo amortizado del activo desde el ejercicio de la
     concesión / su coste, menos lo ya imputado. El efecto impositivo es el tipo × lo imputado. Así se contabiliza 840 /
     746 y 479 / 8301.
     - Es acumulada: repetir el cierre no cambia nada.
     - Primero hay que amortizar el activo.
   - **Tipo del efecto impositivo:** el 25 % por defecto, modificable en la ficha.
   - **Deshacer:** del último movimiento al primero.
4. **Integración** (0065):
   - **Cierre del ejercicio.** La regularización salda los grupos 8 y 9 contra su 13x: las 94x y 84x, contra la 13 del
     mismo tercer dígito; las 83x, contra la 130. Si la subcuenta 13x no existe, el cierre la crea. La apertura lleva
     la 130.
   - **Baja del activo** en Inmovilizado: imputa lo pendiente de sus subvenciones. Al anular la baja, se deshace.
   - **ECPN** (`erp.equity_statement`), para todas las empresas:
     - **Parte A,** desde los grupos 6, 7, 8 y 9. El efecto impositivo se separa según el movimiento de la subvención
       que lo originó.
     - **Parte B,** por columnas: capital, prima, reservas, resultados anteriores, resultado, dividendo a cuenta y
       subvenciones. Tiene estas filas:
       - **saldo inicial:** la apertura o, si no la hay, el año anterior;
       - **ingresos y gastos reconocidos;**
       - **operaciones con socios:** capital, dividendos y dividendos a cuenta. En el reparto, la parte que va a
         dividendos;
       - **otras variaciones:** el resto del reparto, las compensaciones y los asientos manuales.
     - Se comprueba contra el patrimonio neto del balance.
   - **Asistente de cierre:** paso nuevo, el 10 «Subvenciones». El auditor pasa al 11, el Impuesto sobre Sociedades al
     12 y el cierre al 13.
   - **Auditor:** `grants_ledger`, en el que la regularización del cierre cuenta como movimiento del módulo.
   - **Cuentas controladas:** 94, 84, 83 y 4708.
   - **Glosario:** cuatro términos nuevos. **Practicar:** dos supuestos nuevos.
5. **Pantallas** (paso 233):
   - **Subvenciones:** la lista, la ficha con sus acciones, el alta con el asiento y el % del activo que financia, y el
     cierre;
   - **ECPN,** en Informes: las partes A y B con su comprobación, y exportación a Excel.

## Alternativas descartadas
- **Llevar la subvención a la 130 directamente**, sin los grupos 8 y 9. Es lo que hacen muchos programas sencillos, pero
  así no hay parte A del ECPN: el estado de ingresos y gastos reconocidos sale justamente de esos grupos.
- **Imputar de forma lineal por años**, sin mirar la amortización. Rompe la correlación de la NRV 18.ª: si el activo se
  amortiza por meses, se vende o se deteriora, la imputación tiene que seguirlo.
- **Una sola 4708 para las dos clases.** El EFE la clasificaría mal en una de ellas, y el invariante «directo =
  indirecto» lo detectó al probar.
- **Controlar la 130, la 172 y la 522.** La apertura de una empresa que ya existía, o importada, las necesita a mano.
- **Enseñar la parte A del ECPN solo a las empresas que aplican el PGC normal.** Diosvely decidió enseñarla a todas:
  el laboratorio enseña el modelo completo.

## Consecuencias
- Las cuentas anuales del PGC ya están completas en el ERP: balance, cuenta de resultados, ECPN y EFE.
- **Limitaciones conocidas:**
  - no hay donaciones ni legados de socios, ni subvenciones en especie, ni el reintegro efectivo de una subvención;
  - una subvención de capital solo financia activos amortizables (un terreno no tiene ficha en Inmovilizado);
  - el deterioro del activo no imputa por sí solo: la NRV 18.ª lo pide, y queda pendiente;
  - en la parte B del ECPN, «Otros instrumentos de patrimonio», «Ajustes por cambios de valor» y las acciones propias no
    tienen columna propia;
  - los gastos de constitución contra reservas van a «Otras variaciones».
- **Pruebas:** 60 de 60 en la base de datos (fases 59 y 60) y 227 tests en la web. **Lo que salió al probar:**
  - el balance no cuadraba con los grupos 8 y 9 antes de regularizarlos;
  - el EFE se rompía con las cuentas nuevas y clasificaba mal la 4708;
  - en el ECPN, un `NULL` en una condición dejaba fuera el resultado de la apertura;
  - en el ECPN, la comparación con el balance cogía la 479 (`PNC.IV` empieza por «PN»);
  - en la pantalla, una subvención mayor que el coste del activo no se avisaba.

## Cómo explicarlo
- **Una subvención para comprar una máquina no es un ingreso del año en que se cobra.** Si lo fuera, ese año tendría un
  beneficio enorme y los siguientes cargarían con la amortización sin nada que la compense. Por eso se va reconociendo
  **al ritmo de la amortización**: el año que la máquina gasta el 10 %, la subvención aporta el 10 %. Es el principio
  de correlación entre ingresos y gastos.
- **Mientras tanto, es patrimonio neto, pero «neto de impuestos».** Cuando pase a resultados tributará, así que el 25 %
  se registra ya como un pasivo diferido (479). Por eso la 130 tiene 13.500 y no 18.000: los otros 4.500 se deben a
  Hacienda en el futuro.
- **Los grupos 8 y 9 son una cuenta de resultados del patrimonio neto.** Igual que los grupos 6 y 7 se cierran contra la
  129, los grupos 8 y 9 se cierran contra la 130. De ahí sale la parte A del ECPN: lo que se ha ganado o perdido sin
  pasar por la cuenta de resultados.
- **El ECPN contesta «¿por qué ha cambiado mi patrimonio?».** Puede ser por el resultado y las subvenciones (reconocidos),
  por lo que han puesto o retirado los socios (ampliaciones, dividendos) o por cambios entre partidas (el reparto a
  reservas). Si el saldo final no coincide con el balance, algo está mal.
- **Reintegrable o no:** mientras puede tener que devolverse, es una deuda. El día que se cumple la condición, deja de
  serlo.
- **En BC y SAP** no hay módulo estándar de subvenciones: se registran en el diario y el ECPN se monta con un informe.
  Aquí sale del diario solo, comprobado contra el balance.
