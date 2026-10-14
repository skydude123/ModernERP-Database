/*
    Simple Fuel Consumption Acceptance
    Target: SQL Server 2012+

    This module is NON-STOCKING. Nothing in this script updates inventory,
    receiving quantities, warehouses, general-ledger tables, or PO quantities.
    Voucher Payable owns the accounting entry for posted documents.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.Seq_FuelAcceptanceNo', N'SO') IS NULL
    EXEC(N'CREATE SEQUENCE dbo.Seq_FuelAcceptanceNo AS bigint START WITH 1 INCREMENT BY 1;');
GO

IF OBJECT_ID(N'dbo.Seq_FuelAcceptanceLineNo', N'SO') IS NULL
    EXEC(N'CREATE SEQUENCE dbo.Seq_FuelAcceptanceLineNo AS bigint START WITH 1 INCREMENT BY 1;');
GO

IF OBJECT_ID(N'dbo.FuelAcceptanceHdr', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FuelAcceptanceHdr
    (
        fuel_acceptance_no varchar(30) NOT NULL,
        acceptance_date date NOT NULL,
        po_no varchar(30) NOT NULL,
        supp_code varchar(20) NOT NULL,
        branchname varchar(50) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_Branch DEFAULT ('MANDAUE'),
        vehicle_no varchar(50) NOT NULL,
        plate_no varchar(30) NOT NULL,
        driver_name nvarchar(150) NOT NULL,
        purpose nvarchar(250) NOT NULL,
        po_amount decimal(19,4) NOT NULL,
        status char(1) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_Status DEFAULT ('N'),
        total_liters decimal(18,4) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_TotalLiters DEFAULT (0),
        total_gross decimal(19,4) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_TotalGross DEFAULT (0),
        total_basic decimal(19,4) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_TotalBasic DEFAULT (0),
        total_input_vat decimal(19,4) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_TotalInputVat DEFAULT (0),
        total_ewt decimal(19,4) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_TotalEwt DEFAULT (0),
        total_net decimal(19,4) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_TotalNet DEFAULT (0),
        no_receipt_amount decimal(19,4) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_NoReceipt DEFAULT (0),
        remarks nvarchar(500) NULL,
        user_id varchar(50) NOT NULL,
        created_date datetime2(0) NOT NULL
            CONSTRAINT DF_FuelAcceptanceHdr_CreatedDate DEFAULT (SYSUTCDATETIME()),
        modified_by varchar(50) NULL,
        modified_date datetime2(0) NULL,
        posted_by varchar(50) NULL,
        posted_date datetime2(0) NULL,
        reversed_by varchar(50) NULL,
        reversed_date datetime2(0) NULL,
        reverse_reason nvarchar(500) NULL,
        row_version rowversion NOT NULL,
        CONSTRAINT PK_FuelAcceptanceHdr
            PRIMARY KEY CLUSTERED (fuel_acceptance_no),
        CONSTRAINT CK_FuelAcceptanceHdr_Status
            CHECK (status IN ('N', 'A', 'R')),
        CONSTRAINT CK_FuelAcceptanceHdr_RequiredText
            CHECK
            (
                NULLIF(LTRIM(RTRIM(po_no)), '') IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(supp_code)), '') IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(branchname)), '') IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(vehicle_no)), '') IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(plate_no)), '') IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(driver_name)), '') IS NOT NULL
                AND NULLIF(LTRIM(RTRIM(purpose)), '') IS NOT NULL
            ),
        CONSTRAINT CK_FuelAcceptanceHdr_Totals
            CHECK
            (
                po_amount > 0
                AND total_liters >= 0
                AND total_gross >= 0
                AND total_basic >= 0
                AND total_input_vat >= 0
                AND total_ewt >= 0
                AND total_net >= 0
                AND no_receipt_amount >= 0
                AND total_gross <= po_amount
            )
    );
END;
GO

IF OBJECT_ID(N'dbo.FuelAcceptanceDtl', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FuelAcceptanceDtl
    (
        fuel_line_no bigint NOT NULL,
        fuel_acceptance_no varchar(30) NOT NULL,
        line_seq int NOT NULL,
        fuel_date date NOT NULL,
        fuel_station nvarchar(150) NOT NULL,
        receipt_no varchar(50) NULL,
        has_receipt bit NOT NULL,
        no_receipt_reason nvarchar(250) NULL,
        fuel_type varchar(30) NOT NULL,
        liters decimal(18,4) NOT NULL,
        unit_price decimal(19,4) NOT NULL,
        gross_amount decimal(19,4) NOT NULL,
        tax_scheme_code varchar(10) NOT NULL,
        vat_rate decimal(9,6) NOT NULL,
        ewt_rate decimal(9,6) NOT NULL,
        basic_amount decimal(19,4) NOT NULL,
        input_vat decimal(19,4) NOT NULL,
        ewt_amount decimal(19,4) NOT NULL,
        net_amount decimal(19,4) NOT NULL,
        remarks nvarchar(500) NULL,
        user_id varchar(50) NOT NULL,
        CONSTRAINT PK_FuelAcceptanceDtl
            PRIMARY KEY CLUSTERED (fuel_line_no),
        CONSTRAINT FK_FuelAcceptanceDtl_Header
            FOREIGN KEY (fuel_acceptance_no)
            REFERENCES dbo.FuelAcceptanceHdr(fuel_acceptance_no),
        CONSTRAINT UQ_FuelAcceptanceDtl_Line
            UNIQUE (fuel_acceptance_no, line_seq),
        CONSTRAINT CK_FuelAcceptanceDtl_TaxScheme
            CHECK (tax_scheme_code IN ('NV', 'NV1', 'NV2', 'RV', 'RV1', 'RV2')),
        CONSTRAINT CK_FuelAcceptanceDtl_Amounts
            CHECK
            (
                liters > 0
                AND unit_price > 0
                AND gross_amount > 0
                AND basic_amount >= 0
                AND input_vat >= 0
                AND ewt_amount >= 0
                AND net_amount >= 0
            ),
        CONSTRAINT CK_FuelAcceptanceDtl_Receipt
            CHECK
            (
                (
                    has_receipt = 1
                    AND NULLIF(LTRIM(RTRIM(receipt_no)), '') IS NOT NULL
                )
                OR
                (
                    has_receipt = 0
                    AND receipt_no IS NULL
                    AND NULLIF(LTRIM(RTRIM(no_receipt_reason)), '') IS NOT NULL
                    AND tax_scheme_code = 'NV'
                    AND vat_rate = 0
                    AND ewt_rate = 0
                )
            )
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.FuelAcceptanceHdr')
      AND name = N'UX_FuelAcceptanceHdr_ActivePo'
)
BEGIN
    CREATE UNIQUE INDEX UX_FuelAcceptanceHdr_ActivePo
        ON dbo.FuelAcceptanceHdr(po_no)
        WHERE status <> 'R';
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.FuelAcceptanceHdr')
      AND name = N'IX_FuelAcceptanceHdr_List'
)
BEGIN
    CREATE INDEX IX_FuelAcceptanceHdr_List
        ON dbo.FuelAcceptanceHdr(acceptance_date DESC, status, branchname)
        INCLUDE
        (
            po_no, supp_code, vehicle_no, plate_no, driver_name, purpose, po_amount,
            total_liters, total_gross, total_input_vat, total_ewt,
            total_net, no_receipt_amount
        );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.FuelAcceptanceDtl')
      AND name = N'IX_FuelAcceptanceDtl_DuplicateReceipt'
)
BEGIN
    CREATE INDEX IX_FuelAcceptanceDtl_DuplicateReceipt
        ON dbo.FuelAcceptanceDtl(fuel_date, receipt_no)
        INCLUDE (fuel_acceptance_no, fuel_station, gross_amount)
        WHERE has_receipt = 1 AND receipt_no IS NOT NULL;
END;
GO

IF TYPE_ID(N'dbo.FuelAcceptanceDetailType') IS NULL
BEGIN
    EXEC(N'
        CREATE TYPE dbo.FuelAcceptanceDetailType AS TABLE
        (
            line_seq int NOT NULL PRIMARY KEY,
            fuel_date date NOT NULL,
            fuel_station nvarchar(150) NOT NULL,
            receipt_no varchar(50) NULL,
            has_receipt bit NOT NULL,
            no_receipt_reason nvarchar(250) NULL,
            fuel_type varchar(30) NOT NULL,
            liters decimal(18,4) NOT NULL,
            unit_price decimal(19,4) NOT NULL,
            tax_scheme_code varchar(10) NOT NULL,
            remarks nvarchar(500) NULL
        );');
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_SupplierLookup', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_SupplierLookup AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_SupplierLookup
    @search nvarchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @search = NULLIF(LTRIM(RTRIM(@search)), '');

    SELECT TOP (100)
        s.supp_code,
        LTRIM(RTRIM(s.supp_name)) AS supp_name
    FROM dbo.a_suppliers AS s
    WHERE
        @search IS NULL
        OR s.supp_code LIKE '%' + @search + '%'
        OR s.supp_name LIKE '%' + @search + '%'
    ORDER BY s.supp_name;
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_BranchLookup', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_BranchLookup AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_BranchLookup
    @search nvarchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @search = NULLIF(LTRIM(RTRIM(@search)), '');

    SELECT b.branchname
    FROM dbo.BRANCH AS b
    WHERE @search IS NULL OR b.branchname LIKE '%' + @search + '%'
    ORDER BY
        CASE WHEN UPPER(LTRIM(RTRIM(b.branchname))) = 'MANDAUE' THEN 0 ELSE 1 END,
        b.branchname;
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_TaxSchemeLookup', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_TaxSchemeLookup AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_TaxSchemeLookup
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH supported AS
    (
        SELECT *
        FROM
        (
            VALUES
                ('NV',  CAST(0.00 AS decimal(9,6)), CAST(0.00 AS decimal(9,6)), N'Non-VAT'),
                ('NV1', CAST(0.00 AS decimal(9,6)), CAST(0.01 AS decimal(9,6)), N'Non-VAT / EWT 1%'),
                ('NV2', CAST(0.00 AS decimal(9,6)), CAST(0.02 AS decimal(9,6)), N'Non-VAT / EWT 2%'),
                ('RV',  CAST(0.12 AS decimal(9,6)), CAST(0.00 AS decimal(9,6)), N'VAT 12%'),
                ('RV1', CAST(0.12 AS decimal(9,6)), CAST(0.01 AS decimal(9,6)), N'VAT 12% / EWT 1%'),
                ('RV2', CAST(0.12 AS decimal(9,6)), CAST(0.02 AS decimal(9,6)), N'VAT 12% / EWT 2%')
        ) AS value_list(tax_scheme_code, vat_rate, ewt_rate, default_name)
    )
    SELECT
        supported.tax_scheme_code,
        COALESCE(NULLIF(LTRIM(RTRIM(tax.tax_name)), ''), supported.default_name) AS tax_name,
        supported.vat_rate,
        supported.ewt_rate
    FROM supported
    LEFT JOIN dbo.TaxScheme AS tax
        ON UPPER(LTRIM(RTRIM(tax.vat_type))) = supported.tax_scheme_code
    ORDER BY
        CASE supported.tax_scheme_code
            WHEN 'NV' THEN 1 WHEN 'NV1' THEN 2 WHEN 'NV2' THEN 3
            WHEN 'RV' THEN 4 WHEN 'RV1' THEN 5 ELSE 6
        END;
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_OpenPoLookup', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_OpenPoLookup AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_OpenPoLookup
    @search nvarchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @search = NULLIF(LTRIM(RTRIM(@search)), '');

    SELECT TOP (100)
        po.po_no,
        po.po_date,
        po.supp_code,
        LTRIM(RTRIM(s.supp_name)) AS supp_name,
        COALESCE(NULLIF(LTRIM(RTRIM(po.branchname)), ''), 'MANDAUE') AS branchname,
        CONVERT(varchar(50), COALESCE(fuel_line.vehicle_no, po.po_no)) AS vehicle_no,
        po_total.po_amount
    FROM dbo.a_po_hdr AS po
    INNER JOIN dbo.a_suppliers AS s
        ON s.supp_code = po.supp_code
    OUTER APPLY
    (
        SELECT TOP (1)
            NULLIF(LTRIM(RTRIM(d.item_desc)), '') AS vehicle_no
        FROM dbo.a_po_det AS d
        WHERE d.po_no = po.po_no
          AND
          (
              UPPER(ISNULL(d.item_desc, '')) LIKE '%GASOLINE%'
              OR UPPER(ISNULL(d.item_desc, '')) LIKE '%DIESEL%'
              OR UPPER(ISNULL(d.item_desc, '')) LIKE '%FUEL%'
          )
        ORDER BY d.item_desc
    ) AS fuel_line
    CROSS APPLY
    (
        SELECT
            CONVERT(decimal(19,4), ROUND(
                ISNULL(SUM(
                    CONVERT(decimal(19,4), ISNULL(d.qty_po, 0))
                    * CONVERT(decimal(19,4), ISNULL(d.unit_price, 0))
                ), 0),
                4
            )) AS po_amount
        FROM dbo.a_po_det AS d
        WHERE d.po_no = po.po_no
    ) AS po_total
    WHERE UPPER(LTRIM(RTRIM(CONVERT(varchar(20), po.status))))
              IN ('A', 'POST', 'POSTED', 'APPROVED')
      AND
      (
          UPPER(LTRIM(RTRIM(CONVERT(varchar(50), po.po_type))))
              IN ('GASOLINE_PO', 'FUEL_PO', 'FUEL_EXPENSE_PO')
          OR fuel_line.vehicle_no IS NOT NULL
      )
      AND po_total.po_amount > 0
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.FuelAcceptanceHdr AS acceptance
          WHERE acceptance.po_no = po.po_no
            AND acceptance.status IN ('N', 'A')
      )
      AND
      (
          @search IS NULL
          OR po.po_no LIKE '%' + @search + '%'
          OR po.supp_code LIKE '%' + @search + '%'
          OR s.supp_name LIKE '%' + @search + '%'
      )
    ORDER BY po.po_date DESC, po.po_no DESC;
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_GetByNo', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_GetByNo AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_GetByNo
    @fuel_acceptance_no varchar(30)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        h.fuel_acceptance_no,
        h.acceptance_date,
        h.po_no,
        h.supp_code,
        LTRIM(RTRIM(s.supp_name)) AS supp_name,
        h.branchname,
        h.vehicle_no,
        h.plate_no,
        h.driver_name,
        h.purpose,
        h.po_amount,
        h.status,
        h.total_liters,
        h.total_gross,
        h.total_basic,
        h.total_input_vat,
        h.total_ewt,
        h.total_net,
        h.no_receipt_amount,
        h.remarks,
        h.user_id,
        h.created_date,
        h.modified_by,
        h.modified_date,
        h.posted_by,
        h.posted_date,
        h.reversed_by,
        h.reversed_date,
        h.reverse_reason,
        CONVERT(varchar(18), h.row_version, 1) AS row_version
    FROM dbo.FuelAcceptanceHdr AS h
    LEFT JOIN dbo.a_suppliers AS s
        ON s.supp_code = h.supp_code
    WHERE h.fuel_acceptance_no = @fuel_acceptance_no;

    SELECT
        d.fuel_line_no,
        d.fuel_acceptance_no,
        d.line_seq,
        d.fuel_date,
        d.fuel_station,
        d.receipt_no,
        d.has_receipt,
        d.no_receipt_reason,
        d.fuel_type,
        d.liters,
        d.unit_price,
        d.gross_amount,
        d.tax_scheme_code,
        d.vat_rate,
        d.ewt_rate,
        d.basic_amount,
        d.input_vat,
        d.ewt_amount,
        d.net_amount,
        d.remarks,
        d.user_id
    FROM dbo.FuelAcceptanceDtl AS d
    WHERE d.fuel_acceptance_no = @fuel_acceptance_no
    ORDER BY d.line_seq;
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_List', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_List AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_List
    @from_date date = NULL,
    @to_date date = NULL,
    @status varchar(3) = 'ALL',
    @branchname varchar(50) = NULL,
    @search nvarchar(150) = NULL,
    @skip int = 0,
    @take int = 50,
    @sort_field varchar(40) = 'acceptanceDate',
    @sort_dir varchar(4) = 'desc'
AS
BEGIN
    SET NOCOUNT ON;

    SET @status = UPPER(LTRIM(RTRIM(ISNULL(@status, 'ALL'))));
    SET @branchname = NULLIF(LTRIM(RTRIM(@branchname)), '');
    SET @search = NULLIF(LTRIM(RTRIM(@search)), '');
    SET @skip = CASE WHEN @skip < 0 THEN 0 ELSE @skip END;
    SET @take = CASE WHEN @take BETWEEN 1 AND 200 THEN @take ELSE 50 END;
    SET @sort_dir = CASE WHEN LOWER(@sort_dir) = 'asc' THEN 'asc' ELSE 'desc' END;

    ;WITH filtered AS
    (
        SELECT
            h.fuel_acceptance_no,
            h.acceptance_date,
            h.po_no,
            h.supp_code,
            LTRIM(RTRIM(s.supp_name)) AS supp_name,
            h.branchname,
            h.vehicle_no,
            h.plate_no,
            h.driver_name,
            h.purpose,
            h.po_amount,
            h.total_liters,
            h.total_gross,
            h.total_input_vat,
            h.total_ewt,
            h.total_net,
            h.no_receipt_amount,
            h.status
        FROM dbo.FuelAcceptanceHdr AS h
        LEFT JOIN dbo.a_suppliers AS s
            ON s.supp_code = h.supp_code
        WHERE (@from_date IS NULL OR h.acceptance_date >= @from_date)
          AND (@to_date IS NULL OR h.acceptance_date <= @to_date)
          AND (@status = 'ALL' OR h.status = @status)
          AND (@branchname IS NULL OR h.branchname = @branchname)
          AND
          (
              @search IS NULL
              OR h.fuel_acceptance_no LIKE '%' + @search + '%'
              OR h.po_no LIKE '%' + @search + '%'
              OR h.supp_code LIKE '%' + @search + '%'
              OR s.supp_name LIKE '%' + @search + '%'
              OR h.vehicle_no LIKE '%' + @search + '%'
              OR h.plate_no LIKE '%' + @search + '%'
              OR h.driver_name LIKE '%' + @search + '%'
          )
    )
    SELECT
        filtered.*,
        COUNT(1) OVER () AS total_count
    FROM filtered
    ORDER BY
        CASE WHEN @sort_field = 'fuelAcceptanceNo' AND @sort_dir = 'asc'
            THEN fuel_acceptance_no END ASC,
        CASE WHEN @sort_field = 'fuelAcceptanceNo' AND @sort_dir = 'desc'
            THEN fuel_acceptance_no END DESC,
        CASE WHEN @sort_field = 'status' AND @sort_dir = 'asc'
            THEN status END ASC,
        CASE WHEN @sort_field = 'status' AND @sort_dir = 'desc'
            THEN status END DESC,
        CASE WHEN @sort_field = 'totalNet' AND @sort_dir = 'asc'
            THEN total_net END ASC,
        CASE WHEN @sort_field = 'totalNet' AND @sort_dir = 'desc'
            THEN total_net END DESC,
        CASE WHEN @sort_dir = 'asc' THEN acceptance_date END ASC,
        CASE WHEN @sort_dir = 'desc' THEN acceptance_date END DESC,
        fuel_acceptance_no DESC
    OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY;
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_SaveUpsert', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_SaveUpsert AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_SaveUpsert
    @fuel_acceptance_no varchar(30) = NULL,
    @acceptance_date date,
    @po_no varchar(30),
    @supp_code varchar(20),
    @branchname varchar(50) = 'MANDAUE',
    @vehicle_no varchar(50),
    @plate_no varchar(30),
    @driver_name nvarchar(150),
    @purpose nvarchar(250),
    @remarks nvarchar(500) = NULL,
    @user_id varchar(50),
    @expected_row_version varchar(18) = NULL,
    @details dbo.FuelAcceptanceDetailType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @fuel_acceptance_no = NULLIF(LTRIM(RTRIM(@fuel_acceptance_no)), '');
    SET @po_no = LTRIM(RTRIM(@po_no));
    SET @supp_code = LTRIM(RTRIM(@supp_code));
    SET @branchname = NULLIF(LTRIM(RTRIM(@branchname)), '');
    SET @vehicle_no = NULLIF(LTRIM(RTRIM(@vehicle_no)), '');
    SET @plate_no = NULLIF(LTRIM(RTRIM(@plate_no)), '');
    SET @driver_name = NULLIF(LTRIM(RTRIM(@driver_name)), '');
    SET @purpose = NULLIF(LTRIM(RTRIM(@purpose)), '');
    SET @remarks = NULLIF(LTRIM(RTRIM(@remarks)), '');
    SET @user_id = NULLIF(LTRIM(RTRIM(@user_id)), '');

    IF @acceptance_date IS NULL
        THROW 51000, 'Acceptance Date is required.', 1;
    IF NULLIF(@po_no, '') IS NULL
        THROW 51000, 'PO is required.', 1;
    IF NULLIF(@supp_code, '') IS NULL
        THROW 51000, 'Supplier is required.', 1;
    IF @branchname IS NULL
        THROW 51000, 'Branch is required.', 1;
    IF @vehicle_no IS NULL
        THROW 51000, 'Vehicle is required.', 1;
    IF @plate_no IS NULL
        THROW 51000, 'Plate No. is required.', 1;
    IF @driver_name IS NULL
        THROW 51000, 'Driver Name is required.', 1;
    IF @purpose IS NULL
        THROW 51000, 'Purpose is required.', 1;
    IF @user_id IS NULL
        THROW 51000, 'Authenticated user is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM @details)
        THROW 51000, 'At least one fuel receipt line is required.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @details
        WHERE fuel_date IS NULL
           OR NULLIF(LTRIM(RTRIM(fuel_station)), '') IS NULL
           OR NULLIF(LTRIM(RTRIM(fuel_type)), '') IS NULL
           OR liters <= 0
           OR unit_price <= 0
    )
        THROW 51000, 'Each line requires Fuel Date, Fuel Station, Fuel Type, positive Liters, and positive Unit Price.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @details
        WHERE liters * unit_price
            > CONVERT(decimal(19,4), 999999999999999.9999)
    )
        THROW 51000, 'A fuel line amount exceeds the supported accounting precision.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @details
        WHERE has_receipt = 1
          AND NULLIF(LTRIM(RTRIM(receipt_no)), '') IS NULL
    )
        THROW 51000, 'Receipt No. is required when Has Receipt is true.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @details
        WHERE has_receipt = 0
          AND NULLIF(LTRIM(RTRIM(no_receipt_reason)), '') IS NULL
    )
        THROW 51000, 'No Receipt Reason is required when Has Receipt is false.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @details
        WHERE has_receipt = 1
          AND UPPER(LTRIM(RTRIM(tax_scheme_code)))
              NOT IN ('NV', 'NV1', 'NV2', 'RV', 'RV1', 'RV2')
    )
        THROW 51000, 'Unsupported TaxScheme.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @details
        WHERE has_receipt = 0
          AND UPPER(LTRIM(RTRIM(tax_scheme_code))) <> 'NV'
    )
        THROW 51000, 'Fuel without a receipt must use TaxScheme NV.', 1;
    IF EXISTS
    (
        SELECT
            UPPER(LTRIM(RTRIM(fuel_station))),
            UPPER(LTRIM(RTRIM(receipt_no))),
            fuel_date,
            ROUND(liters * unit_price, 4)
        FROM @details
        WHERE has_receipt = 1
        GROUP BY
            UPPER(LTRIM(RTRIM(fuel_station))),
            UPPER(LTRIM(RTRIM(receipt_no))),
            fuel_date,
            ROUND(liters * unit_price, 4)
        HAVING COUNT(*) > 1
    )
        THROW 51001, 'Duplicate receipt detected in the submitted lines.', 1;

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.a_po_hdr AS po WITH (UPDLOCK, HOLDLOCK)
            WHERE po.po_no = @po_no
              AND po.supp_code = @supp_code
              AND UPPER(LTRIM(RTRIM(CONVERT(varchar(20), po.status))))
                  IN ('A', 'POST', 'POSTED', 'APPROVED')
              AND
              (
                  UPPER(LTRIM(RTRIM(CONVERT(varchar(50), po.po_type))))
                      IN ('GASOLINE_PO', 'FUEL_PO', 'FUEL_EXPENSE_PO')
                  OR EXISTS
                  (
                      SELECT 1
                      FROM dbo.a_po_det AS detail
                      WHERE detail.po_no = po.po_no
                        AND
                        (
                            UPPER(ISNULL(detail.item_desc, '')) LIKE '%GASOLINE%'
                            OR UPPER(ISNULL(detail.item_desc, '')) LIKE '%DIESEL%'
                            OR UPPER(ISNULL(detail.item_desc, '')) LIKE '%FUEL%'
                        )
                  )
              )
        )
            THROW 51000, 'PO must be posted or approved, must be a fuel PO, and Supplier must match the PO.', 1;

        DECLARE @po_amount decimal(19,4);
        SELECT
            @po_amount = CONVERT(decimal(19,4), ROUND(
                ISNULL(SUM(
                    CONVERT(decimal(19,4), ISNULL(detail.qty_po, 0))
                    * CONVERT(decimal(19,4), ISNULL(detail.unit_price, 0))
                ), 0),
                4
            ))
        FROM dbo.a_po_det AS detail WITH (UPDLOCK, HOLDLOCK)
        WHERE detail.po_no = @po_no;

        IF ISNULL(@po_amount, 0) <= 0
            THROW 51000, 'The selected fuel PO must have a positive amount.', 1;

        DECLARE @requested_gross decimal(38,4);
        SELECT @requested_gross = CONVERT(decimal(38,4), ROUND(
            SUM(ROUND(detail.liters * detail.unit_price, 4)),
            4
        ))
        FROM @details AS detail;

        IF @requested_gross > @po_amount
            THROW 51004, 'Total Gross cannot exceed the Purchase Order amount.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM @details AS incoming
            INNER JOIN dbo.FuelAcceptanceDtl AS existing
                ON existing.has_receipt = 1
               AND UPPER(LTRIM(RTRIM(existing.fuel_station)))
                    = UPPER(LTRIM(RTRIM(incoming.fuel_station)))
               AND UPPER(LTRIM(RTRIM(existing.receipt_no)))
                    = UPPER(LTRIM(RTRIM(incoming.receipt_no)))
               AND existing.fuel_date = incoming.fuel_date
               AND existing.gross_amount = ROUND(incoming.liters * incoming.unit_price, 4)
            INNER JOIN dbo.FuelAcceptanceHdr AS header
                ON header.fuel_acceptance_no = existing.fuel_acceptance_no
            WHERE incoming.has_receipt = 1
              AND header.status <> 'R'
              AND
              (
                  @fuel_acceptance_no IS NULL
                  OR existing.fuel_acceptance_no <> @fuel_acceptance_no
              )
        )
            THROW 51001, 'Duplicate receipt detected by Fuel Station, Receipt No., Fuel Date, and Gross Amount.', 1;

        DECLARE @is_new bit =
            CASE WHEN @fuel_acceptance_no IS NULL THEN 1 ELSE 0 END;

        IF @is_new = 1
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM dbo.FuelAcceptanceHdr WITH (UPDLOCK, HOLDLOCK)
                WHERE po_no = @po_no
                  AND status IN ('N', 'A')
            )
                THROW 51001, 'This PO already has an active Fuel Acceptance.', 1;

            DECLARE @next_acceptance_no bigint =
                NEXT VALUE FOR dbo.Seq_FuelAcceptanceNo;

            SET @fuel_acceptance_no =
                CONCAT(
                    'FA-',
                    RIGHT(
                        REPLICATE('0', 10)
                        + CONVERT(varchar(20), @next_acceptance_no),
                        10
                    )
                );

            INSERT dbo.FuelAcceptanceHdr
            (
                fuel_acceptance_no, acceptance_date, po_no, supp_code,
                branchname, vehicle_no, plate_no, driver_name, purpose,
                po_amount, status,
                remarks, user_id, created_date
            )
            VALUES
            (
                @fuel_acceptance_no, @acceptance_date, @po_no, @supp_code,
                @branchname, @vehicle_no, @plate_no, @driver_name, @purpose,
                @po_amount, 'N',
                @remarks, @user_id, SYSUTCDATETIME()
            );
        END
        ELSE
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.FuelAcceptanceHdr WITH (UPDLOCK, HOLDLOCK)
                WHERE fuel_acceptance_no = @fuel_acceptance_no
            )
                THROW 51002, 'Fuel Acceptance was not found.', 1;

            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.FuelAcceptanceHdr
                WHERE fuel_acceptance_no = @fuel_acceptance_no
                  AND status = 'N'
            )
                THROW 51002, 'Posted or reversed Fuel Acceptance documents are read-only.', 1;

            IF @expected_row_version IS NULL
               OR NOT EXISTS
               (
                   SELECT 1
                   FROM dbo.FuelAcceptanceHdr
                   WHERE fuel_acceptance_no = @fuel_acceptance_no
                     AND row_version = CONVERT(varbinary(8), @expected_row_version, 1)
               )
                THROW 51003, 'Fuel Acceptance changed after it was loaded. Refresh and try again.', 1;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.FuelAcceptanceHdr WITH (UPDLOCK, HOLDLOCK)
                WHERE po_no = @po_no
                  AND status IN ('N', 'A')
                  AND fuel_acceptance_no <> @fuel_acceptance_no
            )
                THROW 51001, 'This PO already has an active Fuel Acceptance.', 1;

            UPDATE dbo.FuelAcceptanceHdr
            SET
                acceptance_date = @acceptance_date,
                po_no = @po_no,
                supp_code = @supp_code,
                branchname = @branchname,
                vehicle_no = @vehicle_no,
                plate_no = @plate_no,
                driver_name = @driver_name,
                purpose = @purpose,
                po_amount = @po_amount,
                remarks = @remarks,
                modified_by = @user_id,
                modified_date = SYSUTCDATETIME()
            WHERE fuel_acceptance_no = @fuel_acceptance_no;

            DELETE dbo.FuelAcceptanceDtl
            WHERE fuel_acceptance_no = @fuel_acceptance_no;
        END;

        ;WITH normalized AS
        (
            SELECT
                detail.line_seq,
                detail.fuel_date,
                LTRIM(RTRIM(detail.fuel_station)) AS fuel_station,
                CASE
                    WHEN detail.has_receipt = 1
                        THEN NULLIF(LTRIM(RTRIM(detail.receipt_no)), '')
                END AS receipt_no,
                detail.has_receipt,
                CASE
                    WHEN detail.has_receipt = 0
                        THEN NULLIF(LTRIM(RTRIM(detail.no_receipt_reason)), '')
                END AS no_receipt_reason,
                UPPER(LTRIM(RTRIM(detail.fuel_type))) AS fuel_type,
                detail.liters,
                detail.unit_price,
                ROUND(detail.liters * detail.unit_price, 4) AS gross_amount,
                CASE
                    WHEN detail.has_receipt = 0 THEN 'NV'
                    ELSE UPPER(LTRIM(RTRIM(detail.tax_scheme_code)))
                END AS tax_scheme_code,
                NULLIF(LTRIM(RTRIM(detail.remarks)), '') AS remarks
            FROM @details AS detail
        ),
        rated AS
        (
            SELECT
                normalized.*,
                CASE
                    WHEN tax_scheme_code IN ('RV', 'RV1', 'RV2')
                        THEN CAST(0.12 AS decimal(9,6))
                    ELSE CAST(0 AS decimal(9,6))
                END AS vat_rate,
                CASE
                    WHEN tax_scheme_code IN ('NV1', 'RV1')
                        THEN CAST(0.01 AS decimal(9,6))
                    WHEN tax_scheme_code IN ('NV2', 'RV2')
                        THEN CAST(0.02 AS decimal(9,6))
                    ELSE CAST(0 AS decimal(9,6))
                END AS ewt_rate
            FROM normalized
        ),
        amounts AS
        (
            SELECT
                rated.*,
                CASE
                    WHEN vat_rate = 0.12
                        THEN ROUND(gross_amount / 1.12, 4)
                    ELSE gross_amount
                END AS basic_amount
            FROM rated
        )
        INSERT dbo.FuelAcceptanceDtl
        (
            fuel_line_no, fuel_acceptance_no, line_seq, fuel_date,
            fuel_station, receipt_no, has_receipt, no_receipt_reason,
            fuel_type, liters, unit_price, gross_amount, tax_scheme_code,
            vat_rate, ewt_rate, basic_amount, input_vat, ewt_amount,
            net_amount, remarks, user_id
        )
        SELECT
            NEXT VALUE FOR dbo.Seq_FuelAcceptanceLineNo OVER (ORDER BY line_seq),
            @fuel_acceptance_no,
            line_seq,
            fuel_date,
            fuel_station,
            receipt_no,
            has_receipt,
            no_receipt_reason,
            fuel_type,
            liters,
            unit_price,
            gross_amount,
            tax_scheme_code,
            vat_rate,
            ewt_rate,
            basic_amount,
            ROUND(gross_amount - basic_amount, 4),
            ROUND(basic_amount * ewt_rate, 4),
            ROUND(gross_amount - (basic_amount * ewt_rate), 4),
            remarks,
            @user_id
        FROM amounts;

        UPDATE header
        SET
            total_liters = total.total_liters,
            total_gross = total.total_gross,
            total_basic = total.total_basic,
            total_input_vat = total.total_input_vat,
            total_ewt = total.total_ewt,
            total_net = total.total_net,
            no_receipt_amount = total.no_receipt_amount
        FROM dbo.FuelAcceptanceHdr AS header
        CROSS APPLY
        (
            SELECT
                SUM(detail.liters) AS total_liters,
                SUM(detail.gross_amount) AS total_gross,
                SUM(detail.basic_amount) AS total_basic,
                SUM(detail.input_vat) AS total_input_vat,
                SUM(detail.ewt_amount) AS total_ewt,
                SUM(detail.net_amount) AS total_net,
                SUM(CASE WHEN detail.has_receipt = 0
                    THEN detail.gross_amount ELSE 0 END) AS no_receipt_amount
            FROM dbo.FuelAcceptanceDtl AS detail
            WHERE detail.fuel_acceptance_no = @fuel_acceptance_no
        ) AS total
        WHERE header.fuel_acceptance_no = @fuel_acceptance_no;

        COMMIT TRANSACTION;

        SELECT
            fuel_acceptance_no,
            status,
            CONVERT(varchar(18), row_version, 1) AS row_version,
            CASE WHEN @is_new = 1
                THEN 'Fuel Acceptance created.'
                ELSE 'Fuel Acceptance updated.'
            END AS message
        FROM dbo.FuelAcceptanceHdr
        WHERE fuel_acceptance_no = @fuel_acceptance_no;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_Post', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_Post AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_Post
    @fuel_acceptance_no varchar(30),
    @user_id varchar(50),
    @expected_row_version varchar(18)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.FuelAcceptanceHdr WITH (UPDLOCK)
        SET
            status = 'A',
            posted_by = @user_id,
            posted_date = SYSUTCDATETIME(),
            modified_by = @user_id,
            modified_date = SYSUTCDATETIME()
        WHERE fuel_acceptance_no = @fuel_acceptance_no
          AND status = 'N'
          AND row_version = CONVERT(varbinary(8), @expected_row_version, 1)
          AND EXISTS
          (
              SELECT 1
              FROM dbo.FuelAcceptanceDtl AS detail
              WHERE detail.fuel_acceptance_no = @fuel_acceptance_no
          );

        IF @@ROWCOUNT <> 1
            THROW 51002, 'Only the current Draft Fuel Acceptance can be posted.', 1;

        /*
            Posting ends here intentionally: no inventory movement, PO receipt
            quantity update, warehouse transaction, journal, or GL entry.
        */
        COMMIT TRANSACTION;

        SELECT
            fuel_acceptance_no,
            status,
            CONVERT(varchar(18), row_version, 1) AS row_version,
            'Fuel Acceptance posted and ready for Voucher Payable.' AS message
        FROM dbo.FuelAcceptanceHdr
        WHERE fuel_acceptance_no = @fuel_acceptance_no;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_Reverse', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_Reverse AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_Reverse
    @fuel_acceptance_no varchar(30),
    @user_id varchar(50),
    @expected_row_version varchar(18),
    @reverse_reason nvarchar(500)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @reverse_reason = NULLIF(LTRIM(RTRIM(@reverse_reason)), '');
    IF @reverse_reason IS NULL
        THROW 51000, 'Reversal reason is required.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.FuelAcceptanceHdr WITH (UPDLOCK)
        SET
            status = 'R',
            reversed_by = @user_id,
            reversed_date = SYSUTCDATETIME(),
            reverse_reason = @reverse_reason,
            modified_by = @user_id,
            modified_date = SYSUTCDATETIME()
        WHERE fuel_acceptance_no = @fuel_acceptance_no
          AND status = 'A'
          AND row_version = CONVERT(varbinary(8), @expected_row_version, 1);

        IF @@ROWCOUNT <> 1
            THROW 51002, 'Only the current Posted Fuel Acceptance can be reversed.', 1;

        /*
            Reversal retains header/detail audit rows. It generates neither an
            inventory reversal nor a GL reversal because posting generated none.
        */
        COMMIT TRANSACTION;

        SELECT
            fuel_acceptance_no,
            status,
            CONVERT(varchar(18), row_version, 1) AS row_version,
            'Fuel Acceptance reversed. A replacement may now be created for the PO.' AS message
        FROM dbo.FuelAcceptanceHdr
        WHERE fuel_acceptance_no = @fuel_acceptance_no;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

