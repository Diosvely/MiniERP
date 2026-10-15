# ADR 0031 · Cuentas controladas (modo estricto o guiado) y comprobaciones del auditor

- **Fecha:** 2026-10-15
- **Versión:** v0.33.0
- **Estado:** aceptada

## Contexto

Con la v0.32.0 los pagos ya se hacen contra la factura, pero nada impedía seguir haciéndolos a mano («410 a 572»):
la factura no se enteraba y la cuenta del tercero dejaba de cuadrar con sus facturas. Los ERP resuelven esto de dos
maneras:

- **SAP y Business Central controlan «antes».** La cuenta de proveedores es una *cuenta asociada* (SAP) o no admite
  *registro directo* (BC): solo la mueve su módulo. En el ERP cubano Versat eran las «cuentas controladas».
- **Los ERP españoles (A3, Sage, ContaPlus) controlan «después».** Dejan el asiento manual y lo detectan con cuadres:
  el IVA contra el libro registro, los terceros contra sus facturas, el punteo…

Para un laboratorio de aprendizaje interesan las dos: la disciplina de SAP/BC y los cuadres que hace un auditor en
España (`docs/cuentas-controladas.md`).

## Decisión

1. **Cuentas controladas como datos** (`erp.control_rules`, migración 0036): qué módulo mueve cada cuenta y por qué
   lado. Gana el prefijo más largo.

   | Cuentas | Lado | La mueven |
   |---|---|---|
   | 400, 410, 430, 440 | ambos | Facturas y Cobros y pagos |
   | 4009, 4309 | — | libres (ajustes de cierre) |
   | 472, 477 | ambos | Facturas y Liquidación |
   | 4750 | Haber | Liquidación (el pago a Hacienda, al Debe, es manual) |
   | 4700 | Debe | Liquidación (el cobro de la devolución, al Haber, es manual) |
2. **Modo por empresa** (`companies.control_mode`, solo lo cambia el administrador):
   - **estricto** (SAP/BC): un asiento manual que mueve una cuenta controlada no se contabiliza. Se comprueba con un
     trigger de restricción **diferido** al final de la transacción, porque los módulos crean primero el asiento y
     después su documento;
   - **guiado** (ERP español): se contabiliza, la web avisa antes y queda listado en Comprobaciones;
   - por defecto, guiado en la base de datos (no cambia nada en las empresas existentes ni en las importadas); la web
     crea las empresas nuevas en estricto;
   - nunca se bloquean la apertura, el cierre, los contraasientos, las importaciones ni los asientos de los módulos.
3. **Comprobaciones del auditor como datos** (`erp.audit_checks`, `erp.run_audit_checks`, migración 0037), siempre
   activas y a una fecha. Cada una da el libro, la contabilidad, la diferencia, los casos enlazados y la pantalla donde
   se arregla:
   - 472 y 477 frente al libro registro (sin liquidación ni prorrata);
   - 4751 frente a los modelos 111/115. Es informativa: las retenciones de nómina son normales;
   - cada tercero frente a sus facturas pendientes;
   - saldos al revés de su naturaleza (reutiliza la 0013): aviso, o error si es imposible;
   - IGIC en la Península o IVA en Canarias;
   - asientos manuales sobre cuentas controladas (los pagos ya vinculados no cuentan).
4. **Conceptos** (`erp.concepts`, migración 0038): el glosario también en la base de datos, con las cuentas del PGC de
   cada término. Es la primera pieza de la ontología: cuenta → conceptos → comprobaciones, para el Tutor y el chat.
   La fuente sigue siendo `glossary.js`, porque la web lo enseña sin sesión y al instante; un test falla si las dos
   copias se separan.
5. **Web:**
   - modo de control al crear la empresa y en la pantalla Comprobaciones;
   - aviso en el formulario de asiento antes de contabilizar, y en estricto no se puede contabilizar, solo guardar en
     borrador;
   - error traducido con un botón a la pantalla del módulo;
   - pantalla «Comprobaciones» en el menú Auditor;
   - cuentas del PGC en el glosario, que también se busca por cuenta.

## Alternativas descartadas
- **Solo avisar (sin modo estricto):** no enseña la disciplina de SAP/BC, que es justo lo que pide el mercado.
- **Solo bloquear:** rompería la contabilidad importada y no enseña los cuadres de un auditor español.
- **Una marca por subcuenta** en `gl_accounts`: duplicaría la regla en cada empresa. Por prefijo y como datos se
  cambia en un sitio.
- **La web lee el glosario de la base de datos:** habría que abrir la tabla a anónimos y esperar una consulta para
  cada globo ⓘ.

## Consecuencias
- El ERP se comporta como SAP/BC o como un ERP español con un interruptor, y el alumno ve la diferencia.
- Las comprobaciones son la base de la fase 3 del plan «IA guiada por reglas»: el chat podrá responder «¿cuadra mi
  IVA?» con datos, no con suposiciones.
- **Pruebas:** 32 de 32 en la base de datos (fases 30, 31 y 32 nuevas) y 98 tests de la web.
