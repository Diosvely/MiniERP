import { money } from './format'

// ERRORES EN LENGUAJE CLARO
// La base de datos protege las reglas contables y, cuando algo no se puede hacer, responde con un mensaje técnico en
// inglés ("Unbalanced entry: debit 100 ≠ credit 90 (difference 10)"). Aquí se reconoce cada mensaje con un patrón,
// se sacan sus datos ({1}, {2}…) y se traduce a: QUÉ HA PASADO (title) + QUÉ HACER (hint) + DÓNDE ARREGLARLO (to).
//   [patrón, clave del i18n (err.<clave>.title / .hint), pantalla donde se arregla (opcional)]
// Si un mensaje no se reconoce, se muestra tal cual (muchos ya vienen traducidos por la propia pantalla).
const RULES = [
  // Ejercicios y periodos
  [/^No fiscal year for (?:date )?(.+)$/, 'noFiscalYear', 'closing'],
  [/^Posting date (.+) is outside fiscal year (.+)$/, 'dateOutsideYear'],
  [/^Fiscal year (.+) is already closed$/, 'yearAlreadyClosed', 'closing'],
  [/^Fiscal year (.+) is closed$/, 'yearClosed', 'closing'],
  [/^Period (.+) of (.+) is closed$/, 'periodClosed', 'closing'],
  [/^Reopen fiscal year (.+) first$/, 'reopenFirst', 'closing'],
  [/^Fiscal year (\S+) does not exist$/, 'yearMissing', 'closing'],
  [/^Fiscal year (.+) cannot be closed: (.+)$/, 'cannotClose'],
  [/^Review and accept the warnings before closing/, 'acceptWarnings'],

  // Asientos
  [/^Unbalanced entry: debit (.+) ≠ credit (.+) \(difference (.+)\)$/, 'unbalanced'],
  [/^An entry needs at least 2 lines/, 'twoLines'],
  [/^Entry (.+?) is posted(?: and cannot be (?:changed|deleted)|: its lines cannot be changed)/, 'postedImmutable', 'journal'],
  [/^Entry (.+) is already reversed$/, 'alreadyReversed', 'journal'],
  [/^A reversal entry cannot be reversed$/, 'reverseOfReverse'],
  [/^Only posted entries can be reversed/, 'draftReverse'],
  [/^The reversal date cannot be earlier than the original entry \((.+)\)$/, 'reversalDate'],
  [/^This entry belongs to an invoice/, 'entryFromInvoice', 'invoices'],
  [/^This entry belongs to a tax settlement/, 'entryFromSettlement', 'settlement'],
  [/^This entry belongs to a year-end closing/, 'entryFromClosing', 'closing'],
  [/^This entry is a pro rata regularization/, 'entryFromProRata', 'prorata'],

  // Cuentas
  [/^Line (\d+): account (\S+) is a heading account$/, 'lineHeadingAccount', 'accounts'],
  [/^Account (\S+)(?: \(.+\))? is a heading account/, 'headingAccount', 'accounts'],
  [/^Line (\d+): account (\S+) does not exist$/, 'lineAccountMissing', 'accounts'],
  [/^Account (\S+) is blocked$/, 'accountBlocked', 'accounts'],
  [/^Account (\S+) \((.+)\) would have a (\S+) balance of (\S+) on (\S+): it is blocked for inverse balances$/, 'inverseBlocked', 'reports'],
  [/^Posting account (\S+) must have (\d+) digits$/, 'digits'],
  [/^Posting account (\S+) does not belong to any PGC account/, 'noPgcParent'],
  [/^No free accounts left under (\S+)$/, 'noFreeAccounts', 'accounts'],
  [/^Account (\S+) already belongs to another partner$/, 'accountTaken', 'partners'],

  // Terceros
  [/^Invalid Spanish tax ID \(NIF\/NIE\/CIF\): (.+)$/, 'invalidTaxId'],
  [/^A (\S+) with tax ID (\S+) already exists/, 'partnerDuplicate', 'partners'],
  [/^Partner (.+) is blocked$/, 'partnerBlocked', 'partners'],
  [/^Partner (.+) has no posting account$/, 'partnerNoAccount', 'partners'],
  [/^Partner name is required$/, 'partnerName'],
  [/^Account (\S+) must start with (\S+) for this partner type$/, 'partnerAccountPrefix'],

  // Facturas
  [/^Invoice (.+) of (.+) is already registered$/, 'invoiceDuplicate', 'invoices'],
  [/^Line (\d+): choose a tax code$/, 'lineNeedsTax'],
  [/^(?:Line \d+: )?(?:tax code |Withholding )?(\S+) is not set up for this company/, 'taxNotSetUp', 'taxes'],
  [/^Line (\d+): the amount must be greater than zero$/, 'lineAmount'],
  [/^Line (\d+): account (\S+) is not valid in a received invoice/, 'lineAccountPurchase'],
  [/^Line (\d+): account (\S+) is not valid in an issued invoice/, 'lineAccountSale'],
  [/^The invoice total is negative/, 'invoiceNegative'],
  [/^The invoice total is zero$/, 'invoiceZero'],
  [/^The invoice has no lines$/, 'invoiceNoLines'],
  [/^Enter the vendor invoice number$/, 'vendorInvoiceNo'],
  [/^Choose the partner of the invoice$/, 'choosePartner'],
  [/^The invoice date is required$/, 'invoiceDate'],
  [/^The posting date cannot be earlier than the invoice date$/, 'postingBeforeInvoice'],
  [/^A credit memo must identify the invoice it corrects$/, 'creditMemoNeedsInvoice'],
  [/^A received invoice needs a vendor/, 'receivedNeedsVendor', 'partners'],
  [/^An issued invoice needs a customer/, 'issuedNeedsCustomer', 'partners'],
  [/^Invoices are created only with post_invoice/, 'invoiceImmutable'],
  [/^The corrected invoice must be an invoice of the same partner$/, 'creditMemoSamePartner'],
  [/^Tax code (\S+) needs an input \(472\) and an output \(477\) account$/, 'taxNeedsAccounts', 'taxes'],
  // Casos especiales (ISP, intracomunitarias, exportaciones, recargo): la regla exacta va en el detalle técnico
  [/^Line (\d+): .*(?:is only for|needs a (?:vendor|customer) from|is not available|records its sales|is an intra-EU supply|is not set up \(Taxes)/, 'lineTaxNotApplicable'],

  // Liquidación y prorrata
  [/^(\S+) quarter (\S+)T (\S+) is already settled/, 'quarterSettled', 'settlement'],
  [/^Quarter (\S+)T (\S+) \(or a later one\) is already settled$/, 'quarterSettledLater', 'settlement'],
  [/^Q4 (\S+) is already settled/, 'q4Settled', 'settlement'],
  [/^Only the last settlement can be cancelled$/, 'lastSettlement'],
  [/^The invoice register and the tax accounts differ by (\S+):/, 'registerDiff', 'journal'],
  [/^The (\S+) pro rata of (\S+) is already regularized/, 'proRataDone', 'prorata'],

  // Permisos, límites e IA
  [/^No permission to (.+) (?:in|into) this company$/, 'noPermissionAction'],
  [/^Only the company admin can/, 'onlyAdmin'],
  [/^Only the application owner/, 'onlyOwner'],
  [/^Guest visitors can only view the demo companies/, 'guest'],
  [/^Company limit reached: your account can create (\d+)/, 'companyLimit'],
  [/^(?:Not allowed to read this company|(?:Company|Entry|Settlement) not found)/, 'notAllowed'],
  [/^Daily AI limit reached \((\d+) per day\)$/, 'aiLimit'],
  [/^The AI.* (?:is not enabled for you|is only available to the application owner)/, 'aiNotEnabled'],
  [/^No registered user with email (.+)$/, 'noUser'],
  [/^You cannot remove your own access$/, 'ownAccess'],

  // Importación
  [/^The company already has entries: imports go into a new, empty company$/, 'importNotEmpty'],
  [/^Too many rows: maximum (\d+) per import$/, 'tooManyRows'],
  [/^Import cancelled: (\d+) row\(s\) with errors/, 'importRowsErrors'],

  // Inicio de sesión (Supabase Auth)
  [/^Invalid login credentials/, 'loginInvalid'],
  [/^Email not confirmed/, 'emailNotConfirmed'],
  [/^Password should be at least (\d+)/, 'passwordShortAuth'],
  [/^User already registered/, 'userExists'],
  [/^New password should be different/, 'samePassword'],
  [/rate limit|For security purposes, you can only request/i, 'rateLimit'],

  // Genéricos de PostgreSQL / PostgREST / red (al final: los concretos tienen prioridad)
  [/Could not find the function|PGRST202|schema cache/i, 'dbNotUpdated'],
  [/row-level security|permission denied/i, 'noPermission'],
  [/duplicate key value violates unique constraint/i, 'duplicate'],
  [/JWT expired|invalid JWT/i, 'sessionExpired'],
  [/Failed to fetch|NetworkError|Load failed|fetch failed/i, 'network'],
]

// Rellena {1}, {2}… con los datos sacados del mensaje
const fill = (text, values) => text.replace(/\{(\d)\}/g, (_, i) => values[Number(i)] ?? '')
// Palabras sueltas que vienen en inglés dentro del mensaje (debit → deudor, VAT → IVA, vendor → proveedor…)
// y los importes de la base de datos (1210.00 → 1.210,00 en español)
const word = (v, t, language) => {
  if (/^-?\d+\.\d{2}$/.test(v ?? '')) return money(v, language)
  const w = t(`err.word.${v}`)
  return w === `err.word.${v}` ? v : w
}

// error: el texto (o un objeto con .message) · t y language: los del i18n
// → { title, hint, to, technical }  (to = pantalla de la empresa donde se arregla)
export function friendlyError(error, t, language = 'es') {
  const message = String(error?.message ?? error ?? '').trim()
  if (!message) return null
  for (const [re, key, to] of RULES) {
    const m = message.match(re)
    if (!m) continue
    const title = t(`err.${key}.title`)
    if (title === `err.${key}.title`) break               // sin traducción: se muestra el original
    const hint = t(`err.${key}.hint`)
    const values = [...m].map((v) => word(v, t, language))
    return {
      title: fill(title, values),
      hint: hint === `err.${key}.hint` ? '' : fill(hint, values),
      to: to ?? null,
      technical: message,
    }
  }
  return { title: message, hint: '', to: null, technical: null }
}
