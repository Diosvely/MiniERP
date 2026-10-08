# ADR · Analista IA con modelos open source (Cloudflare Workers AI)

- **Fecha:** 2026-10-08
- **Versión:** v0.22.0
- **Estado:** aceptada

## Contexto

Con el Modo auditor completo (importación, estados, flujos y ratios), el ERP ya produce cifras calculadas,
cuadradas y con su fórmula. Es el momento de añadir IA, que hasta ahora estaba en la hoja de ruta. Se añade
antes de los módulos auxiliares (inmovilizado, inventario, nóminas), que serán largos.

Hay tres condiciones:
- **gratis**;
- **solo para el propietario**;
- **sin exponer las contabilidades reales**, que son privadas.

## Decisión

1. **La IA interpreta y la base de datos decide.**
   - Los números salen siempre de SQL. A la IA se le pasan ya calculados y redondeados, y se le exige citarlos
     sin recalcular.
   - La IA no contabiliza, no escribe SQL y no cambia nada.
2. **Proveedor: Cloudflare Workers AI**, con un modelo open source; por defecto, Mistral Small 3.1.
   - Tiene un plan gratuito diario (10.000 neuronas, unos 70 análisis). Al agotarse falla; nunca cobra.
   - Cloudflare se compromete a no entrenar con lo que se le envía.
   - La web ya está en Cloudflare Pages, así que la IA se usa a través de un *binding*, **sin clave de API**.
   - El modelo se cambia con la variable `AI_MODEL`, sin tocar el código.
3. **Arquitectura:**
   - La web llama a la Pages Function `/api/ai` con la sesión del usuario.
   - La función pide `erp.ai_context` a Supabase **con esa misma sesión**. La base de datos comprueba que el
     usuario es owner y que puede leer la empresa (RLS).
   - Después llama al modelo y devuelve JSON.
4. **Privacidad:** a la IA solo le llegan **cifras agregadas** (partidas, EFE, ratios, sector y territorio).
   Nunca el nombre de la empresa, los terceros ni los conceptos de los asientos. Una prueba automática lo
   comprueba.
5. **Respuesta estructurada:** resumen, puntos fuertes, alertas, preguntas del auditor y una idea para aprender.
   Si el modelo no devuelve JSON válido, se muestra su texto tal cual.

## Alternativas descartadas

- **APIs de pago** (Claude, OpenAI). Tienen más calidad, pero cuestan dinero y exigen guardar una clave secreta.
- **Gemini y OpenRouter gratuitos.** Su privacidad no es adecuada para datos reales: en el plan gratuito de Gemini
  los datos pueden usarse para mejorar productos, y en OpenRouter depende del proveedor de cada modelo.
- **Ollama en local.** Es perfecto para la privacidad, pero no funciona en la web publicada. Queda como
  opción para estudiar en el ordenador.
- **Dejar que la IA consulte la base de datos con SQL.** Es un riesgo de seguridad y de cifras inventadas.

## Consecuencias

- La primera prueba con datos reales no inventó ninguna cifra. Sí destapó un **fallo nuestro**:
  - con pérdidas, la *calidad del resultado* dividía dos negativos y daba un positivo engañoso; lo mismo pasaba
    con el ROE si el patrimonio neto era negativo;
  - ahora esos ratios quedan sin valor.
- **Lección:** la IA es también un **revisor** del propio ERP. Si comenta algo raro, conviene mirar primero los datos.
- Se añadió `lower_is_safer`, para que un endeudamiento bajo no salga como alerta.
- **Limitaciones:**
  - la calidad depende del modelo gratuito;
  - el límite diario es compartido;
  - con `npm run dev` no funciona (hace falta la web publicada o `wrangler pages dev`).
- El mismo patrón (contexto en SQL, función y modelo) servirá para el **tutor de asientos** y para los
  **supuestos prácticos autocorregidos**.