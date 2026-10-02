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
   
## 2026-09-30 · Base de datos en inglés (schema erp)
   - Nombres técnicos en inglés al estilo BC / SAP, comentarios en español (ADR 0003).
   - Reset en Supabase: borrado `conta`, ejecutadas 0001–0006 de `erp`, expuesto `erp` en la Data API.
   - Comprobado: 11 tablas con RLS, 352 cuentas con nombre en inglés, 12 tipos IVA/IGIC.
   - Aprendido: `git switch -c` crea una rama; `git switch` solo cambia a una que ya existe.
   
## 2026-09-30 · Primera pantalla web (bilingüe)
- Frontend React + Vite en /frontend, conectado a Supabase (schema erp).
- Login con correo y contraseña, listado y alta de empresas (copia PGC + ejercicio automáticos).
- Interfaz en español / inglés con diccionarios en src/i18n; idioma guardado por usuario en erp.user_settings.
- Probado: registro, alta de empresa (352 cuentas, 12 periodos) y el idioma se mantiene al volver a entrar.
- Aprendido: componentes y Context de React, variables VITE_ en .env.local, merge entre ramas.

## 2026-09-30 · Web publicada en Cloudflare Pages
- Producción: https://minierp-6ty.pages.dev (se publica sola con cada push a main).
- Root directory = frontend; variables VITE_SUPABASE_URL / VITE_SUPABASE_KEY en Cloudflare.
- Supabase Auth: Site URL y Redirect URLs configuradas (producción, ramas y localhost).
- Probado en el móvil: mismo usuario, mismo idioma y mismas empresas que en el ordenador.


## 2026-09-30 · Primeros asientos desde la web
- Pantalla de empresa con pestañas: Nuevo asiento · Libro diario · Cuentas.
- Alta de subcuentas validada por la base de datos (longitud y cuenta PGC madre).
- Formulario de asiento con cuadre en vivo, cálculo en céntimos, botón "=" y contabilización con post_entry().
- Libro diario desde la vista v_general_journal, bilingüe y con formato de importes por idioma.
- Probado: constitución (572/100) y factura con IGIC (430/705/477).
- Aprendido: organizar en carpeta components/, props y comunicación padre-hijo en React.
  Error típico: crear un archivo fuera de src (Vite no lo encuentra).
  
## 2026-10-01 · Empresas demo y límites por usuario (v0.4.0)
- Migración 0007: perfiles de aplicación (owner sin límite / member con 1 empresa) y empresas demo.
- Una empresa demo la lee cualquier usuario registrado; solo sus miembros la editan (RLS).
- El límite de empresas y la publicación como demo se controlan con un trigger en la base de datos.
- Web: listas "Mis empresas" / "Empresas de demostración", etiqueta DEMO, modo solo lectura,
  botón "Publicar como demo" (solo owner) y aviso de límite.
- Probado con un segundo usuario en ventana de incógnito.
- Aprendido: perfiles de aplicación frente a roles por empresa; redefinir una función (can_read)
  cambia la seguridad de todas las tablas que la usan

## 2026-10-02 · Importación de subcuentas desde CSV (v0.5.0)
- Migración 0008: función import_posting_accounts(empresa, filas, dry_run).
  Vista previa (dry_run) → valida cada fila sin guardar; importación real → todo o nada.
  Estados: nueva / actualiza (renombra) / error (longitud, sin cuenta PGC, duplicada, sin nombre, letras).
- Web: csv.js reutilizable (BOM de Excel, ; o , como separador, UTF-8 o Windows-1252) y pantalla
  de importación con plantilla descargable.
- Probado con el plan de Agrícola del Sur: 62 subcuentas importadas, errores detectados y reimportación.
- Referencia ERP: crear o actualizar como los Configuration Packages de Business Central;
  validación previa y todo o nada como el Migration Cockpit de SAP.