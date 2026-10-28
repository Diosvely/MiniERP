import { useI18n } from '../i18n'
import { monthEnd, monthNames, monthOf } from '../reportPeriod'

// BOTONES DE MES (v0.51.0): «Todo · Ene · Feb … Dic» al lado del año. Un mes pone «hasta» = su último día del
// ejercicio elegido; «Todo» lo vacía (el ejercicio entero). Se marca el mes de la fecha, también si se escribe a mano.
//   year · value: el «hasta» (aaaa-mm-dd o '') · onChange(fecha) · all: false quita «Todo» (Comprobaciones: siempre hay fecha)
export default function MonthPicker({ year, value, onChange, all = true }) {
  const { t, language } = useI18n()
  const current = monthOf(value, year)
  const names = monthNames(language)
  return (
    <div className="barra-meses" role="group" aria-label={t('rp.months')}>
      {all && (
        <button type="button" aria-pressed={!value} className={!value ? 'activa' : ''} onClick={() => onChange('')}
                title={t('rp.allTitle')}>{t('rp.all')}</button>
      )}
      {names.map((n, i) => (
        <button key={n} type="button" aria-pressed={current === i + 1} className={current === i + 1 ? 'activa' : ''}
                title={t('rp.monthTitle').replace('{d}', monthEnd(year, i + 1).split('-').reverse().join('/'))}
                onClick={() => onChange(monthEnd(year, i + 1))}>{n}</button>
      ))}
    </div>
  )
}
