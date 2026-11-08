# ADR 0056 · Tablero «Ventas y gastos»: rankings de clientes, proveedores y gastos desde la contabilidad

- **Fecha:** 2026-11-01
- **Versión:** v0.56.0
- **Estado:** aceptada

## Contexto

Cuarto de los cinco tableros nuevos (`plan-tableros.md`). Tiene que responder a: ¿cuánto vendo y cómo va frente al año
pasado, a quién le vendo más, a quién le compro más y en qué se va el dinero? Trae el último tipo nuevo de tarjeta, el
**ranking**. El diseño se validó antes de construir (`diseno-v0.56.0.md`), con tres decisiones de Diosvely:
- el volumen se mide **sin impuestos, desde los asientos**;
- las **inversiones** (grupo 2) cuentan en el ranking de proveedores;
- se enseñan los **10 primeros** y el «Resto».

El problema de fondo: las empresas importadas no tienen facturas en el ERP, solo asientos. Lo
que tienen todas es una subcuenta por tercero.

## Decisión

1. **Tipo de tarjeta «ranking»** (migración 0083): `dash_widgets` gana la fuente (`customers`, `suppliers` o
   `expense_groups`) y cuántos enseña (`top_n`, 10 por defecto). Sus filas no son métricas del catálogo, son los
   terceros o los subgrupos.
2. **Desde la contabilidad, por subcuenta** (`erp.dash_ranking`):
   - **ventas a un cliente:** lo abonado en las cuentas de la cifra de negocios (700 a 709, las de la partida 1 de la
     PyG) en los asientos que mueven su subcuenta (43, 44). Una rectificativa resta y un cobro no cuenta, porque no toca
     la 70;
   - **compras a un proveedor:** lo cargado en los grupos 6 y 2 en los asientos que mueven su subcuenta (40, 41);
   - **gastos por naturaleza:** los subgrupos del grupo 6 de la PyG, con su nombre del PGC.

   Un asiento con varios terceros se reparte en proporción a lo que mueve cada uno. Lo que no tiene tercero va a «Sin
   cliente» o «Sin proveedor». No cuentan la apertura ni el cierre, y se aplica la regla de qué cuenta en un informe
   (simulación incluida).
3. **La tarjeta entera en la base de datos** (`erp.dash_ranking_card`): los N primeros con el importe del año anterior a
   la misma fecha, el «Resto», lo que no tiene tercero, el total y la base del %:
   - en clientes y proveedores, el total;
   - en gastos por naturaleza, la cifra de negocios.
4. **El tablero**, con 6 tarjetas:
   - cifras clave;
   - ventas acumuladas frente al año anterior;
   - ventas y gastos de cada mes;
   - los 10 clientes, los 10 proveedores y los gastos por naturaleza.
5. **Web:** barras horizontales hechas a mano, con el importe y el % en cada fila. Encima va la concentración («Los 3
   primeros suponen el 93,1 % del total»). Cada cliente y proveedor enlaza a su libro mayor. «Ver como tabla», el
   Excel y el móvil están cubiertos.

## Alternativas descartadas
- **Leer las facturas** (como el 347). Exacto en las empresas creadas en el ERP, pero vacío en las importadas, que son
  las que tienen años de historia.
- **Lo cargado en la cuenta del cliente.** Más sencillo, pero mezcla el IVA / IGIC y no cuadra con las ventas de la
  PyG. Si además se contaran los movimientos de la cuenta, un cobro sumaría como otra venta (la prueba lo vigila).
- **El grupo 7 entero** para las ventas. Metería subvenciones, ingresos financieros o reversiones de deterioro en
  «ventas a un cliente»; con las 700 a 709, el total es exactamente la cifra de negocios.
- **Una librería de gráficos** para las barras horizontales: no hace falta para una lista de barras.

## Consecuencias
- **Cuadra con la PyG:** el ranking de clientes (con «Resto» y «Sin cliente») suma la cifra de negocios, y el de gastos
  por naturaleza, el grupo 6. En el caso: Cliente General SL 118.000 €, Cliente Dudoso SL 2.000 €, Recambios Canarios SL
  45.000 € (compras) y Maquinaria Atlántica SL 40.000 € (el torno), todo sin IGIC.
- **Limitaciones conocidas:**
  - «Sin proveedor» reúne los gastos que no pasan por un proveedor: personal, intereses, impuesto sobre beneficios,
    deterioros y variación de existencias (en el caso, 6.523,72 €);
  - el subgrupo 63 «Tributos» incluye el impuesto sobre beneficios (630), porque así lo agrupa el PGC;
  - una venta al contado sin subcuenta de cliente va a «Sin cliente», y una subcuenta «clientes varios» de una
    importación sale como un único cliente;
  - los nombres son los de la subcuenta (los del ERP o los del fichero importado).
- **Pruebas:** 77 de 77 en la base de datos y 297 tests de la web. La fase 77 comprueba con el caso completo:
  - que clientes = cifra de negocios y gastos por naturaleza = grupo 6;
  - que una venta a dos clientes se reparte 300 y 100, que el cobro no cuenta y que la rectificativa resta;
  - el «Resto», «hasta» con el año anterior, la simulación, que otra empresa no ve nada y 79 ms con una empresa grande
    al lado;
  - regresión: si se midiera por lo que se mueve en la cuenta del cliente, los clientes no sumarían la cifra de
    negocios.

## Cómo explicarlo
- **Concentración de clientes:** si los dos primeros clientes son el 100 % de las ventas (como en el caso), perder uno
  es perder la mitad del negocio o más. Es una de las primeras preguntas de un auditor o de un banco.
- **Por qué desde los asientos:** una venta es un abono en la 70; quién la compra lo dice la subcuenta del cliente
  cargada en el mismo asiento. Así funciona igual con facturas del ERP y con un diario importado.
- **Por qué un cobro no es una venta:** el cobro mueve la 430 y el banco, pero no la 70: no cambia lo vendido, solo lo
  pendiente de cobro.
- **Gastos por naturaleza frente a por función:** el PGC español clasifica los gastos por su naturaleza (compras,
  servicios, personal, amortización…), no por departamentos; esa es la vista de la contabilidad de gestión (fase 2).
- **En BC y SAP:** Business Central enseña «Top 10 clientes» y «Top 10 proveedores» en el *Role Center*, a partir de los
  *Customer / Vendor Ledger Entries*; SAP S/4HANA, las *Fiori apps* de análisis de ventas y de cuentas a pagar.
  *(Pendiente de validar por Diosvely.)*

*Revisión ética (v0.60.1, 2026-11-08): se quitan los nombres de programas comerciales (ADR 0063). La decisión y sus consecuencias no cambian.*
