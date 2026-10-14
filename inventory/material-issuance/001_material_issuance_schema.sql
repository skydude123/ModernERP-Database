SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.a_issue_hdr','row_version') IS NULL
    ALTER TABLE dbo.a_issue_hdr ADD row_version ROWVERSION NOT NULL;
IF COL_LENGTH('dbo.a_issue_hdr','source_no') IS NULL
    ALTER TABLE dbo.a_issue_hdr ADD source_no VARCHAR(20) NULL;
GO

IF OBJECT_ID('dbo.a_issue_number_series','U') IS NULL
BEGIN
    CREATE TABLE dbo.a_issue_number_series
    (
        series_key VARCHAR(20) NOT NULL CONSTRAINT PK_a_issue_number_series PRIMARY KEY,
        last_no INT NOT NULL,
        date_changed DATETIME2(0) NOT NULL CONSTRAINT DF_a_issue_series_changed DEFAULT SYSUTCDATETIME()
    );
    INSERT dbo.a_issue_number_series(series_key,last_no) VALUES('MI',0);
END;
GO

IF OBJECT_ID('dbo.a_issue_lot','U') IS NULL
CREATE TABLE dbo.a_issue_lot
(
    allocation_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_a_issue_lot PRIMARY KEY,
    issue_no CHAR(10) NOT NULL,
    issue_seq INT NOT NULL,
    rr_lot_row_no INT NOT NULL,
    rr_no CHAR(10) NOT NULL,
    item_code VARCHAR(20) NOT NULL,
    whse_code VARCHAR(5) NOT NULL,
    allocated_base_qty DECIMAL(18,4) NOT NULL,
    unit_cost DECIMAL(18,4) NOT NULL,
    issue_value DECIMAL(18,4) NOT NULL,
    is_active BIT NOT NULL CONSTRAINT DF_a_issue_lot_active DEFAULT 1,
    created_by VARCHAR(10) NOT NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_issue_lot_created DEFAULT SYSUTCDATETIME(),
    reversed_at DATETIME2(0) NULL,
    CONSTRAINT FK_a_issue_lot_hdr FOREIGN KEY(issue_no) REFERENCES dbo.a_issue_hdr(issue_no),
    CONSTRAINT CK_a_issue_lot_qty CHECK(allocated_base_qty > 0)
);
GO

IF OBJECT_ID('dbo.a_issue_account_map','U') IS NULL
CREATE TABLE dbo.a_issue_account_map
(
    map_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_a_issue_account_map PRIMARY KEY,
    source_type CHAR(3) NOT NULL,
    item_code VARCHAR(20) NULL,
    debit_account VARCHAR(10) NOT NULL,
    inventory_account VARCHAR(10) NOT NULL,
    is_active BIT NOT NULL CONSTRAINT DF_a_issue_account_map_active DEFAULT 1,
    updated_by VARCHAR(10) NOT NULL,
    updated_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_issue_account_map_changed DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_a_issue_account_map_source CHECK(source_type IN('PRD','JOB','PRJ','DPT','JOT','DIR'))
);
CREATE UNIQUE INDEX UX_a_issue_account_map_item
ON dbo.a_issue_account_map(source_type,item_code) WHERE item_code IS NOT NULL;
CREATE UNIQUE INDEX UX_a_issue_account_map_default
ON dbo.a_issue_account_map(source_type) WHERE item_code IS NULL;
GO

IF OBJECT_ID('dbo.a_issue_reversal_log','U') IS NULL
CREATE TABLE dbo.a_issue_reversal_log
(
    reversal_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_a_issue_reversal_log PRIMARY KEY,
    issue_no CHAR(10) NOT NULL,
    reason NVARCHAR(500) NOT NULL,
    reversed_by VARCHAR(10) NOT NULL,
    reversed_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_issue_reversal_at DEFAULT SYSUTCDATETIME(),
    original_row_version VARBINARY(8) NOT NULL
);
GO

