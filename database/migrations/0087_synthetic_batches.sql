-- =====================================================================
-- 0087 · Empresas sintéticas por tandas (v0.59.1, paso 289)
-- ---------------------------------------------------------------------
-- En Supabase, la v0.59.0 no creaba la empresa: generar un año (unos 460 asientos) de una vez superaba el límite de
-- ~8 s de las llamadas de la web («canceling statement due to statement timeout») y PostgreSQL lo deshacía todo, también
-- la empresa. El límite no se puede subir desde una función (ya lo vimos en la 0029). Como el borrado de empresas y la
-- importación de diarios, se hace POR TANDAS:
--   · erp.create_synthetic_company: crea la empresa, la prepara (ejercicio, impuestos, terceros, plantilla, constitución)
--     y GUARDA EL PLAN de operaciones en erp.synthetic_plan, en orden de fecha (rápido).
--   · erp.synthetic_step(empresa, n): ejecuta las n operaciones siguientes del plan (la web pide tandas de 40 y enseña
--     el progreso). Cada tanda es su propia transacción: si una falla, las anteriores quedan y se puede continuar.
--   · erp.synthetic_progress: cuántas van y cuántas faltan (la web ofrece «Continuar la generación»).
--   · erp.synthetic_run: todas las tandas seguidas (para el SQL Editor y las pruebas, que no tienen el límite de la web).
-- El resultado es EXACTAMENTE el de la v0.59.0: los mismos números al azar, en el mismo orden, y las mismas operaciones
-- en el mismo orden (la semilla 4817 · taller · 12 meses sigue dando g1-2C3AD24C). La versión del generador sigue en g1.
-- =====================================================================

-- ---------- El plan de cada empresa sintética ----------
create table if not exists erp.synthetic_plan (
  company_id uuid not null references erp.companies(id) on delete cascade,
  seq        int  not null,                  -- el orden de ejecución (fecha, orden del día, tipo, referencia)
  d          date not null,                  -- la fecha de la operación
  k          text not null,                  -- el tipo: sale, collect, purchase, pay, payroll, quarter…
  ref        text,                           -- la factura a la que se refiere (S3-2, P5-1, R1, A2)
  data       jsonb not null,                 -- importes, tercero, impuesto…
  result     uuid,                           -- lo que creó (la factura, la nómina) para las operaciones que la siguen
  done       boolean not null default false,
  primary key (company_id, seq)
);
comment on table erp.synthetic_plan is 'Synthetic companies (v0.59.1): the planned operations, executed in batches in date order.';
create index if not exists synthetic_plan_pending on erp.synthetic_plan (company_id, seq) where not done;
create index if not exists synthetic_plan_ref on erp.synthetic_plan (company_id, ref) where ref is not null;

alter table erp.synthetic_plan enable row level security;
drop policy if exists read on erp.synthetic_plan;
drop policy if exists manage on erp.synthetic_plan;
create policy read on erp.synthetic_plan for select to authenticated using (erp.can_read(company_id));
create policy manage on erp.synthetic_plan for all to authenticated using (erp.is_admin(company_id)) with check (erp.is_admin(company_id));
revoke all on erp.synthetic_plan from anon, public;
grant select, insert, update, delete on erp.synthetic_plan to authenticated;

