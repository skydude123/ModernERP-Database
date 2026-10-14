/*
  Service Acceptance deployment (single controlled script).
  Prerequisites: dbo.a_po_hdr, dbo.a_po_det, dbo.a_suppliers, dbo.BRANCH,
  dbo.TaxScheme and the security metadata tables used at the end of this file.

  This module is non-stocking and creates no GL entries. A POSTED Service
  Acceptance is only a source document for Voucher Payable (VP). VAT and EWT
  remain authoritative in VP.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'dbo.TWB_ServiceAcceptanceHdr', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TWB_ServiceAcceptanceHdr
    (
        service_acceptance_no varchar(30) NOT NULL,
        acceptance_date date NOT NULL,
        po_no varchar(15) NOT NULL,
        supp_code varchar(10) NOT NULL,
        service_type varchar(30) NOT NULL,
        branchname varchar(50) NOT NULL CONSTRAINT DF_ServiceAcceptanceHdr_Branch DEFAULT ('MANDAUE'),
        department_code varchar(30) NULL,
        project_no varchar(30) NULL,
        jo_no varchar(30) NULL,
        service_location nvarchar(150) NULL,
        service_period_from date NULL,
        service_period_to date NULL,
        requested_by nvarchar(100) NULL,
        remarks nvarchar(500) NULL,
        completion_percent decimal(5,2) NOT NULL CONSTRAINT DF_ServiceAcceptanceHdr_Completion DEFAULT (0),
        total_accepted_amount decimal(19,4) NOT NULL CONSTRAINT DF_ServiceAcceptanceHdr_Amount DEFAULT (0),
        status varchar(20) NOT NULL CONSTRAINT DF_ServiceAcceptanceHdr_Status DEFAULT ('DRAFT'),
        submitted_by varchar(50) NULL,
        submitted_date datetime2(0) NULL,
        accepted_by varchar(50) NULL,
        accepted_date datetime2(0) NULL,
        posted_by varchar(50) NULL,
        posted_date datetime2(0) NULL,
        reversed_by varchar(50) NULL,
        reversed_date datetime2(0) NULL,
        reverse_reason nvarchar(500) NULL,
        created_by varchar(50) NOT NULL,
        created_date datetime2(0) NOT NULL CONSTRAINT DF_ServiceAcceptanceHdr_Created DEFAULT (SYSUTCDATETIME()),
        modified_by varchar(50) NULL,
        modified_date datetime2(0) NULL,
        row_version rowversion NOT NULL,
        CONSTRAINT PK_ServiceAcceptanceHdr PRIMARY KEY CLUSTERED (service_acceptance_no),
        CONSTRAINT CK_ServiceAcceptanceHdr_Status CHECK (status IN ('DRAFT','SUBMITTED','ACCEPTED','POSTED','REVERSED')),
        CONSTRAINT CK_ServiceAcceptanceHdr_Type CHECK
            (service_type IN ('REPAIR_MAINTENANCE','MECHANIC_SERVICE','COMPUTER_REPAIR','JOB_OUT','INSTALLATION','LABOR','FREIGHT')),
        CONSTRAINT CK_ServiceAcceptanceHdr_Period CHECK
            (service_period_from IS NULL OR service_period_to IS NULL OR service_period_to >= service_period_from),
        CONSTRAINT CK_ServiceAcceptanceHdr_Totals CHECK
            (completion_percent BETWEEN 0 AND 100 AND total_accepted_amount >= 0)
    );
END;
GO

IF OBJECT_ID(N'dbo.TWB_ServiceAcceptanceDtl', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TWB_ServiceAcceptanceDtl
    (
        service_line_no bigint IDENTITY(1,1) NOT NULL,
        service_acceptance_no varchar(30) NOT NULL,
        line_seq int NOT NULL,
        po_seq int NOT NULL,
        item_code varchar(30) NULL,
        service_description nvarchar(255) NOT NULL,
        unit_of_measure varchar(20) NULL,
        po_qty decimal(18,4) NOT NULL,
        remaining_qty decimal(18,4) NOT NULL,
        accepted_qty decimal(18,4) NOT NULL,
        rate decimal(19,4) NOT NULL,
        accepted_amount decimal(19,4) NOT NULL,
        tax_scheme_code varchar(10) NOT NULL,
        remarks nvarchar(500) NULL,
        CONSTRAINT PK_ServiceAcceptanceDtl PRIMARY KEY CLUSTERED (service_line_no),
        CONSTRAINT FK_ServiceAcceptanceDtl_Hdr FOREIGN KEY (service_acceptance_no)
            REFERENCES dbo.TWB_ServiceAcceptanceHdr(service_acceptance_no),
        CONSTRAINT UQ_ServiceAcceptanceDtl_Line UNIQUE (service_acceptance_no, line_seq),
        CONSTRAINT UQ_ServiceAcceptanceDtl_PoLine UNIQUE (service_acceptance_no, po_seq),
        CONSTRAINT CK_ServiceAcceptanceDtl_Values CHECK
            (po_qty > 0 AND remaining_qty >= 0 AND accepted_qty >= 0 AND rate >= 0
             AND accepted_amount = ROUND(accepted_qty * rate, 4))
    );
END;
GO

IF OBJECT_ID(N'dbo.TWB_ServiceAcceptanceChecklist', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TWB_ServiceAcceptanceChecklist
    (
        checklist_line_no bigint IDENTITY(1,1) NOT NULL,
        service_acceptance_no varchar(30) NOT NULL,
        line_seq int NOT NULL,
        checklist_code varchar(30) NOT NULL,
        checklist_description nvarchar(200) NOT NULL,
        is_required bit NOT NULL CONSTRAINT DF_ServiceAcceptanceChecklist_Required DEFAULT (1),
        is_completed bit NOT NULL CONSTRAINT DF_ServiceAcceptanceChecklist_Complete DEFAULT (0),
        completed_by varchar(50) NULL,
        completed_date datetime2(0) NULL,
        remarks nvarchar(500) NULL,
        CONSTRAINT PK_ServiceAcceptanceChecklist PRIMARY KEY CLUSTERED (checklist_line_no),
        CONSTRAINT FK_ServiceAcceptanceChecklist_Hdr FOREIGN KEY (service_acceptance_no)
            REFERENCES dbo.TWB_ServiceAcceptanceHdr(service_acceptance_no),
        CONSTRAINT UQ_ServiceAcceptanceChecklist_Line UNIQUE (service_acceptance_no, line_seq),
        CONSTRAINT UQ_ServiceAcceptanceChecklist_Code UNIQUE (service_acceptance_no, checklist_code)
    );
END;
GO

IF OBJECT_ID(N'dbo.TWB_ServiceAcceptanceVpLink', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.TWB_ServiceAcceptanceVpLink
    (
        service_acceptance_no varchar(30) NOT NULL,
        vp_no varchar(30) NOT NULL,
        linked_by varchar(50) NOT NULL,
        linked_date datetime2(0) NOT NULL CONSTRAINT DF_ServiceAcceptanceVpLink_Date DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_ServiceAcceptanceVpLink PRIMARY KEY CLUSTERED (service_acceptance_no),
        CONSTRAINT UQ_ServiceAcceptanceVpLink_Vp UNIQUE (vp_no, service_acceptance_no),
        CONSTRAINT FK_ServiceAcceptanceVpLink_Hdr FOREIGN KEY (service_acceptance_no)
            REFERENCES dbo.TWB_ServiceAcceptanceHdr(service_acceptance_no)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.TWB_ServiceAcceptanceHdr') AND name = N'IX_ServiceAcceptanceHdr_List')
    CREATE INDEX IX_ServiceAcceptanceHdr_List
        ON dbo.TWB_ServiceAcceptanceHdr(acceptance_date DESC, status, branchname)
        INCLUDE (po_no, supp_code, service_type, project_no, completion_percent, total_accepted_amount);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.TWB_ServiceAcceptanceDtl') AND name = N'IX_ServiceAcceptanceDtl_PoBalance')
    CREATE INDEX IX_ServiceAcceptanceDtl_PoBalance
        ON dbo.TWB_ServiceAcceptanceDtl(po_seq, service_acceptance_no)
        INCLUDE (accepted_qty, accepted_amount);
GO

IF TYPE_ID(N'dbo.ServiceAcceptanceDetailType') IS NULL
EXEC(N'
CREATE TYPE dbo.ServiceAcceptanceDetailType AS TABLE
(
    line_seq int NOT NULL,
    po_seq int NOT NULL,
    item_code varchar(30) NULL,
    service_description nvarchar(255) NOT NULL,
    unit_of_measure varchar(20) NULL,
    po_qty decimal(18,4) NOT NULL,
    remaining_qty decimal(18,4) NOT NULL,
    accepted_qty decimal(18,4) NOT NULL,
    rate decimal(19,4) NOT NULL,
    tax_scheme_code varchar(10) NOT NULL,
    remarks nvarchar(500) NULL,
    PRIMARY KEY (line_seq),
    UNIQUE (po_seq)
);');
GO

IF TYPE_ID(N'dbo.ServiceAcceptanceChecklistType') IS NULL
EXEC(N'
CREATE TYPE dbo.ServiceAcceptanceChecklistType AS TABLE
(
    line_seq int NOT NULL,
    checklist_code varchar(30) NOT NULL,
    checklist_description nvarchar(200) NOT NULL,
    is_required bit NOT NULL,
    is_completed bit NOT NULL,
    remarks nvarchar(500) NULL,
    PRIMARY KEY (line_seq),
    UNIQUE (checklist_code)
);');
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_GetByNo
    @service_acceptance_no varchar(30)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT h.service_acceptance_no, h.acceptance_date, h.po_no, h.supp_code,
           LTRIM(RTRIM(s.supp_name)) AS supp_name, h.service_type, h.branchname,
           h.department_code, h.project_no, h.jo_no, h.service_location,
           h.service_period_from, h.service_period_to, h.requested_by, h.remarks,
           h.completion_percent, h.total_accepted_amount, h.status,
           h.submitted_by, h.submitted_date, h.accepted_by, h.accepted_date,
           h.posted_by, h.posted_date, h.reversed_by, h.reversed_date,
           h.reverse_reason, h.created_by, h.created_date, h.modified_by,
           h.modified_date, CONVERT(varchar(18), h.row_version, 1) AS row_version
    FROM dbo.TWB_ServiceAcceptanceHdr AS h
    LEFT JOIN dbo.a_suppliers AS s ON s.supp_code = h.supp_code
    WHERE h.service_acceptance_no = @service_acceptance_no;

    SELECT service_line_no, service_acceptance_no, line_seq, po_seq, item_code,
           service_description, unit_of_measure, po_qty, remaining_qty,
           accepted_qty, rate, accepted_amount, tax_scheme_code, remarks
    FROM dbo.TWB_ServiceAcceptanceDtl
    WHERE service_acceptance_no = @service_acceptance_no
    ORDER BY line_seq;

    SELECT checklist_line_no, service_acceptance_no, line_seq, checklist_code,
           checklist_description, is_required, is_completed, completed_by,
           completed_date, remarks
    FROM dbo.TWB_ServiceAcceptanceChecklist
    WHERE service_acceptance_no = @service_acceptance_no
    ORDER BY line_seq;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_List
    @from_date date = NULL,
    @to_date date = NULL,
    @status varchar(20) = 'ALL',
    @branchname varchar(50) = NULL,
    @search nvarchar(150) = NULL,
    @skip int = 0,
    @take int = 50,
    @sort_field varchar(40) = 'acceptanceDate',
    @sort_dir varchar(4) = 'desc'
AS
BEGIN
    SET NOCOUNT ON;
    SET @skip = CASE WHEN @skip < 0 THEN 0 ELSE @skip END;
    SET @take = CASE WHEN @take BETWEEN 1 AND 200 THEN @take ELSE 50 END;
    ;WITH filtered AS
    (
        SELECT h.*, LTRIM(RTRIM(s.supp_name)) AS supp_name
        FROM dbo.TWB_ServiceAcceptanceHdr AS h
        LEFT JOIN dbo.a_suppliers AS s ON s.supp_code = h.supp_code
        WHERE (@from_date IS NULL OR h.acceptance_date >= @from_date)
          AND (@to_date IS NULL OR h.acceptance_date < DATEADD(day, 1, @to_date))
          AND (NULLIF(@status, 'ALL') IS NULL OR h.status = @status)
          AND (@branchname IS NULL OR h.branchname = @branchname)
          AND (@search IS NULL OR h.service_acceptance_no LIKE '%' + @search + '%'
               OR h.po_no LIKE '%' + @search + '%' OR h.supp_code LIKE '%' + @search + '%'
               OR s.supp_name LIKE '%' + @search + '%' OR h.project_no LIKE '%' + @search + '%')
    )
    SELECT service_acceptance_no, acceptance_date, po_no, supp_code, supp_name,
           service_type, branchname, project_no, completion_percent,
           total_accepted_amount, status, COUNT(*) OVER() AS total_count
    FROM filtered
    ORDER BY
      CASE WHEN @sort_field = 'serviceAcceptanceNo' AND @sort_dir = 'asc' THEN service_acceptance_no END ASC,
      CASE WHEN @sort_field = 'serviceAcceptanceNo' AND @sort_dir = 'desc' THEN service_acceptance_no END DESC,
      CASE WHEN @sort_field = 'status' AND @sort_dir = 'asc' THEN status END ASC,
      CASE WHEN @sort_field = 'status' AND @sort_dir = 'desc' THEN status END DESC,
      CASE WHEN @sort_field = 'totalAcceptedAmount' AND @sort_dir = 'asc' THEN total_accepted_amount END ASC,
      CASE WHEN @sort_field = 'totalAcceptedAmount' AND @sort_dir = 'desc' THEN total_accepted_amount END DESC,
      CASE WHEN @sort_dir = 'asc' THEN acceptance_date END ASC,
      CASE WHEN @sort_dir <> 'asc' THEN acceptance_date END DESC,
      service_acceptance_no DESC
    OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_PoLookup
    @search nvarchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (100) h.po_no, h.po_date, h.supp_code,
           LTRIM(RTRIM(s.supp_name)) AS supp_name, h.branchname
    FROM dbo.a_po_hdr AS h
    INNER JOIN dbo.a_suppliers AS s ON s.supp_code = h.supp_code
    WHERE RTRIM(h.status) IN ('P','A','POSTED','APPROVED')
      AND EXISTS
      (
        SELECT 1 FROM dbo.a_po_det AS d
        WHERE d.po_no = h.po_no
          AND (UPPER(ISNULL(d.item_code, '')) LIKE 'SVC%'
               OR UPPER(ISNULL(d.item_code, '')) LIKE 'SERVICE%'
               OR UPPER(ISNULL(d.item_desc, '')) LIKE '%SERVICE%'
               OR UPPER(ISNULL(d.item_desc, '')) LIKE '%REPAIR%'
               OR UPPER(ISNULL(d.item_desc, '')) LIKE '%MAINTENANCE%'
               OR UPPER(ISNULL(d.item_desc, '')) LIKE '%LABOR%'
               OR UPPER(ISNULL(d.item_desc, '')) LIKE '%INSTALLATION%'
               OR UPPER(ISNULL(d.item_desc, '')) LIKE '%FREIGHT%')
      )
      AND (@search IS NULL OR h.po_no LIKE '%' + @search + '%'
           OR h.supp_code LIKE '%' + @search + '%' OR s.supp_name LIKE '%' + @search + '%')
    ORDER BY h.po_date DESC, h.po_no DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_PoLineLookup
    @po_no varchar(15),
    @exclude_acceptance_no varchar(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.po_seq, d.item_code, d.item_desc AS service_description,
           d.po_um AS unit_of_measure, CAST(d.qty_po AS decimal(18,4)) AS po_qty,
           CAST(ISNULL(a.accepted_qty, 0) AS decimal(18,4)) AS accepted_qty,
           CAST(d.qty_po - ISNULL(a.accepted_qty, 0) AS decimal(18,4)) AS remaining_qty,
           CAST(ISNULL(d.unit_price, 0) AS decimal(19,4)) AS rate
    FROM dbo.a_po_det AS d
    OUTER APPLY
    (
        SELECT SUM(sd.accepted_qty) AS accepted_qty
        FROM dbo.TWB_ServiceAcceptanceDtl AS sd
        INNER JOIN dbo.TWB_ServiceAcceptanceHdr AS sh
          ON sh.service_acceptance_no = sd.service_acceptance_no
        WHERE sh.po_no = @po_no AND sd.po_seq = d.po_seq
          AND sh.status <> 'REVERSED'
          AND (@exclude_acceptance_no IS NULL OR sh.service_acceptance_no <> @exclude_acceptance_no)
    ) AS a
    WHERE d.po_no = @po_no
      AND d.qty_po > ISNULL(a.accepted_qty, 0)
    ORDER BY d.po_seq;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_TaxSchemeLookup
AS
BEGIN
    SET NOCOUNT ON;
    SELECT x.tax_scheme_code,
           COALESCE(NULLIF(LTRIM(RTRIM(t.tax_name)), ''), x.default_name) AS tax_name
    FROM (VALUES
      ('NV', 'Non-VAT'), ('NV1', 'Non-VAT / 1% EWT'), ('NV2', 'Non-VAT / 2% EWT'),
      ('RV1', 'VAT / 1% EWT'), ('RV2', 'VAT / 2% EWT')
    ) AS x(tax_scheme_code, default_name)
    LEFT JOIN dbo.TaxScheme AS t ON t.vat_type = x.tax_scheme_code
    ORDER BY x.tax_scheme_code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_Save
    @service_acceptance_no varchar(30) = NULL,
    @acceptance_date date,
    @po_no varchar(15),
    @supp_code varchar(10),
    @service_type varchar(30),
    @branchname varchar(50),
    @department_code varchar(30) = NULL,
    @project_no varchar(30) = NULL,
    @jo_no varchar(30) = NULL,
    @service_location nvarchar(150) = NULL,
    @service_period_from date = NULL,
    @service_period_to date = NULL,
    @requested_by nvarchar(100) = NULL,
    @remarks nvarchar(500) = NULL,
    @user_id varchar(50),
    @expected_row_version varchar(18) = NULL,
    @details dbo.ServiceAcceptanceDetailType READONLY,
    @checklist dbo.ServiceAcceptanceChecklistType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @service_acceptance_no = NULLIF(LTRIM(RTRIM(@service_acceptance_no)), '');
    SET @service_type = UPPER(LTRIM(RTRIM(@service_type)));
    IF NOT EXISTS (SELECT 1 FROM @details) THROW 51000, 'At least one service line is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM @checklist) THROW 51000, 'At least one checklist item is required.', 1;
    IF @service_period_from IS NOT NULL AND @service_period_to < @service_period_from
        THROW 51000, 'Service period end cannot be before its start.', 1;
    IF @service_type NOT IN ('REPAIR_MAINTENANCE','MECHANIC_SERVICE','COMPUTER_REPAIR','JOB_OUT','INSTALLATION','LABOR','FREIGHT')
        THROW 51000, 'Invalid service type.', 1;
    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.a_po_hdr
        WHERE po_no = @po_no AND supp_code = @supp_code
          AND RTRIM(status) IN ('P','A','POSTED','APPROVED')
    )
        THROW 51000, 'Service PO must be posted or approved and must belong to the selected supplier.', 1;
    IF EXISTS (SELECT 1 FROM @details WHERE accepted_qty < 0 OR rate < 0)
        THROW 51000, 'Accepted quantity and rate cannot be negative.', 1;
    IF EXISTS (SELECT 1 FROM @details WHERE UPPER(tax_scheme_code) NOT IN ('NV','NV1','NV2','RV1','RV2'))
        THROW 51000, 'Unsupported tax scheme.', 1;

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;
        DECLARE @is_new bit = CASE WHEN @service_acceptance_no IS NULL THEN 1 ELSE 0 END;

        IF EXISTS
        (
            SELECT 1
            FROM @details AS x
            LEFT JOIN dbo.a_po_det AS p WITH (UPDLOCK, HOLDLOCK)
              ON p.po_no = @po_no AND p.po_seq = x.po_seq
            OUTER APPLY
            (
                SELECT SUM(d.accepted_qty) AS used_qty
                FROM dbo.TWB_ServiceAcceptanceDtl AS d WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN dbo.TWB_ServiceAcceptanceHdr AS h WITH (UPDLOCK, HOLDLOCK)
                  ON h.service_acceptance_no = d.service_acceptance_no
                WHERE h.po_no = @po_no AND d.po_seq = x.po_seq
                  AND h.status <> 'REVERSED'
                  AND (@service_acceptance_no IS NULL OR h.service_acceptance_no <> @service_acceptance_no)
            ) AS used
            WHERE p.po_seq IS NULL OR x.accepted_qty > p.qty_po - ISNULL(used.used_qty, 0)
        )
            THROW 51000, 'Accepted quantity exceeds the remaining Service PO balance.', 1;

        IF @is_new = 1
        BEGIN
            DECLARE @prefix varchar(20) = CONCAT('SA-', CONVERT(char(6), @acceptance_date, 112), '-');
            DECLARE @next int = ISNULL((
                SELECT MAX(TRY_CONVERT(int, RIGHT(service_acceptance_no, 6)))
                FROM dbo.TWB_ServiceAcceptanceHdr WITH (UPDLOCK, HOLDLOCK)
                WHERE service_acceptance_no LIKE @prefix + '[0-9][0-9][0-9][0-9][0-9][0-9]'), 0) + 1;
            SET @service_acceptance_no = @prefix + RIGHT('000000' + CONVERT(varchar(6), @next), 6);
            INSERT dbo.TWB_ServiceAcceptanceHdr
                (service_acceptance_no, acceptance_date, po_no, supp_code, service_type,
                 branchname, department_code, project_no, jo_no, service_location,
                 service_period_from, service_period_to, requested_by, remarks, created_by)
            VALUES
                (@service_acceptance_no, @acceptance_date, @po_no, @supp_code, @service_type,
                 @branchname, @department_code, @project_no, @jo_no, @service_location,
                 @service_period_from, @service_period_to, @requested_by, @remarks, @user_id);
        END
        ELSE
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.TWB_ServiceAcceptanceHdr WITH (UPDLOCK, HOLDLOCK)
                WHERE service_acceptance_no = @service_acceptance_no AND status = 'DRAFT'
                  AND row_version = CONVERT(varbinary(8), @expected_row_version, 1)
            )
                THROW 51003, 'Only the current Draft Service Acceptance can be edited. Refresh and try again.', 1;
            UPDATE dbo.TWB_ServiceAcceptanceHdr
            SET acceptance_date = @acceptance_date, po_no = @po_no, supp_code = @supp_code,
                service_type = @service_type, branchname = @branchname,
                department_code = @department_code, project_no = @project_no, jo_no = @jo_no,
                service_location = @service_location, service_period_from = @service_period_from,
                service_period_to = @service_period_to, requested_by = @requested_by,
                remarks = @remarks, modified_by = @user_id, modified_date = SYSUTCDATETIME()
            WHERE service_acceptance_no = @service_acceptance_no;
            DELETE dbo.TWB_ServiceAcceptanceDtl WHERE service_acceptance_no = @service_acceptance_no;
            DELETE dbo.TWB_ServiceAcceptanceChecklist WHERE service_acceptance_no = @service_acceptance_no;
        END;

        INSERT dbo.TWB_ServiceAcceptanceDtl
            (service_acceptance_no, line_seq, po_seq, item_code, service_description,
             unit_of_measure, po_qty, remaining_qty, accepted_qty, rate,
             accepted_amount, tax_scheme_code, remarks)
        SELECT @service_acceptance_no, x.line_seq, x.po_seq, p.item_code, p.item_desc,
               p.po_um, p.qty_po, p.qty_po - ISNULL(used.used_qty, 0), x.accepted_qty,
               ISNULL(p.unit_price, 0), ROUND(x.accepted_qty * ISNULL(p.unit_price, 0), 4),
               UPPER(x.tax_scheme_code), x.remarks
        FROM @details AS x
        INNER JOIN dbo.a_po_det AS p ON p.po_no = @po_no AND p.po_seq = x.po_seq
        OUTER APPLY
        (
            SELECT SUM(d.accepted_qty) AS used_qty
            FROM dbo.TWB_ServiceAcceptanceDtl AS d
            INNER JOIN dbo.TWB_ServiceAcceptanceHdr AS h ON h.service_acceptance_no = d.service_acceptance_no
            WHERE h.po_no = @po_no AND d.po_seq = x.po_seq AND h.status <> 'REVERSED'
        ) AS used;

        INSERT dbo.TWB_ServiceAcceptanceChecklist
            (service_acceptance_no, line_seq, checklist_code, checklist_description,
             is_required, is_completed, completed_by, completed_date, remarks)
        SELECT @service_acceptance_no, line_seq, UPPER(LTRIM(RTRIM(checklist_code))),
               LTRIM(RTRIM(checklist_description)), is_required, is_completed,
               CASE WHEN is_completed = 1 THEN @user_id END,
               CASE WHEN is_completed = 1 THEN SYSUTCDATETIME() END, remarks
        FROM @checklist;

        UPDATE h
        SET total_accepted_amount = x.total_amount,
            completion_percent = c.completion_percent
        FROM dbo.TWB_ServiceAcceptanceHdr AS h
        CROSS APPLY (SELECT ISNULL(SUM(accepted_amount), 0) AS total_amount
                     FROM dbo.TWB_ServiceAcceptanceDtl WHERE service_acceptance_no = @service_acceptance_no) AS x
        CROSS APPLY (SELECT CAST(CASE WHEN COUNT(*) = 0 THEN 0
                                ELSE 100.0 * SUM(CASE WHEN is_completed = 1 THEN 1 ELSE 0 END) / COUNT(*) END AS decimal(5,2)) AS completion_percent
                     FROM dbo.TWB_ServiceAcceptanceChecklist WHERE service_acceptance_no = @service_acceptance_no) AS c
        WHERE h.service_acceptance_no = @service_acceptance_no;

        COMMIT;
        SELECT service_acceptance_no, status, CONVERT(varchar(18), row_version, 1) AS row_version,
               CASE WHEN @is_new = 1 THEN 'Service Acceptance created.' ELSE 'Service Acceptance updated.' END AS message
        FROM dbo.TWB_ServiceAcceptanceHdr WHERE service_acceptance_no = @service_acceptance_no;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_Submit
    @service_acceptance_no varchar(30), @user_id varchar(50), @expected_row_version varchar(18)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
    UPDATE dbo.TWB_ServiceAcceptanceHdr WITH (UPDLOCK)
    SET status = 'SUBMITTED', submitted_by = @user_id, submitted_date = SYSUTCDATETIME(),
        modified_by = @user_id, modified_date = SYSUTCDATETIME()
    WHERE service_acceptance_no = @service_acceptance_no AND status = 'DRAFT'
      AND total_accepted_amount > 0
      AND NOT EXISTS (SELECT 1 FROM dbo.TWB_ServiceAcceptanceChecklist
                      WHERE service_acceptance_no = @service_acceptance_no
                        AND is_required = 1 AND is_completed = 0)
      AND row_version = CONVERT(varbinary(8), @expected_row_version, 1);
    IF @@ROWCOUNT <> 1 BEGIN ROLLBACK; THROW 51003, 'Submit requires the current Draft document, a positive accepted amount, and a completed required checklist.', 1; END;
    COMMIT;
    SELECT service_acceptance_no, status, CONVERT(varchar(18), row_version, 1) AS row_version,
           'Service Acceptance submitted.' AS message
    FROM dbo.TWB_ServiceAcceptanceHdr WHERE service_acceptance_no = @service_acceptance_no;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_Accept
    @service_acceptance_no varchar(30), @user_id varchar(50), @expected_row_version varchar(18)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.TWB_ServiceAcceptanceChecklist
               WHERE service_acceptance_no = @service_acceptance_no AND is_required = 1 AND is_completed = 0)
    BEGIN ROLLBACK; THROW 51000, 'All required checklist items must be complete.', 1; END;
    UPDATE dbo.TWB_ServiceAcceptanceHdr WITH (UPDLOCK)
    SET status = 'ACCEPTED', accepted_by = @user_id, accepted_date = SYSUTCDATETIME(),
        modified_by = @user_id, modified_date = SYSUTCDATETIME()
    WHERE service_acceptance_no = @service_acceptance_no AND status = 'SUBMITTED'
      AND total_accepted_amount > 0
      AND row_version = CONVERT(varbinary(8), @expected_row_version, 1);
    IF @@ROWCOUNT <> 1 BEGIN ROLLBACK; THROW 51003, 'Accept requires the current Submitted document and a positive accepted amount.', 1; END;
    COMMIT;
    SELECT service_acceptance_no, status, CONVERT(varchar(18), row_version, 1) AS row_version,
           'Service accepted.' AS message
    FROM dbo.TWB_ServiceAcceptanceHdr WHERE service_acceptance_no = @service_acceptance_no;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_Post
    @service_acceptance_no varchar(30), @user_id varchar(50), @expected_row_version varchar(18)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
    UPDATE dbo.TWB_ServiceAcceptanceHdr WITH (UPDLOCK)
    SET status = 'POSTED', posted_by = @user_id, posted_date = SYSUTCDATETIME(),
        modified_by = @user_id, modified_date = SYSUTCDATETIME()
    WHERE service_acceptance_no = @service_acceptance_no AND status = 'ACCEPTED'
      AND total_accepted_amount > 0
      AND NOT EXISTS (SELECT 1 FROM dbo.TWB_ServiceAcceptanceChecklist
                      WHERE service_acceptance_no = @service_acceptance_no AND is_required = 1 AND is_completed = 0)
      AND row_version = CONVERT(varbinary(8), @expected_row_version, 1);
    IF @@ROWCOUNT <> 1 BEGIN ROLLBACK; THROW 51003, 'Post requires the current Accepted document, positive amount, and completed checklist.', 1; END;
    COMMIT;
    SELECT service_acceptance_no, status, CONVERT(varchar(18), row_version, 1) AS row_version,
           'Service Acceptance posted and enabled for VP.' AS message
    FROM dbo.TWB_ServiceAcceptanceHdr WHERE service_acceptance_no = @service_acceptance_no;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_Reverse
    @service_acceptance_no varchar(30), @user_id varchar(50),
    @expected_row_version varchar(18), @reverse_reason nvarchar(500)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF NULLIF(LTRIM(RTRIM(@reverse_reason)), '') IS NULL THROW 51000, 'Reversal reason is required.', 1;
    BEGIN TRANSACTION;
    IF EXISTS (SELECT 1 FROM dbo.TWB_ServiceAcceptanceVpLink WITH (UPDLOCK, HOLDLOCK)
               WHERE service_acceptance_no = @service_acceptance_no)
    BEGIN ROLLBACK; THROW 51002, 'Service Acceptance linked to VP cannot be reversed.', 1; END;
    UPDATE dbo.TWB_ServiceAcceptanceHdr WITH (UPDLOCK)
    SET status = 'REVERSED', reversed_by = @user_id, reversed_date = SYSUTCDATETIME(),
        reverse_reason = @reverse_reason, modified_by = @user_id, modified_date = SYSUTCDATETIME()
    WHERE service_acceptance_no = @service_acceptance_no AND status = 'POSTED'
      AND row_version = CONVERT(varbinary(8), @expected_row_version, 1);
    IF @@ROWCOUNT <> 1 BEGIN ROLLBACK; THROW 51003, 'Reverse requires the current Posted document.', 1; END;
    COMMIT;
    SELECT service_acceptance_no, status, CONVERT(varchar(18), row_version, 1) AS row_version,
           'Service Acceptance reversed.' AS message
    FROM dbo.TWB_ServiceAcceptanceHdr WHERE service_acceptance_no = @service_acceptance_no;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_VpSourceLookup
    @supp_code varchar(10) = NULL, @branchname varchar(50) = NULL, @search nvarchar(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (200) h.service_acceptance_no, h.acceptance_date, h.po_no, h.supp_code,
           LTRIM(RTRIM(s.supp_name)) AS supp_name, h.branchname,
           h.total_accepted_amount AS accepted_amount
    FROM dbo.TWB_ServiceAcceptanceHdr AS h
    INNER JOIN dbo.a_suppliers AS s ON s.supp_code = h.supp_code
    WHERE h.status = 'POSTED'
      AND NOT EXISTS (SELECT 1 FROM dbo.TWB_ServiceAcceptanceVpLink AS l
                      WHERE l.service_acceptance_no = h.service_acceptance_no)
      AND (@supp_code IS NULL OR h.supp_code = @supp_code)
      AND (@branchname IS NULL OR h.branchname = @branchname)
      AND (@search IS NULL OR h.service_acceptance_no LIKE '%' + @search + '%' OR h.po_no LIKE '%' + @search + '%')
    ORDER BY h.acceptance_date, h.service_acceptance_no;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ServiceAcceptance_LinkVp
    @service_acceptance_no varchar(30), @vp_no varchar(30), @user_id varchar(50)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRANSACTION;
    IF NOT EXISTS (SELECT 1 FROM dbo.TWB_ServiceAcceptanceHdr WITH (UPDLOCK, HOLDLOCK)
                   WHERE service_acceptance_no = @service_acceptance_no AND status = 'POSTED')
    BEGIN ROLLBACK; THROW 51000, 'Only a Posted Service Acceptance can be linked to VP.', 1; END;
    IF EXISTS (SELECT 1 FROM dbo.TWB_ServiceAcceptanceVpLink WITH (UPDLOCK, HOLDLOCK)
               WHERE service_acceptance_no = @service_acceptance_no)
    BEGIN ROLLBACK; THROW 51001, 'Service Acceptance is already linked to VP.', 1; END;
    INSERT dbo.TWB_ServiceAcceptanceVpLink(service_acceptance_no, vp_no, linked_by)
    VALUES (@service_acceptance_no, @vp_no, @user_id);
    COMMIT;
END;
GO

IF OBJECT_ID(N'dbo.sec_modules', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'SERVICE_ACCEPTANCE')
        INSERT dbo.sec_modules(module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES ('SERVICE_ACCEPTANCE', 'Service Acceptance', NULL, NULL, 89, 1, 1);
    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'SERVICE_ACCEPTANCE_ENTRY')
        INSERT dbo.sec_modules(module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES ('SERVICE_ACCEPTANCE_ENTRY', 'Service Acceptance Entry', '/service-acceptance/new', 'SERVICE_ACCEPTANCE', 90, 1, 1);
    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'SERVICE_ACCEPTANCE_LIST')
        INSERT dbo.sec_modules(module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES ('SERVICE_ACCEPTANCE_LIST', 'Service Acceptance List', '/service-acceptance', 'SERVICE_ACCEPTANCE', 91, 1, 1);
END;
GO

-- Read-only verification
SELECT o.name, o.type_desc
FROM sys.objects AS o
WHERE o.name LIKE 'TWB_ServiceAcceptance%' OR o.name LIKE 'usp_ServiceAcceptance_%'
ORDER BY o.type_desc, o.name;
SELECT name FROM sys.table_types WHERE name IN ('ServiceAcceptanceDetailType','ServiceAcceptanceChecklistType');
GO
