# ADR 0037 · Modelos tributarios (303 / 420, 390 / 425, 347 y 349) y base documental

- **Fecha:** 2026-10-19
- **Versión:** v0.39.0
- **Estado:** aceptada

## Contexto

La liquidación trimestral (v0.7.0) ya calculaba la cuota del 303 / 420 y la cuadraba con la contabilidad, pero no la
repartía en las casillas del modelo. Además faltaban los modelos anuales que se presentan con los datos que el ERP ya
tiene: el resumen anual del IVA o del IGIC (390 / 425), las operaciones con terceros (347) y las operaciones
intracomunitarias (349).

Durante la versión apareció una segunda necesidad. Cada regla del ERP se apoya en una norma o en unas instrucciones
oficiales, pero esas fuentes solo estaban en los ADR y en los comentarios del SQL: el usuario no las veía. Se decidió el
19-10-2026 crear una **base documental**: las fuentes oficiales, con su enlace y la fecha en que se comprobaron, a la
vista en cada pantalla.

## Decisión

1. **Casillas oficiales** (`erp.tax_form_boxes`, migración 0051), desde el libro registro de facturas:
   - con trimestre, el 303 (IVA) o el 420 (IGIC), según el territorio de la empresa; sin trimestre, el 390 o el 425;
   - **rectificativas**: no van en su tipo, sino en «modificación de bases y cuotas» (303: 14/15; 420: 21/22) y en
     «rectificación de deducciones» (303: 40/41; 420: 34/35);
   - **bienes de inversión**: la línea de compra a una cuenta 21 / 22 de al menos 3.005,06 € (art. 108.Dos.5.º LIVA;
     art. 40.Nueve.6.º Ley 20/1991, 500.000 pesetas). El resto, corriente;
   - **adquisiciones intracomunitarias**: servicios si la línea va a una 62; si no, bienes;
   - **cuota deducible** después de la prorrata, con su base en la misma proporción;
   - **420**: cada tipo ocupa tres casillas (base, tipo y cuota), del más bajo al más alto, como dicen sus instrucciones;
   - **compensación** de cuotas de periodos anteriores (303: 110 / 78 / 87; 420: 43) y el resultado (303: 71; 420: 45);
   - **resúmenes anuales**: totales (390: 47, 64, 65, 84-86, 95, 97, 98; 425: 74, 79, 94, 95, 113-119) y volumen de
     operaciones (390: 99, 103, 104, 105, 107, 108; 425: 120, 122, 126, 133, 134).
2. **Modelo 347** (`erp.form_347`, migración 0052, RD 1065/2007, arts. 31 a 35):
   - terceros con más de 3.005,06 € en el año, compras (clave A) y ventas (clave B) por separado, IVA o IGIC incluido,
     por trimestres;
   - las rectificativas se restan del tercero;
   - con inversión del sujeto pasivo, sin el IVA (el proveedor no lo repercute);
   - fuera: operaciones intracomunitarias, exportaciones, facturas con retención de IRPF y terceros extranjeros.
3. **Modelo 349** (`erp.form_349`, RIVA, arts. 78 a 81), solo con IVA:
   - claves E, S, A e I por NIF-IVA, según la cuenta de cada línea;
   - las rectificativas de otro trimestre van aparte, con el importe rectificado y el declarado entonces;
   - `erp.form_349_period`: mensual si E + S pasa de 50.000 € en el trimestre o en alguno de los cuatro anteriores.
4. **Base documental** (`src/sources.js` y `erp.sources`, migración 0053):
   - cada fuente guarda quién la publica (AEAT, ATC o BOE), el enlace oficial (ELI del BOE para las leyes), el artículo
     que se usa y la fecha en que se comprobó;
   - la copia de la base de datos se genera desde la web y un test vigila que coincidan, como el glosario;
   - las comprobaciones del auditor citan sus fuentes (`audit_checks.sources`) y la web las enseña con el botón 📘;
   - una comprobación informativa avisa de las fuentes sin revisar en más de un año.
5. **Comprobaciones nuevas** (0053): cada trimestre liquidado frente a su modelo (los que faltan por liquidar ya los
   avisa el asistente de cierre) y los terceros del 347 sin NIF. **Glosario:** «Modelo tributario (casillas)» y
   «Modelo 347».
6. **Web:** pantalla **Modelos** con cuatro pestañas (303/420, 390/425, 347 y 349), Excel e Imprimir, y el botón 📘
   en cada modelo y en Comprobaciones.
7. **Definición de terminado** (principio 7 del plan): un módulo está terminado cuando cita sus fuentes oficiales en la
   aplicación.

## Alternativas descartadas
- **Calcular los modelos desde la contabilidad** (como la liquidación): los modelos se rellenan con el libro registro,
  que es lo que pide la norma; la contabilidad sirve para cuadrarlos (comprobación nueva).
- **Asignar casillas fijas a cada tipo del IGIC**: las instrucciones del 420 dejan que cada grupo de tres casillas
  lleve el tipo que corresponda.
- **Presentar los modelos desde el ERP** (ficheros BOE o API de la AEAT): fuera del objetivo de aprendizaje; el ERP
  da el borrador para compararlo con el de Hacienda.
- **Guardar las fuentes solo en la base de datos**: la web las necesita sin consultas y el test de copia evita que se
  separen, igual que con el glosario.

## Consecuencias
- El ERP da el borrador de los seis modelos del IVA / IGIC que presenta una pyme con sus casillas oficiales.
- **Limitación conocida:** en el 390 los totales son exactos, pero las instrucciones no dicen qué par de casillas va con
  cada tipo; se sigue el orden del impreso y el ejemplo del Manual práctico de IVA 2025. Fuera de alcance: importaciones,
  regímenes especiales, ventanilla única, cobros en metálico del 347, arrendamientos y operaciones triangulares.
- **Pruebas:** 48 de 48 en la base de datos y 134 tests en la web.
  - **Fase 46:** 303, 420, 390 y 425 con sus supuestos de referencia, al céntimo.
  - **Fase 47:** 347 y 349, con sus supuestos.
  - **Fase 48:** la integración y la base documental.
  - **Fase 34:** el resumen anual es la suma de los cuatro trimestres en las dos empresas al azar.
