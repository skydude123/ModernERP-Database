IF OBJECT_ID(N'dbo.usp_Supplier_Validate', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_Supplier_Validate AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.usp_Supplier_Validate
    @SupplierCode       VARCHAR(10),
    @SupplierName       VARCHAR(100),
    @TinNo              VARCHAR(50) = NULL,
    @SupplierGroupCode  VARCHAR(5),
    @TermsCode          VARCHAR(4) = NULL,
    @CurrencyCode       VARCHAR(5) = NULL,
    @TaxProfileCode     VARCHAR(15) = NULL,
    @IsCreate           BIT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NormalizedName VARCHAR(100);
    DECLARE @NormalizedTin VARCHAR(50);
    DECLARE @SimilarSupplierCode VARCHAR(10);
    DECLARE @SimilarSupplierName VARCHAR(100);
    DECLARE @WarningMessage VARCHAR(300);

    SET @SupplierCode = UPPER(LTRIM(RTRIM(@SupplierCode)));
    SET @SupplierName = LTRIM(RTRIM(@SupplierName));
    SET @SupplierGroupCode = UPPER(LTRIM(RTRIM(@SupplierGroupCode)));
    SET @TermsCode = NULLIF(UPPER(LTRIM(RTRIM(@TermsCode))), '');
    SET @CurrencyCode = NULLIF(UPPER(LTRIM(RTRIM(@CurrencyCode))), '');
    SET @TaxProfileCode = NULLIF(UPPER(LTRIM(RTRIM(@TaxProfileCode))), '');
    SET @TinNo = NULLIF(LTRIM(RTRIM(@TinNo)), '');
    SET @NormalizedName = UPPER(@SupplierName);
    SET @NormalizedTin =
        CASE WHEN @TinNo IS NULL THEN NULL ELSE NULLIF(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                UPPER(@TinNo), ' ', ''), '-', ''), '.', ''), '/', ''), '(', ''), ')', ''), '')
        END;

    SELECT TOP (1)
        @SimilarSupplierCode = LTRIM(RTRIM(s.supp_code)),
        @SimilarSupplierName = LTRIM(RTRIM(s.supp_name))
    FROM dbo.a_suppliers AS s
    WHERE s.supp_code <> @SupplierCode
      AND
      (
          UPPER(LTRIM(RTRIM(s.supp_name))) = @NormalizedName
          OR
          (
              LEN(@NormalizedName) >= 5
              AND
              (
                  UPPER(LTRIM(RTRIM(s.supp_name))) LIKE @NormalizedName + '%'
                  OR @NormalizedName LIKE UPPER(LTRIM(RTRIM(s.supp_name))) + '%'
              )
          )
      )
    ORDER BY
        CASE WHEN UPPER(LTRIM(RTRIM(s.supp_name))) = @NormalizedName THEN 0 ELSE 1 END,
        s.supp_code;

    IF @SimilarSupplierCode IS NOT NULL
    BEGIN
        SET @WarningMessage =
            'A supplier with a similar name already exists: ' +
            @SimilarSupplierCode + ' - ' + @SimilarSupplierName + '.';
    END;

    SELECT
        SupplierExists = CAST(CASE WHEN EXISTS
        (
            SELECT 1 FROM dbo.a_suppliers WHERE supp_code = @SupplierCode
        ) THEN 1 ELSE 0 END AS BIT),
        SupplierCodeExists = CAST(CASE WHEN EXISTS
        (
            SELECT 1 FROM dbo.a_suppliers WHERE supp_code = @SupplierCode
        ) THEN 1 ELSE 0 END AS BIT),
        SupplierGroupExists = CAST(CASE WHEN EXISTS
        (
            SELECT 1 FROM dbo.a_supp_group WHERE sup_group_code = @SupplierGroupCode
        ) THEN 1 ELSE 0 END AS BIT),
        TermsExists = CAST(CASE WHEN @TermsCode IS NULL OR EXISTS
        (
            SELECT 1 FROM dbo.a_terms WHERE term_code = @TermsCode
        ) THEN 1 ELSE 0 END AS BIT),
        CurrencyExists = CAST(CASE WHEN @CurrencyCode IS NULL OR EXISTS
        (
            SELECT 1 FROM dbo.a_currency WHERE curr_code = @CurrencyCode
        ) THEN 1 ELSE 0 END AS BIT),
        TaxProfileExists = CAST(CASE WHEN @TaxProfileCode IS NULL OR EXISTS
        (
            SELECT 1
            FROM dbo.AP_CHRX
            WHERE CHRX_NO = @TaxProfileCode
              AND ISNULL(CHRX_APFLG, 'N') = 'Y'
        ) THEN 1 ELSE 0 END AS BIT),
        DuplicateTinExists = CAST(CASE WHEN @NormalizedTin IS NOT NULL
        AND
        (
            @IsCreate = 1
            OR NOT EXISTS
            (
                SELECT 1
                FROM dbo.a_suppliers AS current_supplier
                WHERE current_supplier.supp_code = @SupplierCode
                  AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                        UPPER(LTRIM(RTRIM(current_supplier.tin_no))), ' ', ''), '-', ''), '.', ''), '/', ''), '(', ''), ')', '') = @NormalizedTin
            )
        )
        AND EXISTS
        (
            SELECT 1
            FROM dbo.a_suppliers AS s
            WHERE s.supp_code <> @SupplierCode
              AND NULLIF(LTRIM(RTRIM(s.tin_no)), '') IS NOT NULL
              AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                    UPPER(LTRIM(RTRIM(s.tin_no))), ' ', ''), '-', ''), '.', ''), '/', ''), '(', ''), ')', '') = @NormalizedTin
        ) THEN 1 ELSE 0 END AS BIT),
        SimilarSupplierCode = @SimilarSupplierCode,
        SimilarSupplierName = @SimilarSupplierName,
        WarningMessage = @WarningMessage;
END;
GO
