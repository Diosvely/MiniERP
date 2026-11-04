# Permisos: quién puede hacer qué

> **Generado desde la prueba** (`database/tests/test_fase79_permissions_matrix.sql`) con
> `node scripts/generar-permisos.mjs`. No se edita a mano: si cambia un permiso, cambia la prueba y se vuelve a generar.
> Versión v0.58.0 · 348 intentos, cada uno deshecho al terminar.

## Las dos reglas

El Mini ERP es para **aprender haciendo el ciclo completo**, no para llevar una empresa real (ADR 0010). Por eso no hay
separación de funciones: **cada persona es dueña absoluta de su información** y **nadie entra en la información de otro
usuario** (ADR 0058).

1. **Lo tuyo, todo.** Quien crea una empresa queda como su **administrador** y en ella lo hace todo: asientos, facturas,
   liquidaciones, cierre, configuración, importar, borrarla y usar la IA (con su cuota diaria). Lo mismo en su empresa
   temporal mientras no caduque.
2. **Lo de otro, nada.** Ni un registrado, ni un invitado, ni el propietario de la aplicación ven o tocan la empresa de
   otro usuario, por ningún camino: pantallas, funciones internas, importaciones o IA.

Además:
- **Las demos, solo para ver.** Cualquiera con sesión (también un invitado) las lee; nadie las cambia desde la web.
- **Los roles para compartir.** Solo existen cuando el propietario de la aplicación comparte una empresa suya:
  el **lector** ve; el **contable** ve y contabiliza, pero cierra y configura quien administra; el **titular de los
  datos** (un contable al que pertenecen los datos) además usa la IA y puede publicar la empresa como demo. Para que
  alguien haga el ciclo completo en una empresa compartida, se le da «administrador».
- **Dar y quitar accesos:** el propietario de la aplicación, solo en las empresas que administra.
- **Sin sesión, nada:** ninguna función del ERP y ninguna tabla.

## Sobre una empresa

✓ lo hace (o lo para una regla contable, no un permiso) · ✗ no lo hace o no ve nada · — no aplica (en una temporal
recién empezada aún no hay asientos)

Las columnas «demo» son una empresa de demostración; «de otro» u «otra», una empresa en la que ese usuario no tiene
ningún rol.

| Grupo | Acción | Sin sesión | Invitado · demo | Invitado · otra | Registrado · demo | Registrado · de otro | Lector | Contable | Titular de los datos | Administrador | Propietario · suya | Propietario · de otro | Dueño de su temporal |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ver | ver la empresa | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| Ver | diario | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | — |
| Ver | facturas | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | — |
| Ver | balance | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | — |
| Ver | tablero | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| Ver | comprobaciones | ✗ | ✓ | ✗ | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| Ver | quién tiene acceso | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| Escribir | crear un borrador | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| Escribir | contabilizar un borrador | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | — |
| Escribir | anular un asiento | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | — |
| Escribir | crear una subcuenta | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| Escribir | registrar una factura | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| Escribir | liquidar el 1T | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ |
| Cerrar | cerrar el ejercicio | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ |
| Cerrar | reabrir el mes | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ |
| Configurar | modo de control | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ |
| Configurar | forma jurídica | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ |
| Accesos | dar acceso a otro | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| Accesos | quitar un acceso | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| Accesos | borrar la empresa | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ |
| IA | Analista: datos para la IA | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ |
| IA | Analista: gastar una consulta | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ |
| IA | Tutor: datos para la IA | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ | ✗ | ✓ |

## Fuera de una empresa

«La temporal T» es la empresa temporal del dueño de la temporal: para él es lo suyo; para los demás, la de otro.

| Grupo | Acción | Sin sesión | Invitado | Registrado | Lector de otra empresa | Propietario | Dueño de una temporal |
|---|---|---|---|---|---|---|---|
| Importar | empezar una importación propia | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ |
| Importar | preparar la importación de la temporal T | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Casos | cargar el caso Taller Atlántico | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ |
| Mantenimiento | limpiar empresas temporales caducadas | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |

## Power BI (`powerbi_reader`)

- esquema erp (empresas): ✗
- esquema bi (empresas demo): ✓

Solo lee el esquema `bi`, que enseña las empresas demo.

## Cómo se comprueba

- **Fase 79 (esta matriz):** cada actor intenta cada acción y la prueba exige el resultado de `public.esperado`.
- **Fase 80 (la guardiana):** tres atacantes (un registrado sin acceso, un invitado y el propietario de la aplicación)
  llaman a **todas** las funciones del ERP que puede ejecutar una sesión con los identificadores de las empresas de otro
  usuario (280 funciones; 1651 llamadas, contando las de control). Hay fuga si cambia algo de esas
  empresas, si enseña un identificador suyo que no se le dio o si responde con datos distintos de los que daría ante
  identificadores que no existen. Como control, la víctima hace las mismas llamadas y ve o cambia lo suyo. Una función
  nueva entra sola en la prueba.
