// Paso 222 · v0.42.0 · Operaciones societarias integradas: glosario, LSC, avisos, módulo en el diario, facturas a la 113 y la 113 en el impuesto
// Cambia solo los trozos necesarios (con unas líneas de contexto) y crea los ficheros nuevos.
// Uso (desde la carpeta frontend):   node aplicar-paso222-web.mjs
// Se puede ejecutar dos veces sin problema. Si algo no encaja, lo dice y no toca ese trozo.
import fs from 'node:fs'

const NEW_FILES = {}
const EDITS = [
  [
    "src/components/GeneralJournal.jsx",
    "              {e.source === 'corporate_tax' && <span className=\"etiqueta\">{t('sourceCorporateTax')}</span>}\n              {e.reversal_of_no && <span className=\"etiqueta anula\">↩ {t('reversesEntry').replace('{n}', e.reversal_of_no)}</span>}\n",
    "              {e.source === 'corporate_tax' && <span className=\"etiqueta\">{t('sourceCorporateTax')}</span>}\n              {e.source === 'equity' && <span className=\"etiqueta\">{t('sourceEquity')}</span>}\n              {e.reversal_of_no && <span className=\"etiqueta anula\">↩ {t('reversesEntry').replace('{n}', e.reversal_of_no)}</span>}\n"
  ],
  [
    "src/components/InvoiceForm.jsx",
    "      setPartners(p.data.filter((r) => !r.blocked))\n      setAccounts(a.data.filter((r) => groups.includes(r.account_no[0])))\n      // Primero los tipos con cuota (de mayor a menor) y después las operaciones sin cuota con su causa\n",
    "      setPartners(p.data.filter((r) => !r.blocked))\n      // v0.42.0: en las recibidas, también la 113 (gastos de constitución o de ampliación de capital, contra reservas)\n      setAccounts(a.data.filter((r) => groups.includes(r.account_no[0]) || (purchase && r.account_no.startsWith('113'))))\n      // Primero los tipos con cuota (de mayor a menor) y después las operaciones sin cuota con su causa\n"
  ],
  [
    "src/controlled.js",
    "  if (m.includes('corporate_tax')) return 'corporate_tax'   // v0.41.0\n  if (m.includes('accruals') || m.includes('impairments') || m.includes('provisions') || m.includes('inventory')) return 'adjustments'   // v0.36.0 / v0.37.0\n",
    "  if (m.includes('corporate_tax')) return 'corporate_tax'   // v0.41.0\n  if (m.includes('equity')) return 'equity'   // v0.42.0\n  if (m.includes('accruals') || m.includes('impairments') || m.includes('provisions') || m.includes('inventory')) return 'adjustments'   // v0.36.0 / v0.37.0\n"
  ],
  [
    "src/corporateTax.js",
    "  if (r(c.current_tax) > 0) current.push(line('6300', r(c.current_tax), 0))\n  if (r(c.withholdings) !== 0) current.push(line('473', Math.max(-r(c.withholdings), 0), Math.max(r(c.withholdings), 0)))\n",
    "  if (r(c.current_tax) > 0) current.push(line('6300', r(c.current_tax), 0))\n  // v0.42.0: el impuesto que ahorran los gastos cargados a reservas, a reservas\n  if (r(c.equity_tax_effect) > 0) current.push(line('113', 0, r(c.equity_tax_effect)))\n  if (r(c.withholdings) !== 0) current.push(line('473', Math.max(-r(c.withholdings), 0), Math.max(r(c.withholdings), 0)))\n"
  ],
  [
    "src/errors.js",
    "  [/^This entry belongs to an invoice/, 'entryFromInvoice', 'invoices'],\n  // v0.41.0 · Impuesto sobre Sociedades\n",
    "  [/^This entry belongs to an invoice/, 'entryFromInvoice', 'invoices'],\n  // v0.42.0 · Operaciones societarias\n  [/^This entry belongs to an equity operation/, 'entryFromEquity', 'equity'],\n  // v0.41.0 · Impuesto sobre Sociedades\n"
  ],
  [
    "src/glossary.js",
    "    en: { term: 'Deferred tax', def: 'The part of the tax expense paid in other years because of temporary differences and tax losses (PGC, NRV 13.ª). With it, the expense of the year does not depend on when it is paid: asset 4740 / 4745 or liability 479 against 6301.', ex: 'Temporary difference of 2,600 at 21 %: 4740 Dr 546 / 6301 Cr 546.' } },\n}\n",
    "    en: { term: 'Deferred tax', def: 'The part of the tax expense paid in other years because of temporary differences and tax losses (PGC, NRV 13.ª). With it, the expense of the year does not depend on when it is paid: asset 4740 / 4745 or liability 479 against 6301.', ex: 'Temporary difference of 2,600 at 21 %: 4740 Dr 546 / 6301 Cr 546.' } },\n  // v0.42.0 · Operaciones societarias\n  legalReserve: { bc: 'Legal reserve (G/L account)', sap: 'Legal reserve (equity account)', pgc: ['112'],\n    es: { term: 'Reserva legal', def: 'La parte del beneficio que la ley obliga a guardar: el 10 % hasta que llegue al 20 % del capital (art. 274 LSC); en una SL de menos de 3.000 € de capital, al menos el 20 % hasta que capital y reserva sumen 3.000 (art. 4.2). No se reparte como dividendo.', ex: 'Capital 30.000, reserva 4.000, beneficio 50.000: 10 % = 5.000, pero solo faltan 2.000 para el 20 % → 112 H 2.000.' },\n    en: { term: 'Legal reserve', def: 'The part of the profit the law requires to keep: 10 % until it reaches 20 % of the share capital (art. 274 LSC); in an SL with less than €3,000 of capital, at least 20 % until capital and reserve add up to 3,000 (art. 4.2). It is not paid out as dividends.', ex: 'Capital 30,000, reserve 4,000, profit 50,000: 10 % = 5,000, but only 2,000 is missing to reach 20 % → 112 Cr 2,000.' } },\n  interimDividend: { bc: 'Interim dividend (G/L account)', sap: 'Interim dividend', pgc: ['557', '526'],\n    es: { term: 'Dividendo a cuenta', def: 'Dividendo que se paga antes de que la junta apruebe las cuentas, a cuenta del beneficio del año. Solo hasta el resultado desde el último cierre menos las pérdidas anteriores, la reserva legal y el impuesto estimado, y con liquidez (art. 277 LSC). La 557 resta del patrimonio neto hasta la junta.', ex: 'Resultado a 30/09: 40.000; impuesto 10.000; reserva 3.000 → máximo 27.000. Acuerdo: 557 D 20.000 / 526 H 20.000.' },\n    en: { term: 'Interim dividend', def: 'A dividend paid before the general meeting approves the accounts, on account of the profit of the year. Only up to the result since the last year end less prior losses, the legal reserve and the estimated tax, and with enough cash (art. 277 LSC). Account 557 reduces equity until the meeting.', ex: 'Result at 30/09: 40,000; tax 10,000; reserve 3,000 → maximum 27,000. Resolution: 557 Dr 20,000 / 526 Cr 20,000.' } },\n  sharePremium: { bc: 'Share premium (G/L account)', sap: 'Capital reserve (share premium)', pgc: ['110'],\n    es: { term: 'Prima de emisión', def: 'Lo que pagan los socios por encima del valor nominal al suscribir acciones o participaciones nuevas (110). Es patrimonio neto, no capital: compensa a los socios antiguos por las reservas que ya había.', ex: 'Acciones de 10 € de nominal emitidas a 12 €: por cada una, 10 a la 100 y 2 a la 110.' },\n    en: { term: 'Share premium', def: 'What shareholders pay above the nominal value when subscribing new shares (110). It is equity, not share capital: it compensates existing shareholders for the reserves already accumulated.', ex: 'Shares of €10 nominal issued at €12: for each one, 10 to 100 and 2 to 110.' } },\n  uncalledCapital: { bc: 'Uncalled share capital', sap: 'Subscribed capital unpaid', pgc: ['1030', '5580', '190', '194'],\n    es: { term: 'Desembolsos pendientes', def: 'Capital suscrito que los socios aún no han pagado. En la SA puede quedar pendiente hasta el 75 % (art. 79 LSC); en la SL, no. No exigido: 1030 (resta del patrimonio neto); exigido y sin cobrar: 5580 (un derecho de cobro).', ex: 'SA de 60.000 con el 25 % pagado: 572 D 15.000 · 1030 D 45.000 / 190 H 60.000.' },\n    en: { term: 'Uncalled share capital', def: 'Subscribed capital that shareholders have not paid yet. In an SA up to 75 % can remain unpaid (art. 79 LSC); not in an SL. Not called: 1030 (reduces equity); called and unpaid: 5580 (a receivable).', ex: 'SA of 60,000 with 25 % paid: 572 Dr 15,000 · 1030 Dr 45,000 / 190 Cr 60,000.' } },\n}\n"
  ],
  [
    "src/glossary.js",
    "  withholdings: 'withholding', payments: 'openItem', prorata: 'prorata', taxes: 'vat', balance: 'balance', pyg: 'pyg',\n  cashflow: 'cashflow', ratios: 'ratio', reports: 'trialBalance', checks: 'auditCheck', forms: 'taxForm', corporate_tax: 'taxableBase', assets: 'fixedAsset', adjustments: 'deferral', payroll: 'payroll', accounts: 'subaccount', partners: 'partner',\n}\n",
    "  withholdings: 'withholding', payments: 'openItem', prorata: 'prorata', taxes: 'vat', balance: 'balance', pyg: 'pyg',\n  cashflow: 'cashflow', ratios: 'ratio', reports: 'trialBalance', checks: 'auditCheck', forms: 'taxForm', corporate_tax: 'taxableBase', equity: 'legalReserve', assets: 'fixedAsset', adjustments: 'deferral', payroll: 'payroll', accounts: 'subaccount', partners: 'partner',\n}\n"
  ],
  [
    "src/i18n/en.js",
    "    corporate_tax_missing: 'The corporate income tax of {d} is missing: it goes before closing the income statement (the tax expense is part of the result). Calculate and post it in Corporate tax.',\n    withholdings_left: '{d} (withholdings and payments on account) is not zero after the tax: a payment on account was recorded after posting it. Undo it and post it again.',\n",
    "    corporate_tax_missing: 'The corporate income tax of {d} is missing: it goes before closing the income statement (the tax expense is part of the result). Calculate and post it in Corporate tax.',\n    result_not_distributed: 'Last year\\'s result ({d}) is still in 129: the general meeting has not distributed it yet. Record it in Equity operations (legal reserve, dividends and reserves) before closing this year.',\n    withholdings_left: '{d} (withholdings and payments on account) is not zero after the tax: a payment on account was recorded after posting it. Undo it and post it again.',\n"
  ],
  [
    "src/i18n/en.js",
    "  sourceCorporateTax: 'Corporate income tax',\n\n",
    "  sourceCorporateTax: 'Corporate income tax',\n  sourceEquity: 'Equity operation',\n\n"
  ],
  [
    "src/i18n/en.js",
    "    or: ' or ',\n    module: { invoices: 'Invoices', payments: 'Payments', settlement: 'the Settlement', assets: 'Fixed assets', accruals: 'Year-end adjustments (accruals)', impairments: 'Year-end adjustments (impairment)', provisions: 'Year-end adjustments (provisions)', inventory: 'Year-end adjustments (inventory)', payroll: 'Payroll', corporate_tax: 'Corporate income tax' },\n  },\n",
    "    or: ' or ',\n    module: { invoices: 'Invoices', payments: 'Payments', settlement: 'the Settlement', assets: 'Fixed assets', accruals: 'Year-end adjustments (accruals)', impairments: 'Year-end adjustments (impairment)', provisions: 'Year-end adjustments (provisions)', inventory: 'Year-end adjustments (inventory)', payroll: 'Payroll', corporate_tax: 'Corporate income tax', equity: 'Equity operations' },\n  },\n"
  ],
  [
    "src/i18n/en.js",
    "      partner: 'Partner', pending: 'Open invoices', balance: 'Balance', difference: 'Difference', expected: 'Should be', reclass: 'Reclassify to' },\n    source: { manual: 'Manual', import: 'Imported', invoice: 'Invoice', settlement: 'Settlement', pro_rata: 'Pro rata', payment: 'Payment', asset: 'Fixed assets', accrual: 'Accrual', impairment: 'Impairment', provision: 'Provision', inventory: 'Inventory', payroll: 'Payroll', corporate_tax: 'Corporate income tax' },\n    nature: { debit: 'Debit', credit: 'Credit', mixed: 'Either' },\n",
    "      partner: 'Partner', pending: 'Open invoices', balance: 'Balance', difference: 'Difference', expected: 'Should be', reclass: 'Reclassify to' },\n    source: { manual: 'Manual', import: 'Imported', invoice: 'Invoice', settlement: 'Settlement', pro_rata: 'Pro rata', payment: 'Payment', asset: 'Fixed assets', accrual: 'Accrual', impairment: 'Impairment', provision: 'Provision', inventory: 'Inventory', payroll: 'Payroll', corporate_tax: 'Corporate income tax', equity: 'Equity operation' },\n    nature: { debit: 'Debit', credit: 'Credit', mixed: 'Either' },\n"
  ],
  [
    "src/i18n/en.js",
    "    entryFromInvoice: { title: 'This entry belongs to an invoice', hint: 'To correct it, register a credit memo so the tax register and the books still match.' },\n    entryFromCorporateTax: { title: 'This entry belongs to the corporate income tax', hint: 'Undo it from its screen: «Undo the tax» cancels both entries at once.' },\n",
    "    entryFromInvoice: { title: 'This entry belongs to an invoice', hint: 'To correct it, register a credit memo so the tax register and the books still match.' },\n    entryFromEquity: { title: 'This entry belongs to an equity operation', hint: 'Undo it from Equity operations, from the last one.' },\n    entryFromCorporateTax: { title: 'This entry belongs to the corporate income tax', hint: 'Undo it from its screen: «Undo the tax» cancels both entries at once.' },\n"
  ],
  [
    "src/i18n/es.js",
    "    corporate_tax_missing: 'Falta el Impuesto sobre Sociedades de {d}: va antes de la regularización (el gasto por impuesto es parte del resultado). Calcúlalo y contabilízalo en Impuesto sobre Sociedades.',\n    withholdings_left: 'La {d} (retenciones y pagos a cuenta) no ha quedado a cero después del impuesto: hay un pago a cuenta registrado después de contabilizarlo. Deshazlo y vuelve a contabilizarlo.',\n",
    "    corporate_tax_missing: 'Falta el Impuesto sobre Sociedades de {d}: va antes de la regularización (el gasto por impuesto es parte del resultado). Calcúlalo y contabilízalo en Impuesto sobre Sociedades.',\n    result_not_distributed: 'El resultado del año anterior ({d}) sigue en la 129: la junta aún no lo ha repartido. Regístralo en Operaciones societarias (reserva legal, dividendos y reservas) antes de cerrar este año.',\n    withholdings_left: 'La {d} (retenciones y pagos a cuenta) no ha quedado a cero después del impuesto: hay un pago a cuenta registrado después de contabilizarlo. Deshazlo y vuelve a contabilizarlo.',\n"
  ],
  [
    "src/i18n/es.js",
    "  sourceCorporateTax: 'Impuesto sobre Sociedades',\n\n",
    "  sourceCorporateTax: 'Impuesto sobre Sociedades',\n  sourceEquity: 'Operación societaria',\n\n"
  ],
  [
    "src/i18n/es.js",
    "    or: ' o ',\n    module: { invoices: 'Facturas', payments: 'Cobros y pagos', settlement: 'la Liquidación', assets: 'Inmovilizado', accruals: 'Ajustes de cierre (periodificaciones)', impairments: 'Ajustes de cierre (deterioro)', provisions: 'Ajustes de cierre (provisiones)', inventory: 'Ajustes de cierre (inventario)', payroll: 'Nóminas', corporate_tax: 'Impuesto sobre Sociedades' },\n  },\n",
    "    or: ' o ',\n    module: { invoices: 'Facturas', payments: 'Cobros y pagos', settlement: 'la Liquidación', assets: 'Inmovilizado', accruals: 'Ajustes de cierre (periodificaciones)', impairments: 'Ajustes de cierre (deterioro)', provisions: 'Ajustes de cierre (provisiones)', inventory: 'Ajustes de cierre (inventario)', payroll: 'Nóminas', corporate_tax: 'Impuesto sobre Sociedades', equity: 'Operaciones societarias' },\n  },\n"
  ],
  [
    "src/i18n/es.js",
    "      partner: 'Tercero', pending: 'Facturas pendientes', balance: 'Saldo', difference: 'Diferencia', expected: 'Debería ser', reclass: 'Reclasificar a' },\n    source: { manual: 'Manual', import: 'Importado', invoice: 'Factura', settlement: 'Liquidación', pro_rata: 'Prorrata', payment: 'Pago', asset: 'Inmovilizado', accrual: 'Periodificación', impairment: 'Deterioro', provision: 'Provisión', inventory: 'Inventario', payroll: 'Nómina', corporate_tax: 'Impuesto sobre Sociedades' },\n    nature: { debit: 'Deudor', credit: 'Acreedor', mixed: 'Cualquiera' },\n",
    "      partner: 'Tercero', pending: 'Facturas pendientes', balance: 'Saldo', difference: 'Diferencia', expected: 'Debería ser', reclass: 'Reclasificar a' },\n    source: { manual: 'Manual', import: 'Importado', invoice: 'Factura', settlement: 'Liquidación', pro_rata: 'Prorrata', payment: 'Pago', asset: 'Inmovilizado', accrual: 'Periodificación', impairment: 'Deterioro', provision: 'Provisión', inventory: 'Inventario', payroll: 'Nómina', corporate_tax: 'Impuesto sobre Sociedades', equity: 'Operación societaria' },\n    nature: { debit: 'Deudor', credit: 'Acreedor', mixed: 'Cualquiera' },\n"
  ],
  [
    "src/i18n/es.js",
    "    entryFromInvoice: { title: 'Este asiento es de una factura', hint: 'Para corregirlo, registra una factura rectificativa: así el libro registro y la contabilidad siguen cuadrando.' },\n    entryFromCorporateTax: { title: 'Este asiento es del Impuesto sobre Sociedades', hint: 'Se deshace desde su pantalla: «Deshacer el impuesto» anula sus dos asientos a la vez.' },\n",
    "    entryFromInvoice: { title: 'Este asiento es de una factura', hint: 'Para corregirlo, registra una factura rectificativa: así el libro registro y la contabilidad siguen cuadrando.' },\n    entryFromEquity: { title: 'Este asiento es de una operación societaria', hint: 'Se deshace desde Operaciones societarias, de la última a la primera.' },\n    entryFromCorporateTax: { title: 'Este asiento es del Impuesto sobre Sociedades', hint: 'Se deshace desde su pantalla: «Deshacer el impuesto» anula sus dos asientos a la vez.' },\n"
  ],
  [
    "src/sources.js",
    "  },\n  lirpf: {\n",
    "  },\n  lsc: {\n    issuer: 'BOE', checked: '2026-10-21',\n    url: 'https://www.boe.es/eli/es/rdlg/2010/07/02/1/con',\n    es: { title: 'Real Decreto Legislativo 1/2010, Ley de Sociedades de Capital', ref: 'Arts. 4 (capital mínimo; SL de menos de 3.000 €, Ley 18/2022), 78 y 79 (desembolso), 273, 274 y 277 (reparto, reserva legal y dividendo a cuenta), 295 a 304 (aumento) y 317 a 322 (reducción por pérdidas)' },\n    en: { title: 'Royal Legislative Decree 1/2010, Spanish Companies Act (LSC)', ref: 'Arts. 4 (minimum capital; SL under €3,000, Law 18/2022), 78 and 79 (payment), 273, 274 and 277 (distribution, legal reserve and interim dividend), 295 to 304 (increase) and 317 to 322 (reduction for losses)' },\n  },\n  lirpf: {\n"
  ],
  [
    "tests/corporateTax.test.js",
    "    }\n  })\n})\n",
    "    }\n  })\n})\n\n// v0.42.0 · Gastos de constitución en la 113: el ahorro de impuesto va a reservas (las mismas cifras que la fase 56)\ndescribe('Impuesto sobre Sociedades · gastos cargados a reservas', () => {\n  const c = { current_tax: 25000, equity_tax_effect: 300, withholdings: 0, differential: 24700, deferred_tax: 0, deferred_rate: 25,\n    temporary_increase: 0, temporary_decrease: 0, loss_credit: 0, loss_credit_used: 0 }\n  it('6300 25.000 / 113 300 · 4752 24.700, y cuadra', () => {\n    const { current } = entriesPreview(c)\n    expect(current).toEqual([{ account: '6300', debit: 25000, credit: 0 }, { account: '113', debit: 0, credit: 300 }, { account: '4752', debit: 0, credit: 24700 }])\n    expect(balanced(current)).toBe(true)\n  })\n})\n"
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


console.log(warnings ? `\n⚠ ${warnings} aviso(s): pásame el mensaje y lo vemos.` : '\n✔ Paso 222 aplicado. Ahora: npm run lint · npm test · npm run build')
