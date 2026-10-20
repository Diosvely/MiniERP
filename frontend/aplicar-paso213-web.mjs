// Paso 213 · v0.41.0 · Impuesto sobre Sociedades integrado: glosario, fuente, paso del asistente de cierre, avisos y nombres de módulo
// Cambia solo los trozos necesarios (con unas líneas de contexto) y crea los ficheros nuevos.
// Uso (desde la carpeta frontend):   node aplicar-paso213-web.mjs
// Se puede ejecutar dos veces sin problema. Si algo no encaja, lo dice y no toca ese trozo.
import fs from 'node:fs'

const NEW_FILES = {}
const EDITS = [
  [
    "src/controlled.js",
    "  if (m.includes('payroll')) return 'payroll'   // v0.38.0\n  if (m.includes('accruals') || m.includes('impairments') || m.includes('provisions') || m.includes('inventory')) return 'adjustments'   // v0.36.0 / v0.37.0\n",
    "  if (m.includes('payroll')) return 'payroll'   // v0.38.0\n  if (m.includes('corporate_tax')) return 'corporate_tax'   // v0.41.0\n  if (m.includes('accruals') || m.includes('impairments') || m.includes('provisions') || m.includes('inventory')) return 'adjustments'   // v0.36.0 / v0.37.0\n"
  ],
  [
    "src/glossary.js",
    "    en: { term: 'Operation catalogue', def: 'The typical operations of a company (purchase, sale, collection, payroll, depreciation…) with the ERP screen where each is recorded and its model entry. In a real ERP the screen picks the accounts: you only enter the details of the operation.', ex: 'A supplier invoice is recorded in Invoices, not with a manual entry: the ERP posts 600 / 472 to 400.' } },\n}\n",
    "    en: { term: 'Operation catalogue', def: 'The typical operations of a company (purchase, sale, collection, payroll, depreciation…) with the ERP screen where each is recorded and its model entry. In a real ERP the screen picks the accounts: you only enter the details of the operation.', ex: 'A supplier invoice is recorded in Invoices, not with a manual entry: the ERP posts 600 / 472 to 400.' } },\n  // v0.41.0 · Impuesto sobre Sociedades\n  taxableBase: { bc: 'Corporate income tax base (not standard: local add-ons)', sap: 'Taxable income (tax provision)', pgc: ['630', '4752'],\n    es: { term: 'Base imponible', def: 'El beneficio sobre el que se paga el Impuesto sobre Sociedades: el resultado contable más o menos los ajustes de lo que la ley del impuesto no deja deducir o deja deducir en otro año (art. 10.3 LIS), menos las bases negativas de años anteriores.', ex: 'Resultado 182.000 + multa 1.000 + exceso de amortización 2.600 = base 185.600.' },\n    en: { term: 'Taxable base', def: 'The profit on which corporate income tax is paid: the accounting profit plus or minus the adjustments for what the tax law does not allow to deduct, or allows in another year (art. 10.3 LIS), less tax losses from previous years.', ex: 'Profit 182,000 + fine 1,000 + excess depreciation 2,600 = base 185,600.' } },\n  temporaryDifference: { bc: 'Deferred tax (temporary difference)', sap: 'Temporary difference (deferred taxes)', pgc: ['4740', '479'],\n    es: { term: 'Diferencia temporaria', def: 'Un gasto o un ingreso que la contabilidad y el impuesto reconocen en años distintos: hoy no se deduce, pero se deducirá (o al revés). Genera un impuesto diferido; a diferencia de la permanente (una multa), revierte.', ex: 'Amortización contable 5.000 y fiscal 2.400: 2.600 se deducirán en los años siguientes.' },\n    en: { term: 'Temporary difference', def: 'An expense or income recognised by the accounts and by the tax in different years: not deductible today but deductible later (or the other way round). It creates a deferred tax; unlike a permanent difference (a fine), it reverses.', ex: 'Accounting depreciation 5,000 and tax depreciation 2,400: 2,600 will be deducted in the following years.' } },\n  currentTax: { bc: 'Corporate income tax expense (current)', sap: 'Current income tax', pgc: ['6300', '4752', '4709', '473'],\n    es: { term: 'Impuesto corriente', def: 'El Impuesto sobre Sociedades que corresponde pagar por el ejercicio: la cuota íntegra. Se carga a la 6300; lo ya retenido o pagado a cuenta (473) se descuenta y queda la cuota diferencial, a pagar (4752) o a devolver (4709).', ex: 'Cuota 37.976 con 10.000 pagados a cuenta: 6300 D 37.976 / 473 H 10.000 · 4752 H 27.976.' },\n    en: { term: 'Current tax', def: 'The corporate income tax payable for the year: the gross tax. It is charged to 6300; what was withheld or paid on account (473) is deducted, leaving the amount payable (4752) or refundable (4709).', ex: 'Tax 37,976 with 10,000 paid on account: 6300 Dr 37,976 / 473 Cr 10,000 · 4752 Cr 27,976.' } },\n  deferredTax: { bc: 'Deferred tax', sap: 'Deferred taxes', pgc: ['6301', '4740', '4745', '479'],\n    es: { term: 'Impuesto diferido', def: 'La parte del gasto por impuesto que se paga en otros años por las diferencias temporarias y las bases negativas (PGC, NRV 13.ª). Con él, el gasto del año no depende de cuándo se paga: activo 4740 / 4745 o pasivo 479 contra la 6301.', ex: 'Diferencia temporaria de 2.600 al 21 %: 4740 D 546 / 6301 H 546.' },\n    en: { term: 'Deferred tax', def: 'The part of the tax expense paid in other years because of temporary differences and tax losses (PGC, NRV 13.ª). With it, the expense of the year does not depend on when it is paid: asset 4740 / 4745 or liability 479 against 6301.', ex: 'Temporary difference of 2,600 at 21 %: 4740 Dr 546 / 6301 Cr 546.' } },\n}\n"
  ],
  [
    "src/glossary.js",
    "  withholdings: 'withholding', payments: 'openItem', prorata: 'prorata', taxes: 'vat', balance: 'balance', pyg: 'pyg',\n  cashflow: 'cashflow', ratios: 'ratio', reports: 'trialBalance', checks: 'auditCheck', forms: 'taxForm', assets: 'fixedAsset', adjustments: 'deferral', payroll: 'payroll', accounts: 'subaccount', partners: 'partner',\n}\n",
    "  withholdings: 'withholding', payments: 'openItem', prorata: 'prorata', taxes: 'vat', balance: 'balance', pyg: 'pyg',\n  cashflow: 'cashflow', ratios: 'ratio', reports: 'trialBalance', checks: 'auditCheck', forms: 'taxForm', corporate_tax: 'taxableBase', assets: 'fixedAsset', adjustments: 'deferral', payroll: 'payroll', accounts: 'subaccount', partners: 'partner',\n}\n"
  ],
  [
    "src/i18n/en.js",
    "    next_year_closed: 'Fiscal year {d} is closed.',\n  },\n",
    "    next_year_closed: 'Fiscal year {d} is closed.',\n    corporate_tax_missing: 'The corporate income tax of {d} is missing: it goes before closing the income statement (the tax expense is part of the result). Calculate and post it in Corporate tax.',\n    withholdings_left: '{d} (withholdings and payments on account) is not zero after the tax: a payment on account was recorded after posting it. Undo it and post it again.',\n  },\n"
  ],
  [
    "src/i18n/en.js",
    "    or: ' or ',\n    module: { invoices: 'Invoices', payments: 'Payments', settlement: 'the Settlement', assets: 'Fixed assets', accruals: 'Year-end adjustments (accruals)', impairments: 'Year-end adjustments (impairment)', provisions: 'Year-end adjustments (provisions)', inventory: 'Year-end adjustments (inventory)' },\n  },\n",
    "    or: ' or ',\n    module: { invoices: 'Invoices', payments: 'Payments', settlement: 'the Settlement', assets: 'Fixed assets', accruals: 'Year-end adjustments (accruals)', impairments: 'Year-end adjustments (impairment)', provisions: 'Year-end adjustments (provisions)', inventory: 'Year-end adjustments (inventory)', payroll: 'Payroll', corporate_tax: 'Corporate income tax' },\n  },\n"
  ],
  [
    "src/i18n/en.js",
    "      audit_checks: { title: 'Auditor checks', done: 'All green.', pending: '{n} with warning or error: review them in Checks.' },\n      close: { title: 'Close the year', done: 'Closed.', pending: 'When everything else is done: closing and opening entries (below).' },\n",
    "      audit_checks: { title: 'Auditor checks', done: 'All green.', pending: '{n} with warning or error: review them in Checks.' },\n      corporate_tax: { title: 'Corporate income tax', done: 'Posted.', pending: 'Calculate and post it before closing the income statement: the tax expense is part of the result.', na: 'No result: there is no tax to post.' },\n      close: { title: 'Close the year', done: 'Closed.', pending: 'When everything else is done: closing and opening entries (below).' },\n"
  ],
  [
    "src/i18n/es.js",
    "    provisions_not_reviewed: 'Provisiones sin revisar este ejercicio: {d}. Revísalas en Ajustes de cierre con la estimación del cierre.',\n    result_account_created: 'Se creará la subcuenta {d} Resultado del ejercicio.',\n",
    "    provisions_not_reviewed: 'Provisiones sin revisar este ejercicio: {d}. Revísalas en Ajustes de cierre con la estimación del cierre.',\n    corporate_tax_missing: 'Falta el Impuesto sobre Sociedades de {d}: va antes de la regularización (el gasto por impuesto es parte del resultado). Calcúlalo y contabilízalo en Impuesto sobre Sociedades.',\n    withholdings_left: 'La {d} (retenciones y pagos a cuenta) no ha quedado a cero después del impuesto: hay un pago a cuenta registrado después de contabilizarlo. Deshazlo y vuelve a contabilizarlo.',\n    result_account_created: 'Se creará la subcuenta {d} Resultado del ejercicio.',\n"
  ],
  [
    "src/i18n/es.js",
    "    or: ' o ',\n    module: { invoices: 'Facturas', payments: 'Cobros y pagos', settlement: 'la Liquidación', assets: 'Inmovilizado', accruals: 'Ajustes de cierre (periodificaciones)', impairments: 'Ajustes de cierre (deterioro)', provisions: 'Ajustes de cierre (provisiones)', inventory: 'Ajustes de cierre (inventario)' },\n  },\n",
    "    or: ' o ',\n    module: { invoices: 'Facturas', payments: 'Cobros y pagos', settlement: 'la Liquidación', assets: 'Inmovilizado', accruals: 'Ajustes de cierre (periodificaciones)', impairments: 'Ajustes de cierre (deterioro)', provisions: 'Ajustes de cierre (provisiones)', inventory: 'Ajustes de cierre (inventario)', payroll: 'Nóminas', corporate_tax: 'Impuesto sobre Sociedades' },\n  },\n"
  ],
  [
    "src/i18n/es.js",
    "      audit_checks: { title: 'Comprobaciones del auditor', done: 'Todas en verde.', pending: '{n} con aviso o error: revísalas en Comprobaciones.' },\n      close: { title: 'Cerrar el ejercicio', done: 'Cerrado.', pending: 'Cuando lo demás esté hecho: regularización, cierre y apertura (abajo).' },\n",
    "      audit_checks: { title: 'Comprobaciones del auditor', done: 'Todas en verde.', pending: '{n} con aviso o error: revísalas en Comprobaciones.' },\n      corporate_tax: { title: 'Impuesto sobre Sociedades', done: 'Contabilizado.', pending: 'Calcúlalo y contabilízalo antes de la regularización: el gasto por impuesto forma parte del resultado.', na: 'Sin resultado: no hay impuesto que contabilizar.' },\n      close: { title: 'Cerrar el ejercicio', done: 'Cerrado.', pending: 'Cuando lo demás esté hecho: regularización, cierre y apertura (abajo).' },\n"
  ],
  [
    "src/sources.js",
    "  lis: {\n    issuer: 'BOE', checked: '2026-10-19',\n    url: 'https://www.boe.es/eli/es/l/2014/11/27/27/con',\n",
    "  lis: {\n    issuer: 'BOE', checked: '2026-10-20',\n    url: 'https://www.boe.es/eli/es/l/2014/11/27/27/con',\n"
  ],
  [
    "src/sources.js",
    "    url: 'https://www.boe.es/eli/es/l/2014/11/27/27/con',\n    es: { title: 'Ley 27/2014, del Impuesto sobre Sociedades', ref: 'Arts. 12 (amortizaciones) y 13 (deterioros y provisiones)' },\n    en: { title: 'Law 27/2014 on Corporate Income Tax', ref: 'Arts. 12 (depreciation) and 13 (impairments and provisions)' },\n  },\n",
    "    url: 'https://www.boe.es/eli/es/l/2014/11/27/27/con',\n    es: { title: 'Ley 27/2014, del Impuesto sobre Sociedades', ref: 'Arts. 10 a 15 (base imponible, amortizaciones, deterioros, provisiones y gastos no deducibles), 26 (bases negativas), 29 y DT 44.ª (tipos) y 101 y 104 (reducida dimensión)' },\n    en: { title: 'Law 27/2014 on Corporate Income Tax', ref: 'Arts. 10 to 15 (taxable base, depreciation, impairments, provisions and non-deductible expenses), 26 (tax losses), 29 and DT 44.ª (rates) and 101 and 104 (reduced size)' },\n  },\n"
  ],
  [
    "tests/corporateTax.test.js",
    "import es from '../src/i18n/es.js'\n\n",
    "import es from '../src/i18n/es.js'\nimport en from '../src/i18n/en.js'\nimport fs from 'node:fs'\nimport { fileURLToPath } from 'node:url'\n\n"
  ],
  [
    "tests/corporateTax.test.js",
    "  })\n})\n",
    "  })\n})\n\n// v0.41.0 · Integración: cada módulo que controla cuentas (erp.control_rules) tiene su nombre en los avisos\n// («La 630 la registra …»). Antes faltaba el de Nóminas y el aviso enseñaba la clave «ctl.module.payroll».\ndescribe('cuentas controladas: nombre de cada módulo', () => {\n  const dir = fileURLToPath(new URL('../../database/migrations', import.meta.url))\n  const modules = new Set()\n  if (fs.existsSync(dir)) {\n    for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.sql'))) {\n      for (const m of fs.readFileSync(`${dir}/${f}`, 'utf8').matchAll(/'\\{([a-z_,]+)\\}', '(?:both|debit|credit)'/g)) {\n        m[1].split(',').forEach((x) => modules.add(x))\n      }\n    }\n  }\n  it.skipIf(!modules.size)('es y en tienen todos (también corporate_tax y payroll)', () => {\n    expect(modules.has('corporate_tax')).toBe(true)\n    for (const m of modules) {\n      expect(es.ctl.module[m], `es: ${m}`).toBeTruthy()\n      expect(en.ctl.module[m], `en: ${m}`).toBeTruthy()\n    }\n  })\n  it('el paso del asistente y los avisos del cierre tienen texto', () => {\n    for (const d of [es, en]) {\n      expect(d.wiz.step.corporate_tax.pending).toBeTruthy()\n      expect(d.check.corporate_tax_missing).toContain('{d}')\n      expect(d.check.withholdings_left).toContain('{d}')\n    }\n  })\n})\n"
  ]
]

