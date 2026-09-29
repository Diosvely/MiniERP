-- =====================================================================
-- 0005 · INFORMES: libro diario, libro mayor, sumas y saldos, libro registro IVA/IGIC
-- ---------------------------------------------------------------------
-- Solo cuentan los asientos CONTABILIZADOS. Los borradores no existen para los informes.
-- Las vistas usan security_invoker: cada usuario solo ve lo que le permite RLS.
-- =====================================================================

-- ---------------------------------------------------------------------
-- LIBRO DIARIO: asientos en orden cronológico, con sus apuntes
-- ---------------------------------------------------------------------
create or replace view conta.v_libro_diario with (security_invoker = true) as
select a.empresa_id,
       e.anio          as ejercicio,
       a.numero,
       a.fecha,
       a.concepto      as concepto_asiento,
       a.documento,
       a.tipo,
       p.linea,
       c.codigo        as cuenta,
       c.nombre        as nombre_cuenta,
       p.debe,
       p.haber,
       coalesce(p.concepto, a.concepto) as concepto,
       a.id            as asiento_id
from conta.asientos a
join conta.ejercicios e on e.id = a.ejercicio_id
join conta.apuntes   p on p.asiento_id = a.id
join conta.cuentas   c on c.id = p.cuenta_id
where a.estado = 'contabilizado';

-- ---------------------------------------------------------------------
-- LIBRO MAYOR: movimientos de cada subcuenta con saldo acumulado
-- (saldo positivo = deudor, negativo = acreedor)
-- ---------------------------------------------------------------------
create or replace view conta.v_libro_mayor with (security_invoker = true) as
select a.empresa_id,
       e.anio          as ejercicio,
       c.codigo        as cuenta,
       c.nombre        as nombre_cuenta,
       a.fecha,
       a.numero,
       coalesce(p.concepto, a.concepto) as concepto,
       p.debe,
       p.haber,
       sum(p.debe - p.haber) over (
         partition by p.cuenta_id, a.ejercicio_id
         order by a.fecha, a.numero, p.linea
         rows between unbounded preceding and current row
       ) as saldo
from conta.asientos a
join conta.ejercicios e on e.id = a.ejercicio_id
join conta.apuntes   p on p.asiento_id = a.id
join conta.cuentas   c on c.id = p.cuenta_id
where a.estado = 'contabilizado';

-- ---------------------------------------------------------------------
-- BALANCE DE SUMAS Y SALDOS
--   p_nivel: 1 = grupo, 2 = subgrupo, 3 = cuenta, null = subcuenta
--   p_hasta: fecha de corte (por defecto, todo el ejercicio)
-- Uso: select * from conta.sumas_saldos('<empresa>', 2026, 3);
-- ---------------------------------------------------------------------
create or replace function conta.sumas_saldos(
  p_empresa uuid, p_anio int, p_nivel int default null, p_hasta date default null)
returns table (cuenta text, nombre text, suma_debe numeric, suma_haber numeric,
               saldo_deudor numeric, saldo_acreedor numeric)
language sql stable as $$
  with mov as (
    select case when p_nivel is null then c.codigo else left(c.codigo, p_nivel) end as cuenta,
           p.debe, p.haber
    from conta.apuntes p
    join conta.asientos   a on a.id = p.asiento_id
    join conta.ejercicios e on e.id = a.ejercicio_id
    join conta.cuentas    c on c.id = p.cuenta_id
    where a.empresa_id = p_empresa
      and e.anio = p_anio
      and a.estado = 'contabilizado'
      and (p_hasta is null or a.fecha <= p_hasta)
  )
  select m.cuenta,
         c.nombre,
         sum(m.debe),
         sum(m.haber),
         greatest(sum(m.debe) - sum(m.haber), 0),
         greatest(sum(m.haber) - sum(m.debe), 0)
  from mov m
  left join conta.cuentas c on c.empresa_id = p_empresa and c.codigo = m.cuenta
  group by m.cuenta, c.nombre
  order by m.cuenta;
$$;

-- ---------------------------------------------------------------------
-- LIBRO REGISTRO DE IVA / IGIC
-- Sale de los apuntes de cuotas (cuentas 472 soportado / 477 repercutido)
-- que llevan tipo de impuesto y base imponible.
-- ---------------------------------------------------------------------
create or replace view conta.v_libro_impuestos with (security_invoker = true) as
select a.empresa_id,
       e.anio         as ejercicio,
       a.fecha,
       a.numero       as asiento,
       a.documento,
       case c.cuenta_pgc when '472' then 'soportado' when '477' then 'repercutido' end as clase,
       t.impuesto,
       t.porcentaje,
       tr.nif,
       tr.nombre      as tercero,
       p.base_imponible,
       case c.cuenta_pgc when '472' then p.debe - p.haber else p.haber - p.debe end as cuota
from conta.apuntes p
join conta.asientos         a  on a.id = p.asiento_id
join conta.ejercicios       e  on e.id = a.ejercicio_id
join conta.cuentas          c  on c.id = p.cuenta_id
join conta.impuestos_tipos  t  on t.id = p.impuesto_tipo_id
left join conta.terceros    tr on tr.id = p.tercero_id
where a.estado = 'contabilizado'
  and c.cuenta_pgc in ('472', '477');
