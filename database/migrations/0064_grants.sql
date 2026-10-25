-- =====================================================================
-- 0064 · SUBVENCIONES (I): de capital y a la explotación, con los grupos 8 y 9 · v0.44.0
-- ---------------------------------------------------------------------
-- PGC 2007, NRV 18.ª (subvenciones), NRV 13.ª (efecto impositivo) y 5.ª parte (grupos 8 y 9):
--   · De capital, no reintegrable: al patrimonio neto (940), neta del impuesto futuro (8301 / 479); pasa a resultados
--     (840 / 746) al mismo ritmo que la amortización del activo que financia; al venderlo, lo que quede.
--   · A la explotación: directamente a resultados (740).
--   · Reintegrable: mientras pueda devolverse es una deuda (522 si la condición vence en 12 meses; si no, 172); al
--     cumplirse la condición pasa a no reintegrable.
--   · Concesión (4708 o, si ya está cobrada, el banco), cobro (572 / 4708), imputación del cierre (las de todas las
--     subvenciones de una vez, como la reclasificación de los préstamos) y deshacer del último movimiento al primero.
-- La regularización de los grupos 8 y 9 contra la 130 en el cierre, el ECPN y la baja del activo llegan en la 0065.
-- Supuestos de referencia: supuestos-v0.44.0.md (S1 a S3). Re-ejecutable.
-- =====================================================================

-- 1) Plantilla: grupos 8 y 9 (ingresos y gastos imputados al patrimonio neto) y la 522; a las empresas que ya
--    existen, como cuentas de título
insert into erp.coa_template (account_no, name, name_en, account_category) values
('522', 'Deudas a corto plazo transformables en subvenciones, donaciones y legados', 'Short-term debt convertible into grants, donations and bequests', 'liability'),
('8', 'Gastos imputados al patrimonio neto', 'Expenses recognised in equity', 'equity'),
('83', 'Impuesto sobre beneficios', 'Income tax (recognised in equity)', 'equity'),
('830', 'Impuesto sobre beneficios', 'Income tax (recognised in equity)', 'equity'),
('8300', 'Impuesto corriente', 'Current tax (recognised in equity)', 'equity'),
('8301', 'Impuesto diferido', 'Deferred tax (recognised in equity)', 'equity'),
('84', 'Transferencias de subvenciones, donaciones y legados', 'Transfers of grants, donations and bequests', 'equity'),
('840', 'Transferencia de subvenciones oficiales de capital', 'Transfer of official capital grants', 'equity'),
('841', 'Transferencia de donaciones y legados de capital', 'Transfer of capital donations and bequests', 'equity'),
('842', 'Transferencia de otras subvenciones, donaciones y legados', 'Transfer of other grants, donations and bequests', 'equity'),
('9', 'Ingresos imputados al patrimonio neto', 'Income recognised in equity', 'equity'),
('94', 'Ingresos de subvenciones, donaciones y legados', 'Income from grants, donations and bequests', 'equity'),
('940', 'Ingresos de subvenciones oficiales de capital', 'Income from official capital grants', 'equity'),
('941', 'Ingresos de donaciones y legados de capital', 'Income from capital donations and bequests', 'equity'),
('942', 'Ingresos de otras subvenciones, donaciones y legados', 'Income from other grants, donations and bequests', 'equity')
on conflict (account_no) do nothing;
insert into erp.gl_accounts (company_id, account_no, name, name_en, account_type, template_account, account_category)
select c.id, t.account_no, t.name, t.name_en, 'heading', t.account_no, t.account_category
from erp.companies c cross join erp.coa_template t
where t.account_no in ('522', '8', '83', '830', '8300', '8301', '84', '840', '841', '842', '9', '94', '940', '941', '942')
  and not exists (select 1 from erp.gl_accounts g where g.company_id = c.id and g.account_no = t.account_no);

-- 1b) Estado de flujos de efectivo: dónde va cada cuenta nueva
--   · grupos 8 y 9 y la 4708 de capital: financiación (cobros por subvenciones, PGC: EFE C-9 e); la 840 compensa a la
--     746, que el método indirecto ya saca del resultado (A-2 d) y lleva a financiación
--   · 83 (efecto impositivo): con los impuestos, como la 479 con la que se compensa
--   · 47089… (la 4708 de las subvenciones a la explotación): explotación, como las demás deudas de Hacienda
insert into erp.cf_mapping (prefix, home_line, adjust_line, direct_line) values
('8', 'IC1', null, 'DC1'), ('83', 'IA4d', null, 'DA6'), ('9', 'IC1', null, 'DC1'),
('4708', 'IC1', null, 'DC1'), ('47089', 'IA3b', null, 'DA4')
on conflict (prefix) do update set home_line = excluded.home_line, adjust_line = excluded.adjust_line, direct_line = excluded.direct_line;

-- 1c) Balance: durante el año, antes de regularizarlos contra la 130, el saldo de los grupos 8 y 9 ya es patrimonio
--     neto (A-2 Subvenciones, donaciones y legados), como el de los grupos 6 y 7 es el resultado del ejercicio
insert into erp.fs_mapping (statement, prefix, debit_line, credit_line) values
('balance', '8', 'PN.A2', 'PN.A2'), ('balance', '9', 'PN.A2', 'PN.A2')
on conflict do nothing;

