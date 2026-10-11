-- =====================================================================
-- 0032 · BALANCE Y PyG COMPARATIVOS A MITAD DE EJERCICIO (v0.30.0)
-- ---------------------------------------------------------------------
-- erp.financial_statement ya devolvía la columna del ejercicio anterior (amount_prev). Con una fecha de corte
-- ("hasta el 30/06/2026") comparaba LAS DOS a la misma fecha del año anterior (30/06/2025). Eso es correcto para la
-- PyG, pero no para el Balance:
--   · PyG (flujos del periodo)   → mismo periodo del año anterior: 01/01-30/06/2025.
--   · Balance (foto a una fecha) → cierre del ejercicio anterior: 31/12/2025, el último balance aprobado.
-- Es el criterio de los estados financieros intermedios (NIC 34, apartado 20) y el que siguen Business Central y SAP
-- en sus informes comparativos. Sin fecha de corte no cambia nada: las dos columnas son ejercicios completos.
-- Re-ejecutable.
-- =====================================================================

create or replace function erp.financial_statement(p_company uuid, p_year int, p_statement text, p_to_date date default null)
returns table (code text, parent text, sort int, level int, label text, label_en text, is_total boolean,
               amount numeric, amount_prev numeric)
language sql stable as $$
  with recursive depth(code, level) as (
    select l.code, 0 from erp.fs_lines l where l.statement = p_statement and l.parent is null
    union all
    select c.code, d.level + 1 from depth d join erp.fs_lines c on c.statement = p_statement and c.parent = d.code
  )
  select l.code, l.parent, l.sort, d.level, l.label, l.label_en, l.is_total,
         coalesce(n.amount, 0), coalesce(prev.amount, 0)
  from erp.fs_lines l
  join depth d on d.code = l.code
  left join erp.fs_amounts(p_company, p_year, p_statement, p_to_date) n on n.code = l.code
  -- Ejercicio anterior: el Balance, a su cierre (null = completo); la PyG, hasta la misma fecha del año anterior
  left join erp.fs_amounts(p_company, p_year - 1, p_statement,
                           case when p_statement = 'balance' then null
                                else (p_to_date - interval '1 year')::date end) prev on prev.code = l.code
  where l.statement = p_statement
  order by l.sort;
$$;
