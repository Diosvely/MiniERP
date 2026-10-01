# ADR 0004 · Empresas demo y límite de empresas por usuario

**Fecha:** 2026-10-01 · **Estado:** aceptada

## Contexto
Se quiere compartir la web en LinkedIn. Los visitantes deben poder probarla sin llenar la base de datos
gratuita (500 MB) y ver ejemplos reales, mientras el propietario estudia con libertad.

## Decisión (opción A)
- `erp.app_profiles`: perfil de aplicación. `owner` = sin límite y puede publicar demos; el resto es
  `member` con 1 empresa (configurable con `max_companies`).
- `companies.is_demo`: el owner marca sus empresas de estudio como demo. Cualquier usuario con sesión
  las **lee**; escribir sigue requiriendo rol admin/contable en la empresa.
- Todo se impone en la base de datos (trigger `company_rules` + `can_read()` redefinida), no en la web.

## Alternativas descartadas
- **Usuario demo con contraseña compartida:** cualquiera podría cambiar la contraseña.
- **Botón "Ver demo" con sesión anónima:** se puede añadir más adelante encima de esta opción.

## Consecuencias
- Nombrar al owner desde el SQL Editor:
  `insert into erp.app_profiles (user_id, app_role, max_companies) select id, 'owner', null from auth.users where email = '…';`
- Cada funcionalidad nueva queda disponible para los visitantes en su empresa y visible en las demos.
