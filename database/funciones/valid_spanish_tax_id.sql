-- =====================================================================
-- erp.valid_spanish_tax_id · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0009_partners   →   la vigente es la de 0009_partners
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.valid_spanish_tax_id(p text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare
  v       text := erp.normalize_tax_id(p);
  letters constant text := 'TRWAGMYFPDXBNJZSQVHLCKE';
  num     bigint;
  s       int := 0;
  d       int;
  c       int;
  i       int;
begin
  if v is null then return false; end if;

  -- NIF
  if v ~ '^[0-9]{8}[A-Z]$' then
    num := left(v, 8)::bigint;
    return substr(letters, (num % 23)::int + 1, 1) = right(v, 1);
  end if;

  -- NIE (X=0, Y=1, Z=2)
  if v ~ '^[XYZ][0-9]{7}[A-Z]$' then
    num := (strpos('XYZ', left(v, 1)) - 1 || substr(v, 2, 7))::bigint;
    return substr(letters, (num % 23)::int + 1, 1) = right(v, 1);
  end if;

  -- CIF
  if v ~ '^[ABCDEFGHJNPQRSUVW][0-9]{7}[0-9A-J]$' then
    for i in 1..7 loop
      d := substr(v, i + 1, 1)::int;
      if i % 2 = 1 then            -- posiciones impares: se duplica y se suman sus cifras
        d := d * 2;
        d := d / 10 + d % 10;
      end if;
      s := s + d;
    end loop;
    c := (10 - s % 10) % 10;
    if left(v, 1) in ('A', 'B', 'E', 'H') then            -- control numérico
      return right(v, 1) = c::text;
    elsif left(v, 1) in ('K', 'P', 'Q', 'S', 'N', 'W') then -- control con letra
      return right(v, 1) = substr('JABCDEFGHI', c + 1, 1);
    else                                                  -- cualquiera de los dos
      return right(v, 1) in (c::text, substr('JABCDEFGHI', c + 1, 1));
    end if;
  end if;

  return false;
end $function$
;
