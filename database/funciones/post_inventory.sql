-- =====================================================================
-- erp.post_inventory · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0047_inventory_closing   →   la vigente es la de 0047_inventory_closing
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.post_inventory(p jsonb)
 RETURNS TABLE(count_id uuid, entry_no integer, variation numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_company uuid := (p->>'company_id')::uuid;
  v_date    date := (p->>'count_date')::date;
  v_fy      uuid;
  v_entry   uuid;
  v_count   uuid;
  x         jsonb;
  g         erp.gl_accounts;
  v_init    numeric; v_final numeric; v_imp numeric; v_prev numeric;
  v_var     uuid; v_alw uuid;
  v_n       int := 0;
  v_total   numeric := 0;
  v_no      int;
  v_missing text;
begin
  if not erp.can_write(v_company) then raise exception 'No permission to register inventories in this company'; end if;
  if v_date is null then raise exception 'The count date is required'; end if;
  v_fy := erp.adjust_fiscal_year(v_company, v_date);
  if exists (select 1 from erp.inventory_counts c where c.fiscal_year_id = v_fy and c.status = 'posted') then
    raise exception 'The inventory of this fiscal year is already posted: undo it first';
  end if;
  if jsonb_array_length(coalesce(p->'lines', '[]')) = 0 then raise exception 'The inventory needs at least one stock account'; end if;
  -- todas las cuentas con saldo tienen que estar en el recuento
  select string_agg(i.account_no, ', ') into v_missing from erp.inventory_preview(v_company, v_date) i
  where i.initial_value <> 0 and i.account_no not in (select l->>'account_no' from jsonb_array_elements(p->'lines') l);
  if v_missing is not null then raise exception 'Include every stock account with a balance in the count: %', v_missing; end if;

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
  values (v_company, v_fy, v_date, 'Regularización de existencias al ' || to_char(v_date, 'DD/MM/YYYY'))
  returning id into v_entry;
  insert into erp.inventory_counts (company_id, fiscal_year_id, count_date, entry_id)
  values (v_company, v_fy, v_date, v_entry) returning id into v_count;

  for x in select * from jsonb_array_elements(p->'lines') loop
    select * into g from erp.gl_accounts
    where company_id = v_company and account_no = x->>'account_no' and account_type = 'posting';
    if not found or g.account_no !~ '^3[0-6]' then raise exception 'Account % is not a stock account (30-36)', x->>'account_no'; end if;
    v_final := round(coalesce((x->>'final_value')::numeric, 0), 2);
    v_imp := round(coalesce((x->>'impairment')::numeric, 0), 2);
    if v_final < 0 or v_imp < 0 then raise exception 'The count and the impairment cannot be negative'; end if;
    if v_imp > v_final then raise exception 'The impairment of % cannot exceed its value (%)', g.account_no, v_final; end if;
    v_init := erp.account_balance_in_year(g.id, v_fy, v_date);
    v_var := erp.inventory_account(v_company, g.account_no, 'variation');
    v_alw := erp.inventory_account(v_company, g.account_no, 'allowance');
    v_prev := -erp.account_balance_in_year(v_alw, v_fy, v_date);
    -- baja de la existencia inicial y alta de la final
    if v_init <> 0 then
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
        (v_entry, v_company, v_n + 1, v_var, greatest(v_init, 0), greatest(-v_init, 0), 'Existencia inicial · ' || g.name),
        (v_entry, v_company, v_n + 2, g.id, greatest(-v_init, 0), greatest(v_init, 0), 'Existencia inicial · ' || g.name);
      v_n := v_n + 2;
    end if;
    if v_final > 0 then
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
        (v_entry, v_company, v_n + 1, g.id, v_final, 0, 'Existencia final · ' || g.name),
        (v_entry, v_company, v_n + 2, v_var, 0, v_final, 'Existencia final · ' || g.name);
      v_n := v_n + 2;
    end if;
    -- deterioro: se revierte el anterior y se dota el nuevo
    if v_prev > 0 then
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
        (v_entry, v_company, v_n + 1, v_alw, v_prev, 0, 'Reversión del deterioro anterior · ' || g.name),
        (v_entry, v_company, v_n + 2, erp.inventory_account(v_company, g.account_no, 'reversal'), 0, v_prev, 'Reversión del deterioro anterior · ' || g.name);
      v_n := v_n + 2;
    end if;
    if v_imp > 0 then
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
        (v_entry, v_company, v_n + 1, erp.inventory_account(v_company, g.account_no, 'expense'), v_imp, 0, 'Deterioro · ' || g.name),
        (v_entry, v_company, v_n + 2, v_alw, 0, v_imp, 'Deterioro · ' || g.name);
      v_n := v_n + 2;
    end if;
    insert into erp.inventory_count_lines (count_id, company_id, stock_account_id, variation_account_id, initial_value, final_value, impairment, prev_impairment)
    values (v_count, v_company, g.id, v_var, v_init, v_final, v_imp, v_prev);
    v_total := v_total + v_final - v_init;
  end loop;
  if v_n = 0 then raise exception 'Nothing to post: every stock account is zero'; end if;
  v_no := erp.adjust_finish(v_entry);
  count_id := v_count; entry_no := v_no; variation := v_total;
  return next;
end $function$
;