IF OBJECT_ID(N'dbo.usp_FuelAcceptance_OpenForVP', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_FuelAcceptance_OpenForVP AS BEGIN SET NOCOUNT ON; END;');
GO
ALTER PROCEDURE dbo.usp_FuelAcceptance_OpenForVP
    @supp_code varchar(20) = NULL,
    @branchname varchar(50) = NULL,
    @search nvarchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @supp_code = NULLIF(LTRIM(RTRIM(@supp_code)), '');
    SET @branchname = NULLIF(LTRIM(RTRIM(@branchname)), '');
    SET @search = NULLIF(LTRIM(RTRIM(@search)), '');

    SELECT TOP (200)
        CAST('FUEL_ACCEPTANCE' AS varchar(30)) AS source_type,
        h.fuel_acceptance_no AS source_no,
        h.fuel_acceptance_no AS ref_ID,
        h.fuel_acceptance_no,
        h.acceptance_date,
        h.po_no,
        h.supp_code,
        LTRIM(RTRIM(s.supp_name)) AS supp_name,
        h.branchname,
        h.total_gross AS gross_amount,
        h.total_basic AS basic_amount,
        h.total_input_vat AS input_vat,
        h.total_ewt AS ewt_amount,
        h.total_net AS net_amount
    FROM dbo.FuelAcceptanceHdr AS h
    INNER JOIN dbo.a_suppliers AS s
        ON s.supp_code = h.supp_code
    WHERE h.status = 'A'
      AND (@supp_code IS NULL OR h.supp_code = @supp_code)
      AND (@branchname IS NULL OR h.branchname = @branchname)
      AND
      (
          @search IS NULL
          OR h.fuel_acceptance_no LIKE '%' + @search + '%'
          OR h.po_no LIKE '%' + @search + '%'
      )
    ORDER BY h.acceptance_date, h.fuel_acceptance_no;
END;
GO

/*
    Verification (read-only):

    SELECT name, type_desc
    FROM sys.objects
    WHERE name LIKE 'FuelAcceptance%' OR name LIKE 'usp_FuelAcceptance_%'
    ORDER BY type_desc, name;

    SELECT name
    FROM sys.sequences
    WHERE name IN ('Seq_FuelAcceptanceNo', 'Seq_FuelAcceptanceLineNo');

    EXEC dbo.usp_FuelAcceptance_TaxSchemeLookup;
*/
