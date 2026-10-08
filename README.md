# Mini ERP · Contabilidad general española

**🔗 Demo en vivo:** [minierp-6ty.pages.dev/?demo](https://minierp-6ty.pages.dev/?demo) · Entra como invitado, **sin registrarte**,
y consulta las empresas de ejemplo. O regístrate, crea tu empresa y contabiliza.

ERP web de **contabilidad general** para aprender contabilidad española (**PGC 2007, IVA e IGIC**)
como lo haría una gestoría: asientos, terceros, registro de facturas, liquidación trimestral e informes de auditor.
La estructura de datos se inspira en **Microsoft Dynamics 365 Business Central** y **SAP FI**, y el registro de
facturas en los ERP españoles (**A3, Sage, ContaPlus**), simplificado para que cada pieza se entienda.
Proyecto de aprendizaje en evolución.

> **English summary.** A web-based general ledger (mini ERP) built to learn Spanish accounting
> (Spanish GAAP – PGC 2007, VAT and Canary Islands IGIC): business partners, invoice registration with automatic
> VAT/IGIC, quarterly tax settlement (forms 303 / 420), trial balance, general ledger and unusual-balance audit report.
> Data model inspired by Business Central and SAP FI. Database in English, bilingual UI (Spanish / English),
> multi-company, multi-user, guest access to demo companies, accounting rules enforced by PostgreSQL.
> Learning project, work in progress.

---

## ¿Por qué este proyecto?

Después de más de 15 años en control de gestión y costes, al llegar a España necesitaba dominar la
contabilidad española y el funcionamiento real de un ERP. Los ERP comerciales son caros y difíciles de
practicar por cuenta propia, así que decidí **construir uno**. Diseñar la tabla de asientos obliga a
entender *por qué* un ERP impone cada regla. Además, todo el código está en inglés para practicar el
vocabulario técnico de BC y SAP.

## ¿Qué hace hoy? (v0.13.1)

**Contabilidad**
- **Plan General Contable 2007** (grupos 1-7, 352 cuentas) con nombre oficial y traducción al inglés,
  copiado automáticamente a cada empresa. **Subcuentas** de 8 dígitos validadas e **importación desde CSV**
  con vista previa.
- **Empresas** por sector y territorio fiscal: **Península → IVA** o **Canarias → IGIC**. Ejercicio con 12 periodos.
- **Asientos** con cuadre en vivo y manejo rápido con teclado. Numeración correlativa sin huecos.
- **Inmutabilidad**: un asiento contabilizado no se edita ni se borra; se **anula con contraasiento** (con fecha y motivo),
  enlazado al original, como *Reverse Transaction* de BC o la FB08 de SAP.

**Terceros, IVA/IGIC y facturas** (modelo gestoría)
- **Terceros** (clientes 430, proveedores 400, acreedores 410, deudores 440) con su propia subcuenta y
  **validación de NIF/NIE/CIF**.
- **Configuración de impuestos** por tipo (472 soportado / 477 repercutido) con asistente para IVA o IGIC.
- **Registro de facturas** recibidas y emitidas, normales y **rectificativas**, con asiento automático y
  **regla del lado**: devoluciones (608/708), rappels (609/709) y pronto pago (606/706) reducen base y cuota.
  Vista previa del asiento, control de facturas duplicadas y **libro registro** de emitidas y recibidas.
- **Liquidación trimestral** (modelos **303 IVA / 420 IGIC**): borrador por tipo, compensación automática de cuotas,
  devolución en el 4T, cuadre *libro registro ↔ contabilidad* y bloqueo del trimestre declarado.

**Informes (mirada de auditor)**
- **Libro diario** con rango de fechas y búsqueda; **sumas y saldos** por nivel y fecha de corte;
  **libro mayor** con saldo acumulado D/H.
- **Saldos anómalos**: cuentas con saldo contrario a su naturaleza y su reclasificación al cierre
  (572 → 5201, 430 → 438, 400 → 407…). La caja no puede quedar acreedora.

**Plataforma**
- **Multiusuario y multiempresa** con roles por empresa (admin, contable, lectura) mediante *Row Level Security*.
- **Empresas DEMO** publicadas por el propietario y **acceso como invitado sin registro** (solo lectura).
- Menú por **áreas** (Contabilidad · Facturas · Impuestos · Informes · Datos maestros), **español / inglés**
  con selector de bandera, en móvil y en ordenador.

## Arquitectura

| Capa | Tecnología | Notas |
|---|---|---|
| Base de datos | **PostgreSQL** en Supabase (schema `erp`) | Las reglas contables viven en la base de datos: triggers, funciones y RLS |
| Autenticación | Supabase Auth | Correo y contraseña · invitados con *anonymous sign-ins* |
| Web | **React + Vite** | Componentes por pantalla, i18n propio (es/en) |
| Despliegue | **Cloudflare Pages** | Despliegue automático desde `main` y dirección de prueba por rama |
| Versionado | Git + GitHub | Ramas, Pull Requests, versiones etiquetadas y decisiones documentadas (ADR) |

**Principio clave:** la web nunca es la única barrera. Aunque alguien manipule el navegador, PostgreSQL
rechaza un asiento descuadrado, una factura duplicada, una escritura en una empresa ajena o de un invitado,
o la edición de un asiento contabilizado.

## Modelo de datos (resumen)

| Tabla | Equivalente BC | Equivalente SAP |
|---|---|---|
| `companies` | Company | Company Code (BUKRS) |
| `fiscal_years` / `accounting_periods` | Accounting Periods | Fiscal Year / Posting Periods |
| `coa_template` / `gl_accounts` | G/L Account | Chart of Accounts (SKA1 / SKB1) |
| `business_partners` | Customer / Vendor | Business Partner |
| `tax_codes` / `tax_setup` | VAT Product Posting Group / VAT Posting Setup | Tax Code (MWSKZ) / OB40 |
| `journal_entries` / `journal_lines` | G/L Entries | BKPF / BSEG |
| `invoices` / `invoice_tax_lines` | Posted Purchase / Sales Invoices · VAT Entries | FB60 / FB70 · BSET |
| `tax_settlements` | Calc. and Post VAT Settlement | RFUMSV00 |
| `balance_rules` | — | — (regla de auditoría: naturaleza del saldo) |

Detalle en [`docs/modelo-datos.md`](docs/modelo-datos.md) y vocabulario español ↔ inglés ↔ BC ↔ SAP
en [`docs/glosario.md`](docs/glosario.md).

## Documentación

- [Bitácora](docs/bitacora.md): diario del proyecto, versión a versión, con lo aprendido.
- [Decisiones (ADR)](docs/decisiones/): por qué se eligió cada cosa.
- [Guía de Git del proyecto](docs/guia-git.md): plantilla para crear ramas, hacer pull requests y versionar.
- [CHANGELOG](CHANGELOG.md): cambios de cada versión.

## Estructura del repositorio

```
├── database/
│   ├── migrations/        0001 → 0015, se ejecutan en orden en Supabase
│   ├── reset/             reset del schema antiguo (solo histórico)
│   ├── seed/              datos de ejemplo (opcional)
│   └── tests/             pruebas automáticas en SQL (fases 1 → 10)
├── frontend/              web React + Vite
│   └── src/
│       ├── components/    empresas, menú, asientos, diario, facturas, terceros, impuestos, liquidación, informes
│       ├── i18n/          diccionarios es.js / en.js y motor de idioma
│       ├── format.js      formato de importes y nombres de cuenta
│       └── supabase.js    conexión con la base de datos
└── docs/
    ├── bitacora.md        diario del proyecto
    ├── guia-git.md        guía de Git (plantilla)
    ├── modelo-datos.md    tablas, funciones, vistas
    ├── glosario.md        vocabulario contable bilingüe
    └── decisiones/        ADR 0001 → 0009
```

## Instalación propia

1. **Base de datos.** En un proyecto de Supabase → *SQL Editor*, ejecuta en orden `database/migrations/0001` … `0015`.
2. **API.** En *Project Settings → Data API → Exposed schemas*, añade `erp`.
3. **Invitados** (opcional, **después** de la migración 0015): *Authentication → Sign In / Providers* →
   activa **Allow anonymous sign-ins**.
4. **Propietario.** Nombra tu usuario como *owner*:
   ```sql
   insert into erp.app_profiles (user_id, app_role, max_companies)
   select id, 'owner', null from auth.users where email = 'tu-correo@ejemplo.com';
   ```
5. **Web.** En `frontend/`, crea `.env.local` (nunca se sube a Git):
   ```
   VITE_SUPABASE_URL=https://TU-PROYECTO.supabase.co
   VITE_SUPABASE_KEY=sb_publishable_...
   ```
   Después:
   ```bash
   npm install
   npm run dev
   ```
6. **Despliegue.** En Cloudflare Pages:
   - *Root directory*: `frontend`
   - *Build command*: `npm run build`
   - *Output directory*: `dist`
   - Variables `VITE_SUPABASE_URL` y `VITE_SUPABASE_KEY`.

### Pruebas de la base de datos (PostgreSQL local)

Cada fichero de pruebas se ejecuta en una base **limpia** con el simulador de Supabase y todas las migraciones:

```bash
createdb minierp_test
psql -d minierp_test -f database/tests/supabase_stub.sql
for f in database/migrations/*.sql; do psql -d minierp_test -v ON_ERROR_STOP=1 -f "$f"; done
psql -d minierp_test -f database/tests/test_fase1.sql      # repetir en otra base limpia con test_fase2 … test_fase10
```

## Hoja de ruta

- [x] **v0.1.0**: base de datos contable (PGC, asientos, informes en SQL, RLS)
- [x] **v0.2.0**: base de datos en inglés al estilo BC/SAP e interfaz bilingüe
- [x] **v0.3.0**: plan de cuentas, asientos con cuadre en vivo y libro diario en la web
- [x] **v0.4.0**: empresas demo de solo lectura y límites por usuario
- [x] **v0.5.0**: importación de subcuentas desde CSV con vista previa y validación
- [x] **v0.6.0**: terceros con subcuenta automática y validación de NIF/NIE/CIF
- [x] **v0.7.0**: configuración de impuestos IVA/IGIC
- [x] **v0.8.0**: registro de facturas recibidas y emitidas, rectificativas y libro registro
- [x] **v0.9.0**: liquidación trimestral de IVA/IGIC (modelos 303 / 420)
- [x] **v0.10.0**: sumas y saldos, libro mayor y saldos anómalos
- [x] **v0.11.0 – v0.13.1**: menú por áreas, diario con rango de fechas, anulación de asientos, demo sin registro, selector de idioma con bandera
- [x] **v0.14.0**: balance de situación y PyG (modelo PYMES del PGC)
- [x] **v0.15.0**: cierre del ejercicio (regularización, cierre, apertura y reapertura)
- [x] **v0.16.0**: retención IRPF (111/115) y operaciones exentas, exportaciones, intracomunitarias y no sujetas
- [x] **v0.17.0**: inversión del sujeto pasivo, adquisiciones intracomunitarias y recargo de equivalencia
- [x] **v0.18.0**: prorrata general (bloque J5 completo: casos especiales de IVA/IGIC)
- [x] **v0.19.0**: Modo auditor (1): importación de diarios de Sage y Dynamics BC
- [ ] **v0.20.0**: Modo auditor (2): estado de flujos de efectivo (directo e indirecto)
- [ ] Creacion de  ratios
- [ ] Asistente de IA que analiza los datos con modelos open source
- [ ] Módulos auxiliares (inmovilizado y amortizaciones) que envían asientos resumen a contabilidad

*Proyecto de estudio: los tipos impositivos y las reglas fiscales se contrastan con la AEAT y la ATC; no es asesoramiento fiscal.*

## Autor

**Diosvely Perez Arteaga** · Controller financiero en transición hacia Data & ERP · Canarias, España.
Proyecto personal de aprendizaje: sugerencias y comentarios bienvenidos en *Issues*.