-- 2) Las subvenciones y sus movimientos
create table if not exists erp.grants (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references erp.companies(id) on delete cascade,
  code                 text not null,                       -- SUB-0001…
  kind                 text not null check (kind in ('capital', 'operating')),
  description          text not null,
  grantor              text not null default '',
  amount               numeric(14,2) not null check (amount > 0),
  grant_date           date not null,
  refundable           boolean not null default false,      -- reintegrable al concederla
  condition_due        date,                                -- reintegrable: cuándo vence la condición
  tax_rate             numeric(5,2) not null default 25 check (tax_rate between 0 and 100),
  asset_id             uuid references erp.fixed_assets(id),   -- de capital: el activo que financia
  equity_account_id    uuid references erp.gl_accounts(id),    -- 130
  income_account_id    uuid not null references erp.gl_accounts(id),   -- 940 (capital) o 740 (explotación)
  transfer_account_id  uuid references erp.gl_accounts(id),    -- 840
  result_account_id    uuid references erp.gl_accounts(id),    -- 746
  tax_account_id       uuid references erp.gl_accounts(id),    -- 8301
  deferred_account_id  uuid references erp.gl_accounts(id),    -- 479
  receivable_account_id uuid not null references erp.gl_accounts(id),  -- 4708
  debt_account_id      uuid references erp.gl_accounts(id),    -- 522 / 172 (reintegrable)
  status               text not null default 'active' check (status in ('active', 'imputed', 'cancelled')),
  created_at           timestamptz not null default now(),
  unique (company_id, code),
  check (kind = 'operating' or asset_id is not null)
);
comment on table erp.grants is 'Grants (PGC NRV 18): capital grants imputed to profit with the depreciation of the asset they finance, and operating grants.';
create index if not exists grants_company_idx on erp.grants (company_id, grant_date);
create index if not exists grants_asset_idx on erp.grants (asset_id);
create index if not exists grants_equity_account_idx on erp.grants (equity_account_id);
create index if not exists grants_income_account_idx on erp.grants (income_account_id);
create index if not exists grants_transfer_account_idx on erp.grants (transfer_account_id);
create index if not exists grants_result_account_idx on erp.grants (result_account_id);
create index if not exists grants_tax_account_idx on erp.grants (tax_account_id);
create index if not exists grants_deferred_account_idx on erp.grants (deferred_account_id);
create index if not exists grants_receivable_account_idx on erp.grants (receivable_account_id);
create index if not exists grants_debt_account_idx on erp.grants (debt_account_id);

create table if not exists erp.grant_events (
  id          uuid primary key default gen_random_uuid(),
  seq         bigserial,
  grant_id    uuid not null references erp.grants(id) on delete cascade,
  company_id  uuid not null references erp.companies(id) on delete cascade,
  kind        text not null check (kind in ('concession', 'collection', 'unconditional', 'imputation', 'disposal')),
  event_date  date not null,
  amount      numeric(14,2) not null default 0,   -- concesión / cobro / reintegrable → no / lo que pasa a resultados
  tax_amount  numeric(14,2) not null default 0,   -- efecto impositivo (8301 / 479)
  collected   boolean not null default false,     -- concesión ya cobrada (al banco, sin la 4708)
  entry_id    uuid references erp.journal_entries(id),
  status      text not null default 'posted' check (status in ('posted', 'cancelled')),
  created_at  timestamptz not null default now()
);
comment on table erp.grant_events is 'Postings of a grant: concession, collection, becoming non-refundable, year-end imputation and imputation of the rest when the asset is disposed of.';
create index if not exists grant_events_grant_idx on erp.grant_events (grant_id, seq);
create index if not exists grant_events_company_idx on erp.grant_events (company_id);
create index if not exists grant_events_entry_idx on erp.grant_events (entry_id);

alter table erp.grants enable row level security;
alter table erp.grant_events enable row level security;
drop policy if exists read on erp.grants;
create policy read on erp.grants for select to authenticated using (erp.can_read(company_id));
drop policy if exists read on erp.grant_events;
create policy read on erp.grant_events for select to authenticated using (erp.can_read(company_id));
revoke all on erp.grants, erp.grant_events from anon, public;
grant select on erp.grants, erp.grant_events to authenticated;   -- se escriben con las funciones

-- 3) Ayudas
create or replace function erp.grant_check(p_company uuid, p_date date)
returns void language plpgsql security definer set search_path = erp, public as $$
declare v_fy erp.fiscal_years;
begin
  if not erp.can_write(p_company) then raise exception 'No permission to post grants in this company'; end if;
  if p_date is null then raise exception 'The date is required'; end if;
  select * into v_fy from erp.fiscal_years where company_id = p_company and p_date between starting_date and ending_date;
  if not found then raise exception 'No fiscal year for date %: create it first', p_date; end if;
  if v_fy.status = 'closed' then raise exception 'Fiscal year % is closed', v_fy.year; end if;
  perform pg_advisory_xact_lock(hashtext('grants/' || p_company));
end $$;

-- Lo que lleva una subvención según sus movimientos: ¿no reintegrable ya?, ¿cobrada?, imputado y efecto revertido
create or replace function erp.grant_position(p_grant uuid)
returns jsonb language sql stable security definer set search_path = erp, public as $$
  select jsonb_build_object(
    'unconditional', coalesce(bool_or(v.kind = 'unconditional'), false) or (not g.refundable and coalesce(bool_or(v.kind = 'concession'), false)),
    'collected', coalesce(bool_or(v.kind = 'collection' or (v.kind = 'concession' and v.collected)), false),
    'imputed', coalesce(sum(v.amount) filter (where v.kind in ('imputation', 'disposal')), 0),
    'tax_reversed', coalesce(sum(v.tax_amount) filter (where v.kind in ('imputation', 'disposal')), 0),
    'tax_recognised', coalesce(sum(v.tax_amount) filter (where v.kind in ('concession', 'unconditional')), 0),
    'last_date', max(v.event_date), 'events', count(v.id))
  from erp.grants g left join erp.grant_events v on v.grant_id = g.id and v.status = 'posted'
  where g.id = p_grant group by g.refundable;