-- ---------- 1. Preparar: la empresa lista y el plan guardado (lo que hacía la 0086 antes de ejecutar) ----------
drop function if exists erp.load_synthetic(uuid, int, text, int);
create or replace function erp.synthetic_prepare(p_company uuid, p_seed int, p_profile text, p_months int)
returns jsonb language plpgsql set search_path = erp, public as $$
declare
  e uuid := p_company; n int := 0;   -- n: el contador del azar (cada número se pide una vez y en el mismo orden)
  v_tax text := case when p_profile in ('workshop', 'incidents') then 'IGIC' else 'VAT' end;
  v_gen text := case when p_profile in ('workshop', 'incidents') then 'IGIC7' else 'VAT21' end;
  v_red text := case when p_profile in ('workshop', 'incidents') then 'IGIC3' else 'VAT10' end;
  v_sale_acc text := case p_profile when 'services' then '70500001' else '70000001' end;
  v_end date := (make_date(2026, p_months, 1) + interval '1 month - 1 day')::date;
  cust uuid[] := '{}'; vend uuid[] := '{}'; v_rent uuid; v_adv uuid; v_asset_vendor uuid; v_moroso uuid;
  ev jsonb := '[]'; x jsonb; inv jsonb := '{}'; r record; c text; i int; m int; k int; q int;
  d date; d2 date; v_amt numeric; v_id uuid; v_loan uuid; v_run jsonb := '{}'; v_due numeric; v_entries int;
  v_customers text[] := array['Comercial Teide SL', 'Distribuciones Lagos SL', 'Hostelería Brisa SL', 'Construcciones Roque SL',
    'Clínica Alisio SL', 'Transportes Garajonay SL', 'Academia Faro SL', 'Agencia Marea SL'];
  v_shops text[] := array['Tienda de Ana Ficticia', 'Tienda de Luis Inventado', 'Bazar de Marta Ejemplo'];
  v_vendors text[] := case when p_profile = 'services'
    then array['Papelería Central SL', 'Suministros Digitales SL', 'Limpiezas Brillo SL', 'Formación Abierta SL']
    else array['Mayorista Insular SL', 'Recambios del Sur SL', 'Suministros Atlántico SL', 'Embalajes Costa SL'] end;
  v_exp_acc text[] := case when p_profile = 'services'
    then array['62900001', '62800001', '62200001', '62900001'] else array['60000001', '60000001', '60000001', '62800001'] end;
