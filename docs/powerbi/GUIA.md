# Guía · Power BI con el Mini ERP (v0.50.0)

Cómo conectar Power BI Desktop al **esquema `bi`** del Mini ERP y cómo construir, con Claude Code y un servidor MCP de
Power BI, un proyecto **PBIP** con el balance, la cuenta de pérdidas y ganancias, el estado de flujos de efectivo y 8
ratios que **cuadran al céntimo con el ERP**. Decisión de diseño: [ADR 0050](../decisiones/0050-puente-power-bi.md).

> Reparto: **el ERP decide** (en qué línea va cada cuenta, cómo se clasifica cada flujo); **Power BI calcula y enseña**
> (medidas DAX de fechas, comparativas y ratios, matrices y gráficos). Si una cifra no cuadra, la referencia es el ERP.

---

## 1. Qué hay en `bi`

Solo las **empresas demo** (marcadas como demo en el ERP). Una empresa sale en Power BI en el siguiente refresco tras
publicarla como demo y desaparece al quitarle la marca. Las temporales nunca llegan.

| Vista | Grano | Claves y columnas |
|---|---|---|
| `dim_empresa` | una empresa demo | `empresa_id` · empresa, territorio, impuesto (IVA / IGIC), sector |
| `dim_fecha` | un día | `fecha` · anio, trimestre, mes, nombre_mes, anio_mes, fin_mes, es_fin_mes |
| `dim_cuenta` | una subcuenta | `cuenta_id` · empresa_id, subcuenta, nombre, cuenta_pgc (4 dígitos), subgrupo, grupo y sus nombres |
| `dim_linea` | una línea de un estado | `clave_linea` (`estado\|código`, p. ej. `balance\|AC`) · estado (`balance`, `pyg`, `efe_indirecto`, `efe_directo`), codigo, clave_padre, orden, nivel, texto, texto_en, es_total |
| `puente_linea` | línea → hoja | `clave_linea` (la línea que se enseña) · `clave_hoja` (cada línea de detalle que suma, ella incluida) |
| `dim_ratio` | un ratio | `ratio` (WC, CR…) · grupo, orden, nombre, formula, unidad, referencia_min / max, `primera_entrega` |
| `fact_apuntes` | una línea de asiento contabilizado | apunte_id · empresa_id, asiento_id, ejercicio, numero, fecha, tipo_asiento, concepto, cuenta_id, debe, haber, importe |
| `fact_saldos_mes` | cuenta × fin de mes × estado | empresa_id, ejercicio, fin_mes, cuenta_id, estado, `clave_hoja`, saldo, **importe** |
| `fact_flujos` | movimiento de tesorería clasificado | empresa_id, ejercicio, estado (`efe_indirecto` / `efe_directo`), `clave_hoja`, subcuenta, nombre, importe |
| `control_estados` | lo que enseña el ERP | empresa_id, ejercicio, fecha, estado, `clave_linea`, importe, numerador, denominador |

**Reglas de los importes** (para no tener que pensar en signos):
- `fact_saldos_mes[importe]` ya lleva el signo con que se enseña: **activo, patrimonio neto y pasivo en positivo**; en la
  PyG, **ingresos en positivo y gastos en negativo**. Es el saldo **acumulado del ejercicio a ese fin de mes**, sin los
  asientos de regularización y de cierre (como el ERP).
- La **línea del balance ya está decidida** según el signo: un banco en descubierto viene en el pasivo.
- Los totales (`es_total`) no tienen importes propios: se obtienen sumando sus hojas con `puente_linea`.
- `fact_flujos` es por **ejercicio**; `control_estados` trae el balance y la PyG por **fin de mes**, y los flujos y los
  ratios por **ejercicio** (con fecha = último día del ejercicio).

---

## 2. Preparar Supabase (una vez, en el SQL Editor)

```sql
grant connect on database postgres to powerbi_reader;
grant powerbi_reader to postgres;                       -- para poder hacer comprobaciones con «set role»
alter role powerbi_reader with login password 'UNA-CONTRASEÑA-LARGA';   -- la tuya; nunca en el repositorio
```

Comprobación (pegar el bloque entero y pulsar Run **una vez**; cada Run es una sesión nueva):

