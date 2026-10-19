-- =====================================================================
-- 0055 · PRACTICAR INTEGRADO: evaluar la IA con los supuestos y glosario · v0.40.0
-- ---------------------------------------------------------------------
--   · Evaluar la IA: el Tutor de asientos (la misma IA que propone asientos) resuelve los supuestos con su enunciado y
--     erp.grade_exercise la corrige igual que a una persona. Cada intento de la IA guarda el modelo que contestó
--     (erp.exercise_attempts.model), para comparar modelos y ver si mejora o empeora con el tiempo.
--   · erp.submit_exercise(clave, respuesta, by, model): el modelo solo se guarda en los intentos de la IA.
--   · erp.v_exercise_progress: además, el modelo y la fecha del último intento de la IA.
--   · Glosario (0038): «Supuesto práctico» y «Catálogo de operaciones».
-- Re-ejecutable.
-- =====================================================================

-- 1) Conceptos (generados desde frontend/src/glossary.js con frontend/tests/glossarySql.js)
insert into erp.concepts (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc) values
('exercise', 530, 'Supuesto práctico', 'Enunciado de una operación real que hay que contabilizar, como en los manuales y exámenes de contabilidad. El ERP corrige el asiento línea a línea: la cuenta por su grupo o subgrupo del PGC (vale cualquier subcuenta), el lado y el importe, y explica los errores frecuentes.', 'Compra de mercaderías por 2.000 + IVA 21 %: 600 D 2.000 · 472 D 420 / 400 H 2.420.', 'Practice case', 'The statement of a real operation to be recorded, as in accounting textbooks and exams. The ERP grades the entry line by line: the account by its PGC group or subgroup (any sub-account is accepted), the side and the amount, and explains frequent mistakes.', 'Purchase of goods for 2,000 + 21 % VAT: 600 Dr 2,000 · 472 Dr 420 / 400 Cr 2,420.', 'Training scenario (sandbox company)', 'Training exercise (IDES / SAP Learning)', '{}'),
('operationCatalog', 540, 'Catálogo de operaciones', 'Las operaciones típicas de una empresa (compra, venta, cobro, nómina, amortización…) con la pantalla del ERP en que se registran y su asiento modelo. En un ERP real, la pantalla elige las cuentas sola: tú solo das los datos de la operación.', 'Una factura de un proveedor se registra en Facturas, no con un asiento manual: el ERP hace 600 / 472 a 400.', 'Operation catalogue', 'The typical operations of a company (purchase, sale, collection, payroll, depreciation…) with the ERP screen where each is recorded and its model entry. In a real ERP the screen picks the accounts: you only enter the details of the operation.', 'A supplier invoice is recorded in Invoices, not with a manual entry: the ERP posts 600 / 472 to 400.', 'Posting groups (posting setup)', 'Automatic account determination (OBYC)', '{}')
on conflict (key) do update set
  sort = excluded.sort, term = excluded.term, definition = excluded.definition, example = excluded.example,
  term_en = excluded.term_en, definition_en = excluded.definition_en, example_en = excluded.example_en,
  bc = excluded.bc, sap = excluded.sap, pgc = excluded.pgc;

-- 2) El modelo de IA que contestó cada intento de la IA
alter table erp.exercise_attempts add column if not exists model text;
-- la hora real de cada intento (no la de la transacción): ordena bien los intentos seguidos de la IA
alter table erp.exercise_attempts alter column created_at set default clock_timestamp();
alter table erp.exercise_attempts drop constraint if exists exercise_attempts_model_check;
alter table erp.exercise_attempts add constraint exercise_attempts_model_check
  check ((by = 'ai' or model is null) and coalesce(length(model), 0) <= 100);

-- 3) Corregir y guardar el intento (ahora con el modelo de la IA)
drop function if exists erp.submit_exercise(text, jsonb, text);
create or replace function erp.submit_exercise(p_key text, p_answer jsonb, p_by text default 'user', p_model text default null)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare g jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in to practise'; end if;
  if p_by not in ('user', 'ai') then raise exception 'Invalid attempt: %', p_by; end if;
  if jsonb_typeof(p_answer) is distinct from 'array' or jsonb_array_length(p_answer) > 30 then raise exception 'Invalid answer'; end if;
  g := erp.grade_exercise(p_key, p_answer);
  insert into erp.exercise_attempts (user_id, exercise, by, answer, score, ok, model)
  values (auth.uid(), p_key, p_by, p_answer, (g->>'score')::int, (g->>'ok')::boolean,
          case when p_by = 'ai' then left(nullif(btrim(p_model), ''), 100) end);
  return g;
end $$;
revoke execute on function erp.submit_exercise(text, jsonb, text, text) from anon, public;
grant execute on function erp.submit_exercise(text, jsonb, text, text) to authenticated;

-- 4) Progreso: lo de antes y, al final, el modelo y la fecha del último intento de la IA
create or replace view erp.v_exercise_progress with (security_invoker = true) as
select x.key, x.sort, x.level, x.operation, x.tax_type, x.title, x.title_en,
       count(t.id) filter (where t.by = 'user') as attempts,
       coalesce(max(t.score) filter (where t.by = 'user'), 0) as best_score,
       coalesce(bool_or(t.ok) filter (where t.by = 'user'), false) as solved,
       max(t.created_at) filter (where t.by = 'user') as last_at,
       ai.score as ai_score,
       ai.ok as ai_ok,
       ai.model as ai_model,
       ai.created_at as ai_at
from erp.exercises x
left join erp.exercise_attempts t on t.exercise = x.key and t.user_id = auth.uid()
left join lateral (select a.score, a.ok, a.model, a.created_at from erp.exercise_attempts a
                   where a.exercise = x.key and a.by = 'ai' and a.user_id = auth.uid()
                   order by a.created_at desc limit 1) ai on true
group by x.key, ai.score, ai.ok, ai.model, ai.created_at;
revoke all on erp.v_exercise_progress from anon, public;
grant select on erp.v_exercise_progress to authenticated;
