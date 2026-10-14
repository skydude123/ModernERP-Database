IF OBJECT_ID(N'dbo.usp_Supplier_GetGroups', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_Supplier_GetGroups AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.usp_Supplier_GetGroups
    @Search VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

    SELECT
        Code = LTRIM(RTRIM(sup_group_code)),
        Description = LTRIM(RTRIM(sup_group_desc)),
        DisplayName = LTRIM(RTRIM(sup_group_code)) + ' - ' + LTRIM(RTRIM(sup_group_desc))
    FROM dbo.a_supp_group
    WHERE @Search IS NULL
       OR sup_group_code LIKE '%' + @Search + '%'
       OR sup_group_desc LIKE '%' + @Search + '%'
    ORDER BY sup_group_desc, sup_group_code;
END;
GO

IF OBJECT_ID(N'dbo.usp_Supplier_GetTerms', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_Supplier_GetTerms AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.usp_Supplier_GetTerms
    @Search VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

    SELECT
        Code = LTRIM(RTRIM(term_code)),
        Description = LTRIM(RTRIM(term_description)),
        DisplayName = LTRIM(RTRIM(term_code)) + ' - ' + LTRIM(RTRIM(term_description))
    FROM dbo.a_terms
    WHERE @Search IS NULL
       OR term_code LIKE '%' + @Search + '%'
       OR term_description LIKE '%' + @Search + '%'
    ORDER BY term_description, term_code;
END;
GO

IF OBJECT_ID(N'dbo.usp_Supplier_GetCurrencies', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_Supplier_GetCurrencies AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.usp_Supplier_GetCurrencies
    @Search VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

    SELECT
        Code = LTRIM(RTRIM(curr_code)),
        Description = LTRIM(RTRIM(curr_desc)),
        DisplayName = LTRIM(RTRIM(curr_code)) + ' - ' + LTRIM(RTRIM(curr_desc))
    FROM dbo.a_currency
    WHERE @Search IS NULL
       OR curr_code LIKE '%' + @Search + '%'
       OR curr_desc LIKE '%' + @Search + '%'
    ORDER BY curr_desc, curr_code;
END;
GO

IF OBJECT_ID(N'dbo.usp_Supplier_GetTaxProfiles', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_Supplier_GetTaxProfiles AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.usp_Supplier_GetTaxProfiles
    @Search VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');

    SELECT
        Code = LTRIM(RTRIM(CONVERT(VARCHAR(15), CHRX_NO))),
        Description = LTRIM(RTRIM(CONVERT(VARCHAR(50), MAX(CHRX_DESC)))),
        DisplayName =
            LTRIM(RTRIM(CONVERT(VARCHAR(15), CHRX_NO))) + ' - ' +
            LTRIM(RTRIM(CONVERT(VARCHAR(50), MAX(CHRX_DESC))))
    FROM dbo.AP_CHRX
    WHERE ISNULL(CHRX_APFLG, 'N') = 'Y'
      AND
      (
          @Search IS NULL
          OR CHRX_NO LIKE '%' + @Search + '%'
          OR CHRX_DESC LIKE '%' + @Search + '%'
      )
    GROUP BY CHRX_NO
    ORDER BY Description, Code;
END;
GO
