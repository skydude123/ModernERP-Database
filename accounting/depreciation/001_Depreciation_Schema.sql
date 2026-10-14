SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.a_asset_master','U') IS NULL
    RAISERROR('dbo.a_asset_master is required. Deploy and post Asset Acceptance before depreciation.',16,1);
GO

IF OBJECT_ID('dbo.a_dep_run_series','U') IS NULL
BEGIN
    CREATE TABLE dbo.a_dep_run_series
    (
        series_key VARCHAR(20) NOT NULL CONSTRAINT PK_a_dep_run_series PRIMARY KEY,
        last_no INT NOT NULL,
        updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_dep_run_series_updated DEFAULT SYSUTCDATETIME()
    );
    INSERT dbo.a_dep_run_series(series_key,last_no) VALUES('DEP',0);
END;
GO

IF OBJECT_ID('dbo.a_dep_run_hdr','U') IS NULL
CREATE TABLE dbo.a_dep_run_hdr
(
    dep_run_no VARCHAR(30) NOT NULL CONSTRAINT PK_a_dep_run_hdr PRIMARY KEY,
    period_key CHAR(6) NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    run_date DATE NOT NULL,
    branch_code VARCHAR(50) NULL,
    asset_category_code VARCHAR(30) NULL,
    method_code VARCHAR(30) NULL,
    depreciation_convention VARCHAR(20) NOT NULL,
    include_zero_amount BIT NOT NULL,
    status VARCHAR(15) NOT NULL,
    asset_count INT NOT NULL CONSTRAINT DF_a_dep_run_hdr_count DEFAULT 0,
    total_acquisition_cost DECIMAL(19,4) NOT NULL CONSTRAINT DF_a_dep_run_hdr_cost DEFAULT 0,
    total_opening_accumulated_depreciation DECIMAL(19,4) NOT NULL CONSTRAINT DF_a_dep_run_hdr_open_acc DEFAULT 0,
    total_current_depreciation DECIMAL(19,4) NOT NULL CONSTRAINT DF_a_dep_run_hdr_current DEFAULT 0,
    total_closing_accumulated_depreciation DECIMAL(19,4) NOT NULL CONSTRAINT DF_a_dep_run_hdr_close_acc DEFAULT 0,
    total_closing_net_book_value DECIMAL(19,4) NOT NULL CONSTRAINT DF_a_dep_run_hdr_close_nbv DEFAULT 0,
    journal_no VARCHAR(30) NULL,
    reversal_journal_no VARCHAR(30) NULL,
    remarks NVARCHAR(500) NULL,
    prepared_by VARCHAR(50) NOT NULL,
    submitted_by VARCHAR(50) NULL,
    approved_by VARCHAR(50) NULL,
    posted_by VARCHAR(50) NULL,
    reversed_by VARCHAR(50) NULL,
    cancelled_by VARCHAR(50) NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_dep_run_hdr_created DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    submitted_at DATETIME2(0) NULL,
    approved_at DATETIME2(0) NULL,
    posted_at DATETIME2(0) NULL,
    reversed_at DATETIME2(0) NULL,
    cancelled_at DATETIME2(0) NULL,
    cancellation_reason NVARCHAR(500) NULL,
    row_version ROWVERSION NOT NULL,
    CONSTRAINT CK_a_dep_run_period CHECK(period_key NOT LIKE '%[^0-9]%'),
    CONSTRAINT CK_a_dep_run_convention CHECK(depreciation_convention IN('FULL_MONTH','NEXT_MONTH')),
    CONSTRAINT CK_a_dep_run_status CHECK(status IN('DRAFT','SUBMITTED','APPROVED','POSTED','REVERSED','CANCELLED'))
);
GO

IF OBJECT_ID('dbo.a_dep_run_dtl','U') IS NULL
CREATE TABLE dbo.a_dep_run_dtl
(
    dep_run_no VARCHAR(30) NOT NULL,
    line_no INT NOT NULL,
    asset_id BIGINT NOT NULL,
    asset_code VARCHAR(50) NOT NULL,
    asset_description NVARCHAR(255) NOT NULL,
    asset_category_code VARCHAR(30) NULL,
    branch_code VARCHAR(50) NULL,
    location_code VARCHAR(30) NULL,
    custodian_code VARCHAR(50) NULL,
    acquisition_date DATE NULL,
    in_service_date DATE NULL,
    depreciation_start_date DATE NULL,
    method_code VARCHAR(30) NOT NULL,
    convention VARCHAR(20) NOT NULL,
    acquisition_cost DECIMAL(19,4) NOT NULL,
    residual_value DECIMAL(19,4) NOT NULL,
    useful_life_months INT NOT NULL,
    periods_depreciated_before INT NOT NULL,
    opening_accumulated_depreciation DECIMAL(19,4) NOT NULL,
    opening_net_book_value DECIMAL(19,4) NOT NULL,
    depreciation_rate DECIMAL(19,8) NOT NULL,
    current_depreciation DECIMAL(19,4) NOT NULL,
    closing_accumulated_depreciation DECIMAL(19,4) NOT NULL,
    closing_net_book_value DECIMAL(19,4) NOT NULL,
    asset_cost_account VARCHAR(50) NULL,
    depreciation_expense_account VARCHAR(50) NULL,
    accumulated_depreciation_account VARCHAR(50) NULL,
    is_selected BIT NOT NULL,
    eligibility_status VARCHAR(20) NOT NULL,
    eligibility_message NVARCHAR(500) NULL,
    posting_status VARCHAR(20) NULL,
    journal_line_reference VARCHAR(100) NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_dep_run_dtl_created DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2(0) NULL,
    CONSTRAINT PK_a_dep_run_dtl PRIMARY KEY(dep_run_no,line_no),
    CONSTRAINT FK_a_dep_run_dtl_hdr FOREIGN KEY(dep_run_no) REFERENCES dbo.a_dep_run_hdr(dep_run_no),
    CONSTRAINT UQ_a_dep_run_dtl_asset UNIQUE(dep_run_no,asset_id)
);
GO

