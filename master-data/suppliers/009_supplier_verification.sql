/*
    SUPPLIER MASTER VERIFICATION

    Run only in an authorized development/test RISCDB after scripts 001-008.
    The script creates uniquely named test suppliers and removes only those
    generated rows. It must never be run against production.
*/
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @TestCode VARCHAR(10);
DECLARE @SecondCode VARCHAR(10);
DECLARE @GroupCode VARCHAR(5);
DECLARE @TermsCode VARCHAR(4);
DECLARE @CurrencyCode VARCHAR(5);
DECLARE @TaxProfileCode VARCHAR(15);
DECLARE @TinNo VARCHAR(50);
DECLARE @ModifiedDate DATETIME;
DECLARE @UpdatedDate DATETIME;
DECLARE @ErrorMessage NVARCHAR(4000);

SET @TestCode = 'ZX' + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
SET @SecondCode = 'ZY' + LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 8);
SET @TinNo = 'VERIFY-' + @TestCode;

SELECT TOP (1) @GroupCode = sup_group_code
FROM dbo.a_supp_group
ORDER BY sup_group_code;

SELECT TOP (1) @TermsCode = term_code
FROM dbo.a_terms
ORDER BY term_code;

SELECT TOP (1) @CurrencyCode = curr_code
FROM dbo.a_currency
ORDER BY curr_code;

SELECT TOP (1) @TaxProfileCode = CONVERT(VARCHAR(15), CHRX_NO)
FROM dbo.AP_CHRX
WHERE ISNULL(CHRX_APFLG, 'N') = 'Y'
ORDER BY CHRX_NO;

IF @GroupCode IS NULL
BEGIN
    RAISERROR('Supplier verification requires at least one supplier group.', 16, 1);
    RETURN;
END;

