-- =====================================================================
-- 0080 · Tablero «Rentabilidad y márgenes» (v0.53.0 · ADR 0053)
-- ---------------------------------------------------------------------
-- Diseño validado por Diosvely (plan-tableros.md, 01-11-2026). Primero de los cinco tableros nuevos.
--
--   · UN TABLERO NUEVO SON FILAS DEL CATÁLOGO (0075): 13 métricas, el tablero y sus 4 tarjetas.
--   · LAS CIFRAS SALEN DE LA PyG DEL ERP, partida a partida: aprovisionamientos (4), personal (6), otros gastos de
--     explotación (7), amortización (8) y resultado de explotación (A). El EBITDA es la misma fórmula que en Ratios
--     (resultado de explotación + amortización), y el margen de explotación y el neto, los mismos ratios.
--   · SIGNO EN LAS MÉTRICAS DE PARTIDA: en la PyG los gastos son negativos (se restan). En un tablero se leen mejor en
--     positivo («aprovisionamientos 37.000 €»), así que una métrica de partida puede llevar sign = -1, como ya podían
--     las de grupo. Sin signo, la partida tal cual (como hasta ahora).
--
-- Se puede ejecutar dos veces.
-- =====================================================================

-- ---------- El signo vale para las partidas y los grupos; las sumas, restas y cocientes no lo usan ----------
alter table erp.dash_metrics drop constraint if exists dash_metrics_sign_kind;
alter table erp.dash_metrics add constraint dash_metrics_sign_kind check (sign is null or kind in ('line', 'group'));
comment on column erp.dash_metrics.sign is
  'kind group: 1 = saldo deudor positivo (gastos), -1 = acreedor (ingresos). kind line: -1 = la partida cambiada de signo '
  '(un gasto de la PyG en positivo); null = tal cual.';

create or replace function erp.dash_metric_values(p_company uuid, p_year integer, p_dates date[])
returns table(at date, v jsonb) language plpgsql stable set jit to 'off' as $$
#variable_conflict use_column
declare
  bal jsonb; pyg jsonb; grp jsonb; vals jsonb; m erp.dash_metrics; x numeric; va numeric; vb numeric; d date;
begin
  -- { fecha: { partida: importe } } del Balance y de la PyG, y { fecha: { cuenta: saldo } } de la PyG (los grupos)
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into bal
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'balance', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into pyg
  from (select f.at, jsonb_object_agg(f.code, f.amount) m from erp.fs_amounts_at(p_company, p_year, 'pyg', p_dates) f group by f.at) z;
  select coalesce(jsonb_object_agg(coalesce(z.at::text, '-'), z.m), '{}') into grp
  from (select c.at, jsonb_object_agg(c.account_no, c.balance) m from erp.fs_classified_at(p_company, p_year, 'pyg', p_dates) c group by c.at) z;

  foreach d in array (select array_agg(distinct x) from unnest(p_dates) x) loop
    vals := '{}';
    for m in select * from erp.dash_metrics order by sort loop
      if m.kind = 'line' then
        -- 0080: con signo (-1 = el gasto en positivo)
        x := coalesce(m.sign, 1)
             * coalesce(((case m.statement when 'balance' then bal else pyg end) -> coalesce(d::text, '-') ->> m.line_code)::numeric, 0);
      elsif m.kind = 'group' then
        select m.sign * coalesce(sum(e.value::numeric), 0) into x
        from jsonb_each_text(coalesce(grp -> coalesce(d::text, '-'), '{}')) e where e.key like m.account_prefix || '%';
      else
        va := (vals ->> m.a)::numeric; vb := (vals ->> m.b)::numeric;
        x := case m.kind when 'sum' then va + vb when 'diff' then va - vb
                         else case when vb is null or vb = 0 then null else round(va / vb, 4) end end;
      end if;
      vals := vals || jsonb_build_object(m.code, x);
    end loop;
    at := d; v := vals; return next;
  end loop;
