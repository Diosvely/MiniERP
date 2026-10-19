-- =====================================================================
-- erp.submit_exercise · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0054_operations_exercises 0055_practice_integration   →   la vigente es la de 0055_practice_integration
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.submit_exercise(p_key text, p_answer jsonb, p_by text DEFAULT 'user'::text, p_model text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
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
end $function$
;
