-- =====================================================================
-- 0029 · RENDIMIENTO CON MUCHOS DATOS (v0.29.0)
-- ---------------------------------------------------------------------
-- Con una empresa importada de varios años (decenas de miles de apuntes) aparecieron dos problemas:
--
--   1) El LIBRO MAYOR no cargaba nunca ("canceling statement due to statement timeout").
--      La vista v_general_ledger (0005) calcula el saldo acumulado con una función de ventana sobre TODOS
--      los apuntes visibles y solo después filtra por cuenta y año: el filtro no se puede aplicar antes
--      de la ventana. Supabase corta las consultas de la web a los ~8 segundos.
--      → erp.general_ledger(empresa, año, cuenta, hasta): primero FILTRA (índice por cuenta) y después
--        calcula el saldo. Como el "Movimientos de contabilidad" filtrado por cuenta de Business Central
--        o la transacción FBL3N de SAP: nunca se recorre el libro entero para ver una cuenta.
--
--   2) BORRAR UNA EMPRESA grande tardaba minutos. Al borrar cada asiento, PostgreSQL comprueba las claves
--      foráneas que apuntan a él (anulaciones, facturas, liquidaciones, cierres…). Esas columnas no tenían
--      índice: cada comprobación recorría la tabla entera (60.000 asientos × 60.000 filas).
--      → Índices en todas las claves foráneas que no los tenían (es lo que recomienda el "Performance
--        Advisor" de Supabase: "unindexed foreign keys").
--
--      Aun con índices, borrar 60.000 asientos de una vez tarda unos 4-5 s (9 comprobaciones por asiento),
--      demasiado cerca del límite de 8 s de la web, y el límite no se puede subir desde una función.
--      → erp.delete_company_step(empresa): borra la empresa POR TANDAS de 5.000 asientos y devuelve cuántos
--        quedan; la web lo llama en bucle con una barra de progreso, igual que la importación mes a mes.
--        Con 0 asientos borra la empresa (y en cascada todo lo demás). Como en Business Central, borrar una
--        empresa es un proceso aparte, no una consulta más.
--      erp.delete_company (0004) se mantiene para empresas pequeñas (pruebas y deshacer una importación).
--
-- La vista v_general_ledger se mantiene (las pruebas y consultas manuales en el SQL Editor la usan);
-- la web pasa a usar la función.
-- Re-ejecutable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) LIBRO MAYOR de una subcuenta en un ejercicio (opcionalmente hasta una fecha)
--    security invoker: RLS sigue decidiendo qué puede ver cada usuario (también el invitado en la demo).
--    running_balance > 0 = saldo deudor · < 0 = saldo acreedor
-- ---------------------------------------------------------------------
create or replace function erp.general_ledger(
  p_company uuid, p_year int, p_account text, p_to_date date default null)
returns table (posting_date date, entry_no int, document_no text, description text,
               debit numeric, credit numeric, running_balance numeric)
language sql stable as $$
  select e.posting_date,
         e.entry_no,
         e.document_no,
         coalesce(l.description, e.description),
         l.debit,
         l.credit,
         sum(l.debit - l.credit) over (order by e.posting_date, e.entry_no, l.line_no
                                       rows between unbounded preceding and current row)
  from erp.journal_lines   l
  join erp.journal_entries e on e.id = l.entry_id
  where l.gl_account_id = (select a.id from erp.gl_accounts a
                           where a.company_id = p_company and a.account_no = p_account)
    and e.fiscal_year_id = (select fy.id from erp.fiscal_years fy
                            where fy.company_id = p_company and fy.year = p_year)
    and e.status = 'posted'
    and (p_to_date is null or e.posting_date <= p_to_date)
  order by e.posting_date, e.entry_no, l.line_no;
$$;

revoke execute on function erp.general_ledger(uuid, int, text, date) from public;
grant execute on function erp.general_ledger(uuid, int, text, date) to authenticated;

-- ---------------------------------------------------------------------
-- 2) ÍNDICES EN LAS CLAVES FORÁNEAS QUE NO LOS TENÍAN
-- ---------------------------------------------------------------------
-- Asientos: anulaciones y documentos que apuntan a un asiento
create index if not exists journal_entries_reversal_of  on erp.journal_entries (reversal_of)  where reversal_of is not null;
create index if not exists journal_entries_reversed_by  on erp.journal_entries (reversed_by)  where reversed_by is not null;
create index if not exists invoices_entry               on erp.invoices (entry_id);
create index if not exists tax_settlements_entry        on erp.tax_settlements (entry_id);
create index if not exists pro_rata_entry               on erp.pro_rata (entry_id);
create index if not exists year_closings_closing_pl     on erp.year_closings (closing_pl_entry_id);
create index if not exists year_closings_closing        on erp.year_closings (closing_entry_id);
create index if not exists year_closings_opening        on erp.year_closings (opening_entry_id);

-- Apuntes y líneas de factura
create index if not exists journal_lines_company        on erp.journal_lines (company_id);
create index if not exists journal_lines_partner        on erp.journal_lines (partner_id) where partner_id is not null;
create index if not exists invoice_lines_company        on erp.invoice_lines (company_id);
create index if not exists invoice_lines_account        on erp.invoice_lines (gl_account_id);
create index if not exists invoice_tax_lines_company    on erp.invoice_tax_lines (company_id);

-- Facturas
create index if not exists invoices_partner             on erp.invoices (partner_id);
create index if not exists invoices_fiscal_year         on erp.invoices (fiscal_year_id);
create index if not exists invoices_corrected           on erp.invoices (corrected_invoice_id) where corrected_invoice_id is not null;

-- Configuración de impuestos y retenciones (tablas pequeñas: el índice es por coherencia)
create index if not exists tax_setup_input              on erp.tax_setup (input_account_id);
create index if not exists tax_setup_output             on erp.tax_setup (output_account_id);
create index if not exists tax_setup_surcharge          on erp.tax_setup (surcharge_account_id);
create index if not exists tax_settlement_setup_pay     on erp.tax_settlement_setup (payable_account_id);
create index if not exists tax_settlement_setup_rec     on erp.tax_settlement_setup (receivable_account_id);
create index if not exists withholding_setup_pay        on erp.withholding_setup (payable_account_id);
create index if not exists withholding_setup_rec        on erp.withholding_setup (receivable_account_id);

-- Resto de tablas por empresa
create index if not exists year_closings_company        on erp.year_closings (company_id);
create index if not exists import_batches_company       on erp.import_batches (company_id);
create index if not exists import_lines_company         on erp.import_lines (company_id);
create index if not exists ai_feedback_company          on erp.ai_feedback (company_id);

-- ---------------------------------------------------------------------
-- 3) BORRAR UNA EMPRESA POR TANDAS (solo su admin)
--    Devuelve los asientos que quedan: la web repite la llamada hasta que devuelve 0 (empresa borrada).
--    Orden: primero lo que apunta a los asientos (cierres, prorratas, liquidaciones, facturas), después
--    los apuntes y asientos de la tanda y, al final, la empresa (el resto se borra en cascada).
--    Un asiento y su contraasiento se apuntan entre sí: van siempre en la misma tanda.
-- ---------------------------------------------------------------------
create or replace function erp.delete_company_step(p_company uuid, p_batch int default 5000)
returns integer language plpgsql security definer set search_path = erp, public as $$
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
end $$;

revoke execute on function erp.delete_company_step(uuid, int) from anon, public;
grant execute on function erp.delete_company_step(uuid, int) to authenticated;