```sql
set role powerbi_reader;
select current_user as usuario, (select count(*) from bi.dim_linea) as lineas,
       (select count(*) from bi.dim_empresa) as empresas_demo, has_schema_privilege('erp', 'usage') as puede_entrar_en_erp;
```

Debe dar `powerbi_reader · 122 · (tus demos) · false`.

---

## 3. Conectar Power BI Desktop

1. **Datos de la conexión:** en Supabase, botón **Connect** → método **Session pooler** (la conexión directa del plan
   gratuito es solo IPv6). De la cadena `postgresql://postgres.XXXX:[PASSWORD]@HOST:5432/postgres` se usan:
   - **Servidor:** `HOST:5432` (copiar el host tal cual: el número de clúster, `aws-0` o `aws-1`, no se adivina);
   - **Base de datos:** `postgres`;
   - **Usuario:** `powerbi_reader.XXXX` (el nombre del usuario, un punto y la referencia del proyecto, `XXXX`). Sin
     la referencia, el *pooler* responde «Tenant or user not found».
2. **Power BI Desktop** → Obtener datos → **Base de datos PostgreSQL** → Servidor y base de datos → modo **Importar**.
3. Credenciales: pestaña **Base de datos**, usuario y contraseña de arriba, **Cifrar conexión** marcado.
   - Si da un error de certificado: en Supabase, *Database Settings → SSL Configuration → Download certificate* e
     instalarlo en Windows en «Entidades de certificación raíz de confianza» (`certmgr.msc`). **Pendiente de
     comprobar por Diosvely.** Quitar el cifrado solo para una prueba en local con datos de demo, nunca para publicar.
4. En el navegador, abrir el esquema **`bi`** y marcar las diez vistas.
5. **Archivo → Guardar como → Proyecto de Power BI (.pbip)**, con el modelo en **TMDL** y el informe en **PBIR**
   (en *Opciones → Características en versión preliminar* si no salen por defecto).

---

## 4. El modelo

### Relaciones (todas 1 → *, dirección simple)

| Desde (1) | Hacia (*) |
|---|---|
| `dim_empresa[empresa_id]` | `fact_apuntes`, `fact_saldos_mes`, `fact_flujos`, `control_estados`, `dim_cuenta` (`empresa_id`) |
| `dim_cuenta[cuenta_id]` | `fact_apuntes[cuenta_id]`, `fact_saldos_mes[cuenta_id]` |
| `dim_fecha[fecha]` | `fact_apuntes[fecha]` |
| `dim_linea[clave_linea]` | `puente_linea[clave_linea]` |

**Sin relación** (se usan con `TREATAS` en las medidas): `fact_saldos_mes[clave_hoja]`, `fact_flujos[clave_hoja]`,
`control_estados[clave_linea]` y `fact_saldos_mes[fin_mes]`. Así una línea de total suma sus hojas sin relaciones
de muchos a muchos.

Marcar `dim_fecha` como **tabla de fechas** (columna `fecha`). Ordenar `dim_linea[texto]` por `dim_linea[orden]` y
`dim_fecha[nombre_mes]` por `dim_fecha[mes]`.

Las medidas DAX de esta guía se han escrito siguiendo la misma lógica que la prueba de la base de datos (fase 67,
donde el balance, la PyG, los flujos y los ratios cuadran al céntimo), pero **se comprueban en Power BI en el primer
ensayo**: si alguna no da la cifra de la sección 6, se corrige aquí.

### Medidas (carpeta «Estados»)

```dax
Fecha de corte = MAX ( dim_fecha[fin_mes] )

Importe línea =
CALCULATE (
    SUM ( fact_saldos_mes[importe] ),
    TREATAS ( VALUES ( puente_linea[clave_hoja] ), fact_saldos_mes[clave_hoja] )
)

Balance =
VAR corte = [Fecha de corte]
RETURN CALCULATE ( [Importe línea], fact_saldos_mes[fin_mes] = corte, fact_saldos_mes[estado] = "balance" )

PyG acumulada =
VAR corte = [Fecha de corte]
RETURN CALCULATE ( [Importe línea], fact_saldos_mes[fin_mes] = corte, fact_saldos_mes[estado] = "pyg" )

PyG del mes =
VAR corte = [Fecha de corte]
VAR anterior = EOMONTH ( corte, -1 )
VAR acum_anterior =
    IF ( YEAR ( anterior ) = YEAR ( corte ),
         CALCULATE ( [Importe línea], fact_saldos_mes[fin_mes] = anterior, fact_saldos_mes[estado] = "pyg" ) )
RETURN [PyG acumulada] - acum_anterior

Balance año anterior =
VAR corte = EOMONTH ( [Fecha de corte], -12 )
RETURN CALCULATE ( [Importe línea], fact_saldos_mes[fin_mes] = corte, fact_saldos_mes[estado] = "balance" )

Flujos =
VAR anio = YEAR ( [Fecha de corte] )
RETURN
CALCULATE (
    SUM ( fact_flujos[importe] ),
    TREATAS ( VALUES ( puente_linea[clave_hoja] ), fact_flujos[clave_hoja] ),
    fact_flujos[ejercicio] = anio
)
```