$$;

-- Imputación a una fecha de una subvención de capital no reintegrable: lo que corresponde a la amortización del activo
-- desde el ejercicio de la concesión (lo amortizado / el coste × la subvención), menos lo ya imputado; y su efecto
-- impositivo (el tipo × lo imputado, menos lo ya revertido)
create or replace function erp.grant_imputation_amount(p_grant uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare g erp.grants; pos jsonb; a erp.fixed_assets; v_from date; v_dep numeric; v_target numeric; v_tax numeric; v_pending boolean;
begin
  select * into g from erp.grants where id = p_grant;
  pos := erp.grant_position(p_grant);
  if g.kind <> 'capital' or g.status <> 'active' or not (pos->>'unconditional')::boolean then return null; end if;
  select * into a from erp.fixed_assets where id = g.asset_id;
  select starting_date into v_from from erp.fiscal_years where company_id = g.company_id and g.grant_date between starting_date and ending_date;
  select coalesce(sum(d.amount), 0) into v_dep from erp.asset_depreciations d
  where d.asset_id = a.id and d.period_end between v_from and p_date;
  v_pending := a.status = 'active' and erp.asset_depr_at(a.id, p_date) > erp.asset_posted(a.id);
  v_target := least(g.amount, round(g.amount * v_dep / a.cost, 2));
  v_tax := round(v_target * g.tax_rate / 100, 2);
  return jsonb_build_object('amount', greatest(0, v_target - (pos->>'imputed')::numeric),
    'tax', greatest(0, least(v_tax, (pos->>'tax_recognised')::numeric) - (pos->>'tax_reversed')::numeric),
    'depreciation', v_dep, 'cost', a.cost, 'pct', case when a.cost > 0 then round(v_dep / a.cost * 100, 4) end,
    'depreciation_pending', v_pending, 'asset_code', a.code);
end $$;

-- 4) Alta y concesión: p = { company_id, kind ('capital' | 'operating'), description, grantor?, amount, date,
--    refundable? (false), condition_due? (reintegrable), collected? (ya cobrada: al banco), bank_account_no?,
--    asset_id? (de capital: obligatorio), tax_rate? (25) }
create or replace function erp.grant_create(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare
  v_company uuid := (p->>'company_id')::uuid; v_kind text := coalesce(p->>'kind', 'capital'); v_date date := (p->>'date')::date;
  v_amt numeric := round(coalesce((p->>'amount')::numeric, 0), 2); v_ref boolean := coalesce((p->>'refundable')::boolean, false);
  v_due date := (p->>'condition_due')::date; v_coll boolean := coalesce((p->>'collected')::boolean, false);
  v_rate numeric := coalesce((p->>'tax_rate')::numeric, 25); v_desc text := nullif(btrim(p->>'description'), '');
  v_asset uuid := nullif(p->>'asset_id', '')::uuid; a erp.fixed_assets; v_code text; v_id uuid; v_tax numeric := 0; v_entry uuid;
  a_eq uuid; a_inc uuid; a_tr uuid; a_res uuid; a_tax uuid; a_def uuid; a_rec uuid; a_debt uuid; a_first uuid;
begin
  perform erp.grant_check(v_company, v_date);
  if v_kind not in ('capital', 'operating') then raise exception 'Invalid grant type: %', v_kind; end if;
  if v_desc is null then raise exception 'The description is required'; end if;
  if v_amt <= 0 then raise exception 'The grant amount must be positive'; end if;
  if v_rate < 0 or v_rate > 100 then raise exception 'The tax rate must be between 0 and 100'; end if;
  if v_kind = 'capital' then
    select * into a from erp.fixed_assets where id = v_asset and company_id = v_company;
    if not found then raise exception 'Choose the fixed asset the capital grant finances (Fixed assets)'; end if;
    if a.status <> 'active' then raise exception 'Asset % is disposed', a.code; end if;
    if v_amt > a.cost then raise exception 'The grant cannot exceed the cost of the asset (%)', a.cost; end if;
  else
    v_asset := null;
  end if;
  if v_ref and v_due is null then raise exception 'A refundable grant needs the date its condition falls due'; end if;
  -- la 4708 de las de capital y la de las de explotación son subcuentas distintas (4708… y 47089…): el cobro es un
  -- flujo de financiación en unas y de explotación en otras (estado de flujos de efectivo, cf_mapping)
  a_rec := case v_kind when 'capital' then erp.adjust_account(v_company, '4708', 'Hacienda Pública, deudora por subvenciones de capital concedidas')
                else erp.adjust_account(v_company, '47089', 'Hacienda Pública, deudora por subvenciones a la explotación concedidas') end;
  if v_kind = 'capital' then
    a_eq  := erp.adjust_account(v_company, '130', 'Subvenciones oficiales de capital');
    a_inc := erp.adjust_account(v_company, '940', 'Ingresos de subvenciones oficiales de capital');
    a_tr  := erp.adjust_account(v_company, '840', 'Transferencia de subvenciones oficiales de capital');
    a_res := erp.adjust_account(v_company, '746', 'Subvenciones de capital transferidas al resultado del ejercicio');
    a_tax := erp.adjust_account(v_company, '8301', 'Impuesto diferido');
    a_def := erp.adjust_account(v_company, '479', 'Pasivos por diferencias temporarias imponibles');
  else
    a_inc := erp.adjust_account(v_company, '740', 'Subvenciones a la explotación');
  end if;
  if v_ref then
    a_debt := case when v_due <= v_date + interval '1 year'
                   then erp.adjust_account(v_company, '522', 'Deudas a corto plazo transformables en subvenciones')
                   else erp.adjust_account(v_company, '172', 'Deudas a largo plazo transformables en subvenciones') end;
  end if;
  select 'SUB-' || lpad((count(*) + 1)::text, 4, '0') into v_code from erp.grants where company_id = v_company;
  insert into erp.grants (company_id, code, kind, description, grantor, amount, grant_date, refundable, condition_due, tax_rate, asset_id,
                          equity_account_id, income_account_id, transfer_account_id, result_account_id, tax_account_id, deferred_account_id,
                          receivable_account_id, debt_account_id)
  values (v_company, v_code, v_kind, v_desc, coalesce(btrim(p->>'grantor'), ''), v_amt, v_date, v_ref, v_due, v_rate, v_asset,
          a_eq, a_inc, a_tr, a_res, a_tax, a_def, a_rec, a_debt)
  returning id into v_id;
  a_first := case when v_coll then erp.equity_bank(v_company, p->>'bank_account_no') else a_rec end;
  if not v_ref and v_kind = 'capital' then v_tax := round(v_amt * v_rate / 100, 2); end if;
  v_entry := erp.equity_entry(v_company, v_date, 'Subvención concedida' || case when v_ref then ' (reintegrable)' else '' end || ' · ' || v_desc, v_code,
               jsonb_build_array(erp.equity_line(a_first, v_amt, 0), erp.equity_line(coalesce(a_debt, a_inc), 0, v_amt),
                                 erp.equity_line(a_tax, v_tax, 0), erp.equity_line(a_def, 0, v_tax)));
  insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, tax_amount, collected, entry_id)
  values (v_id, v_company, 'concession', v_date, v_amt, v_tax, v_coll, v_entry);
  return jsonb_build_object('grant_id', v_id, 'code', v_code, 'tax', v_tax, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $$;

-- 5) Cobro: p = { grant_id, date, bank_account_no? }
create or replace function erp.grant_collect(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare g erp.grants; v_date date := (p->>'date')::date; v_entry uuid;
begin
  select * into g from erp.grants where id = (p->>'grant_id')::uuid;
  if not found then raise exception 'Grant not found'; end if;
  perform erp.grant_check(g.company_id, v_date);
  if g.status = 'cancelled' then raise exception 'The grant is cancelled'; end if;
  if (erp.grant_position(g.id)->>'collected')::boolean then raise exception 'The grant is already collected'; end if;
  if v_date < (erp.grant_position(g.id)->>'last_date')::date then raise exception 'The date is earlier than the last posting of this grant'; end if;
  v_entry := erp.equity_entry(g.company_id, v_date, 'Cobro de la subvención · ' || g.description, g.code,
               jsonb_build_array(erp.equity_line(erp.equity_bank(g.company_id, p->>'bank_account_no'), g.amount, 0),
                                 erp.equity_line(g.receivable_account_id, 0, g.amount)));
  insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, entry_id) values (g.id, g.company_id, 'collection', v_date, g.amount, v_entry);
  return jsonb_build_object('code', g.code, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $$;

-- 6) Se cumple la condición: la reintegrable pasa a no reintegrable (deuda → patrimonio neto, o → 740 si es a la
--    explotación): p = { grant_id, date }
create or replace function erp.grant_unconditional(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare g erp.grants; v_date date := (p->>'date')::date; v_tax numeric := 0; v_entry uuid;
begin
  select * into g from erp.grants where id = (p->>'grant_id')::uuid;
  if not found then raise exception 'Grant not found'; end if;
  perform erp.grant_check(g.company_id, v_date);
  if g.status <> 'active' then raise exception 'The grant is not active (%)', g.status; end if;
  if not g.refundable then raise exception 'The grant is not refundable'; end if;
  if (erp.grant_position(g.id)->>'unconditional')::boolean then raise exception 'The grant is already non-refundable'; end if;
  if v_date < (erp.grant_position(g.id)->>'last_date')::date then raise exception 'The date is earlier than the last posting of this grant'; end if;
  if g.kind = 'capital' then v_tax := round(g.amount * g.tax_rate / 100, 2); end if;
  v_entry := erp.equity_entry(g.company_id, v_date, 'La subvención deja de ser reintegrable · ' || g.description, g.code,
               jsonb_build_array(erp.equity_line(g.debt_account_id, g.amount, 0), erp.equity_line(g.income_account_id, 0, g.amount),
                                 erp.equity_line(g.tax_account_id, v_tax, 0), erp.equity_line(g.deferred_account_id, 0, v_tax)));
  insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, tax_amount, entry_id)
  values (g.id, g.company_id, 'unconditional', v_date, g.amount, v_tax, v_entry);
  return jsonb_build_object('code', g.code, 'tax', v_tax, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $$;

-- 7) Imputación del cierre: vista previa y contabilización de todas las subvenciones de capital vivas
create or replace function erp.grant_year_end_preview(p_company uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare r jsonb := '[]'; g erp.grants; v jsonb;
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  for g in select * from erp.grants where company_id = p_company and kind = 'capital' and status = 'active' and grant_date <= p_date order by code loop
    v := erp.grant_imputation_amount(g.id, p_date);
    r := r || jsonb_build_object('grant_id', g.id, 'code', g.code, 'description', g.description, 'amount', g.amount,
      'unconditional', v is not null, 'imputation', coalesce((v->>'amount')::numeric, 0), 'tax', coalesce((v->>'tax')::numeric, 0),
      'pct', v->'pct', 'asset_code', v->>'asset_code', 'depreciation_pending', coalesce((v->>'depreciation_pending')::boolean, false),
      'imputed', (erp.grant_position(g.id)->>'imputed')::numeric);
  end loop;
  return jsonb_build_object('date', p_date, 'grants', r,
    'imputation_total', (select coalesce(sum((x->>'imputation')::numeric), 0) from jsonb_array_elements(r) x),
    'tax_total', (select coalesce(sum((x->>'tax')::numeric), 0) from jsonb_array_elements(r) x),
    'depreciation_pending', (select count(*) from jsonb_array_elements(r) x where (x->>'depreciation_pending')::boolean));
end $$;

create or replace function erp.grant_year_end(p_company uuid, p_date date)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare pv jsonb; x jsonb; g erp.grants; v_entry uuid; v_n int := 0;
begin
  perform erp.grant_check(p_company, p_date);
  pv := erp.grant_year_end_preview(p_company, p_date);
  for x in select * from jsonb_array_elements(pv->'grants') loop
    select * into g from erp.grants where id = (x->>'grant_id')::uuid;
    if (x->>'depreciation_pending')::boolean then
      raise exception 'Asset % is not depreciated up to %: post the depreciation first (Fixed assets)', x->>'asset_code', p_date;
    end if;
    if exists (select 1 from erp.grant_events where grant_id = g.id and status = 'posted' and event_date > p_date) then
      raise exception '% has postings after %', g.code, p_date;
    end if;
    if (x->>'imputation')::numeric > 0 or (x->>'tax')::numeric > 0 then
      v_entry := erp.equity_entry(p_company, p_date, 'Subvención transferida al resultado · ' || g.description, g.code,
                   jsonb_build_array(erp.equity_line(g.transfer_account_id, (x->>'imputation')::numeric, 0), erp.equity_line(g.result_account_id, 0, (x->>'imputation')::numeric),
                                     erp.equity_line(g.deferred_account_id, (x->>'tax')::numeric, 0), erp.equity_line(g.tax_account_id, 0, (x->>'tax')::numeric)));
      insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, tax_amount, entry_id)
      values (g.id, p_company, 'imputation', p_date, (x->>'imputation')::numeric, (x->>'tax')::numeric, v_entry);
      v_n := v_n + 1;
    end if;
  end loop;
  return pv || jsonb_build_object('entries', v_n);
