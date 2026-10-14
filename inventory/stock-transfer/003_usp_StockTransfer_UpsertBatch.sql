CREATE OR ALTER PROCEDURE dbo.usp_StockTransfer_UpsertBatch
    @st_no VARCHAR(10) = NULL OUTPUT,
    @expected_row_version VARBINARY(8) = NULL,
    @st_date DATE,
    @source_whse_code VARCHAR(5),
    @destination_whse_code VARCHAR(5),
    @reference VARCHAR(20),
    @received_by VARCHAR(10) = NULL,
    @received_date DATETIME = NULL,
    @remarks VARCHAR(500) = NULL,
    @target_status CHAR(1),
    @user_id VARCHAR(10),
    @details dbo.StockTransferDetailBatchType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @st_no = NULLIF(LTRIM(RTRIM(@st_no)), '');
    SET @source_whse_code = LTRIM(RTRIM(@source_whse_code));
    SET @destination_whse_code = LTRIM(RTRIM(@destination_whse_code));
    SET @reference = LTRIM(RTRIM(@reference));
    SET @received_by = NULLIF(LTRIM(RTRIM(@received_by)), '');

    IF @target_status NOT IN ('N', 'A')
        THROW 51200, 'Target status must be N or A.', 1;
    IF @source_whse_code = @destination_whse_code
        THROW 51201, 'Source and destination warehouses must be different.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.a_whse WHERE whse_code = @source_whse_code)
        THROW 51202, 'Source warehouse does not exist in dbo.a_whse.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.a_whse WHERE whse_code = @destination_whse_code)
        THROW 51203, 'Destination warehouse does not exist in dbo.a_whse.', 1;
    IF NULLIF(@reference, '') IS NULL
        THROW 51204, 'Reference is required.', 1;
    IF @target_status = 'A' AND @received_by IS NULL
        THROW 51205, 'Received by is required before posting.', 1;
    IF NOT EXISTS (SELECT 1 FROM @details)
        THROW 51206, 'At least one stock-transfer detail is required.', 1;
    IF EXISTS (SELECT 1 FROM @details WHERE qty_iss <= 0 OR conv_factor <= 0)
        THROW 51207, 'Detail quantities and conversion factors must be positive.', 1;
    IF EXISTS (SELECT 1 FROM @details GROUP BY item_code HAVING COUNT(*) > 1)
        THROW 51208, 'Duplicate item codes are not allowed in one stock transfer.', 1;
    IF EXISTS (SELECT 1 FROM @details GROUP BY st_seq HAVING COUNT(*) > 1)
        THROW 51209, 'Duplicate stock-transfer sequences are not allowed.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @details AS d
        LEFT JOIN dbo.a_item_master AS i ON i.item_code = d.item_code
        WHERE i.item_code IS NULL OR i.active <> 'Y' OR ISNULL(i.blocked, 'N') = 'Y'
    )
        THROW 51210, 'One or more transfer items are missing, inactive, or blocked.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @details AS d
        LEFT JOIN dbo.a_whse_item AS wi
          ON wi.whse_code = @source_whse_code
         AND wi.item_code = d.item_code
        WHERE wi.item_code IS NULL OR wi.qty_rcv - wi.qty_issued <= 0
    )
        THROW 51210, 'Source warehouse-item stock is missing or has no on-hand quantity.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @is_new BIT = CASE WHEN @st_no IS NULL THEN 1 ELSE 0 END,
                @current_status CHAR(1),
                @fiscal_year INT,
                @fiscal_period INT,
                @company_code CHAR(5),
                @next_number INT;

        SELECT TOP (1)
               @fiscal_year = fiscal_year,
               @fiscal_period = fiscal_period
        FROM dbo.m_fiscal_period
        WHERE @st_date >= CONVERT(DATE, date_from)
          AND @st_date <= CONVERT(DATE, date_to)
        ORDER BY fiscal_year, fiscal_period;

        IF @fiscal_year IS NULL OR @fiscal_period IS NULL
            THROW 51211, 'The stock-transfer date is not configured in dbo.m_fiscal_period.', 1;

        IF @is_new = 1
        BEGIN
            IF (SELECT COUNT_BIG(*) FROM dbo.c_company WITH (UPDLOCK, HOLDLOCK)) <> 1
                THROW 51212, 'Stock-transfer numbering requires exactly one company row.', 1;

            IF EXISTS
            (
                SELECT 1
                FROM dbo.c_company
                WHERE NULLIF(LTRIM(RTRIM(st_no)), '') IS NULL
                   OR st_no LIKE '%[^0-9]%'
            )
                THROW 51213, 'The legacy stock-transfer control must contain digits only.', 1;

            SELECT @company_code = co_code,
                   @next_number = CONVERT(INT, st_no) + 1
            FROM dbo.c_company WITH (UPDLOCK, HOLDLOCK);

            IF @next_number IS NULL OR @next_number > 999999
                THROW 51213, 'The legacy six-digit stock-transfer number is invalid or exhausted.', 1;

            SET @st_no = RIGHT('000000' + CONVERT(VARCHAR(6), @next_number), 6);

            UPDATE dbo.c_company
            SET st_no = @st_no,
                date_changed = GETDATE()
            WHERE co_code = @company_code;

            IF EXISTS (SELECT 1 FROM dbo.a_stock_transfer_hdr WITH (UPDLOCK, HOLDLOCK) WHERE st_no = @st_no)
                THROW 51214, 'The allocated stock-transfer number already exists.', 1;
        END
        ELSE
        BEGIN
            SELECT @current_status = status
            FROM dbo.a_stock_transfer_hdr WITH (UPDLOCK, HOLDLOCK)
            WHERE st_no = @st_no;

            IF @current_status IS NULL
                THROW 51215, 'Stock transfer was not found.', 1;
            IF @current_status <> 'N'
                THROW 51216, 'Only a Draft stock transfer can be edited or posted.', 1;
            IF @expected_row_version IS NULL
               OR NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.a_stock_transfer_hdr
                      WHERE st_no = @st_no AND row_version = @expected_row_version
                  )
                THROW 51217, 'Stock transfer has changed. Reload before saving.', 1;
        END;

        IF @target_status = 'A'
           AND EXISTS
              (
                  SELECT 1
                  FROM @details AS d
                  LEFT JOIN dbo.a_whse_item AS wi
                    ON wi.whse_code = @destination_whse_code
                   AND wi.item_code = d.item_code
                  WHERE wi.item_code IS NULL
              )
            THROW 51218, 'Destination warehouse-item setup is missing for one or more items.', 1;

        IF @is_new = 1
        BEGIN
            INSERT dbo.a_stock_transfer_hdr
            (
                st_no, st_date, whse_code_fr, whse_code_to, reference,
                status, trans_type, remarks, user_id, date_changed,
                received_by, received_date, fiscal_year, fiscal_period
            )
            VALUES
            (
                @st_no, @st_date, @source_whse_code, @destination_whse_code,
                @reference, 'N', 'ST', @remarks, @user_id, GETDATE(),
                @received_by, @received_date, @fiscal_year, @fiscal_period
            );
        END
        ELSE
        BEGIN
            UPDATE dbo.a_stock_transfer_hdr
            SET st_date = @st_date,
                whse_code_fr = @source_whse_code,
                whse_code_to = @destination_whse_code,
                reference = @reference,
                remarks = @remarks,
                received_by = @received_by,
                received_date = @received_date,
                fiscal_year = @fiscal_year,
                fiscal_period = @fiscal_period,
                user_id = @user_id,
                date_changed = GETDATE()
            WHERE st_no = @st_no;

            DELETE dbo.a_stock_transfer_det WHERE st_no = @st_no;
        END;

        INSERT dbo.a_stock_transfer_det
        (
            st_no, st_seq, item_code, qty_iss, xfer_um, conv_factor,
            base_um, user_id, date_changed, unit_price,
            unit_cost_snapshot, transfer_cost
        )
        SELECT @st_no, d.st_seq, d.item_code, d.qty_iss, d.xfer_um, d.conv_factor,
               d.base_um, @user_id, GETDATE(), ROUND(costs.unit_cost, 2),
               costs.unit_cost, ROUND(d.qty_iss * d.conv_factor * costs.unit_cost, 4)
        FROM @details AS d
        INNER JOIN dbo.a_whse_item AS wi
          ON wi.whse_code = @source_whse_code
         AND wi.item_code = d.item_code
        CROSS APPLY
        (
            SELECT CAST(CASE
                WHEN wi.qty_rcv - wi.qty_issued > 0
                    THEN wi.on_hand_cost / (wi.qty_rcv - wi.qty_issued)
                ELSE wi.average_uc
            END AS DECIMAL(18,4)) AS unit_cost
        ) AS costs;

        IF @target_status = 'A'
        BEGIN
            DECLARE @lock_whse VARCHAR(5), @lock_item VARCHAR(20), @lock_probe DECIMAL(18,4);
            DECLARE balance_lock_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT whse_code, item_code
                FROM
                (
                    SELECT @source_whse_code AS whse_code, item_code FROM @details
                    UNION
                    SELECT @destination_whse_code, item_code FROM @details
                ) AS locks
                ORDER BY whse_code, item_code;

            OPEN balance_lock_cursor;
            FETCH NEXT FROM balance_lock_cursor INTO @lock_whse, @lock_item;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @lock_probe = NULL;
                SELECT @lock_probe = qty_rcv - qty_issued
                FROM dbo.a_whse_item WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
                WHERE whse_code = @lock_whse AND item_code = @lock_item;
                IF @lock_probe IS NULL
                    THROW 51218, 'Warehouse-item setup is missing for one or more transfer balances.', 1;
                FETCH NEXT FROM balance_lock_cursor INTO @lock_whse, @lock_item;
            END;
            CLOSE balance_lock_cursor;
            DEALLOCATE balance_lock_cursor;

            DECLARE @st_seq INT,
                    @item_code VARCHAR(20),
                    @qty_iss DECIMAL(18,4),
                    @xfer_um CHAR(3),
                    @conv_factor DECIMAL(18,4),
                    @base_um CHAR(3),
                    @base_qty DECIMAL(18,4),
                    @source_qty DECIMAL(18,4),
                    @source_cost DECIMAL(18,4),
                    @destination_qty DECIMAL(18,4),
                    @destination_cost DECIMAL(18,4),
                    @unit_cost DECIMAL(18,4),
                    @transfer_cost DECIMAL(18,4),
                    @source_end_qty DECIMAL(18,4),
                    @source_end_cost DECIMAL(18,4),
                    @destination_end_qty DECIMAL(18,4),
                    @destination_end_cost DECIMAL(18,4);

            DECLARE detail_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT st_seq, item_code, qty_iss, xfer_um, conv_factor, base_um
                FROM @details
                ORDER BY st_seq;

            OPEN detail_cursor;
            FETCH NEXT FROM detail_cursor
                INTO @st_seq, @item_code, @qty_iss, @xfer_um, @conv_factor, @base_um;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @base_qty = ROUND(@qty_iss * @conv_factor, 4);

                SELECT @source_qty = qty_rcv - qty_issued,
                       @source_cost = on_hand_cost
                FROM dbo.a_whse_item
                WHERE whse_code = @source_whse_code AND item_code = @item_code;

                SELECT @destination_qty = qty_rcv - qty_issued,
                       @destination_cost = on_hand_cost
                FROM dbo.a_whse_item
                WHERE whse_code = @destination_whse_code AND item_code = @item_code;

                IF @source_qty < @base_qty
                    THROW 51219, 'Source warehouse stock is insufficient for this transfer.', 1;
                IF @source_qty <= 0 OR @source_cost < 0
                    THROW 51220, 'Source warehouse quantity or cost is inconsistent.', 1;

                SET @unit_cost = ROUND(@source_cost / @source_qty, 4);
                SET @transfer_cost = CASE
                    WHEN @base_qty = @source_qty THEN @source_cost
                    ELSE ROUND(@base_qty * @unit_cost, 4)
                END;
                SET @source_end_qty = @source_qty - @base_qty;
                SET @source_end_cost = ROUND(@source_cost - @transfer_cost, 4);
                SET @destination_end_qty = @destination_qty + @base_qty;
                SET @destination_end_cost = ROUND(@destination_cost + @transfer_cost, 4);

                IF @source_end_cost < 0
                    THROW 51221, 'Source warehouse cost is insufficient for this transfer.', 1;

                UPDATE dbo.a_whse_item
                SET qty_issued = qty_issued + @base_qty,
                    qty_for_issue = qty_for_issue - @base_qty,
                    on_hand_cost = @source_end_cost,
                    average_uc = CASE WHEN @source_end_qty = 0 THEN 0 ELSE ROUND(@source_end_cost / @source_end_qty, 4) END,
                    user_id = @user_id,
                    date_changed = GETDATE()
                WHERE whse_code = @source_whse_code AND item_code = @item_code;

                UPDATE dbo.a_whse_item
                SET qty_rcv = qty_rcv + @base_qty,
                    qty_for_issue = qty_for_issue + @base_qty,
                    on_hand_cost = @destination_end_cost,
                    last_unit_cost = @unit_cost,
                    average_uc = CASE WHEN @destination_end_qty = 0 THEN 0 ELSE ROUND(@destination_end_cost / @destination_end_qty, 4) END,
                    user_id = @user_id,
                    date_changed = GETDATE()
                WHERE whse_code = @destination_whse_code AND item_code = @item_code;

                UPDATE dbo.a_stock_transfer_det
                SET unit_price = ROUND(@unit_cost, 2),
                    unit_cost_snapshot = @unit_cost,
                    transfer_cost = @transfer_cost
                WHERE st_no = @st_no AND st_seq = @st_seq;

                INSERT dbo.a_inv_hst
                (
                    trans_type, trans_no, trans_date, trans_line_no,
                    whse_code, ref_trans_type, reference, item_code,
                    beg_bal_qty, beg_bal_cost, trans_qty, base_um,
                    po_conv_factor, pr_conv_factor, unit_cost, unit_price,
                    remarks, user_id, date_changed, fiscal_year, fiscal_period,
                    cust_code, loading_plan_no, issue_um, issue_conv_factor
                )
                VALUES
                ('STO', @st_no, @st_date, @st_seq, @source_whse_code, 'ST', @reference, @item_code,
                 @source_qty, @source_cost, -@base_qty, @base_um, 1, 1, @unit_cost, @unit_cost,
                 LEFT(ISNULL(@remarks, 'Transfer OUT'), 100), @user_id, GETDATE(), @fiscal_year, @fiscal_period,
                 '', '', @xfer_um, @conv_factor),
                ('STI', @st_no, @st_date, @st_seq, @destination_whse_code, 'ST', @reference, @item_code,
                 @destination_qty, @destination_cost, @base_qty, @base_um, 1, 1, @unit_cost, @unit_cost,
                 LEFT(ISNULL(@remarks, 'Transfer IN'), 100), @user_id, GETDATE(), @fiscal_year, @fiscal_period,
                 '', '', @xfer_um, @conv_factor);

                FETCH NEXT FROM detail_cursor
                    INTO @st_seq, @item_code, @qty_iss, @xfer_um, @conv_factor, @base_um;
            END;

            CLOSE detail_cursor;
            DEALLOCATE detail_cursor;

            UPDATE dbo.a_stock_transfer_hdr
            SET status = 'A',
                received_by = @received_by,
                received_date = COALESCE(@received_date, GETDATE()),
                processed_by = @user_id,
                processed_when = GETDATE(),
                user_id = @user_id,
                date_changed = GETDATE()
            WHERE st_no = @st_no AND status = 'N';

            IF @@ROWCOUNT <> 1
                THROW 51222, 'Stock transfer could not be posted from Draft status.', 1;
        END;

        DECLARE @row_version VARBINARY(8);
        SELECT @row_version = row_version
        FROM dbo.a_stock_transfer_hdr
        WHERE st_no = @st_no;

        COMMIT TRANSACTION;

        SELECT LTRIM(RTRIM(@st_no)) AS StNo,
               @target_status AS Status,
               @row_version AS RowVersion,
               CASE WHEN @target_status = 'A'
                    THEN 'Stock transfer posted successfully.'
                    ELSE 'Stock transfer draft saved successfully.'
               END AS Message;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        IF CURSOR_STATUS('local', 'balance_lock_cursor') > -1
            CLOSE balance_lock_cursor;
        IF CURSOR_STATUS('local', 'balance_lock_cursor') >= -1
            DEALLOCATE balance_lock_cursor;
        IF CURSOR_STATUS('local', 'detail_cursor') > -1
            CLOSE detail_cursor;
        IF CURSOR_STATUS('local', 'detail_cursor') >= -1
            DEALLOCATE detail_cursor;
        THROW;
    END CATCH;
END;
GO
