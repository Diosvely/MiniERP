# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado semántico.

## [0.23.0] - 2026-10-09
### Añadido
- **Tutor de asientos con IA** (Contabilidad › Asiento):
  - describes una operación y la IA propone el asiento según el PGC, con la NRV aplicable, los supuestos, el porqué
    de cada línea y una pregunta de repaso;
  - el ERP la comprueba (subcuentas, impuesto vigente calculado por el ERP, cuadre y reglas de criterio) y la carga
    en el formulario sin contabilizar.
- Migración `0025`: `valuation_rules` (las 23 NRV), `entry_tutor_context`, `validate_proposed_entry` y
  `next_subaccount_no`.
- Migración `0026`: reglas de criterio contable y cuentas 2800–2806 y 2811–2819 del PGC.
- Pages Function `functions/api/tutor.js`: modelo `gpt-oss-120b` con Mistral Small de respaldo y segunda vuelta
  con los avisos del ERP.
- Prueba `test_fase20_entry_tutor.sql`.
### Cambiado
- El PGC de la plantilla pasa de 362 a 378 cuentas.
- `/api/ai` y `/api/tutor` avisan de forma clara cuando falta ejecutar una migración en Supabase.

## [0.22.0] - 2026-10-08
### Añadido
- **Analista IA** con un modelo open source de Cloudflare Workers AI (gratuito y sin clave de API):
  - comenta como un auditor los estados financieros, el EFE y los ratios del ejercicio, con resumen, puntos
    fuertes, alertas, preguntas del auditor y una idea para aprender;
  - botón en Informes › Ratios y en Flujos de efectivo;
  - solo para el propietario de la aplicación.
- Migración `0024`: `can_use_ai()` y `ai_context()`. La IA solo recibe cifras agregadas: nunca nombres,
  terceros ni conceptos.
- Pages Function `functions/api/ai.js` (POST para el análisis, GET para comprobar la configuración).
- Prueba `test_fase19_ai_context.sql`.
### Corregido
- La **calidad del resultado** (con pérdidas) y el **ROE** (con patrimonio neto negativo) ya no muestran un
  valor positivo engañoso: quedan sin calcular.

## [0.21.0] - 2026-10-08
### Añadido
- **Ratios financieros** (migración `0023`): 21 ratios de liquidez, solvencia y endeudamiento, rentabilidad,
  actividad (periodos medios de cobro, pago y existencias) y flujos de caja. Cada uno trae su fórmula, su
  explicación, su zona de referencia, el año anterior y su numerador y denominador.
- Pantalla **Informes › Ratios** (es / en):
  - semáforo frente a la zona de referencia y evolución ↑↓;
  - detalle con la fórmula y los importes reales de la empresa.
- Prueba `test_fase18_ratios.sql`.

## [0.20.0] - 2026-10-08
### Añadido
- **Estado de flujos de efectivo** por el método indirecto (modelo normal del PGC) y el directo (NIC 7),
  con columna del ejercicio anterior y detalle por cuentas en cada línea (migración `0022`).
- **Cuadre del auditor**:
  - efectivo inicial + flujos = efectivo final;
  - directo = indirecto = variación del subgrupo 57;
  - comparación por actividades con la lista de asientos sin dinero que explican la diferencia.
- Pantalla **Informes › Flujos de efectivo** (es / en).
- Prueba `test_fase17_cash_flow.sql`.

## [0.19.0] · 2026-10-08
### Añadido
- Importar diario de otro ERP (Sage, Dynamics 365 Business Central o plantilla del laboratorio) en una empresa nueva,
  con todos sus ejercicios, vista previa con controles de auditor e importación por lotes.
- 10 cuentas del PGC en la plantilla del plan de cuentas.
### Cambiado
- Sumas y saldos y saldos anómalos no incluyen el asiento de cierre.

## [0.18.0] · 2026-10-07
### Añadido
- Prorrata general del IVA / IGIC: porcentaje provisional por año, reparto de la cuota entre deducible y no deducible
  en las facturas recibidas, y regularización con la prorrata definitiva en el 4T.
- Impuestos › Prorrata: cálculo de la definitiva, asiento de regularización e historial.
### Cambiado
- El libro registro guarda lo deducido de cada tipo; la liquidación usa esa cifra e incluye la regularización de la prorrata.


## [0.17.0] · 2026-10-07
### Añadido
- Inversión del sujeto pasivo (IVA e IGIC) y adquisiciones intracomunitarias de bienes, con autorrepercusión 472/477.
- Recargo de equivalencia: clientes en recargo (venta con IVA + recargo) y régimen de la empresa minorista
  (compras no deducibles, ventas con IVA incluido).
- Régimen de IVA de la empresa en Impuestos y marca "cliente en recargo de equivalencia" en Terceros.
### Cambiado
- La liquidación 303/420 incluye el recargo repercutido y el ISP en devengado y deducible, y excluye lo no deducible.

## [0.16.0] · 2026-10-07
### Añadido
- Retención IRPF en facturas recibidas y emitidas (profesionales 15 % / 7 %, alquileres 19 %), con líquido a pagar o cobrar.
- Impuestos › Retenciones IRPF: borrador trimestral de los modelos 111 y 115 y retenciones soportadas.
- Operaciones sin cuota con su causa: exenta (E1), exportación (E2), entrega intracomunitaria (E5) y no sujeta (N2).
### Cambiado
- El motor de facturas valida cada causa de exención según el tipo de factura y el territorio del tercero.
- El borrador del 303/420 muestra las bases sin cuota con su causa en lugar de "0 %".

## [0.15.0] · 2026-10-06
### Añadido
- Cierre del ejercicio: comprobaciones, regularización, cierre, apertura del año siguiente y reapertura.
- Etiqueta "Cierre" en el libro diario para los asientos del cierre.
### Cambiado
- Balance y PyG no incluyen los asientos de regularización y cierre.

## [0.14.0] · 2026-10-06
### Añadido
- Balance de situación y Cuenta de Pérdidas y Ganancias (modelo PYMES del PGC) con ejercicio anterior,
  fecha de corte y detalle de cuentas por partida.
### Cambiado
- Los importes muestran siempre separador de miles.

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
