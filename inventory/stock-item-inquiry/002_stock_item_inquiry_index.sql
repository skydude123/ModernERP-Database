/* Narrow access-path index for the Stock Card query. Existing warehouse and
   receipt-lot indexes were reviewed and are already adequate. */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.a_inv_hst')
      AND name = N'IX_a_inv_hst_stock_item_inquiry'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_a_inv_hst_stock_item_inquiry
        ON dbo.a_inv_hst(item_code, whse_code, trans_date, row_no);
END;
GO
