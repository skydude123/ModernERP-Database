/*
    MODERN ERP - Supplier Price Management for Purchase Orders

    Deployment order:
      1. Run this script against an authorized development/test RISCDB database.
      2. Deploy the matching ASP.NET Core API.
      3. Deploy the matching Angular application.

    Compatibility:
      - Written for database compatibility level 100 (SQL Server 2008 syntax).
      - Legacy dbo.a_supplier_pricelist and dbo.a_item_um_conv are read only here.
      - Existing dbo.PurchaseOrderDetailUpsertType is not changed. A companion
        type/procedure preserves the authoritative decimal(18,4) conversion
        factor after the legacy PO save procedure runs, in the same transaction.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.SupplierItemPriceMaster', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SupplierItemPriceMaster
    (
        supplier_code  VARCHAR(10)     NOT NULL,
        item_code      VARCHAR(20)     NOT NULL,
        price_um       VARCHAR(3)      NOT NULL,
        unit_price     DECIMAL(18,4)   NOT NULL,
        effective_date DATE            NOT NULL,
        is_active      BIT             NOT NULL
            CONSTRAINT DF_SupplierItemPriceMaster_IsActive DEFAULT (1),
        remarks        NVARCHAR(500)   NULL,
        created_by     VARCHAR(10)     NOT NULL,
        created_at     DATETIME2(3)    NOT NULL
            CONSTRAINT DF_SupplierItemPriceMaster_CreatedAt DEFAULT (SYSUTCDATETIME()),
        modified_by    VARCHAR(10)     NOT NULL,
        modified_at    DATETIME2(3)    NOT NULL
            CONSTRAINT DF_SupplierItemPriceMaster_ModifiedAt DEFAULT (SYSUTCDATETIME()),
        row_version    ROWVERSION      NOT NULL,

        CONSTRAINT PK_SupplierItemPriceMaster
            PRIMARY KEY CLUSTERED (supplier_code, item_code, price_um),
        CONSTRAINT CK_SupplierItemPriceMaster_UnitPrice
            CHECK (unit_price >= 0),
        CONSTRAINT FK_SupplierItemPriceMaster_Supplier
            FOREIGN KEY (supplier_code) REFERENCES dbo.a_suppliers (supp_code),
        CONSTRAINT FK_SupplierItemPriceMaster_Item
            FOREIGN KEY (item_code) REFERENCES dbo.a_item_master (item_code),
        CONSTRAINT FK_SupplierItemPriceMaster_Um
            FOREIGN KEY (price_um) REFERENCES dbo.a_um (um)
    );
END;
GO

IF OBJECT_ID(N'dbo.SupplierItemPriceHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SupplierItemPriceHistory
    (
        history_id      BIGINT IDENTITY(1,1) NOT NULL,
        supplier_code   VARCHAR(10)          NOT NULL,
        item_code       VARCHAR(20)          NOT NULL,
        price_um        VARCHAR(3)           NOT NULL,
        old_price       DECIMAL(18,4)        NULL,
        new_price       DECIMAL(18,4)        NOT NULL,
        effective_date  DATE                 NOT NULL,
        source_type     VARCHAR(30)          NOT NULL,
        source_reference VARCHAR(50)         NULL,
        remarks         NVARCHAR(500)        NULL,
        old_is_active   BIT                  NULL,
        new_is_active   BIT                  NOT NULL,
        changed_by      VARCHAR(10)          NOT NULL,
        changed_at      DATETIME2(3)         NOT NULL
            CONSTRAINT DF_SupplierItemPriceHistory_ChangedAt DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_SupplierItemPriceHistory
            PRIMARY KEY CLUSTERED (history_id),
        CONSTRAINT CK_SupplierItemPriceHistory_Prices
            CHECK ((old_price IS NULL OR old_price >= 0) AND new_price >= 0),
        CONSTRAINT FK_SupplierItemPriceHistory_Supplier
            FOREIGN KEY (supplier_code) REFERENCES dbo.a_suppliers (supp_code),
        CONSTRAINT FK_SupplierItemPriceHistory_Item
            FOREIGN KEY (item_code) REFERENCES dbo.a_item_master (item_code),
        CONSTRAINT FK_SupplierItemPriceHistory_Um
            FOREIGN KEY (price_um) REFERENCES dbo.a_um (um)
    );
END;
GO

/*
    History rows are written explicitly by usp_PurchasePrice_Upsert.
    This trigger only enforces append-only immutability; it is not the
    mechanism that creates audit history.
*/
IF OBJECT_ID(N'dbo.trg_SupplierItemPriceHistory_AppendOnly', N'TR') IS NULL
    EXEC(N'
        CREATE TRIGGER dbo.trg_SupplierItemPriceHistory_AppendOnly
        ON dbo.SupplierItemPriceHistory
        AFTER INSERT
        AS
        BEGIN
            SET NOCOUNT ON;
        END;');
GO

ALTER TRIGGER dbo.trg_SupplierItemPriceHistory_AppendOnly
ON dbo.SupplierItemPriceHistory
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    RAISERROR('PURCHASE_PRICE_HISTORY_APPEND_ONLY: Supplier price history cannot be updated or deleted.', 16, 1);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.SupplierItemPriceMaster')
      AND name = N'IX_SupplierItemPriceMaster_ItemUmCurrent'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_SupplierItemPriceMaster_ItemUmCurrent
        ON dbo.SupplierItemPriceMaster
        (
            item_code,
            price_um,
            is_active,
            effective_date,
            supplier_code
        )
        INCLUDE (unit_price, modified_at);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.SupplierItemPriceHistory')
      AND name = N'IX_SupplierItemPriceHistory_ItemUmChangedAt'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_SupplierItemPriceHistory_ItemUmChangedAt
        ON dbo.SupplierItemPriceHistory
        (item_code, price_um, changed_at DESC, supplier_code)
        INCLUDE (old_price, new_price, effective_date, source_type, changed_by);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.a_po_det')
      AND name = N'IX_a_po_det_PriceHistory'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_a_po_det_PriceHistory
        ON dbo.a_po_det (item_code, po_um, date_changed DESC)
        INCLUDE (po_no, po_seq, unit_price, po_conv_factor);
END;
GO

IF TYPE_ID(N'dbo.PurchaseOrderPricingDetailType') IS NULL
BEGIN
    EXEC(N'
        CREATE TYPE dbo.PurchaseOrderPricingDetailType AS TABLE
        (
            row_no         INT             NOT NULL,
            po_line_no     INT             NULL,
            item_code      VARCHAR(20)     NOT NULL,
            po_um          VARCHAR(3)      NOT NULL,
            po_conv_factor DECIMAL(18,4)   NOT NULL,
            PRIMARY KEY (row_no)
        );');
END;
GO

IF OBJECT_ID(N'dbo.usp_PurchasePrice_ItemUms', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PurchasePrice_ItemUms AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PurchasePrice_ItemUms
    @item_code VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');

    SELECT
        LTRIM(RTRIM(c.item_code)) AS ItemCode,
        LTRIM(RTRIM(c.from_um)) AS PoUm,
        ISNULL(NULLIF(LTRIM(RTRIM(u.um_desc)), ''), LTRIM(RTRIM(c.from_um))) AS UmDescription,
        CAST(c.conv_factor AS DECIMAL(18,4)) AS ConversionFactor,
        LTRIM(RTRIM(c.base_um)) AS BaseUm
    FROM dbo.a_item_um_conv c
    INNER JOIN dbo.a_item_master i
        ON i.item_code = c.item_code
       AND LOWER(i.active) = 'y'
       AND LTRIM(RTRIM(i.um)) = LTRIM(RTRIM(c.base_um))
    INNER JOIN dbo.a_um u
        ON LTRIM(RTRIM(u.um)) = LTRIM(RTRIM(c.from_um))
    INNER JOIN dbo.a_um bu
        ON LTRIM(RTRIM(bu.um)) = LTRIM(RTRIM(c.base_um))
    WHERE LTRIM(RTRIM(c.item_code)) = @item_code
      AND c.conv_factor > 0
    ORDER BY
        CASE WHEN LTRIM(RTRIM(c.from_um)) = LTRIM(RTRIM(c.base_um)) THEN 0 ELSE 1 END,
        c.from_um;
END;
GO

IF OBJECT_ID(N'dbo.usp_PurchasePrice_SupplierList', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PurchasePrice_SupplierList AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PurchasePrice_SupplierList
    @supplier_code VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SET @supplier_code = NULLIF(LTRIM(RTRIM(@supplier_code)), '');

    /*
        Return one bounded preload plus one sentinel row. The application rejects
        5,001 rows so the desktop lookup never silently truncates a large result.
    */
    SELECT TOP (5001)
        p.supplier_code AS SupplierCode,
        LTRIM(RTRIM(s.supp_name)) AS SupplierName,
        p.item_code AS ItemCode,
        LTRIM(RTRIM(i.item_desc)) AS ItemDescription,
        p.price_um AS PoUm,
        umc.BaseUm,
        umc.PoConvFactor,
        p.unit_price AS UnitPrice,
        p.effective_date AS EffectiveDate,
        p.modified_at AS DateChanged,
        p.is_active AS IsActive
    FROM dbo.SupplierItemPriceMaster p
    INNER JOIN dbo.a_suppliers s
        ON s.supp_code = p.supplier_code
       AND s.active_flag = 'Y'
    INNER JOIN dbo.a_item_master i
        ON i.item_code = p.item_code
       AND LOWER(i.active) = 'y'
    CROSS APPLY
    (
        SELECT TOP (1)
            LTRIM(RTRIM(c.base_um)) AS BaseUm,
            CAST(c.conv_factor AS DECIMAL(18,4)) AS PoConvFactor
        FROM dbo.a_item_um_conv c
        INNER JOIN dbo.a_um u
            ON LTRIM(RTRIM(u.um)) = LTRIM(RTRIM(c.from_um))
        INNER JOIN dbo.a_um bu
            ON LTRIM(RTRIM(bu.um)) = LTRIM(RTRIM(c.base_um))
        WHERE LTRIM(RTRIM(c.item_code)) = LTRIM(RTRIM(p.item_code))
          AND LTRIM(RTRIM(c.from_um)) = LTRIM(RTRIM(p.price_um))
          AND LTRIM(RTRIM(i.um)) = LTRIM(RTRIM(c.base_um))
          AND c.conv_factor > 0
        ORDER BY c.date_changed DESC, c.base_um, c.conv_factor DESC
    ) umc
    WHERE p.supplier_code = @supplier_code
      AND p.is_active = 1
      AND p.effective_date <= CAST(GETDATE() AS DATE)
    ORDER BY ItemDescription, ItemCode, PoUm;
END;
GO

IF OBJECT_ID(N'dbo.usp_PurchasePrice_Resolve', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PurchasePrice_Resolve AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PurchasePrice_Resolve
    @supplier_code VARCHAR(10),
    @item_code     VARCHAR(20),
    @po_um         VARCHAR(3),
    @as_of_date    DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @supplier_code = NULLIF(LTRIM(RTRIM(@supplier_code)), '');
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');
    SET @po_um = NULLIF(LTRIM(RTRIM(@po_um)), '');
    SET @as_of_date = ISNULL(@as_of_date, CAST(GETDATE() AS DATE));

    DECLARE @item_description VARCHAR(60);
    DECLARE @conversion_factor DECIMAL(18,4);
    DECLARE @base_um VARCHAR(3);
    DECLARE @master_price DECIMAL(18,4);
    DECLARE @master_effective_date DATE;
    DECLARE @master_row_version BINARY(8);
    DECLARE @configured_master_price DECIMAL(18,4);
    DECLARE @configured_master_effective_date DATE;
    DECLARE @configured_master_is_active BIT;
    DECLARE @configured_master_remarks NVARCHAR(500);
    DECLARE @configured_master_row_version BINARY(8);
    DECLARE @legacy_price DECIMAL(18,4);
    DECLARE @legacy_converted_price DECIMAL(18,4);
    DECLARE @legacy_compatible BIT;
    DECLARE @last_po_price DECIMAL(18,4);
    DECLARE @last_po_no VARCHAR(10);
    DECLARE @last_po_date DATETIME;
    DECLARE @suggested_price DECIMAL(18,4);
    DECLARE @suggested_source VARCHAR(30);

    SELECT @item_description = LTRIM(RTRIM(item_desc))
    FROM dbo.a_item_master
    WHERE LTRIM(RTRIM(item_code)) = @item_code;

    SELECT TOP (1)
        @conversion_factor = CAST(c.conv_factor AS DECIMAL(18,4)),
        @base_um = LTRIM(RTRIM(c.base_um))
    FROM dbo.a_item_um_conv c
    INNER JOIN dbo.a_item_master i
        ON i.item_code = c.item_code
       AND LOWER(i.active) = 'y'
       AND LTRIM(RTRIM(i.um)) = LTRIM(RTRIM(c.base_um))
    INNER JOIN dbo.a_um u
        ON LTRIM(RTRIM(u.um)) = LTRIM(RTRIM(c.from_um))
    WHERE LTRIM(RTRIM(c.item_code)) = @item_code
      AND LTRIM(RTRIM(c.from_um)) = @po_um
      AND c.conv_factor > 0;

    IF @conversion_factor IS NOT NULL
    BEGIN
        SELECT
            @configured_master_price = p.unit_price,
            @configured_master_effective_date = p.effective_date,
            @configured_master_is_active = p.is_active,
            @configured_master_remarks = p.remarks,
            @configured_master_row_version = p.row_version
        FROM dbo.SupplierItemPriceMaster p
        WHERE p.supplier_code = @supplier_code
          AND p.item_code = @item_code
          AND p.price_um = @po_um;

        IF @configured_master_is_active = 1
           AND @configured_master_effective_date <= @as_of_date
        BEGIN
            SET @master_price = @configured_master_price;
            SET @master_effective_date = @configured_master_effective_date;
            SET @master_row_version = @configured_master_row_version;
        END;

        SELECT
            @legacy_price = CAST(l.unit_price AS DECIMAL(18,4))
        FROM dbo.a_supplier_pricelist l
        WHERE LTRIM(RTRIM(l.item_code)) = @item_code;

        SET @legacy_compatible = CASE WHEN @legacy_price IS NULL THEN 0 ELSE 1 END;
        SET @legacy_converted_price =
            CASE
                WHEN @legacy_compatible = 1
                THEN CAST(@legacy_price * @conversion_factor AS DECIMAL(18,4))
                ELSE NULL
            END;

        SELECT TOP (1)
            @last_po_price = CAST(d.unit_price AS DECIMAL(18,4)),
            @last_po_no = LTRIM(RTRIM(h.po_no)),
            @last_po_date = h.po_date
        FROM dbo.a_po_hdr h
        INNER JOIN dbo.a_po_det d
            ON d.po_no = h.po_no
        WHERE LTRIM(RTRIM(h.supp_code)) = @supplier_code
          AND LTRIM(RTRIM(d.item_code)) = @item_code
          AND LTRIM(RTRIM(d.po_um)) = @po_um
          AND ISNULL(h.status, '') <> 'C'
          AND d.unit_price > 0
        ORDER BY h.po_date DESC, d.date_changed DESC, h.po_no DESC, d.po_seq DESC;

        SET @suggested_price =
            CASE
                WHEN @master_price IS NOT NULL THEN @master_price
                WHEN @legacy_converted_price IS NOT NULL THEN @legacy_converted_price
                WHEN @last_po_price IS NOT NULL THEN @last_po_price
                ELSE NULL
            END;

        SET @suggested_source =
            CASE
                WHEN @master_price IS NOT NULL THEN 'SUPPLIER_MASTER'
                WHEN @legacy_converted_price IS NOT NULL THEN 'LEGACY_DEFAULT'
                WHEN @last_po_price IS NOT NULL THEN 'LAST_ACTUAL_PO'
                ELSE 'NONE'
            END;
    END
    ELSE
    BEGIN
        SET @legacy_compatible = 0;
        SET @suggested_source = 'INVALID_UM';
    END;

    SELECT
        @supplier_code AS SupplierCode,
        @item_code AS ItemCode,
        ISNULL(@item_description, '') AS ItemDescription,
        @po_um AS PoUm,
        @conversion_factor AS PoConvFactor,
        @base_um AS BaseUm,
        CAST(CASE WHEN @conversion_factor IS NULL THEN 0 ELSE 1 END AS BIT) AS IsUmValid,
        @suggested_price AS SuggestedPrice,
        @suggested_source AS SuggestedSource,
        @master_price AS CurrentSupplierMasterPrice,
        @master_effective_date AS CurrentSupplierEffectiveDate,
        @master_row_version AS CurrentSupplierRowVersion,
        @configured_master_price AS ConfiguredSupplierMasterPrice,
        @configured_master_effective_date AS ConfiguredSupplierEffectiveDate,
        @configured_master_is_active AS ConfiguredSupplierIsActive,
        @configured_master_remarks AS ConfiguredSupplierRemarks,
        @configured_master_row_version AS ConfiguredSupplierRowVersion,
        @last_po_price AS LastActualPoPrice,
        @last_po_no AS LastActualPoNo,
        @last_po_date AS LastActualPoDate,
        @legacy_price AS LegacyPrice,
        @legacy_converted_price AS LegacyConvertedPrice,
        ISNULL(@legacy_compatible, 0) AS IsLegacyUmCompatible;
END;
GO

IF OBJECT_ID(N'dbo.usp_PurchasePrice_CurrentPage', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PurchasePrice_CurrentPage AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PurchasePrice_CurrentPage
    @supplier_code VARCHAR(10) = NULL,
    @item_code     VARCHAR(20) = NULL,
    @po_um         VARCHAR(3) = NULL,
    @active        VARCHAR(3) = 'ALL',
    @as_of_date    DATE = NULL,
    @skip          INT = 0,
    @take          INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SET @supplier_code = NULLIF(LTRIM(RTRIM(@supplier_code)), '');
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');
    SET @po_um = NULLIF(LTRIM(RTRIM(@po_um)), '');
    SET @active = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@active)), ''), 'ALL'));
    SET @as_of_date = ISNULL(@as_of_date, CAST(GETDATE() AS DATE));
    SET @skip = CASE WHEN ISNULL(@skip, 0) < 0 THEN 0 ELSE ISNULL(@skip, 0) END;
    SET @take = CASE WHEN ISNULL(@take, 0) < 1 THEN 50 WHEN @take > 250 THEN 250 ELSE @take END;

    ;WITH SourceRows AS
    (
        SELECT
            p.supplier_code AS SupplierCode,
            LTRIM(RTRIM(s.supp_name)) AS SupplierName,
            p.item_code AS ItemCode,
            LTRIM(RTRIM(i.item_desc)) AS ItemDescription,
            p.price_um AS PoUm,
            p.unit_price AS UnitPrice,
            p.effective_date AS EffectiveDate,
            p.is_active AS IsActive,
            p.remarks AS Remarks,
            p.created_by AS CreatedBy,
            p.created_at AS CreatedAt,
            p.modified_by AS ModifiedBy,
            p.modified_at AS ModifiedAt,
            p.row_version AS RowVersion
        FROM dbo.SupplierItemPriceMaster p
        INNER JOIN dbo.a_suppliers s ON s.supp_code = p.supplier_code
        INNER JOIN dbo.a_item_master i ON i.item_code = p.item_code
        WHERE (@supplier_code IS NULL OR p.supplier_code = @supplier_code)
          AND (@item_code IS NULL OR p.item_code = @item_code)
          AND (@po_um IS NULL OR p.price_um = @po_um)
          AND
          (
              @active = 'ALL'
              OR (@active = 'Y' AND p.is_active = 1 AND p.effective_date <= @as_of_date)
              OR (@active = 'N' AND (p.is_active = 0 OR p.effective_date > @as_of_date))
          )
    ),
    NumberedRows AS
    (
        SELECT *, ROW_NUMBER() OVER
        (
            ORDER BY ItemDescription, SupplierName, PoUm, SupplierCode
        ) AS RowNumber
        FROM SourceRows
    )
    SELECT
        SupplierCode, SupplierName, ItemCode, ItemDescription, PoUm,
        UnitPrice, EffectiveDate, IsActive, Remarks, CreatedBy, CreatedAt,
        ModifiedBy, ModifiedAt, RowVersion
    FROM NumberedRows
    WHERE RowNumber > @skip AND RowNumber <= @skip + @take
    ORDER BY RowNumber;

    SELECT COUNT_BIG(1) AS Total
    FROM dbo.SupplierItemPriceMaster p
    WHERE (@supplier_code IS NULL OR p.supplier_code = @supplier_code)
      AND (@item_code IS NULL OR p.item_code = @item_code)
      AND (@po_um IS NULL OR p.price_um = @po_um)
      AND
      (
          @active = 'ALL'
          OR (@active = 'Y' AND p.is_active = 1 AND p.effective_date <= @as_of_date)
          OR (@active = 'N' AND (p.is_active = 0 OR p.effective_date > @as_of_date))
      );
END;
GO

IF OBJECT_ID(N'dbo.usp_PurchasePrice_Inquiry', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PurchasePrice_Inquiry AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PurchasePrice_Inquiry
    @supplier_code VARCHAR(10),
    @item_code     VARCHAR(20),
    @po_um         VARCHAR(3),
    @as_of_date    DATE = NULL,
    @skip          INT = 0,
    @take          INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SET @supplier_code = NULLIF(LTRIM(RTRIM(@supplier_code)), '');
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');
    SET @po_um = NULLIF(LTRIM(RTRIM(@po_um)), '');
    SET @as_of_date = ISNULL(@as_of_date, CAST(GETDATE() AS DATE));
    SET @skip = CASE WHEN ISNULL(@skip, 0) < 0 THEN 0 ELSE ISNULL(@skip, 0) END;
    SET @take = CASE WHEN ISNULL(@take, 0) < 1 THEN 50 WHEN @take > 250 THEN 250 ELSE @take END;

    EXEC dbo.usp_PurchasePrice_Resolve
        @supplier_code = @supplier_code,
        @item_code = @item_code,
        @po_um = @po_um,
        @as_of_date = @as_of_date;

    ;WITH SourceRows AS
    (
        SELECT
            p.supplier_code AS SupplierCode,
            LTRIM(RTRIM(s.supp_name)) AS SupplierName,
            p.item_code AS ItemCode,
            p.price_um AS PoUm,
            p.unit_price AS UnitPrice,
            p.effective_date AS EffectiveDate,
            p.modified_at AS ModifiedAt,
            p.is_active AS IsActive,
            CAST
            (
                CASE
                    WHEN p.is_active = 1 AND p.effective_date <= @as_of_date THEN 1
                    ELSE 0
                END AS BIT
            ) AS IsCurrent,
            CAST(CASE WHEN p.supplier_code = @supplier_code THEN 1 ELSE 0 END AS BIT) AS IsSelectedSupplier
        FROM dbo.SupplierItemPriceMaster p
        INNER JOIN dbo.a_suppliers s ON s.supp_code = p.supplier_code
        WHERE p.item_code = @item_code
          AND p.price_um = @po_um
    ),
    NumberedRows AS
    (
        SELECT *, ROW_NUMBER() OVER
        (
            ORDER BY UnitPrice, SupplierName, SupplierCode
        ) AS RowNumber
        FROM SourceRows
    )
    SELECT
        SupplierCode, SupplierName, ItemCode, PoUm, UnitPrice,
        EffectiveDate, ModifiedAt, IsActive, IsCurrent, IsSelectedSupplier
    FROM NumberedRows
    WHERE RowNumber > @skip AND RowNumber <= @skip + @take
    ORDER BY RowNumber;

    SELECT
        COUNT_BIG(1) AS Total,
        MIN
        (
            CASE
                WHEN p.is_active = 1 AND p.effective_date <= @as_of_date
                THEN p.unit_price
                ELSE NULL
            END
        ) AS LowestConfiguredPrice,
        MAX
        (
            CASE
                WHEN p.is_active = 1 AND p.effective_date <= @as_of_date
                THEN p.unit_price
                ELSE NULL
            END
        ) AS HighestConfiguredPrice
    FROM dbo.SupplierItemPriceMaster p
    WHERE p.item_code = @item_code
      AND p.price_um = @po_um;
END;
GO

IF OBJECT_ID(N'dbo.usp_PurchasePrice_Upsert', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PurchasePrice_Upsert AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PurchasePrice_Upsert
    @supplier_code      VARCHAR(10),
    @item_code          VARCHAR(20),
    @po_um              VARCHAR(3),
    @unit_price         DECIMAL(18,4),
    @effective_date     DATE,
    @is_active          BIT,
    @remarks            NVARCHAR(500) = NULL,
    @source_reference   VARCHAR(50) = NULL,
    @expected_row_version BINARY(8) = NULL,
    @user_id            VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @supplier_code = NULLIF(LTRIM(RTRIM(@supplier_code)), '');
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');
    SET @po_um = NULLIF(LTRIM(RTRIM(@po_um)), '');
    SET @remarks = NULLIF(LTRIM(RTRIM(@remarks)), '');
    SET @source_reference = NULLIF(LTRIM(RTRIM(@source_reference)), '');
    SET @user_id = NULLIF(LTRIM(RTRIM(@user_id)), '');

    IF @supplier_code IS NULL OR LEN(@supplier_code) > 10
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: Supplier code is required and cannot exceed 10 characters.', 16, 1);
        RETURN;
    END;
    IF @item_code IS NULL OR LEN(@item_code) > 20
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: Item code is required and cannot exceed 20 characters.', 16, 1);
        RETURN;
    END;
    IF @po_um IS NULL OR LEN(@po_um) > 3
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: Price U/M is required and cannot exceed 3 characters.', 16, 1);
        RETURN;
    END;
    IF @unit_price IS NULL OR @unit_price < 0
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: Unit price must be zero or greater.', 16, 1);
        RETURN;
    END;
    IF @effective_date IS NULL
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: Effective date is required.', 16, 1);
        RETURN;
    END;
    IF @user_id IS NULL OR LEN(@user_id) > 10
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: Authenticated user is required.', 16, 1);
        RETURN;
    END;
    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.a_suppliers
        WHERE supp_code = @supplier_code AND active_flag = 'Y'
    )
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: Supplier is invalid or inactive.', 16, 1);
        RETURN;
    END;
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.a_item_um_conv c
        INNER JOIN dbo.a_item_master i
            ON i.item_code = c.item_code
           AND LOWER(i.active) = 'y'
           AND LTRIM(RTRIM(i.um)) = LTRIM(RTRIM(c.base_um))
        INNER JOIN dbo.a_um u
            ON LTRIM(RTRIM(u.um)) = LTRIM(RTRIM(c.from_um))
        WHERE LTRIM(RTRIM(c.item_code)) = @item_code
          AND LTRIM(RTRIM(c.from_um)) = @po_um
          AND c.conv_factor > 0
    )
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: Item/U/M conversion is missing or invalid.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @old_price DECIMAL(18,4);
        DECLARE @old_effective_date DATE;
        DECLARE @old_is_active BIT;
        DECLARE @old_remarks NVARCHAR(500);
        DECLARE @actual_row_version BINARY(8);
        DECLARE @exists BIT;
        DECLARE @changed BIT;
        DECLARE @now DATETIME2(3);

        SET @now = SYSUTCDATETIME();
        SET @exists = 0;
        SET @changed = 0;

        SELECT
            @exists = 1,
            @old_price = unit_price,
            @old_effective_date = effective_date,
            @old_is_active = is_active,
            @old_remarks = remarks,
            @actual_row_version = row_version
        FROM dbo.SupplierItemPriceMaster WITH (UPDLOCK, HOLDLOCK)
        WHERE supplier_code = @supplier_code
          AND item_code = @item_code
          AND price_um = @po_um;

        IF @exists = 1 AND @expected_row_version IS NULL
            RAISERROR('PURCHASE_PRICE_CONFLICT: Refresh the current supplier price before updating it.', 16, 1);
        IF @exists = 1 AND @expected_row_version <> @actual_row_version
            RAISERROR('PURCHASE_PRICE_CONFLICT: The supplier price was changed by another user. Refresh and try again.', 16, 1);

        IF @exists = 0
        BEGIN
            INSERT dbo.SupplierItemPriceMaster
            (
                supplier_code, item_code, price_um, unit_price,
                effective_date, is_active, remarks,
                created_by, created_at, modified_by, modified_at
            )
            VALUES
            (
                @supplier_code, @item_code, @po_um, @unit_price,
                @effective_date, @is_active, @remarks,
                @user_id, @now, @user_id, @now
            );

            SET @changed = 1;
        END
        ELSE IF
        (
            @old_price <> @unit_price
            OR @old_effective_date <> @effective_date
            OR @old_is_active <> @is_active
            OR ISNULL(@old_remarks, N'') <> ISNULL(@remarks, N'')
        )
        BEGIN
            UPDATE dbo.SupplierItemPriceMaster
            SET unit_price = @unit_price,
                effective_date = @effective_date,
                is_active = @is_active,
                remarks = @remarks,
                modified_by = @user_id,
                modified_at = @now
            WHERE supplier_code = @supplier_code
              AND item_code = @item_code
              AND price_um = @po_um
              AND row_version = @actual_row_version;

            IF @@ROWCOUNT <> 1
                RAISERROR('PURCHASE_PRICE_CONFLICT: The supplier price was changed by another user. Refresh and try again.', 16, 1);

            SET @changed = 1;
        END;

        IF @changed = 1
        BEGIN
            INSERT dbo.SupplierItemPriceHistory
            (
                supplier_code, item_code, price_um,
                old_price, new_price, effective_date,
                source_type, source_reference, remarks,
                old_is_active, new_is_active, changed_by, changed_at
            )
            VALUES
            (
                @supplier_code, @item_code, @po_um,
                CASE WHEN @exists = 1 THEN @old_price ELSE NULL END,
                @unit_price, @effective_date,
                CASE WHEN @exists = 1 THEN 'MASTER_UPDATE' ELSE 'MASTER_CREATE' END,
                @source_reference, @remarks,
                CASE WHEN @exists = 1 THEN @old_is_active ELSE NULL END,
                @is_active, @user_id, @now
            );
        END;

        COMMIT TRANSACTION;

        SELECT
            p.supplier_code AS SupplierCode,
            LTRIM(RTRIM(s.supp_name)) AS SupplierName,
            p.item_code AS ItemCode,
            LTRIM(RTRIM(i.item_desc)) AS ItemDescription,
            p.price_um AS PoUm,
            p.unit_price AS UnitPrice,
            p.effective_date AS EffectiveDate,
            p.is_active AS IsActive,
            p.remarks AS Remarks,
            p.created_by AS CreatedBy,
            p.created_at AS CreatedAt,
            p.modified_by AS ModifiedBy,
            p.modified_at AS ModifiedAt,
            p.row_version AS RowVersion,
            @changed AS WasChanged
        FROM dbo.SupplierItemPriceMaster p
        INNER JOIN dbo.a_suppliers s ON s.supp_code = p.supplier_code
        INNER JOIN dbo.a_item_master i ON i.item_code = p.item_code
        WHERE p.supplier_code = @supplier_code
          AND p.item_code = @item_code
          AND p.price_um = @po_um;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @error_message NVARCHAR(4000);
        SET @error_message = ERROR_MESSAGE();
        RAISERROR(@error_message, 16, 1);
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.usp_PurchasePrice_MasterHistoryPage', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PurchasePrice_MasterHistoryPage AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PurchasePrice_MasterHistoryPage
    @supplier_code VARCHAR(10) = NULL,
    @item_code     VARCHAR(20),
    @po_um         VARCHAR(3),
    @from_date     DATE = NULL,
    @to_date       DATE = NULL,
    @skip          INT = 0,
    @take          INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET @supplier_code = NULLIF(LTRIM(RTRIM(@supplier_code)), '');
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');
    SET @po_um = NULLIF(LTRIM(RTRIM(@po_um)), '');
    SET @skip = CASE WHEN ISNULL(@skip, 0) < 0 THEN 0 ELSE ISNULL(@skip, 0) END;
    SET @take = CASE WHEN ISNULL(@take, 0) < 1 THEN 50 WHEN @take > 250 THEN 250 ELSE @take END;

    ;WITH SourceRows AS
    (
        SELECT
            h.history_id AS HistoryId,
            h.supplier_code AS SupplierCode,
            LTRIM(RTRIM(s.supp_name)) AS SupplierName,
            h.item_code AS ItemCode,
            h.price_um AS PoUm,
            h.old_price AS OldPrice,
            h.new_price AS NewPrice,
            h.effective_date AS EffectiveDate,
            h.source_type AS SourceType,
            h.source_reference AS SourceReference,
            h.remarks AS Remarks,
            h.old_is_active AS OldIsActive,
            h.new_is_active AS NewIsActive,
            h.changed_by AS ChangedBy,
            h.changed_at AS ChangedAt
        FROM dbo.SupplierItemPriceHistory h
        INNER JOIN dbo.a_suppliers s ON s.supp_code = h.supplier_code
        WHERE (@supplier_code IS NULL OR h.supplier_code = @supplier_code)
          AND h.item_code = @item_code
          AND h.price_um = @po_um
          AND (@from_date IS NULL OR h.changed_at >= @from_date)
          AND (@to_date IS NULL OR h.changed_at < DATEADD(DAY, 1, @to_date))
    ),
    NumberedRows AS
    (
        SELECT *, ROW_NUMBER() OVER (ORDER BY ChangedAt DESC, HistoryId DESC) AS RowNumber
        FROM SourceRows
    )
    SELECT
        HistoryId, SupplierCode, SupplierName, ItemCode, PoUm,
        OldPrice, NewPrice, EffectiveDate, SourceType, SourceReference,
        Remarks, OldIsActive, NewIsActive, ChangedBy, ChangedAt
    FROM NumberedRows
    WHERE RowNumber > @skip AND RowNumber <= @skip + @take
    ORDER BY RowNumber;

    SELECT COUNT_BIG(1) AS Total
    FROM dbo.SupplierItemPriceHistory h
    WHERE (@supplier_code IS NULL OR h.supplier_code = @supplier_code)
      AND h.item_code = @item_code
      AND h.price_um = @po_um
      AND (@from_date IS NULL OR h.changed_at >= @from_date)
      AND (@to_date IS NULL OR h.changed_at < DATEADD(DAY, 1, @to_date));
END;
GO

IF OBJECT_ID(N'dbo.usp_PurchasePrice_ActualPoHistoryPage', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PurchasePrice_ActualPoHistoryPage AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PurchasePrice_ActualPoHistoryPage
    @supplier_code VARCHAR(10) = NULL,
    @item_code     VARCHAR(20),
    @po_um         VARCHAR(3),
    @from_date     DATE = NULL,
    @to_date       DATE = NULL,
    @skip          INT = 0,
    @take          INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET @supplier_code = NULLIF(LTRIM(RTRIM(@supplier_code)), '');
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');
    SET @po_um = NULLIF(LTRIM(RTRIM(@po_um)), '');
    SET @skip = CASE WHEN ISNULL(@skip, 0) < 0 THEN 0 ELSE ISNULL(@skip, 0) END;
    SET @take = CASE WHEN ISNULL(@take, 0) < 1 THEN 50 WHEN @take > 250 THEN 250 ELSE @take END;

    ;WITH SourceRows AS
    (
        SELECT
            LTRIM(RTRIM(h.po_no)) AS PoNo,
            d.po_seq AS PoLineNo,
            h.po_date AS PoDate,
            LTRIM(RTRIM(h.supp_code)) AS SupplierCode,
            LTRIM(RTRIM(s.supp_name)) AS SupplierName,
            LTRIM(RTRIM(d.item_code)) AS ItemCode,
            LTRIM(RTRIM(d.item_desc)) AS ItemDescription,
            LTRIM(RTRIM(d.po_um)) AS PoUm,
            CAST(d.po_conv_factor AS DECIMAL(18,4)) AS PoConvFactor,
            CAST(d.qty_po AS DECIMAL(18,2)) AS QtyPo,
            CAST(d.unit_price AS DECIMAL(18,4)) AS UnitPrice,
            LTRIM(RTRIM(h.status)) AS Status,
            LTRIM(RTRIM(d.user_id)) AS ChangedBy,
            d.date_changed AS ChangedAt
        FROM dbo.a_po_hdr h
        INNER JOIN dbo.a_po_det d ON d.po_no = h.po_no
        INNER JOIN dbo.a_suppliers s ON s.supp_code = h.supp_code
        WHERE (@supplier_code IS NULL OR LTRIM(RTRIM(h.supp_code)) = @supplier_code)
          AND LTRIM(RTRIM(d.item_code)) = @item_code
          AND LTRIM(RTRIM(d.po_um)) = @po_um
          AND ISNULL(h.status, '') <> 'C'
          AND d.unit_price > 0
          AND (@from_date IS NULL OR h.po_date >= @from_date)
          AND (@to_date IS NULL OR h.po_date < DATEADD(DAY, 1, @to_date))
    ),
    NumberedRows AS
    (
        SELECT *, ROW_NUMBER() OVER
        (
            ORDER BY PoDate DESC, ChangedAt DESC, PoNo DESC, PoLineNo DESC
        ) AS RowNumber
        FROM SourceRows
    )
    SELECT
        PoNo, PoLineNo, PoDate, SupplierCode, SupplierName,
        ItemCode, ItemDescription, PoUm, PoConvFactor, QtyPo,
        UnitPrice, Status, ChangedBy, ChangedAt
    FROM NumberedRows
    WHERE RowNumber > @skip AND RowNumber <= @skip + @take
    ORDER BY RowNumber;

    SELECT COUNT_BIG(1) AS Total
    FROM dbo.a_po_hdr h
    INNER JOIN dbo.a_po_det d ON d.po_no = h.po_no
    WHERE (@supplier_code IS NULL OR LTRIM(RTRIM(h.supp_code)) = @supplier_code)
      AND LTRIM(RTRIM(d.item_code)) = @item_code
      AND LTRIM(RTRIM(d.po_um)) = @po_um
      AND ISNULL(h.status, '') <> 'C'
      AND d.unit_price > 0
      AND (@from_date IS NULL OR h.po_date >= @from_date)
      AND (@to_date IS NULL OR h.po_date < DATEADD(DAY, 1, @to_date));
END;
GO

IF OBJECT_ID(N'dbo.usp_PurchasePrice_ValidateAndApplyPoConversions', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PurchasePrice_ValidateAndApplyPoConversions AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PurchasePrice_ValidateAndApplyPoConversions
    @po_no   VARCHAR(15),
    @details dbo.PurchaseOrderPricingDetailType READONLY
AS
BEGIN
    SET NOCOUNT ON;

    SET @po_no = NULLIF(LTRIM(RTRIM(@po_no)), '');

    IF @po_no IS NULL
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: PO number is required for conversion validation.', 16, 1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM @details d
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.a_item_um_conv c WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.a_item_master i
                ON i.item_code = c.item_code
               AND LOWER(i.active) = 'y'
               AND LTRIM(RTRIM(i.um)) = LTRIM(RTRIM(c.base_um))
            INNER JOIN dbo.a_um u
                ON LTRIM(RTRIM(u.um)) = LTRIM(RTRIM(c.from_um))
            WHERE LTRIM(RTRIM(c.item_code)) = LTRIM(RTRIM(d.item_code))
              AND LTRIM(RTRIM(c.from_um)) = LTRIM(RTRIM(d.po_um))
              AND c.conv_factor > 0
              AND CAST(c.conv_factor AS DECIMAL(18,4)) = d.po_conv_factor
        )
    )
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: A PO detail has a missing, invalid, or changed item/U/M conversion.', 16, 1);
        RETURN;
    END;

    UPDATE det
    SET det.po_conv_factor = src.po_conv_factor,
        det.pr_conv_factor = src.po_conv_factor
    FROM dbo.a_po_det det
    INNER JOIN @details src
        ON src.po_line_no IS NOT NULL
       AND det.po_no = @po_no
       AND det.po_seq = src.po_line_no;

    ;WITH NewInput AS
    (
        SELECT
            row_no,
            po_conv_factor,
            ROW_NUMBER() OVER (ORDER BY row_no) AS NewRowNumber
        FROM @details
        WHERE po_line_no IS NULL
    ),
    NewSaved AS
    (
        SELECT
            det.po_seq,
            ROW_NUMBER() OVER (ORDER BY det.po_seq) AS NewRowNumber
        FROM dbo.a_po_det det
        WHERE det.po_no = @po_no
          AND NOT EXISTS
          (
              SELECT 1
              FROM @details existing_source
              WHERE existing_source.po_line_no = det.po_seq
          )
    )
    UPDATE det
    SET det.po_conv_factor = input.po_conv_factor,
        det.pr_conv_factor = input.po_conv_factor
    FROM dbo.a_po_det det
    INNER JOIN NewSaved saved ON saved.po_seq = det.po_seq
    INNER JOIN NewInput input ON input.NewRowNumber = saved.NewRowNumber
    WHERE det.po_no = @po_no;

    IF (SELECT COUNT(1) FROM dbo.a_po_det WHERE po_no = @po_no) <>
       (SELECT COUNT(1) FROM @details)
    BEGIN
        RAISERROR('PURCHASE_PRICE_VALIDATION: Saved PO detail rows do not match the submitted conversion snapshot.', 16, 1);
        RETURN;
    END;

    SELECT
        d.po_seq AS PoLineNo,
        LTRIM(RTRIM(d.po_no)) AS PoNo,
        LTRIM(RTRIM(ISNULL(d.item_code, ''))) AS ItemCode,
        LTRIM(RTRIM(ISNULL(d.item_desc, ''))) AS ItemDesc,
        CAST(d.qty_po AS DECIMAL(18,2)) AS QtyPo,
        LTRIM(RTRIM(ISNULL(d.po_um, ''))) AS PoUm,
        CAST(d.unit_price AS DECIMAL(18,4)) AS UnitPrice,
        CAST(d.po_conv_factor AS DECIMAL(18,4)) AS PoConvFactor,
        LTRIM(RTRIM(ISNULL(d.user_id, ''))) AS UserId
    FROM dbo.a_po_det d
    WHERE d.po_no = @po_no
    ORDER BY d.po_seq;
END;
GO

/* Static verification queries. Do not treat these as deployment success checks. */
SELECT
    OBJECT_ID(N'dbo.SupplierItemPriceMaster', N'U') AS SupplierItemPriceMasterObjectId,
    OBJECT_ID(N'dbo.SupplierItemPriceHistory', N'U') AS SupplierItemPriceHistoryObjectId,
    OBJECT_ID(N'dbo.usp_PurchasePrice_SupplierList', N'P') AS SupplierPriceListProcedureObjectId,
    TYPE_ID(N'dbo.PurchaseOrderPricingDetailType') AS PurchaseOrderPricingDetailTypeId;
GO
