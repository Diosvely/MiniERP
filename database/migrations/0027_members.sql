-- =====================================================================
-- 0027 · MEMBERS · Accesos y titulares de los datos
-- ---------------------------------------------------------------------
-- Roles al estilo de Microsoft (área de trabajo de Power BI / Fabric):
--   Administrador  → el propietario de la aplicación (owner): control total.               (ya existía)
--   MIEMBRO        → el TITULAR DE LOS DATOS de una empresa que el owner importó con su permiso:
--                    la ve y trabaja en ella como contable, usa la IA (con cuota diaria)
--                    y decide él si la publica como demo y con qué mención.                 (NUEVO)
--   Colaborador    → quien se registra y lleva sus propias empresas.                         (ya existía)
--   Visor          → el invitado que mira las demos.                                          (ya existía)
-- El acceso se da por email (grant_company_access, solo el owner): el usuario tiene que estar registrado
-- (se registra él, o el owner lo crea en Supabase › Authentication).
-- La IA deja de ser solo del owner: el owner (sin límite) y el titular de los datos en su empresa (con cuota).
-- Las opiniones sobre las respuestas de la IA se guardan en ai_feedback para mejorarla.
-- =====================================================================

alter table erp.company_users add column if not exists data_owner boolean not null default false;
comment on column erp.company_users.data_owner is
  'Data owner (Member): the person who provided this company''s data. Can publish it as demo and use the AI.';
alter table erp.companies add column if not exists data_credit text check (length(data_credit) <= 200);
comment on column erp.companies.data_credit is 'Credit shown in the demo, e.g. "Data from course X".';
alter table erp.app_profiles add column if not exists ai_daily_limit smallint check (ai_daily_limit >= 0);
comment on column erp.app_profiles.ai_daily_limit is 'AI calls per day for this user (null: the default of 10; the owner has no limit).';

-- ¿Es el usuario conectado el titular de los datos de esta empresa?
create or replace function erp.is_data_owner(p_company uuid)
returns boolean language sql stable security definer set search_path = erp, public as $$
  select exists (select 1 from erp.company_users
                 where company_id = p_company and user_id = auth.uid() and data_owner);
$$;

-- ¿Puede usar la IA en esta empresa? El owner en las que puede leer; el titular de los datos en la suya.
create or replace function erp.ai_allowed(p_company uuid)
returns boolean language sql stable security definer set search_path = erp, public as $$
  select (erp.is_owner() and erp.can_read(p_company)) or erp.is_data_owner(p_company);
$$;

-- ---------------------------------------------------------------------
-- Cuota diaria de IA (el modelo gratuito de Cloudflare tiene un límite diario compartido)
-- ---------------------------------------------------------------------
create table if not exists erp.ai_usage (
  user_id  uuid not null,
  used_on  date not null default current_date,
  calls    int  not null default 0,
  primary key (user_id, used_on)
);
alter table erp.ai_usage enable row level security;
drop policy if exists own on erp.ai_usage;
create policy own on erp.ai_usage for select to authenticated using (user_id = auth.uid() or erp.is_owner());
revoke all on erp.ai_usage from anon, public;
grant select on erp.ai_usage to authenticated;

-- La llama la función de Cloudflare ANTES de usar el modelo: comprueba el permiso, suma 1 y devuelve lo que queda
create or replace function erp.ai_consume(p_company uuid)
returns jsonb language plpgsql volatile security definer set search_path = erp, public as $$
declare
  v_limit int;
  v_used  int;
begin
  if not erp.ai_allowed(p_company) then raise exception 'The AI is not enabled for you in this company'; end if;
  insert into erp.ai_usage (user_id, used_on, calls) values (auth.uid(), current_date, 1)
  on conflict (user_id, used_on) do update set calls = erp.ai_usage.calls + 1
  returning calls into v_used;
  if erp.is_owner() then
    return jsonb_build_object('used', v_used, 'limit', null, 'remaining', null);
  end if;
  select coalesce(ai_daily_limit, 10) into v_limit from erp.app_profiles where user_id = auth.uid();
  v_limit := coalesce(v_limit, 10);
  if v_used > v_limit then
    raise exception 'Daily AI limit reached (% per day)', v_limit;
  end if;
  return jsonb_build_object('used', v_used, 'limit', v_limit, 'remaining', v_limit - v_used);
end $$;

