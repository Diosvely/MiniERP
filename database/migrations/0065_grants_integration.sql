-- =====================================================================
-- 0065 · SUBVENCIONES INTEGRADAS: cierre de los grupos 8 y 9, baja del activo, ECPN, asistente, auditor, cuentas
--        controladas, glosario y supuestos · v0.44.0
-- ---------------------------------------------------------------------
--   · Cierre del ejercicio: la regularización salda también los grupos 8 y 9, cada cuenta contra su 13x (94x y 84x
--     contra la 13 del mismo tercer dígito; 83x, el efecto impositivo, contra la 130), igual que los grupos 6 y 7 contra
--     la 129; el cierre y la apertura ya llevan la 130. Aviso si queda imputación de subvenciones por contabilizar.
--   · Inmovilizado: al dar de baja un activo, lo que queda de sus subvenciones de capital pasa a resultados (NRV 18.ª);
--     al anular la baja, se deshace.
--   · Estado de cambios en el patrimonio neto (erp.equity_statement): parte A (ingresos y gastos reconocidos) y parte B
--     (estado total, por columnas), comprobado contra el patrimonio neto del balance. Para todas las empresas.
--   · Asistente de cierre: paso nuevo 10 «Subvenciones» (imputación del año): 11 auditor · 12 Impuesto sobre
--     Sociedades · 13 cierre.
--   · Auditor: «grants_ledger» (grupos 8 y 9, 4708, 522 / 172 y 130-132 frente al módulo; la regularización del cierre
--     cuenta como del módulo).
--   · Cuentas controladas: 94, 84, 83 y 4708 (la 130, la 172 y la 522, no: la apertura de una empresa que ya existía las
--     necesita a mano).
--   · Glosario: «Subvención de capital», «Subvención reintegrable», «Grupos 8 y 9» y «ECPN». Practicar: dos supuestos.
-- Re-ejecutable.
-- =====================================================================

-- 1) Vista previa del cierre (versión de la 0061 con la regularización de los grupos 8 y 9 y el aviso de las subvenciones)
CREATE OR REPLACE FUNCTION erp.year_closing_preview(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_fy       erp.fiscal_years;
  v_prev     erp.fiscal_years;
  v_next     erp.fiscal_years;
  v_done     erp.year_closings;
  v_checks   jsonb := '[]';
  v_n        int;
  v_txt      text;
  v_result   numeric;
  v_res_no   text := erp.result_account_no(p_company);
  v_pl       jsonb;
  v_close    jsonb;
  v_reg      jsonb;   -- v0.44.0: regularización de los grupos 8 y 9 (cuenta, saldo y su 13x)
begin
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then
    raise exception 'Fiscal year % does not exist', p_year;
  end if;
  select * into v_prev from erp.fiscal_years where company_id = p_company and year = p_year - 1;
  select * into v_next from erp.fiscal_years where company_id = p_company and year = p_year + 1;
  select * into v_done from erp.year_closings where fiscal_year_id = v_fy.id and status = 'posted';

  -- 1) COMPROBACIONES · error = impide cerrar · warning = hay que aceptarlo · info = solo informa
  if v_prev.id is not null and v_prev.status = 'open'
     and exists (select 1 from erp.journal_entries where fiscal_year_id = v_prev.id and status = 'posted') then
    v_checks := v_checks || jsonb_build_object('code', 'previous_year_open', 'severity', 'error', 'detail', p_year - 1);
  end if;

  select count(*) into v_n from erp.journal_entries where fiscal_year_id = v_fy.id and status = 'draft';
  if v_n > 0 then
    v_checks := v_checks || jsonb_build_object('code', 'draft_entries', 'severity', 'error', 'detail', v_n);
  end if;

  -- Trimestres de IVA / IGIC sin liquidar (después del cierre ya no se podrán contabilizar)
  select string_agg(x.tax || ' ' || x.q || 'T', ', ' order by x.tax, x.q) into v_txt
  from (select case s.tax_type when 'VAT' then 'IVA' else 'IGIC' end as tax, q
        from erp.tax_settlement_setup s cross join generate_series(1, 4) q
        where s.company_id = p_company
          and not exists (select 1 from erp.tax_settlements t
                          where t.company_id = p_company and t.tax_type = s.tax_type
                            and t.year = p_year and t.quarter = q and t.status = 'posted')) x;
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'unsettled_quarters', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- Saldos anómalos graves (p. ej. caja acreedora): se arrastrarían al año siguiente
  select string_agg(a.account_no, ', ' order by a.account_no) into v_txt
  from erp.balance_anomalies(p_company, p_year) a where a.severity = 'error';
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'anomalies', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.35.0 · Inmovilizado sin amortizar hasta el final del ejercicio (la amortización es un gasto del año: NRV 2.ª)
  select string_agg(a.code, ', ' order by a.code) into v_txt
  from erp.fixed_assets a
  where a.company_id = p_company and a.status = 'active' and a.start_date <= v_fy.ending_date
    and erp.asset_depr_at(a.id, v_fy.ending_date) > erp.asset_posted(a.id);
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'assets_not_depreciated', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.36.0 · Periodificaciones de un ejercicio anterior sin revertir (el gasto o el ingreso se quedaría en el balance)
  select string_agg(a.code, ', ' order by a.code) into v_txt
  from erp.accruals a
  where a.company_id = p_company and a.status = 'active' and a.cutoff_date < v_fy.starting_date;
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'accruals_unreversed', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.37.0 · Inventario sin contabilizar (hay existencias o compras de aprovisionamientos) y provisiones sin revisar
  if not exists (select 1 from erp.inventory_counts c where c.fiscal_year_id = v_fy.id and c.status = 'posted')
     -- (solo si la empresa tiene cuentas de existencias: una de servicios con alguna compra suelta no tiene almacén)
     and exists (select 1 from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting' and g.account_no ~ '^3[0-6]') then
    v_checks := v_checks || jsonb_build_object('code', 'inventory_not_counted', 'severity', 'warning', 'detail', p_year);
  end if;
  select string_agg(pv.code, ', ' order by pv.code) into v_txt
  from erp.provisions pv
  where pv.company_id = p_company and pv.status = 'active'
    and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date < v_fy.starting_date)
    and not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                    and m.movement_date between v_fy.starting_date and v_fy.ending_date);
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'provisions_not_reviewed', 'severity', 'warning', 'detail', v_txt);
  end if;

  -- v0.41.0 · Impuesto sobre Sociedades: va antes de la regularización (en modo estricto, sin él no se cierra)
  if v_fy.status = 'open' and erp.pre_tax_result(p_company, v_fy.id) <> 0
     and not exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then
    v_checks := v_checks || jsonb_build_object('code', 'corporate_tax_missing',
      'severity', case when (select control_mode from erp.companies where id = p_company) = 'strict' then 'error' else 'warning' end,
      'detail', p_year);
  end if;
  -- …y después de contabilizarlo, la 473 (retenciones y pagos a cuenta) tiene que quedar a cero
  if v_fy.status = 'open' and exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then
    select string_agg(g.account_no, ', ') into v_txt from (
      select g.account_no from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id join erp.gl_accounts g on g.id = l.gl_account_id
      where e.company_id = p_company and e.fiscal_year_id = v_fy.id and e.status = 'posted' and e.entry_type not in ('closing_pl', 'closing')
        and g.account_no like '473%' group by g.account_no having sum(l.debit - l.credit) <> 0) g;
    if v_txt is not null then
      v_checks := v_checks || jsonb_build_object('code', 'withholdings_left', 'severity', 'warning', 'detail', v_txt);
    end if;
  end if;

  -- v0.42.0 · el resultado del año anterior sigue en la 129: la junta aún no lo ha repartido (Operaciones societarias)
  if v_fy.status = 'open' and erp.equity_bal(p_company, '129', v_fy.ending_date) <> 0 then
    v_checks := v_checks || jsonb_build_object('code', 'result_not_distributed', 'severity', 'warning',
      'detail', erp.equity_bal(p_company, '129', v_fy.ending_date));
  end if;

  -- v0.44.0 · subvenciones de capital sin imputar este año (Subvenciones): la parte del año iría al año siguiente
  if v_fy.status = 'open' and exists (select 1 from erp.grants g where g.company_id = p_company and g.kind = 'capital' and g.status = 'active') then
    declare gy jsonb := erp.grant_year_end_preview(p_company, v_fy.ending_date);
    begin
      if (gy->>'imputation_total')::numeric > 0 or (gy->>'tax_total')::numeric > 0 then
        v_checks := v_checks || jsonb_build_object('code', 'grants_not_imputed', 'severity', 'warning', 'detail', gy->>'imputation_total');
      end if;
    end;
  end if;

  if not exists (select 1 from erp.gl_accounts where company_id = p_company and account_no = v_res_no) then
    v_checks := v_checks || jsonb_build_object('code', 'result_account_created', 'severity', 'info', 'detail', v_res_no);
  end if;
  if v_next.id is null then
    v_checks := v_checks || jsonb_build_object('code', 'next_year_created', 'severity', 'info', 'detail', p_year + 1);
  elsif v_next.status = 'closed' then
    v_checks := v_checks || jsonb_build_object('code', 'next_year_closed', 'severity', 'error', 'detail', p_year + 1);
  end if;

  -- 2) REGULARIZACIÓN: cada cuenta de gastos e ingresos se salda al lado contrario; la diferencia, a la 129
  select -coalesce(sum(b.balance), 0),
         coalesce(jsonb_agg(jsonb_build_object('account_no', b.account_no, 'account_name', b.account_name,
                    'debit', greatest(-b.balance, 0), 'credit', greatest(b.balance, 0)) order by b.account_no), '[]')
    into v_result, v_pl
  from erp.year_account_balances(v_fy.id) b
  where left(b.account_no, 1) in ('6', '7');
  if v_result <> 0 then
    v_pl := v_pl || jsonb_build_object('account_no', v_res_no, 'account_name', 'Resultado del ejercicio',
                      'debit', greatest(-v_result, 0), 'credit', greatest(v_result, 0));
  end if;

  -- 2b) v0.44.0 · REGULARIZACIÓN DE LOS GRUPOS 8 Y 9: cada cuenta se salda contra su 13x (94x / 84x → 13 del mismo
  --     tercer dígito; 83x, el efecto impositivo, → 130). La subcuenta 13x: la primera que haya o, si no, se crea al cerrar
  select coalesce(jsonb_agg(jsonb_build_object('account_no', r.account_no, 'account_name', r.account_name, 'balance', r.balance,
                    'target', coalesce((select min(g.account_no) from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting'
                                         and g.account_no like r.tp || '%'),
                                       (select rpad(r.tp, posting_account_digits - 1, '0') || '1' from erp.companies where id = p_company)))
                  order by r.account_no), '[]')
    into v_reg
  from (select b.account_no, b.account_name, b.balance,
               case when b.account_no like '83%' then '130' else '13' || substr(b.account_no, 3, 1) end as tp
        from erp.year_account_balances(v_fy.id) b where left(b.account_no, 1) in ('8', '9')) r;
  v_pl := v_pl
    || (select coalesce(jsonb_agg(jsonb_build_object('account_no', x->>'account_no', 'account_name', x->>'account_name',
                  'debit', greatest(-(x->>'balance')::numeric, 0), 'credit', greatest((x->>'balance')::numeric, 0)) order by x->>'account_no'), '[]')
        from jsonb_array_elements(v_reg) x)
    || (select coalesce(jsonb_agg(jsonb_build_object('account_no', t.target, 'account_name', 'Subvenciones, donaciones y legados',
                  'debit', greatest(t.bal, 0), 'credit', greatest(-t.bal, 0)) order by t.target), '[]')
        from (select x->>'target' as target, sum((x->>'balance')::numeric) as bal from jsonb_array_elements(v_reg) x group by 1) t where t.bal <> 0);

  -- 3) CIERRE: saldos de balance (grupos 1 a 5) después de la regularización, saldados al lado contrario
  select coalesce(jsonb_agg(jsonb_build_object('account_no', c.account_no, 'account_name', c.account_name,
                    'debit', greatest(-c.balance, 0), 'credit', greatest(c.balance, 0)) order by c.account_no), '[]')
    into v_close
  from (
    select b.account_no, b.account_name,
           b.balance + case when b.account_no = v_res_no then -v_result else 0 end
                     + coalesce((select sum((x->>'balance')::numeric) from jsonb_array_elements(v_reg) x where x->>'target' = b.account_no), 0) as balance
    from erp.year_account_balances(v_fy.id) b
    where left(b.account_no, 1) between '1' and '5'
    union all   -- la 129 aún sin movimientos
    select v_res_no, 'Resultado del ejercicio', -v_result
    where v_result <> 0
      and not exists (select 1 from erp.year_account_balances(v_fy.id) b where b.account_no = v_res_no)
    union all   -- v0.44.0: la 13x aún sin movimientos
    select t.target, 'Subvenciones, donaciones y legados', t.bal
    from (select x->>'target' as target, sum((x->>'balance')::numeric) as bal from jsonb_array_elements(v_reg) x group by 1) t
    where t.bal <> 0 and not exists (select 1 from erp.year_account_balances(v_fy.id) b where b.account_no = t.target)
  ) c
  where c.balance <> 0;

  return jsonb_build_object(
    'year', p_year, 'status', v_fy.status,
    'closing_date', v_fy.ending_date, 'opening_date', v_fy.ending_date + 1,
    'checks', v_checks,
    'can_close', v_fy.status = 'open' and not exists (select 1 from jsonb_array_elements(v_checks) c where c->>'severity' = 'error'),
    'has_warnings', exists (select 1 from jsonb_array_elements(v_checks) c where c->>'severity' = 'warning'),
    'result', coalesce(v_done.result, v_result),
    'result_account_no', v_res_no,
    'closing_pl_lines', v_pl,
    'closing_lines', v_close,
    'closed', v_done.id is not null,
    'closing_id', v_done.id,
    'entries', case when v_done.id is null then null else jsonb_build_object(
       'closing_pl', (select entry_no from erp.journal_entries where id = v_done.closing_pl_entry_id),
       'closing',    (select entry_no from erp.journal_entries where id = v_done.closing_entry_id),
       'opening',    (select entry_no from erp.journal_entries where id = v_done.opening_entry_id)) end,
    'can_reopen', v_done.id is not null and coalesce(v_next.status, 'open') = 'open');
