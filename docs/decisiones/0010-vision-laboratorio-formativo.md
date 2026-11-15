# ADR 0010 · Visión: laboratorio de práctica contable, complemento a la formación oficial

**Fecha:** 2026-10-06 · **Estado:** aceptada · matizada el 2026-10-15 por las ADR 0016 y 0021 (ver al final)

## Contexto
En FP ya se usan programas profesionales con licencias educativas;
en la universidad la contabilidad se enseña sobre todo con teoría, papel y Excel. Esas herramientas son para
trabajar, no para aprender: no explican el porqué, requieren licencia o instalación del centro y no corrigen ejercicios.

## Decisión
1. El Mini ERP es un laboratorio de práctica de contabilidad española que complementa la formación oficial;
   no compite con ningún programa comercial, ni es un software contable para empresas reales.
2. El autor es el primer estudiante del laboratorio.
3. Público: autodidactas, alumnos de FP o universidad que practican en casa, personas en reconversión profesional
   y candidatos que se preparan para trabajar en una gestoría.
4. Diferencia: explicar el porqué contable, acceso web sin instalación y, en el futuro, supuestos prácticos autocorregidos.
5. No se cobra por usar el ERP.

## Consecuencias
- No se aceptan contabilidades reales de empresas en el ERP.

## Actualización (2026-10-15): diarios de estudio
Una revisión externa señaló que esta consecuencia («no se aceptan contabilidades reales») contradice la ADR 0016
(importación de diarios). Las dos se refieren a cosas distintas, y queda así:

1. **Lo que sigue en pie:** el Mini ERP **no es el programa oficial** con el que una empresa lleva y presenta su
   contabilidad. No hay libros legalizados, ni presentación a la AEAT (SII, Verifactu, modelos), ni garantía. Para
   eso están los programas contables profesionales.
2. **Lo que sí se permite:** **estudiar** diarios con las herramientas del laboratorio (ADR 0016):
   importar el diario de otro ERP o registrar operaciones de práctica para encontrar fallos.
   - Siempre en una empresa **privada** de quien la importa.
   - Esos datos **nunca entran en el repositorio**; las pruebas usan datos inventados.
   - Un diario de estudio de terceros **nunca** es demo (actualización v0.60.5, al final). Otro diario importado solo
     se publica como demo si su **titular** lo decide, **anonimizado** y con su **mención** (ADR 0021 y 0027).

*Revisión ética (v0.60.1, 2026-11-08): se quitan los nombres de programas comerciales (ADR 0063). La decisión y sus consecuencias no cambian.*

*Política de uso (v0.60.3, 2026-11-09): el Mini ERP es para practicar y aprender. No invita a usarlo con datos reales de
empresas y su autor no se responsabiliza si alguien lo hace. La importación de diarios sigue existiendo para practicar.*

## Actualización (v0.60.5, 2026-11-14): los diarios de estudio de terceros
Decisión de Diosvely. **Los diarios de estudio de terceros** son diarios ficticios que compartieron profesionales y que
Diosvely importa en empresas privadas **solo para estudiarlos**. No son suyos y no se pueden usar:
- en el repositorio **no se nombran** («Empresa 1», «Empresa 2»…), **no se dan sus cifras** (número de asientos o
  apuntes, importes, porcentajes) y **no se llaman «contabilidad real»**;
- **nunca son demo**;
- lo que se aprende de ellos se cuenta sin sus cifras («una empresa importada grande»).
Se quitaron de la bitácora, el CHANGELOG, las decisiones y los comentarios de las migraciones (los comentarios no cambian
nada en la base de datos). El historial de git conserva los textos antiguos.

