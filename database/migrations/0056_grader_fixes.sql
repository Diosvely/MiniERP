-- =====================================================================
-- 0056 · CORRECTOR DE SUPUESTOS: SOLO CUENTAS VÁLIDAS DEL PGC · v0.40.1
-- ---------------------------------------------------------------------
-- Arreglo de la revisión externa del 19-10-2026. erp.grade_exercise (0054) aceptaba cualquier cuenta que EMPEZARA por
-- la esperada: daba por buena la 4009 («Proveedores, facturas pendientes de recibir o de formalizar») en lugar de la
-- 400, y cuentas que no existen (600xyz, 400ABC). Ahora:
--   1. Formato: una cuenta solo vale si son dígitos.                                  → si no, «extra» · invalid
--   2. Existencia (erp.pgc_account_problem): hasta 3 dígitos, tiene que ser una cuenta del PGC (grupo, subgrupo o
--      cuenta); con 4 o más, su cuenta de 3 dígitos tiene que estar en el PGC.        → si no, «extra» · not_in_pgc
--      (Así vale la 4000 «Proveedores (euros)» y cualquier subcuenta, como 40000001 o 47200021.)
--   3. Cuentas de 4 dígitos con OTRO significado que su madre (erp.pgc_distinct_accounts: 4009, 4109, 4309, 4409,
--      las de facturas pendientes de recibir o de formalizar): una respuesta suya no casa con la madre
--      (erp.account_matches), y se explica la diferencia en las pistas.
--   4. Las esperadas de grupo (6 y 7 en la regularización) siguen casando por su primer dígito.
-- Lo usan la corrección de la persona y la de la IA (erp.submit_exercise llama a erp.grade_exercise).
-- No se tocan erp.coa_template ni las cuentas de las empresas: añadir allí la 4009 cambiaría la cuenta madre de las
-- subcuentas nuevas 4009xxxx (template_account) y los informes por niveles. Fuente: RD 1514/2007, cuadro de cuentas.
-- Pruebas: test_fase51_grader_fixes.sql (falla con la 0055, pasa con esta). Re-ejecutable.
-- =====================================================================

-- 1) Cuentas de 4 dígitos del PGC con un significado distinto del de su cuenta de 3 dígitos
create table if not exists erp.pgc_distinct_accounts (
  account_no text primary key check (account_no ~ '^[0-9]{4}$'),
  name       text not null,
  name_en    text not null,
  tip        text not null,
  tip_en     text not null
);
comment on table erp.pgc_distinct_accounts is 'PGC 4-digit accounts whose meaning differs from their 3-digit parent (4009 is not 400): the exercise grader does not accept them for the parent.';
insert into erp.pgc_distinct_accounts (account_no, name, name_en, tip, tip_en) values
('4009', 'Proveedores, facturas pendientes de recibir o de formalizar', 'Suppliers, invoices pending receipt or formalisation',
 'La 4009 es para facturas pendientes de recibir o de formalizar (una compra devengada sin factura al cierre). Si la factura ya está recibida, va a la 400.',
 '4009 is for invoices pending receipt or formalisation (a purchase accrued without an invoice at year end). If the invoice has been received, it goes to 400.'),
('4109', 'Acreedores por prestaciones de servicios, facturas pendientes de recibir o de formalizar', 'Service creditors, invoices pending receipt or formalisation',
 'La 4109 es para servicios devengados cuya factura aún no ha llegado. Si la factura ya está recibida, va a la 410.',
 '4109 is for services accrued whose invoice has not arrived yet. If the invoice has been received, it goes to 410.'),
('4309', 'Clientes, facturas pendientes de formalizar', 'Customers, invoices pending formalisation',
 'La 4309 es para ventas devengadas que aún no se han facturado. Si la factura ya está emitida, va a la 430.',
 '4309 is for sales accrued but not yet invoiced. If the invoice has been issued, it goes to 430.'),