end $function$
;

-- 2) Cierre del ejercicio (versión de la 0017 que crea las 13x de la regularización)
CREATE OR REPLACE FUNCTION erp.close_fiscal_year(p_company uuid, p_year integer, p_accept_warnings boolean DEFAULT false)
 RETURNS TABLE(closing_id uuid, result numeric, closing_pl_no integer, closing_no integer, opening_no integer)
 LANGUAGE plpgsql
AS $function$
declare
  c        jsonb;
  v_fy     erp.fiscal_years;
  v_next   uuid;
  v_pl     uuid;
  v_close  uuid;
  v_open   uuid;
  v_id     uuid;
  v_res_no text;
begin
  if not erp.is_admin(p_company) then
    raise exception 'Only the company admin can close the fiscal year';
  end if;
  perform pg_advisory_xact_lock(hashtext('closing/' || p_company));

  c := erp.year_closing_preview(p_company, p_year);
  if (c->>'status') = 'closed' then
    raise exception 'Fiscal year % is already closed', p_year;
  end if;
  if not (c->>'can_close')::boolean then
    raise exception 'Fiscal year % cannot be closed: %', p_year,
      (select string_agg((x->>'code') || ' (' || (x->>'detail') || ')', ', ')
       from jsonb_array_elements(c->'checks') x where x->>'severity' = 'error');
  end if;
  if (c->>'has_warnings')::boolean and not p_accept_warnings then
    raise exception 'Review and accept the warnings before closing: %',
      (select string_agg((x->>'code') || ' (' || (x->>'detail') || ')', ', ')
       from jsonb_array_elements(c->'checks') x where x->>'severity' = 'warning');
  end if;

  perform set_config('erp.year_closing_engine', 'on', true);
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;

  -- Subcuenta 129 y ejercicio siguiente, si no existen
  v_res_no := c->>'result_account_no';
  if not exists (select 1 from erp.gl_accounts where company_id = p_company and account_no = v_res_no) then
    perform erp.create_posting_account(p_company, v_res_no, 'Resultado del ejercicio', 'Profit (loss) for the year');
  end if;
  -- v0.44.0: las subcuentas 13x de la regularización de los grupos 8 y 9, si no existen
  perform erp.create_posting_account(p_company, l->>'account_no', 'Subvenciones, donaciones y legados')
  from jsonb_array_elements(c->'closing_pl_lines') l
  where not exists (select 1 from erp.gl_accounts g where g.company_id = p_company and g.account_no = l->>'account_no');
  select id into v_next from erp.fiscal_years where company_id = p_company and year = p_year + 1;
  if v_next is null then
    v_next := erp.create_fiscal_year(p_company, p_year + 1);
  end if;

  -- 2) Regularización · 3) Cierre (31/12) · 4) Apertura (1/1), con las líneas del cierre al revés
  v_pl := erp.post_closing_entry(p_company, v_fy.id, v_fy.ending_date, 'closing_pl',
            'Regularización del ejercicio ' || p_year, 'REG-' || p_year, c->'closing_pl_lines');
  v_close := erp.post_closing_entry(p_company, v_fy.id, v_fy.ending_date, 'closing',
            'Asiento de cierre del ejercicio ' || p_year, 'CIE-' || p_year, c->'closing_lines');
  v_open := erp.post_closing_entry(p_company, v_next, v_fy.ending_date + 1, 'opening',
            'Asiento de apertura del ejercicio ' || (p_year + 1), 'APE-' || (p_year + 1),
            (select coalesce(jsonb_agg(jsonb_build_object('account_no', l->>'account_no',
                               'debit', l->'credit', 'credit', l->'debit')), '[]')
             from jsonb_array_elements(c->'closing_lines') l));

  insert into erp.year_closings (company_id, fiscal_year_id, year, result, closing_pl_entry_id, closing_entry_id,
                                 opening_entry_id, warnings)
  values (p_company, v_fy.id, p_year, (c->>'result')::numeric, v_pl, v_close, v_open,
          (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(c->'checks') x where x->>'severity' = 'warning'))
  returning id into v_id;

  update erp.fiscal_years set status = 'closed' where id = v_fy.id;
  perform set_config('erp.year_closing_engine', 'off', true);

  return query select v_id, (c->>'result')::numeric,
    (select entry_no from erp.journal_entries where id = v_pl),
    (select entry_no from erp.journal_entries where id = v_close),
    (select entry_no from erp.journal_entries where id = v_open);
end $function$
;

