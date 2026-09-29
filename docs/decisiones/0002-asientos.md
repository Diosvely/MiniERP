# ADR 0002 · Asientos: un solo par de tablas con estado, e inmutabilidad en la base de datos

**Fecha:** 2026-09-29 · **Estado:** aceptada

## Contexto
Business Central separa el diario (*Gen. Journal Line*, editable) de los movimientos contabilizados
(*G/L Entry*, inmutables). SAP guarda cabecera (BKPF) y posiciones (BSEG) y distingue documentos
aparcados de contabilizados.

## Decisión
- Un único par `asientos` (cabecera) + `apuntes` (líneas), con `estado`: `borrador` → `contabilizado`.
- Las reglas contables las impone **PostgreSQL** (triggers y funciones), no la web:
  - Un asiento contabilizado no se edita ni se borra; se corrige con `conta.anular()`, que genera un
    **contraasiento** (Debe ↔ Haber) y conserva el original, como exige la práctica contable.
  - `conta.contabilizar()` exige Debe = Haber, al menos 2 apuntes y periodo abierto, y asigna el número
    correlativo por ejercicio (sin huecos, con bloqueo para usuarios simultáneos).
  - Solo se apunta en subcuentas (`tipo = 'auxiliar'`), nunca en cuentas de 3 dígitos del PGC.

## Por qué
- Es el mismo concepto que BC/SAP con la mitad de tablas: más fácil de estudiar.
- Si mañana se cambia el frontend (web, app, Power BI escribiendo…), las reglas siguen valiendo.

## Consecuencias
- Borrar una empresa con asientos contabilizados solo es posible con `conta.eliminar_empresa()` (solo admin),
  pensado para empresas de práctica.
- Si en el futuro se necesita un "diario" tipo BC con importación masiva, se puede añadir una tabla de
  borradores sin tocar lo contabilizado.