IF OBJECT_ID('dbo.a_dep_schedule','U') IS NULL
CREATE TABLE dbo.a_dep_schedule
(
    schedule_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_a_dep_schedule PRIMARY KEY,
    dep_run_no VARCHAR(30) NOT NULL,
    asset_id BIGINT NOT NULL,
    period_key CHAR(6) NOT NULL,
    acquisition_cost DECIMAL(19,4) NOT NULL,
    residual_value DECIMAL(19,4) NOT NULL,
    opening_accumulated_depreciation DECIMAL(19,4) NOT NULL,
    current_depreciation DECIMAL(19,4) NOT NULL,
    closing_accumulated_depreciation DECIMAL(19,4) NOT NULL,
    closing_net_book_value DECIMAL(19,4) NOT NULL,
    journal_no VARCHAR(30) NOT NULL,
    is_active BIT NOT NULL CONSTRAINT DF_a_dep_schedule_active DEFAULT 1,
    reversed_by_run_no VARCHAR(30) NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_dep_schedule_created DEFAULT SYSUTCDATETIME(),
    reversed_at DATETIME2(0) NULL,
    CONSTRAINT FK_a_dep_schedule_run FOREIGN KEY(dep_run_no) REFERENCES dbo.a_dep_run_hdr(dep_run_no)
);
GO

IF OBJECT_ID('dbo.a_dep_journal_hdr','U') IS NULL
CREATE TABLE dbo.a_dep_journal_hdr
(
    journal_no VARCHAR(30) NOT NULL CONSTRAINT PK_a_dep_journal_hdr PRIMARY KEY,
    journal_date DATE NOT NULL,
    period_key CHAR(6) NOT NULL,
    source_type VARCHAR(20) NOT NULL,
    source_no VARCHAR(30) NOT NULL,
    status VARCHAR(15) NOT NULL,
    total_debit DECIMAL(19,4) NOT NULL,
    total_credit DECIMAL(19,4) NOT NULL,
    narration NVARCHAR(500) NULL,
    created_by VARCHAR(50) NOT NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_dep_journal_hdr_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_a_dep_journal_source UNIQUE(source_type,source_no),
    CONSTRAINT CK_a_dep_journal_balance CHECK(total_debit=total_credit)
);
GO

IF OBJECT_ID('dbo.a_dep_journal_dtl','U') IS NULL
CREATE TABLE dbo.a_dep_journal_dtl
(
    journal_no VARCHAR(30) NOT NULL,
    line_no INT NOT NULL,
    branch_code VARCHAR(50) NULL,
    account_code VARCHAR(50) NOT NULL,
    debit DECIMAL(19,4) NOT NULL,
    credit DECIMAL(19,4) NOT NULL,
    reference VARCHAR(100) NOT NULL,
    narration NVARCHAR(500) NULL,
    CONSTRAINT PK_a_dep_journal_dtl PRIMARY KEY(journal_no,line_no),
    CONSTRAINT FK_a_dep_journal_dtl_hdr FOREIGN KEY(journal_no) REFERENCES dbo.a_dep_journal_hdr(journal_no),
    CONSTRAINT CK_a_dep_journal_side CHECK((debit>0 AND credit=0) OR (credit>0 AND debit=0))
);
GO

IF OBJECT_ID('dbo.a_dep_run_journal_link','U') IS NULL
CREATE TABLE dbo.a_dep_run_journal_link
(
    dep_run_no VARCHAR(30) NOT NULL CONSTRAINT PK_a_dep_run_journal_link PRIMARY KEY,
    journal_no VARCHAR(30) NOT NULL,
    posted_at DATETIME2(0) NOT NULL,
    is_reversed BIT NOT NULL CONSTRAINT DF_a_dep_link_reversed DEFAULT 0,
    reversal_journal_no VARCHAR(30) NULL,
    reversed_at DATETIME2(0) NULL,
    CONSTRAINT FK_a_dep_link_run FOREIGN KEY(dep_run_no) REFERENCES dbo.a_dep_run_hdr(dep_run_no)
);
GO

IF OBJECT_ID('dbo.a_dep_run_reversal_log','U') IS NULL
CREATE TABLE dbo.a_dep_run_reversal_log
(
    reversal_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_a_dep_reversal_log PRIMARY KEY,
    dep_run_no VARCHAR(30) NOT NULL,
    original_journal_no VARCHAR(30) NOT NULL,
    reversal_journal_no VARCHAR(30) NOT NULL,
    reason NVARCHAR(500) NOT NULL,
    reversed_by VARCHAR(50) NOT NULL,
    reversed_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_dep_reversal_at DEFAULT SYSUTCDATETIME()
);
GO
