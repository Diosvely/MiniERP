# ADR · Tutor de asientos con IA

- **Fecha:** 2026-10-09
- **Versión:** v0.23.0
- **Estado:** aceptada

## Contexto

Después del Analista IA (v0.22.0), el siguiente uso con más valor para aprender es que el alumno describa una
operación ("compro un ordenador a plazos…") y reciba el asiento propuesto según el PGC. El riesgo es evidente:
un modelo puede equivocarse de cuenta, olvidar el impuesto o inventarse una norma, y un asiento mal hecho que
**cuadra** es el error más peligroso, porque parece correcto.

## Decisión

1. **La IA propone, el ERP comprueba y el usuario decide.** Nada se contabiliza solo: la propuesta se carga en
   el formulario de asientos, donde el usuario la revisa, la guarda o la contabiliza.
2. **Lo que se le enseña a la IA** (`entry_tutor_context`, solo el owner):
   - el PGC 2007, que es público;
   - los **tipos de IVA / IGIC vigentes de la empresa** con sus cuentas, y las retenciones;
   - la **lista cerrada de las 23 NRV** (tabla `valuation_rules`).

   Nunca las subcuentas ni los terceros de la empresa, porque pueden llevar nombres reales.
3. **El impuesto lo pone el ERP, no la IA.** La IA indica el código (`VAT21`, `IGIC7`…) y la base. La cuenta y la
   cuota salen de nuestras tablas; si la IA calcula mal, se corrige y se avisa.
4. **Validación** (`validate_proposed_entry`):
   - cuentas del PGC convertidas a subcuentas de la empresa (existentes o nuevas, nunca la de otro tercero);
   - el tercero, si el usuario lo nombra y existe;
   - Debe = Haber;
   - **reglas de criterio** (0026): la misma cuenta en los dos lados, una amortización que no corresponde a su
     elemento (218 ↔ 2818), la amortización acumulada en el Haber en una baja, la 523 / 173 sin inmovilizado y una
     NRV que no encaja con las cuentas.
5. **Segunda vuelta.** Si hay errores o avisos de criterio, se le devuelven a la IA **una vez** para que corrija.
6. **Modelo:** `gpt-oss-120b` (OpenAI, open source) en Workers AI para el tutor, con Mistral Small como respaldo
   automático. El Analista de ratios sigue con Mistral Small.

## Alternativas descartadas

- **Dejar que la IA elija las cuentas del impuesto y calcule la cuota.** Es la fuente de error más habitual y la
  que el ERP ya resuelve con datos fiables.
- **Contabilizar directamente.** El objetivo es aprender, y el usuario tiene que revisar cada asiento.
- **Enviar el plan de cuentas de la empresa.** En las empresas importadas las subcuentas llevan nombres reales de
  clientes y proveedores.
- **Mantener Mistral Small también para el tutor.** En la prueba real dio un asiento de venta de inmovilizado que
  cuadraba pero tenía pérdida en lugar de beneficio.

## Consecuencias

- **Primera prueba (Mistral Small):** 1 de 3 operaciones correcta. Errores de criterio (523 para una abogada,
  NRV 14ª en un gasto) y una baja de inmovilizado mal hecha que cuadraba.
- **Segunda prueba (gpt-oss-120b, con reglas y una guía de cuentas):** **3 de 3 correctas**, incluida la baja de
  la furgoneta con su beneficio en la 771.
- Se añadieron al PGC las cuentas **2800–2806 y 2811–2819** (amortización acumulada por elemento), que faltaban.
- **Coste:** unos 5.000 tokens por consulta, con un límite diario gratuito de unos 30 asientos compartido con el
  Analista.
- **Pendiente:**
  - mejorar las preguntas de comprobación;
  - si el tercero no está dado de alta, el ERP usa la primera subcuenta genérica de su cuenta: conviene crear el
    tercero antes.
- El patrón queda listo para los **supuestos prácticos autocorregidos** y para ayudar en los módulos de
  inmovilizado, inventario y nóminas.