let warnings = 0
const read = (f) => fs.readFileSync(f, 'utf8')
// Trabaja con saltos de línea \n y respeta los \r\n del fichero si los tiene (Windows)
const edit = (f, fn) => {
  const raw = read(f)
  const crlf = raw.includes('\r\n')
  const before = raw.replace(/\r\n/g, '\n')
  const after = fn(before)
  if (after !== before) fs.writeFileSync(f, crlf ? after.replace(/\n/g, '\r\n') : after)
}

for (const [f, content] of Object.entries(NEW_FILES)) {
  if (fs.existsSync(f) && read(f).replace(/\r\n/g, '\n') === content) console.log(`· ${f} ya estaba`)
  else { fs.writeFileSync(f, content); console.log(`✓ ${f} creado`) }
}

for (const [f, from, to] of EDITS) {
  edit(f, (s) => {
    if (s.includes(to)) { console.log(`· ${f}: ya estaba cambiado`); return s }
    if (!s.includes(from)) { warnings++; console.log(`⚠ ${f}: no encuentro el trozo que empieza por:\n    ${from.split('\n')[0].trim()}`); return s }
    console.log(`✓ ${f}: ${from.split('\n')[0].trim().slice(0, 70)}…`)
    return s.replace(from, to)
  })
}


console.log(warnings ? `\n⚠ ${warnings} aviso(s): pásame el mensaje y lo vemos.` : '\n✔ Paso 213 aplicado. Ahora: npm run lint · npm test · npm run build')
