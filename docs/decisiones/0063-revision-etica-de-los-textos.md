# ADR 0063 · Revisión ética de los textos: sin nombres de programas comerciales, y los modos de control por lo que hacen

- **Fecha:** 2026-11-08
- **Versión:** v0.60.1
- **Estado:** aceptada (decisión de Diosvely del 07-11-2026 y del 08-11-2026; diseño validado, `diseno-v0.60.1.md`).

## Contexto

El Mini ERP es un laboratorio para **practicar y aprender** contabilidad española (ADR 0010). Su contenido tiene que
ser **didáctico**, sin polémicas ni comparaciones. Al revisar la documentación y los textos de la web aparecieron:

- nombres de programas contables comerciales usados como modelo («fecha rápida como …», «el asistente de cierre de …»,
  «importa el diario de …») en el README, el CHANGELOG, la bitácora, 16 ADR, los textos de la web y los comentarios
  del código y de las migraciones;
- los dos modos de las cuentas controladas presentados como **«estricto = SAP / BC»** frente a **«guiado = los ERP
  españoles»**, una contraposición que no enseña nada y puede leerse como una crítica;
- una expresión de captación («un gancho de colaboración», ADR 0021);
- un ejemplo de la ficha del PGC de la cuenta 112 que parecía sacado de una contabilidad real de prueba.

## Decisión

1. **En nada de lo que se lee se nombra ni se compara un programa comercial**: textos de la web, documentación, ADR,
   CHANGELOG, bitácora y comentarios del código y de las migraciones. **Business Central y SAP** se pueden citar
   como **referencia de buenas prácticas** para explicar un concepto, nunca para comparar.
2. **Los modos de control se explican por lo que hacen:**
   - **estricto: control antes de contabilizar** (preventivo): solo el módulo mueve la cuenta controlada;
   - **guiado: control después** (posterior o detectivo): el asiento manual se permite con aviso y se revisa en
     Comprobaciones.
3. **El importador describe el archivo por sus columnas** («diario en Excel: Fecha, Asiento, Cuenta, Debe, Haber…»).
   El valor interno `'sage'` y la función `fromSage` se quedan porque no se leen en pantalla (opción A).
4. **Lo histórico también se corrige en lo ético** (nombres, contraposiciones, captación), pero **no las cifras** que
   eran verdad en su versión. Un ADR corregido lleva al final «Revisión ética (v0.60.1, fecha): …».
5. **Los textos que viven en la base de datos** se cambian con una migración solo de textos (**0090**): el concepto
   «Modo estricto o guiado», el ejemplo de la cuenta 112 (ahora inventado: 80.000 · 8.000 · 72.000) y dos
   comentarios de tabla y columna. Las migraciones antiguas se editan también, para que una instalación nueva dé lo
   mismo.
6. **Dos pruebas guardianas** para que no vuelva a pasar:
   - **fase 83** (base de datos): ningún concepto, ficha del PGC ni comprobación del auditor nombra un programa
     comercial;
   - **`ethics.test.js`** (web): ningún archivo del repositorio que se lea los nombra ni contrapone los modos.

## Alternativas descartadas

- **Una excepción para nombrar el formato de archivo** del importador (opción C): la regla se quedaría con una puerta
  abierta; describirlo por sus columnas enseña más.
- **Renombrar también lo interno** (`'sage'`, `fromSage`) (opción B): más cambios, el mismo resultado visible.
- **Reescribir el historial de Git** para borrar el ejemplo antiguo de la 112: es arriesgado y la regla no lo pide.

## Consecuencias

- **Pruebas:** 83 de 83 en la base de datos y 339 tests de la web (2 nuevos en `ethics.test.js`). La regresión
  (regla A1) está dentro de las dos pruebas: si se pone el nombre de un programa comercial en un texto, fallan.
- **Ningún cálculo cambia.** Solo palabras.
- **Lo que queda abierto:** el criterio legal sobre el uso de nombres comerciales lo revisa el chat de auditoría
  fiscal (encargo AF-E1); el lema de la portada, el chat de redacción (H-19).

## Cómo explicarlo

- **Control preventivo y control posterior.** Es el vocabulario del control interno. El preventivo impide el error
  (la cuenta de proveedores solo la mueve su módulo); el posterior lo encuentra después con cuadres (el IVA contra el
  libro registro, cada tercero contra sus facturas). Un auditor usa los dos, y el ERP deja elegir con un interruptor.
- **Enseñar la norma, no el programa.** Lo que vale en cualquier empresa es el PGC y el control interno; cada programa
  lo resuelve a su manera, y eso no hace falta compararlo.
- **Una prueba que vigila una regla ética.** Igual que una prueba vigila que el balance cuadre, otra vigila que una
  regla de contenido se siga cumpliendo cuando el proyecto crece.
