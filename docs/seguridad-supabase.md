# Lista de comprobación: ajustes de seguridad de Supabase

Los ajustes del panel de Supabase no están en el código: hay que revisarlos a mano. Repasa esta lista después de
cada cambio de seguridad y, como mínimo, una vez al trimestre.

## Autenticación
- [ ] **Authentication → Sign In / Providers → Email:** «Confirm email» activado.
- [ ] **Authentication → Sign In / Providers:** «Allow anonymous sign-ins» activado (los invitados de la demo).
- [ ] **Contraseñas:** longitud mínima **8** (la misma que exige la web). «Leaked password protection» activada si el
  plan lo permite.
- [ ] **Authentication → Attack Protection:** CAPTCHA activado con **Turnstile** y su *Secret Key* (v0.28.0).
- [ ] **Authentication → Rate Limits:** valores por defecto o más bajos para registros, inicios de sesión y sesiones
  anónimas.
- [ ] **Authentication → URL Configuration:** «Site URL» y «Redirect URLs» solo con el dominio de Cloudflare Pages
  (y `http://localhost:5173` para desarrollo), sin comodines amplios.

## Base de datos
- [ ] **Database → Extensions:** `pg_cron` activado, y la tarea de limpieza en marcha:
  ```sql
  select jobname, schedule, active from cron.job;   -- erp-cleanup-guests · 30 3 * * * · true
  ```
- [ ] Todas las migraciones aplicadas, hasta la última de `database/migrations/`.
- [ ] **Advisors → Security Advisor:** sin avisos de nivel **ERROR** (RLS desactivada, funciones expuestas…).
- [ ] **Advisors → Performance Advisor:** sin *unindexed foreign keys* (la prueba de la fase 23 lo vigila en el código).

## Claves
- [ ] **Project Settings → API Keys:** la web usa solo la clave **publicable** (`sb_publishable_…`).
- [ ] La clave secreta o `service_role` **no** está en Cloudflare Pages, ni en el repositorio, ni en `.env.local`.
- [ ] La *Secret Key* de Turnstile solo está en Supabase.

## Revisión de titulares y demos
Desde la v0.29.1 solo el propietario puede nombrar titulares de los datos. Aun así, conviene revisar de vez en
cuando que no haya nada que no reconozcas:
```sql
-- Titulares de los datos: deben ser solo los que nombraste tú
select c.name, u.email, cu.role, cu.data_owner, cu.created_at
from erp.company_users cu
join erp.companies c on c.id = cu.company_id
join auth.users u on u.id = cu.user_id
where cu.data_owner
order by cu.created_at;

-- Empresas publicadas como demo: deben ser solo las que conoces
select c.name, c.data_credit, c.created_at, u.email as creada_por
from erp.companies c
left join auth.users u on u.id = c.created_by
where c.is_demo
order by c.created_at;
```
Si aparece algo que no reconoces, corrígelo desde el SQL Editor:
```sql
update erp.company_users set data_owner = false where company_id = '<id>' and user_id = '<id>';
update erp.companies set is_demo = false where id = '<id>';
```
