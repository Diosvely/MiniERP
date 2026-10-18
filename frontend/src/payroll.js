// NÓMINAS (v0.38.0): cálculos de la pantalla. Quien calcula de verdad y contabiliza es la base de datos (0049:
// erp.payslip_calc y erp.run_payroll); aquí se repite la parte sencilla para enseñarla mientras se escribe
// (la base de cotización de la ficha) y se arma la vista previa del asiento con lo que devuelve la base de datos.
import { cents } from './assets'
import { defaultSubaccount } from './adjustments'

const num = (v) => Number(String(v ?? '').replace(',', '.')) || 0

// Base de cotización (art. 147 LGSS): salario del mes + prorrata de las pagas extra, con el tope de la base máxima
//   e: { monthly_salary, extra_payments } · limits: erp.ss_limits del año ({ max_base, min_base })
export function ssBase(e, limits) {
  const salary = cents(num(e.monthly_salary)) / 100
  const prorata = Math.round(salary * (Number(e.extra_payments) || 0) / 12 * 100) / 100
  const remuneration = Math.round((salary + prorata) * 100) / 100
  const max = limits ? num(limits.max_base) : Infinity
  const base = Math.min(remuneration, max)
  return { prorata, remuneration, base, capped: remuneration > max, belowMin: !!limits && base > 0 && base < num(limits.min_base) }
}

// Meses en que se pagan las pagas extra: 2 → junio y diciembre; 3 → abril, agosto y diciembre; 4 → cada trimestre
export function payMonths(extraPayments) {
  const n = Number(extraPayments) || 0
  if (n <= 0) return []
  return Array.from({ length: n }, (_, i) => (i + 1) * (12 / n))
}

// Último día del mes de un 'AAAA-MM' (o de una fecha)
export function monthEnd(value) {
  const [y, m] = String(value).slice(0, 7).split('-').map(Number)
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10)
}
// Mes siguiente a 'AAAA-MM-DD' en formato 'AAAA-MM'
export function nextMonth(value) {
  const [y, m] = String(value).slice(0, 7).split('-').map(Number)
  return m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`
}

// ¿Está de alta en ese mes? (la base de datos liquida el mes entero: el alta o la baja a mitad de mes se avisa)
export function activeIn(e, month) {
  const end = monthEnd(month), start = `${String(month).slice(0, 7)}-01`
  return e.hire_date <= end && (!e.end_date || e.end_date >= start)
}

// Asiento de la nómina (sumado por cuenta y lado, en el orden del PGC) con lo que devuelve erp.payslip_calc
//   640 D salarios (+ paga devengada) · 465 D paga extra que se paga · 642 D Seguridad Social a cargo de la empresa
//   476 H cuotas (empresa + trabajador) · 4751 H IRPF · 465 H líquido (+ paga devengada)
export function payrollEntryLines(slips, digits = 8) {
  const s = (f) => slips.reduce((acc, x) => acc + cents(f(x)), 0) / 100
  const lines = [
    ['640', s((x) => num(x.salary) + num(x.extra_accrual)), 0],
    ['465', s((x) => x.extra_paid), 0],
    ['642', s((x) => x.ss_employer), 0],
    ['476', 0, s((x) => num(x.ss_employer) + num(x.ss_employee))],
    ['4751', 0, s((x) => x.irpf)],
    ['465', 0, s((x) => num(x.net) + num(x.extra_accrual))],
  ]
  return lines.filter(([, d, h]) => d || h).map(([p, debit, credit]) => ({ account_no: defaultSubaccount(p, digits), debit, credit }))
}

// Totales de la nómina del mes
export function payrollTotals(slips) {
  const s = (f) => slips.reduce((acc, x) => acc + cents(f(x)), 0) / 100
  return {
    gross: s((x) => num(x.salary) + num(x.extra_paid)),   // lo que cobra el trabajador antes de descuentos
    expense: s((x) => num(x.salary) + num(x.extra_accrual) + num(x.ss_employer)),   // gasto del mes (640 + 642)
    ssEmployee: s((x) => x.ss_employee), ssEmployer: s((x) => x.ss_employer), irpf: s((x) => x.irpf), net: s((x) => x.net),
  }
}

// Recibo de salarios: devengos, deducciones del trabajador y aportación de la empresa (del detalle de erp.payslip_calc)
export function payslipSummary(slip) {
  const detail = slip.ss_detail ?? []
  const deductions = detail.filter((d) => num(d.employee) > 0)
    .map((d) => ({ concept: d.concept, name: d.name, name_en: d.name_en, base: num(d.base), pct: num(d.employee_pct), amount: num(d.employee) }))
  const employer = detail.filter((d) => num(d.employer) > 0)
    .map((d) => ({ concept: d.concept, name: d.name, name_en: d.name_en, base: num(d.base), pct: num(d.employer_pct), amount: num(d.employer) }))
  const earnings = num(slip.salary) + num(slip.extra_paid)
  return {
    earnings, deductions, employer,
    totalDeductions: Math.round((num(slip.ss_employee) + num(slip.irpf)) * 100) / 100,
    net: num(slip.net),
    cost: Math.round((num(slip.salary) + num(slip.extra_accrual) + num(slip.ss_employer)) * 100) / 100,
  }
}

// Qué se puede hacer con una nómina contabilizada: pagar el líquido, después los seguros sociales; deshacer, lo último
export function nextPayment(run) {
  if (run.status !== 'posted') return null
  if (!run.net_payment_entry_no) return 'net'
  if (!run.ss_payment_entry_no) return 'social_security'
  return null
}