IF OBJECT_ID('dbo.a_issue_inventory_movement','U') IS NULL
CREATE TABLE dbo.a_issue_inventory_movement
(
    movement_id BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_a_issue_inventory_movement PRIMARY KEY,
    issue_no CHAR(10) NOT NULL,
    issue_seq INT NOT NULL,
    allocation_id BIGINT NOT NULL,
    movement_type CHAR(3) NOT NULL,
    movement_date DATETIME NOT NULL,
    whse_code VARCHAR(5) NOT NULL,
    item_code VARCHAR(20) NOT NULL,
    base_um CHAR(3) NOT NULL,
    base_qty DECIMAL(18,4) NOT NULL,
    unit_cost DECIMAL(18,4) NOT NULL,
    movement_value DECIMAL(18,4) NOT NULL,
    beg_bal_qty DECIMAL(18,4) NOT NULL,
    beg_bal_cost DECIMAL(18,4) NOT NULL,
    end_bal_qty DECIMAL(18,4) NOT NULL,
    end_bal_cost DECIMAL(18,4) NOT NULL,
    user_id VARCHAR(10) NOT NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_issue_move_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_a_issue_move_type CHECK(movement_type IN('OUT','REV'))
);
GO

IF OBJECT_ID('dbo.a_issue_gl_hdr','U') IS NULL
CREATE TABLE dbo.a_issue_gl_hdr
(
    journal_no VARCHAR(15) NOT NULL CONSTRAINT PK_a_issue_gl_hdr PRIMARY KEY,
    issue_no CHAR(10) NOT NULL,
    journal_type VARCHAR(10) NOT NULL,
    journal_date DATE NOT NULL,
    source_type CHAR(3) NOT NULL,
    total_debit DECIMAL(18,4) NOT NULL,
    total_credit DECIMAL(18,4) NOT NULL,
    created_by VARCHAR(10) NOT NULL,
    created_at DATETIME2(0) NOT NULL CONSTRAINT DF_a_issue_gl_hdr_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT UQ_a_issue_gl_source UNIQUE(issue_no,journal_type),
    CONSTRAINT CK_a_issue_gl_balanced CHECK(total_debit=total_credit)
);
GO

IF OBJECT_ID('dbo.a_issue_gl_det','U') IS NULL
CREATE TABLE dbo.a_issue_gl_det
(
    journal_no VARCHAR(15) NOT NULL,
    line_no INT NOT NULL,
    account_code VARCHAR(10) NOT NULL,
    debit DECIMAL(18,4) NOT NULL,
    credit DECIMAL(18,4) NOT NULL,
    reference VARCHAR(20) NOT NULL,
    narration NVARCHAR(200) NULL,
    CONSTRAINT PK_a_issue_gl_det PRIMARY KEY(journal_no,line_no),
    CONSTRAINT FK_a_issue_gl_det_hdr FOREIGN KEY(journal_no) REFERENCES dbo.a_issue_gl_hdr(journal_no),
    CONSTRAINT CK_a_issue_gl_det_side CHECK((debit>0 AND credit=0) OR (credit>0 AND debit=0))
);
GO

IF TYPE_ID('dbo.MaterialIssuanceDetailBatchType') IS NULL
EXEC('CREATE TYPE dbo.MaterialIssuanceDetailBatchType AS TABLE
(
    issue_seq INT NOT NULL,
    item_code VARCHAR(20) NOT NULL,
    item_desc VARCHAR(60) NOT NULL,
    qty_iss DECIMAL(18,4) NOT NULL,
    issue_um CHAR(3) NOT NULL,
    base_um CHAR(3) NOT NULL,
    conv_factor DECIMAL(18,4) NOT NULL,
    cc_code VARCHAR(5) NULL,
    remarks VARCHAR(100) NULL
)');
GO

IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.a_issue_lot') AND name='IX_a_issue_lot_fifo')
CREATE INDEX IX_a_issue_lot_fifo ON dbo.a_issue_lot(rr_lot_row_no,is_active) INCLUDE(allocated_base_qty,issue_value);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.a_issue_hdr') AND name='IX_a_issue_hdr_register')
CREATE INDEX IX_a_issue_hdr_register ON dbo.a_issue_hdr(issue_date DESC,status,trans_type,whse_code) INCLUDE(reference,source_no,no_of_reverts);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.a_rr_lot') AND name='IX_a_rr_lot_fifo_issue')
CREATE INDEX IX_a_rr_lot_fifo_issue ON dbo.a_rr_lot(whse_code,item_code,trans_date,row_no) INCLUDE(base_qty,qty_issued,unit_cost,base_um,trans_no);
GO
