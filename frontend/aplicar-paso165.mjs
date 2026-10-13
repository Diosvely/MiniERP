// Paso 165 · Cierre de la v0.31.0: ADR 0029, CHANGELOG, bitácora y README
// Uso (desde la carpeta RAÍZ del proyecto, no desde frontend):   node aplicar-paso165.mjs
// Se puede ejecutar dos veces sin problema: lo que ya está hecho no se repite. Si algo no encaja, lo dice.
import fs from 'node:fs'

const ADR_PATH = 'docs/decisiones/0029-ia-guiada-por-reglas-y-uso-de-la-web.md'
const ADR = "# ADR 0029 · IA guiada por reglas (retenciones) y panel de uso de la web\n\n- **Fecha:** 2026-10-13\n- **Versión:** v0.31.0\n- **Estado:** aceptada\n\n## Contexto\n\n1. **La IA no aplicaba la retención.** Probando el Tutor con «factura de una abogada autónoma por 1.000 € en\n   Canarias», la IA acertaba el IGIC (el ERP le da los tipos de la empresa y recalcula la cuota) pero **nunca**\n   practicaba la retención del 15 %. Las instrucciones solo decían «retenciones: role withholding», sin regla de\n   cuándo ni de cuánto, y el ERP no la recalculaba. No era un fallo puntual del modelo: era una regla contable que\n   dependía de que el modelo «se acordara».\n2. **No se sabía cuánta gente probaba la demo.** Al difundir la web hacía falta medirlo. Además, la limpieza\n   nocturna de invitados (0028) borraba a los de más de 7 días, así que contando usuarios se perdía la historia.\n\n## Decisión\n\n### 1. La IA clasifica, la base de datos contabiliza (migración 0033)\nEs el mismo reparto que en los ERP grandes: los **grupos contables** de Business Central o la **determinación de\ncuentas** de SAP (OBYC) deciden las cuentas a partir de datos maestros, no del texto.\n\n- **La ficha del tercero manda**, como el maestro del acreedor en SAP:\n  - **forma jurídica**, que por defecto sale del NIF (NIF / NIE → persona física; CIF → entidad);\n  - **retención por defecto** (IRPF15, IRPF7, IRPF19).\n\n  La base de datos rechaza lo que no tiene sentido: la retención de profesionales a una entidad, o cualquier\n  retención a un cliente.\n- **Reglas de retención como datos** (`erp.withholding_rules`):\n  - 623 profesionales: IRPF15 / IRPF7 si es persona física;\n  - 621 alquiler de local: IRPF19.\n\n  La IA las recibe en su contexto y el ERP las comprueba. Una regla nueva es una fila nueva, no código nuevo.\n- **El ERP calcula, como ya hacía con el IVA:**\n  - el código: el de la ficha, si no el de la línea, si no el de la regla del gasto;\n  - la cuenta: la 4751 / 473 configurada;\n  - el importe: base × tipo.\n\n  Si corrige un importe, ajusta la línea del tercero para que cuadre (1.000 + 70 − 150 = 920). Solo lo hace si hay\n  una única línea de tercero; un descuadre que no viene de una corrección del ERP no se tapa.\n- **Avisos:** «gasto con retención sin ella», «la ficha dice IRPF15 y el asiento no la lleva», «retención de\n  profesionales a una entidad». Los de nivel aviso hacen que la IA corrija en una segunda vuelta. El del alquiler es\n  solo informativo, porque el *renting* de una furgoneta no lleva retención.\n- **La factura recibida** toma la retención de la ficha del tercero al elegirlo.\n\n### 2. Panel «Uso de la web», solo para el propietario (migración 0034)\n- `erp.web_usage(días)`:\n  - **solo cifras agregadas**: visitantes de la demo (usuarios anónimos), registros, activos de la semana, empresas,\n    importaciones y consultas a la IA;\n  - sin correos y sin contar al propietario;\n  - días en hora de Canarias.\n- `erp.cleanup_guests` guarda en `erp.guest_history` cuántos invitados había cada día **antes** de borrarlos. Así,\n  los totales y la serie diaria no cambian con la limpieza.\n- **Visualización, con el criterio de «menos es más»:** 4 cifras y un único gráfico de barras (visitantes por día),\n  con tooltip y «Ver como tabla». Los registros van en el tooltip y en la tabla, no en una segunda serie.\n- Lo que pasa **antes** de pulsar la demo (visitas a la portada, procedencia) queda para Cloudflare Web Analytics:\n  sin cookies y sin código.\n\n## Alternativas descartadas\n- **Arreglar solo las instrucciones de la IA:** ayuda, pero sigue dependiendo de que el modelo obedezca. Se hace\n  también, pero el control está en la base de datos.\n- **Que el ERP añada la línea de retención por su cuenta:** no se sabe si la abogada es persona física hasta que lo\n  dice la ficha o el texto. Se avisa y se deja decidir (a la IA en la segunda vuelta, y al usuario al final).\n- **Rastreo propio de visitas (tabla de eventos, cookies):** innecesario. Los usuarios anónimos ya son el recuento, y\n  la RGPD se complica.\n\n## Consecuencias\n- El Tutor deja de alucinar en el caso de las retenciones. Es la **fase 1** del plan «IA guiada por reglas»\n  (`ideas-pendientes.md`). Las siguientes fases van en el mismo sentido: catálogo de operaciones, controles de auditor\n  como datos, banco de casos y, al final, una ontología contable con chat.\n- **Nuevos datos en la ficha del tercero** (`legal_form`, `withholding_code`) y en la vista `v_partners`.\n- **Pruebas:** 28 de 28 en la base de datos (fases 27 y 28 nuevas, y las dos fallan sin su migración) y 83 tests de la\n  web.\n"
const CHANGELOG = "## [0.31.0] - 2026-10-13\n### Añadido\n- **Retenciones guiadas por reglas:**\n  - ficha del tercero con **forma jurídica** (sale del NIF) y **retención por defecto**;\n  - reglas de retención en la base de datos (`erp.withholding_rules`: 623 profesionales, 621 alquiler);\n  - el ERP calcula en el Tutor la retención y lo que queda a pagar al tercero;\n  - avisos de retención que falta o que no procede;\n  - migración `0033_withholding_rules.sql` y prueba `test_fase27_withholding_rules.sql`.\n- La **factura recibida** toma la retención de la ficha del tercero.\n- **Panel «Uso de la web»** solo para el propietario: visitantes de la demo, registros, activos, empresas,\n  importaciones y consultas a la IA, con barras por día. Migración `0034_web_usage.sql` y prueba\n  `test_fase28_web_usage.sql`.\n- `src/partnerTax.js` y `barPath` en `src/chart.js`, con sus tests (83 en total).\n### Cambiado\n- **Tutor de asientos:**\n  - instrucciones con las reglas de retención y un ejemplo resuelto;\n  - la IA indica el código de la retención;\n  - los avisos informativos ya no provocan una segunda vuelta.\n### Corregido\n- La limpieza nocturna de invitados ya no hace perder la historia de visitas a la demo (`erp.guest_history`).\n- Dos desplegables sin etiqueta en Terceros, y el territorio, que se salía de la tarjeta en el móvil.\n"
const BITACORA = "\n## 2026-10-13 · v0.31.0 · IA guiada por reglas (retenciones) y panel de uso de la web\n\n**Qué se hizo**\n- **Retenciones guiadas por reglas** (migración 0033):\n  - la ficha del tercero manda (forma jurídica y retención por defecto);\n  - las reglas de cuándo hay retención están en la base de datos;\n  - el ERP calcula la retención y lo que queda a pagar;\n  - la IA corrige en una segunda vuelta si falta la retención.\n- **Factura recibida** con la retención de la ficha del tercero.\n- **Panel «Uso de la web»** (migración 0034): visitantes de la demo, registros y uso, solo para el propietario. Con\n  la historia a salvo de la limpieza nocturna.\n- 28 pruebas SQL (fases 27 y 28 nuevas) y 83 tests de la web.\n\n**Lo que se aprende en esta fase**\n- **Por qué alucina una IA en contabilidad:** acertaba el IGIC porque el ERP lo restringía y lo recalculaba, y fallaba\n  el IRPF porque nadie lo hacía. Lo que no está en una regla queda al azar del modelo.\n- **La IA clasifica, la base de datos contabiliza:** como los grupos contables de BC o la determinación de cuentas\n  de SAP. La IA entiende la operación; las cuentas, los tipos y los importes salen de datos maestros y reglas.\n- **La retención en la factura:** profesional persona física 15 % (7 % en inicio de actividad), alquiler de local\n  19 %. Se calcula sobre la base, sin impuesto, y el tercero cobra base + impuesto − retención: 1.000 + 70 − 150 = 920.\n  Una SL que presta servicios profesionales no lleva retención.\n- **El NIF dice la forma jurídica:** un NIF o NIE es de una persona física; un CIF, de una entidad.\n- **Medir sin rastrear:** los usuarios anónimos de la demo ya son el recuento. Al borrar datos, antes se guarda lo\n  que se quiere seguir midiendo.\n\n**Decisiones:** ADR 0029 · IA guiada por reglas (retenciones) y panel de uso de la web.\n\n**Siguiente paso:** usar el ERP con contabilidad real y anotar cada fallo de la IA: cada uno será una regla o un caso\nde prueba de las fases 2 a 4. Después, el **Inmovilizado**.\n"
const README = [
  [
    "## ¿Qué hace hoy? (v0.30.0)",
    "## ¿Qué hace hoy? (v0.31.0)"
  ],
  [
    "  - **Tú decides** si cargarlo en el formulario.\n",
    "  - **Retenciones con reglas de la base de datos:** la ficha del tercero (persona física o entidad, retención por\n    defecto) manda, y el ERP calcula la retención y lo que queda a pagar (1.000 + 70 − 150 = 920). La IA clasifica;\n    la base de datos contabiliza.\n  - **Tú decides** si cargarlo en el formulario.\n"
  ],
  [
    "- **Español / inglés** con selector de bandera, en móvil y en ordenador.\n",
    "- **Español / inglés** con selector de bandera, en móvil y en ordenador.\n- **Uso de la web** solo para el propietario: visitantes de la demo, registros y activos por día, sin datos personales.\n"
  ],
  [
    "26 pruebas SQL, 75 tests de la web",
    "28 pruebas SQL, 83 tests de la web"
  ],
  [
    "0001 → 0032,",
    "0001 → 0034,"
  ],
  [
    "`database/migrations/0001` … `0032`",
    "`database/migrations/0001` … `0034`"
  ],
  [
    "ADR 0001 → 0028",
    "ADR 0001 → 0029"
  ],
  [
    "las 26 pruebas de la base de datos",
    "las 28 pruebas de la base de datos"
  ],
  [
    "**75 tests de la web con Vitest**",
    "**83 tests de la web con Vitest**"
  ],
  [
    "# las 26 pruebas, cada una en una base limpia",
    "# las 28 pruebas, cada una en una base limpia"
  ],
  [
    "# 75 tests con Vitest",
    "# 83 tests con Vitest"
  ],
  [
    "- [x] **v0.30.0**: Inicio con indicadores, Balance y PyG comparativos, cascada del EFE, evolución de ratios, Excel e imprimir\n",
    "- [x] **v0.30.0**: Inicio con indicadores, Balance y PyG comparativos, cascada del EFE, evolución de ratios, Excel e imprimir\n- [x] **v0.31.0**: IA guiada por reglas (retenciones calculadas por el ERP desde la ficha del tercero) y panel de uso de la web\n"
  ]
]