-- 3) Baja de un activo (versión de la 0046 que imputa lo que queda de sus subvenciones)
CREATE OR REPLACE FUNCTION erp.dispose_asset(p jsonb)
 RETURNS TABLE(entry_no integer, net_book_value numeric, result numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  a        erp.fixed_assets;
  v_date   date := (p->>'disposal_date')::date;
  v_inv    erp.invoices;
  v_price  numeric := 0;
  v_fy     uuid;
  v_entry  uuid;
  v_catch  numeric;
  v_acc    numeric;
  v_nbv    numeric;
  v_res    numeric;
  v_digits int;
  v_no     int;
  v_line   int := 0;
  v_imp    numeric;
begin
  select * into a from erp.fixed_assets where id = (p->>'asset_id')::uuid;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  if a.status <> 'active' then raise exception 'Asset % is already disposed', a.code; end if;
  if v_date is null then raise exception 'The disposal date is required'; end if;
  if v_date < a.start_date then raise exception 'The disposal date cannot be earlier than the start date'; end if;
  if exists (select 1 from erp.asset_events x where x.asset_id = a.id and x.event_date > v_date) then
    raise exception 'Asset % has a later impairment or adjustment', a.code;
  end if;
  if exists (select 1 from erp.asset_depreciations d where d.asset_id = a.id and d.period_end > v_date) then
    raise exception 'Asset % is already depreciated after %: cancel that depreciation first', a.code, v_date;
  end if;
  select id into v_fy from erp.fiscal_years where company_id = a.company_id and v_date between starting_date and ending_date;
  if v_fy is null then raise exception 'No fiscal year for date %', v_date; end if;

  -- Factura de venta: emitida, de esta empresa, y con su línea en la cuenta del activo (eso es el precio)
  if p->>'invoice_id' is not null then
    select * into v_inv from erp.invoices i where i.id = (p->>'invoice_id')::uuid and i.company_id = a.company_id;
    if not found or v_inv.invoice_type <> 'sale' then raise exception 'The sale must be an issued invoice of this company'; end if;
    select coalesce(sum(l.amount * l.sign), 0) into v_price from erp.invoice_lines l
    where l.invoice_id = v_inv.id and l.gl_account_id = a.asset_account_id;
    if v_price <= 0 then raise exception 'Invoice % has no line on the asset account', v_inv.invoice_no; end if;
    if exists (select 1 from erp.fixed_assets x where x.disposal_invoice_id = v_inv.id) then
      raise exception 'Invoice % is already used for another disposal', v_inv.invoice_no;
    end if;
  end if;

  v_catch := erp.asset_depr_at(a.id, v_date) - erp.asset_posted(a.id);
  v_acc := erp.asset_posted(a.id) + greatest(v_catch, 0);
  v_imp := erp.asset_impairment_at(a.id, v_date);                -- v0.37.0: deterioro acumulado
  v_nbv := a.cost - v_acc - v_imp;
  v_res := v_price - v_nbv;
  v_digits := (select posting_account_digits from erp.companies where id = a.company_id);

  insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description, document_no)
  values (a.company_id, v_fy, v_date, left(case when v_inv.id is null then 'Baja de ' else 'Venta de ' end || a.code || ' · ' || a.name, 250),
          v_inv.invoice_no)
  returning id into v_entry;
  if v_catch > 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description) values
      (v_entry, a.company_id, 1, a.expense_account_id, v_catch, 0, 'Amortización hasta la baja'),
      (v_entry, a.company_id, 2, a.depreciation_account_id, 0, v_catch, 'Amortización hasta la baja');
    v_line := 2;
    insert into erp.asset_depreciations (asset_id, company_id, period_end, amount, entry_id)
    values (a.id, a.company_id, v_date, v_catch, v_entry);
  end if;
  if v_acc > 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1, a.depreciation_account_id, v_acc, 0, 'Cancelación de la amortización acumulada');
    v_line := v_line + 1;
  end if;
  if v_imp > 0 then   -- v0.37.0: se cancela el deterioro acumulado (29x)
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1,
            erp.asset_impairment_account(a.company_id, (select account_no from erp.gl_accounts where id = a.asset_account_id), 'allowance'),
            v_imp, 0, 'Cancelación del deterioro');
    v_line := v_line + 1;
  end if;
  if a.cost - v_price <> 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1, a.asset_account_id,
            greatest(v_price - a.cost, 0), greatest(a.cost - v_price, 0), 'Baja del activo');
    v_line := v_line + 1;
  end if;
  if v_res <> 0 then
    insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit, description)
    values (v_entry, a.company_id, v_line + 1,
            erp.asset_result_account(a.company_id, (select account_no from erp.gl_accounts where id = a.asset_account_id), v_res),
            greatest(-v_res, 0), greatest(v_res, 0), case when v_res < 0 then 'Pérdida' else 'Beneficio' end || ' en la baja');
  end if;
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.post_entry(v_entry);
  perform set_config('erp.asset_engine', 'off', true);

  update erp.fixed_assets set status = 'disposed', disposal_date = v_date, disposal_price = v_price,
                              disposal_invoice_id = v_inv.id, disposal_entry_id = v_entry
  where id = a.id;
  entry_no := v_no; net_book_value := v_nbv; result := v_res;
  -- v0.44.0: lo que queda de sus subvenciones de capital, a resultados (NRV 18.ª)
  perform erp.grant_impute_rest(jsonb_build_object('grant_id', g.id, 'date', v_date))
  from erp.grants g
  where g.asset_id = a.id and g.kind = 'capital' and g.status = 'active' and (erp.grant_position(g.id)->>'unconditional')::boolean;
  return next;
end $function$
;

-- 4) Anular la baja (versión de la 0041 que deshace la imputación de sus subvenciones)
CREATE OR REPLACE FUNCTION erp.cancel_disposal(p_asset uuid, p_date date DEFAULT NULL::date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare a erp.fixed_assets; v_no int;
begin
  select * into a from erp.fixed_assets where id = p_asset;
  if not found then raise exception 'Asset not found'; end if;
  if not erp.can_write(a.company_id) then raise exception 'No permission to register fixed assets in this company'; end if;
  if a.status <> 'disposed' then raise exception 'Asset % is not disposed', a.code; end if;
  -- v0.44.0: primero se deshace la imputación de sus subvenciones que hizo la baja
  perform erp.grant_cancel(g.id) from erp.grants g
  where g.asset_id = a.id and g.status = 'imputed'
    and (select v.kind from erp.grant_events v where v.grant_id = g.id and v.status = 'posted' order by v.seq desc limit 1) = 'disposal';
  perform set_config('erp.asset_engine', 'on', true);
  v_no := erp.reverse_entry(a.disposal_entry_id, coalesce(p_date, a.disposal_date), 'Baja anulada');
  perform set_config('erp.asset_engine', 'off', true);
  delete from erp.asset_depreciations where entry_id = a.disposal_entry_id;
  update erp.fixed_assets set status = 'active', disposal_date = null, disposal_price = null,
                              disposal_invoice_id = null, disposal_entry_id = null
  where id = a.id;
  return v_no;
end $function$
;

-- 5) Asistente de cierre (versión de la 0063 con el paso de las subvenciones)
CREATE OR REPLACE FUNCTION erp.closing_checklist(p_company uuid, p_year integer)
 RETURNS TABLE(step integer, code text, status text, detail jsonb, screen text)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_fy    erp.fiscal_years;
  v_type  text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
  v_n     int;
  v_m     int;
  v_txt   text;
