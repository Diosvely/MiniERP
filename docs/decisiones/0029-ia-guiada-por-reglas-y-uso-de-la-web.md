# ADR 0029 · IA guiada por reglas (retenciones) y panel de uso de la web

- **Fecha:** 2026-10-13
- **Versión:** v0.31.0
- **Estado:** aceptada

## Contexto

1. **La IA no aplicaba la retención.** Probando el Tutor con «factura de una abogada autónoma por 1.000 € en
   Canarias», la IA acertaba el IGIC (el ERP le da los tipos de la empresa y recalcula la cuota) pero **nunca**
   practicaba la retención del 15 %. Las instrucciones solo decían «retenciones: role withholding», sin regla de
   cuándo ni de cuánto, y el ERP no la recalculaba. No era un fallo puntual del modelo: era una regla contable que
   dependía de que el modelo «se acordara».
2. **No se sabía cuánta gente probaba la demo.** Al difundir la web hacía falta medirlo. Además, la limpieza
   nocturna de invitados (0028) borraba a los de más de 7 días, así que contando usuarios se perdía la historia.

## Decisión

### 1. La IA clasifica, la base de datos contabiliza (migración 0033)
Es el mismo reparto que en los ERP grandes: los **grupos contables** de Business Central o la **determinación de
cuentas** de SAP (OBYC) deciden las cuentas a partir de datos maestros, no del texto.

- **La ficha del tercero manda**, como el maestro del acreedor en SAP:
  - **forma jurídica**, que por defecto sale del NIF (NIF / NIE → persona física; CIF → entidad);
  - **retención por defecto** (IRPF15, IRPF7, IRPF19).

  La base de datos rechaza lo que no tiene sentido: la retención de profesionales a una entidad, o cualquier
  retención a un cliente.
- **Reglas de retención como datos** (`erp.withholding_rules`):
  - 623 profesionales: IRPF15 / IRPF7 si es persona física;
  - 621 alquiler de local: IRPF19.

  La IA las recibe en su contexto y el ERP las comprueba. Una regla nueva es una fila nueva, no código nuevo.
- **El ERP calcula, como ya hacía con el IVA:**
  - el código: el de la ficha, si no el de la línea, si no el de la regla del gasto;
  - la cuenta: la 4751 / 473 configurada;
  - el importe: base × tipo.

  Si corrige un importe, ajusta la línea del tercero para que cuadre (1.000 + 70 − 150 = 920). Solo lo hace si hay
  una única línea de tercero; un descuadre que no viene de una corrección del ERP no se tapa.
- **Avisos:** «gasto con retención sin ella», «la ficha dice IRPF15 y el asiento no la lleva», «retención de
  profesionales a una entidad». Los de nivel aviso hacen que la IA corrija en una segunda vuelta. El del alquiler es
  solo informativo, porque el *renting* de una furgoneta no lleva retención.
- **La factura recibida** toma la retención de la ficha del tercero al elegirlo.

### 2. Panel «Uso de la web», solo para el propietario (migración 0034)
- `erp.web_usage(días)`:
  - **solo cifras agregadas**: visitantes de la demo (usuarios anónimos), registros, activos de la semana, empresas,
    importaciones y consultas a la IA;
  - sin correos y sin contar al propietario;
  - días en hora de Canarias.
- `erp.cleanup_guests` guarda en `erp.guest_history` cuántos invitados había cada día **antes** de borrarlos. Así,
  los totales y la serie diaria no cambian con la limpieza.
- **Visualización, con el criterio de «menos es más»:** 4 cifras y un único gráfico de barras (visitantes por día),
  con tooltip y «Ver como tabla». Los registros van en el tooltip y en la tabla, no en una segunda serie.
- Lo que pasa **antes** de pulsar la demo (visitas a la portada, procedencia) queda para Cloudflare Web Analytics:
  sin cookies y sin código.

## Alternativas descartadas
- **Arreglar solo las instrucciones de la IA:** ayuda, pero sigue dependiendo de que el modelo obedezca. Se hace
  también, pero el control está en la base de datos.
- **Que el ERP añada la línea de retención por su cuenta:** no se sabe si la abogada es persona física hasta que lo
  dice la ficha o el texto. Se avisa y se deja decidir (a la IA en la segunda vuelta, y al usuario al final).
- **Rastreo propio de visitas (tabla de eventos, cookies):** innecesario. Los usuarios anónimos ya son el recuento, y
  la RGPD se complica.

## Consecuencias
- El Tutor deja de alucinar en el caso de las retenciones. Es la **fase 1** del plan «IA guiada por reglas»
  (`ideas-pendientes.md`). Las siguientes fases van en el mismo sentido: catálogo de operaciones, controles de auditor
  como datos, banco de casos y, al final, una ontología contable con chat.
- **Nuevos datos en la ficha del tercero** (`legal_form`, `withholding_code`) y en la vista `v_partners`.
- **Pruebas:** 28 de 28 en la base de datos (fases 27 y 28 nuevas, y las dos fallan sin su migración) y 83 tests de la
  web.