Las comparativas (variación, %) se construyen sobre estas, con `DIVIDE`.

### Medidas (carpeta «Ratios»): los 8 de la primera entrega, con las fórmulas del ERP

En DAX no hay medidas con parámetros: se crea una medida por cada línea que hace falta. `REMOVEFILTERS ( dim_linea )`
evita que el filtro de la página (por ejemplo `estado = "balance"`) deje en blanco una línea de la PyG.

```dax
Activo corriente = CALCULATE ( [Balance], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "balance|AC" )
Pasivo corriente = CALCULATE ( [Balance], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "balance|PC" )
Pasivo no corriente = CALCULATE ( [Balance], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "balance|PNC" )
Patrimonio neto = CALCULATE ( [Balance], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "balance|PN" )
Activo total = CALCULATE ( [Balance], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "balance|ACT" )
Existencias = CALCULATE ( [Balance], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "balance|AC.I" )
Resultado de explotación = CALCULATE ( [PyG acumulada], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "pyg|PA" )
Resultado del ejercicio = CALCULATE ( [PyG acumulada], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "pyg|PD" )
Cifra de negocios = CALCULATE ( [PyG acumulada], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "pyg|P1" )
Amortización = - CALCULATE ( [PyG acumulada], REMOVEFILTERS ( dim_linea ), dim_linea[clave_linea] = "pyg|P8" )   -- en la PyG va en negativo

Fondo de maniobra = [Activo corriente] - [Pasivo corriente]
Liquidez general = DIVIDE ( [Activo corriente], [Pasivo corriente] )
Prueba ácida = DIVIDE ( [Activo corriente] - [Existencias], [Pasivo corriente] )
Endeudamiento = DIVIDE ( [Pasivo no corriente] + [Pasivo corriente], [Patrimonio neto] + [Pasivo no corriente] + [Pasivo corriente] )
ROA = DIVIDE ( [Resultado de explotación], [Activo total] )
ROE = IF ( [Patrimonio neto] > 0, DIVIDE ( [Resultado del ejercicio], [Patrimonio neto] ) )   -- con PN negativo no tiene sentido
Margen neto = DIVIDE ( [Resultado del ejercicio], [Cifra de negocios] )
EBITDA = [Resultado de explotación] + [Amortización]
```

### Medidas (carpeta «Comprobación»)

```dax
ERP =
VAR corte = [Fecha de corte]
RETURN
CALCULATE (
    SUM ( control_estados[importe] ),
    TREATAS ( VALUES ( dim_linea[clave_linea] ), control_estados[clave_linea] ),
    control_estados[fecha] = corte
)

Diferencia balance = [Balance] - [ERP]
Diferencia PyG = [PyG acumulada] - [ERP]

ERP · Fondo de maniobra =
CALCULATE ( SUM ( control_estados[importe] ),
    control_estados[clave_linea] = "ratio|WC", control_estados[ejercicio] = YEAR ( [Fecha de corte] ) )
-- … y así con los otros 7 (CR, QR, DEBT, ROA, ROE, NPM, EBITDA), cada uno frente a su medida de la carpeta «Ratios»
```

Para los flujos y los ratios, `control_estados` trae un valor por **ejercicio**: comparar al **cierre del ejercicio**
(fecha de corte = 31/12). El ERP redondea los ratios a 4 decimales.

---

## 5. Las páginas del informe

