// =====================================================================
// Genera docs/permisos.md desde la salida de la prueba de permisos (fase 79), para que el documento no se
// desactualice: lo que dice es lo que la prueba ha medido y exige.
// Uso (desde la raíz del proyecto):
//   scripts/test-db.sh fase79                                  → deja /tmp/test_fase79_permissions_matrix.log
//   node scripts/generar-permisos.mjs /tmp/test_fase79_permissions_matrix.log
// =====================================================================
import fs from 'node:fs'

const log = process.argv[2] ?? '/tmp/test_fase79_permissions_matrix.log'
if (!fs.existsSync(log)) {
  console.error(`✗ No encuentro ${log}: ejecuta antes scripts/test-db.sh fase79`)
  process.exit(1)
}
const texto = fs.readFileSync(log, 'utf8')
if (!texto.includes('FASE 79 OK')) {
  console.error('✗ La fase 79 no ha terminado bien: el documento no se genera con una prueba fallida')
  process.exit(1)
}
const bloque = texto.split('@@MATRIZ@@')[1]?.split('@@FIN@@')[0]
if (!bloque) { console.error('✗ No encuentro la matriz (@@MATRIZ@@ … @@FIN@@) en el log'); process.exit(1) }

const filas = bloque.trim().split('\n').slice(1).map((l) => {
  const [actor, empresa, grupo, accion, resultado, esperado] = l.split('|')
  return { actor, empresa, grupo, accion, resultado, esperado }
})

// ✓ lo hace (o lo para una regla contable, no un permiso) · ✗ no lo hace o no ve nada · — no aplica
const celda = (f) => (!f ? ' ' : f.esperado === '—' ? '—' : f.resultado.startsWith('sí') ? '✓' : '✗')
const buscar = (actor, empresa, accion) => filas.find((f) => f.actor === actor && f.empresa === empresa && f.accion === accion)

const COLUMNAS = [
  ['sin sesión', 'X', 'Sin sesión'],
  ['invitado de la demo', 'D', 'Invitado · demo'],
  ['invitado de la demo', 'X', 'Invitado · otra'],
  ['registrado sin acceso', 'D', 'Registrado · demo'],
  ['registrado sin acceso', 'X', 'Registrado · de otro'],
  ['solo lectura', 'X', 'Lector'],
  ['contable', 'X', 'Contable'],
  ['titular de los datos', 'X', 'Titular de los datos'],
  ['administrador', 'X', 'Administrador'],
  ['propietario (su empresa)', 'X', 'Propietario · suya'],
  ['propietario (empresa ajena)', 'Z', 'Propietario · de otro'],
  ['dueño de la temporal', 'T', 'Dueño de su temporal'],
]
const acciones = [...new Map(filas.filter((f) => ['X', 'D', 'Z'].includes(f.empresa) && f.actor !== 'Power BI')
  .map((f) => [f.accion, f.grupo])).entries()]

const tabla = (cabecera, lineas) =>
  [`| ${cabecera.join(' | ')} |`, `|${cabecera.map(() => '---').join('|')}|`, ...lineas.map((l) => `| ${l.join(' | ')} |`)].join('\n')

const empresa = tabla(['Grupo', 'Acción', ...COLUMNAS.map((c) => c[2])],
  acciones.map(([accion, grupo]) => [grupo, accion, ...COLUMNAS.map(([a, e]) => celda(buscar(a, e, accion)))]))

const FUERA = [['sin sesión', 'Sin sesión'], ['invitado de la demo', 'Invitado'], ['registrado sin acceso', 'Registrado'],
  ['solo lectura', 'Lector de otra empresa'], ['propietario (su empresa)', 'Propietario'], ['dueño de la temporal', 'Dueño de una temporal']]
const fueraAcciones = [...new Map(filas.filter((f) => ['Importar', 'Casos', 'Mantenimiento'].includes(f.grupo))
  .map((f) => [f.accion, f.grupo])).entries()]
// «la temporal T» es la del dueño de la temporal: para él es lo suyo; para los demás, la de otro
const fuera = tabla(['Grupo', 'Acción', ...FUERA.map((c) => c[1])],
  fueraAcciones.map(([accion, grupo]) => [grupo, accion, ...FUERA.map(([a]) =>
    celda(filas.find((f) => f.actor === a && f.accion === accion)))]))

const bi = filas.filter((f) => f.actor === 'Power BI').map((f) => `- ${f.accion}: ${celda(f)}`).join('\n')
const intentos = filas.length
const guardiana = fs.existsSync('/tmp/test_fase80_permissions_guardian.log')
  ? (fs.readFileSync('/tmp/test_fase80_permissions_guardian.log', 'utf8').match(/OK  · (\d+) funciones, (\d+) llamadas/) ?? null)
  : null

const md = `# Permisos: quién puede hacer qué

> **Generado desde la prueba** (\`database/tests/test_fase79_permissions_matrix.sql\`) con
> \`node scripts/generar-permisos.mjs\`. No se edita a mano: si cambia un permiso, cambia la prueba y se vuelve a generar.
> Versión v0.58.0 · ${intentos} intentos, cada uno deshecho al terminar.

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

${empresa}

## Fuera de una empresa

«La temporal T» es la empresa temporal del dueño de la temporal: para él es lo suyo; para los demás, la de otro.

${fuera}

## Power BI (\`powerbi_reader\`)

${bi}

Solo lee el esquema \`bi\`, que enseña las empresas demo.

## Cómo se comprueba

- **Fase 79 (esta matriz):** cada actor intenta cada acción y la prueba exige el resultado de \`public.esperado\`.
- **Fase 80 (la guardiana):** tres atacantes (un registrado sin acceso, un invitado y el propietario de la aplicación)
  llaman a **todas** las funciones del ERP que puede ejecutar una sesión con los identificadores de las empresas de otro
  usuario${guardiana ? ` (${guardiana[1]} funciones; ${guardiana[2]} llamadas, contando las de control)` : ''}. Hay fuga si cambia algo de esas
  empresas, si enseña un identificador suyo que no se le dio o si responde con datos distintos de los que daría ante
  identificadores que no existen. Como control, la víctima hace las mismas llamadas y ve o cambia lo suyo. Una función
  nueva entra sola en la prueba.
`

fs.writeFileSync('docs/permisos.md', md)
console.log(`✓ docs/permisos.md (${intentos} intentos, ${acciones.length + fueraAcciones.length} acciones)`)