-- La web: ¿enseño los botones de IA en esta empresa?
create or replace function erp.ai_status(p_company uuid)
returns jsonb language sql stable security definer set search_path = erp, public as $$
  select jsonb_build_object(
    'allowed', erp.ai_allowed(p_company),
    'used', coalesce((select calls from erp.ai_usage where user_id = auth.uid() and used_on = current_date), 0),
    'limit', case when erp.is_owner() then null
                  else coalesce((select ai_daily_limit from erp.app_profiles where user_id = auth.uid()), 10) end);
$$;

-- ---------------------------------------------------------------------
-- Lo que la IA recibe ahora lo puede pedir también el titular de los datos
-- ---------------------------------------------------------------------
create or replace function erp.ai_context(p_company uuid, p_year int, p_language text default 'es')
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare
  en      boolean := p_language = 'en';
  v_out   jsonb;
begin
  if not erp.ai_allowed(p_company) then raise exception 'The AI analyst is not enabled for you in this company'; end if;
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  if not exists (select 1 from erp.fiscal_years where company_id = p_company and year = p_year) then
    raise exception 'Fiscal year % does not exist', p_year;
  end if;

  select jsonb_build_object(
    'language', case when en then 'en' else 'es' end,
    'year', p_year,
    'previous_year', p_year - 1,
    'currency', 'EUR',
    'company', (select jsonb_build_object(
                  'industry', c.industry, 'tax_territory', c.tax_territory,
                  'tax', case c.tax_territory when 'canary_islands' then 'IGIC' else 'VAT/IVA' end,
                  'imported_from', (select b.source from erp.import_batches b where b.company_id = c.id
                                    order by b.created_at desc limit 1))
                from erp.companies c where c.id = p_company),
    -- Estados financieros (modelo PYMES): partidas hasta el segundo nivel con importe en alguno de los dos años
    'balance_sheet', (select jsonb_agg(jsonb_build_object('line', case when en then s.label_en else s.label end,
                         'amount', s.amount, 'previous', s.amount_prev) order by s.sort)
                      from erp.financial_statement(p_company, p_year, 'balance') s
                      where s.level <= 2 and (s.amount <> 0 or s.amount_prev <> 0)),
    'income_statement', (select jsonb_agg(jsonb_build_object('line', case when en then s.label_en else s.label end,
                            'amount', s.amount, 'previous', s.amount_prev) order by s.sort)
                         from erp.financial_statement(p_company, p_year, 'pyg') s
                         where s.amount <> 0 or s.amount_prev <> 0),
    -- Flujos de efectivo: método indirecto y el cuadre con el directo
    'cash_flow_indirect', (select jsonb_agg(jsonb_build_object('line', case when en then s.label_en else s.label end,
                              'amount', s.amount, 'previous', s.amount_prev) order by s.sort)
                           from erp.cash_flow_statement(p_company, p_year, 'indirect') s
                           where s.level <= 2 and (s.amount <> 0 or s.amount_prev <> 0)),
    'cash_flow_check', (select k - 'cross_entries' - 'year' from erp.cash_flow_check(p_company, p_year) k),
    -- Ratios con su zona de referencia y su valoración (ok / low / high)
    'ratios', (select jsonb_agg(jsonb_build_object(
                  'group', r.grp, 'ratio', case when en then r.label_en else r.label end,
                  'formula', case when en then r.formula_en else r.formula end,
                  'unit', case r.unit when 'pct' then 'percent' when 'eur' then 'EUR' else r.unit end,
                  'value', erp.ai_ratio_value(r.value, r.unit), 'previous', erp.ai_ratio_value(r.value_prev, r.unit),
                  'reference_min', erp.ai_ratio_value(r.ref_min, r.unit), 'reference_max', erp.ai_ratio_value(r.ref_max, r.unit),
                  'status', r.status,
                  -- para que la IA no confunda "bajo" con "malo": en estos, quedarse por debajo es menos riesgo
                  'lower_is_safer', r.code in ('DEBT', 'DQ', 'FINC', 'DSO', 'DPO', 'DIO')))
               from erp.financial_ratios(p_company, p_year) r)
  ) into v_out;
  return jsonb_strip_nulls(v_out);
end $$;

create or replace function erp.entry_tutor_context(p_company uuid, p_language text default 'es')
returns jsonb language plpgsql stable security definer set search_path = erp, public as $$
declare
  en boolean := p_language = 'en';
  c  erp.companies;