begin
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found or not erp.can_read(p_company) then return; end if;

  -- 1) Liquidaciones de IVA / IGIC de los cuatro trimestres
  select count(*) into v_n from erp.tax_settlements s
  where s.company_id = p_company and s.year = p_year and s.status = 'posted' and s.tax_type = v_type;
  select count(*) into v_m from erp.invoices i where i.company_id = p_company and i.fiscal_year_id = v_fy.id;
  step := 1; code := 'settlements'; screen := 'settlement';
  status := case when v_n >= 4 then 'done' when v_m = 0 and v_n = 0 then 'na' else 'pending' end;
  detail := jsonb_build_object('settled', v_n, 'tax', v_type); return next;

  -- 2) Periodificaciones del año anterior revertidas
  select count(*) into v_n from erp.accruals a where a.company_id = p_company and a.status = 'active' and a.cutoff_date < v_fy.starting_date;
  step := 2; code := 'accruals_reversed'; screen := 'adjustments';
  status := case when v_n = 0 then 'done' else 'pending' end; detail := jsonb_build_object('pending', v_n); return next;

  -- 3) Amortización del inmovilizado hasta el 31/12
  select count(*), count(*) filter (where erp.asset_depr_at(a.id, v_fy.ending_date) > erp.asset_posted(a.id)) into v_m, v_n
  from erp.fixed_assets a where a.company_id = p_company and a.status = 'active' and a.start_date <= v_fy.ending_date;
  step := 3; code := 'depreciation'; screen := 'assets';
  status := case when v_m = 0 then 'na' when v_n = 0 then 'done' else 'pending' end;
  detail := jsonb_build_object('assets', v_m, 'pending', v_n); return next;

  -- 4) Deterioro del inmovilizado: el valor recuperable lo estima la empresa
  step := 4; code := 'asset_impairment'; screen := 'assets';
  status := case when v_m = 0 then 'na' else 'review' end;
  detail := jsonb_build_object('impaired', (select count(distinct ev.asset_id) from erp.asset_events ev join erp.fixed_assets a on a.id = ev.asset_id
                                            where ev.company_id = p_company and ev.kind = 'impairment' and a.status = 'active')); return next;

  -- 5) Periodificaciones del cierre (las de este año)
  select count(*) into v_n from erp.accruals a where a.company_id = p_company and a.status <> 'cancelled'
    and a.cutoff_date between v_fy.starting_date and v_fy.ending_date;
  step := 5; code := 'accruals'; screen := 'adjustments';
  status := case when v_n > 0 then 'done' else 'review' end; detail := jsonb_build_object('accruals', v_n); return next;

  -- 6) Deterioro de clientes: vencidas hace más de 6 meses sin deterioro, y deterioros de facturas ya cobradas
  select count(*) into v_n from erp.open_items(p_company, v_fy.ending_date) o
  where o.invoice_type = 'sale' and o.pending > 0 and o.due_date + interval '6 months' <= v_fy.ending_date
    and not exists (select 1 from erp.receivable_impairments i where i.invoice_id = o.invoice_id and i.status = 'active');
  select count(*) into v_m from erp.receivable_impairments i join erp.open_items(p_company, v_fy.ending_date) o on o.invoice_id = i.invoice_id
  where i.company_id = p_company and i.status = 'active' and i.method = 'individual' and o.pending <= 0;
  step := 6; code := 'bad_debts'; screen := 'adjustments';
  status := case when v_m > 0 then 'pending' when v_n > 0 then 'review' else 'done' end;
  detail := jsonb_build_object('overdue_6m', v_n, 'collected', v_m); return next;

  -- 7) Provisiones revisadas este año
  select count(*), count(*) filter (where not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                                                      and m.movement_date between v_fy.starting_date and v_fy.ending_date))
  into v_m, v_n from erp.provisions pv where pv.company_id = p_company and pv.status = 'active'
    and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date <= v_fy.ending_date);
  step := 7; code := 'provisions'; screen := 'adjustments';
  status := case when v_m = 0 then 'review' when v_n = 0 then 'done' else 'pending' end;
  detail := jsonb_build_object('active', v_m, 'not_reviewed', v_n); return next;

  -- 8) Inventario del cierre (si hay existencias o compras de aprovisionamientos)
  select count(*) into v_n from erp.inventory_counts c where c.fiscal_year_id = v_fy.id and c.status = 'posted';
  -- v0.37.0 (0048): con cuentas de existencias, falta; sin ellas pero con compras de aprovisionamientos, revisar
  select count(*) into v_m from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting' and g.account_no ~ '^3[0-6]';
  step := 8; code := 'inventory'; screen := 'adjustments';
  status := case when v_n > 0 then 'done' when v_m > 0 then 'pending'
                 when exists (select 1 from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id
                              join erp.gl_accounts g on g.id = l.gl_account_id
                              where e.fiscal_year_id = v_fy.id and e.status = 'posted' and g.account_no ~ '^60[0-2]') then 'review'
                 else 'na' end;
  detail := jsonb_build_object('posted', v_n > 0); return next;

  -- 9) v0.43.0 · Financiación: intereses devengados y reclasificación a corto de los préstamos vivos (y ninguna cuota
  --    vencida sin contabilizar)
  select count(*) into v_m from erp.loans l where l.company_id = p_company and l.status = 'active' and l.start_date <= v_fy.ending_date;
  step := 9; code := 'financing'; screen := 'financing';
  if v_m = 0 then
    status := 'na'; detail := jsonb_build_object('loans', 0);
  else
    declare pv jsonb := erp.loan_year_end_preview(p_company, v_fy.ending_date);
    begin
      status := case when (pv->>'overdue')::int > 0 or (pv->>'accrual_total')::numeric <> 0 or (pv->>'reclassification_total')::numeric <> 0
                     then 'pending' else 'done' end;
      detail := jsonb_build_object('loans', v_m, 'accrual', pv->'accrual_total', 'reclassification', pv->'reclassification_total', 'overdue', pv->'overdue');
    end;
  end if;
  return next;

  -- 10) v0.44.0 · Subvenciones: la imputación del año de las de capital (después de la amortización, paso 3)
  select count(*) into v_m from erp.grants g where g.company_id = p_company and g.kind = 'capital' and g.status = 'active' and g.grant_date <= v_fy.ending_date;
  step := 10; code := 'grants'; screen := 'grants';
  if v_m = 0 then
    status := 'na'; detail := jsonb_build_object('grants', 0);
  else
    declare gy jsonb := erp.grant_year_end_preview(p_company, v_fy.ending_date);
    begin
      status := case when (gy->>'imputation_total')::numeric > 0 or (gy->>'tax_total')::numeric > 0 or (gy->>'depreciation_pending')::int > 0 then 'pending' else 'done' end;
      detail := jsonb_build_object('grants', v_m, 'imputation', gy->'imputation_total', 'depreciation_pending', gy->'depreciation_pending');
    end;
  end if;
  return next;

  -- 11) Comprobaciones del auditor sin avisos ni errores
  select count(*), string_agg(c.code, ', ' order by c.sort) into v_n, v_txt
  from erp.run_audit_checks(p_company, p_year, v_fy.ending_date) c where c.status in ('warning', 'error');
  step := 11; code := 'audit_checks'; screen := 'checks';
  status := case when v_n = 0 then 'done' else 'pending' end; detail := jsonb_build_object('open', v_n, 'codes', v_txt); return next;

  -- 12) v0.41.0 · Impuesto sobre Sociedades (antes de la regularización)
  step := 12; code := 'corporate_tax'; screen := 'corporate_tax';
  status := case when exists (select 1 from erp.corporate_tax_returns r where r.fiscal_year_id = v_fy.id and r.status = 'posted') then 'done'
                 when erp.pre_tax_result(p_company, v_fy.id) = 0 then 'na' else 'pending' end;
  detail := jsonb_build_object('pre_tax_result', erp.pre_tax_result(p_company, v_fy.id)); return next;

  -- 13) Cierre del ejercicio (regularización, cierre y apertura)
  step := 13; code := 'close'; screen := 'closing';
  status := case when v_fy.status = 'closed' then 'done' else 'pending' end;
  detail := jsonb_build_object('fiscal_year_status', v_fy.status); return next;
end $function$
;

