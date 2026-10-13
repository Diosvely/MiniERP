// DATOS FISCALES DEL TERCERO (v0.31.0): forma jurídica y retención por defecto.
// La base de datos es quien decide (0033); aquí solo se replica la regla para que el formulario no ofrezca lo que
// luego rechazaría. Como en la ficha del proveedor de Business Central o el maestro del acreedor de SAP.

const clean = (v) => String(v ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '')

// NIF (12345678Z) o NIE (X1234567L) → persona física · CIF (B12345674) → entidad · otro → null (no se sabe)
export function legalFormFromTaxId(taxId) {
  const v = clean(taxId)
  if (/^([0-9]{8}|[KLMXYZ][0-9]{7})[A-Z]$/.test(v)) return 'individual'
  if (/^[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]$/.test(v)) return 'company'
  return null
}

// Solo se retiene a proveedores y acreedores
export const canWithhold = (partnerType) => partnerType === 'vendor' || partnerType === 'creditor'

// Retenciones que admite el tercero: a una entidad no se le aplica la de profesionales (sí la de alquiler)
export function allowedWithholdings(codes, partnerType, legalForm) {
  if (!canWithhold(partnerType)) return []
  return codes.filter((c) => !(legalForm === 'company' && c.kind === 'professional'))
}
