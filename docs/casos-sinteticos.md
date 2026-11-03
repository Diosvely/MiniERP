# Empresas sintéticas con semilla

Con un número (la **semilla**), un **perfil** y los **meses**, el Mini ERP genera una contabilidad ficticia completa.
Con la misma semilla, cualquiera obtiene **exactamente la misma**, en su Supabase o en el de otro. Sirve para practicar
(cada alumno, «su» empresa reproducible), para informar de un error **sin compartir datos reales** (ADR 0010) y como
datos para las pruebas (ADR 0059).

## Cómo se crea
- **En la web:** en la lista de empresas, «Empresa sintética con semilla». Se elige la semilla (la web propone una al
  azar), el perfil y los meses.
- **Dónde queda:** como al importar.
  - Un registrado sin perfil la tiene en una **empresa temporal**, que se borra sola.
  - Un miembro o el propietario la tiene **permanente**, y cuenta en su límite de empresas.
  - Un invitado no puede crearla.
- **En SQL** (con sesión): `select erp.create_synthetic_company(4817, 'workshop', 12);`

| Perfil | Territorio | Qué trae | Meses |
|---|---|---|---|
| `services` · Servicios | Península (IVA) | Consultora: alquiler con retención (115), asesoría con IRPF (111), dos nóminas, equipos informáticos, préstamo | 1 a 12 |
| `trade` · Comercio | Península (IVA) | Mayorista: compra mercaderías y vende a empresas y a tres tiendas en recargo de equivalencia; sin nóminas | 1 a 12 |
| `workshop` · Taller | Canarias (IGIC) | Recambios, una máquina, un préstamo, dos nóminas, alquiler y asesoría | 1 a 12 |
| `incidents` · Incidencias | Canarias (IGIC) | El taller con cuatro errores sembrados para la lista de control | 6 a 12 |

**En todos los perfiles:**
- constitución el 2 de enero, préstamo el 15 de enero con cuotas mensuales, y la inversión el 20 de enero;
- cada mes, de 6 a 10 ventas y de 4 a 7 compras, cobradas y pagadas antes de vencer (a 30 días);
- cada trimestre, amortización, liquidación y pago de los modelos el día 20 del mes siguiente.

El cierre del ejercicio **no** se genera: lo hace quien aprende.

## Informar de un error con una semilla
1. Abre la empresa sintética donde ves el error y ve a la pantalla donde aparece.
2. Pulsa **«Copiar datos para informar de un error»** (en la cabecera). Se copia algo así:
   ```
   Mini ERP v0.59.0
   Semilla: 4817
   Perfil: workshop (Taller)
   Meses: 12
   Huella: g1-2C3AD24C
   Pantalla: tableros/impuestos
   Fecha de trabajo: 2026-12-31
   Idioma: es
   ```
3. Pégalo en el aviso (una *issue* de GitHub o un mensaje) junto a lo que ves y lo que esperabas.

El texto no lleva tu email, el nombre de la empresa ni sus identificadores internos.

**La huella** (`g1-…`) resume todos los asientos: número, fecha, estado, descripción, cuentas e importes.
- Si quien lo revisa crea la misma semilla, perfil y meses y le sale la misma huella, está viendo exactamente tu
  contabilidad.
- Si sale distinta, algo ha cambiado entre medias (otra versión del generador, o la empresa se ha tocado después de
  crearla).
- `g1` es la versión del generador: si un día cambia la forma de generar, cambia el prefijo y las huellas antiguas no
  se confunden.

## Semillas de la comunidad
Comprobadas con la versión `g1` del generador, con 12 meses.

| Semilla · perfil | Huella | Qué enseña |
|---|---|---|
| 4817 · `workshop` | `g1-2C3AD24C` | Un año de un taller canario: liquidaciones del IGIC de 1.096,25, 1.030,66, 2.497,10 y 3.140,94 €. El 4T queda pendiente de pago en enero, y en el Balance se ve la deuda con Hacienda a corto plazo |
| 4817 · `services` | `g1-A7A35B0D` | **Las mismas ventas que el taller** (292.297,74 €), pero con IVA: compárala con la 4817 · `workshop` para ver el IVA frente al IGIC con la misma base. También tiene el 111 y el 115 |
| 4817 · `trade` | `g1-ECFE0570` | El recargo de equivalencia repercutido (cuentas 4770…) en las ventas a tiendas; un comercio sin nóminas |
| 4817 · `incidents` | `g1-E0B8EF25` | La lista de control con sus cuatro errores: un proveedor deudor (1.500 € en la 40000005, porque la máquina se pagó dos veces), un cliente con 2.675 € vencidos a más de 90 días, un borrador descuadrado y el 2T sin liquidar. Además sale un tercero sin conciliar, que es consecuencia del pago duplicado. ¿Sabes arreglarlos? |

¿Has encontrado una semilla que enseña algo? Propónla con su huella y lo que enseña.

## Límites conocidos
- **Solo 2026:** las cotizaciones de la Seguridad Social se publican cada año y solo está cargada la de 2026.
- **Mismo azar en todos los perfiles:** «servicios» y «taller» con la misma semilla tienen las mismas bases de venta.
  Es útil para comparar, pero no son empresas «distintas».
- **Sin cierres de mes:** la contabilidad mes a mes no se activa.
- **Unos 460 asientos al año:** se generan en unos 3 segundos.
- **No se publica como demo:** las demos son el caso «Taller Atlántico».
