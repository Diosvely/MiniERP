# ADR 0060 · Confirmar lo que se crea con un diálogo, y los procesos largos por tandas

- **Fecha:** 2026-11-04
- **Versión:** v0.59.1
- **Estado:** aceptada

## Contexto

En Supabase, la empresa sintética de la v0.59.0 no aparecía en «Mis empresas». Generar un año (unos 460 asientos) en una
sola llamada superaba el límite de unos **8 segundos** que Supabase pone a cada llamada de la web («canceling statement
due to statement timeout»), y PostgreSQL deshacía todo, también la empresa. En local tardaba 3 segundos, y no lo
medimos contra ese límite, aunque ya estaba documentado en la migración 0029.

La web sí avisaba, pero **abajo del todo de la página**, debajo del formulario de «Nueva empresa», y Diosvely no lo vio.
De ahí su regla: **cuando se crea algo, el sistema tiene que confirmar si se hizo o no.**

## Decisión

1. **Un cuadro de diálogo común de confirmación** (`components/Notice.jsx`, `useNotice()`). Hay que cerrarlo con
   «Aceptar» o con Esc, y el foco va a su botón.
   - **Éxito:** qué se ha creado (por ejemplo, el nombre, los asientos y la huella), con una acción («Abrir la empresa»).
   - **Error:** la misma caja de error en lenguaje claro de siempre, dentro del diálogo.

   Se aplica ya a las cuatro formas de crear una empresa: nueva, caso, sintética e importación de un diario. Las demás
   acciones de crear o contabilizar (28 pantallas) se migran poco a poco: en cada versión nueva se dice cuáles se
   aprovechan.
2. **Red de seguridad para todas las pantallas:** la caja de error (`ErrorBox`) se desplaza sola a la vista cuando
   aparece.
3. **La empresa sintética, por tandas** (migración 0087):
   - `create_synthetic_company` crea y prepara la empresa y **guarda el plan** de operaciones (`erp.synthetic_plan`),
     en orden de fecha;
   - `synthetic_step(empresa, n)` ejecuta las n siguientes;
   - la web pide tandas de 25 y enseña el progreso («Generando… abril · 156 de 437 operaciones (35 %)»). Si una tanda
     se corta por tiempo, la repite con la mitad (hasta 5);
   - si se interrumpe, la empresa queda en la lista con «⏳ a medias» y se continúa desde su cabecera («Continuar la
     generación»);
   - `synthetic_run` hace todas las tandas seguidas, para el SQL Editor y las pruebas.

   El resultado es **exactamente** el de la v0.59.0 (las mismas huellas), así que la versión del generador sigue en
   `g1`.

## Alternativas descartadas
- **Subir el límite de 8 s del rol `authenticated`.** Afectaría a todas las pantallas y escondería el problema: una
  consulta lenta tiene que arreglarse, no esperar más.
- **Un aviso que desaparece solo** (como el *MessageToast* de SAP Fiori) para el éxito al crear. Diosvely pidió un
  diálogo que haya que cerrar: crear una empresa o contabilizar es una acción importante y tiene que quedar confirmada.
  El aviso breve queda para los cambios pequeños.
- **Migrar ya las 28 pantallas.** Es mucho cambio de golpe en pantallas que funcionan. Se hace poco a poco, con la red
  de seguridad mientras tanto.
- **Generar en segundo plano con `pg_cron`.** Funcionaría sin la web abierta, pero añade una cola y un estado más. Las
  tandas desde la web son lo mismo que ya hacen el borrado de empresas y la importación de diarios.

## Consecuencias
- **Medido:**
  - preparar tarda menos de 0,4 s;
  - la tanda de 25 más lenta, 0,4 s en local, muy por debajo de 8 s;
  - las cuatro huellas de la semilla 4817 son las de la v0.59.0.
- **Pruebas:** 81 de 81 en la base de datos y 321 tests de la web. La fase 81 comprueba:
  - las huellas de la v0.59.0;
  - con un límite de 1,5 s, de una vez se corta y por tandas no;
  - una tanda que falla no deja nada a medias y, al continuar, sale lo mismo;
  - otro usuario no genera ni ve el progreso de la empresa de otro.

  En la web, las tandas se adaptan (25 → 12 → 6) y los textos del diálogo coinciden en los dos idiomas. Se probó en un
  navegador (ordenador y móvil) con una base de datos de mentira que corta las tandas grandes.
- **Pendiente:** las 28 pantallas de «crear o contabilizar» (lista en el Project, `pendientes-visibilidad.md`).

## Cómo explicarlo
- **Por qué un límite de tiempo:** un servidor compartido no deja que una llamada ocupe la base de datos sin fin. Si
  pasa del límite, se corta y se deshace (atomicidad: o todo o nada).
- **Por qué tandas:** cada tanda es su propia transacción. Si una falla, las anteriores quedan hechas y se puede
  continuar. Es lo que hacen los procesos largos de un ERP: la cola de proyectos (*Job Queue*) de Business Central y
  los trabajos de fondo (*background jobs*) de SAP.
- **Confirmar lo que se crea:** una acción importante sin respuesta visible genera dudas («¿se hizo?») y repeticiones.
  El diálogo obliga a leer el resultado, como el *MessageBox* de SAP Fiori o los mensajes de Business Central.
- *(Pendiente de validar por Diosvely la equivalencia con BC y SAP.)*