begin
  if not erp.is_admin(e) then raise exception 'No permission: only the company admin can generate a synthetic company'; end if;
  if exists (select 1 from erp.journal_entries j where j.company_id = e) then
    raise exception 'Generate into a new company: this one already has entries';
  end if;

  -- Preparación: ejercicio, impuestos, retenciones, cuentas y terceros (como en Configuración y Terceros)
  perform erp.create_fiscal_year(e, 2026);
  perform erp.setup_taxes(e);
  perform erp.setup_withholdings(e);
  foreach c in array array['57200001:Banco', '70000001:Ventas de mercaderías', '70500001:Prestaciones de servicios',
    '60000001:Compras de mercaderías', '62100001:Arrendamientos', '62200001:Reparaciones y conservación',
    '62300001:Servicios de profesionales', '62800001:Suministros', '62900001:Otros servicios',
    '21300001:Maquinaria', '21700001:Equipos para procesos de información'] loop
    if not exists (select 1 from erp.gl_accounts where company_id = e and account_no = split_part(c, ':', 1)) then
      perform erp.create_posting_account(e, split_part(c, ':', 1), split_part(c, ':', 2));
    end if;
  end loop;
  -- clientes: seis de la lista (cuáles, según la semilla); en comercio, además, tres tiendas en recargo
  n := n + 1; k := erp.syn_int(p_seed, n, 0, 7);   -- desde qué nombre de la lista se empieza
  for i in 1..6 loop
    select partner_id into v_id from erp.create_partner(e, 'customer', v_customers[1 + (i - 1 + k) % 8], erp.syn_cif('B', p_seed * 10 + i));
    cust := cust || v_id;
  end loop;
  if p_profile = 'trade' then
    for i in 1..3 loop
      select partner_id into v_id from erp.create_partner(e, 'customer', v_shops[i], erp.syn_nif(p_seed * 100 + 50 + i));
      update erp.business_partners set equivalence_surcharge = true where id = v_id;
      cust := cust || v_id;
    end loop;
  end if;
  for i in 1..4 loop
    select partner_id into v_id from erp.create_partner(e, 'vendor', v_vendors[i], erp.syn_cif('B', p_seed * 10 + 5000000 + i));
    vend := vend || v_id;
  end loop;
  select partner_id into v_rent from erp.create_partner(e, 'creditor', 'Locales Puerto SL', erp.syn_cif('B', p_seed * 10 + 7000001));
  select partner_id into v_adv  from erp.create_partner(e, 'creditor', 'Asesoría Ficticia', erp.syn_nif(p_seed * 100 + 7));
  select partner_id into v_asset_vendor from erp.create_partner(e, 'vendor',
    case when p_profile = 'services' then 'Equipos Digitales SL' else 'Maquinaria Atlántica SL' end, erp.syn_cif('B', p_seed * 10 + 8000001));
  if p_profile = 'incidents' then
    select partner_id into v_moroso from erp.create_partner(e, 'customer', 'Cliente Moroso SL', erp.syn_cif('B', p_seed * 10 + 9000001));
  end if;
  -- todos cobran y pagan a 30 días (la fecha de vencimiento de cada factura)
  update erp.business_partners set payment_days = 30 where company_id = e;
  -- plantilla: dos personas ficticias desde el 1 de enero (no en comercio: es un mayorista pequeño, sin nóminas)
  if p_profile <> 'trade' then
    n := n + 1;
    perform erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Empleada Ficticia', 'hire_date', '2026-01-01',
      'monthly_salary', erp.syn_amount(p_seed, n, 1600, 2400), 'irpf_pct', 12));
    n := n + 1;
    perform erp.save_employee(jsonb_build_object('company_id', e, 'name', 'Empleado Inventado', 'hire_date', '2026-01-01',
      'monthly_salary', erp.syn_amount(p_seed, n, 1400, 2000), 'irpf_pct', 8));
  end if;

  -- 1. Constitución (Operaciones societarias): capital de 60.000 a 90.000
  n := n + 1;
  perform erp.equity_incorporation(jsonb_build_object('company_id', e, 'date', '2026-01-02',
    'capital', 60000 + 10000 * erp.syn_int(p_seed, n, 0, 3), 'bank_account_no', '57200001'));

  -- 2. El plan de operaciones: cada una con su fecha y su orden dentro del día (o)
  -- el préstamo, el 15 de enero, con cuotas mensuales; y la inversión del mes 1
  n := n + 1;
  ev := ev || jsonb_build_object('d', '2026-01-15', 'o', 1, 'k', 'loan', 'amount', 20000 + 5000 * erp.syn_int(p_seed, n, 0, 4));
  for m in 2..p_months loop
    ev := ev || jsonb_build_object('d', make_date(2026, m, 15), 'o', 5, 'k', 'loan_pay');
  end loop;
  n := n + 1;
  ev := ev || jsonb_build_object('d', '2026-01-20', 'o', 2, 'k', 'asset', 'pid', v_asset_vendor,
    'amount', case when p_profile = 'services' then erp.syn_amount(p_seed, n, 3000, 9000) else erp.syn_amount(p_seed, n, 15000, 40000) end);
  for m in 1..p_months loop
    -- alquiler del local (con retención del 19 %, modelo 115) y su pago, el día 1
    ev := ev || jsonb_build_object('d', make_date(2026, m, 1), 'o', 1, 'k', 'rent', 'ref', 'R' || m, 'pid', v_rent);
    ev := ev || jsonb_build_object('d', make_date(2026, m, 3), 'o', 6, 'k', 'pay', 'ref', 'R' || m);
    -- ventas: de 6 a 10 en el mes, en días crecientes; el cobro, de 5 a 28 días después (antes de vencer)
    n := n + 1;
    k := erp.syn_int(p_seed, n, 6, 10);
    for i in 1..k loop
      d := make_date(2026, m, 1) + ((i * 27) / (k + 1));
      n := n + 1; v_amt := case when p_profile = 'trade' then erp.syn_amount(p_seed, n, 400, 3500) else erp.syn_amount(p_seed, n, 600, 4500) end;
      n := n + 1;
      ev := ev || jsonb_build_object('d', d, 'o', 3, 'k', 'sale', 'ref', 'S' || m || '-' || i,
        'pid', cust[erp.syn_int(p_seed, n, 1, array_length(cust, 1))], 'amount', v_amt,
        'code', case when erp.syn_rand(p_seed, n + 1000000) < 0.85 then v_gen else v_red end);
      n := n + 1;
      d2 := d + erp.syn_int(p_seed, n, 5, 28);
      if d2 <= v_end then ev := ev || jsonb_build_object('d', d2, 'o', 4, 'k', 'collect', 'ref', 'S' || m || '-' || i); end if;
    end loop;
    -- compras y gastos: de 4 a 7 en el mes; el pago, de 10 a 29 días después
    n := n + 1;
    k := erp.syn_int(p_seed, n, 4, 7);
    for i in 1..k loop
      d := make_date(2026, m, 1) + ((i * 26) / (k + 1)) + 1;
      n := n + 1; q := erp.syn_int(p_seed, n, 1, 4);
      n := n + 1;
      ev := ev || jsonb_build_object('d', d, 'o', 2, 'k', 'purchase', 'ref', 'P' || m || '-' || i, 'pid', vend[q],
        'acc', v_exp_acc[q], 'amount', case when p_profile = 'services' then erp.syn_amount(p_seed, n, 80, 900)
                                            else erp.syn_amount(p_seed, n, 300, 2600) end, 'code', v_gen);
      n := n + 1;
      d2 := d + erp.syn_int(p_seed, n, 10, 29);
      if d2 <= v_end then ev := ev || jsonb_build_object('d', d2, 'o', 6, 'k', 'pay', 'ref', 'P' || m || '-' || i); end if;
    end loop;
    -- la asesoría del mes (profesional con IRPF, modelo 111), pagada a los 10 días
    n := n + 1;
    ev := ev || jsonb_build_object('d', make_date(2026, m, 25), 'o', 2, 'k', 'advisor', 'ref', 'A' || m, 'pid', v_adv,
      'amount', erp.syn_amount(p_seed, n, 150, 450));
    if make_date(2026, m, 25) + 10 <= v_end then
      ev := ev || jsonb_build_object('d', make_date(2026, m, 25) + 10, 'o', 6, 'k', 'pay', 'ref', 'A' || m);
    end if;
    -- nóminas: el último día del mes, con el neto pagado ese día y la Seguridad Social el último del mes siguiente
    if p_profile <> 'trade' then
      d := (make_date(2026, m, 1) + interval '1 month - 1 day')::date;
      ev := ev || jsonb_build_object('d', d, 'o', 7, 'k', 'payroll', 'm', m);
      if m > 1 then ev := ev || jsonb_build_object('d', d, 'o', 8, 'k', 'pay_ss', 'm', m - 1); end if;
    end if;
    -- fin de trimestre: amortización y liquidación; el pago de los modelos, el 20 del mes siguiente
    if m % 3 = 0 then
      d := (make_date(2026, m, 1) + interval '1 month - 1 day')::date;
      ev := ev || jsonb_build_object('d', d, 'o', 9, 'k', 'quarter', 'q', m / 3);
      if m < p_months then ev := ev || jsonb_build_object('d', d + 20, 'o', 1, 'k', 'pay_taxes', 'q', m / 3); end if;
    end if;
  end loop;
  -- incidencias sembradas (perfil «incidencias»)
  if p_profile = 'incidents' then
    ev := ev || jsonb_build_object('d', '2026-02-10', 'o', 3, 'k', 'bad_sale', 'pid', v_moroso);   -- nunca se cobra
    ev := ev || jsonb_build_object('d', make_date(2026, 5, 18), 'o', 6, 'k', 'double_pay', 'pid', v_asset_vendor);  -- la máquina, otra vez
    ev := ev || jsonb_build_object('d', v_end, 'o', 10, 'k', 'bad_draft');                  -- un borrador descuadrado
  end if;

  -- 3. El plan se guarda en orden de fecha: las tandas lo ejecutan en ese orden (los mismos asientos con los mismos números)
  insert into erp.synthetic_plan (company_id, seq, d, k, ref, data)
  select e, row_number() over (order by (v->>'d')::date, (v->>'o')::int, v->>'k', v->>'ref'), (v->>'d')::date, v->>'k', v->>'ref', v
  from jsonb_array_elements(ev) v;
  update erp.companies set synthetic_seed = p_seed, synthetic_profile = p_profile, synthetic_months = p_months where id = e;
  return jsonb_build_object('company_id', e, 'seed', p_seed, 'profile', p_profile, 'months', p_months,
    'total', (select count(*) from erp.synthetic_plan where company_id = e));
