# ADR 0048 · PGC de estudio: el Plan General de Contabilidad dentro del ERP

- **Fecha:** 2026-10-26
- **Versión:** v0.48.0
- **Estado:** aceptada

## Contexto

Para estudiar contabilidad hay que tener el PGC a mano: qué es cada cuenta, cuándo se carga y cuándo se abona, dónde
sale en las cuentas anuales y qué norma de valoración la trata. Hasta ahora eso quedaba fuera del ERP, en el BOE o en
un manual. En otro chat Diosvely preparó un prototipo con 703 cuentas, 70 fichas, las 23 normas de registro y valoración
(NRV) y los 6 principios contables, más su especificación (`SPEC_pgc_estudio.md`). Antes de construir se comprobaron
los datos y se validó el diseño (`diseno-v0.48.0.md`):
- todos los ejemplos cuadran y los nombres coinciden con el plan de cuentas del ERP;
- faltaban la 2804 y las cuentas de los grupos 8 y 9, que el ERP usa desde la v0.44.0.

## Decisión

1. **Un libro de consulta, aparte de la contabilidad** (migración 0071):
   - seis tablas en inglés, como el resto de la base de datos (ADR 0003): `pgc_groups`, `pgc_subgroups`,
     `pgc_accounts`, `pgc_cards`, `pgc_valuation_rules` y `pgc_principles`; los textos van en español;
   - de **solo lectura**: las lee cualquiera que haya entrado y nadie las cambia desde la web;
   - **comunes a todas las empresas**: no tocan el plan de cuentas operativo ni los asientos;
   - contenido: 9 grupos, 78 subgrupos, 712 cuentas (las 703 del prototipo, la 2804 y 8 de los grupos 8 y 9, estas sin
     ficha), 70 fichas, 23 NRV y 6 principios.
2. **Las fichas, tal cual y «pendientes de validar por Diosvely»** (regla A3): una columna `validated` y un aviso en
   cada ficha. Solo se quitó lo que se salía del tema (la frase sobre Power BI de la 129).
3. **Pantalla «PGC de estudio»** (`#/pgc`), con el botón «PGC» en la cabecera, al lado de Practicar:
   - **Cuentas:** buscador (por número o nombre, sin tildes), filtros por grupo y «solo con ficha», árbol
     grupo › subgrupo › cuenta y la ficha: uso, Debe (azul) y Haber (teja), saldo, dónde aparece, normativa, ejemplo con
     IGIC 7 % y su total, «Ojo» y los términos del glosario;
   - las cuentas que salen en los textos («contra la 480») son enlaces a su ficha;
   - **Normas de valoración** y **Principios**, cada una en su pestaña;
   - **enlaces directos:** `#/pgc/6400`, `#/pgc/nrv/12` y `#/pgc/principios`; el texto oficial está en 📘 Fuentes.
4. **El PGC en Nuevo asiento**, en un panel lateral como el de la IA:
   - un ⓘ en cada línea (o «?» en el campo de cuenta) abre la ficha de los 4 primeros dígitos de la subcuenta;
   - un botón «PGC» en la cabecera del asiento abre el buscador;
   - el aviso de cuenta controlada enlaza a su ficha;
   - el panel no se cierra al navegar entre fichas, y «Abrir en el PGC completo» lo abre en otra pestaña, así no se
     pierde el asiento.

## Alternativas descartadas
- **Mezclarlo con el plan de cuentas de la empresa.** El plan operativo es de cada empresa y se modifica; el PGC de
  estudio es la norma, igual para todos. Juntos, un cambio en uno estropearía el otro.
- **Cargar los datos desde un fichero JSON en la web.** En la base de datos se comprueban con pruebas (que todo cuadra y
  las referencias existen) y los podrán usar el Tutor y Practicar.
- **Abrir el PGC en otra pantalla desde el asiento.** Se perdería el asiento a medio escribir; el panel lo deja a la vista.
- **Copiar los colores y las fuentes del prototipo.** Se usa el diseño del ERP (modo oscuro y accesibilidad incluidos);
  del prototipo se queda la idea de Debe en azul y Haber en teja.

## Consecuencias
- Mientras se estudia o se contabiliza, la ficha de cualquier cuenta está a un clic, sin salir del ERP.
- **Limitaciones conocidas:**
  - 70 de 712 cuentas tienen ficha; las demás muestran su nombre y dónde aparecen en las cuentas anuales;
  - las fichas están pendientes de validar por Diosvely y no son el texto literal del BOE;
  - los textos de las fichas están en español, también con la web en inglés;
  - el panel está en Nuevo asiento, no en el Libro diario.
- **Pruebas:** 65 de 65 en la base de datos (fase 65: cuántos hay, todo cuadra, las referencias existen, el plan del
  ERP está entero y los permisos) y 265 tests en la web. Comprobado en el navegador a 1366 y 1920 px (claro y oscuro) y
  en el móvil, sin errores de accesibilidad.

## Cómo explicarlo
- **El PGC es el idioma común.** Cada número de cuenta dice qué es (el 4 son acreedores y deudores, el 40 proveedores, el
  400 los proveedores en euros). Saber leerlo es saber dónde va cada operación.
- **Cargo y abono no son «sumar» y «restar».** Cada cuenta tiene su naturaleza: un activo aumenta por el Debe y un
  pasivo por el Haber. La ficha lo dice en palabras («se carga al pagarles») y lo enseña con un asiento que cuadra.
- **La norma de valoración dice cuánto, el cuadro de cuentas dice dónde.** Por eso cada ficha enlaza a su NRV.
- **Consultar sin perder el hilo:** en el ERP real se consulta el PGC mientras se contabiliza; el panel hace lo mismo.
- **En BC y SAP:** el plan de cuentas lleva una descripción por cuenta (BC: «G/L Account Card»; SAP: el texto largo de la
  cuenta de mayor, FS00). Aquí la ficha va más allá: cuándo se carga y se abona, y un ejemplo.
