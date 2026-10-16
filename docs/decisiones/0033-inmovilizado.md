# ADR 0033 · Inmovilizado: ficha, amortización lineal, baja y venta con resultado

- **Fecha:** 2026-10-16
- **Versión:** v0.35.0
- **Estado:** aceptada

## Contexto

Hasta ahora un ordenador o una furgoneta eran un apunte en la 21x, y su amortización, un asiento manual 681/281
cada mes o cada año. Nada recordaba la vida útil, el cuadro de amortización ni el valor neto contable. La venta exigía
calcular a mano la pérdida o el beneficio. En Business Central (Activos fijos) y en SAP (FI-AA), en cambio, el activo
tiene su ficha y el módulo hace los asientos.

Es la prioridad 1 de la fase 2 del plan revisado (15-10-2026).

## Decisión

1. **Ficha del activo** (`erp.fixed_assets`, migración 0041):
   - se da de alta desde la línea de una factura recibida a una cuenta 20x/21x/22x, o sin factura para lo que ya
     existía;
   - recoge el coste, el valor residual, la fecha de compra y la de **puesta en funcionamiento** (desde ahí se
     amortiza, NRV 2.ª) y la vida útil en meses;
   - crea sola su 28x (2817, 2818…) y su 68x;
   - los terrenos (210, 220) no se amortizan.
2. **Amortización lineal por meses, con el primer mes proporcional a los días.** Es la cuota de los libros de texto:
   furgoneta de 18.000 con 2.000 de residual a 96 meses → 9 meses + 17/31 en 2026 = 1.591,40.
   - Hay un cuadro de amortización por años.
   - «Amortizar hasta» genera un asiento 68x/28x con todos los activos; la última amortización se deshace desde el
     módulo y nunca desde el diario.
3. **Baja y venta, en dos piezas** (como BC o A3):
   - la venta es una **factura emitida a la cuenta del activo** (no a una 7xx), para que el IVA entre en el libro
     registro y en el 303;
   - la baja amortiza hasta la fecha, cancela la 28x y lo que queda de la 2x, y lleva la diferencia a **67x** o
     **77x**. El resultado es el asiento clásico, pero con el IVA declarado;
   - el retiro sin venta (siniestro u obsolescencia) lleva todo el valor neto a pérdidas. La baja se puede deshacer.
4. **Tabla fiscal** (art. 12.1.a de la Ley 27/2014 del IS) con 18 tipos de activo. Si la amortización contable supera
   el coeficiente máximo, o la vida supera el período máximo, el ERP **avisa**: la diferencia es temporaria y se ajusta
   en el Impuesto sobre Sociedades. No lo bloquea, porque la contable sigue la vida útil real.
5. **Integración** (migración 0042):
   - las cuentas 20x/21x/22x y 28x pasan a ser **controladas** por el módulo;
   - dos comprobaciones nuevas: las fichas frente a la 21x y la 28x, y la amortización pendiente;
   - el cierre avisa de los activos sin amortizar;
   - la **prorrata** deja fuera las ventas de bienes de inversión (art. 104.Tres.2.º LIVA);
   - el glosario recoge «Inmovilizado» y «Valor neto contable»;
   - el diario marca los asientos del módulo.
6. **Web:** pantalla Inmovilizado, con resumen, lista, ficha con el cuadro, «Amortizar hasta», baja o venta y alta
   con vista previa y aviso fiscal. También un acceso desde el Inicio.

## Alternativas descartadas
- **Amortizar por días (cuota diaria):** más exacta, pero no coincide con los supuestos de los libros, que van por
  meses.
- **Métodos degresivos y por unidades de producción:** el lineal es el habitual en las pymes. Quedan como mejora.
- **Venta como asiento único del módulo, sin factura:** el IVA de la venta no estaría en el libro registro ni en el 303.
- **Bloquear la amortización por encima del máximo fiscal:** la contabilidad sigue la vida útil real (NRV 2.ª); el
  límite fiscal solo afecta al Impuesto sobre Sociedades.

## Consecuencias
- El ERP cubre el ciclo completo de un activo, y la ficha y la contabilidad se vigilan entre sí.
- **Limitación conocida:** la **rectificativa de una compra de inmovilizado** baja la 21x, pero no ajusta el coste
  de la ficha. La comprobación lo detecta. Pasa al backlog.
- **Pruebas:** 37 de 37 en la base de datos y 104 tests de la web.
  - Las fases 36 y 37 son nuevas, con el supuesto calculado a mano.
  - La fase 34 compra, amortiza y vende activos al azar, con cuatro semillas.
