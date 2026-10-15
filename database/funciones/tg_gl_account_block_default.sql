-- =====================================================================
-- erp.tg_gl_account_block_default · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0013_balance_rules   →   la vigente es la de 0013_balance_rules
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_gl_account_block_default()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.account_type = 'posting' and left(new.account_no, 3) in ('570', '571') then
    new.block_inverse_balance := true;
  end if;
  return new;
end $function$
;
