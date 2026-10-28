import { useEffect, useRef, useState } from 'react'
import { useI18n } from '../i18n'
import { addDays, outsideMonth, parseQuickDate, showDate } from '../quickDate'
import { todayIso, workDate } from '../workDate'

// CAMPO DE FECHA RÁPIDA (v0.47.0): se escribe como en ContaSol («2» → día 2 del mes de trabajo; «1503» → 15/03…),
// ↑ ↓ suman o restan un día y el botón 📅 abre el calendario del navegador. Guarda la fecha en ISO.
// En la contabilidad mes a mes avisa si la fecha cae fuera del mes abierto (el motor no la dejaría contabilizar).
//   value: aaaa-mm-dd · onChange(aaaa-mm-dd) · company: para la fecha de trabajo y el mes abierto
//   v0.51.0 · en los informes: clearable (borrar el texto deja la fecha vacía: «todo el ejercicio») y
//   monthHint={false} (el aviso del mes abierto es para contabilizar, no para consultar) y baseDate (la fecha de la
//   que salen «2» o «0102»: en un informe, el ejercicio elegido)
export default function DateField({ value, onChange, company, id, required, label, clearable = false, monthHint = true, baseDate }) {
  const { t } = useI18n()
  const [text, setText] = useState(showDate(value))
  const [focused, setFocused] = useState(false)
  const [invalid, setInvalid] = useState(false)
  const picker = useRef(null)
  const base = baseDate ?? workDate(company)

  // Si la fecha cambia desde fuera (otro asiento, el Tutor…), se enseña la nueva
  useEffect(() => { if (!focused) { setText(showDate(value)); setInvalid(false) } }, [value, focused])   // eslint-disable-line react-hooks/set-state-in-effect

  function type(v) {
    setText(v)
    const d = parseQuickDate(v, base, todayIso())
    setInvalid(Boolean(v.trim()) && !d)
    if (d && d !== value) onChange(d)
  }
  function commit() {
    setFocused(false)
    const d = parseQuickDate(text, base, todayIso())
    if (d) { setText(showDate(d)); setInvalid(false); if (d !== value) onChange(d) }
    else if (!text.trim()) { if (clearable && value) onChange(''); else setText(showDate(value)) }
  }
  function keys(e) {
    if ((e.key === 'ArrowUp' || e.key === 'ArrowDown') && value) {
      e.preventDefault()
      const d = addDays(value, e.key === 'ArrowUp' ? 1 : -1)
      onChange(d); setText(showDate(d))
    } else if (e.key === 'Enter') commit()
  }

  const out = monthHint && company?.monthly ? outsideMonth(value, company.work_month) : null
  const hintId = id ? `${id}-aviso` : undefined
  return (
    <span className="campo-fecha">
      <span className="fila-fecha">
        <input id={id} type="text" inputMode="numeric" autoComplete="off" value={text} required={required}
               placeholder={t('qd.placeholder')} aria-label={label} aria-invalid={invalid || undefined}
               aria-describedby={(invalid || out) ? hintId : undefined}
               onFocus={(e) => { setFocused(true); e.target.select() }} onBlur={commit} onKeyDown={keys}
               onChange={(e) => type(e.target.value)} />
        <button type="button" className="boton-calendario" aria-label={t('qd.calendar')} title={t('qd.calendar')}
                onClick={() => { try { picker.current?.showPicker?.() } catch { picker.current?.focus() } }}>📅</button>
        <input ref={picker} type="date" className="selector-oculto" tabIndex={-1} aria-hidden="true" value={value ?? ''}
               onChange={(e) => { if (e.target.value) { onChange(e.target.value); setText(showDate(e.target.value)) } }} />
      </span>
      {invalid && <small id={hintId} className="aviso" role="alert">{t('qd.invalid')}</small>}
      {!invalid && out && (
        <small id={hintId} className="aviso">
          {t(`qd.${out}`).replace('{m}', `${showDate(company.work_month.from)} – ${showDate(company.work_month.to)}`)}
        </small>)}
    </span>
  )
}