BEGIN TRY
    /* 1. Create active supplier; optional lookups and TIN are exercised. */
    EXEC dbo.usp_Supplier_Create
        @SupplierCode = @TestCode,
        @SupplierName = 'CODEX SUPPLIER VERIFICATION',
        @SupplierGroupCode = @GroupCode,
        @AddressLine1 = 'Verification Address',
        @ContactPerson = 'Verification Contact',
        @Telephone = '000-VERIFY',
        @Email = 'supplier.verify@example.com',
        @TinNo = @TinNo,
        @TermsCode = @TermsCode,
        @CurrencyCode = @CurrencyCode,
        @TaxProfileCode = @TaxProfileCode,
        @UserId = 'VERIFY';

    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.a_suppliers
        WHERE supp_code = @TestCode AND active_flag = 'Y'
    )
        RAISERROR('Verification failed: active supplier was not created.', 16, 1);

    SELECT @ModifiedDate = date_changed
    FROM dbo.a_suppliers
    WHERE supp_code = @TestCode;

    /* 2. Duplicate supplier code is rejected. */
    BEGIN TRY
        EXEC dbo.usp_Supplier_Create
            @SupplierCode = @TestCode,
            @SupplierName = 'DUPLICATE CODE',
            @SupplierGroupCode = @GroupCode,
            @UserId = 'VERIFY';
        RAISERROR('Verification failed: duplicate supplier code was accepted.', 16, 1);
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE 'SUPPLIER_DUPLICATE_CODE:%'
        BEGIN
            SET @ErrorMessage = ERROR_MESSAGE();
            RAISERROR(@ErrorMessage, 16, 1);
        END;
    END CATCH;

    /* 3. Blank supplier name is rejected. */
    BEGIN TRY
        EXEC dbo.usp_Supplier_Create
            @SupplierCode = @SecondCode,
            @SupplierName = '   ',
            @SupplierGroupCode = @GroupCode,
            @UserId = 'VERIFY';
        RAISERROR('Verification failed: blank supplier name was accepted.', 16, 1);
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE 'SUPPLIER_INVALID_NAME:%'
        BEGIN
            SET @ErrorMessage = ERROR_MESSAGE();
            RAISERROR(@ErrorMessage, 16, 1);
        END;
    END CATCH;

    /* 4-7. Unknown group, terms, currency, and tax profile are rejected. */
    BEGIN TRY
        EXEC dbo.usp_Supplier_Create @SecondCode, 'INVALID GROUP', '!BAD', @UserId = 'VERIFY';
        RAISERROR('Verification failed: invalid group was accepted.', 16, 1);
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE 'SUPPLIER_INVALID_GROUP:%'
        BEGIN SET @ErrorMessage = ERROR_MESSAGE(); RAISERROR(@ErrorMessage, 16, 1); END;
    END CATCH;

    BEGIN TRY
        EXEC dbo.usp_Supplier_Create
            @SupplierCode = @SecondCode,
            @SupplierName = 'INVALID TERMS',
            @SupplierGroupCode = @GroupCode,
            @TermsCode = '!BAD',
            @UserId = 'VERIFY';
        RAISERROR('Verification failed: invalid terms were accepted.', 16, 1);
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE 'SUPPLIER_INVALID_TERMS:%'
        BEGIN SET @ErrorMessage = ERROR_MESSAGE(); RAISERROR(@ErrorMessage, 16, 1); END;
    END CATCH;

    BEGIN TRY
        EXEC dbo.usp_Supplier_Create
            @SupplierCode = @SecondCode,
            @SupplierName = 'INVALID CURRENCY',
            @SupplierGroupCode = @GroupCode,
            @CurrencyCode = '!BAD',
            @UserId = 'VERIFY';
        RAISERROR('Verification failed: invalid currency was accepted.', 16, 1);
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE 'SUPPLIER_INVALID_CURRENCY:%'
        BEGIN SET @ErrorMessage = ERROR_MESSAGE(); RAISERROR(@ErrorMessage, 16, 1); END;
    END CATCH;

    BEGIN TRY
        EXEC dbo.usp_Supplier_Create
            @SupplierCode = @SecondCode,
            @SupplierName = 'INVALID TAX PROFILE',
            @SupplierGroupCode = @GroupCode,
            @TaxProfileCode = '!BAD',
            @UserId = 'VERIFY';
        RAISERROR('Verification failed: invalid tax profile was accepted.', 16, 1);
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE 'SUPPLIER_INVALID_TAX_PROFILE:%'
        BEGIN SET @ErrorMessage = ERROR_MESSAGE(); RAISERROR(@ErrorMessage, 16, 1); END;
    END CATCH;

    /* 8. Punctuation-insensitive duplicate TIN is rejected. */
    BEGIN TRY
        EXEC dbo.usp_Supplier_Create
            @SupplierCode = @SecondCode,
            @SupplierName = 'DUPLICATE TIN',
            @SupplierGroupCode = @GroupCode,
            @TinNo = @TinNo,
            @UserId = 'VERIFY';
        RAISERROR('Verification failed: duplicate normalized TIN was accepted.', 16, 1);
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE 'SUPPLIER_DUPLICATE_TIN:%'
        BEGIN SET @ErrorMessage = ERROR_MESSAGE(); RAISERROR(@ErrorMessage, 16, 1); END;
    END CATCH;

    /* 9. Update and 10. stale-token rejection. */
    EXEC dbo.usp_Supplier_Update
        @SupplierCode = @TestCode,
        @SupplierName = 'CODEX SUPPLIER VERIFICATION UPDATED',
        @SupplierGroupCode = @GroupCode,
        @AddressLine1 = 'Updated Verification Address',
        @TinNo = @TinNo,
        @TermsCode = @TermsCode,
        @CurrencyCode = @CurrencyCode,
        @TaxProfileCode = @TaxProfileCode,
        @ExpectedModifiedDate = @ModifiedDate,
        @UserId = 'VERIFY';

    SELECT @UpdatedDate = date_changed
    FROM dbo.a_suppliers
    WHERE supp_code = @TestCode;

    IF @UpdatedDate <= @ModifiedDate
        RAISERROR('Verification failed: update concurrency token did not advance.', 16, 1);

    BEGIN TRY
        EXEC dbo.usp_Supplier_Update
            @SupplierCode = @TestCode,
            @SupplierName = 'STALE UPDATE',
            @SupplierGroupCode = @GroupCode,
            @ExpectedModifiedDate = @ModifiedDate,
            @UserId = 'VERIFY';
        RAISERROR('Verification failed: stale update was accepted.', 16, 1);
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE 'SUPPLIER_CONCURRENCY:%'
        BEGIN SET @ErrorMessage = ERROR_MESSAGE(); RAISERROR(@ErrorMessage, 16, 1); END;
    END CATCH;

    /* 11. A different supplier code cannot redirect an update. */
    BEGIN TRY
        EXEC dbo.usp_Supplier_Update
            @SupplierCode = @SecondCode,
            @SupplierName = 'CODE CHANGE ATTEMPT',
            @SupplierGroupCode = @GroupCode,
            @ExpectedModifiedDate = @UpdatedDate,
            @UserId = 'VERIFY';
        RAISERROR('Verification failed: supplier code change attempt was accepted.', 16, 1);
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() NOT LIKE 'SUPPLIER_NOT_FOUND:%'
        BEGIN SET @ErrorMessage = ERROR_MESSAGE(); RAISERROR(@ErrorMessage, 16, 1); END;
    END CATCH;

    /* 12. Deactivate; 14. exclude from active listing; 15. remain readable. */
    EXEC dbo.usp_Supplier_SetActiveStatus
        @SupplierCode = @TestCode,
        @ActiveFlag = 'N',
        @ExpectedModifiedDate = @UpdatedDate,
        @UserId = 'VERIFY';

    SELECT @ModifiedDate = date_changed
    FROM dbo.a_suppliers
    WHERE supp_code = @TestCode;

    IF EXISTS
    (
        SELECT 1 FROM dbo.a_suppliers
        WHERE supp_code = @TestCode AND active_flag = 'Y'
    )
        RAISERROR('Verification failed: supplier was not deactivated.', 16, 1);

    EXEC dbo.usp_Supplier_Query
        @Search = @TestCode,
        @ActiveFlag = 'Y',
        @Skip = 0,
        @Take = 50,
        @SortField = 'SupplierCode',
        @SortDirection = 'ASC';

    EXEC dbo.usp_Supplier_GetByCode @SupplierCode = @TestCode;

    /* 13. Reactivate. */
    EXEC dbo.usp_Supplier_SetActiveStatus
        @SupplierCode = @TestCode,
        @ActiveFlag = 'Y',
        @ExpectedModifiedDate = @ModifiedDate,
        @UserId = 'VERIFY';

    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.a_suppliers
        WHERE supp_code = @TestCode AND active_flag = 'Y'
    )
        RAISERROR('Verification failed: supplier was not reactivated.', 16, 1);

    /* 16-20. Execute paging/filter and each supported search field. */
    EXEC dbo.usp_Supplier_Query @SupplierGroupCode = @GroupCode, @Skip = 0, @Take = 1, @SortField = 'ModifiedDate', @SortDirection = 'DESC';
    EXEC dbo.usp_Supplier_Query @Search = @TestCode, @ActiveFlag = 'ALL', @Skip = 0, @Take = 50;
    EXEC dbo.usp_Supplier_Query @Search = 'CODEX SUPPLIER VERIFICATION UPDATED', @ActiveFlag = 'ALL', @Skip = 0, @Take = 50;
    EXEC dbo.usp_Supplier_Query @Search = @TinNo, @ActiveFlag = 'ALL', @Skip = 0, @Take = 50;
    EXEC dbo.usp_Supplier_Query @Search = 'Verification Contact', @ActiveFlag = 'ALL', @Skip = 0, @Take = 50;
    EXEC dbo.usp_Supplier_Query @Search = 'supplier.verify@example.com', @ActiveFlag = 'ALL', @Skip = 0, @Take = 50;

    EXEC dbo.usp_Supplier_GetGroups;
    EXEC dbo.usp_Supplier_GetTerms;
    EXEC dbo.usp_Supplier_GetCurrencies;
    EXEC dbo.usp_Supplier_GetTaxProfiles;

    DELETE FROM dbo.a_suppliers
    WHERE supp_code IN (@TestCode, @SecondCode);

    SELECT VerificationResult = 'PASS';
END TRY
BEGIN CATCH
    SET @ErrorMessage = ERROR_MESSAGE();

    DELETE FROM dbo.a_suppliers
    WHERE supp_code IN (@TestCode, @SecondCode);

    RAISERROR(@ErrorMessage, 16, 1);
END CATCH;
