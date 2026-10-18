# ADR 0036 · Nóminas: empleados, cotizaciones del año, asiento de la nómina y modelo 111

- **Fecha:** 2026-10-18
- **Versión:** v0.38.0
- **Estado:** aceptada

## Contexto

Hasta ahora la nómina solo se podía registrar con un asiento manual (la plantilla «nómina» del Tutor). Así no se
aprende de dónde sale cada cifra, la 4751 de las nóminas no cuadraba con el modelo 111 y la comprobación de retenciones
tenía que avisar de que «el ERP aún no tiene nóminas».

El objetivo es **aprender el asiento de la nómina** de una pyme, no sustituir a un programa de nóminas. Por eso el plan
del 18-10-2026 fijó el alcance: cuotas desde una tabla de tipos del año, sin bases mínimas por grupo de cotización.
Los empleados son **ficticios**: no se guarda ni DNI ni IBAN ni ningún dato personal.

## Decisión

1. **Tipos de cotización por año** (`erp.ss_rates` y `erp.ss_limits`, migración 0049), los de 2026 según la
   **Orden PJC/297/2026** (BOE 31/03/2026):

   | Concepto | Empresa | Trabajador |
   |---|---|---|
   | Contingencias comunes | 23,60 % | 4,70 % |
   | Desempleo, indefinido / temporal | 5,50 % / 6,70 % | 1,55 % / 1,60 % |
   | FOGASA | 0,20 % | — |
   | Formación profesional | 0,60 % | 0,10 % |
   | MEI | 0,75 % | 0,15 % |
   | Solidaridad (sobre lo que supera la base máxima, 3 tramos) | 0,96 / 1,04 / 1,22 % | 0,19 / 0,21 / 0,24 % |

   - **Base máxima:** 5.101,20 €/mes. La base mínima más baja (1.424,40) solo se usa para avisar.
   - **AT / EP:** va en la ficha del empleado (tarifa de primas, DA 4.ª de la Ley 42/2006). Por defecto es el 1,00 %, el
     de los trabajos exclusivos de oficina.
   - Para otro año basta con una migración con sus filas. Sin tipos del año, la nómina no se calcula.
2. **Ficha del empleado** (`erp.employees`): contrato indefinido o temporal, alta y baja, salario mensual, pagas extra
   (0 a 4) prorrateadas o no, % de IRPF y % de AT / EP.
   - El **% de IRPF lo pone el usuario**: sale del algoritmo de la AEAT (art. 82 del Reglamento del IRPF) con la
     situación personal de cada trabajador, que el ERP no guarda.
3. **Cálculo del recibo** (`erp.payslip_calc`, sin contabilizar):
   - **base de cotización** = salario + prorrata de las pagas extra (art. 147 LGSS), con el tope de la base máxima;
   - cada cuota es la base × su %, redondeada al céntimo;
   - **IRPF** = % × lo que se paga ese mes (el salario y, en su mes, la paga extra);
   - **pagas no prorrateadas:** cada mes se devenga su parte (640 D / 465 H) y se paga en junio y diciembre (o repartidas
     si son 3 o 4). El mes de la paga cuadra el redondeo: 5 × 333,33 + 333,35 = 2.000.
4. **Asiento de la nómina del mes** (`erp.run_payroll`, uno por mes y en orden):

   | Debe | Haber |
   |---|---|
   | 640 salarios (+ la paga extra devengada) | 476 cuotas de la empresa y del trabajador |
   | 642 Seguridad Social a cargo de la empresa | 4751 IRPF |
   | 465 la paga extra que se paga ese mes | 465 líquido a pagar (+ la paga devengada) |

   - **Pagos** (`erp.pay_payroll`): el líquido (465 D / 57x H) y los seguros sociales del mes siguiente (476 D / 57x H).
   - **Deshacer** (`erp.cancel_payroll`): primero el último pago; sin pagos, la nómina, y solo la del último mes.
   - La 465 y la 476 pasan a ser **cuentas controladas** por Nóminas. Sus asientos no se anulan desde el diario.
5. **Integración** (migración 0050):
   - comprobación **«Nóminas frente a la contabilidad (465 / 476)»**;
   - la comprobación de **retenciones (4751)** suma el IRPF de las nóminas;
   - **modelo 111**: las nóminas del trimestre en las casillas 01 a 03 (perceptores, percepciones dinerarias y
     retenciones), junto a los profesionales (07 a 09);
   - **glosario:** «Nómina» y «Seguridad Social a cargo de la empresa».
6. **Web:** pantalla **Nóminas** con la nómina del mes y su vista previa, la lista de nóminas con sus pagos, los recibos
   de salarios desplegables y la ficha del empleado, que calcula la base mientras se escribe.

## Alternativas descartadas
- **Bases mínimas y máximas por grupo de cotización** (11 grupos): mucho dato que cambia cada año para lo que se quiere
  aprender, que es el asiento. Se avisa con la base mínima más baja.
- **Calcular el % de IRPF:** el algoritmo de la AEAT necesita datos personales (hijos, discapacidad, movilidad…) que
  aquí no se guardan a propósito.
- **Incapacidad temporal, horas extra, embargos, atrasos y finiquitos:** fuera de alcance. El alta o la baja a mitad de
  mes se avisa y se prorratea a mano.
- **Una nómina por empleado** en vez de una por mes: en el PGC lo habitual es un asiento por mes con el resumen de la
  nómina. Cada línea del asiento lleva el código del empleado.
- **Pagar los seguros sociales en el mismo asiento:** se ingresan el mes siguiente, y la 476 a fin de año enseña lo que
  se debe a la Seguridad Social.

## Consecuencias
- El ERP hace el ciclo completo de la nómina: recibo, asiento, pago del líquido, pago de la Seguridad Social y modelo 111.
- La 4751 de las nóminas cuadra con el 111.
- **Pruebas:** 45 de 45 en la base de datos y 126 tests en la web.
  - **Fase 44:** el supuesto de referencia (Ana y Luis), calculado a mano con los tipos de 2026.
  - **Fase 45:** la integración (comprobaciones y modelo 111).
  - **Fase 34:** doce meses de nóminas al azar en las dos empresas, con todo lo demás.
