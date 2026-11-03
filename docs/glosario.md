# Glosario contable · Accounting glossary

Vocabulario del proyecto en español, inglés y cómo lo llaman Business Central (BC) y SAP.

El glosario completo, con la definición de cada término y sus cuentas del PGC, está en la propia aplicación (pantalla
Glosario; `frontend/src/glossary.js`, copiado en `erp.concepts`). Este documento recoge el vocabulario básico y el de
los tableros. Las equivalencias con BC y SAP son orientativas *(pendiente de validar por Diosvely)*.

## Estructura

| Español | English (este proyecto) | Business Central | SAP |
|---|---|---|---|
| Empresa / sociedad | company (`companies`) | Company | Company Code (BUKRS) |
| Ejercicio | fiscal year (`fiscal_years`) | Fiscal Year | Fiscal Year |
| Periodo contable | accounting period (`accounting_periods`) | Accounting Period | Posting Period |
| Plan de cuentas | chart of accounts (`coa_template`) | Chart of Accounts | Chart of Accounts (SKA1) |
| Cuenta contable | G/L account (`gl_accounts`) | G/L Account | G/L Account (SKB1) |
| Cuenta de título | heading account | Account Type = Heading | — |
| Subcuenta | posting account | Account Type = Posting | G/L account |
| Masa patrimonial | account category | Account Category | Account Group |
| Tercero | business partner (`business_partners`) | Customer / Vendor | Business Partner |
| Cliente | customer | Customer | Customer |
| Proveedor | vendor / supplier | Vendor | Vendor / Supplier |
| Acreedor | creditor | Vendor | Creditor |
| Deudor | debtor | Customer | Debtor |

## Asientos

| Español | English | Business Central | SAP |
|---|---|---|---|
| Asiento | journal entry (`journal_entries`) | Document (G/L Entries) | Accounting Document (BKPF) |
| Apunte / línea | journal line (`journal_lines`) | G/L Entry | Line Item (BSEG) |
| Debe | debit | Debit Amount | Debit (S) |
| Haber | credit | Credit Amount | Credit (H) |
| Fecha contable | posting date | Posting Date | Posting Date (BUDAT) |
| Concepto | description | Description | Item Text |
| Nº de documento | document no. | Document No. | Reference |
| Borrador | draft | General Journal line | Parked document |
| Contabilizar | post | Post | Post |
| Contabilizado | posted | Posted | Posted |
| Anular (contraasiento) | reverse (reversal entry) | Reverse Transaction | Reverse Document (FB08) |
| Cuadrado / descuadrado | balanced / unbalanced | — | — |
| Asiento de apertura | opening entry | Opening entry | Balance carryforward |
| Regularización | closing P&L entry (`closing_pl`) | Close Income Statement | P&L closing |
| Asiento de cierre | closing entry | — | Year-end closing |

## Informes

| Español | English | Business Central | SAP |
|---|---|---|---|
| Libro diario | general journal (`v_general_journal`) | G/L Register | Journal |
| Libro mayor | general ledger (`v_general_ledger`) | G/L Account Statement | Account Line Items (FBL3N) |
| Saldo acumulado | running balance | Balance | — |
| Balance de sumas y saldos | trial balance (`trial_balance`) | Trial Balance | Balance List (S_ALR_87012277) |
| Saldo deudor / acreedor | debit balance / credit balance | — | — |
| Cuenta de pérdidas y ganancias (PyG) | profit and loss account / income statement | Income Statement | P&L Statement |
| Balance de situación | balance sheet | Balance Sheet | Balance Sheet |
| Libro registro de IVA | VAT book (`v_tax_book`) | VAT Entries | Tax Report |

## Impuestos

