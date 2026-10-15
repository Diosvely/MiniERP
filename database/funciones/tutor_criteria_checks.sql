-- =====================================================================
-- erp.tutor_criteria_checks · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0026_tutor_checks   →   la vigente es la de 0026_tutor_checks
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tutor_criteria_checks(p_lines jsonb, p_rule text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare
  v_out   jsonb := '[]';
  r       record;
begin
  -- 1. La misma subcuenta en los dos lados
  for r in select x->>'account_no' as acc from jsonb_array_elements(p_lines) x
           group by 1 having sum((x->>'debit')::numeric) > 0 and sum((x->>'credit')::numeric) > 0 loop
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'same_account_both_sides', 'detail', r.acc);
  end loop;

  -- 2. Amortización acumulada que no corresponde a su inmovilizado: 281d ↔ 21d · 280d ↔ 20d
  for r in select distinct left(d->>'account_no', 4) as dep
           from jsonb_array_elements(p_lines) d
           where d->>'account_no' ~ '^28[01][0-9]'
             -- hay inmovilizado del mismo subgrupo (20 / 21) en el asiento…
             and exists (select 1 from jsonb_array_elements(p_lines) a
                         where left(a->>'account_no', 2) = '2' || substr(d->>'account_no', 3, 1))
             -- …pero ninguno es el que corresponde a esta amortización (2818 → 218)
             and not exists (select 1 from jsonb_array_elements(p_lines) a
                             where left(a->>'account_no', 3) = '2' || substr(d->>'account_no', 3, 2)) loop
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'depreciation_mismatch',
                                         'detail', r.dep || ' ↔ 2' || substr(r.dep, 3, 2));
  end loop;

  -- 3. Baja: se abona el inmovilizado y la amortización acumulada también va al Haber
  if exists (select 1 from jsonb_array_elements(p_lines) a
             where a->>'account_no' ~ '^2[0-3]' and (a->>'credit')::numeric > 0)
     and exists (select 1 from jsonb_array_elements(p_lines) d
                 where d->>'account_no' ~ '^28' and (d->>'credit')::numeric > 0) then
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'disposal_depreciation_side', 'detail', '');
  end if;

  -- 4. Proveedor de inmovilizado sin inmovilizado
  if exists (select 1 from jsonb_array_elements(p_lines) x
             where x->>'account_no' ~ '^(523|173)' and (x->>'credit')::numeric > 0)
     and not exists (select 1 from jsonb_array_elements(p_lines) x
                     where x->>'account_no' ~ '^2[0-5]' and (x->>'debit')::numeric > 0) then
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'asset_supplier_misuse', 'detail', '');
  end if;

  -- 5. NRV que no encaja con las cuentas del asiento
  if p_rule is not null and p_rule <> '' and not exists (
       select 1 from jsonb_array_elements(p_lines) x
       where x->>'account_no' ~ case p_rule
               when 'NRV2'  then '^(21|23|281|291|671|771)'
               when 'NRV3'  then '^(21|23|281|291|671|771)'
               when 'NRV4'  then '^(22|282|292|672|772)'
               when 'NRV5'  then '^(20|280|290|670|770)'
               when 'NRV6'  then '^(20|280|290|670|770)'
               when 'NRV10' then '^(3|60|61|39|693|793)'
               when 'NRV12' then '^(472|477|631|634|639)'
               when 'NRV13' then '^(630|633|638|4752|473|474|479)'
               when 'NRV14' then '^(70|71|72|73|74|75)'
               when 'NRV18' then '^(13|74|94)'
               else '.' end) then
    v_out := v_out || jsonb_build_object('level', 'warning', 'code', 'valuation_rule_mismatch', 'detail', p_rule);
  end if;
  return v_out;
end $function$
;