-- 6) Comprobaciones del auditor (versión de la 0063 con «grants_ledger»)
CREATE OR REPLACE FUNCTION erp.run_audit_checks(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(code text, sort integer, area text, status text, title text, title_en text, why text, why_en text, fix text, fix_en text, screen text, book numeric, ledger numeric, difference numeric, items integer, details jsonb)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_to     date := coalesce(p_to_date, (select f.ending_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year));
  v_type   text := (select case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT' end from erp.companies c where c.id = p_company);
  r        record;
  v_sev    text;
  v_prefix text;
  v_sign   int;
  v_err    boolean;
  v_book numeric; v_ledger numeric; v_items int; v_det jsonb;
begin
  if v_type is null or v_to is null then return; end if;     -- empresa o ejercicio que no existe (o no se puede ver)

  for r in select * from erp.audit_checks c order by c.sort loop
    v_book := null; v_ledger := null; v_items := 0; v_det := '[]'; v_sev := r.severity;

    if r.code in ('vat_input', 'vat_output') then
      -- 472 al Debe (soportado) · 477 al Haber (repercutido); sin liquidación ni prorrata
      v_prefix := case r.code when 'vat_input' then '472' else '477' end;
      v_sign   := case r.code when 'vat_input' then 1 else -1 end;
      select coalesce(sum(v_sign * (a.debit - a.credit)) filter (where a.source = 'invoice'), 0),
             coalesce(sum(v_sign * (a.debit - a.credit)), 0)
      into v_book, v_ledger
      from erp.audit_lines(p_company, p_year, v_to) a
      where a.account_no like v_prefix || '%' and a.source not in ('settlement', 'pro_rata');
      -- Detalle: asientos manuales o importados (cada uno junto con su contraasiento: si se anularon, no salen)
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(v_sign * (a.debit - a.credit)) as amount
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.account_no like v_prefix || '%' and a.source in ('manual', 'import')
        group by a.k, a.source having sum(a.debit - a.credit) <> 0
      ), n as (
        select g.*, e.entry_no, e.posting_date, row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'amount', n.amount)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'tax_quota' then
      -- v0.33.1: apuntes manuales o importados en 472 / 477 con base y tipo, cuya cuota no es base × tipo
      --   (tolerancia de 1 céntimo por redondeo; un asiento ya anulado no cuenta)
      with x as (
        select e.id as entry_id, e.entry_no, e.posting_date,
               case when e.import_batch_id is not null then 'import' else 'manual' end as source,
               g.account_no, l.tax_code, c.rate_pct, l.tax_base,
               abs(l.debit - l.credit) as amount, round(abs(l.tax_base) * c.rate_pct / 100, 2) as expected
        from erp.journal_lines l
        join erp.journal_entries e on e.id = l.entry_id
        join erp.fiscal_years fy on fy.id = e.fiscal_year_id
        join erp.gl_accounts g on g.id = l.gl_account_id
        join erp.tax_codes c on c.code = l.tax_code
        where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
          and e.posting_date <= v_to and e.reversal_of is null
          and not exists (select 1 from erp.journal_entries rv
                          where rv.reversal_of = e.id and rv.status = 'posted' and rv.posting_date <= v_to)
          and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
          and (g.account_no like '472%' or g.account_no like '477%')
          and coalesce(l.tax_base, 0) <> 0
      ), n as (
        select x.*, row_number() over (order by x.posting_date, x.entry_no) as rn
        from x where abs(x.amount - x.expected) > 0.01
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.entry_id, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'tax_code', n.tax_code,
                                                   'rate_pct', n.rate_pct, 'tax_base', n.tax_base,
                                                   'amount', n.amount, 'expected', n.expected)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'withholdings' then
      -- Libro: retenciones practicadas en facturas recibidas (modelos 111 / 115)
      select coalesce(sum(w.withholding_amount), 0) into v_book
      from erp.v_withholding_register w
      where w.company_id = p_company and w.fiscal_year = p_year and w.side = 'withheld' and w.posting_date <= v_to;
      -- v0.38.0: más el IRPF de las nóminas (también va al modelo 111, casillas 01 a 03)
      v_book := v_book + coalesce((select sum(s.irpf) from erp.payslips s
                                   join erp.payroll_runs pr on pr.id = s.run_id
                                   join erp.journal_entries je on je.id = pr.entry_id
                                   join erp.fiscal_years f on f.id = je.fiscal_year_id
                                   where pr.company_id = p_company and pr.status = 'posted' and f.year = p_year and pr.period <= v_to), 0);
      -- Contabilidad: asientos que ABONAN la 4751 (las retenciones). Los que la cargan son el ingreso en Hacienda.
      -- Un contraasiento va con su original (por eso se agrupa por k y el signo es el del original).
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, sum(a.credit - a.debit) as amount,
               (select sum(l.credit - l.debit) from erp.journal_lines l join erp.gl_accounts ga on ga.id = l.gl_account_id
                where l.entry_id = a.k and ga.account_no like '4751%' and ga.account_no not like '47512%') as original
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.account_no like '4751%' and a.account_no not like '47512%'   -- v0.42.0: la 47512 (dividendos) va al modelo 123
        group by a.k, a.source
      ), n as (
        select g.*, e.entry_no, e.posting_date,
               row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
        where g.original > 0
      )
      select coalesce(sum(n.amount), 0),
             count(*) filter (where n.source in ('manual', 'import') and n.amount <> 0)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'amount', n.amount)
                                order by n.rn) filter (where n.source in ('manual', 'import') and n.amount <> 0), '[]')
      into v_ledger, v_items, v_det
      from n;

    elsif r.code = 'tax_forms_settlements' then
      -- v0.39.0 · el resultado de cada modelo trimestral (303 / 420, desde el libro registro) frente a su liquidación
      --   contabilizada (desde la contabilidad): un trimestre liquidado aceptando una diferencia
      with q as (
        select g.q, erp.quarter_end(p_year, g.q) as q_end,
               (select b.amount from erp.tax_form_boxes(p_company, p_year, g.q) b where b.box = case v_type when 'VAT' then '46' else '41' end) as form_result,
               (select s.output_tax - s.input_tax from erp.tax_settlements s where s.company_id = p_company and s.tax_type = v_type
                  and s.year = p_year and s.quarter = g.q and s.status = 'posted') as settled
        from generate_series(1, 4) g(q)
        where erp.quarter_end(p_year, g.q) <= v_to
      ), n as (   -- solo los trimestres liquidados (los que faltan por liquidar los avisa el asistente de cierre)
        select q.*, row_number() over (order by q.q) as rn from q
        where q.settled is not null and q.settled <> q.form_result
      )
      select (select coalesce(sum(form_result), 0) from q where settled is not null), (select coalesce(sum(settled), 0) from q), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('quarter', n.q, 'form', case v_type when 'VAT' then '303' else '420' end,
                                                   'form_result', n.form_result, 'settled', n.settled, 'amount', coalesce(n.settled, 0) - n.form_result)
                                order by n.rn), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'form347_missing_vat' then
      -- v0.39.0 · terceros que hay que declarar en el 347 (más de 3.005,06 € en el año) y no tienen NIF
      with n as (select f.*, row_number() over (order by f.partner_name) as rn from erp.form_347(p_company, p_year) f where f.missing_vat_no)
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('partner_id', n.partner_id, 'partner_name', n.partner_name, 'op_key', n.op_key,
                                                   'amount', n.total) order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'sources_review' then
      -- v0.39.0 · fuentes oficiales sin revisar en más de un año (las normas y las instrucciones cambian)
      with n as (select s.*, row_number() over (order by s.checked, s.key) as rn from erp.sources s where s.checked < current_date - interval '1 year')
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('key', n.key, 'name', n.title, 'issuer', n.issuer, 'checked', n.checked) order by n.rn), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'partners' then
      with x as (
        select 'purchase' as t, a.* from erp.aging(p_company, 'purchase', v_to) a
        union all
        select 'sale', a.* from erp.aging(p_company, 'sale', v_to) a
      ), d as (
        select x.*, row_number() over (order by abs(x.account_balance - x.total) desc, x.partner_name) as rn
        from x where x.account_balance <> x.total
      )
      select coalesce(sum(d.total), 0), coalesce(sum(d.account_balance), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('partner_id', d.partner_id, 'partner_name', d.partner_name,
                                                   'account_no', d.partner_account_no, 'invoice_type', d.t,
                                                   'pending', d.total, 'balance', d.account_balance,
                                                   'amount', d.account_balance - d.total)
                                order by d.rn) filter (where d.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from d;

    elsif r.code = 'anomalies' then
      select count(*)::int, bool_or(b.severity = 'error'),
             coalesce(jsonb_agg(jsonb_build_object('account_no', b.account_no, 'account_name', b.name, 'expected', b.expected,
                                                   'amount', b.balance, 'reclass_to', b.reclass_to, 'severity', b.severity,
                                                   'note', b.note, 'note_en', b.note_en)), '[]')
      into v_items, v_err, v_det
      from erp.balance_anomalies(p_company, p_year, null, v_to) b;
      if v_err then v_sev := 'error'; end if;
      v_det := coalesce((select jsonb_agg(j.d) from jsonb_array_elements(v_det) with ordinality j(d, n) where j.n <= 50), '[]');

    elsif r.code = 'tax_territory' then
      with g as (
        select a.k, a.source, min(a.account_no) as account_no, min(a.tax_code) as tax_code, sum(a.debit - a.credit) as amount
        from erp.audit_lines(p_company, p_year, v_to) a join erp.tax_codes c on c.code = a.tax_code
        where c.tax_type <> v_type
        group by a.k, a.source
        having count(*) filter (where a.entry_id = a.k) > count(*) filter (where a.entry_id <> a.k)  -- sin anular
      ), n as (
        select g.*, e.entry_no, e.posting_date, row_number() over (order by e.posting_date, e.entry_no) as rn
        from g join erp.journal_entries e on e.id = g.k
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.k, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'source', n.source, 'account_no', n.account_no, 'tax_code', n.tax_code,
                                                   'amount', n.amount)
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'controlled' then
      -- Manuales sin anular que tocan una cuenta controlada; no cuentan los vinculados a un pago (ya están conciliados)
      with m as (
        select distinct a.entry_id, a.entry_no, a.posting_date
        from erp.audit_lines(p_company, p_year, v_to) a
        where a.source = 'manual' and a.entry_id = a.k
      ), h as (
        select m.*, erp.entry_controlled_lines(m.entry_id) as hit
        from m
        where not exists (select 1 from erp.journal_entries x
                          where x.reversal_of = m.entry_id and x.status = 'posted' and x.posting_date <= v_to)
          and not exists (select 1 from erp.payments py where py.entry_id = m.entry_id and py.linked)
      ), n as (
        select h.*, row_number() over (order by h.posting_date, h.entry_no) as rn
        from h where jsonb_array_length(h.hit) > 0
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('entry_id', n.entry_id, 'entry_no', n.entry_no, 'posting_date', n.posting_date,
                                                   'account_no', n.hit->0->>'account_no', 'modules', n.hit->0->'modules')
                                order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'assets_ledger' then
      -- v0.35.0 · cada cuenta de inmovilizado (coste de los activos en uso) y de amortización acumulada (lo amortizado)
      --   frente a su saldo contable a la fecha (sin terrenos 210 / 220, que no tienen ficha amortizable)
      with f as (
        select a.asset_account_id as acc, sum(a.cost) as book from erp.fixed_assets a
        where a.company_id = p_company and (a.status = 'active' or a.disposal_date > v_to) and a.acquisition_date <= v_to
        group by 1
        union all
        select a.depreciation_account_id, -sum(d.amount) from erp.fixed_assets a
        join erp.asset_depreciations d on d.asset_id = a.id and d.period_end <= v_to
        where a.company_id = p_company and (a.status = 'active' or a.disposal_date > v_to)
        group by 1
        union all
        -- v0.37.0 · el deterioro (29x) frente al deterioro neto de las fichas
        select (select jl.gl_account_id from erp.journal_lines jl join erp.gl_accounts g2 on g2.id = jl.gl_account_id
                where jl.entry_id = ev.entry_id and g2.account_no like '29%' limit 1),
               -sum(case ev.kind when 'impairment' then ev.amount else -ev.amount end)
        from erp.asset_events ev join erp.fixed_assets a on a.id = ev.asset_id
        where ev.company_id = p_company and ev.kind in ('impairment', 'reversal') and ev.event_date <= v_to
          and (a.status = 'active' or a.disposal_date > v_to)
        group by 1
      ), l as (
        -- saldo acumulado a la fecha: todos los ejercicios, sin los asientos de cierre ni las aperturas del propio ERP
        -- (repetirían saldos); una apertura IMPORTADA sí cuenta
        select g.id as acc, sum(jl.debit - jl.credit) as ledger
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and (left(g.account_no, 2) in ('20', '21', '22', '28') or left(g.account_no, 3) in ('290', '291', '292'))
          and left(g.account_no, 3) not in ('210', '220')
        group by 1
      ), x as (
        select coalesce(f.acc, l.acc) as acc, coalesce(sum(f.book), 0) as book, coalesce(max(l.ledger), 0) as ledger
        from f full join l on l.acc = f.acc group by coalesce(f.acc, l.acc)
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'assets_pending' then
      -- v0.35.0 · activos con amortización pendiente hasta el último fin de mes de la fecha de corte
      -- (último fin de mes: la propia fecha si es fin de mes; si no, el del mes anterior)
      with c as (select (date_trunc('month', v_to + 1) - interval '1 day')::date as cut),
      p as (
        select a.id, a.code, a.name, a.start_date,
               erp.asset_depr_at(a.id, c.cut) - erp.asset_posted(a.id) as pending,
               (select max(d.period_end) from erp.asset_depreciations d where d.asset_id = a.id) as last_period
        from erp.fixed_assets a cross join c
        where a.company_id = p_company and a.status = 'active'
      ), n as (select p.*, row_number() over (order by p.code) as rn from p where p.pending > 0)
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('asset_id', n.id, 'code', n.code, 'name', n.name, 'amount', n.pending,
                                                   'last_period', n.last_period) order by n.rn) filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'adjustments_ledger' then
      -- v0.36.0 · 480 / 485 / 4009 / 4309 frente a las periodificaciones vivas y 490 frente a los deterioros vivos, a la fecha
      --   (viva: contabilizada hasta la fecha y aún sin revertir, aplicar ni anular a esa fecha)
      with f as (
        select a.balance_account_id as acc,
               sum(case when a.kind in ('prepaid_expense', 'accrued_income') then a.amount else -a.amount end) as book
        from erp.accruals a
        where a.company_id = p_company and a.cutoff_date <= v_to
          and (a.reversal_date is null or a.reversal_date > v_to)
          and (a.cancel_entry_id is null or (select ce.posting_date from erp.journal_entries ce where ce.id = a.cancel_entry_id) > v_to)
        group by 1
        union all
        select (select g.id from erp.gl_accounts g join erp.journal_lines jl on jl.gl_account_id = g.id
                where jl.entry_id = i.entry_id and g.account_no like '490%' limit 1), -sum(i.amount)
        from erp.receivable_impairments i
        where i.company_id = p_company and i.impair_date <= v_to
          and (i.end_date is null or i.end_date > v_to)
          and (i.cancel_entry_id is null or (select ce.posting_date from erp.journal_entries ce where ce.id = i.cancel_entry_id) > v_to)
        group by 1
      ), l as (
        -- saldo acumulado a la fecha (todos los ejercicios, sin cierres ni aperturas del propio ERP), como assets_ledger
        select g.id as acc, sum(jl.debit - jl.credit) as ledger
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and (g.account_no like '480%' or g.account_no like '485%' or g.account_no like '4009%'
               or g.account_no like '4309%' or g.account_no like '490%')
        group by 1
      ), x as (
        select coalesce(f.acc, l.acc) as acc, coalesce(sum(f.book), 0) as book, coalesce(max(l.ledger), 0) as ledger
        from f full join l on l.acc = f.acc group by coalesce(f.acc, l.acc)
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'accruals_unreversed' then
      -- v0.36.0 · periodificaciones de un ejercicio anterior que siguen sin revertir en este
      with fy as (select f.starting_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year),
      n as (
        select a.id, a.code, a.description, a.cutoff_date, a.amount, row_number() over (order by a.code) as rn
        from erp.accruals a cross join fy
        where a.company_id = p_company and a.status = 'active' and a.cutoff_date < fy.starting_date and fy.starting_date <= v_to
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('accrual_id', n.id, 'code', n.code, 'name', n.description,
                                                   'cutoff_date', n.cutoff_date, 'amount', n.amount) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code in ('provisions_ledger', 'inventory_ledger', 'payroll_ledger', 'financing_ledger', 'grants_ledger') then
      -- v0.37.0 · las cuentas de provisiones (141 / 142 / 5292 / 5293 / 499) y de existencias (30-36 / 39) frente a lo
      --   que han contabilizado sus módulos: la diferencia es un asiento manual o un saldo importado sin su ficha
      with lm as (
        select g.id as acc, sum(jl.debit - jl.credit) as amount,
               bool_or(exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
                       or exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id and ic.status = 'posted')
                       -- v0.38.0: la nómina y sus pagos
                       or exists (select 1 from erp.payroll_runs pr where e.id in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id))
                       -- v0.43.0: los préstamos y el leasing (también la factura de la cuota)
                       or exists (select 1 from erp.loan_events le where le.entry_id = e.id and le.status = 'posted')
                       -- v0.44.0: las subvenciones, y la regularización de los grupos 8 y 9 contra la 130 del cierre
                       or exists (select 1 from erp.grant_events ge where ge.entry_id = e.id and ge.status = 'posted')
                       or e.entry_type = 'closing_pl') as module
        from erp.journal_lines jl join erp.journal_entries e on e.id = jl.entry_id
        join erp.gl_accounts g on g.id = jl.gl_account_id
        where e.company_id = p_company and e.status = 'posted' and e.posting_date <= v_to and e.entry_type <> 'closing'
          and not exists (select 1 from erp.year_closings yc where yc.opening_entry_id = e.id)
          and case r.code when 'provisions_ledger' then g.account_no ~ '^(141|142|5292|5293|499)'
                          when 'payroll_ledger' then g.account_no ~ '^(465|476)'   -- v0.38.0
                          when 'financing_ledger' then g.account_no ~ '^(170|171|174|520|521|524|527|528)'   -- v0.43.0
                          when 'grants_ledger' then g.account_no ~ '^(13[0-2]|172|522|4708|8|9)'   -- v0.44.0
                          else g.account_no ~ '^3[0-6]|^39' end
          -- un movimiento anulado y su contraasiento se compensan: ninguno de los dos cuenta como del módulo
          and not (e.reversal_of is not null or e.reversed_by is not null)
        group by g.id, e.id
      ), x as (
        select acc, coalesce(sum(amount) filter (where module), 0) as book, sum(amount) as ledger from lm group by acc
      ), n as (
        select g.account_no, g.name, x.book, x.ledger, row_number() over (order by g.account_no) as rn
        from x join erp.gl_accounts g on g.id = x.acc where x.book <> x.ledger
      )
      select coalesce(sum(n.book), 0), coalesce(sum(n.ledger), 0), count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('account_no', n.account_no, 'account_name', n.name, 'book', n.book,
                                                   'balance', n.ledger, 'amount', n.ledger - n.book) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_book, v_ledger, v_items, v_det
      from n;

    elsif r.code = 'provisions_review' then
      -- v0.37.0 · al cierre, provisiones vivas sin revisar en el ejercicio (NRV 15.ª: se revisan en cada cierre)
      with fy as (select f.starting_date, f.ending_date from erp.fiscal_years f where f.company_id = p_company and f.year = p_year),
      n as (
        select pv.id, pv.code, pv.description, erp.provision_balance(pv.id) as balance,
               (select max(m.movement_date) from erp.provision_movements m where m.provision_id = pv.id) as last_date,
               row_number() over (order by pv.code) as rn
        from erp.provisions pv cross join fy
        where pv.company_id = p_company and pv.status = 'active' and v_to >= fy.ending_date
          and exists (select 1 from erp.provision_movements m where m.provision_id = pv.id and m.movement_date < fy.starting_date)
          and not exists (select 1 from erp.provision_movements m where m.provision_id = pv.id
                          and m.movement_date between fy.starting_date and fy.ending_date)
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('provision_id', n.id, 'code', n.code, 'name', n.description,
                                                   'amount', n.balance, 'last_date', n.last_date) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;

    elsif r.code = 'impairments_collected' then
      -- v0.36.0 · deterioro individual vivo de una factura que ya no tiene nada pendiente (cobrada o rectificada)
      with n as (
        select i.id, i.code, i.amount, o.invoice_no, o.partner_name, row_number() over (order by i.code) as rn
        from erp.receivable_impairments i
        join erp.open_items(p_company, v_to) o on o.invoice_id = i.invoice_id
        where i.company_id = p_company and i.method = 'individual' and i.status = 'active' and i.impair_date <= v_to
          and o.pending <= 0
      )
      select count(*)::int,
             coalesce(jsonb_agg(jsonb_build_object('impairment_id', n.id, 'code', n.code, 'invoice_no', n.invoice_no,
                                                   'partner_name', n.partner_name, 'amount', n.amount) order by n.rn)
                      filter (where n.rn <= 50), '[]')
      into v_items, v_det
      from n;
    end if;

    code := r.code; sort := r.sort; area := r.area;
    status := case when coalesce(v_ledger, 0) = coalesce(v_book, 0) and v_items = 0 then 'ok' else v_sev end;
    title := r.title; title_en := r.title_en; why := r.why; why_en := r.why_en; fix := r.fix; fix_en := r.fix_en;
    screen := r.screen; book := v_book; ledger := v_ledger;
    difference := case when v_book is null then null else v_ledger - v_book end;
    items := v_items; details := v_det;
    return next;
  end loop;
end $function$
;

-- 7) Estado de cambios en el patrimonio neto (PGC, 3.ª parte; para todas las empresas)
--    Columna de cada cuenta del patrimonio neto (los grupos 6 y 7 son el resultado del año; los 8 y 9, subvenciones)
create or replace function erp.equity_statement_column(p_account_no text)
returns text language sql immutable as $$
  select case when p_account_no ~ '^10' then 'capital'
              when p_account_no ~ '^110' then 'premium'
              when p_account_no ~ '^11' then 'reserves'
              when p_account_no ~ '^129' then 'result'
              when p_account_no ~ '^12' then 'prior_results'
              when p_account_no ~ '^13' then 'grants'
              when p_account_no ~ '^557' then 'interim'
              when p_account_no ~ '^[67]' then 'result'
              when p_account_no ~ '^[89]' then 'grants' end;
$$;

-- Fila de cada apunte: start (apertura), recognised (ingresos y gastos reconocidos), owners (operaciones con socios)
-- u other (otras variaciones). Del reparto del resultado, lo que va a dividendos es «con socios» y lo que va a
-- reservas, «otras variaciones». Importes con el signo del patrimonio neto (Haber − Debe).
create or replace function erp.equity_statement_lines(p_company uuid, p_year int)
returns table (col text, row_code text, account_no text, amount numeric)
language sql stable security definer set search_path = erp, public as $$
  with l as (
    select e.id as entry_id, coalesce(e.reversal_of, e.id) as k, e.entry_type, g.account_no, l.credit - l.debit as amount,
           erp.equity_statement_column(g.account_no) as col
    from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
    join erp.fiscal_years f on f.id = e.fiscal_year_id and f.year = p_year
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and e.entry_type not in ('closing', 'closing_pl')
  ), op as (
    select l.*, (select eo.kind from erp.equity_operations eo where l.k = any (eo.entry_ids) limit 1) as eq_kind,
           sum(case when l.account_no ~ '^(526|557)' then l.amount else 0 end) over (partition by l.entry_id) as dividends
    from l
  )
  select col, case when entry_type = 'opening' then 'start'
                   when account_no ~ '^[6789]' then 'recognised'
                   when eq_kind in ('incorporation', 'capital_increase', 'call', 'interim_dividend') then 'owners'
                   when eq_kind = 'distribution' and account_no ~ '^557' then 'owners'
                   else 'other' end, account_no, amount
  from op where col is not null and not (coalesce(eq_kind, '') = 'distribution' and account_no ~ '^129')
  union all   -- el reparto: la 129 se divide entre dividendos (con socios) y reservas (otras variaciones)
  select col, 'owners', account_no, -dividends from op where col is not null and coalesce(eq_kind, '') = 'distribution' and account_no ~ '^129'
  union all
  select col, 'other', account_no, amount + dividends from op where col is not null and coalesce(eq_kind, '') = 'distribution' and account_no ~ '^129'
  union all   -- sin asiento de apertura (primer año en el ERP o el anterior sin cerrar): el saldo final del año anterior
  select erp.equity_statement_column(g.account_no), 'start', g.account_no, l.credit - l.debit
  from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
  join erp.fiscal_years f on f.id = e.fiscal_year_id and f.year = p_year - 1
  join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and e.entry_type not in ('closing', 'closing_pl') and erp.equity_statement_column(g.account_no) is not null
    and not exists (select 1 from erp.journal_entries o join erp.fiscal_years fo on fo.id = o.fiscal_year_id
                    where o.company_id = p_company and fo.year = p_year and o.entry_type = 'opening' and o.status = 'posted');
$$;

create or replace function erp.equity_statement(p_company uuid, p_year int)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare v_fy erp.fiscal_years; a jsonb; b jsonb; v_rec numeric; v_end numeric; v_bal numeric;
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and year = p_year;
  if not found then raise exception 'Fiscal year % does not exist', p_year; end if;

  -- Parte A: ingresos y gastos reconocidos (el efecto impositivo se separa por el movimiento de la subvención que lo
  -- originó: la concesión, en B; la imputación a resultados, en C)
  with l as (
    select g.account_no, l.credit - l.debit as amount,
           (select v.kind from erp.grant_events v where v.entry_id = coalesce(e.reversal_of, e.id) limit 1) as gk
    from erp.journal_lines l join erp.journal_entries e on e.id = l.entry_id and e.status = 'posted'
    join erp.fiscal_years f on f.id = e.fiscal_year_id and f.year = p_year
    join erp.gl_accounts g on g.id = l.gl_account_id
    where e.company_id = p_company and e.entry_type not in ('closing', 'closing_pl', 'opening') and g.account_no ~ '^[6789]'
  )
  select jsonb_build_object(
    'result', coalesce(sum(amount) filter (where account_no ~ '^[67]'), 0),
    'b_grants', coalesce(sum(amount) filter (where account_no ~ '^94'), 0),
    'b_tax', coalesce(sum(amount) filter (where account_no ~ '^83' and (gk in ('concession', 'unconditional') or (gk is null and amount < 0))), 0),
    'b_other', coalesce(sum(amount) filter (where account_no ~ '^[89]' and account_no !~ '^(94|84|83)'), 0),
    'c_grants', coalesce(sum(amount) filter (where account_no ~ '^84'), 0),
    'c_tax', coalesce(sum(amount) filter (where account_no ~ '^83' and (gk in ('imputation', 'disposal') or (gk is null and amount > 0))), 0))
  into a from l;
  a := a || jsonb_build_object(
    'b_total', (a->>'b_grants')::numeric + (a->>'b_tax')::numeric + (a->>'b_other')::numeric,
    'c_total', (a->>'c_grants')::numeric + (a->>'c_tax')::numeric);
  a := a || jsonb_build_object('total', (a->>'result')::numeric + (a->>'b_total')::numeric + (a->>'c_total')::numeric);

  -- Parte B: estado total, por columnas
  select coalesce(jsonb_object_agg(r, cols), '{}') into b from (
    select row_code as r, jsonb_object_agg(col, amt) as cols
    from (select row_code, col, sum(amount) as amt from erp.equity_statement_lines(p_company, p_year) group by 1, 2) x
    group by row_code) y;
  v_rec := coalesce((select sum(amount) from erp.equity_statement_lines(p_company, p_year) where row_code = 'recognised'), 0);
  v_end := coalesce((select sum(amount) from erp.equity_statement_lines(p_company, p_year)), 0);
  select coalesce(sum(amount), 0) into v_bal from erp.fs_classified_accounts(p_company, p_year, 'balance', v_fy.ending_date) where line_code like 'PN.%';   -- el patrimonio neto (no PNC ni PC)
  return jsonb_build_object('year', p_year, 'part_a', a, 'part_b', b,
    'columns', (select coalesce(jsonb_agg(c order by o), '[]') from unnest(array['capital', 'premium', 'reserves', 'prior_results', 'result', 'interim', 'grants']) with ordinality u(c, o)
                where exists (select 1 from erp.equity_statement_lines(p_company, p_year) s where s.col = u.c and s.amount <> 0)),
    'start', coalesce((select sum(amount) from erp.equity_statement_lines(p_company, p_year) where row_code = 'start'), 0),
    'end', v_end, 'balance_net_worth', v_bal, 'ok', v_end = v_bal and v_rec = (a->>'total')::numeric);
end $$;
revoke execute on function erp.equity_statement_lines(uuid, int) from anon, public, authenticated;
revoke execute on function erp.equity_statement(uuid, int) from anon, public;
grant execute on function erp.equity_statement(uuid, int), erp.equity_statement_column(text) to authenticated;


-- 8) Conceptos (generados desde frontend/src/glossary.js con frontend/tests/glossarySql.js)
insert into erp.concepts (key, sort, term, definition, example, term_en, definition_en, example_en, bc, sap, pgc) values
('capitalGrant', 670, 'Subvención de capital', 'Dinero público para comprar un activo, que no hay que devolver (NRV 18.ª). No es un ingreso del año en que se cobra: va al patrimonio neto (130), neta del impuesto que se pagará (479), y pasa a resultados (746) al mismo ritmo que se amortiza el activo; si se vende, lo que quede, de una vez.', 'Máquina de 50.000 con 20.000 de subvención: el año en que se amortizan 5.000 (el 10 %), 840 D 2.000 / 746 H 2.000 y 479 D 500 / 8301 H 500.', 'Capital grant', 'Public money to buy an asset that does not have to be repaid (NRV 18). It is not income of the year it is received: it goes to equity (130), net of the tax that will be paid (479), and is transferred to profit (746) at the same pace as the asset is depreciated; if the asset is sold, the rest at once.', 'Machine of 50,000 with a 20,000 grant: in the year 5,000 is depreciated (10 %), 840 Dr 2,000 / 746 Cr 2,000 and 479 Dr 500 / 8301 Cr 500.', 'Not standard: general journal', 'Investment support (Asset Accounting)', '{130,940,840,746}'),
('refundableGrant', 680, 'Subvención reintegrable', 'La que hay que devolver si no se cumplen sus condiciones. Mientras haya dudas razonables de cumplirlas es una deuda (522 si la condición vence en 12 meses; si no, 172); cuando se cumplen, pasa a ser no reintegrable y va al patrimonio neto o a resultados (NRV 18.ª).', 'Cobro de 10.000 condicionados a instalar el equipo antes de marzo: 572 D / 522 H 10.000; en marzo, 522 D 10.000 / 940 H 10.000 y 8301 D 2.500 / 479 H 2.500.', 'Refundable grant', 'One that must be repaid if its conditions are not met. While there are reasonable doubts about meeting them it is a debt (522 if the condition falls due within 12 months; otherwise 172); once met, it becomes non-refundable and goes to equity or to profit (NRV 18).', 'Receipt of 10,000 conditional on installing the equipment before March: 572 Dr / 522 Cr 10,000; in March, 522 Dr 10,000 / 940 Cr 10,000 and 8301 Dr 2,500 / 479 Cr 2,500.', 'Not standard: general journal', 'Not standard: general ledger', '{522,172}'),
('groupsEightNine', 690, 'Grupos 8 y 9', 'Los «gastos» (8) y los «ingresos» (9) que no pasan por la cuenta de resultados, sino directamente por el patrimonio neto: subvenciones de capital (940 / 840) y su efecto impositivo (8301). Al cierre se regularizan contra su cuenta del subgrupo 13, igual que los grupos 6 y 7 contra la 129. De ellos sale la parte A del ECPN.', 'Al cierre: 940 D 20.000 / 130 H 20.000 y 130 D 6.500 / 840 H 2.000 · 8301 H 4.500 → la 130 queda en 13.500.', 'Groups 8 and 9', 'The "expenses" (8) and "income" (9) that do not go through profit or loss but directly through equity: capital grants (940 / 840) and their tax effect (8301). At year end they are closed against their subgroup 13 account, as groups 6 and 7 against 129. Part A of the statement of changes in equity comes from them.', 'At year end: 940 Dr 20,000 / 130 Cr 20,000 and 130 Dr 6,500 / 840 Cr 2,000 · 8301 Cr 4,500 → 130 ends at 13,500.', 'No equivalent: other comprehensive income by journal', 'Other comprehensive income (OCI) accounts', '{8,9}'),
('equityStatement', 700, 'Estado de cambios en el patrimonio neto (ECPN)', 'Explica por qué cambia el patrimonio neto en el año. Parte A (ingresos y gastos reconocidos): el resultado más lo que se imputa directamente al patrimonio neto (grupos 9 y 8) y lo que se transfiere a resultados. Parte B (estado total): una columna por partida (capital, reservas, resultado, subvenciones…) con el saldo inicial, los ingresos y gastos reconocidos, las operaciones con socios y otras variaciones, hasta el saldo final, que es el del balance.', 'Resultado 30.000 + subvención 20.000 − su impuesto 5.000 − transferido a resultados 1.500 = 43.500 reconocidos; 78.000 al inicio + 43.500 = 121.500 al final.', 'Statement of changes in equity', 'It explains why equity changes during the year. Part A (recognised income and expense): profit plus what is recognised directly in equity (groups 9 and 8) and what is transferred to profit. Part B (total statement): one column per item (capital, reserves, profit, grants…) with the opening balance, recognised income and expense, transactions with owners and other changes, to the closing balance, which is the balance sheet one.', 'Profit 30,000 + grant 20,000 − its tax 5,000 − transferred to profit 1,500 = 43,500 recognised; 78,000 at the start + 43,500 = 121,500 at the end.', 'Not standard: account schedules', 'Statement of changes in equity (financial statement version)', '{10,11,12,13}')
on conflict (key) do update set
  sort = excluded.sort, term = excluded.term, definition = excluded.definition, example = excluded.example,
  term_en = excluded.term_en, definition_en = excluded.definition_en, example_en = excluded.example_en,
  bc = excluded.bc, sap = excluded.sap, pgc = excluded.pgc;

-- 9) Cuentas controladas (la 130, la 172 y la 522, no: la apertura de una empresa que ya existía las necesita)
insert into erp.control_rules (account_prefix, modules, side, note, note_en) values
('94', '{grants}', 'both', 'Ingresos de subvenciones imputados al patrimonio neto: los mueven la concesión, el paso a no reintegrable y la regularización del cierre.', 'Grant income recognised in equity: posted by the concession, becoming non-refundable and the year-end closing.'),
('84', '{grants}', 'both', 'Transferencias de subvenciones a resultados: las mueven la imputación del cierre y la baja del activo.', 'Grant transfers to profit: posted by the year-end imputation and the asset disposal.'),
('83', '{grants}', 'both', 'Efecto impositivo de los ingresos imputados al patrimonio neto: lo mueven las subvenciones.', 'Tax effect of income recognised in equity: posted by grants.'),
('4708', '{grants}', 'both', 'Hacienda deudora por subvenciones concedidas: la mueven la concesión y el cobro.', 'Grants receivable from public bodies: posted by the concession and the collection.')
on conflict (account_prefix) do update set modules = excluded.modules, side = excluded.side, note = excluded.note, note_en = excluded.note_en;