let avisos = 0
const leer = (p) => fs.readFileSync(p, 'utf8')
const crlf = (s) => s.includes('\r\n')
const guardar = (p, texto, conCrlf) => fs.writeFileSync(p, conCrlf ? texto.replace(/\r?\n/g, '\r\n') : texto)

if (!fs.existsSync('README.md') || !fs.existsSync('docs')) {
  console.error('✗ Ejecútalo desde la carpeta raíz del proyecto (donde están README.md y docs).'); process.exit(1)
}

// 1. ADR nuevo
if (fs.existsSync(ADR_PATH)) console.log('· ADR 0029 ya existía')
else { fs.writeFileSync(ADR_PATH, ADR); console.log('✓ ' + ADR_PATH) }

// 2. CHANGELOG: la versión nueva va arriba, antes de la 0.30.0
{
  const raw = leer('CHANGELOG.md'), c = crlf(raw), s = raw.replace(/\r\n/g, '\n')
  if (s.includes('## [0.31.0]')) console.log('· CHANGELOG ya tenía la 0.31.0')
  else if (s.includes('## [0.30.0]')) { guardar('CHANGELOG.md', s.replace('## [0.30.0]', CHANGELOG + '\n## [0.30.0]'), c); console.log('✓ CHANGELOG.md') }
  else { avisos++; console.log('⚠ CHANGELOG.md: no encuentro "## [0.30.0]"; pega a mano el texto de la 0.31.0 arriba') }
}

// 3. Bitácora: la entrada nueva va al final
{
  const raw = leer('docs/bitacora.md'), c = crlf(raw), s = raw.replace(/\r\n/g, '\n')
  if (s.includes('· v0.31.0 ·')) console.log('· La bitácora ya tenía la v0.31.0')
  else { guardar('docs/bitacora.md', s.replace(/\n*$/, '\n') + BITACORA, c); console.log('✓ docs/bitacora.md') }
}

// 4. README: versión, IA, plataforma, cifras de pruebas y hoja de ruta
{
  const raw = leer('README.md'), c = crlf(raw)
  let s = raw.replace(/\r\n/g, '\n')
  for (const [de, a] of README) {
    if (s.includes(a)) continue
    if (!s.includes(de)) { avisos++; console.log('⚠ README.md: no encuentro «' + de.trim().slice(0, 70) + '»'); continue }
    s = s.replace(de, a)
  }
  guardar('README.md', s, c); console.log('✓ README.md')
}

console.log(avisos ? `\nHecho con ${avisos} aviso(s): revísalos.` : '\n✔ Paso 165 aplicado. Revisa los cambios con: git diff')