end $$;

-- 8) Lo que queda, de una vez, a resultados (venta o baja del activo; NRV 18.ª): p = { grant_id, date }
create or replace function erp.grant_impute_rest(p jsonb)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare g erp.grants; pos jsonb; v_date date := (p->>'date')::date; v_amt numeric; v_tax numeric; v_entry uuid;
begin
  select * into g from erp.grants where id = (p->>'grant_id')::uuid;
  if not found then raise exception 'Grant not found'; end if;
  perform erp.grant_check(g.company_id, v_date);
  if g.kind <> 'capital' or g.status <> 'active' then raise exception 'Only an active capital grant can be imputed'; end if;
  pos := erp.grant_position(g.id);
  if not (pos->>'unconditional')::boolean then raise exception 'The grant is still refundable'; end if;
  if v_date < (pos->>'last_date')::date then raise exception 'The date is earlier than the last posting of this grant'; end if;
  v_amt := g.amount - (pos->>'imputed')::numeric;
  v_tax := (pos->>'tax_recognised')::numeric - (pos->>'tax_reversed')::numeric;
  v_entry := erp.equity_entry(g.company_id, v_date, 'Subvención: lo pendiente, al resultado (baja del activo) · ' || g.description, g.code,
               jsonb_build_array(erp.equity_line(g.transfer_account_id, v_amt, 0), erp.equity_line(g.result_account_id, 0, v_amt),
                                 erp.equity_line(g.deferred_account_id, v_tax, 0), erp.equity_line(g.tax_account_id, 0, v_tax)));
  insert into erp.grant_events (grant_id, company_id, kind, event_date, amount, tax_amount, entry_id)
  values (g.id, g.company_id, 'disposal', v_date, v_amt, v_tax, v_entry);
  update erp.grants set status = 'imputed' where id = g.id;
  return jsonb_build_object('code', g.code, 'amount', v_amt, 'tax', v_tax, 'entry_no', (select entry_no from erp.journal_entries where id = v_entry));