-- 10) Comprobación nueva del auditor
insert into erp.audit_checks (code, sort, area, severity, title, title_en, why, why_en, fix, fix_en, screen, concept) values
('grants_ledger', 66, 'ledger', 'warning',
 'Subvenciones frente a la contabilidad',
 'Grants against the books',
 'Los grupos 8 y 9, la 4708, la 522 / 172 y la 130-132 solo deben moverse desde Subvenciones (y la regularización del cierre): así cada saldo tiene su ficha y su activo, y se imputa a resultados con su amortización. Un asiento manual o un saldo importado sin ficha queda sin control.',
 'Groups 8 and 9, 4708, 522 / 172 and 130-132 should only be posted from Grants (and the year-end closing): so each balance has its record and its asset, and is imputed to profit with its depreciation. A manual entry or an imported balance without a record is out of control.',
 'Da de alta la subvención en Subvenciones (y anula el asiento manual), o revierte el saldo importado que ya no corresponde.',
 'Create the grant in Grants (and reverse the manual entry), or reverse the imported balance.',
 'grants', 'capitalGrant')
on conflict (code) do update set sort = excluded.sort, area = excluded.area, severity = excluded.severity,
  title = excluded.title, title_en = excluded.title_en, why = excluded.why, why_en = excluded.why_en,
  fix = excluded.fix, fix_en = excluded.fix_en, screen = excluded.screen, concept = excluded.concept;

