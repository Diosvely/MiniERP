-- =====================================================================
-- erp.tg_partner_account · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0094_integrity_hardening   →   la vigente es la de 0094_integrity_hardening
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.tg_partner_account()
 RETURNS trigger
 LANGUAGE plpgsql
 SET jit TO 'off'
AS $function$
declare
  v_account erp.gl_accounts;
  v_prefix  text;
begin
  if new.gl_account_id is null
     or coalesce(current_setting('erp.deleting_company', true), '') = 'on' then
    return new;
  end if;
  select * into v_account from erp.gl_accounts where id = new.gl_account_id;
  if not found or v_account.company_id <> new.company_id then
    raise exception 'The account does not belong to this company';
  end if;
  v_prefix := erp.partner_control_account(new.partner_type);
  if v_account.account_type <> 'posting' or v_account.account_no not like v_prefix || '%' then
    raise exception 'The account % does not match the partner type (it must be a %… posting account)',
      v_account.account_no, v_prefix;
  end if;
  return new;
end $function$
;
