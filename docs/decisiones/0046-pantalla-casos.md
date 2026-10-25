# ADR 0046 · Pantalla «Casos»: cargar un caso completo y compararlo

- **Fecha:** 2026-10-25
- **Versión:** v0.46.0
- **Estado:** aceptada

## Contexto

La v0.45.0 puso en el motor un caso completo, «Taller Atlántico SL»: el motor lo carga con cada módulo y lo compara al
céntimo con el cálculo a mano. Pero solo se podía cargar desde el SQL. Para estudiarlo hacía falta:
- cargarlo desde la web;
- ver cada operación con su porqué y su pantalla;
- **hacer yo el cierre** y comprobar si me sale lo mismo que en el documento.

## Decisión

Diseño validado por Diosvely antes de construir (paso 238):

1. **Dos modos de carga:**
   - **«Completo»:** las 19 operaciones, con el cierre hecho. Sirve para mirar cada pantalla y comparar.
   - **«Hasta el cierre»:** las operaciones 1 a 10, con el año abierto. Las 11 a 19 (amortización, subvención,
     intereses, periodificación, deterioro, existencias, impuesto y cierre) las hace quien estudia con el asistente de
     cierre.
2. **Dónde va:**
   - En la lista de empresas, una tarjeta «Casos completos» con los dos botones. `erp.create_case_company` crea la
     empresa (en modo estricto y con el límite de empresas de siempre), carga el caso y abre su pantalla.
   - Dentro de la empresa del caso, **«Caso»** en el menú (en Básico y en Auditor), solo en esa empresa.
3. **Las operaciones del caso** van en la base de datos (`erp.case_steps`, en español y en inglés), como los supuestos de
   Practicar: fecha, asiento, por qué (con la norma), pantalla y paso del asistente de cierre.
   - `erp.case_entries` apunta qué asientos hizo cada operación al cargarla, para ir de la operación a su ficha.
   - `erp.case_progress` dice si cada una está hecha. Las del cierre que hace quien estudia cuentan como hechas cuando
     su paso del asistente está hecho.
4. **Cada cifra de la comparación tiene un estado:**
   - **igual;**
   - **pendiente:** no coincide, pero aún no está contabilizado el Impuesto sobre Sociedades, así que falta el cierre;
   - **diferencia:** no coincide con el cierre hecho.

   La comparación va por grupos (PyG, balance, ECPN, EFE, IS, 420 y 111). Cada grupo trae su tabla y un enlace a su
   pantalla, y se exporta a Excel. Con la 0068, «mis empresas» dice qué caso tiene cargado cada empresa y la comparación
   trae el nombre de cada partida.

## Alternativas descartadas
- **Cargar el caso en una empresa que ya existe.** Sus asientos se mezclarían con los del caso y la comparación no
  diría nada. El caso va siempre en una empresa nueva.
- **Marcar como «diferencia» todo lo que no coincide.** En el modo «hasta el cierre», antes del cierre saldrían 52
  diferencias que no son errores.
- **Llevar los textos de las operaciones en la web.** Irían por un lado y las cifras por otro. En la base de datos
  están junto al caso, como los supuestos de Practicar.
- **Una pantalla de la cabecera, junto a Practicar.** Diosvely prefirió tenerla en la lista de empresas y dentro de la
  empresa del caso, que es donde se trabaja.

## Consecuencias
- Un caso completo se carga y se estudia sin salir de la web. El modo «hasta el cierre» es un examen práctico del cierre
  con su corrección al céntimo.
- **Limitaciones conocidas:**
  - hay un solo caso; los siguientes son filas nuevas en el catálogo y una rama nueva en `erp.load_case`;
  - las operaciones que hace quien estudia no se enlazan a sus asientos: se ven en el diario y en su pantalla;
  - la comparación tarda alrededor de un segundo y medio, porque calcula todos los estados.
- **Pruebas:** 62 de 62 en la base de datos (fase 62) y 236 tests en la web. Comprobada en el navegador a 1366 y 1920 px
  (claro y oscuro) y en el móvil, sin errores de accesibilidad.

## Cómo explicarlo
- **Un caso completo es un examen con la solución al lado.** Primero se mira hecho; luego se carga «hasta el cierre» y el
  cierre se hace a mano. El ERP dice qué cifras salen igual y cuáles no.
- **Una diferencia apunta a lo que falta.** Si la amortización está 3.000 por debajo, falta la amortización. Si la
  diferencia solo está en el EFE, la clasificación de algún cobro o pago está mal. Seguir la diferencia hasta su asiento
  es lo que hace un auditor.
- **«Pendiente» no es un error.** Mientras no se ha hecho el cierre, el resultado no puede coincidir. Por eso el estado
  depende de si ya está contabilizado el impuesto, el último paso antes de la regularización.
- **En BC y SAP** esto se hace con empresas de demostración (CRONUS, IDES) y con guías de formación. Aquí el caso trae su
  solución calculada a mano y se corrige solo.
