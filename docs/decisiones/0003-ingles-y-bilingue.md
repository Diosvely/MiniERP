# ADR 0003 · Base de datos en inglés e interfaz bilingüe

**Fecha:** 2026-09-30 · **Estado:** aceptada · **Sustituye:** los nombres en español de la v0.1.0

## Contexto
El proyecto sirve también para aprender inglés. Business Central, SAP y casi todo el software
profesional usan nombres en inglés (`G/L Account`, `Posting Date`, `Debit`, `Credit`…).

## Decisión
1. **Todo lo técnico en inglés**: schema `erp`, tablas, columnas, funciones, vistas, valores de estado
   y mensajes de error, siguiendo el vocabulario de BC y SAP.
2. **Comentarios del SQL en español**, para entender el porqué de cada pieza.
3. **Datos bilingües**: el plan de cuentas guarda el nombre oficial del PGC (`name`) y su traducción
   (`name_en`); los tipos de impuesto, `description` y `description_en`.
4. **Interfaz con selector de idioma** (es / en), guardado por usuario en `erp.user_settings`.
5. **Reset en vez de migración de renombrado**: se borra el schema `conta` y se ejecutan las nuevas
   migraciones desde cero.

## Por qué el reset es aceptable aquí
La regla del proyecto es "nunca editar una migración ya ejecutada". Se hace una excepción porque:
- `conta` no tenía datos reales (proyecto recién creado).
- Renombrar 10 tablas, sus columnas, funciones, triggers, vistas y políticas en una migración `0007`
  sería más largo y propenso a errores que empezar limpio.
- La versión anterior queda en el historial de Git (etiqueta `v0.1.0`).

A partir de la v0.2.0 la regla vuelve a aplicarse sin excepciones.

## Consecuencias
- En Supabase: ejecutar `database/reset/0000_drop_conta.sql`, luego las migraciones 0001–0006,
  y en *Exposed schemas* cambiar `conta` por `erp`.
- Los mensajes de error de la base de datos salen en inglés. Más adelante la web podrá traducirlos.
- Ver `docs/glosario.md` para el vocabulario español ↔ inglés ↔ BC ↔ SAP.