('4409', 'Deudores, facturas pendientes de formalizar', 'Debtors, invoices pending formalisation',
 'La 4409 es para ingresos devengados de deudores aún sin factura. Si la factura ya está emitida, va a la 440.',
 '4409 is for income accrued from debtors without an invoice yet. If the invoice has been issued, it goes to 440.')
on conflict (account_no) do update set name = excluded.name, name_en = excluded.name_en, tip = excluded.tip, tip_en = excluded.tip_en;
alter table erp.pgc_distinct_accounts enable row level security;
drop policy if exists read on erp.pgc_distinct_accounts;
create policy read on erp.pgc_distinct_accounts for select to authenticated using (true);
revoke all on erp.pgc_distinct_accounts from anon, public;
grant select on erp.pgc_distinct_accounts to authenticated;

-- 2) ¿Es una cuenta del PGC? null = sí · 'invalid' = no son dígitos · 'not_in_pgc' = no existe en el PGC
create or replace function erp.pgc_account_problem(p_account text)
returns text language sql stable as $$
  select case
    when coalesce(btrim(p_account), '') !~ '^[0-9]+$' then 'invalid'
    when length(btrim(p_account)) <= 3
         and not exists (select 1 from erp.coa_template t where t.account_no = btrim(p_account)) then 'not_in_pgc'
    when length(btrim(p_account)) > 3
         and not exists (select 1 from erp.coa_template t where t.account_no = left(btrim(p_account), 3)) then 'not_in_pgc'
  end;
$$;

-- 3) ¿La cuenta de la respuesta es la esperada (o una subcuenta suya)? La 40000001 sí es la 400; la 4009, no.
create or replace function erp.account_matches(p_answer text, p_expected text)
returns boolean language sql stable as $$
  select p_answer like p_expected || '%'
     and not exists (select 1 from erp.pgc_distinct_accounts d
                     where d.account_no like p_expected || '_%' and p_answer like d.account_no || '%');
$$;

-- 4) Corregir una respuesta (versión de la 0054 con las cuentas válidas del PGC: marcado «v0.40.1»)
create or replace function erp.grade_exercise(p_key text, p_answer jsonb)
returns jsonb language plpgsql stable as $$
declare
  x erp.exercises; a jsonb; e jsonb; v_lines jsonb := '[]'; v_ok int := 0; v_n int := 0; v_match numeric; v_other numeric;
  v_used int[] := '{}'; v_extra jsonb := '[]'; v_tips jsonb := '[]'; v_status text; v_debit numeric; v_credit numeric; i int;
  v_alts text[]; v_hits int[]; v_bad jsonb := '[]';