end $$;

-- 9) Deshacer el último movimiento (si es la concesión, la subvención queda anulada)
create or replace function erp.grant_cancel(p_grant uuid)
returns jsonb language plpgsql security definer set search_path = erp, public as $$
declare g erp.grants; ev erp.grant_events;
begin
  select * into g from erp.grants where id = p_grant;
  if not found then raise exception 'Grant not found'; end if;
  if not erp.can_write(g.company_id) then raise exception 'No permission to change grants in this company'; end if;
  perform pg_advisory_xact_lock(hashtext('grants/' || g.company_id));
  select * into ev from erp.grant_events where grant_id = p_grant and status = 'posted' order by seq desc limit 1;
  if not found then raise exception 'The grant is already cancelled'; end if;
  if exists (select 1 from erp.fiscal_years f where f.company_id = g.company_id and ev.event_date between f.starting_date and f.ending_date and f.status = 'closed') then
    raise exception 'The year of this posting is closed: reopen it first';
  end if;
  if ev.entry_id is not null then perform erp.adjust_reverse(ev.entry_id, ev.event_date, 'Deshacer ' || g.code); end if;
  update erp.grant_events set status = 'cancelled' where id = ev.id;
  update erp.grants set status = case when ev.kind = 'concession' then 'cancelled' else 'active' end where id = g.id;
  return jsonb_build_object('code', g.code, 'kind', ev.kind, 'date', ev.event_date);
end $$;

