# ADR · Accesos y titulares de los datos (rol Miembro)

- **Fecha:** 2026-10-10
- **Versión:** v0.24.0
- **Estado:** aceptada
- **Sustituye en parte a:** la regla "las empresas importadas nunca se publican como demo".

## Contexto

Las contabilidades reales del Modo auditor son de profesionales que compartieron sus datasets en cursos. Se busca
un gancho de colaboración: decirles "tus datos están montados en mi ERP; revisa cómo los analiza y contabiliza la
IA y dame tu criterio". Para eso, quien cede los datos tiene que poder:
- entrar **solo en su empresa**;
- trabajar en ella y usar la IA;
- **decidir él** si se publica como demo.

Las demos eran hasta ahora exclusivas del owner.

## Decisión

1. **Cuatro roles al estilo Microsoft** (área de trabajo de Power BI / Fabric):
   - **Administrador** = el owner, con control total.
   - **Miembro** = el **titular de los datos**: marca `company_users.data_owner` y rol **contable**.
   - **Colaborador** = quien se registra y lleva sus propias empresas.
   - **Visor** = el invitado que mira las demos.
2. **El acceso se da por email** (`grant_company_access`, solo el owner). El usuario tiene que existir: o se
   registra él, o el owner lo crea en Supabase con una contraseña provisional que el usuario cambia desde la web.
   Para alguien nuevo: se registra, envía su fichero, el owner lo importa y le da acceso.
3. **El titular publica su demo** (`set_company_demo`), con una **mención** visible ("Datos del curso de…") y
   aceptando expresamente que los datos serán públicos. El owner conserva el control de **qué datos entran**,
   porque los importa él.
4. **La IA deja de ser solo del owner** (`ai_allowed`): el owner sin límite, en sus empresas; el titular, en la
   suya, con una **cuota diaria** (`ai_consume`, 10 por defecto, configurable por usuario en
   `app_profiles.ai_daily_limit`), porque el plan gratuito de Workers AI es compartido.
5. **Opiniones sobre la IA** (`ai_feedback`): cada respuesta del Tutor y del Analista se puede marcar como
   correcta, a medias o incorrecta, con un comentario. El owner las lee en "Accesos". Así, quien sabe
   contabilidad española ayuda a mejorar la IA.

## Alternativas descartadas

- **Pasar siempre la contraseña al usuario.** Se permite para los conocidos, pero con cambio de contraseña en la
  web. Para gente nueva es mejor que se registre ella misma.
- **Miembro en solo lectura.** Se descartó para que pueda probar el Tutor y contabilizar; su valor es revisar
  cómo contabiliza la IA.
- **Que cualquier colaborador publique demos.** Una demo es pública: riesgo de contenido inapropiado o de datos
  de terceros sin permiso. Solo el owner y el titular invitado.
- **Que el Miembro suba él mismo el fichero.** Se aplaza: de momento el owner revisa e importa cada dataset.

## Consecuencias

- El proyecto pasa de laboratorio personal a **laboratorio colaborativo**, sin perder el control de los datos.
- Las opiniones sobre la IA son un conjunto de casos reales para afinar las instrucciones del tutor.
- La regla de privacidad queda así: *una empresa importada se publica solo si su titular lo decide, con su
  mención y con datos anonimizados*.
- **Pendiente:**
  - aviso por email al dar acceso;
  - que el Miembro suba su fichero y el owner lo apruebe;
  - una pantalla global de opiniones para todas las empresas.