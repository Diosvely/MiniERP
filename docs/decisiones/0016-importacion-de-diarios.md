# ADR 0016 · Importación de diarios a una plantilla común y en una empresa nueva

**Fecha:** 2026-10-08 · **Estado:** aceptada

## Contexto
Queremos estudiar diarios exportados de otros programas (un diario en Excel, Dynamics BC) con las mismas herramientas
del laboratorio, sin Power BI de por medio, y con varios ejercicios por fichero.

## Decisión
1. Una PLANTILLA del laboratorio (fecha, asiento, tipo, cuenta, nombre, debe, haber, concepto, documento) y un
   convertidor por ERP en la web. Base de datos y plantilla no dependen del ERP de origen.
2. Cada importación crea una empresa NUEVA (los dígitos de sus subcuentas salen del fichero). No se mezclan datos.
3. Vista previa con controles de auditor antes de importar; los errores graves bloquean, los avisos se documentan.
4. Importación por meses y cierre por ejercicios, en llamadas cortas (límite de tiempo de Supabase), con funciones
   SECURITY DEFINER que comprueban primero el permiso de administrador.
5. Los asientos históricos no se bloquean por saldos inversos: se señalan en el informe de saldos anómalos.
6. Los diarios de estudio se quedan en empresas privadas y nunca entran en el repositorio (las pruebas usan datos inventados).

## Consecuencias
- Balance, PyG, sumas y saldos, mayor, anómalos y cierre funcionan igual con datos importados.
- No hay libro registro ni 303 en las empresas importadas (los diarios no traen facturas).

## Relación con la ADR 0010 (2026-10-15)
La ADR 0010 dice que el ERP no es un software contable para empresas reales: no sustituye al programa oficial.
Importar un diario **para estudiarlo** es compatible con eso, con las condiciones del punto 6 y de la ADR 0021.
Detalle en la actualización al final de la ADR 0010.

*Política de uso (v0.60.5, 2026-11-14): el Mini ERP es para practicar y aprender. No invita a usarlo con datos reales
de una empresa y su autor no se hace responsable si alguien lo hace. Los diarios que se importan para estudiar son de
práctica; los diarios de estudio de terceros no se nombran ni se dan sus cifras en el repositorio.*

*Revisión ética (v0.60.1, 2026-11-08): se quitan los nombres de programas comerciales (ADR 0063). La decisión y sus consecuencias no cambian.*