-- 10) Las subvenciones de la empresa (lo que enseña la pantalla)
create or replace function erp.grant_status(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
begin
  if not erp.can_read(p_company) then raise exception 'No permission to read this company'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('grant_id', g.id, 'code', g.code, 'kind', g.kind, 'description', g.description,
      'grantor', g.grantor, 'amount', g.amount, 'grant_date', g.grant_date, 'refundable', g.refundable, 'condition_due', g.condition_due,
      'tax_rate', g.tax_rate, 'status', g.status, 'asset_code', (select code from erp.fixed_assets where id = g.asset_id),
      'asset_name', (select name from erp.fixed_assets where id = g.asset_id),
      'unconditional', (pos->>'unconditional')::boolean, 'collected', (pos->>'collected')::boolean,
      'imputed', (pos->>'imputed')::numeric, 'pending', g.amount - (pos->>'imputed')::numeric,
      'deferred_tax', (pos->>'tax_recognised')::numeric - (pos->>'tax_reversed')::numeric) order by g.code)
    from erp.grants g cross join lateral (select erp.grant_position(g.id) pos) z
    where g.company_id = p_company and g.status <> 'cancelled'), '[]');
end $$;

revoke execute on function erp.grant_check(uuid, date), erp.grant_position(uuid), erp.grant_imputation_amount(uuid, date) from anon, public, authenticated;
revoke execute on function erp.grant_create(jsonb), erp.grant_collect(jsonb), erp.grant_unconditional(jsonb), erp.grant_year_end_preview(uuid, date),
  erp.grant_year_end(uuid, date), erp.grant_impute_rest(jsonb), erp.grant_cancel(uuid), erp.grant_status(uuid) from anon, public;
grant execute on function erp.grant_create(jsonb), erp.grant_collect(jsonb), erp.grant_unconditional(jsonb), erp.grant_year_end_preview(uuid, date),
  erp.grant_year_end(uuid, date), erp.grant_impute_rest(jsonb), erp.grant_cancel(uuid), erp.grant_status(uuid) to authenticated;

-- 11) Módulo propio: no se anula desde el diario, no es un asiento manual, tiene su origen en el diario y en el
--     auditor, y se borra con la empresa (versiones de la 0062; cambia solo lo marcado «v0.44.0»)
CREATE OR REPLACE FUNCTION erp.tg_entry_adjust_reverse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.reversal_of is not null and coalesce(current_setting('erp.adjust_engine', true), '') <> 'on' then
    if exists (select 1 from erp.accruals where new.reversal_of in (entry_id, reversal_entry_id)) then
      raise exception 'This entry belongs to an accrual: undo it from Year-end adjustments';
    end if;
    if exists (select 1 from erp.receivable_impairments where new.reversal_of in (entry_id, end_entry_id))
       or exists (select 1 from erp.receivable_writeoffs where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a receivable impairment: undo it from Year-end adjustments';
    end if;
    -- v0.37.0: provisiones
    if exists (select 1 from erp.provision_movements where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a provision: undo it from Year-end adjustments';
    end if;
    -- v0.37.0: inventario del cierre
    if exists (select 1 from erp.inventory_counts where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to an inventory count: undo it from Year-end adjustments';
    end if;
    -- v0.41.0: Impuesto sobre Sociedades
    if exists (select 1 from erp.corporate_tax_returns where new.reversal_of in (current_entry_id, deferred_entry_id)) then
      raise exception 'This entry belongs to the corporate income tax: undo it from Corporate tax';
    end if;
    -- v0.42.0: operaciones societarias
    if exists (select 1 from erp.equity_operations where new.reversal_of = any (entry_ids)) then
      raise exception 'This entry belongs to an equity operation: undo it from Equity operations';
    end if;
    -- v0.43.0: préstamos y arrendamiento financiero
    if exists (select 1 from erp.loan_events where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a loan or finance lease: undo it from Financing';
    end if;
    -- v0.44.0: subvenciones
    if exists (select 1 from erp.grant_events where entry_id = new.reversal_of) then
      raise exception 'This entry belongs to a grant: undo it from Grants';
    end if;
    -- v0.38.0: nóminas y sus pagos
    if exists (select 1 from erp.payroll_runs where new.reversal_of in (entry_id, net_payment_entry_id, ss_payment_entry_id)) then
      raise exception 'This entry belongs to a payroll: undo it from Payroll';
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION erp.entry_is_manual(p_entry uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
  select e.entry_type = 'normal' and e.reversal_of is null and e.reversed_by is null and e.import_batch_id is null
     and not exists (select 1 from erp.invoices i where i.entry_id = e.id)
     and not exists (select 1 from erp.tax_settlements s where s.entry_id = e.id)
     and not exists (select 1 from erp.pro_rata p where p.entry_id = e.id)
     and not exists (select 1 from erp.year_closings c where e.id in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id))
     and not exists (select 1 from erp.payments py where py.entry_id = e.id and not py.linked)
     and not exists (select 1 from erp.asset_depreciations d where d.entry_id = e.id)
     and not exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = e.id)
     and not exists (select 1 from erp.asset_events ae where ae.entry_id = e.id)   -- v0.37.0
     -- v0.36.0: periodificaciones y deterioros
     and not exists (select 1 from erp.accruals ac where e.id in (ac.entry_id, ac.reversal_entry_id))
     and not exists (select 1 from erp.receivable_impairments ri where e.id in (ri.entry_id, ri.end_entry_id))
     -- v0.37.0: provisiones
     and not exists (select 1 from erp.provision_movements pm where pm.entry_id = e.id)
     and not exists (select 1 from erp.inventory_counts ic where ic.entry_id = e.id)   -- v0.37.0: inventario
     and not exists (select 1 from erp.payroll_runs pr where e.id in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id))   -- v0.38.0
     and not exists (select 1 from erp.corporate_tax_returns ct where e.id in (ct.current_entry_id, ct.deferred_entry_id))   -- v0.41.0
     and not exists (select 1 from erp.equity_operations eo where e.id = any (eo.entry_ids))   -- v0.42.0
     and not exists (select 1 from erp.loan_events le where le.entry_id = e.id)   -- v0.43.0
     and not exists (select 1 from erp.grant_events ge where ge.entry_id = e.id)   -- v0.44.0
  from erp.journal_entries e where e.id = p_entry;
$function$
;

create or replace view erp.v_general_journal with (security_invoker = true) as
select e.company_id,
       fy.year          as fiscal_year,
       e.entry_no,
       e.posting_date,
       e.description    as entry_description,
       e.document_no,
       e.entry_type,
       l.line_no,
       a.account_no,
       a.name           as account_name,
       a.name_en        as account_name_en,
       l.debit,
       l.credit,
       coalesce(l.description, e.description) as description,
       e.id             as entry_id,
       ro.entry_no      as reversal_of_no,
       rb.entry_no      as reversed_by_no,
       case when exists (select 1 from erp.invoices i where i.entry_id = e.id) then 'invoice'
            when exists (select 1 from erp.tax_settlements s where s.entry_id = e.id or s.entry_id = e.reversal_of) then 'settlement'
            when exists (select 1 from erp.year_closings c
                         where coalesce(e.reversal_of, e.id) in (c.closing_pl_entry_id, c.closing_entry_id, c.opening_entry_id)) then 'closing'
            -- v0.36.0: periodificaciones y deterioros (la insolvencia firme también es un «cobro»: va antes)
            when exists (select 1 from erp.accruals ac where coalesce(e.reversal_of, e.id) in (ac.entry_id, ac.reversal_entry_id)) then 'accrual'
            when exists (select 1 from erp.receivable_impairments ri where coalesce(e.reversal_of, e.id) in (ri.entry_id, ri.end_entry_id))
              or exists (select 1 from erp.receivable_writeoffs w where w.entry_id = coalesce(e.reversal_of, e.id)) then 'impairment'
            -- v0.37.0: provisiones
            when exists (select 1 from erp.provision_movements pm where pm.entry_id = coalesce(e.reversal_of, e.id)) then 'provision'
            when exists (select 1 from erp.inventory_counts ic where ic.entry_id = coalesce(e.reversal_of, e.id)) then 'inventory'
            -- v0.41.0: Impuesto sobre Sociedades
            when exists (select 1 from erp.corporate_tax_returns ct
                         where coalesce(e.reversal_of, e.id) in (ct.current_entry_id, ct.deferred_entry_id)) then 'corporate_tax'
            -- v0.42.0: operaciones societarias
            when exists (select 1 from erp.equity_operations eo where coalesce(e.reversal_of, e.id) = any (eo.entry_ids)) then 'equity'
            -- v0.43.0: préstamos y arrendamiento financiero
            when exists (select 1 from erp.loan_events le where le.entry_id = coalesce(e.reversal_of, e.id)) then 'financing'
            -- v0.44.0: subvenciones
            when exists (select 1 from erp.grant_events ge where ge.entry_id = coalesce(e.reversal_of, e.id)) then 'grant'
            -- v0.38.0: nóminas y sus pagos
            when exists (select 1 from erp.payroll_runs pr
                         where coalesce(e.reversal_of, e.id) in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id)) then 'payroll'
            when exists (select 1 from erp.payments py where not py.linked and (py.entry_id = e.id or py.cancel_entry_id = e.id)) then 'payment'
            when exists (select 1 from erp.asset_depreciations d where d.entry_id = coalesce(e.reversal_of, e.id))
              or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = coalesce(e.reversal_of, e.id))
              or exists (select 1 from erp.asset_events ae where ae.entry_id = coalesce(e.reversal_of, e.id)) then 'asset'
            when e.reversal_of is not null then 'reversal'
            else 'manual' end as source,
       e.reversal_reason
