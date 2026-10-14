/*
Run only in a controlled non-production session after scripts 001-003.
All test data and inventory movements are rolled back before this script exits.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @owns_transaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
IF @owns_transaction = 1
    BEGIN TRANSACTION;
ELSE
    SAVE TRANSACTION StockTransferSmoke;

BEGIN TRY
    DECLARE @source_whse VARCHAR(5),
            @destination_whse VARCHAR(5),
            @item_code VARCHAR(20),
            @base_um CHAR(3),
            @test_date DATE,
            @st_no VARCHAR(10) = NULL,
            @row_version VARBINARY(8),
            @control_before INT,
            @source_qty_before DECIMAL(18,4),
            @source_cost_before DECIMAL(18,4),
            @destination_qty_before DECIMAL(18,4),
            @destination_cost_before DECIMAL(18,4),
            @source_qty_after DECIMAL(18,4),
            @source_cost_after DECIMAL(18,4),
            @destination_qty_after DECIMAL(18,4),
            @destination_cost_after DECIMAL(18,4),
            @qty DECIMAL(18,4) = 0.0100;

    SELECT TOP (1)
           @source_whse = source_item.whse_code,
           @destination_whse = destination_item.whse_code,
           @item_code = source_item.item_code,
           @base_um = source_item.base_um
    FROM dbo.a_whse_item AS source_item
    INNER JOIN dbo.a_whse_item AS destination_item
      ON destination_item.item_code = source_item.item_code
     AND destination_item.whse_code <> source_item.whse_code
    INNER JOIN dbo.a_whse AS source_storage ON source_storage.whse_code = source_item.whse_code
    INNER JOIN dbo.a_whse AS destination_storage ON destination_storage.whse_code = destination_item.whse_code
    INNER JOIN dbo.a_item_master AS item ON item.item_code = source_item.item_code
    WHERE source_item.qty_rcv - source_item.qty_issued >= @qty
      AND source_item.on_hand_cost >= 0
      AND item.active = 'Y'
      AND ISNULL(item.blocked, 'N') <> 'Y'
    ORDER BY source_item.item_code, source_item.whse_code, destination_item.whse_code;

    IF @item_code IS NULL
        RAISERROR('Smoke test requires one active item configured in two warehouses with source stock.', 16, 1);

    SELECT TOP (1) @test_date = CONVERT(DATE, date_from)
    FROM dbo.m_fiscal_period
    ORDER BY current_period_flag DESC, fiscal_year DESC, fiscal_period DESC;

    SELECT @control_before = CONVERT(INT, st_no) FROM dbo.c_company;
    SELECT @source_qty_before = qty_rcv - qty_issued,
           @source_cost_before = on_hand_cost
    FROM dbo.a_whse_item
    WHERE whse_code = @source_whse AND item_code = @item_code;
    SELECT @destination_qty_before = qty_rcv - qty_issued,
           @destination_cost_before = on_hand_cost
    FROM dbo.a_whse_item
    WHERE whse_code = @destination_whse AND item_code = @item_code;

    DECLARE @details dbo.StockTransferDetailBatchType;
    INSERT @details(st_seq, item_code, qty_iss, xfer_um, conv_factor, base_um)
    VALUES(1, @item_code, @qty, @base_um, 1, @base_um);

    EXEC dbo.usp_StockTransfer_UpsertBatch
         @st_no = @st_no OUTPUT,
         @expected_row_version = NULL,
         @st_date = @test_date,
         @source_whse_code = @source_whse,
         @destination_whse_code = @destination_whse,
         @reference = 'ROLLBACK SMOKE TEST',
         @received_by = NULL,
         @received_date = NULL,
         @remarks = 'Rollback-only stock transfer verification',
         @target_status = 'N',
         @user_id = 'CODEX',
         @details = @details;

    IF (SELECT CONVERT(INT, st_no) FROM dbo.c_company) <> @control_before + 1
        RAISERROR('Draft did not allocate exactly one company control number.', 16, 1);
    IF NOT EXISTS (SELECT 1 FROM dbo.a_stock_transfer_hdr WHERE st_no = @st_no AND status = 'N')
        RAISERROR('Draft header was not saved with status N.', 16, 1);
    IF (SELECT COUNT(*) FROM dbo.a_stock_transfer_det WHERE st_no = @st_no) <> 1
        RAISERROR('Draft detail batch was not saved completely.', 16, 1);
    IF EXISTS (SELECT 1 FROM dbo.a_inv_hst WHERE trans_no = @st_no AND trans_type IN ('STO', 'STI'))
        RAISERROR('Draft unexpectedly created inventory history.', 16, 1);
    IF EXISTS
    (
        SELECT 1 FROM dbo.a_whse_item
        WHERE whse_code = @source_whse AND item_code = @item_code
          AND (qty_rcv - qty_issued <> @source_qty_before OR on_hand_cost <> @source_cost_before)
    )
        RAISERROR('Draft unexpectedly changed source inventory.', 16, 1);

    SELECT @row_version = row_version FROM dbo.a_stock_transfer_hdr WHERE st_no = @st_no;

    EXEC dbo.usp_StockTransfer_UpsertBatch
         @st_no = @st_no OUTPUT,
         @expected_row_version = @row_version,
         @st_date = @test_date,
         @source_whse_code = @source_whse,
         @destination_whse_code = @destination_whse,
         @reference = 'ROLLBACK SMOKE TEST',
         @received_by = 'CODEX',
         @received_date = @test_date,
         @remarks = 'Rollback-only stock transfer verification',
         @target_status = 'A',
         @user_id = 'CODEX',
         @details = @details;

    SELECT @source_qty_after = qty_rcv - qty_issued,
           @source_cost_after = on_hand_cost
    FROM dbo.a_whse_item
    WHERE whse_code = @source_whse AND item_code = @item_code;
    SELECT @destination_qty_after = qty_rcv - qty_issued,
           @destination_cost_after = on_hand_cost
    FROM dbo.a_whse_item
    WHERE whse_code = @destination_whse AND item_code = @item_code;

    IF NOT EXISTS (SELECT 1 FROM dbo.a_stock_transfer_hdr WHERE st_no = @st_no AND status = 'A')
        RAISERROR('Posting did not transition the document to A.', 16, 1);
    IF @source_qty_before - @source_qty_after <> @qty
       OR @destination_qty_after - @destination_qty_before <> @qty
        RAISERROR('Posting did not move equal base quantities.', 16, 1);
    IF ROUND(@source_cost_before - @source_cost_after, 4)
       <> ROUND(@destination_cost_after - @destination_cost_before, 4)
        RAISERROR('Posting did not move equal inventory cost.', 16, 1);
    IF (SELECT COUNT(*) FROM dbo.a_inv_hst WHERE trans_no = @st_no AND trans_type IN ('STO', 'STI')) <> 2
        RAISERROR('Posting did not create the expected OUT/IN history pair.', 16, 1);
    IF NOT EXISTS (SELECT 1 FROM dbo.a_inv_hst WHERE trans_no = @st_no AND trans_type = 'STO' AND trans_qty = -@qty)
       OR NOT EXISTS (SELECT 1 FROM dbo.a_inv_hst WHERE trans_no = @st_no AND trans_type = 'STI' AND trans_qty = @qty)
        RAISERROR('Posting history signs or quantities are incorrect.', 16, 1);

    SELECT 'PASS' AS result,
           'Draft allocation/save and atomic posting quantity/cost/history checks passed; all changes will be rolled back.' AS message;

    IF @owns_transaction = 1
        ROLLBACK TRANSACTION;
    ELSE
        ROLLBACK TRANSACTION StockTransferSmoke;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @owns_transaction = 1 OR XACT_STATE() = -1
            ROLLBACK TRANSACTION;
        ELSE
            ROLLBACK TRANSACTION StockTransferSmoke;
    END;
    THROW;
END CATCH;
GO