-- 11) Catálogo de operaciones y supuestos
insert into erp.operations (key, sort, title, title_en, screen, entry, entry_en, accounts, concept, sources, description, description_en) values
('capital_grant', 189, 'Subvención de capital', 'Capital grant', 'grants',
 '4708 D / 940 H · 8301 D / 479 H; cierre: 840 D / 746 H · 479 D / 8301 H', '4708 Dr / 940 Cr · 8301 Dr / 479 Cr; year end: 840 Dr / 746 Cr · 479 Dr / 8301 Cr',
 '{130,940,746}', 'capitalGrant', '{pgc}',
 'La concesión, al patrimonio neto (grupo 9) neta del impuesto futuro; cada cierre pasa a resultados el mismo % que se amortiza el activo; al cierre, los grupos 8 y 9 se regularizan contra la 130.',
 'The concession, to equity (group 9) net of future tax; each year end transfers to profit the same % as the asset is depreciated; at year end groups 8 and 9 are closed against 130.'),
('operating_grant', 190, 'Subvención a la explotación', 'Operating grant', 'grants',
 '4708 D / 740 H', '4708 Dr / 740 Cr',
 '{740,4708}', 'capitalGrant', '{pgc}',
 'Financia un gasto del año: va directamente a resultados (740), sin pasar por los grupos 8 y 9.',
 'It finances an expense of the year: it goes directly to profit (740), not through groups 8 and 9.')
