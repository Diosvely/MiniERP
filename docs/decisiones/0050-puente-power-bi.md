# ADR 0050 · Puente a Power BI: un «contrato» de datos de solo lectura

- **Fecha:** 2026-10-27
- **Versión:** v0.50.0
- **Estado:** aceptada

## Contexto

Diosvely va a dar una charla técnica de unos 20 minutos sobre tecnología de datos de Microsoft (finales de noviembre de
2026). La demo:
1. un cliente da su diario en CSV y pide un balance, una cuenta de pérdidas y ganancias y un estado de flujos;
2. se importa y se valida en el Mini ERP;
3. Claude Code, con un servidor MCP de Power BI, construye el informe en un proyecto PBIP;
4. se comprueba que cuadra con el ERP al céntimo.

Para el punto 3 hacía falta que Power BI leyera los datos del ERP de forma ordenada y segura, sin que Claude Code
tuviera que entender la contabilidad, y sin poner en riesgo nada de lo que ya funciona. El «Puente a Power BI» ya
estaba en el plan de la fase 2; se adelanta. El diseño se validó antes de construir (`diseno-v0.50.0.md`).

## Decisión

1. **Un esquema aparte, `bi`, con vistas de solo lectura** (migración 0073):
   - no cambia nada del ERP, y la web no lo ve (no está en la API de Supabase);
   - modelo en estrella: `dim_empresa`, `dim_fecha`, `dim_cuenta`, `dim_linea` (las líneas de los estados como
     jerarquía), `puente_linea`, `dim_ratio`, `fact_apuntes`, `fact_saldos_mes` y `fact_flujos`;
   - `control_estados`: lo que enseña el ERP (balance y PyG por fin de mes, flujos y ratios por ejercicio), para la
     página «Comprobación» de Power BI.
2. **Solo las empresas demo**, con la marca de siempre: quien publique su empresa como demo sale también en Power BI.
   Las temporales nunca, aunque alguien las marcara.
3. **El ERP decide; Power BI calcula y enseña** (decisión de Diosvely):
   - en `fact_saldos_mes` la línea del balance de cada cuenta **ya viene decidida** según el signo de su saldo (un
     banco en descubierto va al pasivo) y el importe, con el signo con que se enseña;
   - los flujos llegan ya clasificados, por los dos métodos;
   - Power BI hace el DAX (saldo a fecha, comparativas, ratios) y la visualización.
4. **Un usuario propio para Power BI**, `powerbi_reader`, que **solo lee `bi`**: no puede ni entrar en el esquema del
   ERP. Se crea sin poder entrar; la contraseña la pone Diosvely en Supabase. Las vistas leen el ERP con los permisos
   de su propietario.
5. **Primera entrega:** balance, PyG, estado de flujos y 8 ratios (fondo de maniobra, liquidez general, prueba ácida,
   endeudamiento, ROA, ROE, margen neto y EBITDA).
6. **Una guía para Claude Code** (`docs/powerbi/GUIA.md`): cómo conectar por el *session pooler* de Supabase, las
   relaciones, las medidas DAX, las páginas, las cifras esperadas del caso «Taller Atlántico SL» y las instrucciones
   para pegar en Claude Code.

## Alternativas descartadas
- **Conectar Power BI a las tablas del ERP.** Claude Code tendría que entender el PGC, los signos y los asientos de
  regularización y de cierre, y Power BI necesitaría permisos sobre todo el ERP.
- **Que el DAX decida la línea del balance según el signo.** Es posible, pero enrevesado, y en una demo en directo es
  más fácil que falle. La regla ya existe en el ERP y está probada.
- **Una marca aparte («En Power BI») en lugar de «Demo».** Diosvely decidió usar la de demo: sus datos reales nunca se
  publican.
- **Publicar en la web (Publish to web) o incrustar el informe en el ERP.** Lo primero es público y sin seguridad. Lo
  segundo, con RLS por empresa, queda anotado para más adelante (`ideas-pendientes.md`).

## Consecuencias
- Power BI lee un modelo en estrella listo, y el informe se comprueba contra el ERP al céntimo.
- **Escalable:** cada informe del ERP que pase a Power BI será una vista más en `bi`, con el mismo estilo de nombres.
- **Limitaciones conocidas:**
  - las medidas DAX de la guía no se han podido ejecutar aquí: se comprueban en el primer ensayo con las cifras
    esperadas;
  - la conexión por el *session pooler* y el certificado SSL de Supabase en Windows, pendientes de comprobar por
    Diosvely;
  - `fact_saldos_mes` y `control_estados` se calculan al consultarlos: con empresas demo pequeñas es rápido; con
    diarios grandes, el refresco tardará más.
- **Pruebas:** 67 de 67 en la base de datos. La fase 67 comprueba, con el caso completo publicado como demo:
  - que solo llegan las demo;
  - que el balance y la PyG cuadran con el ERP en los 24 fines de mes;
  - que los flujos coinciden por los dos métodos, y la comprobación con las pantallas en los estados y los 21 ratios;
  - que los 8 ratios se recalculan igual;
  - y los permisos de `powerbi_reader`.

## Cómo explicarlo
- **Un contrato de datos:** el ERP no le da a Power BI sus tablas, le da una «fachada» pensada para analizar. Si el ERP
  cambia por dentro, el contrato sigue igual y los informes no se rompen.
- **El modelo en estrella:** hechos (saldos, apuntes, flujos) rodeados de dimensiones (empresa, fecha, cuenta, línea).
  Es como piensa Power BI, y como se enseña en el PL-300.
- **Quién decide y quién calcula:** las reglas contables viven en un solo sitio, el ERP. Power BI no las repite: las
  lee. Por eso las cifras coinciden.
- **Mínimo privilegio:** el usuario de Power BI solo ve lo que necesita, y la página «Comprobación» demuestra que lo que
  enseña es verdad.
- **En BC y SAP:** Business Central publica *API pages* y *queries* para Power BI. SAP tiene las *CDS views* de
  análisis. Aquí, las vistas del esquema `bi`.