from erp.journal_entries e
join erp.fiscal_years  fy on fy.id = e.fiscal_year_id
join erp.journal_lines l  on l.entry_id = e.id
join erp.gl_accounts   a  on a.id = l.gl_account_id
left join erp.journal_entries ro on ro.id = e.reversal_of
left join erp.journal_entries rb on rb.id = e.reversed_by
where e.status = 'posted';

CREATE OR REPLACE FUNCTION erp.audit_lines(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date)
 RETURNS TABLE(entry_id uuid, entry_no integer, posting_date date, k uuid, source text, account_no text, account_name text, debit numeric, credit numeric, tax_code text)
 LANGUAGE sql
 STABLE
AS $function$
  select e.id, e.entry_no, e.posting_date, coalesce(e.reversal_of, e.id),
         case when exists (select 1 from erp.invoices i where i.entry_id = coalesce(e.reversal_of, e.id)) then 'invoice'
              when exists (select 1 from erp.tax_settlements s where s.entry_id = coalesce(e.reversal_of, e.id)) then 'settlement'
              when exists (select 1 from erp.pro_rata p where p.entry_id = coalesce(e.reversal_of, e.id)) then 'pro_rata'
              -- v0.36.0: periodificaciones y deterioros (antes que los cobros: la insolvencia firme también lo es)
              when exists (select 1 from erp.accruals ac where coalesce(e.reversal_of, e.id) in (ac.entry_id, ac.reversal_entry_id)) then 'accrual'
              when exists (select 1 from erp.receivable_impairments ri where coalesce(e.reversal_of, e.id) in (ri.entry_id, ri.end_entry_id))
                or exists (select 1 from erp.receivable_writeoffs w where w.entry_id = coalesce(e.reversal_of, e.id)) then 'impairment'
              -- v0.37.0: provisiones
              when exists (select 1 from erp.provision_movements pm where pm.entry_id = coalesce(e.reversal_of, e.id)) then 'provision'
              when exists (select 1 from erp.inventory_counts ic where ic.entry_id = coalesce(e.reversal_of, e.id)) then 'inventory'
              -- v0.41.0: Impuesto sobre Sociedades
              when exists (select 1 from erp.corporate_tax_returns ct
                           where coalesce(e.reversal_of, e.id) in (ct.current_entry_id, ct.deferred_entry_id)) then 'corporate_tax'
              -- v0.42.0: operaciones societarias
              when exists (select 1 from erp.equity_operations eo where coalesce(e.reversal_of, e.id) = any (eo.entry_ids)) then 'equity'
              -- v0.43.0: préstamos y arrendamiento financiero
              when exists (select 1 from erp.loan_events le where le.entry_id = coalesce(e.reversal_of, e.id)) then 'financing'
              -- v0.44.0: subvenciones
              when exists (select 1 from erp.grant_events ge where ge.entry_id = coalesce(e.reversal_of, e.id)) then 'grant'
              -- v0.38.0: nóminas y sus pagos
              when exists (select 1 from erp.payroll_runs pr
                           where coalesce(e.reversal_of, e.id) in (pr.entry_id, pr.net_payment_entry_id, pr.ss_payment_entry_id)) then 'payroll'
              when exists (select 1 from erp.payments py where not py.linked
                           and coalesce(e.reversal_of, e.id) in (py.entry_id, py.cancel_entry_id)) then 'payment'
              when exists (select 1 from erp.asset_depreciations d where d.entry_id = coalesce(e.reversal_of, e.id))
                or exists (select 1 from erp.fixed_assets fa where fa.disposal_entry_id = coalesce(e.reversal_of, e.id))
                or exists (select 1 from erp.asset_events ae where ae.entry_id = coalesce(e.reversal_of, e.id)) then 'asset'
              when o.import_batch_id is not null then 'import'
              else 'manual' end,
         g.account_no, g.name, l.debit, l.credit, l.tax_code
  from erp.journal_entries e
  join erp.fiscal_years fy on fy.id = e.fiscal_year_id
  join erp.journal_entries o on o.id = coalesce(e.reversal_of, e.id)
  join erp.journal_lines l on l.entry_id = e.id
  join erp.gl_accounts g on g.id = l.gl_account_id
  where e.company_id = p_company and fy.year = p_year and e.status = 'posted' and e.entry_type = 'normal'
    and (p_to_date is null or e.posting_date <= p_to_date);
