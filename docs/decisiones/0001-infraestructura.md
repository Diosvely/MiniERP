# ADR 0001 · Infraestructura: Supabase (schema propio) + Cloudflare

**Fecha:** 2026-09-29 · **Estado:** aceptada

## Contexto
El plan gratuito de Supabase permite 2 proyectos y ambos están en uso. La web se despliega en Cloudflare.

## Decisión
Crear el ERP en un **schema `conta`** dentro de uno de los proyectos existentes, no en un proyecto nuevo.

## Por qué
- Un proyecto de Supabase es un PostgreSQL completo: admite varios schemas aislados entre sí.
- Se conserva Supabase Auth (usuarios, invitaciones) y Row Level Security para el multiusuario.
- Nada de lo existente en `public` se ve afectado.

## Alternativas descartadas (por ahora)
- **Cloudflare D1 (SQLite):** todo en Cloudflare, pero sin autenticación ni RLS integrados.
- **Neon (PostgreSQL):** válido si en el futuro se quiere independizar el ERP de Supabase. Como todo es SQL
  estándar en archivos de migración, el cambio sería sencillo.

## Consecuencias
- Hay que añadir `conta` en *Settings → API → Exposed schemas*.
- Se comparte cuota (almacenamiento, peticiones) con la otra aplicación del mismo proyecto.
