# ADR 0065 · Partidas específicas del Balance (norma 6.ª), cuentas protegidas y orden de informe

- **Fecha:** 2026-11-18
- **Versión:** v0.60.10
- **Estado:** aceptada (Diosvely, 18-11-2026; AF-35 de auditoría fiscal, SEG-26 y SEG-28 de seguridad, M-03 y M-04).

## Contexto

Al preparar el mapeo de cuentas de la empresa de práctica para Power BI, se comparó el del Mini ERP (modelo normal)
con dos mapeos de referencia hechos por profesionales, cuenta por cuenta. Salieron tres cosas:

- Los modelos normal y abreviado del Balance del Mini ERP tienen los mismos epígrafes que el PGC (RD 1514/2007,
  tercera parte, texto consolidado a 31-03-2025). Pero la **norma 6.ª de elaboración de las cuentas anuales** manda
  **crear** partidas en algunos casos, y el ERP no las tenía:
  - 6.ª.14: «Diferencia de conversión», dentro de A-2, cuando la moneda funcional no es el euro (cuenta 135);
  - 6.ª.17: «Deuda con características especiales», a largo y a corto plazo, cuando la empresa ha emitido
    instrumentos financieros que se reconocen como pasivos financieros (15; 502 y 507). El manual del modelo 200 de la
    AEAT pone esas mismas cuentas en esas partidas.
- La 1341 (cobertura de una inversión neta en un negocio en el extranjero) iba a «III. Otros», aunque es una
  cobertura del subgrupo 134, como la 1340.
- Seguridad (SEG-28): por la API, quien escribe en su empresa podía cambiar la empresa de una cuenta, o el número o el
  tipo de una cuenta con apuntes.

## Decisión

1. **Partidas específicas, en el normal y en el abreviado:** «Diferencia de conversión» en A-2 del normal (la 135 y,
   antes del cierre, la 82 y la 92, que al cerrar van a la 135); «Deuda con características especiales a largo plazo»
   (la 15) y «… a corto plazo» (la 502 y la 507, cuando son acreedoras). Llevan el nombre que da la norma, sin número
   romano, porque la norma no lo fija. En el abreviado, A-2 no se divide. PYMES no cambia.
2. **La 1341, a «II. Operaciones de cobertura»** (todo el subgrupo 134).
3. **No se crean** «Deudores comerciales no corrientes» ni «Acreedores comerciales no corrientes» (6.ª.8 y 6.ª.16):
   dependen del vencimiento de cada crédito o deuda, no de la cuenta.
4. **Cuentas protegidas (SEG-28):** la empresa de una cuenta no cambia nunca; su número y su tipo, solo si no tiene
   apuntes. El nombre y los bloqueos se siguen cambiando. Un trigger en `erp.gl_accounts`, como el de los ejercicios.
5. **Diagnóstico (SEG-26):** avisa de cualquier rol que salta el RLS (superusuario o `bypassrls`) y entra en `erp`,
   salvo los del sistema.
6. **Power BI (M-03 y M-04):** `bi.dim_linea` tiene una columna nueva, `orden_informe`, con los totales de nivel 1 al
   final de sus líneas; la guía `docs/powerbi/GUIA.md` recoge las siete correcciones del ensayo en Power BI Desktop.

## Consecuencias

- Ningún total cambia: solo la partida en la que se ve cada saldo. La empresa de práctica del vídeo 03 no usa esas
  cuentas: sus cifras no cambian.
- Pruebas: fase 82 (las partidas nuevas en los dos modelos y el orden de A-2), fase 60 (la diferencia de conversión
  después del cierre), fase 80 (SEG-28), fase 67 (`orden_informe`) y la prueba del diagnóstico (SEG-26).

## Alternativas descartadas

- **Copiar la estructura del modelo 200 de la AEAT** (cinco epígrafes en A-2 y las partidas por vencimiento): el modelo
  de la AEAT es una declaración fiscal con casillas de más; las cuentas anuales siguen el PGC.
- **Numerar las partidas nuevas** (IV, VI, VII): la norma no les da número y numerarlas obligaría a renumerar las demás.

## Cómo explicarlo

- **El modelo es un mínimo, no un techo:** el PGC da los epígrafes de siempre y la norma 6.ª dice «si te pasa esto,
  crea esta partida». Un Balance bien hecho las tiene cuando hacen falta, y no enseña las que no.
- **Una deuda que parece capital:** unas acciones que la empresa tiene que recomprar son, para el PGC, una deuda. Van
  aparte, con su nombre, para que nadie las confunda con un préstamo ni con los fondos propios.
- **Una cuenta con historia no se cambia:** si la 62300001 ya tiene apuntes, cambiarle el número es mover esos apuntes a
  otra cuenta sin asiento. Se crea una cuenta nueva y se traspasa con un asiento.
