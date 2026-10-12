# ADR 0028 · Bloque visual: indicadores, estados comparativos, gráficos con criterio y exportación

- **Fecha:** 2026-10-12
- **Versión:** v0.30.0
- **Estado:** aceptada

## Contexto

Tres revisiones externas del proyecto coincidieron: el dominio contable y la documentación son lo más fuerte (9 a
9,5 sobre 10), y lo **visual** es donde más margen hay (6,8 a 8,5). La decisión fue un bloque visual con una premisa:
**menos es más**. Solo los gráficos que dan información útil de un vistazo; nada de gráficos por hacer gráficos.

## Decisión

1. **Inicio con indicadores** (`erp.home_kpis`, migración 0031). Como el *Role Center* de BC o la *Overview Page* de
   SAP Fiori:
   - **5 cifras a la fecha de trabajo**: tesorería (57), resultado (7 − 6) frente al año anterior, IVA/IGIC del
     trimestre, pendiente de cobro (43) y de pago (40, 41). Cada cifra lleva a su informe.
   - **Un solo gráfico: tesorería a fin de mes.** Es la primera pregunta de quien lleva una empresa. Tiene el eje
     desde 0 (con área, cortarlo exageraría), 3 marcas, un único rótulo (el saldo final), un tooltip y "Ver como
     tabla".
   - **Reglas contables:**
     - sin regularización ni cierre (a 31/12 de un ejercicio cerrado no sale todo a 0);
     - el IVA del trimestre sin el asiento de liquidación (4750 / 4700);
     - la tesorería inicial es la del asiento de apertura.
   - **Según quién entra:**
     - empresa importada o demo → indicadores arriba;
     - empresa propia que empieza → solo la ruta guiada (los indicadores estarían a 0);
     - empresa propia con lo básico hecho → los indicadores aparecen debajo de la ruta;
     - empresa con la ruta completa → indicadores arriba y la ruta plegada.
   - **Rendimiento:** permiso comprobado una vez (`can_read`) y `jit = off`. El primer intento tardaba 5 s
     (permisos fila a fila y compilación JIT); el definitivo, 0,17 s con 120.000 apuntes.
2. **Balance y PyG comparativos** (migración 0032 y `src/compare.js`):
   - la columna del año anterior ya existía; se añade el **análisis horizontal**: variación en importe y en %, y el
     año anterior también al desplegar una partida;
   - **corregido:** a mitad de ejercicio, el Balance se comparaba con la misma fecha del año anterior. Ahora se compara
     con el **cierre anterior**, y la PyG con el **mismo periodo** (NIC 34);
   - la variación va **sin color**: que suba un gasto o un ingreso no es bueno o malo por sí solo.
3. **Gráficos con criterio:**
   - ✅ **cascada del EFE**: efectivo inicial → explotación → inversión → financiación → efectivo final. Resume más de
     30 líneas en 5 barras. Lleva el signo escrito además del color y la línea del cero (descubierto);
   - ✅ **evolución de cada ratio** en todos los ejercicios, con la zona de referencia sombreada. Solo al desplegar el
     ratio y con 3 años o más: muestra la tendencia, que la tabla no enseña;
   - ❌ **IVA por trimestre**: 4 cifras que ya están en el historial de liquidaciones. Un gráfico no añadiría nada.
   - **Dibujados a mano en SVG**, sin librería: pocas líneas, ningún peso extra y la CSP intacta.
4. **Exportar a Excel e imprimir** (`src/exportXlsx.js`, `ReportActions`) en Balance, PyG, EFE, sumas y saldos,
   mayor y diario:
   - importes como **números** con formato, fechas como **número de serie de Excel** (con objetos `Date`, SheetJS
     desplazaba algunos días por la zona horaria), cuentas como texto y autofiltro en la cabecera;
   - la librería xlsx solo se descarga al pulsar el botón;
   - para imprimir, hoja limpia en blanco y negro (también desde el modo oscuro), con empresa y filtros, y la cabecera
     de la tabla repetida en cada página.
5. **Pulido:**
   - mayor y sumas y saldos en **tarjetas** en el móvil (cada importe con su nombre y sin celdas vacías);
   - fechas dd/mm/aaaa sin desfase;
   - `tabular-nums` en todas las cifras;
   - filtros a todo el ancho en el móvil.

## Alternativas descartadas

- **Recharts u otra librería de gráficos:** con una línea, una cascada y una tendencia pequeña, dibujar en SVG es más
  simple y más ligero. Se reconsiderará si llegan gráficos más complejos.
- **Indicadores siempre visibles:** en una empresa que empieza estarían a cero y taparían la ruta guiada.
- **Un dashboard con muchos gráficos:** contradice "menos es más"; el detalle está a un clic en cada informe.
- **Colorear la variación** (verde sube, rojo baja): engaña con los gastos.

## Consecuencias

- El ERP se entiende de un vistazo al entrar, y los informes salen a Excel para trabajarlos o llevarlos a Power BI.
- Se corrigieron de paso:
  - un fallo contable (el Balance intermedio comparado con la misma fecha del año anterior);
  - un fallo de contraste (opacidad en los pasos pendientes del recorrido);
  - el desfase de un día en las fechas.
- Las ideas que quedan están en `docs/ideas-pendientes.md`.
