# Mini ERP · Contabilidad general española

ERP web personal para **aprender contabilidad española** (PGC 2007, IVA peninsular e IGIC canario) **y el inglés técnico** de los ERP
haciendo asientos reales sobre empresas de distintos sectores (retail, industria, e-commerce, servicios).
Multiusuario, usable desde el móvil y el ordenador.

> Proyecto de estudio. La estructura de tablas se inspira en **Microsoft Dynamics 365 Business Central**
> y **SAP FI**, simplificada para que cada pieza se entienda. Base de datos en inglés, comentarios en español,
> interfaz en español o inglés a elección del usuario. Vocabulario en [`docs/glosario.md`](docs/glosario.md).

## Stack

| Capa | Tecnología | Por qué |
|---|---|---|
| Base de datos | Supabase (PostgreSQL) — schema `erp` | Reutiliza un proyecto existente; SQL real; Auth + RLS incluidos |
| Lógica contable | Funciones y triggers en PostgreSQL | Las reglas (Debe = Haber, periodos, inmutabilidad) viven junto a los datos |
| Frontend | React + Vite (PWA) — *pendiente* | Responsive: móvil y escritorio |
| Despliegue web | Cloudflare Pages / Workers | Gratuito y ya en uso |
| Control de versiones | Git (desde el commit 1) | Todo el proceso queda versionado |

## Estructura de carpetas

```
mini-erp/
├── README.md                 ← este archivo (léeme)
├── CHANGELOG.md              ← qué cambia en cada versión
├── database/
│   ├── reset/
│   │   └── 0000_drop_conta.sql           borra el schema antiguo en español (solo una vez)
│   ├── migrations/           ← scripts SQL en orden; se ejecutan UNA vez cada uno
│   │   ├── 0001_core.sql                 companies, users, settings, fiscal years, periods
│   │   ├── 0002_chart_of_accounts.sql    PGC template (groups 1-7, es + en) + G/L accounts
│   │   ├── 0003_partners_tax.sql         business partners, VAT / IGIC tax codes
│   │   ├── 0004_journal_entries.sql      journal entries & lines, post, reverse
│   │   ├── 0005_reports.sql              general journal, ledger, trial balance, tax book
│   │   └── 0006_security_rls.sql         permissions and Row Level Security (multi-user)
│   ├── seed/
│   │   └── demo_empresas.sql             2 empresas de ejemplo: Canarias (IGIC) y Península (IVA)
│   └── tests/
│       ├── supabase_stub.sql             imita auth.* de Supabase para probar en local
│       └── test_fase1.sql                pruebas automáticas de la fase 1
├── docs/
│   ├── bitacora.md           ← diario del proceso de aprendizaje, versión a versión
│   ├── modelo-datos.md       ← tablas, relaciones y equivalencias BC / SAP
│   ├── glosario.md           ← vocabulario español ↔ inglés ↔ BC ↔ SAP
│   └── decisiones/           ← ADR: por qué se eligió cada cosa
└── frontend/                 ← (fase 2) aplicación web
```

## Cómo instalar la base de datos en Supabase

1. En tu proyecto de Supabase → **SQL Editor**, ejecuta **en orden** los archivos de `database/migrations/`
   (0001 → 0006). Cada uno es independiente y comentado.
   *(Si vienes de la v0.1.0, ejecuta antes `database/reset/0000_drop_conta.sql`.)*
2. **Project Settings → Data API → Exposed schemas**: añade `erp` para que la web pueda leerlo.
3. (Opcional) Ejecuta `database/seed/demo_empresas.sql` para tener dos empresas con asientos (necesita un usuario en Authentication).

No toca nada de lo que ya tengas en el schema `public`: todo vive en `erp`.

## Cómo probar en local (sin Supabase)

```bash
createdb minierp_test
psql -d minierp_test -v ON_ERROR_STOP=1 -f database/tests/supabase_stub.sql
for f in database/migrations/*.sql; do psql -d minierp_test -v ON_ERROR_STOP=1 -f "$f"; done
psql -d minierp_test -v ON_ERROR_STOP=1 -f database/tests/test_fase1.sql
```

## Flujo Git del proyecto

- `main` siempre funciona. Cada cambio = un commit con mensaje en español y prefijo:
  `feat` (nuevo), `fix` (corrección), `docs`, `test`, `refactor`, `chore`.
- Al cerrar una fase se crea una etiqueta (`v0.1.0`, `v0.2.0`…) y se anota en `CHANGELOG.md` y `docs/bitacora.md`.
- **Nunca se edita una migración ya ejecutada en Supabase**: se crea una nueva (`0007_…`). Igual que un asiento
  contabilizado: no se borra, se corrige con otro.

## Hoja de ruta

- [x] **v0.1.0** — Base contable: empresas, PGC, asientos con validación, libros y sumas y saldos, multiusuario (RLS)
- [ ] v0.2.0 — Base de datos en inglés (BC / SAP) + frontend web bilingüe (login, empresas, asientos desde el móvil)
- [ ] v0.3.0 — Impuestos automáticos: matriz IVA/IGIC, cálculo de cuotas, recargo de equivalencia, IRPF
- [ ] v0.4.0 — PyG y Balance según modelo de cuentas anuales del PGC
- [ ] v0.5.0 — Plantillas de asientos por sector
- [ ] v0.6.0 — Cierre de ejercicio (regularización 129, cierre y apertura), modelos 303 / 420, conexión Power BI
