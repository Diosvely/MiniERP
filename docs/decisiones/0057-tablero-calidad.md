# ADR 0057 · Tablero «Calidad de la contabilidad» y aviso de saldos al revés en el Balance

- **Fecha:** 2026-11-01
- **Versión:** v0.57.0
- **Estado:** aceptada. La presentación de la 400 deudora la cambia el ADR 0061: pasa de Existencias a Otros deudores

## Contexto

Último de los cinco tableros nuevos (`plan-tableros.md`). Tiene que responder a: ¿me puedo fiar de esta contabilidad a
esta fecha, y qué me falta por hacer? Reúne lo que se fue dejando para aquí:
- **los saldos al revés.** La duda de la 400 deudora de las empresas importadas: el ERP la presenta en Existencias,
  como un anticipo, y no la compensa con los proveedores acreedores (`estudio/saldos-al-reves.md`);
- **las liquidaciones pendientes** (decisión de la v0.55.0);
- **los cobros y pagos vencidos** (decisión de la v0.54.0).

Comprobaciones ya tenía 22 comprobaciones del auditor, pero es lenta para mirarla a diario. El diseño se validó antes
de construir (`diseno-v0.57.0.md`), con cuatro decisiones de Diosvely:
- «meses sin cerrar» solo en la contabilidad mes a mes;
- una liquidación pendiente es un error;
- en el Balance, el aviso completo: franja, partida y cuenta;
- la 400 deudora sigue en Existencias con aviso, hasta revisar el criterio (resuelto en la v0.59.2, ADR 0061: va a Deudores).

## Decisión

1. **La lista de control** (`erp.quality_checks`, migración 0084): siete filas a una fecha, cada una con su valor, su
   gravedad y su pantalla. Las gravedades posibles son ok, info, aviso, error y «no aplica».
   - **Saldos al revés:** `balance_anomalies`. Es error si hay alguna «imposible», como una caja acreedora o una
     amortización deudora.
   - **Asientos en edición y con problema:** `draft_ready`, la función que puede usar la web.
   - **Meses sin cerrar:** solo en la contabilidad mes a mes.
   - **Liquidaciones pendientes:** trimestres terminados sin liquidación contabilizada del impuesto de la empresa. Es
     error.
   - **Cobros y pagos vencidos, y terceros sin conciliar:** `aging`. Si la empresa no tiene facturas en el ERP (una
     importada), estas filas dicen «no aplica».

   Los textos de cada fila están en un catálogo (`erp.quality_check_defs`), como el resto de los tableros.
2. **La tarjeta `checklist`.** La dibuja la web con su icono y su estado en texto, nunca solo con color.
3. **Dos fuentes nuevas de ranking:** las cuentas con saldo al revés, con la nota de `balance_rules` de lo que suele
   significar, y los clientes con más importe vencido. El ranking pasa a devolver la nota de cada fila.
4. **El aviso en el Balance** (`erp.fs_line_anomalies`): cada cuenta con saldo al revés, con la partida en la que se
   presenta. En la pantalla del Balance:
   - una franja arriba;
   - un ⚠ con el número en la partida y en las que la contienen;
   - y, al desplegar la partida, el ⚠ y la nota de la cuenta.

   Con la simulación, el aviso cuenta también los asientos en edición.

## Alternativas descartadas
- **Ejecutar Comprobaciones entera** para el tablero: correcto, pero lento para mirarlo cada día. La lista de control
  lee solo lo que necesita y enlaza a Comprobaciones para el análisis completo.
- **Compensar la 400 deudora con los proveedores acreedores**, como hacen algunos informes y modelos de Power BI: va
  contra el principio de no compensación del Marco Conceptual y esconde un derecho y una deuda.
- **Mover ya la 400 deudora a Deudores:** puede ser lo correcto si es un pago duplicado o un abono pendiente, pero
  faltaba revisar el criterio. Hasta entonces, se avisa (resuelto en la v0.59.2, ADR 0061).
- **«Meses sin cerrar» en todas las empresas:** en las que no llevan la contabilidad mes a mes, todos los meses están
  abiertos por diseño; el aviso no significaría nada.

## Consecuencias
- **Lo que trae el caso** «Taller Atlántico SL»:
  - un saldo al revés de verdad: Reservas voluntarias con 850 € deudores, por los gastos de la ampliación de capital
    cargados contra reservas. Sale como aviso en el patrimonio neto;
  - el cliente dudoso, con 2.140 € vencidos a más de 90 días, que es un error.
- **Una caja acreedora no se puede contabilizar en el ERP**, porque está bloqueada para saldos al revés. Sí puede llegar
  en un diario importado; la prueba la mete así.
- **Limitaciones conocidas:**
  - «Liquidaciones pendientes» cuenta un trimestre en cuanto termina, aunque aún esté dentro del plazo de presentación
    (los primeros 20 días del mes siguiente);
  - «Meses sin cerrar» compara con la fecha de hoy, así que en un ejercicio futuro no cuenta nada;
  - la nota de cada cuenta es la de su regla (por prefijo), no un análisis de su mayor.
- **Pruebas:** 78 de 78 en la base de datos y 302 tests de la web. La fase 78 provoca cada problema uno a uno:
  - un proveedor deudor, que da aviso: su ⚠ cae en Existencias y la partida de Proveedores no cambia (regresión de la
    400), además de quedar sin conciliar con sus facturas;
  - una caja acreedora importada, que da error y cae en el pasivo corriente;
  - un borrador descuadrado;
  - un trimestre sin liquidar;
  - los meses sin cerrar en la contabilidad mes a mes; falla si se contaran también en las demás;
  - la simulación, una empresa sin facturas, que otra empresa no ve nada y 88 ms con una empresa grande al lado.

## Cómo explicarlo
- **No compensación:** el Marco Conceptual del PGC prohíbe compensar activos con pasivos salvo que una norma lo permita.
  Un proveedor deudor es un derecho de cobro (o un anticipo); si se resta de los acreedores, el balance enseña menos
  deuda y menos derecho de los que hay.
- **Por qué avisar y no corregir:** el ERP no sabe si un saldo al revés es un anticipo, un pago duplicado o un error; la
  causa está en el libro mayor. El aviso dice dónde mirar y qué suele significar.
- **«Imposibles» frente a «dudosas»:** una caja acreedora o una amortización deudora no pueden existir; un proveedor
  deudor sí (un anticipo). Las primeras son errores; las segundas, avisos.
- **Lista de control frente a auditoría:** lo que un contable mira cada día (borradores, meses, liquidaciones,
  vencidos) frente a lo que revisa un auditor al cierre (Comprobaciones).
- **En BC y SAP:** Business Central tiene las *cues* del *Role Center* del contable (documentos sin registrar,
  vencidos, *VAT Returns* abiertos); SAP S/4HANA, el *Advanced Financial Closing* con su lista de tareas del cierre.
  *(Pendiente de validar por Diosvely.)*

*Revisión ética (v0.60.1, 2026-11-08): se quitan los nombres de programas comerciales (ADR 0063). La decisión y sus consecuencias no cambian.*
