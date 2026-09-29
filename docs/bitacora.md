# Bitácora del proyecto

Diario del proceso: qué se hizo, qué se aprendió y qué queda pendiente. Una entrada por sesión de trabajo.

---

## 2026-09-29 · Arranque del repositorio

- Se crea el repositorio Git desde el primer minuto, con la estructura de carpetas documentada en el README.
- Decisión de infraestructura: base de datos en un **schema `conta` dentro de un proyecto Supabase existente**
  (ver `docs/decisiones/0001-infraestructura.md`).

## 2026-09-29 · v0.1.0 · Base de datos contable

**Qué se hizo**
- 6 migraciones SQL en `database/migrations/` (núcleo, PGC, terceros/impuestos, asientos, informes, seguridad).
- Pruebas automáticas (`database/tests/test_fase1.sql`) ejecutadas en PostgreSQL 16 local: 31 comprobaciones OK.
- Datos de ejemplo con dos empresas para comparar IGIC (Canarias, servicios) e IVA (Península, retail).

**Lo que se aprende en esta fase**
- Plan de cuentas en dos niveles (plantilla PGC + cuentas de la empresa), como SAP (SKA1/SKB1) y BC.
- Cuentas de título (no admiten apuntes) frente a subcuentas (donde se apunta).
- Por qué un asiento contabilizado no se borra: se anula con un contraasiento y ambos quedan en el diario.
- El PGC solo nombra el IVA en 472/477: el IGIC usa esas cuentas con subcuentas propias (4721…, 4771…).
- Una factura de profesional en Canarias: gasto + IGIC soportado − retención IRPF (4751) = total a pagar.

**Decisiones**: ADR 0001 (infraestructura) y ADR 0002 (asientos) en `docs/decisiones/`.

**Siguiente paso**: ejecutar las migraciones en Supabase y empezar el frontend (v0.2.0).


## 2026-09-29 · Instalación en Supabase
   - Ejecutadas las migraciones 0001–0006 en Supabase.
   - Schema `conta` expuesto en la Data API.
   - Repositorio gestionado desde VS Code y publicado en GitHub.