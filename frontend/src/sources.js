// BASE DOCUMENTAL (v0.39.0): las fuentes oficiales en las que se apoya cada regla del ERP.
// Cada fuente lleva quién la publica, el enlace oficial, el artículo o apartado que se usa y la fecha en que se comprobó
// (las normas cambian: una fuente sin revisar en más de un año se avisa). Se ven con el botón 📘 de cada pantalla.
// Para los textos legales se usa el enlace ELI del BOE (identificador europeo de legislación, estable) al texto consolidado.
export const SOURCES = {
  aeat303: {
    issuer: 'AEAT', checked: '2026-10-18',
    url: 'https://sede.agenciatributaria.gob.es/Sede/todas-gestiones/impuestos-tasas/iva/modelo-303-iva-autoliquidacion_/instrucciones-2026.html',
    es: { title: 'Modelo 303 · Instrucciones 2026', ref: 'Casillas 01 a 89 y 108 a 124' },
    en: { title: 'Form 303 · 2026 instructions', ref: 'Boxes 01 to 89 and 108 to 124' },
  },
  aeat390: {
    issuer: 'AEAT', checked: '2026-10-18',
    url: 'https://sede.agenciatributaria.gob.es/static_files/Sede/Procedimiento_ayuda/G412/Instrucciones_modelo_390-2025.pdf',
    es: { title: 'Modelo 390 · Instrucciones (ejercicio 2025)', ref: 'Liquidación, resultado y volumen de operaciones' },
    en: { title: 'Form 390 · Instructions (2025)', ref: 'Return, result and turnover' },
  },
  aeat390manual: {
    issuer: 'AEAT', checked: '2026-10-18',
    url: 'https://sede.agenciatributaria.gob.es/static_files/Sede/Biblioteca/Manual/Practicos/IVA/IVA_2025/Imagenes/Cap_9_390_resumen_anual_es_es.pdf',
    es: { title: 'Manual práctico de IVA 2025 · Capítulo 9: modelo 390', ref: 'Ejemplo resuelto: casillas por tipo' },
    en: { title: 'VAT practical guide 2025 · Chapter 9: form 390', ref: 'Worked example: boxes by rate' },
  },
  atc420: {
    issuer: 'ATC', checked: '2026-10-18',
    url: 'https://www3.gobiernodecanarias.org/tributos/atc/documents/65729/201004/Instrucciones_modelo_420.pdf/59fbc2b2-7aff-4a68-95ea-4984da563cfc?t=1742821063325',
    es: { title: 'Modelo 420 · Instrucciones', ref: 'Casillas 01 a 51' },
    en: { title: 'Form 420 · Instructions', ref: 'Boxes 01 to 51' },
  },
  atc425: {
    issuer: 'ATC', checked: '2026-10-18',
    url: 'https://www3.gobiernodecanarias.org/tributos/atc/documents/65729/204267/Instrucciones_modelo_425.pdf/cf497b3d-275e-0bb3-4ffc-67fc70b0ade0?t=1742821251705',
    es: { title: 'Modelo 425 · Instrucciones', ref: 'Casillas 01 a 134' },
    en: { title: 'Form 425 · Instructions', ref: 'Boxes 01 to 134' },
  },
  liva: {
    issuer: 'BOE', checked: '2026-10-18',
    url: 'https://www.boe.es/eli/es/l/1992/12/28/37/con',
    es: { title: 'Ley 37/1992, del Impuesto sobre el Valor Añadido', ref: 'Art. 108: bienes de inversión (desde 3.005,06 €)' },
    en: { title: 'Law 37/1992 on Value Added Tax', ref: 'Art. 108: capital goods (from €3,005.06)' },
  },
  ley20_1991: {
    issuer: 'BOE', checked: '2026-10-18',
    url: 'https://www.boe.es/eli/es/l/1991/06/07/20/con',
    es: { title: 'Ley 20/1991, del Régimen Económico Fiscal de Canarias (IGIC)', ref: 'Art. 40: bienes de inversión (desde 500.000 pesetas = 3.005,06 €)' },
    en: { title: 'Law 20/1991, Canary Islands tax regime (IGIC)', ref: 'Art. 40: capital goods (from 500,000 pesetas = €3,005.06)' },
  },
  rd1065: {
    issuer: 'BOE', checked: '2026-10-19',
    url: 'https://www.boe.es/eli/es/rd/2007/07/27/1065/con',
    es: { title: 'Real Decreto 1065/2007, de gestión e inspección tributaria', ref: 'Arts. 31 a 35: declaración anual de operaciones con terceros (modelo 347)' },
    en: { title: 'Royal Decree 1065/2007 on tax management', ref: 'Arts. 31 to 35: annual third-party return (form 347)' },
  },
  aeat347faq: {
    issuer: 'AEAT', checked: '2026-10-19',
    url: 'https://sede.agenciatributaria.gob.es/Sede/todas-gestiones/impuestos-tasas/declaraciones-informativas/modelo-347-decla_____racion-anual-operaciones-personas_/preguntas-frecuentes.html',
    es: { title: 'Modelo 347 · Preguntas frecuentes', ref: 'Rectificaciones e imputación por trimestres' },
    en: { title: 'Form 347 · FAQ', ref: 'Corrections and quarterly allocation' },
  },
  riva: {
    issuer: 'BOE', checked: '2026-10-19',
    url: 'https://www.boe.es/eli/es/rd/1992/12/29/1624/con',
    es: { title: 'Real Decreto 1624/1992, Reglamento del IVA', ref: 'Arts. 78 a 81: declaración recapitulativa de operaciones intracomunitarias (modelo 349)' },
    en: { title: 'Royal Decree 1624/1992, VAT Regulation', ref: 'Arts. 78 to 81: EC sales list (form 349)' },
  },
}

// Fuentes de cada modelo (las que salen en su botón 📘)
export const FORM_SOURCES = {
  303: ['aeat303', 'liva'], 390: ['aeat390', 'aeat390manual', 'liva'],
  420: ['atc420', 'ley20_1991'], 425: ['atc425', 'ley20_1991'],
  347: ['rd1065', 'aeat347faq'], 349: ['riva'],
}

// ¿Hay que revisarla? (más de un año desde la última comprobación)
export function isStale(source, today) {
  const d = new Date(`${source.checked}T00:00:00Z`)
  d.setUTCFullYear(d.getUTCFullYear() + 1)
  return d.toISOString().slice(0, 10) < today
}
