# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado semántico.

## [Sin publicar]
### Cambiado
- Base de datos renombrada al inglés al estilo Business Central / SAP: schema `erp`, tablas, columnas,
  funciones, vistas, estados y mensajes de error (ADR 0003).
### Añadido
- Nombres en inglés (`name_en`) para las 352 cuentas del PGC y descripciones de los tipos IVA / IGIC.
- Tabla `user_settings` para el idioma de la interfaz (es / en) por usuario.
- `docs/glosario.md` y script `database/reset/0000_drop_conta.sql`.

## [0.1.0] - 2026-09-29
### Añadido
- Schema `conta` en PostgreSQL/Supabase con 6 migraciones.
- Empresas multisector (retail, industria, e-commerce, servicios) y multiterritorio (Península / Canarias).
- Plan General Contable 2007, grupos 1 a 7 (352 cuentas), copiado automáticamente a cada empresa.
- Subcuentas con longitud fija y enlace automático a su cuenta PGC.
- Terceros y catálogo de tipos IVA / IGIC 2026 con fechas de vigencia.
- Asientos: borrador → contabilizado, validación Debe = Haber, numeración correlativa, periodos cerrables,
  anulación por contraasiento.
- Informes: libro diario, libro mayor, sumas y saldos por niveles, libro registro de IVA/IGIC.
- Multiusuario con roles (admin, contable, lectura) mediante Row Level Security.
- 31 pruebas automáticas y datos de ejemplo (2 empresas).
