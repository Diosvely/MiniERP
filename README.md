# Mini ERP · Contabilidad general española

**🔗 Demo en vivo:** [minierp-6ty.pages.dev](https://minierp-6ty.pages.dev) · Regístrate, crea tu empresa y contabiliza.

ERP web de **contabilidad general** para aprender contabilidad española (**PGC 2007, IVA e IGIC**)
registrando asientos reales. La estructura de datos se inspira en **Microsoft Dynamics 365 Business Central**
y **SAP FI**, simplificada para que cada pieza se entienda. Proyecto de aprendizaje en evolución.

> **English summary.** A web-based general ledger (mini ERP) built to learn Spanish accounting
> (Spanish GAAP – PGC 2007, VAT and Canary Islands IGIC). Data model inspired by Business Central and SAP FI.
> Database in English, bilingual UI (Spanish / English), multi-company, multi-user, accounting rules enforced
> by PostgreSQL. Learning project, work in progress.

---

## ¿Por qué este proyecto?

Después de más de 15 años en control de gestión y costes, al llegar a España necesitaba dominar la
contabilidad española y el funcionamiento real de un ERP. Los ERP comerciales son caros y difíciles de
practicar por cuenta propia, así que decidí **construir uno**. Diseñar la tabla de asientos obliga a
entender *por qué* un ERP impone cada regla. Además, todo el código está en inglés para practicar el
vocabulario técnico de BC y SAP.

## ¿Qué hace hoy? (v0.4.0)

**Contabilidad**
- **Plan General Contable 2007** (grupos 1-7, 352 cuentas) con nombre oficial y traducción al inglés,
  copiado automáticamente a cada empresa.
- **Empresas** por sector (retail, industria, e-commerce, servicios) y territorio fiscal:
  **Península → IVA** o **Canarias → IGIC**.
- **Ejercicio contable** con 12 periodos mensuales que se pueden cerrar.
- **Subcuentas** de 8 dígitos validadas: deben colgar de una cuenta del PGC (título vs. movimiento,
  como *Heading/Posting* en BC).
- **Asientos** con cuadre en vivo. Solo se contabiliza si **Debe = Haber**, con al menos 2 apuntes y en periodo abierto.
- **Numeración correlativa** por ejercicio, sin huecos (segura con varios usuarios a la vez).
- **Inmutabilidad**: un asiento contabilizado no se edita ni se borra; se **anula con contraasiento**.
- **Tipos de IVA e IGIC 2026** con fechas de vigencia y recargo de equivalencia.

**Informes**
- En la web: **libro diario** (bilingüe, importes con formato según idioma).
- En la base de datos, pendientes de pantalla: **libro mayor** con saldo acumulado, **balance de sumas y saldos**
  por nivel y **libro registro de IVA/IGIC**.

**Plataforma**
- **Multiusuario y multiempresa** con roles por empresa (admin, contable, lectura) mediante *Row Level Security*.
- **Empresas DEMO**: el propietario publica empresas de ejemplo que cualquier usuario puede consultar en solo lectura.
- **Límite de empresas por usuario**: los visitantes tienen 1 empresa propia; el propietario, sin límite.
- **Interfaz en español e inglés**, con el idioma guardado por usuario. Funciona en móvil y en ordenador.

## Arquitectura

| Capa | Tecnología | Notas |
|---|---|---|
| Base de datos | **PostgreSQL** en Supabase (schema `erp`) | Las reglas contables viven en la base de datos: triggers, funciones y RLS |
| Autenticación | Supabase Auth | Correo y contraseña |
| Web | **React + Vite** | Componentes por pantalla, i18n propio (es/en) |
| Despliegue | **Cloudflare Pages** | Despliegue automático desde `main` y dirección de prueba por rama |
| Versionado | Git + GitHub | Ramas `feature/*`, Pull Requests, versiones etiquetadas y decisiones documentadas (ADR) |

**Principio clave:** la web nunca es la única barrera. Aunque alguien manipule el navegador, PostgreSQL
rechaza un asiento descuadrado, una escritura en una empresa ajena o la edición de un asiento contabilizado.

## Modelo de datos (resumen)

| Tabla | Equivalente BC | Equivalente SAP |
|---|---|---|
| `companies` | Company | Company Code (BUKRS) |
| `fiscal_years` / `accounting_periods` | Accounting Periods | Fiscal Year / Posting Periods |
| `coa_template` / `gl_accounts` | G/L Account | Chart of Accounts (SKA1 / SKB1) |
| `business_partners` | Customer / Vendor | Business Partner |
| `tax_codes` | VAT Posting Setup | Tax Code (MWSKZ) |
| `journal_entries` / `journal_lines` | G/L Entries | BKPF / BSEG |

Detalle completo en [`docs/modelo-datos.md`](docs/modelo-datos.md) y vocabulario español ↔ inglés ↔ BC ↔ SAP
en [`docs/glosario.md`](docs/glosario.md).

## Estructura del repositorio

```
├── database/
│   ├── migrations/        0001 → 0007, se ejecutan en orden en Supabase
│   ├── reset/             reset del schema antiguo (solo histórico)
│   ├── seed/              datos de ejemplo (opcional)
│   └── tests/             pruebas automáticas en SQL
├── frontend/              web React + Vite
│   └── src/
│       ├── components/    Companies, CompanyView, Accounts, JournalEntryForm, GeneralJournal
│       ├── i18n/          diccionarios es.js / en.js y motor de idioma
│       ├── format.js      formato de importes y nombres de cuenta
│       └── supabase.js    conexión con la base de datos
└── docs/
    ├── bitacora.md        diario del proyecto, sesión a sesión
    ├── modelo-datos.md    tablas, funciones, vistas
    ├── glosario.md        vocabulario contable bilingüe
    └── decisiones/        ADR: por qué se eligió cada cosa
```

## Instalación propia

1. **Base de datos.** En un proyecto de Supabase → *SQL Editor*, ejecuta en orden `database/migrations/0001` … `0007`.
2. **API.** En *Project Settings → Data API → Exposed schemas*, añade `erp`.
3. **Propietario.** Nombra tu usuario como *owner*:
   ```sql
   insert into erp.app_profiles (user_id, app_role, max_companies)
   select id, 'owner', null from auth.users where email = 'tu-correo@ejemplo.com';
   ```
4. **Web.** En `frontend/`, crea `.env.local`:
   ```
   VITE_SUPABASE_URL=https://TU-PROYECTO.supabase.co
   VITE_SUPABASE_KEY=sb_publishable_...
   ```
   Después:
   ```bash
   npm install
   npm run dev
   ```
5. **Despliegue.** En Cloudflare Pages:
   - *Root directory*: `frontend`
   - *Build command*: `npm run build`
   - *Output directory*: `dist`
   - Variables `VITE_SUPABASE_URL` y `VITE_SUPABASE_KEY`.

### Pruebas de la base de datos (PostgreSQL local)

```bash
createdb minierp_test
psql -d minierp_test -f database/tests/supabase_stub.sql
for f in database/migrations/*.sql; do psql -d minierp_test -v ON_ERROR_STOP=1 -f "$f"; done
psql -d minierp_test -f database/tests/test_fase1.sql        # en otra base limpia: test_fase2_demo.sql
```

## Hoja de ruta

- [x] **v0.1.0**: base de datos contable (PGC, asientos, informes en SQL, RLS)
- [x] **v0.2.0**: base de datos en inglés al estilo BC/SAP e interfaz bilingüe
- [x] **v0.3.0**: plan de cuentas, asientos con cuadre en vivo y libro diario en la web
- [x] **v0.4.0**: empresas demo de solo lectura y límites por usuario
- [x] **v0.5.0**: importación de subcuentas desde CSV con vista previa y validación
- [ ] Libro mayor, sumas y saldos, borradores y anulación en la web
- [ ] IVA / IGIC automático, retenciones IRPF y recargo de equivalencia
- [ ] Balance y PyG según el modelo de cuentas anuales del PGC
- [ ] Cierre del ejercicio (regularización 129, cierre y apertura), modelos 303 / 420
- [ ] Importación de libros diarios desde Excel (SAP, BC, Sage) y análisis: flujo de caja y ratios
- [ ] Módulos auxiliares (inmovilizado y amortizaciones) que envían asientos resumen a contabilidad
- [ ] Asistente de IA que analiza los datos con modelos open source

## Autor

**Diosvely Perez Arteaga** · Controller financiero en transición hacia Data & ERP · Canarias, España.
Proyecto personal de aprendizaje: sugerencias y comentarios bienvenidos en *Issues*.