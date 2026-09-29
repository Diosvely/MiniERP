-- =====================================================================
-- 0003 · TERCEROS E IMPUESTOS (catálogo IVA / IGIC)
-- ---------------------------------------------------------------------
-- Equivalencias:
--   terceros          ≈ BC "Customer" / "Vendor"   ≈ SAP deudores (KNA1) / acreedores (LFA1)
--   impuestos_tipos   ≈ BC "VAT Product Posting Group" + % ≈ SAP "Indicador de IVA" (MWSKZ)
--
-- Fase 1: catálogo de tipos con vigencia + cada apunte puede llevar su tipo y base imponible
--         → de ahí sale el libro registro de IVA/IGIC.
-- Fase 3: matriz completa (territorio empresa × territorio tercero × categoría) con
--         cálculo automático de cuotas, recargo de equivalencia y retenciones IRPF.
-- =====================================================================

-- ---------------------------------------------------------------------
-- TERCEROS (clientes, proveedores, acreedores, deudores)
-- ---------------------------------------------------------------------
create table conta.terceros (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references conta.empresas(id) on delete cascade,
  tipo        text not null check (tipo in ('cliente', 'proveedor', 'acreedor', 'deudor')),
  nif         text,
  nombre      text not null,
  -- Dónde está el tercero: junto con el territorio de la empresa decide el impuesto.
  -- Ej: empresa canaria que vende a cliente peninsular → exportación, sin IGIC.
  territorio  text not null default 'peninsula'
              check (territorio in ('peninsula', 'canarias', 'ceuta_melilla', 'ue', 'extranjero')),
  -- Subcuenta contable del tercero (ej. 43000001)
  cuenta_id   uuid references conta.cuentas(id),
  created_at  timestamptz not null default now()
);
create index terceros_empresa on conta.terceros (empresa_id);

-- ---------------------------------------------------------------------
-- TIPOS DE IMPUESTO con fechas de vigencia (los tipos cambian por ley:
-- nunca se escriben fijos en el código).
-- ⚠ Revisar contra la normativa vigente antes de usarlos en serio.
--   Los porcentajes son los de 2026; algunas fechas "vigente_desde" antiguas son orientativas.
-- ---------------------------------------------------------------------
create table conta.impuestos_tipos (
  id                    text primary key,       -- ej. 'IVA21', 'IGIC7'
  impuesto              text not null check (impuesto in ('IVA', 'IGIC')),
  categoria             text not null,          -- general, reducido, superreducido…
  porcentaje            numeric(5,2) not null check (porcentaje >= 0),
  -- Recargo de equivalencia (solo IVA, comercio minorista persona física)
  recargo_equivalencia  numeric(5,2),
  vigente_desde         date not null,
  vigente_hasta         date,
  descripcion           text
);

insert into conta.impuestos_tipos
  (id, impuesto, categoria, porcentaje, recargo_equivalencia, vigente_desde, descripcion) values
-- IVA · Península y Baleares (Ley 37/1992)
('IVA21', 'IVA', 'general',        21.00, 5.20, '2012-09-01', 'Tipo general'),
('IVA10', 'IVA', 'reducido',       10.00, 1.40, '2012-09-01', 'Hostelería, transporte de viajeros, ciertos alimentos…'),
('IVA4',  'IVA', 'superreducido',   4.00, 0.50, '1995-01-01', 'Pan, leche, libros, medicamentos…'),
('IVA0',  'IVA', 'exento',          0.00, null, '1993-01-01', 'Operaciones exentas o no sujetas'),
-- IGIC · Canarias (texto refundido, Decreto Legislativo 1/2025)
('IGIC0',   'IGIC', 'cero',                   0.00, null, '2012-01-01', 'Tipo cero: bienes y servicios enumerados'),
('IGIC1',   'IGIC', 'especifico',             1.00, null, '2026-01-01', 'Petróleo y derivados del refino (nuevo en 2026)'),
('IGIC3',   'IGIC', 'superreducido',          3.00, null, '2012-01-01', 'Bienes de primera necesidad enumerados'),
('IGIC5',   'IGIC', 'reducido',               5.00, null, '2012-01-01', 'Bienes enumerados (p. ej. ciertos refrescos)'),
('IGIC7',   'IGIC', 'general',                7.00, null, '2012-07-01', 'Tipo general'),
('IGIC9_5', 'IGIC', 'incrementado',           9.50, null, '2012-01-01', 'Bienes enumerados'),
('IGIC15',  'IGIC', 'incrementado_especial', 15.00, null, '2012-01-01', 'Bienes enumerados (p. ej. bebidas energéticas)'),
('IGIC20',  'IGIC', 'especial',              20.00, null, '2012-01-01', 'Labores del tabaco');

comment on table conta.impuestos_tipos is
  'Catálogo global de tipos IVA/IGIC con vigencia. Verificar siempre contra la normativa vigente.';