end $$;

-- ---------- Métricas ----------
-- sort: entre las del Resumen de dirección (SALES 10, RESULT 20…). Una métrica usa solo métricas de orden menor.
insert into erp.dash_metrics (code, sort, label, label_en, unit, kind, statement, line_code, account_prefix, sign, a, b, ratio_code, link, help, help_en) values
 ('PROC',       200, 'Aprovisionamientos', 'Procurements', 'eur', 'line', 'pyg', 'P4', null, -1, null, null, null, 'pyg',
  'Compras y variación de existencias de mercaderías y materias primas (partida 4 de la PyG), en positivo.',
  'Purchases and changes in inventories of goods and raw materials (line 4 of the income statement), as a positive figure.'),
 ('STAFF',      210, 'Gastos de personal', 'Personnel expenses', 'eur', 'line', 'pyg', 'P6', null, -1, null, null, null, 'pyg',
  'Sueldos y seguridad social a cargo de la empresa (partida 6 de la PyG), en positivo.',
  'Wages and employer social security (line 6 of the income statement), as a positive figure.'),
 ('OPEX',       220, 'Otros gastos de explotación', 'Other operating expenses', 'eur', 'line', 'pyg', 'P7', null, -1, null, null, null, 'pyg',
  'Servicios exteriores, tributos y pérdidas por créditos comerciales (partida 7 de la PyG), en positivo.',
  'External services, taxes and trade credit losses (line 7 of the income statement), as a positive figure.'),
 ('DEPR',       230, 'Amortización', 'Depreciation', 'eur', 'line', 'pyg', 'P8', null, -1, null, null, null, 'pyg',
  'Amortización del inmovilizado del ejercicio (partida 8 de la PyG), en positivo.',
  'Depreciation and amortisation of the year (line 8 of the income statement), as a positive figure.'),
 ('EBIT',       240, 'Resultado de explotación', 'Operating profit', 'eur', 'line', 'pyg', 'PA', null, null, null, null, null, 'pyg',
  'Lo que gana el negocio antes de intereses e impuestos (resultado A de la PyG).',
  'What the business earns before interest and taxes (result A of the income statement).'),
 ('GROSS',      250, 'Margen bruto', 'Gross margin', 'eur', 'diff', null, null, null, null, 'SALES', 'PROC', null, 'pyg',
  'Cifra de negocios − aprovisionamientos: lo que queda de las ventas después de pagar lo vendido.',
  'Revenue − procurements: what is left of sales after paying for what was sold.'),
 ('EBITDA',     260, 'EBITDA', 'EBITDA', 'eur', 'sum', null, null, null, null, 'EBIT', 'DEPR', 'EBITDA', 'ratios',
  'Resultado de explotación + amortización, como en Ratios. No es caja: no recoge cobros ni pagos pendientes.',
  'Operating profit + depreciation, as in Ratios. It is not cash: it ignores pending receipts and payments.'),
 ('GM_PCT',     270, 'Margen bruto %', 'Gross margin %', 'pct', 'ratio', null, null, null, null, 'GROSS', 'SALES', null, 'pyg',
  'Margen bruto / cifra de negocios: de cada euro vendido, lo que queda después de lo vendido.',
  'Gross margin / revenue.'),
 ('EBITDA_PCT', 280, 'Margen EBITDA', 'EBITDA margin', 'pct', 'ratio', null, null, null, null, 'EBITDA', 'SALES', null, 'ratios',
  'EBITDA / cifra de negocios: lo que genera la explotación por cada euro vendido, antes de amortizar.',
  'EBITDA / revenue.'),
 ('OPM',        290, 'Margen de explotación', 'Operating margin', 'pct', 'ratio', null, null, null, null, 'EBIT', 'SALES', 'OPM', 'ratios',
  'Resultado de explotación / cifra de negocios, como en Ratios.', 'Operating profit / revenue, as in Ratios.'),
 ('PROC_PCT',   300, 'Aprovisionamientos sobre ventas', 'Procurements to revenue', 'pct', 'ratio', null, null, null, null, 'PROC', 'SALES', null, 'pyg',
  'Qué parte de cada euro vendido se va en aprovisionamientos.', 'Share of each euro sold spent on procurements.'),
 ('STAFF_PCT',  310, 'Personal sobre ventas', 'Personnel to revenue', 'pct', 'ratio', null, null, null, null, 'STAFF', 'SALES', null, 'pyg',
  'Qué parte de cada euro vendido se va en personal.', 'Share of each euro sold spent on personnel.'),
 ('OPEX_PCT',   320, 'Otros gastos sobre ventas', 'Other expenses to revenue', 'pct', 'ratio', null, null, null, null, 'OPEX', 'SALES', null, 'pyg',
  'Qué parte de cada euro vendido se va en otros gastos de explotación.', 'Share of each euro sold spent on other operating expenses.'),
 ('DEPR_PCT',   330, 'Amortización sobre ventas', 'Depreciation to revenue', 'pct', 'ratio', null, null, null, null, 'DEPR', 'SALES', null, 'pyg',
  'Qué parte de cada euro vendido se va en amortización.', 'Share of each euro sold spent on depreciation.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en, unit = excluded.unit,
  kind = excluded.kind, statement = excluded.statement, line_code = excluded.line_code, account_prefix = excluded.account_prefix,
  sign = excluded.sign, a = excluded.a, b = excluded.b, ratio_code = excluded.ratio_code, link = excluded.link,
  help = excluded.help, help_en = excluded.help_en;

-- ---------- El tablero ----------
insert into erp.dashboards (code, sort, label, label_en, description, description_en) values
 ('rentabilidad', 20, 'Rentabilidad y márgenes', 'Profitability and margins',
  'Cuánto queda de cada euro vendido: margen bruto, EBITDA y resultado, cómo evolucionan a lo largo del año y en qué se va el dinero.',
  'How much is left of each euro sold: gross margin, EBITDA and profit, how they evolve over the year and where the money goes.')
on conflict (code) do update set sort = excluded.sort, label = excluded.label, label_en = excluded.label_en,
  description = excluded.description, description_en = excluded.description_en;

delete from erp.dash_widgets where dashboard = 'rentabilidad';
insert into erp.dash_widgets (dashboard, sort, kind, size, mode, label, label_en, help, help_en, metrics) values
 ('rentabilidad', 10, 'kpis',  'full', 'end',   'Cifras clave', 'Key figures', null, null, array['SALES', 'GROSS', 'EBITDA', 'RESULT']),
 ('rentabilidad', 20, 'lines', 'full', 'end',   'Márgenes a lo largo del año', 'Margins over the year',
  'Acumulado a cada fin de mes: margen bruto, margen EBITDA y margen neto sobre las ventas, frente al año anterior.',
  'Cumulative at each month end: gross, EBITDA and net margin on revenue, against last year.',
  array['GM_PCT', 'EBITDA_PCT', 'NPM']),
 ('rentabilidad', 30, 'bars',  'full', 'month', 'Ventas y margen bruto de cada mes', 'Revenue and gross margin by month',
  'Lo vendido cada mes y lo que queda después de los aprovisionamientos.',
  'What was sold each month and what is left after procurements.', array['SALES', 'GROSS']),
 ('rentabilidad', 40, 'table', 'full', 'end',   'Estructura de costes', 'Cost structure',
  'Cada coste sobre las ventas, y lo que queda: el margen de explotación y el neto. Con la zona de referencia de Ratios donde la hay.',
  'Each cost on revenue, and what is left: operating and net margin. With the Ratios reference range where there is one.',
  array['PROC_PCT', 'STAFF_PCT', 'OPEX_PCT', 'DEPR_PCT', 'OPM', 'NPM']);

notify pgrst, 'reload schema';
