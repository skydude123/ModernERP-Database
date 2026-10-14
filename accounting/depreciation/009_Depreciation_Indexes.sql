SET NOCOUNT ON;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.a_dep_schedule') AND name='UX_a_dep_schedule_active_asset_period')
 CREATE UNIQUE INDEX UX_a_dep_schedule_active_asset_period ON dbo.a_dep_schedule(asset_id,period_key) WHERE is_active=1;
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.a_dep_run_hdr') AND name='IX_a_dep_run_register')
 CREATE INDEX IX_a_dep_run_register ON dbo.a_dep_run_hdr(period_key DESC,run_date DESC,status,branch_code,asset_category_code,method_code)
 INCLUDE(asset_count,total_current_depreciation,total_closing_net_book_value,journal_no,prepared_by,posted_by,posted_at);
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.a_dep_run_dtl') AND name='IX_a_dep_run_dtl_asset')
 CREATE INDEX IX_a_dep_run_dtl_asset ON dbo.a_dep_run_dtl(asset_id,dep_run_no) INCLUDE(asset_code,asset_description,current_depreciation);
GO
