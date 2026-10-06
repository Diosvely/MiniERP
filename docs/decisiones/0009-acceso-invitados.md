# ADR 0009 · Acceso de invitados a las empresas demo

**Fecha:** 2026-10-06 · **Estado:** aceptada

## Contexto
Para compartir el proyecto en LinkedIn, cualquiera debe poder ver las empresas demo sin registrarse.

## Opciones
1. Usuario demo compartido con contraseña pública: cualquiera podría cambiarla o usar la cuenta para escribir.
2. Lectura con la clave anónima (rol `anon`): abriría datos sin sesión y obligaría a duplicar todas las políticas.
3. **Inicios de sesión anónimos de Supabase** (elegida): sesión temporal sin email marcada con `is_anonymous`.

## Decisión
- Un invitado solo lee empresas con `is_demo = true`; `can_write` e `is_admin` devuelven falso; no crea empresas.
- Enlace `/?demo` para entrar directamente; el propietario lo copia desde la web.
- Limpieza periódica de invitados antiguos desde el SQL Editor.

## Pendiente
CAPTCHA en el alta anónima si el volumen de visitas lo requiere.