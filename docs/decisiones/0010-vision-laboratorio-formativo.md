# ADR 0010 · Visión: laboratorio de práctica contable, complemento a la formación oficial

**Fecha:** 2026-10-06 · **Estado:** aceptada · matizada el 2026-10-15 por las ADR 0016 y 0021 (ver al final)

## Contexto
En FP ya se usan programas reales con licencias educativas (ContaSol de Software DELSOL, Sage 50 con Sage Educa);
en la universidad la contabilidad se enseña sobre todo con teoría, papel y Excel. Esas herramientas son para
trabajar, no para aprender: no explican el porqué, requieren licencia o instalación del centro y no corrigen ejercicios.

## Decisión
1. El Mini ERP es un laboratorio de práctica de contabilidad española que complementa la formación oficial;
   no compite con ContaSol, Sage ni A3, ni es un software contable para empresas reales.
2. El autor es el primer estudiante del laboratorio.
3. Público: autodidactas, alumnos de FP o universidad que practican en casa, personas en reconversión profesional
   y candidatos que se preparan para trabajar en una gestoría.
4. Diferencia: explicar el porqué contable, acceso web sin instalación y, en el futuro, supuestos prácticos autocorregidos.
5. No se cobra por usar el ERP.

## Consecuencias
- No se aceptan contabilidades reales de empresas en el ERP.

## Actualización (2026-10-15): contabilidades reales
Una revisión externa señaló que esta consecuencia («no se aceptan contabilidades reales») contradice la ADR 0016
(importación de diarios reales). Las dos se refieren a cosas distintas, y queda así:

1. **Lo que sigue en pie:** el Mini ERP **no es el programa oficial** con el que una empresa lleva y presenta su
   contabilidad. No hay libros legalizados, ni presentación a la AEAT (SII, Verifactu, modelos), ni garantía. Para
   eso están ContaSol, Sage o A3.
2. **Lo que sí se permite:** **estudiar** contabilidades reales con las herramientas del laboratorio (ADR 0016):
   importar el diario de otro ERP o registrar operaciones reales para practicar y encontrar fallos.
   - Siempre en una empresa **privada** de quien la importa.
   - Los datos reales **nunca entran en el repositorio**; las pruebas usan datos inventados.
   - Solo se publica como demo si su **titular** lo decide, **anonimizada** y con su **mención** (ADR 0021 y 0027).
