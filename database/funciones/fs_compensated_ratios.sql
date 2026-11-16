-- =====================================================================
-- erp.fs_compensated_ratios · versión vigente (GENERADO por scripts/volcar-funciones.sh: no editar)
-- Definida en: 0096_compensated_balance_and_audits   →   la vigente es la de 0096_compensated_balance_and_audits
-- =====================================================================

CREATE OR REPLACE FUNCTION erp.fs_compensated_ratios(p_company uuid, p_year integer, p_to_date date DEFAULT NULL::date, p_drafts boolean DEFAULT false, p_model text DEFAULT 'pymes'::text)
 RETURNS TABLE(code text, amount numeric, amount_comp numeric)
 LANGUAGE sql
 STABLE
 SET jit TO 'off'
AS $function$
  with b as (select * from erp.fs_compensated(p_company, p_year, p_to_date, p_drafts, p_model)),
  v as (
    select
      sum(b.amount)      filter (where b.code = 'AC')  as ac,  sum(b.amount_comp) filter (where b.code = 'AC')  as ac_c,
      sum(b.amount)      filter (where b.code = 'PC')  as pc,  sum(b.amount_comp) filter (where b.code = 'PC')  as pc_c,
      sum(b.amount)      filter (where b.code = 'PNC') as pnc, sum(b.amount_comp) filter (where b.code = 'PNC') as pnc_c,
      sum(b.amount)      filter (where b.code = 'ACT') as act, sum(b.amount_comp) filter (where b.code = 'ACT') as act_c,
      sum(b.amount)      filter (where b.code = case when p_model = 'pymes' then 'AC.I' else 'AC.II' end) as inv,
      sum(b.amount_comp) filter (where b.code = case when p_model = 'pymes' then 'AC.I' else 'AC.II' end) as inv_c,
      sum(b.amount)      filter (where b.code = case when p_model = 'pymes' then 'AC.VI' else 'AC.VII' end) as cash,
      sum(b.amount_comp) filter (where b.code = case when p_model = 'pymes' then 'AC.VI' else 'AC.VII' end) as cash_c
    from b)
  select x.code, x.a, x.c from v cross join lateral (values
    ('LIQ',    round(v.ac / nullif(v.pc, 0), 4),               round(v.ac_c / nullif(v.pc_c, 0), 4)),
    ('QR',     round((v.ac - v.inv) / nullif(v.pc, 0), 4),     round((v.ac_c - v.inv_c) / nullif(v.pc_c, 0), 4)),
    ('CASH',   round(v.cash / nullif(v.pc, 0), 4),             round(v.cash_c / nullif(v.pc_c, 0), 4)),
    ('DEBT',   round((v.pnc + v.pc) / nullif(v.act, 0), 4),    round((v.pnc_c + v.pc_c) / nullif(v.act_c, 0), 4)),
    ('WC',     v.ac - v.pc,                                     v.ac_c - v.pc_c),
    ('HIDDEN', v.act - v.act_c,                                 0::numeric)) x(code, a, c);
$function$
;
