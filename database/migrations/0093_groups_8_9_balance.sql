-- =====================================================================
-- 0093 · v0.60.4 · Los grupos 8 y 9 sin regularizar, en su partida del patrimonio neto (hallazgo AF-06)
-- ---------------------------------------------------------------------
-- Antes del cierre, el Balance ponía todo lo de los grupos 8 y 9 en «A-3) Subvenciones, donaciones y legados
-- recibidos». Pero solo 84 y 94 (subvenciones) acaban en las cuentas 130-132 (A-3). Las 80/90 (valoración de activos
-- y pasivos), 81/91 (operaciones de cobertura) y 82/92 (diferencias de conversión) se llevan al cierre a la 133, la
-- 1340 y la 135: «A-2) Ajustes por cambios de valor». RD 1514/2007, cuarta parte (grupos 8 y 9) y modelos de balance.
-- Decisión de Diosvely (10-11-2026): corregirlo, no solo documentarlo. Modelos normal y abreviado; PYMES no se toca
-- (la ficha de auditoría fiscal no lo revisó). El total del patrimonio neto no cambia: solo cambia la partida.
-- =====================================================================
insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line) values
  ('normal', '80', 'PN.A2.I',   'PN.A2.I'),
  ('normal', '90', 'PN.A2.I',   'PN.A2.I'),
  ('normal', '81', 'PN.A2.II',  'PN.A2.II'),
  ('normal', '91', 'PN.A2.II',  'PN.A2.II'),
  ('normal', '82', 'PN.A2.III', 'PN.A2.III'),
  ('normal', '92', 'PN.A2.III', 'PN.A2.III')
on conflict (model, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- Abreviado: derivado del normal, como en la 0089
insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line)
select 'abreviado', prefix, erp.fs_abridged_line(debit_line), erp.fs_abridged_line(credit_line)
from erp.fs_model_mapping where model = 'normal' and prefix in ('80', '90', '81', '91', '82', '92')
on conflict (model, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- Para poder usarlas: las cuentas de los subgrupos 80-82 y 90-92 en la plantilla del plan de cuentas (hasta ahora solo
-- estaban las de subvenciones, 83-84 y 94; un diario con una 900 no se podía importar). Nombres del PGC tras el
-- RD 1/2021 (pendiente de validar por Diosvely la redacción literal, regla A3). A las empresas que ya existen, como
-- cuentas de título.
-- Limitación conocida: el cierre del ERP (0065) regulariza los grupos 8 y 9 contra la 130; para 80-82 y 90-92 la
-- contrapartida sería la 133, la 1340 o la 135. Queda para auditoría fiscal.
insert into erp.coa_template (account_no, name, name_en, account_category) values
('80',  'Gastos financieros por valoración de activos y pasivos', 'Financial expenses from asset and liability measurement', 'equity'),
('800', 'Pérdidas en activos financieros a valor razonable con cambios en el patrimonio neto', 'Losses on financial assets at fair value through equity', 'equity'),
('802', 'Transferencia de beneficios en activos financieros a valor razonable con cambios en el patrimonio neto', 'Transfer of gains on financial assets at fair value through equity', 'equity'),
('81',  'Gastos en operaciones de cobertura', 'Expenses on hedging transactions', 'equity'),
('810', 'Pérdidas por coberturas de flujos de efectivo', 'Losses on cash flow hedges', 'equity'),
('811', 'Pérdidas por coberturas de inversiones netas en un negocio en el extranjero', 'Losses on hedges of net investments in a foreign operation', 'equity'),
('812', 'Transferencia de beneficios por coberturas de flujos de efectivo', 'Transfer of gains on cash flow hedges', 'equity'),
('813', 'Transferencia de beneficios por coberturas de inversiones netas en un negocio en el extranjero', 'Transfer of gains on hedges of net investments in a foreign operation', 'equity'),
('82',  'Gastos por diferencias de conversión', 'Expenses from translation differences', 'equity'),
('820', 'Diferencias de conversión negativas', 'Negative translation differences', 'equity'),
('821', 'Transferencia de diferencias de conversión positivas', 'Transfer of positive translation differences', 'equity'),
('90',  'Ingresos financieros por valoración de activos y pasivos', 'Financial income from asset and liability measurement', 'equity'),
('900', 'Beneficios en activos financieros a valor razonable con cambios en el patrimonio neto', 'Gains on financial assets at fair value through equity', 'equity'),
('902', 'Transferencia de pérdidas de activos financieros a valor razonable con cambios en el patrimonio neto', 'Transfer of losses on financial assets at fair value through equity', 'equity'),
('91',  'Ingresos en operaciones de cobertura', 'Income from hedging transactions', 'equity'),
('910', 'Beneficios por coberturas de flujos de efectivo', 'Gains on cash flow hedges', 'equity'),
('911', 'Beneficios por coberturas de una inversión neta en un negocio en el extranjero', 'Gains on hedges of a net investment in a foreign operation', 'equity'),
('912', 'Transferencia de pérdidas por coberturas de flujos de efectivo', 'Transfer of losses on cash flow hedges', 'equity'),
('913', 'Transferencia de pérdidas por coberturas de una inversión neta en un negocio en el extranjero', 'Transfer of losses on hedges of a net investment in a foreign operation', 'equity'),
('92',  'Ingresos por diferencias de conversión', 'Income from translation differences', 'equity'),
('920', 'Diferencias de conversión positivas', 'Positive translation differences', 'equity'),
('921', 'Transferencia de diferencias de conversión negativas', 'Transfer of negative translation differences', 'equity')
on conflict (account_no) do nothing;
insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
select c.id, t.account_no, t.name, t.name_en, 'heading', t.account_no, t.account_category
from erp.companies c cross join erp.coa_template t
where t.account_no ~ '^(80|81|82|90|91|92)'
  and not exists (select 1 from erp.gl_accounts g where g.company_id = c.id and g.account_no = t.account_no);

-- Y en el PGC de estudio (0071), con el mismo nombre: cada cuenta de la plantilla tiene allí su ficha y dice dónde
-- aparece (las de tres cifras se guardan con un 0 al final, como la 9400)
insert into erp.pgc_accounts (account, subgroup, name, statement_lines)
select t.account_no || '0', left(t.account_no, 2), t.name,
       jsonb_build_array('ECPN, parte A (ingresos y gastos reconocidos) › ' || case
         when t.account_no in ('800', '900') then 'I. Por valoración de instrumentos financieros'
         when t.account_no in ('802', '902') then 'VI. Por valoración de instrumentos financieros (transferencias a la cuenta de pérdidas y ganancias)'
         when t.account_no in ('810', '811', '910', '911') then 'II. Por coberturas de flujos de efectivo'
         when t.account_no in ('812', '813', '912', '913') then 'VII. Por coberturas de flujos de efectivo (transferencias a la cuenta de pérdidas y ganancias)'
         when t.account_no in ('820', '920') then 'IV. Diferencias de conversión'
         else 'Diferencias de conversión (transferencias a la cuenta de pérdidas y ganancias)' end
         || ' · Balance: A-2) Ajustes por cambios de valor')
from erp.coa_template t
where t.account_no ~ '^(80|81|82|90|91|92)[0-9]$'
on conflict do nothing;
