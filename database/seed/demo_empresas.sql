-- =====================================================================
-- DEMO DATA · DATOS DE EJEMPLO (opcional) · dos empresas para comparar IGIC e IVA
--   A) Demo Asesoría Canarias SL  → servicios · Canarias  · IGIC + retención IRPF
--   B) Demo Tienda Península SL   → retail    · Península · IVA
--
-- Se ejecuta en el SQL Editor de Supabase DESPUÉS de las migraciones.
-- Asigna las empresas al primer usuario registrado en Authentication → Users
-- (regístrate antes en tu web o créalo en el panel de Supabase).
--
-- Convención de subcuentas (8 dígitos) para impuestos:
--   4720xxxx IVA soportado    4721xxxx IGIC soportado     (xx = tipo: 21, 10, 07…)
--   4770xxxx IVA repercutido  4771xxxx IGIC repercutido
-- =====================================================================
do $$
declare
  v_user uuid := (select id from auth.users order by created_at limit 1);
  e uuid; ej uuid; a uuid; t_cli uuid; t_prov uuid;
begin
  if v_user is null then
    raise exception 'No hay usuarios en auth.users: crea uno antes de cargar la demo';
  end if;

  -- ═════════════ A) CANARIAS · SERVICIOS · IGIC ═════════════
  insert into erp.companies (name, vat_registration_no, industry, tax_territory, created_by)
  values ('Demo Asesoría Canarias SL', 'B35000001', 'services', 'canary_islands', v_user)
  returning id into e;
  ej := erp.create_fiscal_year(e, 2026);

  perform erp.create_posting_account(e, s.account_no, s.name, s.name_en)
  from (values ('10000001','Capital social','Share capital'),
               ('57200001','Banco c/c','Bank current account'),
               ('43000001','Cliente Hotel Atlántico SL','Customer Hotel Atlántico SL'),
               ('41000001','Acreedor Gestoría Martín','Creditor Gestoría Martín'),
               ('62300001','Servicios de profesionales independientes','Professional services'),
               ('70500001','Prestación de servicios de asesoría','Consulting services rendered'),
               ('47210007','IGIC soportado 7%','Input IGIC 7%'),
               ('47710007','IGIC repercutido 7%','Output IGIC 7%'),
               ('47510001','HP acreedora por retenciones IRPF profesionales','Withholdings payable – professionals')) as s(account_no, name, name_en);

  insert into erp.business_partners (company_id, partner_type, vat_registration_no, name, tax_territory, gl_account_id)
  values (e, 'customer', 'B35999994', 'Hotel Atlántico SL', 'canary_islands',
          (select id from erp.gl_accounts where company_id = e and account_no = '43000001'))
  returning id into t_cli;
  insert into erp.business_partners (company_id, partner_type, vat_registration_no, name, tax_territory, gl_account_id)
  values (e, 'creditor', '42000000E', 'Gestoría Martín', 'canary_islands',
          (select id from erp.gl_accounts where company_id = e and account_no = '41000001'))
  returning id into t_prov;

  -- 1. Constitución: aportación de capital al banco
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, entry_type)
  values (e, ej, '2026-01-02', 'Constitución de la sociedad', 'opening') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit, credit)
  select a, (select id from erp.gl_accounts where company_id = e and account_no = x.cod), x.d, x.h
  from (values ('57200001', 3000, 0), ('10000001', 0, 3000)) as x(cod, d, h);
  perform erp.post_entry(a);

  -- 2. Factura de un profesional: IGIC soportado 7% y retención IRPF 15%
  --    500 + 35 IGIC − 75 retención = 460 a pagar
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (e, ej, '2026-01-20', 'Factura gestoría enero', 'GM-2026-01') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit, credit, partner_id, tax_code, tax_base)
  select a, (select id from erp.gl_accounts where company_id = e and account_no = x.cod), x.d, x.h,
         t_prov, x.imp, x.base
  from (values ('62300001', 500, 0, null, null),
               ('47210007',  35, 0, 'IGIC7', 500),
               ('47510001',   0, 75, null, null),
               ('41000001',   0, 460, null, null)) as x(cod, d, h, imp, base);
  perform erp.post_entry(a);

  -- 3. Factura de venta: IGIC repercutido 7%
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (e, ej, '2026-01-31', 'Factura asesoría enero', 'F-2026-001') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit, credit, partner_id, tax_code, tax_base)
  select a, (select id from erp.gl_accounts where company_id = e and account_no = x.cod), x.d, x.h,
         t_cli, x.imp, x.base
  from (values ('43000001', 1070, 0, null, null),
               ('70500001', 0, 1000, null, null),
               ('47710007', 0,   70, 'IGIC7', 1000)) as x(cod, d, h, imp, base);
  perform erp.post_entry(a);

  -- 4. Cobro de la factura
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (e, ej, '2026-02-15', 'Cobro F-2026-001', 'F-2026-001') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit, credit, partner_id)
  select a, (select id from erp.gl_accounts where company_id = e and account_no = x.cod), x.d, x.h, t_cli
  from (values ('57200001', 1070, 0), ('43000001', 0, 1070)) as x(cod, d, h);
  perform erp.post_entry(a);

  -- ═════════════ B) PENÍNSULA · RETAIL · IVA ═════════════
  insert into erp.companies (name, vat_registration_no, industry, tax_territory, created_by)
  values ('Demo Tienda Península SL', 'B28000002', 'retail', 'mainland', v_user)
  returning id into e;
  ej := erp.create_fiscal_year(e, 2026);

  perform erp.create_posting_account(e, s.account_no, s.name, s.name_en)
  from (values ('10000001','Capital social','Share capital'),
               ('57200001','Banco c/c','Bank current account'),
               ('43000001','Clientes contado','Cash customers'),
               ('40000001','Proveedor Distribuciones Norte SA','Supplier Distribuciones Norte SA'),
               ('60000001','Compras de mercaderías','Purchases of merchandise'),
               ('70000001','Ventas de mercaderías','Sales of merchandise'),
               ('47200021','IVA soportado 21%','Input VAT 21%'),
               ('47700021','IVA repercutido 21%','Output VAT 21%')) as s(account_no, name, name_en);

  insert into erp.business_partners (company_id, partner_type, vat_registration_no, name, tax_territory, gl_account_id)
  values (e, 'vendor', 'A28888881', 'Distribuciones Norte SA', 'mainland',
          (select id from erp.gl_accounts where company_id = e and account_no = '40000001'))
  returning id into t_prov;

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, entry_type)
  values (e, ej, '2026-01-02', 'Constitución de la sociedad', 'opening') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit, credit)
  select a, (select id from erp.gl_accounts where company_id = e and account_no = x.cod), x.d, x.h
  from (values ('57200001', 5000, 0), ('10000001', 0, 5000)) as x(cod, d, h);
  perform erp.post_entry(a);

  -- Compra de mercaderías con IVA 21%
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (e, ej, '2026-01-10', 'Compra mercaderías', 'DN-1450') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit, credit, partner_id, tax_code, tax_base)
  select a, (select id from erp.gl_accounts where company_id = e and account_no = x.cod), x.d, x.h,
         t_prov, x.imp, x.base
  from (values ('60000001', 1000, 0, null, null),
               ('47200021',  210, 0, 'VAT21', 1000),
               ('40000001', 0, 1210, null, null)) as x(cod, d, h, imp, base);
  perform erp.post_entry(a);

  -- Ventas de contado de la semana con IVA 21%
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (e, ej, '2026-01-17', 'Ventas de caja semana 3', 'Z-003') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit, credit, tax_code, tax_base)
  select a, (select id from erp.gl_accounts where company_id = e and account_no = x.cod), x.d, x.h, x.imp, x.base
  from (values ('57200001', 1815, 0, null, null),
               ('70000001', 0, 1500, null, null),
               ('47700021', 0,  315, 'VAT21', 1500)) as x(cod, d, h, imp, base);
  perform erp.post_entry(a);

  -- Pago al proveedor
  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (e, ej, '2026-02-10', 'Pago DN-1450', 'DN-1450') returning id into a;
  insert into erp.journal_lines (entry_id, gl_account_id, debit, credit, partner_id)
  select a, (select id from erp.gl_accounts where company_id = e and account_no = x.cod), x.d, x.h, t_prov
  from (values ('40000001', 1210, 0), ('57200001', 0, 1210)) as x(cod, d, h);
  perform erp.post_entry(a);

  raise notice 'Demo cargada: 2 empresas con 4 asientos cada una, asignadas al usuario %', v_user;
end $$;