on conflict (key) do update set sort = excluded.sort, title = excluded.title, title_en = excluded.title_en, screen = excluded.screen,
  entry = excluded.entry, entry_en = excluded.entry_en, accounts = excluded.accounts, concept = excluded.concept,
  sources = excluded.sources, description = excluded.description, description_en = excluded.description_en;

insert into erp.exercises (key, sort, level, operation, tax_type, title, title_en, statement, statement_en, expected, explanation, explanation_en, errors, sources, concept) values
('capital_grant_imputation', 210, 'advanced', 'capital_grant', null, 'Imputación anual de una subvención de capital', 'Yearly imputation of a capital grant',
 'Una máquina de 50.000 € se amortiza en 10 años (5.000 € al año). Para comprarla se recibió una subvención de capital no reintegrable de 20.000 €, ya contabilizada con su efecto impositivo al 25 %. Contabiliza la imputación del primer año a resultados con su efecto impositivo (en un solo asiento).',
 'A €50,000 machine is depreciated over 10 years (€5,000 a year). A non-refundable €20,000 capital grant was received to buy it, already recorded with its 25 % tax effect. Record the first year''s transfer to profit with its tax effect (in a single entry).',
 '[{"account": "840", "side": "debit", "amount": 2000}, {"account": "746", "side": "credit", "amount": 2000}, {"account": "479", "side": "debit", "amount": 500}, {"account": "8301", "side": "credit", "amount": 500}]',
 'La subvención pasa a resultados al mismo ritmo que se amortiza la máquina: el 10 % (5.000 de 50.000), es decir, 2.000 (NRV 18.ª). La 840 es la transferencia (grupo 8) y la 746 el ingreso. Como ese ingreso ya tributa, el impuesto diferido que se registró al conceder (479) baja el 25 %: 500, contra la 8301.',
 'The grant is transferred to profit at the same pace as the machine is depreciated: 10 % (5,000 of 50,000), that is 2,000 (NRV 18). 840 is the transfer (group 8) and 746 the income. As that income is now taxed, the deferred tax recorded at the concession (479) goes down by 25 %: 500, against 8301.',
 '[{"account": "940", "side": "debit", "msg": "La 940 recoge la concesión y se regulariza al cierre contra la 130; la transferencia a resultados va por la 840.", "msg_en": "940 records the concession and is closed against 130 at year end; the transfer to profit goes through 840."},
   {"account": "130", "side": "debit", "msg": "La 130 no se toca durante el año: los movimientos van por los grupos 8 y 9, que se regularizan contra ella al cierre.", "msg_en": "130 is not posted during the year: movements go through groups 8 and 9, which are closed against it at year end."},
   {"account": "740", "side": "credit", "msg": "La 740 es para subvenciones a la explotación; las de capital transferidas al resultado van a la 746.", "msg_en": "740 is for operating grants; capital grants transferred to profit go to 746."}]',
 '{pgc}', 'capitalGrant'),
('capital_grant_concession', 220, 'medium', 'capital_grant', null, 'Concesión de una subvención de capital', 'Concession of a capital grant',
 'El Gobierno de Canarias concede a la empresa una subvención de capital no reintegrable de 20.000 € para comprar una máquina; aún no la ha cobrado. El tipo del Impuesto sobre Sociedades es el 25 %. Contabiliza la concesión con su efecto impositivo (en un solo asiento).',
 'The Canary Islands Government grants the company a non-refundable €20,000 capital grant to buy a machine; it has not been collected yet. The corporate tax rate is 25 %. Record the concession with its tax effect (in a single entry).',
 '[{"account": "4708", "side": "debit", "amount": 20000}, {"account": "940", "side": "credit", "amount": 20000}, {"account": "8301", "side": "debit", "amount": 5000}, {"account": "479", "side": "credit", "amount": 5000}]',
 'No es un ingreso del año: va al patrimonio neto a través del grupo 9 (940), y se reconoce el impuesto que se pagará cuando pase a resultados: el 25 % (5.000) como pasivo diferido (479), contra la 8301. El derecho de cobro frente a la Administración es la 4708.',
 'It is not income of the year: it goes to equity through group 9 (940), and the tax to be paid when it is transferred to profit is recognised: 25 % (5,000) as a deferred liability (479), against 8301. The receivable from the public body is 4708.',
 '[{"account": "746", "side": "credit", "msg": "La 746 recoge lo que se va transfiriendo a resultados con la amortización, no la concesión: la concesión va a la 940.", "msg_en": "746 records what is transferred to profit with depreciation, not the concession: the concession goes to 940."},
   {"account": "130", "side": "credit", "msg": "La 130 se alimenta al cierre, al regularizar los grupos 8 y 9; durante el año, la concesión va a la 940.", "msg_en": "130 is fed at year end, when groups 8 and 9 are closed; during the year the concession goes to 940."},
   {"account": "4752", "side": "credit", "msg": "No es un impuesto a pagar este año: es un pasivo por diferencia temporaria imponible (479).", "msg_en": "It is not tax payable this year: it is a deferred tax liability (479)."}]',
 '{pgc}', 'capitalGrant')
on conflict (key) do update set sort = excluded.sort, level = excluded.level, operation = excluded.operation, tax_type = excluded.tax_type,
  title = excluded.title, title_en = excluded.title_en, statement = excluded.statement, statement_en = excluded.statement_en,
  expected = excluded.expected, explanation = excluded.explanation, explanation_en = excluded.explanation_en,
  errors = excluded.errors, sources = excluded.sources, concept = excluded.concept;
