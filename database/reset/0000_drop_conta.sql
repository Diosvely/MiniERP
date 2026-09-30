-- =====================================================================
-- RESET · Elimina el schema antiguo "conta" (v0.1.0, nombres en español)
-- ---------------------------------------------------------------------
-- Ejecutar UNA sola vez en Supabase → SQL Editor, ANTES de las migraciones en inglés.
-- Solo es seguro porque "conta" no tiene datos reales (proyecto de estudio recién creado).
-- Ver docs/decisiones/0003-ingles-y-bilingue.md
-- =====================================================================
drop schema if exists conta cascade;