end $$;

-- ---------- 2. Una tanda: las n operaciones siguientes del plan, con las funciones de cada módulo ----------
create or replace function erp.synthetic_step(p_company uuid, p_max int default 40)
returns jsonb language plpgsql set search_path = erp, public as $$
declare
  e uuid := p_company; co erp.companies; x erp.synthetic_plan; r record;
  v_tax text; v_gen text; v_sale_acc text; v_prof text;
  d date; v_id uuid; v_res uuid; v_inv uuid; v_loan uuid; v_last date; v_done int; v_total int;
begin
  if not erp.is_admin(e) then raise exception 'No permission: only the company admin can generate a synthetic company'; end if;
  -- una tanda a la vez por empresa (si hay dos pestañas, la segunda espera y sigue donde acabó la primera)
  select * into co from erp.companies where id = e for update;
  if co.synthetic_seed is null then raise exception 'This is not a synthetic company'; end if;
  v_prof := co.synthetic_profile;
  v_tax := case when v_prof in ('workshop', 'incidents') then 'IGIC' else 'VAT' end;
  v_gen := case when v_prof in ('workshop', 'incidents') then 'IGIC7' else 'VAT21' end;
  v_sale_acc := case v_prof when 'services' then '70500001' else '70000001' end;
  select id into v_loan from erp.loans where company_id = e order by created_at limit 1;

  for x in select * from erp.synthetic_plan p where p.company_id = e and not p.done order by p.seq limit greatest(coalesce(p_max, 40), 1) loop
    d := x.d; v_res := null;
    -- la factura a la que se refiere un cobro o un pago
    if x.k in ('collect', 'pay') then
      select p.result into v_inv from erp.synthetic_plan p
      where p.company_id = e and p.ref = x.ref and p.k in ('sale', 'purchase', 'rent', 'advisor');
    end if;
    case x.k
    when 'sale' then
      v_res := erp.case_invoice(e, 'sale', (x.data->>'pid')::uuid, d, null, 'Venta',
        jsonb_build_array(jsonb_build_object('account_no', v_sale_acc, 'amount', (x.data->>'amount')::numeric, 'tax_code', x.data->>'code')));
    when 'purchase' then
      v_res := erp.case_invoice(e, 'purchase', (x.data->>'pid')::uuid, d, x.ref,
        case when x.data->>'acc' = '60000001' then 'Compra de mercaderías' else 'Gasto del mes' end,
        jsonb_build_array(jsonb_build_object('account_no', x.data->>'acc', 'amount', (x.data->>'amount')::numeric, 'tax_code', x.data->>'code')));
    when 'rent' then
      v_res := erp.case_invoice(e, 'purchase', (x.data->>'pid')::uuid, d, x.ref, 'Alquiler del local',
        jsonb_build_array(jsonb_build_object('account_no', '62100001', 'amount', 1200, 'tax_code', v_gen)), 'IRPF19');
    when 'advisor' then
      v_res := erp.case_invoice(e, 'purchase', (x.data->>'pid')::uuid, d, x.ref, 'Asesoría del mes',
        jsonb_build_array(jsonb_build_object('account_no', '62300001', 'amount', (x.data->>'amount')::numeric, 'tax_code', v_gen)), 'IRPF15');
    when 'collect' then
      perform erp.case_payment(e, 'collection', (select partner_id from erp.invoices where id = v_inv), d, v_inv);
    when 'pay' then
      perform erp.case_payment(e, 'payment', (select partner_id from erp.invoices where id = v_inv), d, v_inv);
    when 'asset' then
      v_id := erp.case_invoice(e, 'purchase', (x.data->>'pid')::uuid, d, 'INV-1',
        case when v_prof = 'services' then 'Equipos informáticos' else 'Máquina para el taller' end,
        jsonb_build_array(jsonb_build_object('account_no', case when v_prof = 'services' then '21700001' else '21300001' end,
                                             'amount', (x.data->>'amount')::numeric, 'tax_code', v_gen)));
      perform erp.create_fixed_asset(jsonb_build_object('company_id', e,
        'name', case when v_prof = 'services' then 'Equipos informáticos' else 'Máquina para el taller' end,
        'asset_account_no', case when v_prof = 'services' then '21700001' else '21300001' end,
        'cost', (x.data->>'amount')::numeric, 'useful_life_months', case when v_prof = 'services' then 48 else 120 end,
        'start_date', d, 'acquisition_date', d, 'invoice_id', v_id));
      perform erp.case_payment(e, 'payment', (x.data->>'pid')::uuid, d, v_id);
      v_res := v_id;
    when 'loan' then
      perform erp.loan_create(jsonb_build_object('company_id', e, 'description', 'Préstamo para circulante', 'lender', 'Banco Ficticio',
        'principal', (x.data->>'amount')::numeric, 'rate', 5, 'periods', 36, 'frequency', 12, 'start_date', d,
        'bank_account_no', '57200001'));
      select id into v_loan from erp.loans where company_id = e order by created_at limit 1;
      v_res := v_loan;
    when 'loan_pay' then
      perform erp.loan_payment(jsonb_build_object('loan_id', v_loan, 'date', d, 'bank_account_no', '57200001'));
    when 'payroll' then
      select run_id into v_res from erp.run_payroll(jsonb_build_object('company_id', e, 'period', d));
      perform erp.pay_payroll(jsonb_build_object('run_id', v_res, 'what', 'net', 'payment_date', d, 'cash_account_no', '57200001'));
    when 'pay_ss' then
      perform erp.pay_payroll(jsonb_build_object('run_id',
        (select p.result from erp.synthetic_plan p where p.company_id = e and p.k = 'payroll' and p.data->>'m' = x.data->>'m'),
        'what', 'social_security', 'payment_date', d, 'cash_account_no', '57200001'));
    when 'quarter' then
      begin
        perform erp.post_depreciation(e, d);
      exception when others then if sqlerrm not like 'Nothing to depreciate%' then raise; end if;
      end;
      -- incidencias: el 2T se queda sin liquidar
      if not (v_prof = 'incidents' and (x.data->>'q')::int = 2) then
        perform erp.post_tax_settlement(e, v_tax, 2026, (x.data->>'q')::int);
      end if;
    when 'pay_taxes' then
      -- el resultado de la liquidación (4750) y las retenciones del trimestre (4751: modelo 111 y modelo 115), cada
      -- subcuenta con su pago
      for r in select g.account_no, erp.case_balance(e, g.account_no, d) as due from erp.gl_accounts g
               where g.company_id = e and g.account_type = 'posting' and (g.account_no like '4750%' or g.account_no like '4751%')
               order by g.account_no loop
        if r.due > 0 then
          perform erp.case_entry(e, d, case when r.account_no like '4750%' then 'Pago de la liquidación del '
                                            else 'Pago de las retenciones del ' end || (x.data->>'q') || 'T',
            jsonb_build_array(jsonb_build_array(r.account_no, r.due, 0), jsonb_build_array('57200001', 0, r.due)));
        end if;
      end loop;
    when 'bad_sale' then
      perform erp.case_invoice(e, 'sale', (x.data->>'pid')::uuid, d, null, 'Venta que no se cobra',
        jsonb_build_array(jsonb_build_object('account_no', v_sale_acc, 'amount', 2500, 'tax_code', v_gen)));
    when 'double_pay' then
      perform erp.case_entry(e, d, 'Pago duplicado a un proveedor',
        jsonb_build_array(jsonb_build_array((select account_no from erp.v_partners where id = (x.data->>'pid')::uuid), 1500, 0),
                          jsonb_build_array('57200001', 0, 1500)));
    when 'bad_draft' then
      insert into erp.journal_entries (company_id, fiscal_year_id, posting_date, description)
      values (e, (select id from erp.fiscal_years where company_id = e and year = 2026), d, 'Borrador descuadrado')
      returning id into v_id;
      insert into erp.journal_lines (entry_id, company_id, line_no, gl_account_id, debit, credit) values
        (v_id, e, 1, (select id from erp.gl_accounts where company_id = e and account_no = '62900001'), 100, 0),
        (v_id, e, 2, (select id from erp.gl_accounts where company_id = e and account_no = '57200001'), 0, 70);
    end case;
    update erp.synthetic_plan set done = true, result = v_res where company_id = e and seq = x.seq;
    v_last := d;
  end loop;

  select count(*) filter (where done)::int, count(*)::int into v_done, v_total from erp.synthetic_plan where company_id = e;
  return jsonb_build_object('company_id', e, 'done', v_done, 'total', v_total, 'left', v_total - v_done, 'date', v_last,
    'entries', (select count(*) from erp.journal_entries j where j.company_id = e),
    'fingerprint', case when v_done = v_total then erp.company_fingerprint(e) end);
