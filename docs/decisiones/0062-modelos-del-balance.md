# ADR 0062 · El Balance en los tres modelos del PGC: PYMES, abreviado y normal

- **Fecha:** 2026-11-06
- **Versión:** v0.60.0
- **Estado:** aceptada (diseño validado por Diosvely, `diseno-v0.60.0.md`).

## Contexto

Diosvely comparó el Balance del ERP con el modelo de balance del BOE y vio que en el ERP las Existencias son «I» y en
el BOE «II». No era un error. El ERP presentaba el Balance con el modelo del **PGC de PYMES** (RD 1515/2007, ADR 0011),
y lo que él miraba era el modelo **normal** del **PGC general** (RD 1514/2007). El modelo normal empieza el activo
corriente por «I. Activos no corrientes mantenidos para la venta», una partida que el de PYMES no tiene, y por eso todo
lo que sigue sube un número.

Su próximo vídeo trata del Balance, y quería enseñar esa diferencia con el ERP.

## Decisión

1. **El mismo Balance en tres modelos:** PYMES (por defecto), abreviado y normal, con un selector en la pantalla. La web
   recuerda el último modelo elegido en el navegador. Las adaptaciones sectoriales quedan fuera: traen cuentas propias
   y las empresas de práctica son pymes.
2. **PYMES no cambia.** Sigue en `erp.fs_lines` y `erp.fs_mapping`, y es la clasificación que usan los ratios, los
   tableros, Power BI, el caso y el ECPN. Con `p_model = 'pymes'` (el valor por defecto), las funciones ejecutan el
   mismo código de antes.
3. **El abreviado y el normal solo recolocan** (migración 0089). El saldo de cada cuenta se calcula una sola vez
   (`erp.fs_classified_at`), y cada modelo lo coloca en su partida con sus tablas (`erp.fs_models`,
   `erp.fs_model_lines` y `erp.fs_model_mapping`). Se sigue la regla de siempre: cada subcuenta por su propio saldo,
   sin compensar. Así el total no puede cambiar de un modelo a otro.
4. **Partidas y cuentas del normal:** se copiaron de la columna «Núm. cuentas» del BOE consolidado (Diosvely,
   06-11-2026). Las cuentas que el BOE no nombra van a la partida «otros» de su grupo, en el mismo lado que en PYMES.
   Las cuentas al revés siguen la regla de la v0.59.2: en el normal, el proveedor deudor va a «Deudores varios», el
   cliente acreedor a «Anticipos de clientes» y el banco en descubierto a «Deudas con entidades de crédito».
5. **El abreviado agrupa las partidas del normal** (`erp.fs_abridged_line`). Así no puede contradecirlo.
6. **Solo el Balance.** La PyG sigue en el modelo PYMES (decisión 4 del diseño).
7. **Fuentes en la pantalla:** botón 📘 con el RD 1515/2007 o el RD 1514/2007, según el modelo.

## Alternativas descartadas

- **Una columna «modelo» en `fs_lines` y `fs_mapping`.** Habría que tocar todas las funciones que las leen (ratios,
  tableros, Power BI, cierre…), y el riesgo era cambiar sin querer las cifras de PYMES.
- **Un mapeo del normal escrito a mano y otro del abreviado.** Dos listas de casi 200 prefijos que podrían
  contradecirse. Por eso el abreviado se deriva del normal.
- **Las adaptaciones sectoriales:** se descartan por el motivo del punto 1.

## Consecuencias

- **Pruebas:** 82 de 82 en la base de datos y 337 tests de la web.
  - **Fase 82** comprueba:
    - cobertura: 2.848 casos (cada cuenta del PGC de estudio × saldo deudor y acreedor × modelo), todos con partida
      y en la misma masa que en PYMES. Solo cambian de masa la 1034 y la 1044 (capital pendiente de inscripción), que
      el BOE pone en el pasivo corriente;
    - las cuatro sintéticas a tres fechas: mismas masas, cuadra, cada cuenta una vez y cada partida es la suma de sus
      líneas;
    - los casos del BOE;
    - que PYMES es igual que antes y que otro usuario no ve nada.
  - Regresión: si el banco acreedor se deja en el activo, la prueba falla.
