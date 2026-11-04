-- =====================================================================
-- erp.synthetic_prepare · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0087_synthetic_batches   →   la vigente es la de 0087_synthetic_batches
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.synthetic_prepare(p_company uuid, p_seed integer, p_profile text, p_months integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'erp', 'public'
AS $function$
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
end $function$
;