| Español | English | Business Central | SAP |
|---|---|---|---|
| IVA | VAT (value added tax) | VAT | Tax / VAT |
| IVA soportado (472) | input VAT / input tax | Purchase VAT | Input Tax |
| IVA repercutido (477) | output VAT / output tax | Sales VAT | Output Tax |
| Base imponible | tax base | VAT Base | Tax Base |
| Cuota | tax amount | VAT Amount | Tax Amount |
| Tipo de impuesto | tax code / rate | VAT Posting Setup | Tax Code (MWSKZ) |
| Recargo de equivalencia | equivalence surcharge | EC % | — |
| Retención IRPF | withholding tax | — | Withholding Tax |
| Península | mainland | — | — |
| Canarias | Canary Islands | — | — |

## Masas patrimoniales (account_category)

| Español | English |
|---|---|
| Activo | asset |
| Pasivo | liability |
| Patrimonio neto | equity |
| Gasto | expense |
| Ingreso | income |

## Tableros e indicadores (v0.52.0 → v0.57.0)

| Español | English | Business Central | SAP |
|---|---|---|---|
| Tablero | dashboard (`dashboards`) | Role Center | Fiori Overview Page |
| Métrica / cifra clave | metric / KPI (`dash_metrics`) | Cue / KPI | KPI tile |
| Margen bruto | gross margin | — (Account Schedule) | Gross margin |
| EBITDA | EBITDA | — (Account Schedule) | EBITDA |
| Margen de explotación / neto | operating / net margin | — | Operating / net margin |
| Fondo de maniobra | working capital | — | Working capital |
| Liquidez general · prueba ácida · disponibilidad | current ratio · quick ratio · cash ratio | — | — |
| Periodo medio de cobro / de pago | days sales / payables outstanding (DSO / DPO) | — | DSO / DPO (Fiori) |
| Entradas y salidas de tesorería | cash inflows / outflows | Cash Flow Forecast | Cash Position |
| Cuotas devengadas / deducibles | output / input tax | VAT Statement | Tax Reconciliation |
| Retenciones practicadas / soportadas | withholdings made / suffered | — | Withholding Tax |
| Concentración de clientes | customer concentration | Top 10 Customers | Top Customers |
| Gastos por naturaleza | expenses by nature | — | Cost elements |
| Saldo al revés de su naturaleza | balance against its nature (`balance_rules`) | — | — |
| Saldo «imposible» (caja acreedora…) | impossible balance (`severity = error`) | — | — |
| Lista de control | checklist (`quality_checks`) | Cues de trabajo pendiente | Financial Close Cockpit |
| Simulación con los asientos en edición | simulation with drafts (`p_drafts`) | — | Parked documents in reports |


## Permisos (v0.58.0)

| Español | English | Business Central | SAP |
|---|---|---|---|
| Separación de funciones | segregation of duties (SoD) | SoD (Permission Sets en conflicto) | SAP GRC Access Control |
| Aislamiento entre usuarios (cada empresa, de quien la crea) | tenant isolation | Company | Client / company code |
| Rol de una empresa (administrador, contable, lectura) | company role (`company_users.role`) | Permission Set | Role (PFCG) |
| Titular de los datos | data owner (`company_users.data_owner`) | — | — |
| Mínimo privilegio | least privilege | — | — |
| Seguridad fila a fila | row level security (RLS) | Security filter | Authorization object |
| Prueba guardiana | guardian test (fase 80) | — | — |

## Empresas sintéticas (v0.59.0)

| Español | English | Business Central | SAP |
|---|---|---|---|
| Empresa sintética | synthetic company (`create_synthetic_company`) | Demo company (CRONUS) | Model company |
| Semilla | seed (`synthetic_seed`) | — | — |
| Perfil | profile (`synthetic_profile`) | Demo data (Contoso) | Best Practices test data |
| Azar determinista (pseudoaleatorio) | deterministic pseudo-random (`syn_rand`) | — | — |
| Huella de la contabilidad | fingerprint (`company_fingerprint`) | — | — |
| Versión del generador | generator version (`g1`) | — | — |
