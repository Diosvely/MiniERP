# ADR 0027 · Protección del titular de los datos, licencia MIT y dependencias

- **Fecha:** 2026-10-11
- **Versión:** v0.29.1
- **Estado:** aceptada
- **Corrige a:** ADR del rol Miembro (v0.24.0, migración 0027).

## Contexto

Una revisión de seguridad externa (hecha por un agente de IA sobre la v0.28.0) encontró un fallo, **reproducido
también sobre la v0.29.0**:
1. La migración 0027 añadió la columna `erp.company_users.data_owner`: el titular de los datos (rol Miembro) puede
   usar la IA con cuota y publicar su empresa como demo.
2. La política `manage` de `erp.company_users` (migración 0006) deja al **admin de una empresa** editar todas sus
   filas. Quien se registra y crea su empresa es admin de ella.
3. Así, cualquier usuario registrado podía ejecutar desde el navegador
   `update erp.company_users set data_owner = true where user_id = auth.uid();`. Con eso:
   - usaba la IA, gastando la cuota gratuita compartida de Cloudflare;
   - publicaba su empresa como demo, con la mención que quisiera, visible para todos los visitantes.

Antes de la 0027 solo el propietario publicaba demos: era una **regresión**. La revisión señaló también tres faltas
de mantenimiento: el repositorio público no tenía **licencia**, no había **política de seguridad** y nadie vigilaba
las **dependencias**.

## Decisión

1. **Migración `0030_protect_data_owner.sql`:** un trigger `BEFORE INSERT OR UPDATE` en `erp.company_users`.
   - Una fila con `data_owner = true` solo la **crea o la cambia el owner** de la aplicación (en la práctica, con
     `erp.grant_company_access`).
   - Los demás pueden **quitar** la marca (`true → false`), nunca ponerla ni trasladarla a otro usuario o empresa.
   - Sin sesión (SQL Editor, `pg_cron`, migraciones), la regla no se aplica.
   - **Por qué un trigger y no RLS:** una política RLS no compara cómodamente el valor anterior con el nuevo de una
     columna, y la regla es justo esa: quitar sí, poner no.
2. **Prueba `test_fase24_data_owner.sql`:**
   - el owner nombra titulares;
   - un admin no puede nombrarse titular, ni insertar a otro como titular, ni usar la IA, ni publicar la demo;
   - el titular sigue publicando su demo.

   Se comprobó que **falla sin la 0030**.
3. **Licencia MIT** (`LICENSE`): el proyecto es un portfolio para difundir en la comunidad. La MIT permite
   reutilizarlo con la única condición de mantener el aviso de autoría. La AGPL se descartó porque el ERP es un
   laboratorio de formación, no un producto, y hay muchos productos contables en el mercado.
4. **`SECURITY.md`:** los fallos se avisan en privado (*Security → Report a vulnerability*), nunca en un Issue.
5. **Dependabot** (`.github/dependabot.yml`): un PR semanal con las actualizaciones menores de npm, agrupadas, y uno
   mensual con las de GitHub Actions. Pasan por la misma CI. `xlsx` se ignora: viene del CDN de SheetJS.
6. **`docs/seguridad-supabase.md`:** la lista de ajustes del panel de Supabase que no están en el código, y las
   consultas para revisar titulares y demos.

## Tabla de permisos

| Quién | Acción | Resultado |
|---|---|---|
| Propietario de la app | Nombrar titular con `grant_company_access` | ✅ Permitido |
| Titular de los datos | Publicar o retirar su empresa como demo | ✅ Permitido |
| Cualquiera | Quitar la marca de titular (`true → false`) | ✅ Permitido |
| Admin de una empresa (no owner) | Ponerse `data_owner = true` | ❌ Rechazado |
| Admin de una empresa (no owner) | Insertar una fila con `data_owner = true` | ❌ Rechazado |
| Admin de una empresa (no owner) | Trasladar una fila de titular a otro usuario o empresa | ❌ Rechazado |
| SQL Editor, `pg_cron`, migraciones | Cualquier cambio | ✅ La regla no se aplica |

## Consecuencias

- Solo el propietario decide quién es titular. Cualquier usuario sigue llevando su empresa con normalidad.
- **Lección:** una columna nueva que **da poder** (IA, publicar) en una tabla que ya tenía políticas hay que
  revisarla contra esas políticas: la RLS protege filas, no columnas. A partir de ahora, cada columna de permisos
  nueva lleva su prueba de "un usuario normal no puede ponérsela".
- Tras aplicar la 0030 en Supabase, se revisan titulares y demos con las consultas de
  `docs/seguridad-supabase.md`.
- **[MANUAL] en GitHub:** activar *Private vulnerability reporting*, *Dependabot alerts* y *Dependabot security
  updates*.
