IF OBJECT_ID(N'dbo.usp_Supplier_SetActiveStatus', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_Supplier_SetActiveStatus AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.usp_Supplier_SetActiveStatus
    @SupplierCode          VARCHAR(10),
    @ActiveFlag            CHAR(1),
    @ExpectedModifiedDate  DATETIME,
    @UserId                VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CurrentModifiedDate DATETIME;
    DECLARE @CurrentActiveFlag CHAR(1);
    DECLARE @ModifiedDate DATETIME;

    SET @SupplierCode = UPPER(LTRIM(RTRIM(@SupplierCode)));
    SET @ActiveFlag = UPPER(LTRIM(RTRIM(@ActiveFlag)));
    SET @UserId = LTRIM(RTRIM(@UserId));

    IF @ActiveFlag NOT IN ('Y', 'N')
    BEGIN
        RAISERROR('SUPPLIER_INVALID_STATUS: Supplier status must be Y or N.', 16, 1);
        RETURN;
    END;

    IF @ExpectedModifiedDate IS NULL
    BEGIN
        RAISERROR('SUPPLIER_CONCURRENCY: Expected modified date is required.', 16, 1);
        RETURN;
    END;

    IF @UserId = ''
    BEGIN
        RAISERROR('SUPPLIER_INVALID_USER: Authenticated user is required.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @CurrentModifiedDate = s.date_changed,
            @CurrentActiveFlag = s.active_flag
        FROM dbo.a_suppliers AS s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.supp_code = @SupplierCode;

        IF @CurrentModifiedDate IS NULL
        BEGIN
            RAISERROR('SUPPLIER_NOT_FOUND: Supplier was not found.', 16, 1);
        END;

        IF @CurrentModifiedDate <> @ExpectedModifiedDate
        BEGIN
            RAISERROR('SUPPLIER_CONCURRENCY: The supplier was changed by another user. Refresh before trying again.', 16, 1);
        END;

        IF @CurrentActiveFlag = @ActiveFlag
        BEGIN
            RAISERROR('SUPPLIER_STATUS_CONFLICT: Supplier is already in the requested status.', 16, 1);
        END;

        SET @ModifiedDate = GETDATE();
        IF @ModifiedDate <= @CurrentModifiedDate
            SET @ModifiedDate = DATEADD(MILLISECOND, 4, @CurrentModifiedDate);

        UPDATE dbo.a_suppliers
        SET active_flag = @ActiveFlag,
            user_id = @UserId,
            date_changed = @ModifiedDate
        WHERE supp_code = @SupplierCode
          AND date_changed = @ExpectedModifiedDate
          AND active_flag = @CurrentActiveFlag;

        IF @@ROWCOUNT <> 1
        BEGIN
            RAISERROR('SUPPLIER_CONCURRENCY: The supplier was changed by another user. Refresh before trying again.', 16, 1);
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage = ERROR_MESSAGE();
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
        Message = CAST(
            CASE WHEN @ActiveFlag = 'Y'
                THEN 'Supplier activated successfully.'
                ELSE 'Supplier deactivated successfully.'
            END AS VARCHAR(200)),
        WarningMessage = CAST(NULL AS VARCHAR(300))
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
