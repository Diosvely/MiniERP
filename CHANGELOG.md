# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado semántico.

## [0.13.1] · 2026-10-06
### Añadido
- Guía de Git del proyecto (`docs/guia-git.md`).
### Cambiado
- Selector de idioma con banderas.
- Cabeceras de área del menú diferenciadas de las opciones.
- README actualizado.
### Eliminado
- Carpeta `Codigo GIT` (sustituida por la guía en `docs`).

## [0.13.0] · 2026-10-06
### Añadido
- Acceso como invitado (sin registro) a las empresas demo, solo lectura.
- Enlace directo para compartir la demo.
### Corregido
- La lista de empresas no muestra separadores vacíos cuando falta el NIF.

## [0.12.0] · 2026-10-05
### Añadido
- Anulación de asientos con contraasiento, fecha y motivo.
- Libro diario con rango de fechas, búsqueda y totales del filtro.
- Etiquetas de origen del asiento (factura, liquidación) y de anulación.

## [0.11.0] · 2026-10-05
### Cambiado
- Menú de la empresa agrupado por áreas (barra lateral en ordenador, menú desplegable en móvil).
- La aplicación recuerda la última pantalla abierta de cada empresa.

## [0.10.0] · 2026-10-05
### Añadido
- Informes: sumas y saldos por nivel y fecha de corte, libro mayor con saldo acumulado y drill-down.
- Informe de saldos anómalos con explicación y cuenta de reclasificación.
- Bloqueo de saldo inverso por subcuenta (caja bloqueada por defecto).

## [0.9.0] · 2026-10-05
### Añadido
- Liquidación trimestral de IVA (modelo 303) e IGIC (modelo 420) con borrador por tipo.
- Compensación automática de cuotas de periodos anteriores y devolución en el 4T.
- Cuadre libro registro ↔ contabilidad antes de liquidar.
- Bloqueo del trimestre liquidado y deshacer la última liquidación.

## [0.8.0] · 2026-10-05
### Añadido
- Registro de facturas recibidas y emitidas, normales y rectificativas, con asiento automático.
- Regla del lado: devoluciones, rappels y descuentos por pronto pago reducen base y cuota.
- Vista previa del asiento antes de registrar.
- Libro registro de facturas emitidas y recibidas.
- Control de facturas duplicadas y numeración correlativa por serie.

## [Sin publicar]
### Cambiado
- Base de datos renombrada al inglés al estilo Business Central / SAP: schema `erp`, tablas, columnas,
  funciones, vistas, estados y mensajes de error (ADR 0003).
### Añadido
- Nombres en inglés (`name_en`) para las 352 cuentas del PGC y descripciones de los tipos IVA / IGIC.
- Tabla `user_settings` para el idioma de la interfaz (es / en) por usuario.
- `docs/glosario.md` y script `database/reset/0000_drop_conta.sql`.

## [0.7.0] · 2026-10-04
### Añadido
- Configuración de impuestos: subcuentas 472/477 por tipo de IVA/IGIC y 4750/4700 de liquidación.
- Asistente para configurar IGIC o IVA en un clic.
- El apunte en una cuenta de impuesto toma su tipo y aparece en el libro registro.
### Corregido
- Comprobación de permisos para usuarios que no son miembros de la empresa.

|
## [0.6.0] · 2026-10-03
### Añadido
- Terceros: clientes, proveedores, acreedores y deudores con su subcuenta (430/400/410/440).
- Validación de NIF/NIE/CIF españoles y control de duplicados.
- Saldo de cada tercero con su naturaleza (deudor/acreedor).


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