end $$;

-- ---------- 3. Cómo va: cuántas operaciones van y cuántas faltan ----------
create or replace function erp.synthetic_progress(p_company uuid)
returns jsonb language plpgsql stable set search_path = erp, public as $$
declare v_done int; v_total int; v_next date;
begin
  if not erp.can_read(p_company) then raise exception 'Not allowed to read this company'; end if;
  select count(*) filter (where done)::int, count(*)::int, min(d) filter (where not done)
  into v_done, v_total, v_next from erp.synthetic_plan where company_id = p_company;
  return jsonb_build_object('done', v_done, 'total', v_total, 'left', v_total - v_done, 'next_date', v_next);
end $$;

-- ---------- 4. Todo seguido (SQL Editor y pruebas: allí no está el límite de la web) ----------
create or replace function erp.synthetic_run(p_company uuid)
returns jsonb language sql set search_path = erp, public as $$
  select erp.synthetic_step(p_company, 1000000);
$$;

-- ---------- 5. Crear: la empresa preparada y su plan; la web pide después las tandas ----------
create or replace function erp.create_synthetic_company(p_seed int, p_profile text, p_months int default 12)
returns jsonb language plpgsql set search_path = erp, public as $$
declare v_p record; v_name text; v_n int := 1; e uuid;
begin
  if auth.uid() is null then raise exception 'Sign in to create a synthetic company'; end if;
  if p_seed is null or p_seed not between 1 and 999999 then raise exception 'The seed must be a number from 1 to 999999'; end if;
  select * into v_p from erp.synthetic_profiles() s where s.profile = p_profile;
  if not found then raise exception 'Unknown synthetic profile: %', p_profile; end if;
  if p_months is null or p_months not between 1 and 12 then raise exception 'The months must be from 1 to 12'; end if;
  if p_months < v_p.min_months then
    raise exception 'The % profile needs at least % months', p_profile, v_p.min_months;
  end if;
  v_name := 'Sintética ' || p_seed || ' · ' || v_p.name || ' SL';
  while exists (select 1 from erp.companies c join erp.company_users u on u.company_id = c.id and u.user_id = auth.uid()
                where c.name = v_name) loop
    v_n := v_n + 1; v_name := 'Sintética ' || p_seed || ' · ' || v_p.name || ' SL (' || v_n || ')';
  end loop;
  insert into erp.companies (name, industry, tax_territory, legal_form, created_by, temporary)
  values (v_name, case p_profile when 'services' then 'services' else 'retail' end, v_p.territory, 'sl', auth.uid(),
          not erp.is_trusted())
  returning id into e;
  return erp.synthetic_prepare(e, p_seed, p_profile, p_months) || jsonb_build_object('name', v_name);
