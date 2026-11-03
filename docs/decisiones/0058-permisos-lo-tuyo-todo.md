# ADR 0058 · Permisos: «lo tuyo, todo; lo de otro, nada», con la matriz y la prueba guardiana

- **Fecha:** 2026-11-03
- **Versión:** v0.58.0
- **Estado:** aceptada

## Contexto

Al anunciar el Mini ERP en LinkedIn con sus roles, un comentario propuso comprobar que «cada rol vea y modifique solo
lo previsto, también al importar datos y consultar la IA». Hasta ahora cada pantalla se había probado por separado, pero
no había una matriz completa de quién puede hacer qué, ni nada que vigilara las funciones nuevas.

Lo normal en una empresa real es la **separación de funciones**: quien hace la nómina no la paga. Diosvely lo descartó
para este ERP (03-11-2026): es para **aprender haciendo el ciclo completo** (ADR 0010), y un rol que impidiera cerrar el
ejercicio o usar la IA dejaría el ciclo a medias. Su criterio: **cada persona es dueña absoluta de su información y
nadie puede entrar en la información de otro usuario.**

Se hizo en tres pasos: medir sin cambiar nada (283), fijar y arreglar (284) y publicar (285).

## Decisión

1. **Dos reglas:**
   - **lo tuyo, todo.** Quien crea una empresa queda como su administrador y en ella lo hace todo: contabilizar,
     cerrar, configurar, importar, borrar y usar la IA. Lo mismo en su empresa temporal mientras no caduque;
   - **lo de otro, nada.** Ni un registrado, ni un invitado, ni el propietario de la aplicación ven o tocan la empresa
     de otro usuario, por ningún camino.

   Las demos son solo para ver. Los roles contable y lectura solo sirven para compartir una empresa del propietario.
2. **La IA para quien administra** (migración 0085, `erp.ai_allowed`), con la cuota diaria que ya había: 10 consultas
   los miembros, 5 los registrados y sin límite el propietario. Antes solo la usaban el propietario, el titular de los
   datos y el creador de una temporal. La decisión fue de Diosvely: si hay muchos usuarios, el producto gusta; si no,
   quien entra tiene la IA.
3. **El propietario, solo en sus empresas** (`erp.can_manage_access`):
   - ver quién entra, dar y quitar accesos;
   - publicar como demo (`set_company_demo`);
   - leer las opiniones sobre la IA (`ai_feedback`).
4. **Lo que se cierra:**
   - `erp.temp_cleanup`: solo la limpieza programada (sin sesión), el propietario o la propia importación, que deja una
     marca en su transacción (`set_config`, que la web no puede llamar);
   - `erp.fiscal_year_company`: dice de qué empresa es un ejercicio solo a quien puede leerla;
   - sin sesión (`anon`), ninguna función del ERP: había 28 abiertas por el permiso por defecto de PostgreSQL
     (`PUBLIC`). Las de disparador se quitan a todos, porque no necesitan el permiso para dispararse.
5. **Dos pruebas:**
   - **fase 79, la matriz:** diez actores frente a 27 acciones (348 intentos, cada uno deshecho al terminar), y lo que
     se exige está escrito en `public.esperado`;
   - **fase 80, la guardiana:** tres atacantes llaman a **todas** las funciones que puede ejecutar una sesión (267) con
     los identificadores de las empresas de otro usuario.

   Hay fuga en tres casos:
   - si cambia algo de esas empresas (una huella de todas sus filas, antes y después);
   - si enseña un identificador suyo que no se le dio;
   - si responde con datos distintos de los que daría ante identificadores que no existen.

   Como control, la víctima hace las mismas llamadas y ve o cambia lo suyo en más de 100 funciones. Si una función
   nueva tiene un parámetro que la prueba no conoce, falla hasta que se le dice qué identificador le corresponde.
6. **Publicar sin que se desactualice:**
   - `docs/permisos.md` lo genera `scripts/generar-permisos.mjs` desde la salida de la fase 79;
   - la pantalla Accesos enseña «qué puede hacer cada rol» (`src/roles.js`), y un test de la web comprueba que dice lo
     mismo que `docs/permisos.md`.

