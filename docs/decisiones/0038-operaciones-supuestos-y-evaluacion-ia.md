# ADR 0038 · Catálogo de operaciones, supuestos autocorregidos y evaluación de la IA

- **Fecha:** 2026-10-19
- **Versión:** v0.40.0
- **Estado:** aceptada

## Contexto

Con el cierre, las nóminas y los modelos ya hechos, el ERP cubre el ciclo contable de una pyme. Faltaban dos piezas de
la ontología del plan:
- las **operaciones**: dónde se registra cada operación en el ERP y cuál es su asiento modelo;
- los **casos**: supuestos con solución conocida que sirven a la vez de ejercicio para aprender y de examen para la IA.

El Tutor de asientos proponía el asiento, pero no decía que una factura de proveedor no se registra con un asiento
manual, sino en Facturas. Y la IA solo se valoraba con 👍 / 👎, sin casos de solución conocida.

## Decisión

1. **Catálogo de operaciones** (`erp.operations`, migración 0054). Son 17 operaciones típicas: factura recibida, de
   profesional con retención, emitida, rectificativa, adquisición intracomunitaria, compra de inmovilizado, cobro,
   pago, amortización, periodificación, deterioro de clientes, provisión, variación de existencias, nómina,
   liquidación del IVA / IGIC, cierre y asiento manual.
   - Cada una guarda su **pantalla**, su **asiento modelo**, las cuentas del PGC que la identifican, su concepto del
     glosario y sus fuentes.
   - `erp.operation_for_lines` dice a qué operación se parece un asiento: la que tiene todas sus cuentas en él, y entre
     varias, la más concreta. Así el **Tutor dice dónde se registra** y enlaza a esa pantalla de la empresa.
2. **Supuestos autocorregidos** (`erp.exercises`, 0054). Son 14 supuestos en tres niveles: 5 básicos, 6 intermedios
   y 3 avanzados.
   - Cada uno tiene su enunciado (en español e inglés), el asiento esperado, la explicación, los errores frecuentes, su
     concepto del glosario y sus fuentes.
   - Seis **fuentes nuevas** en la base documental: PGC, LIS, LIRPF, RIRPF, LGSS y la Orden de cotización 2026.
3. **Corrección en la base de datos** (`erp.grade_exercise`). Cada línea esperada se busca por su **grupo o subgrupo
   del PGC** (vale cualquier subcuenta: `600` o `60000001`) y su lado, y se le da uno de cuatro estados:
   - **bien**;
   - **importe** distinto;
   - **lado** contrario;
   - **falta**.

   Además:
   - Lo que no casa con ninguna línea esperada **sobra**.
   - Varias líneas de la misma cuenta y lado se suman.
   - Algunas líneas admiten **alternativas** (la 700 por la 708), con aviso.
   - Los errores frecuentes reconocidos se explican.
   - Nota: % de líneas esperadas bien. Correcto: todas bien, nada sobra y cuadra.

   `erp.submit_exercise` corrige y guarda el intento (`erp.exercise_attempts`, cada usuario solo ve los suyos).
   `erp.v_exercise_progress` da el progreso.
4. **Evaluar la IA** (migración 0055). El Tutor de asientos resuelve los supuestos con su enunciado, a través del mismo
   `/api/tutor` y con la cuota de la empresa elegida. La misma función que corrige a la persona corrige a la IA
   (`by = 'ai'`), y cada intento guarda el **modelo** que contestó.
   - Solo se evalúan los supuestos del impuesto de la empresa: el Tutor aplica IVA o IGIC según el territorio.
   - Si no hay cuota para todos, primero van los que la IA aún no ha hecho.
5. **Web:**
   - pantalla **Practicar** (`#/practicar`, con sesión): lista por niveles con el progreso, formulario de asiento,
     corrección línea a línea, solución, 📘 y «dónde se registra»;
   - «📍 Dónde se registra» en el Tutor;
   - sección «Evaluar la IA».
   - **Glosario:** «Supuesto práctico» y «Catálogo de operaciones». Este último equivale a los *posting groups* de BC
     y a la determinación automática de cuentas (OBYC) de SAP.
6. **Diagnóstico de Supabase** (`scripts/generar-diagnostico.sh` → `database/diagnostico-supabase.sql`):
   - **Por qué:** al aplicar la 0054, la Supabase real no tenía tres migraciones antiguas (0039, 0040 y 0042) y la
     clave foránea de los conceptos falló.
   - **Qué es:** una consulta de solo lectura que lista lo que falta o sobra frente al repositorio: tablas, vistas,
     funciones (por la huella de su cuerpo), conceptos, comprobaciones y fuentes.
   - **Cuándo se regenera:** al cerrar cada versión, como el volcado de funciones.
   - **Cómo se repara lo que falte:** con un script que pone solo lo que falta, en su versión vigente; nunca repitiendo
     migraciones antiguas.
   - La 0054 empieza reponiendo el glosario completo, con las mismas filas.

## Alternativas descartadas
- **Corregir en la web (JavaScript):** las reglas viven en la base de datos (principio 3), y así la persona y la IA se
  corrigen con la misma función.
- **Exigir la subcuenta exacta:** cada empresa tiene sus subcuentas; lo que se aprende es la cuenta del PGC.
- **Ocultar la solución** (por RLS) para evitar trampas: es un laboratorio para aprender. La solución se ve cuando se
  quiere, y el progreso es de cada uno.
- **Un endpoint nuevo que evalúe la IA en el servidor:** obligaría a otra clave y otra cuota. Reutilizar `/api/tutor`
  con la sesión del usuario mide exactamente la IA que se usa, con sus mismos límites.
- **Repetir migraciones antiguas para reparar Supabase:** redefinirían funciones que migraciones posteriores ya
  cambiaron (`run_audit_checks`, `year_closing_preview`).

## Consecuencias
- Cada operación tiene su pantalla y su asiento modelo, y el Tutor ya no invita a hacer a mano lo que hace un módulo.
- La IA se mide con casos de solución conocida, por modelo y en el tiempo, con la misma regla que la persona.
- **Limitaciones conocidas:**
  - No se corrigen la fecha, el concepto ni los terceros: solo cuentas, lados e importes.
  - Un supuesto de dos asientos (variación de existencias) se corrige como uno solo.
  - Del plan quedan para más adelante los supuestos de margen, modelos y presupuesto (este, en la v0.42.0).
  - La evaluación de la IA guarda el último intento, sin estadística de varias repeticiones.
- **Pruebas:** 50 de 50 en la base de datos y 148 tests en la web.
  - **Fase 49:** catálogo, «dónde se registra», los 14 supuestos con nota 100 y los casos de corrección.
  - **Fase 50:** modelo de la IA, último intento, respuestas no válidas y glosario.
