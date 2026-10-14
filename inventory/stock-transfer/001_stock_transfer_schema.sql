SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.a_stock_transfer_hdr', 'row_version') IS NULL
    ALTER TABLE dbo.a_stock_transfer_hdr ADD row_version ROWVERSION NOT NULL;
GO

IF COL_LENGTH('dbo.a_stock_transfer_det', 'unit_cost_snapshot') IS NULL
    ALTER TABLE dbo.a_stock_transfer_det ADD unit_cost_snapshot DECIMAL(18,4) NULL;

IF COL_LENGTH('dbo.a_stock_transfer_det', 'transfer_cost') IS NULL
    ALTER TABLE dbo.a_stock_transfer_det ADD transfer_cost DECIMAL(18,4) NULL;
GO

IF TYPE_ID('dbo.StockTransferDetailBatchType') IS NULL
EXEC('CREATE TYPE dbo.StockTransferDetailBatchType AS TABLE
(
    st_seq INT NOT NULL,
    item_code VARCHAR(20) NOT NULL,
    qty_iss DECIMAL(18,4) NOT NULL,
    xfer_um CHAR(3) NOT NULL,
    conv_factor DECIMAL(18,4) NOT NULL,
    base_um CHAR(3) NOT NULL
)');
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.a_stock_transfer_hdr')
      AND name = 'IX_a_stock_transfer_hdr_register'
)
CREATE INDEX IX_a_stock_transfer_hdr_register
ON dbo.a_stock_transfer_hdr(st_date DESC, status, whse_code_fr, whse_code_to)
INCLUDE(reference, received_by, processed_by);
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.a_stock_transfer_det')
      AND name = 'IX_a_stock_transfer_det_item'
)
CREATE INDEX IX_a_stock_transfer_det_item
ON dbo.a_stock_transfer_det(item_code, st_no)
INCLUDE(qty_iss, conv_factor, transfer_cost);
GO
