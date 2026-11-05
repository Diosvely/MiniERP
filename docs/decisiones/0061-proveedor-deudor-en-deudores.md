# ADR 0061 · El proveedor con saldo deudor se presenta en Deudores, no en Existencias

- **Fecha:** 2026-11-05
- **Versión:** v0.59.2
- **Estado:** aceptada. Cambia la presentación de la 400 deudora que dejaba el ADR 0057.

## Contexto

Diosvely estudió en su empresa de prueba un proveedor con saldo deudor (propuesta 3 del parte de estudio, 05-11-2026).
El ERP ya hacía lo correcto en lo principal:
- **no compensaba** el proveedor deudor con los demás proveedores (principio de no compensación del Marco Conceptual);
- lo **avisaba** con ⚠ y una nota.

Pero lo presentaba en **Existencias**, como si fuera un anticipo (la 407), mientras la **410** deudora iba a **Otros
deudores**: dos criterios distintos para el mismo caso.

Si la empresa sigue el PGC, un anticipo de verdad se registra en la **407**. Un proveedor deudor es casi siempre otra
cosa: un pago duplicado, un abono pendiente de cobrar o una factura sin registrar, es decir, un **derecho de cobro**.
Llevarlo a Existencias además infla las existencias y cambia los ratios de rotación y la prueba ácida.

La decisión de Diosvely fue que, siempre que una cuenta tenga el saldo contrario a su naturaleza, se presente en la
partida que le corresponde a ese saldo, sin compensar, y con el aviso como está.

Al revisar la misma pantalla se vieron dos detalles más:
- **la nota del banco acreedor** podía hacer pensar que el asiento a la 5201 es obligatorio y definitivo;
- al desplegar «II. Deudas a corto plazo», **la subcuenta del banco** salía colgando de la partida, por encima de su
  sublínea «1. Deudas con entidades de crédito».

## Decisión

1. **La partida de cada saldo** (migración 0088, `erp.fs_mapping`):
   - 400–405 y 408–409 deudoras van a **AC.II.3 Otros deudores**, como la 410 deudora;
   - la **407** (anticipos a proveedores) sigue en **Existencias**, su sitio en el modelo de balance del PGC;
   - la **406** (envases y embalajes a devolver a proveedores) va a **Proveedores, restando**, también su sitio en el
     modelo de balance.

   El resto de cuentas de terceros ya iba a su sitio: 41, 44, 46 y 47 deudoras a Otros deudores; 43 acreedora a Otros
   acreedores; banco acreedor a Deudas con entidades de crédito.
2. **El aviso ⚠ se mantiene**, con notas que dicen qué revisar:
   - **400 deudora:** «se presenta en Otros deudores, sin compensar… Si es un anticipo, llévalo a la 407; si es un
     pago duplicado o un abono pendiente, es un derecho de cobro». Ya no propone una sola cuenta de destino, porque
     depende de la causa;
   - **banco acreedor:** «el balance ya lo presenta en Deudas con entidades de crédito. Si haces el asiento de
     reclasificación a la 5201 al cierre, reviértelo al abrir el ejercicio siguiente para que el mayor del banco siga
     cuadrando con el extracto».
3. **Web:** al desplegar una partida con sublíneas, cada cuenta dice en cuál se presenta (por ejemplo, «57200000 Banco
   → 1. Deudas con entidades de crédito»).

## Alternativas descartadas
- **Dejar la 400 deudora en Existencias.** Solo es correcto si es un anticipo, y un anticipo de verdad va en la 407.
- **Compensarla con los proveedores acreedores** (sumar la 400 entera). Va contra el principio de no compensación y
  esconde un derecho y una deuda. Solo sería admisible con un importe sin importancia relativa.
- **Reclasificar con un asiento automático.** La causa (anticipo, pago duplicado, abono) solo se sabe mirando el mayor.
  El ERP presenta y avisa; quien contabiliza corrige.

## Consecuencias
- **Pruebas:** 81 de 81 en la base de datos y 323 tests de la web.
  - **Fase 11:** el proveedor deudor ya no está en Existencias, sino en Otros deudores (273 + 50).
  - **Fase 78:** su ⚠ cae en Otros deudores, la nota dice qué revisar, y se comprueba que la 407 sigue en Existencias y
    la 406 resta en Proveedores.
  - Las dos fallan sin la migración 0088.
- **Cambia una cifra que ya se veía:** una empresa con una 400 deudora tendrá menos Existencias y más Otros deudores
  (y una prueba ácida distinta). Una 406 con saldo, si alguien la usa, pasa de Existencias a restar en Proveedores.

## Cómo explicarlo
- **Reclasificar para presentar frente a corregir el registro:**
  - el **banco** en descubierto es correcto en el mayor; solo se presenta en el pasivo. Si se hace el asiento, se
    revierte el 1 de enero;
  - el **proveedor** deudor suele ser un error o un derecho que hay que **corregir** con un asiento definitivo (a la
    407 si es un anticipo, o a Deudores si es un pago duplicado). No se revierte.
- **No compensación:** un proveedor deudor no se resta de los proveedores acreedores; cada saldo va a su lado del
  balance (Marco Conceptual del PGC).
- **Por subcuenta, no por cuenta:** la clasificación por signo se hace proveedor a proveedor. Sumar la 400 entera (en
  una hoja de cálculo o en un modelo de Power BI) compensa sin querer.
- **Fuente:** el PGC (Real Decreto 1514/2007): el Marco Conceptual (principio de no compensación) y el modelo de
  balance (Existencias, «Anticipos a proveedores», 407; Proveedores, con la 406 restando). *(Pendiente de validar por
  Diosvely la redacción exacta del modelo de balance y de las definiciones y relaciones contables de la 400 y la 407.)*
