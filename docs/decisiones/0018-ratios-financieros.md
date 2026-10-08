# ADR · Ratios financieros del Modo auditor

- **Fecha:** 2026-10-08
- **Versión:** v0.21.0
- **Estado:** aceptada

## Contexto

Con la importación de diarios (v0.19.0) y el estado de flujos de efectivo (v0.20.0), el ERP ya tiene todo lo
necesario para el último bloque del análisis que se suele hacer en Excel o Power BI: los **ratios**.
El objetivo es aprender a leerlos, no solo a calcularlos. Por eso cada ratio tiene que poder comprobarse a mano.

## Decisión

1. **El catálogo de 21 ratios es una tabla** (`ratio_defs`) en 5 grupos: liquidez, solvencia y endeudamiento,
   rentabilidad, actividad y flujos de caja. Cada ratio guarda su fórmula, su explicación y su zona de
   referencia, en español y en inglés.
2. **Se calculan con las partidas del balance y la PyG del propio ERP** (`fs_amounts`, modelo PYMES) y con el
   total A) del estado de flujos. Cualquier mejora en la clasificación de cuentas llega sola a los ratios.
3. **Se usan saldos de cierre, no medias.** Así cada ratio se comprueba con el balance que hay en pantalla.
   Los manuales usan a veces saldos medios para la rotación y los periodos medios; se anota como mejora futura.
4. **Las zonas de referencia son las de los manuales españoles** (Amat, Rivero…) y son orientativas.
   Fuera de la zona, el ratio se marca como bajo o alto, pero no como "malo": depende del sector, y así se dice
   en pantalla.
5. **Cada ratio devuelve su numerador y su denominador**, para que la pantalla muestre la fórmula con los
   importes reales. Si el denominador es 0, el ratio no tiene valor; nunca se muestra un cero engañoso.
6. **Rendimiento:** el cálculo interno (`ratio_parts`) es `SECURITY DEFINER` y no se expone a la web.
   `financial_ratios` comprueba `can_read`. Con la empresa más grande tarda unos 2,7 s.

## Alternativas descartadas

- **Calcular los ratios en la web (JavaScript).** Se descarta porque las fórmulas quedarían repartidas y no se
  podrían usar desde SQL ni desde Power BI.
- **Una fórmula editable por el usuario** (un mini lenguaje de expresiones). Es más flexible pero más complejo.
  SIMPLICIDAD: un ratio nuevo es una fila más en `ratio_defs` y una línea en `ratio_parts`.

## Consecuencias

- El Modo auditor queda completo: importar → balance y PyG → flujos de efectivo → ratios.
- Los ratios de las empresas reales enseñan cosas que no se ven en los estados financieros, por ejemplo:
  - periodos de cobro por encima del máximo legal de 60 días;
  - beneficio que no llega a la caja;
  - empresas que ganan por rotación y no por margen.
- **Limitaciones conocidas:**
  - el periodo medio de cobro sale algo alto, porque los clientes llevan IVA / IGIC y la cifra de negocios no;
  - el periodo medio de pago solo mide proveedores 400 frente a los aprovisionamientos.
- **Pendiente para más adelante:** comparar varias empresas en una misma pantalla y llevar los ratios a Power BI.