begin
  select * into x from erp.exercises where key = p_key;
  if not found then raise exception 'Exercise % not found', p_key; end if;
  -- la respuesta, normalizada: [{ i, account, side, amount }]
  select coalesce(jsonb_agg(jsonb_build_object('i', o.ord, 'account', btrim(o.v->>'account_no'),
           'problem', erp.pgc_account_problem(btrim(o.v->>'account_no')),
           'side', case when coalesce((o.v->>'debit')::numeric, 0) <> 0 then 'debit' else 'credit' end,
           'amount', abs(coalesce(nullif((o.v->>'debit')::numeric, 0), (o.v->>'credit')::numeric, 0))) order by o.ord), '[]'),
         coalesce(sum(coalesce((o.v->>'debit')::numeric, 0)), 0), coalesce(sum(coalesce((o.v->>'credit')::numeric, 0)), 0)
    into a, v_debit, v_credit
  from jsonb_array_elements(p_answer) with ordinality o(v, ord)
  where coalesce(btrim(o.v->>'account_no'), '') <> '' and (coalesce((o.v->>'debit')::numeric, 0) <> 0 or coalesce((o.v->>'credit')::numeric, 0) <> 0);

  -- v0.40.1 · las cuentas que no son cuentas del PGC (letras, 9999…) no casan con nada: van a «extra» con su motivo
  select coalesce(jsonb_agg(l - 'i' - 'problem' || jsonb_build_object('reason', l->>'problem') order by (l->>'i')::int), '[]') into v_bad
  from jsonb_array_elements(a) l where l->>'problem' is not null;
  select coalesce(jsonb_agg(l), '[]') into a from jsonb_array_elements(a) l where l->>'problem' is null;

  for e in select * from jsonb_array_elements(x.expected) loop
    v_n := v_n + 1;
    v_alts := array[e->>'account'] || coalesce((select array_agg(z) from jsonb_array_elements_text(e->'alt') z), '{}');
    -- líneas de la respuesta de ese grupo y ese lado (que no haya usado otra línea esperada)
    select coalesce(sum((l->>'amount')::numeric), 0), coalesce(array_agg((l->>'i')::int), '{}') into v_match, v_hits
    from jsonb_array_elements(a) l
    where l->>'side' = e->>'side' and exists (select 1 from unnest(v_alts) p where erp.account_matches(l->>'account', p))
      and not ((l->>'i')::int = any (v_used));
    select coalesce(sum((l->>'amount')::numeric), 0) into v_other
    from jsonb_array_elements(a) l
    where l->>'side' <> e->>'side' and exists (select 1 from unnest(v_alts) p where erp.account_matches(l->>'account', p));
    v_status := case when cardinality(v_hits) > 0 and abs(v_match - (e->>'amount')::numeric) < 0.005 then 'ok'
                     when cardinality(v_hits) > 0 then 'amount'
                     when v_other <> 0 then 'side'
                     else 'missing' end;
    if v_status = 'ok' then v_ok := v_ok + 1; end if;
    v_used := v_used || v_hits;
    v_lines := v_lines || jsonb_build_object('account', e->>'account', 'side', e->>'side', 'expected', (e->>'amount')::numeric,
                                             'answered', case when cardinality(v_hits) > 0 then v_match end, 'status', v_status,
                                             'alt_used', cardinality(v_hits) > 0 and not exists (
                                               select 1 from jsonb_array_elements(a) l where (l->>'i')::int = any (v_hits) and erp.account_matches(l->>'account', e->>'account')));
  end loop;
  select coalesce(jsonb_agg(l - 'i' - 'problem'), '[]') || v_bad into v_extra from jsonb_array_elements(a) l where not ((l->>'i')::int = any (v_used));
  -- errores frecuentes reconocidos
  select coalesce(jsonb_agg(jsonb_build_object('msg', r->>'msg', 'msg_en', r->>'msg_en')), '[]') into v_tips
  from jsonb_array_elements(x.errors) r
  where exists (select 1 from jsonb_array_elements(a) l where l->>'side' = r->>'side' and l->>'account' like (r->>'account') || '%');
  -- v0.40.1 · una cuenta de 4 dígitos con otro significado (4009 en lugar de 400): se explica la diferencia
  v_tips := v_tips || coalesce((
    select jsonb_agg(distinct jsonb_build_object('msg', d.tip, 'msg_en', d.tip_en))
    from jsonb_array_elements(a) l
    join erp.pgc_distinct_accounts d on l->>'account' like d.account_no || '%'
    where exists (select 1 from jsonb_array_elements(x.expected) ex
                  where d.account_no like (ex->>'account') || '_%')), '[]');
  return jsonb_build_object('exercise', x.key, 'lines', v_lines, 'extra', v_extra, 'tips', v_tips,
    'balanced', abs(v_debit - v_credit) < 0.005, 'debit', v_debit, 'credit', v_credit,
    'score', case when v_n = 0 then 0 else round(100.0 * v_ok / v_n)::int end,
    'ok', v_ok = v_n and jsonb_array_length(v_extra) = 0 and abs(v_debit - v_credit) < 0.005);
end $$;

revoke execute on function erp.pgc_account_problem(text), erp.account_matches(text, text), erp.grade_exercise(text, jsonb) from anon, public;
grant execute on function erp.pgc_account_problem(text), erp.account_matches(text, text), erp.grade_exercise(text, jsonb) to authenticated;
