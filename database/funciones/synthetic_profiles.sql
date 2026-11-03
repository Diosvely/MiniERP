-- =====================================================================
-- erp.synthetic_profiles · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0086_synthetic_companies   →   la vigente es la de 0086_synthetic_companies
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.synthetic_profiles()
 RETURNS TABLE(profile text, name text, name_en text, territory text, tax_type text, description text, description_en text, min_months integer)
 LANGUAGE sql
 STABLE
AS $function$
  values
  ('services', 'Servicios', 'Services', 'mainland', 'VAT',
   'Una consultora en la península: IVA, alquiler con retención (115) y profesionales con IRPF (111).',
   'A consultancy in mainland Spain: VAT, rent with withholding (115) and professionals with income tax withholding (111).', 1),
  ('trade', 'Comercio', 'Trade', 'mainland', 'VAT',
   'Un mayorista en la península: compra mercaderías y vende a empresas y a tiendas en recargo de equivalencia.',
   'A wholesaler in mainland Spain: buys goods and sells to companies and to shops under the equivalence surcharge.', 1),
  ('workshop', 'Taller', 'Workshop', 'canary_islands', 'IGIC',
   'Un taller en Canarias: IGIC, recambios, una máquina, un préstamo y dos personas en plantilla.',
   'A workshop in the Canary Islands: IGIC, spare parts, a machine, a loan and two employees.', 1),
  ('incidents', 'Incidencias', 'Incidents', 'canary_islands', 'IGIC',
   'El taller con cuatro errores sembrados para encontrarlos: un proveedor deudor, un cliente con un vencido de más de 90 días, un borrador descuadrado y un trimestre sin liquidar.',
   'The workshop with four planted errors to find: a supplier with a debit balance, a customer more than 90 days overdue, an unbalanced draft and an unsettled quarter.', 6);
$function$
;
