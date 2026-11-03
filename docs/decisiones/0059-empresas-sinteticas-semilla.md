# ADR 0059 · Empresas sintéticas con semilla: la misma contabilidad ficticia para todos, con su huella

- **Fecha:** 2026-11-03
- **Versión:** v0.59.0
- **Estado:** aceptada

## Contexto

El mismo comentario de LinkedIn que llevó a la v0.58.0 sugería probar con datos generados. Para el Mini ERP tiene tres
usos:
- **aprender:** cada alumno puede tener una empresa distinta y reproducible, y un profesor puede decir «semilla 4817»;
- **informar de errores sin datos reales.** El ADR 0010 no acepta contabilidades de empresas reales, así que hacía
  falta una forma de enseñar un fallo que otro pueda reproducir;
- **datos para las pruebas:** empresas grandes y variadas sin ficheros.

El diseño se validó antes de construir (`diseno-v0.59.0.md`), y Diosvely aceptó las seis propuestas:
- se crea como al importar;
- sin cierre del ejercicio;
- cuatro perfiles y cuatro incidencias;
- solo 2026;
- no se publica como demo.

## Decisión

1. **`erp.create_synthetic_company(semilla, perfil, meses)`** (migración 0086) crea la empresa y la llena **llamando a
   las funciones de cada módulo**, las mismas que usan las pantallas:
   - `post_invoice`, `post_payment`, `run_payroll` y `pay_payroll`;
   - `create_fixed_asset`, `loan_create` y `loan_payment`;
   - `post_depreciation` y `post_tax_settlement`.

   Si una función tiene un fallo, la empresa sintética lo enseña.
2. **Azar determinista:** cada número sale de `md5('semilla:n')` (`erp.syn_rand`), nunca de `random()`. El generador
   primero planifica todas las operaciones y después las ejecuta **en orden de fecha**. Así:
   - los números de asiento salen siempre iguales;
   - el banco nunca queda en negativo a mitad de año (el ERP lo bloquea).
3. **Cuatro perfiles:**
   - **servicios:** península, IVA, 111 y 115;
   - **comercio:** mayorista con clientes en recargo de equivalencia;
   - **taller:** Canarias, IGIC;
   - **incidencias:** el taller con cuatro errores sembrados (un proveedor deudor, un vencido de más de 90 días, un
     borrador descuadrado y el 2T sin liquidar).

   Los perfiles limpios cobran y pagan antes de vencer, así que su lista de control sale en verde.
4. **La huella** (`erp.company_fingerprint`) es `g1-` más 8 caracteres del md5 de cada asiento: número, fecha, estado,
   descripción, cuentas e importes, sin identificadores internos ni horas. `g1` es la versión del generador
   (`erp.synthetic_version`).
5. **Dónde se crea:** como al importar. Un registrado sin perfil, en una empresa temporal; un miembro o el
   propietario, permanente (cuenta en su límite). Un invitado no puede. Una sintética no se publica como demo
   (`set_company_demo`).
6. **Web:**
   - la tarjeta «Empresa sintética con semilla» en la lista de empresas;
   - la insignia 🎲 con la semilla;
   - en la cabecera, «Copiar datos para informar de un error»: versión, semilla, perfil, meses, huella, pantalla, fecha
     de trabajo e idioma, sin nada personal.

   La guía está en `docs/casos-sinteticos.md`, con las semillas de la comunidad.

## Alternativas descartadas
- **Insertar los asientos directamente** (más rápido). No probaría los módulos y podría crear contabilidades que el
  ERP nunca dejaría hacer.
- **`setseed()` + `random()`**, como la fase 34. Depende del orden de las llamadas en toda la sesión y de la versión de
  PostgreSQL; con un hash de la semilla y un contador, cada número es siempre el mismo.
- **Ejecutar las operaciones en el orden en que se piensan** (mes a mes, primero ventas y luego cobros). Un pago podía
  llegar antes que el cobro del que salía el dinero, y el bloqueo de saldos al revés lo paraba.
- **Comercio en recargo de equivalencia.** Una SL no puede estar en ese régimen (es de minoristas personas físicas);
  el perfil es el mayorista que vende a tiendas en recargo.
- **Generar también el cierre del ejercicio.** Se deja a quien aprende, como en el caso «hasta el cierre».

## Consecuencias
- **Medido:**
  - unos 460 asientos al año (395 en comercio), en unos 3 segundos;
  - las mismas huellas en dos bases de datos distintas;
  - un barrido de 12 semillas por perfil, con de 6 a 12 meses: los perfiles limpios, en verde; «incidencias», siempre
    exactamente lo sembrado.
- **Fallos encontrados al construir:**
  - el 111 y el 115 se pagaban juntos en la primera subcuenta 4751, que quedaba deudora (un saldo al revés). Ahora cada
    subcuenta se paga por separado;
  - el pago de más a un proveedor con facturas pendientes no daba saldo deudor. Ahora se paga dos veces la máquina.
- **La guardiana (fase 80) incluyó las 10 funciones nuevas sola** (277 en total) y no encontró fugas.
- **Limitaciones conocidas:**
  - solo 2026 (las cotizaciones de la Seguridad Social);
  - el mismo azar en todos los perfiles: «servicios» y «taller» con la misma semilla tienen las mismas bases de venta,
    y la guía lo aprovecha para comparar el IVA y el IGIC;
  - sin contabilidad mes a mes;
  - la huella cambia si la empresa se toca después de crearla.
- **Pruebas:** 81 de 81 en la base de datos y 316 tests de la web.
  - La fase 81 comprueba que la misma semilla da la misma huella (con todos los identificadores internos distintos) y
    que un céntimo la cambia.
  - En cada perfil: los invariantes, el Balance, que cada liquidación coincide con el libro, las cuentas y el tablero,
    y que las ventas coinciden con la PyG.
  - También la lista de control (limpia o exactamente lo sembrado), quién la crea, los límites y que no es una demo.

## Cómo explicarlo
- **Una semilla es una receta, no un fichero:** «4817, taller, 12 meses» ocupa una línea y da 463 asientos. Compartir la
  receta no comparte datos de nadie.
- **Pseudoaleatorio y determinista:** los números parecen al azar pero salen de una fórmula. Con la misma entrada, la
  misma salida; así se puede repetir un fallo.
- **La huella** es como el código de control de una factura: si cambia un céntimo, cambia la huella.
- **Probar con los caminos del usuario:** generar con las funciones de cada módulo es lo que hace un buen generador de
  datos de prueba en un ERP. Los datos «imposibles» no prueban nada.
- **En BC y SAP:** Business Central trae empresas de demostración (CRONUS) y la *Contoso Coffee Demo Data*; SAP, la
  empresa modelo y los datos de prueba de *SAP Best Practices*. Ninguna de las dos genera una contabilidad distinta
  para cada número. *(Pendiente de validar por Diosvely.)*
