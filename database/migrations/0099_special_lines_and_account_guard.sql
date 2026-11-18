-- =====================================================================
-- 0099 · v0.60.10 · Partidas específicas del Balance (NECA 6.ª), cuentas protegidas y orden de informe para Power BI
-- ---------------------------------------------------------------------
-- 1. AF-35 (Diosvely, 18-11-2026). El modelo normal y el abreviado del Balance son los del PGC (RD 1514/2007, tercera
--    parte, consolidado a 31-03-2025): no les falta ningún epígrafe. Pero la norma 6.ª de elaboración de las cuentas
--    anuales manda CREAR partidas específicas en algunos casos. Las que se pueden decidir por la cuenta:
--    · 6.ª.14 «Diferencia de conversión», dentro de A-2 (moneda funcional distinta del euro): la 135 y, antes del
--      cierre, la 82 y la 92 (que al cerrar van a la 135, AF-16). Hasta ahora iban a «III. Otros».
--    · 6.ª.17 «Deuda con características especiales», a largo y a corto plazo (instrumentos financieros emitidos que se
--      reconocen como pasivos financieros): la 15 a largo; la 502 y la 507 a corto. Hasta ahora iban a «Otros pasivos
--      financieros» y a «Obligaciones y otros valores negociables».
--    Las de 6.ª.8 y 6.ª.16 (deudores y acreedores comerciales no corrientes) dependen del vencimiento, no de la cuenta:
--    no se crean. Y la 1341 (cobertura de una inversión neta en un negocio en el extranjero) es una cobertura: va a
--    «II. Operaciones de cobertura», como la 1340 (todo el subgrupo 134), no a «III. Otros».
--    PYMES no cambia (su modelo no tiene A-2 dividido). El total del patrimonio neto y del pasivo no cambia.
-- 2. SEG-28. Por la API, quien puede escribir en su empresa podía cambiar la empresa de una cuenta, o el número o el tipo
--    de una cuenta con apuntes (los apuntes quedaban en otra cuenta). Ahora: la empresa no cambia nunca; el número y el
--    tipo, solo si la cuenta no tiene apuntes. El nombre y los bloqueos se siguen cambiando.
-- 3. M-04. bi.dim_linea: columna nueva orden_informe, con los totales de nivel 1 (TOTAL ACTIVO, TOTAL PATRIMONIO NETO Y
--    PASIVO, resultado del ejercicio, totales de flujos) al FINAL de sus líneas, como en el modelo del PGC. La columna
--    orden no cambia (los informes que ya ordenan por ella siguen igual).
-- =====================================================================

-- ---------- 1. Partidas específicas (normal y abreviado) ----------
update erp.fs_model_lines set sort = 535 where model = 'normal' and code = 'PN.A2.III';
insert into erp.fs_model_lines (model, code, parent, sort, label, label_en, side, is_total) values
  ('normal',    'PN.A2.DC', 'PN.A2', 534, 'Diferencia de conversión', 'Translation differences', 'credit', false),
  ('normal',    'PNC.DE',   'PNC',   660, 'Deuda con características especiales a largo plazo', 'Long-term debt with special characteristics', 'credit', false),
  ('normal',    'PC.DE',    'PC',    760, 'Deuda con características especiales a corto plazo', 'Short-term debt with special characteristics', 'credit', false),
  ('abreviado', 'PNC.DE',   'PNC',   660, 'Deuda con características especiales a largo plazo', 'Long-term debt with special characteristics', 'credit', false),
  ('abreviado', 'PC.DE',    'PC',    760, 'Deuda con características especiales a corto plazo', 'Short-term debt with special characteristics', 'credit', false)
on conflict (model, code) do update set parent = excluded.parent, sort = excluded.sort, label = excluded.label,
  label_en = excluded.label_en, side = excluded.side, is_total = excluded.is_total;

insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line) values
  ('normal', '134', 'PN.A2.II',  'PN.A2.II'),
  ('normal', '135', 'PN.A2.DC',  'PN.A2.DC'),
  ('normal', '82',  'PN.A2.DC',  'PN.A2.DC'),
  ('normal', '92',  'PN.A2.DC',  'PN.A2.DC'),
  ('normal', '15',  'PNC.DE',    'PNC.DE'),
  ('normal', '502', 'AC.V.5',    'PC.DE'),
  ('normal', '507', 'AC.V.5',    'PC.DE')
on conflict (model, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

-- Abreviado: derivado del normal, como en la 0089 (A-2 no se divide en el abreviado: la diferencia de conversión
-- queda en A-2; las dos de deuda con características especiales sí existen)
insert into erp.fs_model_mapping (model, prefix, debit_line, credit_line)
select 'abreviado', prefix, erp.fs_abridged_line(debit_line), erp.fs_abridged_line(credit_line)
from erp.fs_model_mapping where model = 'normal' and prefix in ('134', '135', '82', '92', '15', '502', '507')
on conflict (model, prefix) do update set debit_line = excluded.debit_line, credit_line = excluded.credit_line;

do $$
begin
  if exists (select 1 from erp.fs_model_mapping m
             where not exists (select 1 from erp.fs_model_lines l where l.model = m.model and l.code = m.debit_line)
                or not exists (select 1 from erp.fs_model_lines l where l.model = m.model and l.code = m.credit_line)) then
    raise exception 'fs_model_mapping points to a missing fs_model_lines code';
  end if;
end $$;

-- ---------- 2. SEG-28 · una cuenta con apuntes no cambia de número, tipo ni empresa ----------
create or replace function erp.tg_gl_account_protect()
returns trigger language plpgsql set jit = off as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;   -- funciones de la base y administrador
  if new.company_id is distinct from old.company_id then
    raise exception 'The company of an account cannot be changed';
  end if;
  if (new.account_no is distinct from old.account_no or new.account_type is distinct from old.account_type)
     and exists (select 1 from erp.journal_lines l where l.gl_account_id = old.id) then
    raise exception 'Account % has journal lines: its number and type cannot be changed', old.account_no;
  end if;
  return new;
end $$;
drop trigger if exists gl_account_protect on erp.gl_accounts;
create trigger gl_account_protect before update on erp.gl_accounts
  for each row execute function erp.tg_gl_account_protect();
revoke execute on function erp.tg_gl_account_protect() from anon, public, authenticated;

-- ---------- 3. M-04 · bi.dim_linea con orden_informe (las columnas de antes no cambian) ----------
create or replace view bi.dim_linea as
with recursive l as (
  select statement as estado, code, parent, sort, label, label_en, is_total, side from erp.fs_lines
  union all
  select case method when 'indirect' then 'efe_indirecto' else 'efe_directo' end, code, parent, sort, label, label_en,
         is_total, null from erp.cf_lines
), depth as (
  select estado, code, 1 as nivel from l where parent is null
  union all
  select l.estado, l.code, d.nivel + 1 from depth d join l on l.estado = d.estado and l.parent = d.code
), down as (
  select estado, code as top, code, sort from l where parent is null
  union all
  select down.estado, down.top, l.code, l.sort from down join l on l.estado = down.estado and l.parent = down.code
)
select l.estado || '|' || l.code as clave_linea, l.estado, l.code as codigo,
       case when l.parent is null then null else l.estado || '|' || l.parent end as clave_padre,
       l.sort as orden, d.nivel, l.label as texto, l.label_en as texto_en, l.is_total as es_total, l.side as lado,
       case when l.parent is null
            then (select max(x.sort) from down x where x.estado = l.estado and x.top = l.code) + 1
            else l.sort end as orden_informe
from l join depth d on d.estado = l.estado and d.code = l.code;
comment on view bi.dim_linea is 'Lines of the statements (balance, pyg, efe_indirecto, efe_directo): hierarchy for the matrices. orden_informe puts the level-1 totals after their lines.';
revoke all on bi.dim_linea from public, anon, authenticated;
grant select on bi.dim_linea to powerbi_reader;
