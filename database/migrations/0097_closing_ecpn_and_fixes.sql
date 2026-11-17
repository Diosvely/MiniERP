-- =====================================================================
-- 0097 · v0.60.8 · Correcciones de la etapa: cierre de los grupos 8 y 9, ECPN, plazo de pago y la IA
-- ---------------------------------------------------------------------
-- Aprobado por Diosvely (15 y 17-11-2026). Fichas de auditoría fiscal y de seguridad.
--   AF-16 · el cierre regulariza cada cuenta de los grupos 8 y 9 contra su cuenta del PGC (133, 1340, 1341, 135 o
--           130-132), con el nombre del PGC; una cuenta 8 o 9 sin regla es un error que impide cerrar.
--           PGC (RD 1514/2007), 5.ª parte, grupos 8 y 9, regla «al cierre del ejercicio» de cada cuenta.
--   AF-17 · ECPN, parte A: valoración (800, 900), coberturas (810, 910) y diferencias de conversión (820, 920) en B, y
--           sus transferencias (802, 902; 812, 912; 821, 921) en C. 811 y 911 siguen en b_other; 813 y 913, en c_other.
--           PGC, 3.ª parte; tabla de equivalencias de la AEAT (modelo 200).
--   AF-22 · la ayuda de los periodos medios de cobro y de pago: art. 4 de la Ley 3/2004 (30 días si no se pacta otro;
--           nunca más de 60), en la redacción de la Ley 11/2013. El umbral de 60 días no cambia.
--   H-66  · la nota de la regla del banco acreedor: un descubierto (520) o una póliza de crédito (5201).
--   SEG-23 · erp.ai_refund: como mucho 3 devoluciones de consultas de IA por usuario y día.
-- AF-20 (cerrar con la caja en negativo) no cambia: sigue siendo un aviso (decisión de Diosvely, 17-11-2026).
-- Pruebas: fase 60 (cierre de los grupos 8 y 9), fase 63 (ECPN), fase 18 (ayudas), fase 80 (SEG-23).
-- =====================================================================

-- ---------- AF-16 · La cuenta del PGC de cada cuenta de los grupos 8 y 9 al cierre ----------
create or replace function erp.closing_equity_target(p_account_no text)
returns text language sql immutable set jit = off as $$
  select case
    when p_account_no ~ '^(800|802|900|902)' then '133'
    when p_account_no ~ '^(810|812|910|912)' then '1340'
    when p_account_no ~ '^(811|813|911|913)' then '1341'
    when p_account_no ~ '^(82|92)'           then '135'
    when p_account_no ~ '^(84|94)'           then '13' || substr(p_account_no, 3, 1)
    when p_account_no ~ '^83'                then '130'   -- criterio del ERP: la 83 solo la mueve el módulo de subvenciones (130)
  end;
$$;

-- Las cuentas 133, 134 (1340, 1341) y 135 en la plantilla del plan de cuentas y en todas las empresas (como cuentas de
-- título), para que el cierre pueda crear sus subcuentas
insert into erp.coa_template (account_no, name, name_en, account_category) values
('133',  'Ajustes por valoración en activos financieros a valor razonable con cambios en el patrimonio neto', 'Valuation adjustments on financial assets at fair value through equity', 'equity'),
('134',  'Operaciones de cobertura', 'Hedging transactions', 'equity'),
('1340', 'Cobertura de flujos de efectivo', 'Cash flow hedges', 'equity'),
('1341', 'Cobertura de una inversión neta en un negocio en el extranjero', 'Hedge of a net investment in a foreign operation', 'equity'),
('135',  'Diferencias de conversión', 'Translation differences', 'equity')
on conflict (account_no) do nothing;
insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
select c.id, t.account_no, t.name, t.name_en, 'heading', t.account_no, t.account_category
from erp.companies c cross join erp.coa_template t
where t.account_no in ('133', '134', '1340', '1341', '135')
  and not exists (select 1 from erp.gl_accounts g where g.company_id = c.id and g.account_no = t.account_no);

-- H-47 · la ficha de estudio de las 820, 821, 920 y 921 citaba una línea del ECPN que no existe («IV. Diferencias de
-- conversión»): la línea es «Diferencias de conversión» (con número propio solo en el modelo normal)
update erp.pgc_accounts set statement_lines = jsonb_build_array(
  'ECPN, parte A (ingresos y gastos reconocidos) › ' || case when account in ('8200', '9200') then 'Diferencias de conversión'
    else 'Diferencias de conversión (transferencias a la cuenta de pérdidas y ganancias)' end
  || ' · Balance: A-2) Ajustes por cambios de valor')
