SET NOCOUNT ON;
GO
IF OBJECT_ID('dbo.usp_Depreciation_ReportData','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_ReportData AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_ReportData @dep_run_no VARCHAR(30)
AS
BEGIN
 SET NOCOUNT ON;
 SELECT h.dep_run_no,h.period_key,h.period_start,h.period_end,h.run_date,h.status,h.branch_code,h.asset_category_code,
  h.method_code,h.depreciation_convention,h.asset_count,h.total_acquisition_cost,h.total_current_depreciation,
  h.total_closing_net_book_value,h.journal_no,h.reversal_journal_no,h.prepared_by,h.submitted_by,h.approved_by,
  h.posted_by,h.reversed_by,h.remarks,d.line_no,d.asset_code,d.asset_description,d.acquisition_cost,d.residual_value,
  d.useful_life_months,d.method_code asset_method,d.opening_accumulated_depreciation,d.current_depreciation,
  d.closing_accumulated_depreciation,d.closing_net_book_value,d.depreciation_expense_account,
  d.accumulated_depreciation_account,SYSUTCDATETIME() print_timestamp
 FROM dbo.a_dep_run_hdr h JOIN dbo.a_dep_run_dtl d ON d.dep_run_no=h.dep_run_no
 WHERE h.dep_run_no=@dep_run_no AND d.is_selected=1 ORDER BY d.line_no;
END;
GO
