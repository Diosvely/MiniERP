# ADR 0024 · Glosario en la app, accesibilidad medida y colores con variables

- **Fecha:** 2026-10-10
- **Versión:** v0.27.0
- **Estado:** aceptada

## Contexto

- El glosario (`docs/glosario.md`) solo existía en el repositorio: quien usaba la app no lo veía.
- La accesibilidad no se medía.
- Los colores de estado estaban escritos a mano (32 apariciones), sin versión oscura: el verde de "éxito" y el texto
  blanco sobre el azul claro del modo oscuro no llegaban al contraste mínimo.
- Los iconos eran emojis, que cambian de aspecto según el sistema.

## Decisión

1. **Glosario como datos** (`src/glossary.js`):
   - 36 términos en español e inglés, con definición corta, ejemplo opcional y su nombre en **Business Central y
     SAP**;
   - un mismo origen alimenta el globo ⓘ y la página `#/glosario` con buscador.
2. **`<Term id>`** junto a la **ruta de cada pantalla** (un solo cambio en `CompanyView` cubre 15 pantallas) y en el
   Debe / Haber del asiento:
   - se abre al pasar el ratón, al tocar o con el teclado, y se cierra con Escape;
   - en el móvil se recoloca para no salirse de la pantalla.
3. **Accesibilidad medida, no supuesta:**
   - axe-core (el motor de Lighthouse) sobre seis pantallas, en modo claro y oscuro: de 20 y 31 fallos a **0**;
   - `lang` de la página que sigue al idioma, título, etiquetas visibles, nombres accesibles y foco visible común.
4. **Colores de estado como variables con versión oscura:**
   - `--exito`, `--alerta`, `--alerta-fondo`, `--error` y `--sobre-color` (texto sobre color: blanco en claro,
     oscuro en oscuro);
   - aplicado con un script que solo cambia los colores escritos a mano.
5. **Iconos `lucide-react`** (un tamaño y grosor comunes, `aria-hidden`) en las piezas nuevas. Las pantallas antiguas
   conservan sus emojis hasta que se toquen.

## Alternativas descartadas

- **Leer `docs/glosario.md` en tiempo de ejecución:** obligaría a analizar Markdown en el navegador, y las tablas del
  documento son de vocabulario, no de definiciones. Mejor una versión corta como datos.
- **Una librería de tooltips** (Floating UI, Tippy): para un único caso basta con medir el globo y desplazarlo.
- **Un tema oscuro con otra paleta completa:** bastaba con que los colores de estado y el texto sobre color tuvieran
  su versión oscura.
- **Cambiar todos los emojis de golpe:** demasiados ficheros a la vez. Se cambian en las piezas nuevas y al tocar
  cada pantalla.

## Consecuencias

- Cada pantalla enseña su concepto en un clic, con el vocabulario de los ERP reales.
- La accesibilidad tiene una cifra (0 fallos con axe-core) que se puede volver a medir tras cada cambio.
- El README muestra capturas reales de la app (`docs/capturas/`).
- **Pendiente:**
  - llevar los iconos a las pantallas antiguas;
  - añadir más términos al glosario (amortización por métodos, provisiones, periodificaciones) cuando llegue el    módulo de Inmovilizado.