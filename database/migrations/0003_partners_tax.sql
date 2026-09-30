-- =====================================================================
-- 0003 · BUSINESS PARTNERS & TAX CODES · Terceros e impuestos (IVA / IGIC)
-- ---------------------------------------------------------------------
-- Equivalencias / Equivalents:
--   business_partners  ≈ BC "Customer" / "Vendor"  ≈ SAP S/4 "Business Partner" (antes KNA1 / LFA1)
--   tax_codes          ≈ BC "VAT Product Posting Group" + %  ≈ SAP "Tax Code" (MWSKZ)
--
-- Glosario rápido:
--   input tax  = impuesto soportado (lo pagas al comprar)   → cuenta 472
--   output tax = impuesto repercutido (lo cobras al vender) → cuenta 477
--   equivalence surcharge = recargo de equivalencia
--
-- Fase 1: catálogo de tipos con vigencia; cada apunte puede llevar su tax_code y tax_base
--         → de ahí sale el libro registro de IVA/IGIC (tax book).
-- Fase 3: matriz completa (territorio empresa × territorio tercero × categoría) con
--         cálculo automático de cuotas, recargo de equivalencia y retenciones IRPF.
-- =====================================================================

-- ---------------------------------------------------------------------
-- BUSINESS PARTNERS · Terceros (clientes, proveedores, acreedores, deudores)
-- ---------------------------------------------------------------------
create table erp.business_partners (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references erp.companies(id) on delete cascade,
  partner_type         text not null
                       check (partner_type in ('customer', 'vendor', 'creditor', 'debtor')),
                       -- cliente, proveedor, acreedor, deudor
  vat_registration_no  text,
  name                 text not null,
  -- Dónde está el tercero: junto con el territorio de la empresa decide el impuesto.
  -- Ej: empresa canaria que vende a un cliente peninsular → exportación, sin IGIC.
  tax_territory        text not null default 'mainland'
                       check (tax_territory in ('mainland', 'canary_islands', 'ceuta_melilla', 'eu', 'non_eu')),
  gl_account_id        uuid references erp.gl_accounts(id),   -- subcuenta del tercero (ej. 43000001)
  created_at           timestamptz not null default now()
);
create index business_partners_company on erp.business_partners (company_id);

-- ---------------------------------------------------------------------
-- TAX CODES · Tipos de impuesto con fechas de vigencia
-- (los tipos cambian por ley: nunca se escriben fijos en el código)
-- ⚠ Revisar contra la normativa vigente antes de usarlos en serio.
--   Los porcentajes son los de 2026; algunas fechas valid_from antiguas son orientativas.
-- ---------------------------------------------------------------------
create table erp.tax_codes (
  code                         text primary key,     -- ej. 'VAT21', 'IGIC7'
  tax_type                     text not null check (tax_type in ('VAT', 'IGIC')),
  rate_category                text not null,        -- standard, reduced, super_reduced…
  rate_pct                     numeric(5,2) not null check (rate_pct >= 0),
  equivalence_surcharge_pct    numeric(5,2),         -- recargo de equivalencia (solo IVA)
  valid_from                   date not null,
  valid_to                     date,
  description                  text,                 -- español
  description_en               text                  -- English
);

insert into erp.tax_codes
  (code, tax_type, rate_category, rate_pct, equivalence_surcharge_pct, valid_from, description, description_en) values
-- IVA / VAT · Península y Baleares (Ley 37/1992)
('VAT21',   'VAT',  'standard',        21.00, 5.20, '2012-09-01', 'Tipo general',                                  'Standard rate'),
('VAT10',   'VAT',  'reduced',         10.00, 1.40, '2012-09-01', 'Hostelería, transporte de viajeros, ciertos alimentos', 'Hospitality, passenger transport, some foods'),
('VAT4',    'VAT',  'super_reduced',    4.00, 0.50, '1995-01-01', 'Pan, leche, libros, medicamentos',              'Bread, milk, books, medicines'),
('VAT0',    'VAT',  'exempt',           0.00, null, '1993-01-01', 'Operaciones exentas o no sujetas',              'Exempt or out-of-scope transactions'),
-- IGIC · Canarias (texto refundido, Decreto Legislativo 1/2025)
('IGIC0',   'IGIC', 'zero',             0.00, null, '2012-01-01', 'Tipo cero: bienes y servicios enumerados',      'Zero rate: listed goods and services'),
('IGIC1',   'IGIC', 'specific',         1.00, null, '2026-01-01', 'Petróleo y derivados del refino (nuevo en 2026)', 'Oil and refined products (new in 2026)'),
('IGIC3',   'IGIC', 'super_reduced',    3.00, null, '2012-01-01', 'Bienes de primera necesidad enumerados',        'Listed essential goods'),
('IGIC5',   'IGIC', 'reduced',          5.00, null, '2012-01-01', 'Bienes enumerados (p. ej. ciertos refrescos)', 'Listed goods (e.g. some soft drinks)'),
('IGIC7',   'IGIC', 'standard',         7.00, null, '2012-07-01', 'Tipo general',                                  'Standard rate'),
('IGIC9_5', 'IGIC', 'increased',        9.50, null, '2012-01-01', 'Tipo incrementado: bienes enumerados',          'Increased rate: listed goods'),
('IGIC15',  'IGIC', 'increased_special',15.00, null, '2012-01-01', 'Bienes enumerados (p. ej. bebidas energéticas)', 'Listed goods (e.g. energy drinks)'),
('IGIC20',  'IGIC', 'special',         20.00, null, '2012-01-01', 'Labores del tabaco',                            'Tobacco products');

comment on table erp.tax_codes is
  'Global catalogue of VAT/IGIC rates with validity dates. Always check against current legislation.';