where account in ('8200', '8210', '9200', '9210');

-- El nombre de la cuenta 13x en el PGC (la subcuenta que se crea al cerrar y la línea del asiento)
create or replace function erp.closing_equity_name(p_account_no text)
returns text language sql stable set jit = off as $$
  select coalesce(
    case when p_account_no like '133%' then 'Ajustes por valoración en activos financieros a valor razonable con cambios en el patrimonio neto' end,
    (select a.name from erp.pgc_accounts a where p_account_no like a.account || '%' order by length(a.account) desc limit 1),
    'Subvenciones, donaciones y legados');
$$;
-- Las usa el cierre (que se ejecuta con la sesión del usuario): sin datos de nadie, solo traducen un número de cuenta
revoke execute on function erp.closing_equity_target(text), erp.closing_equity_name(text) from anon, public;
grant execute on function erp.closing_equity_target(text), erp.closing_equity_name(text) to authenticated;

-- erp.year_closing_preview: copia de la versión de la 0065 con la regla nueva (2b)
CREATE OR REPLACE FUNCTION erp.year_closing_preview(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET jit TO 'off'
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

  -- 2b) v0.44.0 · REGULARIZACIÓN DE LOS GRUPOS 8 Y 9: cada cuenta se salda contra su 13x. La subcuenta 13x: la primera
  --     que haya o, si no, se crea al cerrar.
  --     v0.60.8 (AF-16): la 13x la decide erp.closing_equity_target (800/802/900/902 → 133; 810/812/910/912 → 1340;
  --     811/813/911/913 → 1341; 82/92 → 135; 84/94 → 13 del mismo tercer dígito; 83 → 130). Una cuenta 8 o 9 sin regla
  --     no se adivina: error group_89_without_rule (se regulariza a mano antes de cerrar)
  select string_agg(b.account_no, ', ' order by b.account_no) into v_txt
  from erp.year_account_balances(v_fy.id) b
  where left(b.account_no, 1) in ('8', '9') and b.balance <> 0 and erp.closing_equity_target(b.account_no) is null;
  if v_txt is not null then
    v_checks := v_checks || jsonb_build_object('code', 'group_89_without_rule', 'severity', 'error', 'detail', v_txt);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('account_no', r.account_no, 'account_name', r.account_name, 'balance', r.balance,
                    'target', coalesce((select min(g.account_no) from erp.gl_accounts g where g.company_id = p_company and g.account_type = 'posting'
                                         and g.account_no like r.tp || '%'),
                                       (select rpad(r.tp, posting_account_digits - 1, '0') || '1' from erp.companies where id = p_company)))
                  order by r.account_no), '[]')
    into v_reg
  from (select b.account_no, b.account_name, b.balance,
               erp.closing_equity_target(b.account_no) as tp
        from erp.year_account_balances(v_fy.id) b where left(b.account_no, 1) in ('8', '9')) r
  where r.tp is not null;
  v_pl := v_pl
    || (select coalesce(jsonb_agg(jsonb_build_object('account_no', x->>'account_no', 'account_name', x->>'account_name',
                  'debit', greatest(-(x->>'balance')::numeric, 0), 'credit', greatest((x->>'balance')::numeric, 0)) order by x->>'account_no'), '[]')
        from jsonb_array_elements(v_reg) x)
    || (select coalesce(jsonb_agg(jsonb_build_object('account_no', t.target, 'account_name', erp.closing_equity_name(t.target),
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
    select t.target, erp.closing_equity_name(t.target), t.bal
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
end $function$;

-- erp.close_fiscal_year: copia de la versión de la 0065 con el nombre del PGC de la 13x
CREATE OR REPLACE FUNCTION erp.close_fiscal_year(p_company uuid, p_year integer, p_accept_warnings boolean DEFAULT false)
 RETURNS TABLE(closing_id uuid, result numeric, closing_pl_no integer, closing_no integer, opening_no integer)
 LANGUAGE plpgsql
 SET jit TO 'off'
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
  -- v0.60.8 (AF-16): con el nombre de su cuenta del PGC (133, 1340, 1341, 135 o 130-132)
  perform erp.create_posting_account(p_company, l->>'account_no', erp.closing_equity_name(l->>'account_no'))
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
end $function$;

-- ---------- AF-17 · ECPN (copia de la versión de la 0065 con las líneas nuevas de la parte A) ----------
CREATE OR REPLACE FUNCTION erp.equity_statement(p_company uuid, p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
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
    -- v0.60.8 (AF-17): valoración, coberturas y diferencias de conversión, imputadas (B) y transferidas (C)
    'b_valuation', coalesce(sum(amount) filter (where account_no ~ '^(800|900)'), 0),
    'b_hedges', coalesce(sum(amount) filter (where account_no ~ '^(810|910)'), 0),
    'b_translation', coalesce(sum(amount) filter (where account_no ~ '^(820|920)'), 0),
    'b_other', coalesce(sum(amount) filter (where account_no ~ '^[89]' and account_no !~ '^(94|84|83|800|900|810|910|820|920|802|902|812|912|821|921|813|913)'), 0),
    'c_valuation', coalesce(sum(amount) filter (where account_no ~ '^(802|902)'), 0),
    'c_hedges', coalesce(sum(amount) filter (where account_no ~ '^(812|912)'), 0),
    'c_translation', coalesce(sum(amount) filter (where account_no ~ '^(821|921)'), 0),
    'c_other', coalesce(sum(amount) filter (where account_no ~ '^(813|913)'), 0),
    'c_grants', coalesce(sum(amount) filter (where account_no ~ '^84'), 0),
    'c_tax', coalesce(sum(amount) filter (where account_no ~ '^83' and (gk in ('imputation', 'disposal') or (gk is null and amount > 0))), 0))
  into a from l;
  a := a || jsonb_build_object(
    'b_total', (a->>'b_valuation')::numeric + (a->>'b_hedges')::numeric + (a->>'b_grants')::numeric
             + (a->>'b_translation')::numeric + (a->>'b_tax')::numeric + (a->>'b_other')::numeric,
    'c_total', (a->>'c_valuation')::numeric + (a->>'c_hedges')::numeric + (a->>'c_grants')::numeric
             + (a->>'c_translation')::numeric + (a->>'c_tax')::numeric + (a->>'c_other')::numeric);
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
end $function$;

-- ---------- AF-22 · Plazo de pago (Ley 3/2004, art. 4) ----------
update erp.ratio_defs set
  help = 'Días que tarda en cobrar. Los clientes incluyen el IVA / IGIC y la cifra de negocios no, así que sale algo alto. Entre empresas, el plazo legal es de 30 días si no se pacta otro, y nunca más de 60 (art. 4 de la Ley 3/2004).',
  help_en = 'Days to collect. Receivables include VAT / IGIC and revenue does not, so it is slightly overstated. Between businesses, the legal term is 30 days unless agreed otherwise, never more than 60 (Spanish Law 3/2004, art. 4).'
where code = 'DSO';
update erp.ratio_defs set
  help = replace(help, '(máximo legal 60 días)', '(plazo legal: 30 días si no se pacta otro y nunca más de 60, art. 4 de la Ley 3/2004)'),
  help_en = replace(help_en, '(legal maximum 60 days)', '(legal term: 30 days unless agreed otherwise, never more than 60, Spanish Law 3/2004, art. 4)')
where code = 'DPO';

-- ---------- H-66 · El banco acreedor: descubierto (520) o póliza de crédito (5201) ----------
update erp.balance_rules set
  note = 'Banco con saldo acreedor: un descubierto (520) o una póliza de crédito (5201). En el Balance va a deudas con entidades de crédito.',
  note_en = 'Bank with a credit balance: an overdraft (520) or a credit line (5201). In the balance sheet it goes to bank borrowings.'
where prefix = '572';

-- ---------- SEG-23 · Tope de devoluciones de consultas de IA ----------
CREATE OR REPLACE FUNCTION erp.ai_refund(p_call uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
 SET jit TO 'off'
AS $function$
declare v_day date;
begin
  if auth.uid() is null or erp.is_anonymous() then return false; end if;
  -- v0.60.8 (SEG-23): como mucho 3 devoluciones por usuario y día
  if (select count(*) from erp.ai_calls where user_id = auth.uid() and used_on = current_date and refunded_at is not null) >= 3 then
    return false;
  end if;
  update erp.ai_calls set refunded_at = now()
  where id = p_call and user_id = auth.uid() and refunded_at is null and created_at > now() - interval '15 minutes'
  returning used_on into v_day;
  if not found then return false; end if;
  update erp.ai_usage set calls = greatest(calls - 1, 0) where user_id = auth.uid() and used_on = v_day;
  return true;
end $function$;
