# Funciones del esquema erp (versión vigente)

Generado por `scripts/volcar-funciones.sh` con las migraciones `0001` … `0070`.
No se edita a mano: el código fuente son las migraciones. Esto es para **estudiar** cada función en su forma
actual sin rastrear sus redefiniciones.

- **Versiones:** en cuántas migraciones se ha definido. Más de una = la regla ha cambiado; la historia está en
  los ADR y en el CHANGELOG.
- **Tipo:** *invoker* (se ejecuta con los permisos de quien llama: manda la RLS), *security definer* (con los del
  dueño: comprueba ella misma los permisos) o *trigger*.

316 funciones.

| Función | Versiones | Vigente en | Tipo |
|---|---|---|---|
| [`account_balance_in_year`](account_balance_in_year.sql) | 1 | 0047_inventory_closing | invoker |
| [`account_matches`](account_matches.sql) | 1 | 0056_grader_fixes | invoker |
| [`accrual_elapsed`](accrual_elapsed.sql) | 1 | 0043_year_end_adjustments | invoker |
| [`adjust_account`](adjust_account.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`adjust_finish`](adjust_finish.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`adjust_fiscal_year`](adjust_fiscal_year.sql) | 1 | 0043_year_end_adjustments | invoker |
| [`adjust_post`](adjust_post.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`adjust_reverse`](adjust_reverse.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`aging`](aging.sql) | 1 | 0035_payments | invoker |
| [`ai_allowed`](ai_allowed.sql) | 1 | 0027_members | security definer |
| [`ai_consume`](ai_consume.sql) | 1 | 0027_members | security definer |
| [`ai_context`](ai_context.sql) | 2 | 0027_members | security definer |
| [`ai_ratio_value`](ai_ratio_value.sql) | 1 | 0024_ai_context | invoker |
| [`ai_status`](ai_status.sql) | 1 | 0027_members | security definer |
| [`apply_provision`](apply_provision.sql) | 1 | 0045_provisions | security definer |
| [`asset_account_pair`](asset_account_pair.sql) | 1 | 0041_fixed_assets | security definer |
| [`asset_accumulated_at`](asset_accumulated_at.sql) | 1 | 0041_fixed_assets | invoker |
| [`asset_cost_at`](asset_cost_at.sql) | 1 | 0046_asset_impairment | invoker |
| [`asset_depr_at`](asset_depr_at.sql) | 1 | 0046_asset_impairment | invoker |
| [`asset_event_check`](asset_event_check.sql) | 1 | 0046_asset_impairment | invoker |
| [`asset_impairment_account`](asset_impairment_account.sql) | 1 | 0046_asset_impairment | security definer |
| [`asset_impairment_at`](asset_impairment_at.sql) | 1 | 0046_asset_impairment | invoker |
| [`asset_months_at`](asset_months_at.sql) | 1 | 0046_asset_impairment | invoker |
| [`asset_net_value_at`](asset_net_value_at.sql) | 1 | 0046_asset_impairment | invoker |
| [`asset_posted`](asset_posted.sql) | 1 | 0041_fixed_assets | invoker |
| [`asset_result_account`](asset_result_account.sql) | 1 | 0041_fixed_assets | security definer |
| [`asset_tranche_at`](asset_tranche_at.sql) | 1 | 0046_asset_impairment | invoker |
| [`audit_lines`](audit_lines.sql) | 11 | 0064_grants | invoker |
| [`balance_anomalies`](balance_anomalies.sql) | 1 | 0013_balance_rules | invoker |
| [`balance_nature`](balance_nature.sql) | 1 | 0013_balance_rules | invoker |
| [`can_read`](can_read.sql) | 2 | 0007_demo_and_limits | security definer |
| [`can_use_ai`](can_use_ai.sql) | 1 | 0024_ai_context | invoker |
| [`can_write`](can_write.sql) | 3 | 0015_guest_access | invoker |
| [`cancel_accrual`](cancel_accrual.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`cancel_asset_impairment`](cancel_asset_impairment.sql) | 1 | 0046_asset_impairment | security definer |
| [`cancel_depreciation`](cancel_depreciation.sql) | 1 | 0041_fixed_assets | security definer |
| [`cancel_disposal`](cancel_disposal.sql) | 2 | 0065_grants_integration | security definer |
| [`cancel_impairment`](cancel_impairment.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`cancel_inventory`](cancel_inventory.sql) | 1 | 0047_inventory_closing | security definer |
| [`cancel_payment`](cancel_payment.sql) | 1 | 0035_payments | security definer |
| [`cancel_payroll`](cancel_payroll.sql) | 1 | 0049_payroll | security definer |
| [`cancel_pro_rata_regularization`](cancel_pro_rata_regularization.sql) | 1 | 0020_pro_rata | invoker |
| [`cancel_provision_movement`](cancel_provision_movement.sql) | 1 | 0045_provisions | security definer |
| [`cancel_tax_settlement`](cancel_tax_settlement.sql) | 1 | 0012_tax_settlement | invoker |
| [`cancel_write_off`](cancel_write_off.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`case_balance`](case_balance.sql) | 1 | 0066_complete_case | invoker |
| [`case_compare`](case_compare.sql) | 3 | 0068_case_labels | invoker |
| [`case_entry`](case_entry.sql) | 1 | 0066_complete_case | invoker |
| [`case_invoice`](case_invoice.sql) | 1 | 0066_complete_case | invoker |
| [`case_mark`](case_mark.sql) | 1 | 0067_case_screen | security definer |
| [`case_payment`](case_payment.sql) | 1 | 0066_complete_case | invoker |
| [`case_progress`](case_progress.sql) | 1 | 0067_case_screen | invoker |
| [`cash_flow_check`](cash_flow_check.sql) | 2 | 0066_complete_case | security definer |
| [`cash_flow_statement`](cash_flow_statement.sql) | 1 | 0022_cash_flow | security definer |
| [`cf_account_flows`](cf_account_flows.sql) | 2 | 0066_complete_case | security definer |
| [`cf_account_map`](cf_account_map.sql) | 1 | 0022_cash_flow | invoker |
| [`cf_cash`](cf_cash.sql) | 1 | 0022_cash_flow | security definer |
| [`cf_detail`](cf_detail.sql) | 1 | 0022_cash_flow | security definer |
| [`cf_direct_detail`](cf_direct_detail.sql) | 2 | 0066_complete_case | security definer |
| [`cf_entry_cash`](cf_entry_cash.sql) | 1 | 0022_cash_flow | security definer |
| [`cf_indirect_detail`](cf_indirect_detail.sql) | 1 | 0022_cash_flow | security definer |
| [`cf_line_accounts`](cf_line_accounts.sql) | 1 | 0022_cash_flow | security definer |
| [`cf_line_flows`](cf_line_flows.sql) | 1 | 0066_complete_case | security definer |
| [`check_payment_applications`](check_payment_applications.sql) | 1 | 0035_payments | invoker |
| [`check_tax_account`](check_tax_account.sql) | 1 | 0010_tax_setup | invoker |
| [`cleanup_guests`](cleanup_guests.sql) | 2 | 0034_web_usage | security definer |
| [`close_fiscal_year`](close_fiscal_year.sql) | 2 | 0065_grants_integration | invoker |
| [`close_month`](close_month.sql) | 1 | 0069_monthly_accounting | security definer |
| [`closing_checklist`](closing_checklist.sql) | 5 | 0065_grants_integration | invoker |
| [`company_access`](company_access.sql) | 1 | 0027_members | security definer |
| [`concepts_for_account`](concepts_for_account.sql) | 1 | 0038_concepts | invoker |
| [`control_rule_for`](control_rule_for.sql) | 1 | 0036_controlled_accounts | invoker |
| [`controlled_lines`](controlled_lines.sql) | 1 | 0036_controlled_accounts | invoker |
| [`corporate_tax_calc`](corporate_tax_calc.sql) | 2 | 0061_equity_integration | invoker |
| [`corporate_tax_cancel`](corporate_tax_cancel.sql) | 1 | 0058_corporate_tax_posting | security definer |
| [`corporate_tax_draft`](corporate_tax_draft.sql) | 1 | 0057_corporate_tax | security definer |
| [`corporate_tax_entry`](corporate_tax_entry.sql) | 1 | 0058_corporate_tax_posting | security definer |
| [`corporate_tax_include`](corporate_tax_include.sql) | 1 | 0057_corporate_tax | security definer |
| [`corporate_tax_loss_carryforwards`](corporate_tax_loss_carryforwards.sql) | 1 | 0057_corporate_tax | invoker |
| [`corporate_tax_manual`](corporate_tax_manual.sql) | 1 | 0057_corporate_tax | security definer |
| [`corporate_tax_pending`](corporate_tax_pending.sql) | 1 | 0057_corporate_tax | invoker |
| [`corporate_tax_post`](corporate_tax_post.sql) | 2 | 0061_equity_integration | security definer |
| [`corporate_tax_prepare`](corporate_tax_prepare.sql) | 1 | 0057_corporate_tax | security definer |
| [`corporate_tax_proposals`](corporate_tax_proposals.sql) | 3 | 0061_equity_integration | invoker |
| [`corporate_tax_quota`](corporate_tax_quota.sql) | 1 | 0057_corporate_tax | invoker |
| [`corporate_tax_regime_hint`](corporate_tax_regime_hint.sql) | 1 | 0057_corporate_tax | invoker |
| [`corporate_tax_settings`](corporate_tax_settings.sql) | 1 | 0057_corporate_tax | security definer |
| [`create_accrual`](create_accrual.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`create_case_company`](create_case_company.sql) | 1 | 0067_case_screen | invoker |
| [`create_fiscal_year`](create_fiscal_year.sql) | 1 | 0001_core | invoker |
| [`create_fixed_asset`](create_fixed_asset.sql) | 1 | 0041_fixed_assets | security definer |
| [`create_partner`](create_partner.sql) | 1 | 0009_partners | invoker |
| [`create_posting_account`](create_posting_account.sql) | 1 | 0002_chart_of_accounts | invoker |
| [`create_provision`](create_provision.sql) | 1 | 0045_provisions | security definer |
| [`delete_company`](delete_company.sql) | 1 | 0004_journal_entries | security definer |
| [`delete_company_step`](delete_company_step.sql) | 11 | 0064_grants | security definer |
| [`delete_draft`](delete_draft.sql) | 1 | 0070_entries_screen | security definer |
| [`depreciation_schedule`](depreciation_schedule.sql) | 2 | 0046_asset_impairment | invoker |
| [`dispose_asset`](dispose_asset.sql) | 3 | 0065_grants_integration | security definer |
| [`draft_problem`](draft_problem.sql) | 1 | 0070_entries_screen | security definer |
| [`ensure_tax_account`](ensure_tax_account.sql) | 1 | 0010_tax_setup | invoker |
| [`entries_list`](entries_list.sql) | 1 | 0070_entries_screen | security definer |
| [`entry_controlled_lines`](entry_controlled_lines.sql) | 1 | 0036_controlled_accounts | invoker |
| [`entry_is_manual`](entry_is_manual.sql) | 11 | 0064_grants | security definer |
| [`entry_source`](entry_source.sql) | 1 | 0070_entries_screen | security definer |
| [`entry_tutor_context`](entry_tutor_context.sql) | 3 | 0033_withholding_rules | security definer |
| [`equity_bal`](equity_bal.sql) | 2 | 0061_equity_integration | invoker |
| [`equity_bank`](equity_bank.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_call`](equity_call.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_cancel`](equity_cancel.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_capital_increase`](equity_capital_increase.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_capital_reduction`](equity_capital_reduction.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_distribution`](equity_distribution.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_distribution_preview`](equity_distribution_preview.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_dividend_payment`](equity_dividend_payment.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_entry`](equity_entry.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_incorporation`](equity_incorporation.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_interim_dividend`](equity_interim_dividend.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_interim_preview`](equity_interim_preview.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_legal_reserve`](equity_legal_reserve.sql) | 1 | 0060_equity_operations | invoker |
| [`equity_line`](equity_line.sql) | 1 | 0060_equity_operations | invoker |
| [`equity_loss_offset`](equity_loss_offset.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_net_worth`](equity_net_worth.sql) | 1 | 0060_equity_operations | invoker |
| [`equity_reserves_to_capital`](equity_reserves_to_capital.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_save`](equity_save.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_start`](equity_start.sql) | 1 | 0060_equity_operations | security definer |
| [`equity_statement`](equity_statement.sql) | 1 | 0065_grants_integration | security definer |
| [`equity_statement_column`](equity_statement_column.sql) | 1 | 0065_grants_integration | invoker |
| [`equity_statement_lines`](equity_statement_lines.sql) | 1 | 0065_grants_integration | security definer |
| [`equity_status`](equity_status.sql) | 1 | 0060_equity_operations | security definer |
| [`financial_ratios`](financial_ratios.sql) | 1 | 0023_financial_ratios | security definer |
| [`financial_statement`](financial_statement.sql) | 2 | 0032_comparative_statements | invoker |
| [`fiscal_year_company`](fiscal_year_company.sql) | 1 | 0006_security_rls | security definer |
| [`form_347`](form_347.sql) | 1 | 0052_forms_347_349 | invoker |
| [`form_349`](form_349.sql) | 1 | 0052_forms_347_349 | invoker |
| [`form_349_period`](form_349_period.sql) | 1 | 0052_forms_347_349 | invoker |
| [`fs_amounts`](fs_amounts.sql) | 1 | 0016_financial_statements | invoker |
| [`fs_classified_accounts`](fs_classified_accounts.sql) | 2 | 0017_year_closing | invoker |
| [`fs_line_accounts`](fs_line_accounts.sql) | 1 | 0016_financial_statements | invoker |
| [`general_ledger`](general_ledger.sql) | 1 | 0029_performance | invoker |
| [`global_impairment_calc`](global_impairment_calc.sql) | 1 | 0043_year_end_adjustments | invoker |
| [`grade_exercise`](grade_exercise.sql) | 2 | 0056_grader_fixes | invoker |
| [`grant_cancel`](grant_cancel.sql) | 1 | 0064_grants | security definer |
| [`grant_check`](grant_check.sql) | 1 | 0064_grants | security definer |
| [`grant_collect`](grant_collect.sql) | 1 | 0064_grants | security definer |
| [`grant_company_access`](grant_company_access.sql) | 1 | 0027_members | security definer |
| [`grant_create`](grant_create.sql) | 1 | 0064_grants | security definer |
| [`grant_imputation_amount`](grant_imputation_amount.sql) | 1 | 0064_grants | security definer |
| [`grant_impute_rest`](grant_impute_rest.sql) | 1 | 0064_grants | security definer |
| [`grant_position`](grant_position.sql) | 1 | 0064_grants | security definer |
| [`grant_status`](grant_status.sql) | 1 | 0064_grants | security definer |
| [`grant_unconditional`](grant_unconditional.sql) | 1 | 0064_grants | security definer |
| [`grant_year_end`](grant_year_end.sql) | 1 | 0064_grants | security definer |
| [`grant_year_end_preview`](grant_year_end_preview.sql) | 1 | 0064_grants | security definer |
| [`home_kpis`](home_kpis.sql) | 1 | 0031_home_kpis | security definer |
| [`impair_asset`](impair_asset.sql) | 1 | 0046_asset_impairment | security definer |
| [`impair_receivable`](impair_receivable.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`impair_receivables_global`](impair_receivables_global.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`import_account_name`](import_account_name.sql) | 1 | 0021_journal_import | invoker |
| [`import_batch_open`](import_batch_open.sql) | 1 | 0021_journal_import | invoker |
| [`import_credit`](import_credit.sql) | 1 | 0021_journal_import | invoker |
| [`import_debit`](import_debit.sql) | 1 | 0021_journal_import | invoker |
| [`import_finish`](import_finish.sql) | 1 | 0021_journal_import | security definer |
| [`import_post_month`](import_post_month.sql) | 1 | 0021_journal_import | security definer |
| [`import_posting_accounts`](import_posting_accounts.sql) | 1 | 0008_import_accounts | invoker |
| [`import_prepare`](import_prepare.sql) | 1 | 0021_journal_import | security definer |
| [`import_preview`](import_preview.sql) | 1 | 0021_journal_import | security definer |
| [`import_start`](import_start.sql) | 1 | 0021_journal_import | invoker |
| [`integrity_checks`](integrity_checks.sql) | 2 | 0059_corporate_tax_integration | invoker |
| [`intra_eu_lines`](intra_eu_lines.sql) | 1 | 0052_forms_347_349 | invoker |
| [`inventory_account`](inventory_account.sql) | 1 | 0047_inventory_closing | security definer |
| [`inventory_preview`](inventory_preview.sql) | 1 | 0047_inventory_closing | invoker |
| [`invoice_entry_lines`](invoice_entry_lines.sql) | 7 | 0063_financing_integration | invoker |
| [`invoice_pending`](invoice_pending.sql) | 1 | 0035_payments | invoker |
| [`is_admin`](is_admin.sql) | 3 | 0015_guest_access | invoker |
| [`is_anonymous`](is_anonymous.sql) | 1 | 0015_guest_access | invoker |
| [`is_data_owner`](is_data_owner.sql) | 1 | 0027_members | security definer |
| [`is_owner`](is_owner.sql) | 1 | 0007_demo_and_limits | security definer |
| [`is_settlement_entry`](is_settlement_entry.sql) | 2 | 0017_year_closing | invoker |
| [`is_year_closing_entry`](is_year_closing_entry.sql) | 1 | 0017_year_closing | invoker |
| [`legal_form_from_tax_id`](legal_form_from_tax_id.sql) | 1 | 0033_withholding_rules | invoker |
| [`link_payment`](link_payment.sql) | 1 | 0035_payments | security definer |
| [`load_case`](load_case.sql) | 2 | 0067_case_screen | invoker |
| [`loan_account`](loan_account.sql) | 1 | 0062_loans | security definer |
| [`loan_accrual_amount`](loan_accrual_amount.sql) | 1 | 0062_loans | security definer |
| [`loan_calc`](loan_calc.sql) | 1 | 0062_loans | invoker |
| [`loan_cancel`](loan_cancel.sql) | 2 | 0063_financing_integration | security definer |
| [`loan_check`](loan_check.sql) | 1 | 0062_loans | security definer |
| [`loan_create`](loan_create.sql) | 2 | 0063_financing_integration | security definer |
| [`loan_days360`](loan_days360.sql) | 1 | 0062_loans | invoker |
| [`loan_effective_rate`](loan_effective_rate.sql) | 1 | 0062_loans | invoker |
| [`loan_french_payments`](loan_french_payments.sql) | 1 | 0062_loans | invoker |
| [`loan_instalment_invoice`](loan_instalment_invoice.sql) | 1 | 0063_financing_integration | security definer |
| [`loan_next_instalment`](loan_next_instalment.sql) | 1 | 0062_loans | security definer |
| [`loan_payment`](loan_payment.sql) | 1 | 0062_loans | security definer |
| [`loan_position`](loan_position.sql) | 1 | 0062_loans | security definer |
| [`loan_present_value`](loan_present_value.sql) | 1 | 0062_loans | invoker |
| [`loan_rows`](loan_rows.sql) | 1 | 0062_loans | invoker |
| [`loan_short_target`](loan_short_target.sql) | 1 | 0062_loans | security definer |
| [`loan_status`](loan_status.sql) | 1 | 0062_loans | security definer |
| [`loan_year_end`](loan_year_end.sql) | 1 | 0062_loans | security definer |
| [`loan_year_end_preview`](loan_year_end_preview.sql) | 1 | 0062_loans | security definer |
| [`month_close_preview`](month_close_preview.sql) | 1 | 0069_monthly_accounting | security definer |
| [`my_profile`](my_profile.sql) | 2 | 0015_guest_access | security definer |
| [`my_role`](my_role.sql) | 1 | 0006_security_rls | security definer |
| [`net_turnover`](net_turnover.sql) | 1 | 0057_corporate_tax | invoker |
| [`next_subaccount_no`](next_subaccount_no.sql) | 1 | 0025_entry_tutor | invoker |
| [`normalize_tax_id`](normalize_tax_id.sql) | 1 | 0009_partners | invoker |
| [`open_items`](open_items.sql) | 1 | 0035_payments | invoker |
| [`operation_for_lines`](operation_for_lines.sql) | 1 | 0054_operations_exercises | invoker |
| [`partner_control_account`](partner_control_account.sql) | 1 | 0009_partners | invoker |
| [`pay_payroll`](pay_payroll.sql) | 1 | 0049_payroll | security definer |
| [`payslip_calc`](payslip_calc.sql) | 1 | 0049_payroll | invoker |
| [`pct_text`](pct_text.sql) | 1 | 0051_tax_forms | invoker |
| [`pgc_account_problem`](pgc_account_problem.sql) | 1 | 0056_grader_fixes | invoker |
| [`post_closing_entry`](post_closing_entry.sql) | 1 | 0017_year_closing | invoker |
| [`post_depreciation`](post_depreciation.sql) | 2 | 0046_asset_impairment | security definer |
| [`post_entries`](post_entries.sql) | 1 | 0070_entries_screen | security definer |
| [`post_entry`](post_entry.sql) | 1 | 0004_journal_entries | invoker |
| [`post_inventory`](post_inventory.sql) | 1 | 0047_inventory_closing | security definer |
| [`post_invoice`](post_invoice.sql) | 4 | 0020_pro_rata | invoker |
| [`post_payment`](post_payment.sql) | 1 | 0035_payments | security definer |
| [`post_pro_rata_regularization`](post_pro_rata_regularization.sql) | 1 | 0020_pro_rata | invoker |
| [`post_tax_settlement`](post_tax_settlement.sql) | 1 | 0012_tax_settlement | invoker |
| [`pre_tax_result`](pre_tax_result.sql) | 1 | 0057_corporate_tax | invoker |
| [`preview_invoice`](preview_invoice.sql) | 1 | 0011_invoices | invoker |
| [`pro_rata_calc`](pro_rata_calc.sql) | 2 | 0042_assets_integration | invoker |
| [`provision_account`](provision_account.sql) | 1 | 0045_provisions | security definer |
| [`provision_add_movement`](provision_add_movement.sql) | 1 | 0045_provisions | security definer |
| [`provision_balance`](provision_balance.sql) | 1 | 0045_provisions | invoker |
| [`provision_post`](provision_post.sql) | 1 | 0045_provisions | security definer |
| [`provision_prefix`](provision_prefix.sql) | 1 | 0045_provisions | invoker |
| [`quarter_end`](quarter_end.sql) | 1 | 0012_tax_settlement | invoker |
| [`quarter_start`](quarter_start.sql) | 1 | 0012_tax_settlement | invoker |
| [`ratio_parts`](ratio_parts.sql) | 2 | 0024_ai_context | security definer |
| [`reclassify_provision`](reclassify_provision.sql) | 1 | 0045_provisions | security definer |
| [`reopen_fiscal_year`](reopen_fiscal_year.sql) | 1 | 0017_year_closing | invoker |
| [`reopen_month`](reopen_month.sql) | 1 | 0069_monthly_accounting | security definer |
| [`result_account_no`](result_account_no.sql) | 1 | 0017_year_closing | invoker |
| [`reverse_accrual`](reverse_accrual.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`reverse_accruals`](reverse_accruals.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`reverse_asset_impairment`](reverse_asset_impairment.sql) | 1 | 0046_asset_impairment | security definer |
| [`reverse_entry`](reverse_entry.sql) | 3 | 0017_year_closing | invoker |
| [`reverse_impairment`](reverse_impairment.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`revise_provision`](revise_provision.sql) | 1 | 0045_provisions | security definer |
| [`revoke_company_access`](revoke_company_access.sql) | 1 | 0027_members | security definer |
| [`run_audit_checks`](run_audit_checks.sql) | 11 | 0065_grants_integration | invoker |
| [`run_payroll`](run_payroll.sql) | 1 | 0049_payroll | security definer |
| [`save_draft`](save_draft.sql) | 1 | 0070_entries_screen | security definer |
| [`save_employee`](save_employee.sql) | 1 | 0049_payroll | security definer |
| [`set_company_demo`](set_company_demo.sql) | 1 | 0027_members | security definer |
| [`set_control_mode`](set_control_mode.sql) | 1 | 0036_controlled_accounts | security definer |
| [`set_legal_form`](set_legal_form.sql) | 1 | 0060_equity_operations | security definer |
| [`set_pro_rata`](set_pro_rata.sql) | 1 | 0020_pro_rata | invoker |
| [`set_vat_regime`](set_vat_regime.sql) | 1 | 0019_reverse_charge_surcharge | invoker |
| [`setup_taxes`](setup_taxes.sql) | 1 | 0010_tax_setup | invoker |
| [`setup_withholdings`](setup_withholdings.sql) | 1 | 0018_withholding_exempt | invoker |
| [`special_tax_account`](special_tax_account.sql) | 1 | 0019_reverse_charge_surcharge | invoker |
| [`start_accounting`](start_accounting.sql) | 1 | 0069_monthly_accounting | security definer |
| [`submit_exercise`](submit_exercise.sql) | 2 | 0055_practice_integration | security definer |
| [`tax_form_boxes`](tax_form_boxes.sql) | 1 | 0051_tax_forms | invoker |
| [`tax_form_lines`](tax_form_lines.sql) | 1 | 0051_tax_forms | invoker |
| [`tax_rate_text`](tax_rate_text.sql) | 1 | 0010_tax_setup | invoker |
| [`tax_settlement_calc`](tax_settlement_calc.sql) | 4 | 0039_review_fixes | invoker |
| [`template_parent`](template_parent.sql) | 1 | 0008_import_accounts | invoker |
| [`tf_row`](tf_row.sql) | 1 | 0051_tax_forms | invoker |
| [`tg_company_add_admin`](tg_company_add_admin.sql) | 1 | 0001_core | trigger |
| [`tg_company_copy_coa`](tg_company_copy_coa.sql) | 1 | 0002_chart_of_accounts | trigger |
| [`tg_company_rules`](tg_company_rules.sql) | 3 | 0027_members | trigger |
| [`tg_company_vat_regime`](tg_company_vat_regime.sql) | 1 | 0019_reverse_charge_surcharge | trigger |
| [`tg_entry_adjust_reverse`](tg_entry_adjust_reverse.sql) | 8 | 0064_grants | trigger |
| [`tg_entry_asset_reverse`](tg_entry_asset_reverse.sql) | 2 | 0046_asset_impairment | trigger |
| [`tg_entry_check_inverse`](tg_entry_check_inverse.sql) | 2 | 0021_journal_import | trigger |
| [`tg_entry_controlled_accounts`](tg_entry_controlled_accounts.sql) | 1 | 0036_controlled_accounts | trigger |
| [`tg_entry_invoice_reverse`](tg_entry_invoice_reverse.sql) | 1 | 0011_invoices | trigger |
| [`tg_entry_payment_reverse`](tg_entry_payment_reverse.sql) | 1 | 0035_payments | trigger |
| [`tg_entry_prevent_delete`](tg_entry_prevent_delete.sql) | 1 | 0004_journal_entries | trigger |
| [`tg_entry_pro_rata_reverse`](tg_entry_pro_rata_reverse.sql) | 1 | 0020_pro_rata | trigger |
| [`tg_entry_validate`](tg_entry_validate.sql) | 1 | 0004_journal_entries | trigger |
| [`tg_entry_work_month`](tg_entry_work_month.sql) | 1 | 0069_monthly_accounting | trigger |
| [`tg_fiscal_year_status`](tg_fiscal_year_status.sql) | 1 | 0017_year_closing | trigger |
| [`tg_gl_account_block_default`](tg_gl_account_block_default.sql) | 1 | 0013_balance_rules | trigger |
| [`tg_gl_account_validate`](tg_gl_account_validate.sql) | 1 | 0002_chart_of_accounts | trigger |
| [`tg_invoice_due_date`](tg_invoice_due_date.sql) | 1 | 0035_payments | trigger |
| [`tg_invoice_line_asset_cost`](tg_invoice_line_asset_cost.sql) | 1 | 0046_asset_impairment | trigger |
| [`tg_invoice_loan_credit_memo`](tg_invoice_loan_credit_memo.sql) | 1 | 0063_financing_integration | trigger |
| [`tg_invoice_protect`](tg_invoice_protect.sql) | 1 | 0011_invoices | trigger |
| [`tg_line_set_partner`](tg_line_set_partner.sql) | 1 | 0009_partners | trigger |
| [`tg_line_set_tax_code`](tg_line_set_tax_code.sql) | 2 | 0021_journal_import | trigger |
| [`tg_line_tax_period_lock`](tg_line_tax_period_lock.sql) | 3 | 0021_journal_import | trigger |
| [`tg_line_validate`](tg_line_validate.sql) | 2 | 0021_journal_import | trigger |
| [`tg_partner_equivalence`](tg_partner_equivalence.sql) | 1 | 0019_reverse_charge_surcharge | trigger |
| [`tg_partner_sync_account_name`](tg_partner_sync_account_name.sql) | 1 | 0009_partners | trigger |
| [`tg_partner_validate`](tg_partner_validate.sql) | 1 | 0009_partners | trigger |
| [`tg_partner_withholding_validate`](tg_partner_withholding_validate.sql) | 1 | 0033_withholding_rules | trigger |
| [`tg_pro_rata_protect`](tg_pro_rata_protect.sql) | 1 | 0020_pro_rata | trigger |
| [`tg_protect_data_owner`](tg_protect_data_owner.sql) | 1 | 0030_protect_data_owner | trigger |
| [`tg_tax_settlement_protect`](tg_tax_settlement_protect.sql) | 1 | 0012_tax_settlement | trigger |
| [`tg_tax_settlement_validate`](tg_tax_settlement_validate.sql) | 1 | 0010_tax_setup | trigger |
| [`tg_tax_setup_special_accounts`](tg_tax_setup_special_accounts.sql) | 1 | 0019_reverse_charge_surcharge | trigger |
| [`tg_tax_setup_validate`](tg_tax_setup_validate.sql) | 2 | 0019_reverse_charge_surcharge | trigger |
| [`tg_withholding_auto_setup`](tg_withholding_auto_setup.sql) | 1 | 0018_withholding_exempt | trigger |
| [`tg_withholding_setup_validate`](tg_withholding_setup_validate.sql) | 1 | 0018_withholding_exempt | trigger |
| [`tg_year_closing_protect`](tg_year_closing_protect.sql) | 1 | 0017_year_closing | trigger |
| [`trial_balance`](trial_balance.sql) | 2 | 0021_journal_import | invoker |
| [`tutor_criteria_checks`](tutor_criteria_checks.sql) | 1 | 0026_tutor_checks | invoker |
| [`valid_spanish_tax_id`](valid_spanish_tax_id.sql) | 1 | 0009_partners | invoker |
| [`validate_proposed_entry`](validate_proposed_entry.sql) | 3 | 0033_withholding_rules | invoker |
| [`web_usage`](web_usage.sql) | 1 | 0034_web_usage | security definer |
| [`withholding_setup_core`](withholding_setup_core.sql) | 1 | 0018_withholding_exempt | invoker |
| [`withholding_summary`](withholding_summary.sql) | 2 | 0050_payroll_integration | invoker |
| [`work_month`](work_month.sql) | 1 | 0069_monthly_accounting | security definer |
| [`work_period`](work_period.sql) | 1 | 0069_monthly_accounting | security definer |
| [`write_off_receivable`](write_off_receivable.sql) | 1 | 0043_year_end_adjustments | security definer |
| [`year_account_balances`](year_account_balances.sql) | 1 | 0017_year_closing | invoker |
| [`year_closing_preview`](year_closing_preview.sql) | 8 | 0065_grants_integration | invoker |
