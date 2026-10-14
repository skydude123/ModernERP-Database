SET NOCOUNT ON;

SELECT DB_NAME() AS database_name, compatibility_level
FROM sys.databases WHERE database_id = DB_ID();

SELECT object_name, object_type, found
FROM
(
    SELECT 'dbo.a_asset_master', 'asset master', CASE WHEN OBJECT_ID('dbo.a_asset_master','U') IS NULL THEN 0 ELSE 1 END
    UNION ALL SELECT 'dbo.TWB_FixedAsset', 'legacy asset master', CASE WHEN OBJECT_ID('dbo.TWB_FixedAsset','U') IS NULL THEN 0 ELSE 1 END
    UNION ALL SELECT 'dbo.TWB_FixedAssetDepSchedule', 'legacy depreciation schedule', CASE WHEN OBJECT_ID('dbo.TWB_FixedAssetDepSchedule','U') IS NULL THEN 0 ELSE 1 END
    UNION ALL SELECT 'dbo.TWB_ChaAcct', 'chart of accounts', CASE WHEN OBJECT_ID('dbo.TWB_ChaAcct','U') IS NULL THEN 0 ELSE 1 END
    UNION ALL SELECT 'dbo.TWB_JRNLhdr', 'journal header', CASE WHEN OBJECT_ID('dbo.TWB_JRNLhdr','U') IS NULL THEN 0 ELSE 1 END
    UNION ALL SELECT 'dbo.TWB_JRNLdtl', 'journal detail', CASE WHEN OBJECT_ID('dbo.TWB_JRNLdtl','U') IS NULL THEN 0 ELSE 1 END
    UNION ALL SELECT 'dbo.GJ_HDR', 'alternate journal header', CASE WHEN OBJECT_ID('dbo.GJ_HDR','U') IS NULL THEN 0 ELSE 1 END
    UNION ALL SELECT 'dbo.GJ_DTL', 'alternate journal detail', CASE WHEN OBJECT_ID('dbo.GJ_DTL','U') IS NULL THEN 0 ELSE 1 END
) q(object_name, object_type, found);

IF OBJECT_ID('dbo.a_asset_master','U') IS NOT NULL
BEGIN
    SELECT c.name AS missing_required_column
    FROM (VALUES
        ('asset_master_id'),('asset_no'),('asset_code'),('description'),('acquisition_cost'),
        ('asset_category_code'),('in_service_date'),('branch_name'),('depreciation_method_code'),
        ('useful_life_months'),('residual_value'),('depreciation_start_date'),
        ('asset_cost_account'),('depreciation_expense_account'),
        ('accumulated_depreciation_account'),('status')
    ) c(name)
    WHERE COL_LENGTH('dbo.a_asset_master', c.name) IS NULL;

    SELECT asset_master_id, asset_no, acquisition_cost, residual_value, useful_life_months,
           depreciation_start_date, depreciation_expense_account, accumulated_depreciation_account
    FROM dbo.a_asset_master
    WHERE residual_value < 0
       OR residual_value > acquisition_cost
       OR useful_life_months <= 0
       OR depreciation_start_date IS NULL
       OR NULLIF(LTRIM(RTRIM(depreciation_expense_account)),'') IS NULL
       OR NULLIF(LTRIM(RTRIM(accumulated_depreciation_account)),'') IS NULL;
END;

IF OBJECT_ID('dbo.a_dep_schedule','U') IS NOT NULL
BEGIN
    SELECT asset_id, period_key, COUNT(*) AS active_rows
    FROM dbo.a_dep_schedule
    WHERE is_active = 1
    GROUP BY asset_id, period_key
    HAVING COUNT(*) > 1;

    SELECT asset_id, period_key, acquisition_cost, residual_value,
           closing_accumulated_depreciation, closing_net_book_value
    FROM dbo.a_dep_schedule
    WHERE closing_net_book_value < residual_value
       OR closing_accumulated_depreciation > acquisition_cost - residual_value;
END;