## Alternativas descartadas
- **Separación de funciones por rol**, como en una empresa real (por ejemplo, un contable que no pueda cerrar ni pagar
  lo que contabiliza). Es lo correcto en producción, pero aquí impediría ver el ciclo completo, que es el objetivo.
- **Clasificar a mano cada función** (lectura, escritura, administración, interna) y probar cada clase. Con 267
  funciones, la lista se quedaría atrás en la siguiente versión. Comparar con «una empresa que no existe» no necesita
  saber qué hace cada función.
- **Que el propietario lo vea todo** para dar soporte. Sería cómodo, pero rompe «lo de otro, nada»: una cuenta con
  todos los datos es el primer objetivo de un atacante. Si alguien necesita ayuda, puede compartir su empresa.
- **Revocar por defecto (`alter default privileges`) todas las funciones nuevas.** Es más estricto, pero una función nueva
  quedaría sin permiso para la web sin que nadie lo notara. La guardiana falla si sin sesión se puede ejecutar algo, y
  la migración lo quita explícitamente.

## Consecuencias
- **Fallos encontrados:**
  - la medición (paso 283) encontró los permisos sobrantes, la IA del administrador y la limpieza abierta;
  - la guardiana encontró que el propietario podía entrar en la empresa de otro (accesos, demo y opiniones) y la
    función de los ejercicios;
  - también encontró un fallo en la primera versión del propio arreglo: `is_owner() and my_role(...) = 'admin'` daba
    NULL sin rol, y `if not NULL` no entra, así que dejaba pasar. Es la misma trampa que la restricción de la v0.55.0;
    ahora es `coalesce(…, false)`.
- **Error de la medición, no del ERP:** «el dueño de la temporal no tiene IA» salía porque ese usuario de prueba tenía
  perfil de miembro, y su importación era permanente.
- **Se mantienen** los roles para compartir: el contable ve y contabiliza, pero cierra y configura quien administra.
  Para el ciclo completo en una empresa compartida, se da «Administrador».
- **Limitaciones conocidas:**
  - la guardiana llama con valores de prueba fijos (un año, un importe, una fecha). Una función que valide algo antes
    de comprobar el permiso responde con un error igual al de la empresa que no existe, así que no se cuenta como fuga,
    pero tampoco prueba su permiso. Por eso existe el control de la víctima;
  - `docs/permisos.md` se regenera a mano tras la fase 79; si se olvida, el test de la web avisa en cuanto la tabla de
    roles y el documento no coinciden.
- **Pruebas:** 80 de 80 en la base de datos y 306 tests de la web. Sin la migración 0085:
  - la fase 79 falla en 10 filas;
  - la 80 falla porque sin sesión se pueden ejecutar 28 funciones; con la migración a medias (sin los apartados de
    los accesos y de los ejercicios) encontró 8 fugas.
  - Las fases 24 y 66 cambian: antes exigían que el administrador no usara la IA.

## Cómo explicarlo
- **Separación de funciones:** en una empresa real, quien registra, quien autoriza y quien paga son personas distintas,
  para que un error o un fraude necesite a dos. En un ERP de estudio, la misma persona hace los tres papeles para
  entender cómo encajan.
- **Aislamiento entre usuarios** (*multitenancy*): cada empresa es de quien la crea, y la base de datos lo comprueba en
  cada fila (RLS) y en cada función. La web nunca es la única barrera.
- **Mínimo privilegio:** sin sesión no se ejecuta nada, y una función interna no se abre «por si acaso».
- **Una empresa que no existe como referencia:** si lo que ve un extraño de tu empresa es lo mismo que vería de una
  empresa inventada, no ha visto nada tuyo.
- **NULL en una condición de seguridad:** en SQL, `true and NULL` es NULL, y `if not NULL` no entra. Una comprobación
  de permiso tiene que convertir el NULL en «no» (`coalesce`).
- **En BC y SAP:** Business Central separa las empresas por *Company* y los permisos por *Permission Sets*; los
  auditores revisan la separación de funciones con informes de conflictos (*SoD*). SAP S/4HANA hace lo mismo con los
  roles PFCG, los *authorization objects* y SAP GRC Access Control. *(Pendiente de validar por Diosvely.)*
