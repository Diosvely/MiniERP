# ADR 0022 · Navegación con rutas, pantalla de Inicio y modo Básico / Auditor

- **Fecha:** 2026-10-10
- **Versión:** v0.25.0
- **Estado:** aceptada

## Contexto

Un análisis de experiencia de usuario del repositorio (plan de mejoras UX, bloques A, B y D) detectó que el ERP
era potente pero difícil para quien empieza:
- **Sin rutas:**
  - el botón "atrás" del navegador sacaba de la app;
  - recargar perdía la pantalla abierta;
  - no se podía compartir el enlace al balance de una demo.
- **Sin punto de partida:** al abrir una empresa se caía en una pantalla de trabajo, sin saber qué hacer primero.
- **Menú de 17 entradas con términos técnicos** ("Sumas y saldos · Mayor", "Terceros", "Liquidación"), tanto para
  el principiante como para el auditor.
- **Pantallas en blanco** mientras cargaban, y estados vacíos sin la siguiente acción ("no hay impuestos" sin
  botón para configurarlos).
- **El atajo "−" del asiento** borraba la línea también desde los importes, sin poder deshacer.

## Decisión

1. **Rutas con almohadilla** (`#/empresa/<id>/<pantalla>`), con un hook propio de unas 40 líneas
   (`src/router.js`) y un componente `<Link>`. **Sin `react-router`:**
   - funciona en Cloudflare Pages sin configurar el servidor;
   - `?demo` sigue funcionando porque va antes de la almohadilla;
   - los enlaces de Supabase (`#access_token=…`) no empiezan por `#/`, así que se ignoran.
2. **Pantalla de Inicio** como primera pantalla de cada empresa, al estilo del *Role Center* de Business Central:
   - **Ruta guiada de 6 pasos** (impuestos → tercero → factura → diario → liquidación → balance):
     - cada paso se marca solo, con consultas ligeras (`select id … limit 1`) a vistas que ya existen;
     - **no hay funciones nuevas en la base de datos**.
   - **Recorrido del auditor** para las empresas **importadas** y las demos: diario → balance → PyG → EFE →
     ratios y Analista IA → revisión de saldos.
   - Accesos rápidos y los 5 últimos asientos.
3. **Modo Básico / Auditor**, como los *perfiles* de Business Central:
   - Son **dos menús sobre las mismas pantallas**. El modo **no cambia permisos**: los permisos los sigue
     decidiendo la base de datos.
   - **Básico** (por defecto): 8 entradas, en lenguaje sencillo y con el término técnico debajo.
   - **Auditor:** las 17 entradas, agrupadas por áreas.
   - Se guarda en `localStorage` (sin migración).
   - Una pantalla avanzada abierta en modo Básico se muestra igualmente, con el aviso "Esta pantalla es del modo
     Auditor".
   - "Configurar impuestos" es del modo Básico pero no sale en su menú: se llega desde el paso 1 del Inicio, como
     la *configuración asistida* de BC.
4. **Aviso de carga global:**
   - el cliente de Supabase pasa cada petición por un contador (`src/activity.js`, opción `global.fetch` de
     `createClient`);
   - si alguna tarda más de 0,3 s, aparece "Cargando…" arriba;
   - una sola pieza cubre todas las pantallas, en vez de un estado de carga en cada una.
5. **Estados vacíos con la siguiente acción** (`Empty.jsx`): icono, frase y botón que lleva a la pantalla donde se
   resuelve. Tras contabilizar, enlace "Ver en el diario".
6. **El "−" solo borra con el campo de cuenta vacío**, y aparece "Línea borrada · Deshacer" durante 5 segundos.

## Alternativas descartadas

- **`react-router`:** una dependencia más para 3 tipos de ruta, y con rutas sin almohadilla habría que configurar
  las redirecciones en Cloudflare.
- **Guardar el modo en `user_settings`:** pedía una migración. El modo es una preferencia de pantalla y puede
  vivir en el navegador. Si se quiere sincronizar entre dispositivos, se añadirá la columna más adelante.
- **Un estado `loading` en cada pantalla:** son 20 componentes que tocar y mantener; el contador global consigue lo
  mismo con tres ficheros.
- **Ocultar las pantallas avanzadas en modo Básico:** un enlace compartido daría error. Mostrarlas con un aviso
  respeta el enlace y enseña que existe el modo Auditor.
- **Funciones SQL para la ruta guiada:** innecesarias. Las vistas existentes ya dicen si hay datos, y así el CI no
  necesita otra migración.

## Consecuencias

- Cada pantalla tiene **su dirección**: atrás, recargar y compartir funcionan, y la demo se puede enlazar al
  balance concreto.
- Quien empieza tiene un camino claro y quien audita tiene el suyo, sobre el mismo ERP.
- La **integración continua** (GitHub Actions, paso 132) comprueba en cada PR las 21 pruebas SQL, el lint, la build
  y la auditoría de dependencias. En su primera ejecución cazó dos fallos reales: claves duplicadas en el i18n y un
  carácter invisible en `importers.js`.
- **Pendiente** (v0.26.0 y v0.27.0):
  - errores de la base de datos en lenguaje claro;
  - pantalla de entrada;
  - plantillas de asientos;
  - glosario;
  - accesibilidad y colores;
  - refactorizar la carga de datos de cada pantalla (regla `react-hooks/set-state-in-effect`, que ahora es un
    aviso).