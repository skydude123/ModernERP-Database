CREATE OR ALTER PROCEDURE dbo.usp_StockTransfer_GetWarehouses
    @search VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), '');

    SELECT LTRIM(RTRIM(w.whse_code)) AS WhseCode,
           LTRIM(RTRIM(w.whse_desc)) AS WhseDesc
    FROM dbo.a_whse AS w
    WHERE @search IS NULL
       OR w.whse_code LIKE '%' + @search + '%'
       OR w.whse_desc LIKE '%' + @search + '%'
    ORDER BY w.whse_desc, w.whse_code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_StockTransfer_GetSourceItems
    @whse_code VARCHAR(5),
    @search VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), '');

    SELECT TOP (200)
           LTRIM(RTRIM(i.item_code)) AS ItemCode,
           LTRIM(RTRIM(i.item_desc)) AS ItemDesc,
           LTRIM(RTRIM(wi.whse_code)) AS SourceWhseCode,
           CAST(wi.qty_rcv - wi.qty_issued AS DECIMAL(18,4)) AS StockOnHand,
           LTRIM(RTRIM(wi.base_um)) AS BaseUm,
           CAST(CASE
                    WHEN wi.qty_rcv - wi.qty_issued > 0
                        THEN wi.on_hand_cost / (wi.qty_rcv - wi.qty_issued)
                    ELSE wi.average_uc
                END AS DECIMAL(18,4)) AS UnitCost
    FROM dbo.a_whse_item AS wi
    INNER JOIN dbo.a_item_master AS i
        ON i.item_code = wi.item_code
    WHERE wi.whse_code = @whse_code
      AND wi.qty_rcv - wi.qty_issued > 0
      AND i.active = 'Y'
      AND ISNULL(i.blocked, 'N') <> 'Y'
      AND
      (
          @search IS NULL
          OR i.item_code LIKE '%' + @search + '%'
          OR i.item_desc LIKE '%' + @search + '%'
      )
    ORDER BY i.item_code;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_StockTransfer_GetByNo
    @st_no VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT LTRIM(RTRIM(h.st_no)) AS StNo,
           h.st_date AS StDate,
           LTRIM(RTRIM(h.whse_code_fr)) AS SourceWhseCode,
           LTRIM(RTRIM(wf.whse_desc)) AS SourceWhseDesc,
           LTRIM(RTRIM(h.whse_code_to)) AS DestinationWhseCode,
           LTRIM(RTRIM(wt.whse_desc)) AS DestinationWhseDesc,
           LTRIM(RTRIM(h.reference)) AS Reference,
           CONVERT(VARCHAR(500), h.remarks) AS Remarks,
           h.status AS Status,
           NULLIF(LTRIM(RTRIM(h.received_by)), '') AS ReceivedBy,
           h.received_date AS ReceivedDate,
           NULLIF(LTRIM(RTRIM(h.processed_by)), '') AS PostedBy,
           h.processed_when AS PostedAt,
           h.fiscal_year AS FiscalYear,
           h.fiscal_period AS FiscalPeriod,
           h.user_id AS UserId,
           h.row_version AS RowVersion
    FROM dbo.a_stock_transfer_hdr AS h
    INNER JOIN dbo.a_whse AS wf ON wf.whse_code = h.whse_code_fr
    INNER JOIN dbo.a_whse AS wt ON wt.whse_code = h.whse_code_to
    WHERE h.st_no = @st_no;

    SELECT d.st_seq AS StSeq,
           LTRIM(RTRIM(d.item_code)) AS ItemCode,
           LTRIM(RTRIM(i.item_desc)) AS ItemDesc,
           d.qty_iss AS QtyIss,
           LTRIM(RTRIM(d.xfer_um)) AS XferUm,
           d.conv_factor AS ConvFactor,
           LTRIM(RTRIM(d.base_um)) AS BaseUm,
           CAST(d.qty_iss * d.conv_factor AS DECIMAL(18,4)) AS BaseQty,
           CAST(COALESCE(d.unit_cost_snapshot, d.unit_price, 0) AS DECIMAL(18,4)) AS UnitCost,
           CAST(COALESCE(d.transfer_cost, d.qty_iss * d.conv_factor * COALESCE(d.unit_cost_snapshot, d.unit_price, 0), 0) AS DECIMAL(18,4)) AS TransferCost
    FROM dbo.a_stock_transfer_det AS d
    INNER JOIN dbo.a_item_master AS i ON i.item_code = d.item_code
    WHERE d.st_no = @st_no
    ORDER BY d.st_seq;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_StockTransfer_Query
    @date_from DATE = NULL,
    @date_to DATE = NULL,
    @status VARCHAR(3) = 'ALL',
    @source_whse_code VARCHAR(5) = NULL,
    @destination_whse_code VARCHAR(5) = NULL,
    @search VARCHAR(100) = NULL,
    @skip INT = 0,
    @take INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), '');
    SET @skip = CASE WHEN @skip < 0 THEN 0 ELSE @skip END;
    SET @take = CASE WHEN @take BETWEEN 1 AND 500 THEN @take ELSE 50 END;

    ;WITH summaries AS
    (
        SELECT LTRIM(RTRIM(h.st_no)) AS StNo,
               h.st_date AS StDate,
               LTRIM(RTRIM(h.whse_code_fr)) AS SourceWhseCode,
               LTRIM(RTRIM(wf.whse_desc)) AS SourceWhseDesc,
               LTRIM(RTRIM(h.whse_code_to)) AS DestinationWhseCode,
               LTRIM(RTRIM(wt.whse_desc)) AS DestinationWhseDesc,
               LTRIM(RTRIM(h.reference)) AS Reference,
               CONVERT(VARCHAR(500), h.remarks) AS Remarks,
               h.status AS Status,
               NULLIF(LTRIM(RTRIM(h.received_by)), '') AS ReceivedBy,
               h.received_date AS ReceivedDate,
               COUNT(d.st_seq) AS LineCount,
               CAST(ISNULL(SUM(d.qty_iss * d.conv_factor), 0) AS DECIMAL(18,4)) AS TotalBaseQty,
               CAST(ISNULL(SUM(COALESCE(d.transfer_cost, d.qty_iss * d.conv_factor * COALESCE(d.unit_cost_snapshot, d.unit_price, 0))), 0) AS DECIMAL(18,4)) AS TotalTransferCost
        FROM dbo.a_stock_transfer_hdr AS h
        INNER JOIN dbo.a_whse AS wf ON wf.whse_code = h.whse_code_fr
        INNER JOIN dbo.a_whse AS wt ON wt.whse_code = h.whse_code_to
        LEFT JOIN dbo.a_stock_transfer_det AS d ON d.st_no = h.st_no
        WHERE (@date_from IS NULL OR h.st_date >= @date_from)
          AND (@date_to IS NULL OR h.st_date < DATEADD(DAY, 1, @date_to))
          AND (@status = 'ALL' OR h.status = @status)
          AND (@source_whse_code IS NULL OR h.whse_code_fr = @source_whse_code)
          AND (@destination_whse_code IS NULL OR h.whse_code_to = @destination_whse_code)
          AND
          (
              @search IS NULL
              OR h.st_no LIKE '%' + @search + '%'
              OR h.reference LIKE '%' + @search + '%'
              OR h.remarks LIKE '%' + @search + '%'
          )
        GROUP BY h.st_no, h.st_date, h.whse_code_fr, wf.whse_desc,
                 h.whse_code_to, wt.whse_desc, h.reference, h.remarks,
                 h.status, h.received_by, h.received_date
    ),
    paged AS
    (
        SELECT *, COUNT_BIG(1) OVER() AS TotalCount
        FROM summaries
    )
    SELECT *
    FROM paged
    ORDER BY StDate DESC, StNo DESC
    OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY;
END;
GO