end $$;

-- ---------- La web: cuántas operaciones le faltan a cada sintética (0 = terminada) ----------
create or replace view erp.v_my_companies with (security_invoker = true) as
select c.id, c.name, c.vat_registration_no, c.industry, c.tax_territory,
       c.posting_account_digits, c.is_demo, c.created_at,
       erp.my_role(c.id) as my_role,
       c.vat_regime, c.data_credit, erp.is_data_owner(c.id) as is_data_owner, c.control_mode,
       c.case_key, c.case_mode, c.start_date, c.monthly,
       c.temporary, c.expires_at, c.last_seen_at,
       c.synthetic_seed, c.synthetic_profile, c.synthetic_months,
       (select count(*) from erp.synthetic_plan p where p.company_id = c.id and not p.done)::int as synthetic_left
from erp.companies c
where not (c.temporary and erp.temp_expired(c.expires_at, c.last_seen_at));

-- ---------- Permisos: sin sesión, nada (v0.58.0) ----------
revoke execute on function erp.synthetic_prepare(uuid, int, text, int), erp.synthetic_step(uuid, int),
  erp.synthetic_progress(uuid), erp.synthetic_run(uuid), erp.create_synthetic_company(int, text, int) from public, anon;
grant execute on function erp.synthetic_prepare(uuid, int, text, int), erp.synthetic_step(uuid, int),
  erp.synthetic_progress(uuid), erp.synthetic_run(uuid), erp.create_synthetic_company(int, text, int) to authenticated;
