/*
    Stock Item Inquiry (read-only)
    SQL Server 2012+ compatible deployment.

    The procedures intentionally calculate warehouse on-hand from the same
    qty_rcv/qty_issued columns maintained by current posting procedures.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.usp_StockItemInquiry_Items', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_StockItemInquiry_Items AS BEGIN SET NOCOUNT ON; END');
GO
ALTER PROCEDURE dbo.usp_StockItemInquiry_Items
    @search VARCHAR(100) = NULL,
    @group_code VARCHAR(10) = NULL,
    @skip INT = 0,
    @take INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SET @search = NULLIF(LTRIM(RTRIM(@search)), '');
    SET @group_code = NULLIF(LTRIM(RTRIM(@group_code)), '');
    SET @skip = CASE WHEN @skip < 0 THEN 0 ELSE @skip END;
    SET @take = CASE WHEN @take BETWEEN 1 AND 200 THEN @take ELSE 50 END;

    SELECT LTRIM(RTRIM(im.item_code)) AS ItemCode,
           LTRIM(RTRIM(im.item_desc)) AS ItemDesc,
           LTRIM(RTRIM(im.group_code)) AS GroupCode,
           COALESCE(LTRIM(RTRIM(ig.group_desc)), '') AS GroupDesc,
           LTRIM(RTRIM(im.um)) AS BaseUm,
           LTRIM(RTRIM(im.item_type)) AS ItemType,
           NULLIF(LTRIM(RTRIM(im.item_short_desc)), '') AS ShortDesc,
           CAST(im.last_unit_cost AS DECIMAL(18,4)) AS LastUnitCost
    FROM dbo.a_item_master AS im
    LEFT JOIN dbo.a_item_group AS ig
        ON ig.group_code = im.group_code
    WHERE im.active = 'Y'
      AND (@group_code IS NULL OR im.group_code = @group_code)
      AND
      (
          @search IS NULL
          OR im.item_code LIKE '%' + @search + '%'
          OR im.item_desc LIKE '%' + @search + '%'
          OR im.item_short_desc LIKE '%' + @search + '%'
      )
    ORDER BY im.item_code
    OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY;

    SELECT COUNT_BIG(1) AS Total
    FROM dbo.a_item_master AS im
    WHERE im.active = 'Y'
      AND (@group_code IS NULL OR im.group_code = @group_code)
      AND
      (
          @search IS NULL
          OR im.item_code LIKE '%' + @search + '%'
          OR im.item_desc LIKE '%' + @search + '%'
          OR im.item_short_desc LIKE '%' + @search + '%'
      );
END;
GO

IF OBJECT_ID(N'dbo.usp_StockItemInquiry_WarehouseStocks', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_StockItemInquiry_WarehouseStocks AS BEGIN SET NOCOUNT ON; END');
GO
ALTER PROCEDURE dbo.usp_StockItemInquiry_WarehouseStocks
    @item_code VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');

    IF @item_code IS NULL
        THROW 52001, 'Item code is required.', 1;

    SELECT LTRIM(RTRIM(wi.whse_code)) AS WhseCode,
           LTRIM(RTRIM(wi.item_code)) AS ItemCode,
           CAST(ISNULL(wi.qty_rcv, 0) AS DECIMAL(18,4)) AS QtyReceived,
           CAST(ISNULL(wi.qty_issued, 0) AS DECIMAL(18,4)) AS QtyIssued,
           CAST(ISNULL(wi.qty_for_issue, 0) AS DECIMAL(18,4)) AS QtyForIssue,
           CAST(ISNULL(wi.qty_po, 0) AS DECIMAL(18,4)) AS QtyPo,
           CAST(ISNULL(wi.qty_rcv, 0) - ISNULL(wi.qty_issued, 0) AS DECIMAL(18,4)) AS OnHandQty,
           CAST(ISNULL(wi.qty_rcv, 0) - ISNULL(wi.qty_issued, 0) - ISNULL(wi.qty_for_issue, 0) AS DECIMAL(18,4)) AS AvailableQty,
           LTRIM(RTRIM(wi.base_um)) AS BaseUm,
           CAST(ISNULL(wi.on_hand_cost, 0) AS DECIMAL(18,4)) AS OnHandCost,
           CAST(ISNULL(wi.last_unit_cost, 0) AS DECIMAL(18,4)) AS LastUnitCost,
           NULLIF(LTRIM(RTRIM(wi.user_id)), '') AS UserId,
           wi.date_changed AS DateChanged
    FROM dbo.a_whse_item AS wi
    WHERE wi.item_code = @item_code
    ORDER BY wi.whse_code;
END;
GO

IF OBJECT_ID(N'dbo.usp_StockItemInquiry_WarehouseLots', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_StockItemInquiry_WarehouseLots AS BEGIN SET NOCOUNT ON; END');
GO
ALTER PROCEDURE dbo.usp_StockItemInquiry_WarehouseLots
    @item_code VARCHAR(20),
    @whse_code VARCHAR(5),
    @open_only BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');
    SET @whse_code = NULLIF(LTRIM(RTRIM(@whse_code)), '');

    IF @item_code IS NULL THROW 52002, 'Item code is required.', 1;
    IF @whse_code IS NULL THROW 52003, 'Warehouse code is required.', 1;

    SELECT LTRIM(RTRIM(rl.whse_code)) AS WhseCode,
           LTRIM(RTRIM(rl.item_code)) AS ItemCode,
           LTRIM(RTRIM(rl.trans_type)) AS TransType,
           LTRIM(RTRIM(rl.trans_no)) AS TransNo,
           rl.trans_date AS TransDate,
           rl.trans_line_no AS TransLineNo,
           NULLIF(LTRIM(RTRIM(rl.po_no)), '') AS PoNo,
           rl.po_line_no AS PoLineNo,
           CAST(ISNULL(rl.base_qty, 0) AS DECIMAL(18,4)) AS BaseQty,
           CAST(ISNULL(rl.qty_issued, 0) AS DECIMAL(18,4)) AS QtyIssued,
           CAST(ISNULL(rl.base_qty, 0) - ISNULL(rl.qty_issued, 0) AS DECIMAL(18,4)) AS RemainingQty,
           LTRIM(RTRIM(rl.base_um)) AS BaseUm,
           CAST(ISNULL(rl.qty_rcv, 0) AS DECIMAL(18,4)) AS QtyReceived,
           NULLIF(LTRIM(RTRIM(rl.po_um)), '') AS PoUm,
           CAST(ISNULL(rl.po_conv_factor, 0) AS DECIMAL(18,4)) AS PoConvFactor,
           CAST(ISNULL(rl.pr_conv_factor, 0) AS DECIMAL(18,4)) AS PrConvFactor,
           CAST(ISNULL(rl.unit_cost, 0) AS DECIMAL(18,4)) AS UnitCost,
           CAST(ISNULL(rl.unit_price, 0) AS DECIMAL(18,4)) AS UnitPrice,
           CAST((ISNULL(rl.base_qty, 0) - ISNULL(rl.qty_issued, 0)) * ISNULL(rl.unit_cost, 0) AS DECIMAL(18,4)) AS RemainingValue,
           NULLIF(LTRIM(RTRIM(rl.user_id)), '') AS UserId,
           rl.date_changed AS DateChanged
    FROM dbo.a_rr_lot AS rl
    WHERE rl.item_code = @item_code
      AND rl.whse_code = @whse_code
      AND (@open_only = 0 OR ISNULL(rl.base_qty, 0) > ISNULL(rl.qty_issued, 0))
    ORDER BY rl.trans_date, rl.trans_no, rl.trans_line_no, rl.row_no;
END;
GO

IF OBJECT_ID(N'dbo.usp_StockItemInquiry_StockCard', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_StockItemInquiry_StockCard AS BEGIN SET NOCOUNT ON; END');
GO
ALTER PROCEDURE dbo.usp_StockItemInquiry_StockCard
    @item_code VARCHAR(20),
    @whse_code VARCHAR(5),
    @date_from DATE = NULL,
    @date_to DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');
    SET @whse_code = NULLIF(LTRIM(RTRIM(@whse_code)), '');
    SET @date_from = ISNULL(@date_from, DATEFROMPARTS(YEAR(GETDATE()), 1, 1));
    SET @date_to = ISNULL(@date_to, CONVERT(DATE, GETDATE()));

    IF @item_code IS NULL THROW 52004, 'Item code is required.', 1;
    IF @whse_code IS NULL THROW 52005, 'Warehouse code is required.', 1;
    IF @date_from > @date_to THROW 52006, 'Date From cannot be later than Date To.', 1;

    SELECT ih.row_no AS RowNo,
           ih.trans_date AS TransDate,
           NULLIF(LTRIM(RTRIM(ih.trans_type)), '') AS TransType,
           NULLIF(LTRIM(RTRIM(ih.trans_no)), '') AS TransNo,
           ih.trans_line_no AS TransLineNo,
           NULLIF(LTRIM(RTRIM(ih.reference)), '') AS Reference,
           NULLIF(LTRIM(RTRIM(ih.po_no)), '') AS PoNo,
           ih.po_line_no AS PoLineNo,
           NULLIF(LTRIM(RTRIM(ih.supp_code)), '') AS SuppCode,
           LTRIM(RTRIM(ih.whse_code)) AS WhseCode,
           LTRIM(RTRIM(ih.item_code)) AS ItemCode,
           CAST(ISNULL(ih.beg_bal_qty, 0) AS DECIMAL(18,4)) AS BeginningQty,
           CAST(CASE WHEN ih.trans_qty > 0 THEN ih.trans_qty ELSE 0 END AS DECIMAL(18,4)) AS QtyIn,
           CAST(CASE WHEN ih.trans_qty < 0 THEN ABS(ih.trans_qty) ELSE 0 END AS DECIMAL(18,4)) AS QtyOut,
           CAST(ISNULL(ih.trans_qty, 0) AS DECIMAL(18,4)) AS TransQty,
           CAST(ISNULL(ih.beg_bal_qty, 0) + ISNULL(ih.trans_qty, 0) AS DECIMAL(18,4)) AS EndingQty,
           CAST(ISNULL(ih.unit_cost, 0) AS DECIMAL(18,4)) AS UnitCost,
           CAST(ISNULL(ih.beg_bal_cost, 0) AS DECIMAL(18,4)) AS BeginningCost,
           CAST(ISNULL(ih.trans_qty, 0) * ISNULL(ih.unit_cost, 0) AS DECIMAL(18,4)) AS MovementValue,
           NULLIF(LTRIM(RTRIM(ih.base_um)), '') AS BaseUm,
           NULLIF(LTRIM(RTRIM(ih.po_um)), '') AS PoUm,
           CAST(ISNULL(ih.po_conv_factor, 0) AS DECIMAL(18,4)) AS PoConvFactor,
           CAST(ISNULL(ih.unit_price, 0) AS DECIMAL(18,4)) AS UnitPrice,
           NULLIF(LTRIM(RTRIM(ih.rr_lot_no)), '') AS RrLotNo,
           NULLIF(LTRIM(RTRIM(ih.rr_lot_trans_type)), '') AS RrLotTransType,
           COALESCE(NULLIF(LTRIM(RTRIM(wc.wc_desc)), ''), NULLIF(LTRIM(RTRIM(ih.wc_code)), '')) AS WorkCenter,
           NULLIF(LTRIM(RTRIM(ih.user_id)), '') AS UserId,
           ih.date_changed AS DateChanged
    FROM dbo.a_inv_hst AS ih
    LEFT JOIN dbo.a_work_center AS wc
        ON wc.wc_code = ih.wc_code
    WHERE ih.item_code = @item_code
      AND ih.whse_code = @whse_code
      AND ih.trans_date >= @date_from
      AND ih.trans_date < DATEADD(DAY, 1, @date_to)
    ORDER BY ih.trans_date, ih.row_no;
END;
GO
