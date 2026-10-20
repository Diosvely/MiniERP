# ADR 0039 · Corrector de supuestos: solo cuentas válidas del PGC

- **Fecha:** 2026-10-20
- **Versión:** v0.40.1
- **Estado:** aceptada

## Contexto

La revisión externa del 19-10-2026 encontró un fallo en `erp.grade_exercise` (v0.40.0). El corrector daba por buena
cualquier cuenta que **empezara** por la esperada:
- la **4009** en lugar de la **400** salía correcta, con nota 100. La 4009 es «Proveedores, facturas pendientes de
  recibir o de formalizar», un concepto distinto;
- cuentas que no existen, como `600xyz` o `400ABC`, también salían correctas.

En una herramienta para aprender, un corrector que aprueba un error enseña ese error.

## Decisión

1. **Formato.** Una cuenta de la respuesta solo vale si son dígitos. Si no, va a «sobra» con el motivo `invalid`.
2. **Existencia** (`erp.pgc_account_problem`):
   - con 1-3 dígitos, tiene que ser un grupo, subgrupo o cuenta del PGC (`erp.coa_template`);
   - con 4 o más, su cuenta de 3 dígitos tiene que estar en el PGC.
   - Si no, va a «sobra» con el motivo `not_in_pgc` (la 9999, la 999).
   - Así siguen valiendo la 4000 («Proveedores (euros)») y cualquier subcuenta, como la `40000001` o la `47200021`.
3. **Cuentas de 4 dígitos con otro significado** (`erp.pgc_distinct_accounts`): la 4009, la 4109, la 4309 y la 4409,
   las de facturas pendientes de recibir o de formalizar.
   - Una respuesta suya, o de una subcuenta suya, no casa con la cuenta madre (`erp.account_matches`).
   - Se explica la diferencia en las pistas: «La 4009 es para facturas pendientes de recibir… Si la factura ya está
     recibida, va a la 400».
4. **Las esperadas de grupo** (6 y 7 en la regularización) siguen casando por su primer dígito.
5. **La misma regla para todos:** la persona y la IA se corrigen con la misma función (`erp.submit_exercise` llama a
   `erp.grade_exercise`). La web enseña el motivo de cada cuenta rechazada.
6. **Nueva regla de trabajo, desde esta versión:** cada arreglo lleva una prueba de regresión, y la prueba tiene que
   **fallar sin el arreglo**. La fase 51 se ejecutó antes del arreglo: la 4009 daba `"ok": true` y nota 100.

## Alternativas descartadas
- **Añadir la 4009 y sus hermanas a `erp.coa_template`**, como pedía la revisión. Cambiaría la cuenta madre
  (`template_account`) de las subcuentas nuevas 4009xxxx y los informes por niveles de las empresas nuevas. Una tabla
  aparte da el mismo resultado sin efectos secundarios. Los grupos 8 y 9 sí llegarán a la plantilla, en su bloque.
- **Rechazar toda cuenta de 4 dígitos que no sea su madre**, como decía la revisión tal cual. Rechazaría la 4000 y
  la 4300 («Proveedores / Clientes (euros)»), que significan lo mismo que la 400 y la 430.
- **Incluir la 4069, la 4319 y la 4759**, que pedía la revisión. No figuran en el cuadro de cuentas del PGC 2007
  (RD 1514/2007): la 406 y la 475 no tienen esas divisiones. Quedan fuera hasta que alguien las contraste en el BOE.
- **Exigir que la cuenta exista en la empresa del alumno:** Practicar no depende de ninguna empresa, y lo que se
  aprende es el cuadro de cuentas del PGC.

## Consecuencias
- Practicar y «Evaluar la IA» ya no aprueban cuentas equivocadas ni inventadas, y explican por qué.
- **Limitaciones conocidas:**
  - Solo se distinguen las cuatro cuentas de «facturas pendientes». Si un supuesto nuevo espera otra cuenta con
    divisiones de distinto significado (la 520 con la 5208 de efectos descontados, por ejemplo), se añade a
    `erp.pgc_distinct_accounts`.
  - Una subcuenta inventada de una cuenta real (la 4001) se acepta como subcuenta de la 400.
- **Pruebas:** 51 de 51 en la base de datos y 149 tests en la web. La fase 51 comprueba:
  - la 4009, la 40090001 y la 4309, con su pista;
  - las cuentas no válidas y las que no existen;
  - que las 14 soluciones y sus alternativas siguen sacando un 100;
  - que las 50 subcuentas que crea el propio ERP siguen valiendo (IVA, IGIC, inversión del sujeto pasivo, recargo,
    terceros y banco, en la Península y en Canarias).

## Cómo explicarlo
- Un corrector que aprueba un error enseña ese error: si das por buena la 4009, el alumno aprende que da igual.
- La 4009 no es «una 400 más larga». Es otro concepto del PGC: la compra que ya ha ocurrido pero cuya factura no ha
  llegado al cierre (devengo). Cuando llega la factura, la deuda pasa a la 400.
- Por eso el corrector mira el significado, no solo los primeros dígitos. La 40000001 es una subcuenta de la 400;
  la 40090001 es una subcuenta de la 4009.
- Business Central y SAP no tienen este problema porque no adivinan la cuenta: la eligen los *posting groups* (BC) o
  la determinación de cuentas (SAP), y la cuenta de «facturas pendientes» es una cuenta aparte en su configuración.