- **La nota del proveedor deudor** nombra también la partida del normal («Deudores varios»).
- **Lo que no sabe el ERP:** qué modelo le corresponde a cada empresa por su tamaño. Queda en `ideas-pendientes.md`.
- ~~**Limitación conocida:** antes del cierre, los grupos 8 y 9 se presentan en A-3.~~ Corregido en la v0.60.4: ver la
  actualización de abajo.

## Cómo explicarlo

- **Un balance, tres formatos:** las cuentas y los saldos son los mismos. Cambian la numeración, el desglose y dos
  partidas que solo existen en el PGC general:
  - «Activos no corrientes mantenidos para la venta» (580–584, con sus pasivos vinculados 585–589);
  - «A-2) Ajustes por cambios de valor» (133, 1340, 137). Por eso las subvenciones son A-2 en PYMES y A-3 en el general.
- **Por qué las Existencias son I o II:** el PGC de PYMES no tiene la partida de activos mantenidos para la venta, y todo
  el activo corriente sube un número. Lo mismo pasa con el pasivo corriente.
- **Quién usa cada modelo** (pendiente de validar por Diosvely: art. 257 de la LSC y art. 2 del RD 1515/2007):
  - el de PYMES y el abreviado, las empresas que no superan dos de tres límites (activo, cifra de negocios y plantilla
    media);
  - el normal, las demás.
- **Fuentes:**
  - RD 1514/2007, tercera parte: modelos normales y abreviados;
  - RD 1515/2007, tercera parte: modelos de PYMES.
  **Abreviado validado** (auditoría fiscal, 09-11-2026): partidas y cuentas comparadas con el «Balance abreviado» del
  RD 1514/2007, tercera parte, texto consolidado del BOE (última actualización 21-12-2024).

## Actualización (v0.60.3, 2026-11-09)

- **Las correctoras del activo con saldo acreedor restan en su partida del activo**, como dice el BOE con el paréntesis:
  (437) en Clientes, (5393) y (5394) en Inversiones en empresas del grupo a corto, y (5395) y (549) en Inversiones
  financieras a corto. Antes salían en el pasivo y engordaban los dos lados del Balance. Igual que la (406), que resta
  en Proveedores. Se corrige en los tres modelos a la vez (migración 0092; hallazgo AF-05 de auditoría fiscal). Fase 82
  con su regresión.
- **El modelo abreviado queda validado frente al BOE** (AF-04): las 46 partidas coinciden y, con la corrección de
  arriba, todas las cuentas que nombra el BOE caen en su partida.

### Cómo explicarlo
- **El paréntesis del BOE significa «resta aquí».** Una cuenta correctora no cambia de lado por tener su saldo normal:
  los envases que los clientes nos tienen que devolver (437) rebajan lo que nos deben, igual que la amortización
  rebaja el inmovilizado.

## Actualización (v0.60.4, 2026-11-10)

- **Los grupos 8 y 9 sin regularizar, en su partida** (hallazgo AF-06 de auditoría fiscal; Diosvely decidió corregirlo):
  80 y 90 van a «A-2) I. Activos financieros a valor razonable con cambios en el patrimonio neto», 81 y 91 a «II.
  Operaciones de cobertura» y 82 y 92 a «III. Otros» (en el abreviado, A-2). Las subvenciones (84 y 94) siguen en A-3.
  El total del patrimonio neto no cambia. Migración 0093, con la prueba en la fase 82. El modelo de PYMES no cambia.
- **Las cuentas de los subgrupos 80-82 y 90-92 entran en la plantilla del plan de cuentas,** para poder usarlas (antes
  un diario con una 900 no se podía importar).
- **Limitación conocida:** el cierre del ERP regulariza los grupos 8 y 9 contra la 130; para 80-82 y 90-92 la
  contrapartida sería la 133, la 1340 o la 135. Queda para auditoría fiscal.

### Cómo explicarlo
- **No todo el grupo 9 es una subvención.** Si unas acciones a valor razonable suben de valor, la ganancia todavía no
  realizada va al patrimonio neto (900), pero no es una ayuda pública: es un ajuste por cambio de valor (A-2).