$function$
;

CREATE OR REPLACE FUNCTION erp.delete_company_step(p_company uuid, p_batch integer DEFAULT 5000)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'erp', 'public'
AS $function$
declare
  v_ids  uuid[];
  v_left int;
begin
  if not exists (select 1 from erp.company_users
                 where company_id = p_company and user_id = auth.uid() and role = 'admin') then
    raise exception 'Only the company admin can delete it';
  end if;
  perform set_config('erp.deleting_company', 'on', true);   -- solo dura esta transacción

  -- Documentos que apuntan a asientos (en la primera tanda; en las siguientes ya no hay nada)
  delete from erp.grants                 where company_id = p_company;   -- v0.44.0 (sus movimientos, en cascada)
  delete from erp.loans                  where company_id = p_company;   -- v0.43.0 (su cuadro y sus movimientos, en cascada)
  delete from erp.equity_operations      where company_id = p_company;   -- v0.42.0
  delete from erp.corporate_tax_returns  where company_id = p_company;   -- v0.41.0 (sus ajustes, en cascada)
  delete from erp.payroll_runs           where company_id = p_company;   -- v0.38.0 (las nóminas de cada empleado, en cascada)
  delete from erp.employees              where company_id = p_company;   -- v0.38.0
  delete from erp.inventory_counts       where company_id = p_company;   -- v0.37.0 (sus líneas, en cascada)
  delete from erp.provision_movements    where company_id = p_company;   -- v0.37.0
  delete from erp.provisions             where company_id = p_company;   -- v0.37.0
  delete from erp.receivable_writeoffs   where company_id = p_company;   -- v0.36.0 (antes que los pagos)
  delete from erp.receivable_impairments where company_id = p_company;   -- v0.36.0
  delete from erp.accruals               where company_id = p_company;   -- v0.36.0
  delete from erp.asset_depreciations where company_id = p_company;
  delete from erp.fixed_assets    where company_id = p_company;
  delete from erp.payments        where company_id = p_company;   -- sus aplicaciones, en cascada
  delete from erp.year_closings   where company_id = p_company;
  delete from erp.pro_rata        where company_id = p_company;
  delete from erp.tax_settlements where company_id = p_company;
  delete from erp.invoices        where company_id = p_company;   -- sus líneas, en cascada

  -- Tanda de asientos (los más recientes primero) + su pareja de anulación
  with b as (
    select id, reversal_of, reversed_by from erp.journal_entries
    where company_id = p_company
    order by posting_date desc, entry_no desc nulls first
    limit greatest(p_batch, 1)
  )
  select array_agg(distinct x) into v_ids
  from (select id from b
        union all select reversal_of from b where reversal_of is not null
        union all select reversed_by from b where reversed_by is not null) s(x);

  if v_ids is not null then
    delete from erp.journal_lines   where entry_id = any (v_ids);
    delete from erp.journal_entries where id = any (v_ids);
  end if;

  select count(*)::int into v_left from erp.journal_entries where company_id = p_company;
  if v_left = 0 then
    delete from erp.import_lines where company_id = p_company;
    delete from erp.companies    where id = p_company;
  end if;

  perform set_config('erp.deleting_company', 'off', true);
  return v_left;
end $function$
;
