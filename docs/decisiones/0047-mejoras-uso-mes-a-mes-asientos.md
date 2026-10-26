# ADR 0047 · Mejoras de uso II: contabilidad mes a mes, fecha rápida y pantalla «Asientos»

- **Fecha:** 2026-10-26
- **Versión:** v0.47.0
- **Estado:** aceptada

## Contexto

Al llevar una empresa de prueba como en ContaSol, Diosvely apuntó lo que le frenaba (`mejoras-de-uso.md`, del 7 al 10):
- no se podía elegir cuándo empieza la contabilidad ni avanzar **mes a mes**;
- la fecha había que escribirla entera o buscarla en el calendario;
- los asientos solo se veían línea a línea en el Libro diario, sin su **estado** ni su **origen**;
- y si faltaba una subcuenta, había que salir del asiento para crearla.

Cada mejora se validó antes de construirla.

## Decisión

1. **Contabilidad mes a mes** (0069):
   - al crear la empresa se elige la **fecha de inicio** y, si se marca, el modo mes a mes;
   - **mes de trabajo** = el primer mes abierto, y el motor **solo contabiliza en él**, como la ventana «Permitir
     registro desde / hasta» de Business Central. Así no se cuela un asiento de marzo estando en febrero. La regla vale
     para los asientos manuales y para los de todos los módulos; el cierre y la apertura del ejercicio no cuentan;
   - **«Cerrar mes»** en la cabecera, con avisos: borradores del mes, la nómina y, al cerrar un trimestre, la
     liquidación. Hay que aceptarlos para cerrar. **Diciembre** lo cierra el Cierre del ejercicio;
   - el administrador puede **reabrir el último mes cerrado**;
   - las empresas que ya existían, las importadas y las de los casos completos no cambian.
2. **Fecha rápida**, como ContaSol: `2` → el día 2 del mes de trabajo; `1503` o `15/3` → 15 de marzo; `h` → hoy; ↑ ↓,
   un día más o menos; 📅 abre el calendario. Avisa si la fecha cae fuera del mes abierto.
3. **Pantalla «Asientos»** (0070), la primera de Contabilidad:
   - una fila por asiento con su **origen**: factura, cobro o pago, nómina, inmovilizado…, importado o contraasiento;
   - su **estado**, con un fondo muy suave por estado y siempre con su texto e icono:
     - **contabilizado:** verde;
     - **en edición:** gris; es un borrador que ya se puede contabilizar;
     - **con error:** rojo; es un borrador que todavía no se puede contabilizar, y dice por qué: una sola línea, no
       cuadra, mes cerrado, después del mes abierto, cuenta controlada en modo estricto…;
   - el estado del borrador se **calcula** de sus líneas, no se guarda;
   - filtros **Mes actual · Desde / hasta · Todos** (por páginas), estado, origen y búsqueda; totales y Excel;
   - **acciones:** el clic en un contabilizado abre su ficha y en un borrador lo abre para seguir con él; se pueden
     marcar varios borradores y contabilizarlos de una vez (por fecha, para que la numeración sea correlativa) y borrar
     un borrador.
4. **Nuevo asiento:**
   - se abre desde «Asientos» y sale del menú;
   - el borrador se guarda a medias (una línea o sin cuadrar);
   - al guardar o contabilizar se vuelve a la lista con el mensaje de lo que se hizo;
   - una subcuenta que no existe se crea desde la propia línea («¿Crear la 10000001?»), con la misma validación que el
     Plan de cuentas.

## Alternativas descartadas
- **Dejar abiertos todos los meses y solo avisar.** En un laboratorio el aviso se ignora. La ventana de un solo mes es
  lo que hacen BC y SAP, y enseña el cierre mensual.
- **Guardar el estado del borrador** («error» o «en edición») en una columna. Se quedaría desfasado al cerrar un mes o
  cambiar el modo de control. Calculado, siempre dice la verdad.
- **Numerar los borradores.** El Código de Comercio pide una numeración correlativa de los asientos; el número llega al
  contabilizar.
- **Abrir el Plan de cuentas para crear la subcuenta.** Se perdería el asiento a medio escribir; el mismo formulario va
  dentro de la línea.

## Consecuencias
- Una empresa de prueba se lleva como en ContaSol: mes a mes, escribiendo solo el día, con la lista de asientos y su
  estado a la vista.
- **Limitaciones conocidas:**
  - el modo mes a mes y la fecha de inicio solo se eligen al crear la empresa;
  - un borrador de un mes posterior se puede guardar, pero sale «con error» hasta que llega su mes;
  - la fecha rápida está en Nuevo asiento, Facturas, Cobros y pagos, «Asientos» y el alta de empresa; las demás
    pantallas siguen con el calendario del navegador.
- **Pruebas:** 64 de 64 en la base de datos (fases 63 y 64) y 252 tests en la web. Comprobado en el navegador a 1366 y
  1920 px (claro y oscuro) y en el móvil, sin errores de accesibilidad.

## Cómo explicarlo
- **El cierre mensual no es un trámite.** Cerrar el mes es decir «esto ya está revisado»: después ya no se toca. Por eso
  el ERP avisa antes de lo que suele faltar (la nómina, la liquidación) y solo deja contabilizar en el mes abierto.
- **El estado de un asiento lo dicen sus líneas.** Un borrador que no cuadra no es «un error del programa»: es trabajo
  a medias. La pantalla lo enseña en rojo y dice qué le falta, igual que un revisor.
- **El número llega al final.** El libro diario numera los asientos por orden; los borradores no tienen número hasta
  que se contabilizan, y por eso se contabilizan por fecha.
- **En BC y SAP:** la ventana de registro es «Permitir registro desde / hasta» (BC) o la OB52 (SAP); la lista de
  asientos con su estado es la de los diarios generales. Aquí todo sale del mismo diario.