begin
  if not erp.ai_allowed(p_company) then raise exception 'The AI tutor is not enabled for you in this company'; end if;
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select * into c from erp.companies where id = p_company;

  return jsonb_build_object(
    'language', case when en then 'en' else 'es' end,
    'today', current_date,
    'company', jsonb_build_object(
      'industry', c.industry, 'tax_territory', c.tax_territory,
      'tax', case c.tax_territory when 'canary_islands' then 'IGIC' else 'IVA' end,
      'vat_regime', c.vat_regime),
    -- PGC 2007: cuentas de 3 y 4 dígitos (las de 1 y 2 son títulos de grupo y subgrupo)
    'chart_of_accounts', (select jsonb_agg(t.account_no || ' ' || case when en then t.name_en else t.name end
                                           order by t.account_no)
                          from erp.coa_template t where t.level >= 3),
    -- Tipos vigentes de la empresa, con sus cuentas: la IA no decide ni el tipo ni la cuenta del impuesto
    'tax_codes', (select jsonb_agg(jsonb_build_object(
                    'tax_code', s.tax_code, 'tax', s.tax_type, 'category', s.rate_category, 'rate_pct', s.rate_pct,
                    'description', case when en then coalesce(s.description_en, s.description) else s.description end,
                    'input_account', s.input_account_no, 'output_account', s.output_account_no) order by s.tax_code)
                  from erp.v_tax_setup s where s.company_id = p_company and not s.blocked),
    'tax_setup', exists (select 1 from erp.v_tax_setup s where s.company_id = p_company),
    'withholdings', (select jsonb_agg(jsonb_build_object(
                       'code', w.withholding_code, 'rate_pct', w.rate_pct, 'form', w.form,
                       'description', case when en then coalesce(w.description_en, w.description) else w.description end,
                       'payable_account', w.payable_account_no, 'receivable_account', w.receivable_account_no)
                       order by w.withholding_code)
                     from erp.v_withholding_setup w where w.company_id = p_company and not w.blocked),
    'valuation_rules', (select jsonb_agg(jsonb_build_object('code', r.code,
                          'title', case when en then r.title_en else r.title end) order by r.sort)
                        from erp.valuation_rules r));
end $$;

-- ---------------------------------------------------------------------
-- Opiniones sobre la IA: el Miembro (o el owner) dice si la respuesta es correcta
-- ---------------------------------------------------------------------
create table if not exists erp.ai_feedback (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references erp.companies(id) on delete cascade,
  user_id     uuid not null default auth.uid(),
  kind        text not null check (kind in ('tutor', 'analyst')),
  prompt      text,                                  -- la operación descrita (tutor)
  answer      jsonb not null,                        -- lo que respondió la IA (y el ERP)
  verdict     text not null check (verdict in ('correct', 'partial', 'wrong')),
  comment     text check (length(comment) <= 2000),
  model       text,
  created_at  timestamptz not null default now()
);
alter table erp.ai_feedback enable row level security;
drop policy if exists read on erp.ai_feedback;
drop policy if exists add on erp.ai_feedback;
create policy read on erp.ai_feedback for select to authenticated using (user_id = auth.uid() or erp.is_owner());
create policy add  on erp.ai_feedback for insert to authenticated
  with check (user_id = auth.uid() and erp.ai_allowed(company_id));
revoke all on erp.ai_feedback from anon, public;
grant select, insert on erp.ai_feedback to authenticated;

-- ---------------------------------------------------------------------
-- ACCESOS (solo el owner): dar, quitar y listar quién entra en una empresa
-- ---------------------------------------------------------------------
create or replace function erp.grant_company_access(p_company uuid, p_email text, p_role text, p_data_owner boolean default false)
returns uuid language plpgsql security definer set search_path = erp, public as $$
declare v_user uuid;
begin
  if not erp.is_owner() then raise exception 'Only the application owner can manage access'; end if;
  if p_role not in ('admin', 'accountant', 'viewer') then raise exception 'Unknown role: %', p_role; end if;
  select id into v_user from auth.users where lower(email) = lower(trim(p_email));
  if v_user is null then raise exception 'No registered user with email %', p_email; end if;
  if v_user = auth.uid() then raise exception 'You already have full access'; end if;
  insert into erp.company_users (company_id, user_id, role, data_owner)
  values (p_company, v_user, p_role, coalesce(p_data_owner, false))
  on conflict (company_id, user_id) do update set role = excluded.role, data_owner = excluded.data_owner;
  return v_user;
