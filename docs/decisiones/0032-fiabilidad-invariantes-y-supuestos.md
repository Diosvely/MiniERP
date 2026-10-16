# ADR 0032 · Fiabilidad contable: invariantes y supuestos de referencia

- **Fecha:** 2026-10-16
- **Versión:** v0.34.0
- **Estado:** aceptada

## Contexto

Una revisión externa (15-10-2026) señaló la debilidad de fondo del proyecto: las pruebas las escribió la misma IA que
escribió el código. Comprueban lo que el código hace, no lo que dice la contabilidad. Encontró dos fallos reales que
ninguna prueba había visto (v0.33.1).

La revisión proponía supuestos de libros de FP, de la universidad o de oposiciones. Se decide no esperar a esos
materiales y empezar con dos defensas que no dependen de quién escribe el código.

## Decisión

1. **Invariantes contables** (`erp.integrity_checks`, migración 0040). Son nueve verdades que se cumplen siempre:
   - cada asiento cuadra;
   - sumas y saldos cuadran;
   - Activo = Patrimonio neto + Pasivo;
   - la 129 recibe el resultado de la PyG;
   - la apertura de N+1 es el cierre de N, cuenta a cuenta;
   - un asiento y su contraasiento suman cero;
   - el tercero de cada factura queda por el total menos la retención;
   - las 472/477 de las facturas coinciden con el libro registro;
   - la variación de la 57 coincide con el EFE directo e indirecto.

   Si una falla, el error es del ERP, no del usuario. Quedan como función, para enseñarlas en la web o al chat.
2. **Operaciones al azar** (fase 34). Dos empresas, una con IVA y otra con IGIC, hacen unas 300 operaciones de todos
   los tipos, liquidan cada trimestre **sin aceptar diferencias**, cierran el ejercicio y siguen en el año siguiente.
   Los invariantes se exigen cada 25 operaciones. La semilla es fija para poder repetir un fallo. La prueba termina
   con un recuento de lo que ha hecho el azar, para ver que recorre todos los caminos.
3. **Supuestos de referencia** (fase 35). Cinco casos completos con la solución **calculada a mano desde la norma**,
   citando el artículo de cada cifra:
   - servicios con IRPF (111 y 115);
   - Canarias con IGIC (420);
   - AIB e ISP;
   - recargo de equivalencia;
   - prorrata.

   El ERP tiene que coincidir al céntimo en balance, PyG y modelos.

## Alternativas descartadas
- **Esperar a supuestos de fuentes externas:** retrasaba la versión sin fecha. Quedan como mejora: cada supuesto que
  llegue se añade a la fase 35, con su fuente.
- **Comparar solo con ContaSol:** es manual y no se puede ejecutar en cada cambio. Queda como tarea mía, en paralelo.
- **Generar las cifras esperadas con el propio ERP** (*snapshot testing*): repetiría la debilidad de fondo.

## Consecuencias
- Los supuestos los calcula también una IA, aunque desde la norma y no desde el código. La debilidad se reduce, no
  desaparece. Los invariantes, en cambio, no dependen de quién los escriba.
- Hallazgo: el borrador del 303 tiene los importes correctos y separa AIB e ISP, pero **no numera las casillas
  oficiales**. Pasa al backlog.
- **Pruebas:** 35 de 35 en la base de datos (fases 34 y 35 nuevas; la 34 pasa con cuatro semillas) y 98 tests de la
  web.
