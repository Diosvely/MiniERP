# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado semántico.

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