end $$;

create or replace function erp.revoke_company_access(p_company uuid, p_user uuid)
returns void language plpgsql security definer set search_path = erp, public as $$
begin
  if not erp.is_owner() then raise exception 'Only the application owner can manage access'; end if;
  if p_user = auth.uid() then raise exception 'You cannot remove your own access'; end if;
  delete from erp.company_users where company_id = p_company and user_id = p_user;
end $$;

create or replace function erp.company_access(p_company uuid)
returns table (user_id uuid, email text, role text, data_owner boolean, since timestamptz, ai_calls_today int)
language plpgsql stable security definer set search_path = erp, public as $$
begin
  if not erp.is_owner() then raise exception 'Only the application owner can manage access'; end if;
  return query
  select cu.user_id, u.email::text, cu.role, cu.data_owner, cu.created_at,
         coalesce((select a.calls from erp.ai_usage a where a.user_id = cu.user_id and a.used_on = current_date), 0)
  from erp.company_users cu join auth.users u on u.id = cu.user_id
  where cu.company_id = p_company
  order by cu.created_at;
end $$;

-- ---------------------------------------------------------------------
-- DEMO: la publica el owner o el TITULAR DE LOS DATOS (con su mención)
-- ---------------------------------------------------------------------
create or replace function erp.tg_company_rules()
returns trigger language plpgsql security definer set search_path = erp, public as $$
declare
  v_max     int;
  v_created int;
begin
  if auth.uid() is null then
    return new;
  end if;

  if erp.is_anonymous() then
    raise exception 'Guest visitors can only view the demo companies: sign up to create your own';
  end if;

  if tg_op = 'INSERT' then
    select max_companies into v_max from erp.my_profile();
    select companies_created into v_created from erp.my_profile();
    if v_max is not null and v_created >= v_max then
      raise exception 'Company limit reached: your account can create % compan%', v_max,
        case when v_max = 1 then 'y' else 'ies' end;
    end if;
  end if;

  if (tg_op = 'INSERT' and new.is_demo)
     or (tg_op = 'UPDATE' and new.is_demo is distinct from old.is_demo) then
    -- el propietario de la aplicación, o el titular de los datos de ESTA empresa (0027)
    if not (erp.is_owner() or (tg_op = 'UPDATE' and erp.is_data_owner(new.id))) then
      raise exception 'Only the application owner or the data owner can publish a company as demo';
    end if;
  end if;

  return new;
end $$;

create or replace function erp.set_company_demo(p_company uuid, p_demo boolean, p_credit text default null)
returns void language plpgsql security definer set search_path = erp, public as $$
begin
  if not (erp.is_owner() or erp.is_data_owner(p_company)) then
    raise exception 'Only the application owner or the data owner can publish a company as demo';
  end if;
  update erp.companies
  set is_demo = p_demo, data_credit = coalesce(nullif(trim(p_credit), ''), data_credit)
  where id = p_company;
end $$;

revoke execute on function erp.is_data_owner(uuid), erp.ai_allowed(uuid), erp.ai_consume(uuid), erp.ai_status(uuid),
  erp.grant_company_access(uuid, text, text, boolean), erp.revoke_company_access(uuid, uuid), erp.company_access(uuid),
  erp.set_company_demo(uuid, boolean, text) from anon, public;
grant execute on function erp.is_data_owner(uuid), erp.ai_allowed(uuid), erp.ai_consume(uuid), erp.ai_status(uuid),
  erp.grant_company_access(uuid, text, text, boolean), erp.revoke_company_access(uuid, uuid), erp.company_access(uuid),
  erp.set_company_demo(uuid, boolean, text) to authenticated;

-- La lista de empresas dice si soy el titular de los datos y trae la mención de la demo
create or replace view erp.v_my_companies with (security_invoker = true) as
select c.id, c.name, c.vat_registration_no, c.industry, c.tax_territory,
       c.posting_account_digits, c.is_demo, c.created_at,
       erp.my_role(c.id) as my_role,
       c.vat_regime,
       c.data_credit,
       erp.is_data_owner(c.id) as is_data_owner
from erp.companies c;
grant select on erp.v_my_companies to authenticated;
