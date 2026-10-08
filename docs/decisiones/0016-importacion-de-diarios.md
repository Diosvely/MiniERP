# ADR 0016 · Importación de diarios a una plantilla común y en una empresa nueva

**Fecha:** 2026-10-08 · **Estado:** aceptada

## Contexto
Queremos estudiar contabilidades reales exportadas de otros ERP (Sage, Dynamics BC) con las mismas herramientas
del laboratorio, sin Power BI de por medio, y con varios ejercicios por fichero.

## Decisión
1. Una PLANTILLA del laboratorio (fecha, asiento, tipo, cuenta, nombre, debe, haber, concepto, documento) y un
   convertidor por ERP en la web. Base de datos y plantilla no dependen del ERP de origen.
2. Cada importación crea una empresa NUEVA (los dígitos de sus subcuentas salen del fichero). No se mezclan datos.
3. Vista previa con controles de auditor antes de importar; los errores graves bloquean, los avisos se documentan.
4. Importación por meses y cierre por ejercicios, en llamadas cortas (límite de tiempo de Supabase), con funciones
   SECURITY DEFINER que comprueban primero el permiso de administrador.
5. Los asientos históricos no se bloquean por saldos inversos: se señalan en el informe de saldos anómalos.
6. Los datos reales se quedan en empresas privadas y nunca entran en el repositorio (las pruebas usan datos inventados).

## Consecuencias
- Balance, PyG, sumas y saldos, mayor, anómalos y cierre funcionan igual con datos importados.
- No hay libro registro ni 303 en las empresas importadas (los diarios no traen facturas).