| Página | Contenido |
|---|---|
| **Balance** | Matriz: filas `dim_linea[texto]` filtrada a `estado = "balance"`; valores `[Balance]` y `[Balance año anterior]`. Segmentadores: empresa y fin de mes |
| **Pérdidas y ganancias** | Igual con `estado = "pyg"`; valores `[PyG acumulada]` y `[PyG del mes]` |
| **Flujos de efectivo** | Matriz con `estado = "efe_indirecto"` (y otra con `efe_directo`); valor `[Flujos]` |
| **Ratios** | Tarjetas de los 8 ratios con su referencia de `dim_ratio` |
| **Comprobación** | Balance y PyG: `[Balance]`, `[ERP]` y `[Diferencia balance]` por línea. Tiene que salir **todo a cero** |

Los totales de las matrices (fila «Total») no tienen sentido en un estado contable: desactivarlos. Las líneas con
`es_total = TRUE`, en negrita (formato condicional).

---

## 6. Cifras esperadas · «Taller Atlántico SL» (caso completo), ejercicio 2026

Se carga desde la pantalla de empresas («Casos» → completo) y se publica como demo.

| A 31/12/2026 | Importe |
|---|---|
| Total activo (`balance\|ACT`) = Total patrimonio neto y pasivo (`balance\|PNP`) | 197.160,00 |
| Activo no corriente · Activo corriente | 37.000,00 · 160.160,00 |
| Patrimonio neto · Pasivo no corriente · Pasivo corriente | 134.526,28 · 24.183,74 · 38.449,98 |
| Cifra de negocios (`pyg\|P1`) · Resultado de explotación (`pyg\|PA`) | 120.000,00 · 76.360,00 |
| Resultado financiero · Resultado antes de impuestos | −740,85 · 75.619,15 |
| Impuesto sobre beneficios · **Resultado del ejercicio** (`pyg\|PD`) | −11.342,87 · **64.276,28** |
| Flujos de explotación · inversión · financiación | 64.860,00 · −40.000,00 · 105.000,00 |
| **Aumento neto del efectivo** (los dos métodos) | **129.860,00** |

| A 30/06/2026 | Importe |
|---|---|
| Total activo | 134.198,00 |
| Resultado acumulado | 58.800,00 |

| Ratio (2026) | ERP |
|---|---|
| Fondo de maniobra | 121.710,02 |
| Liquidez general · Prueba ácida | 4,1654 · 3,9573 |
| Endeudamiento | 0,3177 |
| ROA · ROE · Margen neto | 0,3873 · 0,4778 · 0,5356 |
| EBITDA | 79.360,00 |

---

## 7. Instrucciones para Claude Code

Pegar en la sesión de Claude Code, abierta en la carpeta del proyecto PBIP, con el servidor MCP de Power BI
conectado:

> Vas a construir en este proyecto PBIP un informe financiero sobre el esquema `bi` del Mini ERP. Lee primero
> `docs/powerbi/GUIA.md` del repositorio del Mini ERP y síguela al pie de la letra:
> 1. Usa solo las diez vistas de `bi`. No inventes tablas ni columnas, no escribas SQL y no cambies los signos: los
>    importes ya vienen como se enseñan.
> 2. Crea las relaciones de la sección 4 y ninguna más; las líneas de los estados se suman con `TREATAS` sobre
>    `puente_linea`.
> 3. Crea las medidas de la sección 4 en sus carpetas («Estados», «Ratios», «Comprobación»), con formato de número
>    español (miles con punto, dos decimales; los ratios con 4 decimales o en %).
> 4. Crea las páginas de la sección 5.
> 5. Comprueba con la página «Comprobación» y con las cifras de la sección 6 que todo cuadra al céntimo. Si algo no
>    cuadra, no lo ajustes a mano: busca la causa y explícamela.
> 6. Trabaja por etapas (modelo, medidas, páginas, comprobación) y para al final de cada una para que la revise.

---

## 8. Cómo crece (escalable)

Cada informe del ERP que pase a Power BI será **una vista nueva en `bi`**, con el mismo estilo:
`dim_…` para las dimensiones, `fact_…` para los hechos (en español, con las claves `empresa_id`, `cuenta_id`, `fecha`)
y sus cifras del ERP en `control_estados` o en una vista `control_…`. Una vista nueva no rompe un informe que ya exista.
