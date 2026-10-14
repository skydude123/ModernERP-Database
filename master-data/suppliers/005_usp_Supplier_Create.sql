IF OBJECT_ID(N'dbo.usp_Supplier_Create', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_Supplier_Create AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.usp_Supplier_Create
    @SupplierCode       VARCHAR(10),
    @SupplierName       VARCHAR(100),
    @SupplierGroupCode  VARCHAR(5),
    @AddressLine1       VARCHAR(200) = NULL,
    @AddressLine2       VARCHAR(35) = NULL,
    @AddressLine3       VARCHAR(35) = NULL,
    @ContactPerson      VARCHAR(35) = NULL,
    @PositionTitle      VARCHAR(25) = NULL,
    @Telephone          VARCHAR(30) = NULL,
    @Fax                VARCHAR(30) = NULL,
    @Email              VARCHAR(45) = NULL,
    @TinNo              VARCHAR(50) = NULL,
    @TermsCode          VARCHAR(4) = NULL,
    @CurrencyCode       VARCHAR(5) = NULL,
    @Website            VARCHAR(80) = NULL,
    @Specialties        VARCHAR(500) = NULL,
    @TaxProfileCode     VARCHAR(15) = NULL,
    @UserId             VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ModifiedDate DATETIME;
    DECLARE @NormalizedTin VARCHAR(50);
    DECLARE @SimilarSupplierCode VARCHAR(10);
    DECLARE @SimilarSupplierName VARCHAR(100);
    DECLARE @WarningMessage VARCHAR(300);

    SET @SupplierCode = UPPER(LTRIM(RTRIM(@SupplierCode)));
    SET @SupplierName = LTRIM(RTRIM(@SupplierName));
    SET @SupplierGroupCode = UPPER(LTRIM(RTRIM(@SupplierGroupCode)));
    SET @AddressLine1 = NULLIF(LTRIM(RTRIM(@AddressLine1)), '');
    SET @AddressLine2 = NULLIF(LTRIM(RTRIM(@AddressLine2)), '');
    SET @AddressLine3 = NULLIF(LTRIM(RTRIM(@AddressLine3)), '');
    SET @ContactPerson = NULLIF(LTRIM(RTRIM(@ContactPerson)), '');
    SET @PositionTitle = NULLIF(LTRIM(RTRIM(@PositionTitle)), '');
    SET @Telephone = NULLIF(LTRIM(RTRIM(@Telephone)), '');
    SET @Fax = NULLIF(LTRIM(RTRIM(@Fax)), '');
    SET @Email = NULLIF(LTRIM(RTRIM(@Email)), '');
    SET @TinNo = NULLIF(LTRIM(RTRIM(@TinNo)), '');
    SET @TermsCode = NULLIF(UPPER(LTRIM(RTRIM(@TermsCode))), '');
    SET @CurrencyCode = NULLIF(UPPER(LTRIM(RTRIM(@CurrencyCode))), '');
    SET @Website = NULLIF(LTRIM(RTRIM(@Website)), '');
    SET @Specialties = NULLIF(LTRIM(RTRIM(@Specialties)), '');
    SET @TaxProfileCode = NULLIF(UPPER(LTRIM(RTRIM(@TaxProfileCode))), '');
    SET @UserId = LTRIM(RTRIM(@UserId));
    SET @NormalizedTin =
        CASE WHEN @TinNo IS NULL THEN NULL ELSE NULLIF(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                UPPER(@TinNo), ' ', ''), '-', ''), '.', ''), '/', ''), '(', ''), ')', ''), '')
        END;

    IF @SupplierCode = ''
    BEGIN
        RAISERROR('SUPPLIER_INVALID_CODE: Supplier code is required.', 16, 1);
        RETURN;
    END;

    IF @SupplierName = ''
    BEGIN
        RAISERROR('SUPPLIER_INVALID_NAME: Supplier name is required.', 16, 1);
        RETURN;
    END;

    IF @SupplierGroupCode = ''
    BEGIN
        RAISERROR('SUPPLIER_INVALID_GROUP: Supplier group is required.', 16, 1);
        RETURN;
    END;

    IF @UserId = ''
    BEGIN
        RAISERROR('SUPPLIER_INVALID_USER: Authenticated user is required.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.a_suppliers WITH (UPDLOCK, HOLDLOCK)
            WHERE supp_code = @SupplierCode
        )
        BEGIN
            RAISERROR('SUPPLIER_DUPLICATE_CODE: Supplier code already exists.', 16, 1);
        END;

        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.a_supp_group WHERE sup_group_code = @SupplierGroupCode
        )
        BEGIN
            RAISERROR('SUPPLIER_INVALID_GROUP: Supplier group does not exist.', 16, 1);
        END;

        IF @TermsCode IS NOT NULL AND NOT EXISTS
        (
            SELECT 1 FROM dbo.a_terms WHERE term_code = @TermsCode
        )
        BEGIN
            RAISERROR('SUPPLIER_INVALID_TERMS: Payment terms code does not exist.', 16, 1);
        END;

        IF @CurrencyCode IS NOT NULL AND NOT EXISTS
        (
            SELECT 1 FROM dbo.a_currency WHERE curr_code = @CurrencyCode
        )
        BEGIN
            RAISERROR('SUPPLIER_INVALID_CURRENCY: Currency code does not exist.', 16, 1);
        END;

        IF @TaxProfileCode IS NOT NULL AND NOT EXISTS
        (
            SELECT 1
            FROM dbo.AP_CHRX
            WHERE CHRX_NO = @TaxProfileCode
              AND ISNULL(CHRX_APFLG, 'N') = 'Y'
        )
        BEGIN
            RAISERROR('SUPPLIER_INVALID_TAX_PROFILE: Tax profile is not active or does not exist.', 16, 1);
        END;

        IF @NormalizedTin IS NOT NULL AND EXISTS
        (
            SELECT 1
            FROM dbo.a_suppliers WITH (UPDLOCK, HOLDLOCK)
            WHERE NULLIF(LTRIM(RTRIM(tin_no)), '') IS NOT NULL
              AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                    UPPER(LTRIM(RTRIM(tin_no))), ' ', ''), '-', ''), '.', ''), '/', ''), '(', ''), ')', '') = @NormalizedTin
        )
        BEGIN
            RAISERROR('SUPPLIER_DUPLICATE_TIN: Another supplier already uses the same normalized TIN.', 16, 1);
        END;

        SELECT TOP (1)
            @SimilarSupplierCode = LTRIM(RTRIM(s.supp_code)),
            @SimilarSupplierName = LTRIM(RTRIM(s.supp_name))
        FROM dbo.a_suppliers AS s
        WHERE UPPER(LTRIM(RTRIM(s.supp_name))) = UPPER(@SupplierName)
           OR
           (
               LEN(@SupplierName) >= 5
               AND
               (
                   UPPER(LTRIM(RTRIM(s.supp_name))) LIKE UPPER(@SupplierName) + '%'
                   OR UPPER(@SupplierName) LIKE UPPER(LTRIM(RTRIM(s.supp_name))) + '%'
               )
           )
        ORDER BY
            CASE WHEN UPPER(LTRIM(RTRIM(s.supp_name))) = UPPER(@SupplierName) THEN 0 ELSE 1 END,
            s.supp_code;

        IF @SimilarSupplierCode IS NOT NULL
        BEGIN
            SET @WarningMessage =
                'A supplier with a similar name already exists: ' +
                @SimilarSupplierCode + ' - ' + @SimilarSupplierName + '.';
        END;

        SET @ModifiedDate = GETDATE();

        INSERT dbo.a_suppliers
        (
            supp_code, supp_name, sup_group_code, address_1, address_2,
            address_3, contact, position_title, tel_no, fax_no, email,
            tin_no, terms, curr_code, website_add, specialties, user_id,
            date_changed, active_flag, chrx_no
        )
        VALUES
        (
            @SupplierCode, @SupplierName, @SupplierGroupCode, @AddressLine1,
            @AddressLine2, @AddressLine3, @ContactPerson, @PositionTitle,
            @Telephone, @Fax, @Email, @TinNo, @TermsCode, @CurrencyCode,
            @Website, @Specialties, @UserId, @ModifiedDate, 'Y', @TaxProfileCode
        );

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000);
        DECLARE @ErrorNumber INT;
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @ErrorNumber = ERROR_NUMBER();

        IF @ErrorNumber IN (2601, 2627)
            SET @ErrorMessage = 'SUPPLIER_DUPLICATE_CODE: Supplier code already exists.';

        RAISERROR(@ErrorMessage, 16, 1);
        RETURN;
    END CATCH;

    SELECT
        SupplierCode = LTRIM(RTRIM(s.supp_code)),
        SupplierName = LTRIM(RTRIM(s.supp_name)),
        SupplierGroupCode = LTRIM(RTRIM(s.sup_group_code)),
        SupplierGroupName = LTRIM(RTRIM(ISNULL(g.sup_group_desc, ''))),
        AddressLine1 = NULLIF(LTRIM(RTRIM(s.address_1)), ''),
        AddressLine2 = NULLIF(LTRIM(RTRIM(s.address_2)), ''),
        AddressLine3 = NULLIF(LTRIM(RTRIM(s.address_3)), ''),
        ContactPerson = NULLIF(LTRIM(RTRIM(s.contact)), ''),
        PositionTitle = NULLIF(LTRIM(RTRIM(s.position_title)), ''),
        Telephone = NULLIF(LTRIM(RTRIM(s.tel_no)), ''),
        Fax = NULLIF(LTRIM(RTRIM(s.fax_no)), ''),
        Email = NULLIF(LTRIM(RTRIM(s.email)), ''),
        TinNo = NULLIF(LTRIM(RTRIM(s.tin_no)), ''),
        TermsCode = NULLIF(LTRIM(RTRIM(s.terms)), ''),
        TermsDescription = NULLIF(LTRIM(RTRIM(t.term_description)), ''),
        CurrencyCode = NULLIF(LTRIM(RTRIM(s.curr_code)), ''),
        CurrencyDescription = NULLIF(LTRIM(RTRIM(c.curr_desc)), ''),
        Website = NULLIF(LTRIM(RTRIM(s.website_add)), ''),
        Specialties = NULLIF(LTRIM(RTRIM(s.specialties)), ''),
        TaxProfileCode = NULLIF(LTRIM(RTRIM(s.chrx_no)), ''),
        TaxProfileDescription = NULLIF(LTRIM(RTRIM(tp.CHRX_DESC)), ''),
        ActiveFlag = s.active_flag,
        ModifiedBy = LTRIM(RTRIM(s.user_id)),
        ModifiedDate = s.date_changed,
        Message = CAST('Supplier created successfully.' AS VARCHAR(200)),
        WarningMessage = @WarningMessage
    FROM dbo.a_suppliers AS s
    LEFT JOIN dbo.a_supp_group AS g ON g.sup_group_code = s.sup_group_code
    LEFT JOIN dbo.a_terms AS t ON t.term_code = s.terms
    LEFT JOIN dbo.a_currency AS c ON c.curr_code = s.curr_code
    LEFT JOIN
    (
        SELECT CHRX_NO, MAX(CHRX_DESC) AS CHRX_DESC
        FROM dbo.AP_CHRX
        GROUP BY CHRX_NO
    ) AS tp ON tp.CHRX_NO = s.chrx_no
    WHERE s.supp_code = @SupplierCode;
END;
GO
