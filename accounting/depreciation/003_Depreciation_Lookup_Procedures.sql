SET NOCOUNT ON;
GO
IF OBJECT_ID('dbo.usp_Depreciation_GetBranches','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_GetBranches AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_GetBranches @search NVARCHAR(100)=NULL AS
BEGIN
 SET NOCOUNT ON;
 SELECT DISTINCT branch_name Code, branch_name Name FROM dbo.a_asset_master
 WHERE NULLIF(LTRIM(RTRIM(branch_name)),'') IS NOT NULL AND (@search IS NULL OR branch_name LIKE '%'+@search+'%') ORDER BY Name;
END;
GO
IF OBJECT_ID('dbo.usp_Depreciation_GetAssetCategories','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_GetAssetCategories AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_GetAssetCategories @search NVARCHAR(100)=NULL AS
BEGIN
 SET NOCOUNT ON;
 SELECT category_code Code, category_name Name FROM dbo.a_asset_category
 WHERE active_flag='Y' AND (@search IS NULL OR category_code LIKE '%'+@search+'%' OR category_name LIKE '%'+@search+'%') ORDER BY Name;
END;
GO
IF OBJECT_ID('dbo.usp_Depreciation_GetMethods','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_GetMethods AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_GetMethods @search NVARCHAR(100)=NULL AS
BEGIN
 SET NOCOUNT ON;
 SELECT method_code Code, method_name Name FROM dbo.a_depreciation_method
 WHERE active_flag='Y' AND (@search IS NULL OR method_code LIKE '%'+@search+'%' OR method_name LIKE '%'+@search+'%')
 UNION ALL SELECT 'NONDEP','Non-Depreciating' WHERE NOT EXISTS(SELECT 1 FROM dbo.a_depreciation_method WHERE method_code IN('NONDEP','NONE'))
 ORDER BY Name;
END;
GO
IF OBJECT_ID('dbo.usp_Depreciation_GetConventions','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_GetConventions AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_GetConventions @search NVARCHAR(100)=NULL AS
BEGIN
 SET NOCOUNT ON;
 SELECT Code,Name FROM (SELECT 'FULL_MONTH' Code,'Full Month' Name UNION ALL SELECT 'NEXT_MONTH','Next Month') q
 WHERE @search IS NULL OR Code LIKE '%'+@search+'%' OR Name LIKE '%'+@search+'%' ORDER BY Name;
END;
GO
IF OBJECT_ID('dbo.usp_Depreciation_GetPostingAccounts','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_GetPostingAccounts AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_GetPostingAccounts @search NVARCHAR(100)=NULL AS
BEGIN
 SET NOCOUNT ON;
 SELECT account_code Code, account_name Name FROM dbo.a_asset_gl_account
 WHERE active_flag='Y' AND (@search IS NULL OR account_code LIKE '%'+@search+'%' OR account_name LIKE '%'+@search+'%') ORDER BY account_code;
END;
GO
