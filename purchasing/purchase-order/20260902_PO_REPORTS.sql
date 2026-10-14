/*
  Purchase Order Reports.  Deploy after the existing PO and Receiving objects.
  Live PO detail key is dbo.a_po_det.po_seq.  Fulfillment intentionally uses
  dbo.a_po_det.qty_rcv, the verified PO-level snapshot; it does not recompute
  receipts or acceptances from unverified source-table assumptions.
*/
IF OBJECT_ID(N'dbo.usp_PO_Report_Query', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_PO_Report_Query AS BEGIN SET NOCOUNT ON; END;');
GO

ALTER PROCEDURE dbo.usp_PO_Report_Query
    @report_type varchar(25), @po_date_from date = NULL, @po_date_to date = NULL,
    @delivery_date_from date = NULL, @delivery_date_to date = NULL,
    @po_status varchar(10) = NULL, @balance_status varchar(20) = NULL,
    @po_type varchar(10) = NULL, @item_code varchar(20) = NULL,
    @item_desc varchar(100) = NULL, @po_no varchar(15) = NULL,
    @purchaser varchar(50) = NULL, @branch_name varchar(50) = NULL,
    @supplier_mode varchar(10) = 'ALL', @supplier_codes varchar(4000) = NULL,
    @skip int = 0, @take int = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET @report_type = UPPER(LTRIM(RTRIM(@report_type)));
    SET @supplier_mode = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@supplier_mode)), ''), 'ALL'));
    SET @po_status = NULLIF(LTRIM(RTRIM(@po_status)), '');
    SET @balance_status = UPPER(NULLIF(LTRIM(RTRIM(@balance_status)), ''));
    SET @po_type = NULLIF(LTRIM(RTRIM(@po_type)), '');
    SET @item_code = NULLIF(LTRIM(RTRIM(@item_code)), '');
    SET @item_desc = NULLIF(LTRIM(RTRIM(@item_desc)), '');
    SET @po_no = NULLIF(LTRIM(RTRIM(@po_no)), '');
    SET @purchaser = NULLIF(LTRIM(RTRIM(@purchaser)), '');
    SET @branch_name = NULLIF(LTRIM(RTRIM(@branch_name)), '');
    SET @skip = CASE WHEN ISNULL(@skip, 0) < 0 THEN 0 ELSE ISNULL(@skip, 0) END;
    SET @take = CASE WHEN ISNULL(@take, 0) BETWEEN 1 AND 500 THEN @take ELSE 50 END;
    IF @report_type NOT IN ('PO_SUMMARY','PO_TRACKING','PO_BALANCE_SUPPLIER','PO_SUMMARY_ITEM','PO_RR','PO_BALANCE')
    BEGIN RAISERROR('Unsupported PO report type.', 16, 1); RETURN; END;
    IF @supplier_mode NOT IN ('ALL','SELECTED','NONE')
    BEGIN RAISERROR('Invalid supplier mode.', 16, 1); RETURN; END;

    /* PO/RR cannot be safely deployed until the absent live a_rr schema/procedure is versioned. */
    IF @report_type = 'PO_RR'
    BEGIN RAISERROR('PO/RR reporting requires the live Receiving table contract before deployment.', 16, 1); RETURN; END;

    CREATE TABLE #Lines
    (
        PoNo varchar(15) NOT NULL, PoDate datetime NULL, PoDeliveryDate datetime NULL,
        PoType varchar(10) NULL, PoStatus varchar(10) NULL, PoStatusName varchar(30) NULL,
        SuppCode varchar(10) NULL, SuppName varchar(100) NULL, BranchName varchar(50) NULL,
        Purchaser varchar(50) NULL, PoLineNo int NULL, ItemCode varchar(20) NULL,
        ItemDesc varchar(255) NULL, PoUm varchar(10) NULL, QtyPo decimal(19,4) NOT NULL,
        QtyFulfilled decimal(19,4) NOT NULL, BalanceQty decimal(19,4) NOT NULL,
        UnitPrice decimal(19,4) NOT NULL, PoAmount decimal(19,4) NOT NULL,
        FulfilledAmount decimal(19,4) NOT NULL, BalanceAmount decimal(19,4) NOT NULL,
        BalanceStatus varchar(20) NOT NULL
    );

    INSERT #Lines
    SELECT LTRIM(RTRIM(h.po_no)), h.po_date, h.po_del_date, LTRIM(RTRIM(h.po_type)), LTRIM(RTRIM(h.status)),
           CASE LTRIM(RTRIM(h.status)) WHEN 'N' THEN 'Draft' WHEN 'P' THEN 'Posted' WHEN 'A' THEN 'Approved' WHEN 'C' THEN 'Cancelled' ELSE LTRIM(RTRIM(h.status)) END,
           LTRIM(RTRIM(h.supp_code)), LTRIM(RTRIM(s.supp_name)), LTRIM(RTRIM(h.branchname)), LTRIM(RTRIM(h.user_id)), d.po_seq,
           LTRIM(RTRIM(d.item_code)), LTRIM(RTRIM(d.item_desc)), LTRIM(RTRIM(d.po_um)),
           CONVERT(decimal(19,4), ISNULL(d.qty_po, 0)), CONVERT(decimal(19,4), ISNULL(d.qty_rcv, 0)),
           CASE WHEN ISNULL(d.qty_po, 0) > ISNULL(d.qty_rcv, 0) THEN CONVERT(decimal(19,4), d.qty_po - ISNULL(d.qty_rcv, 0)) ELSE 0 END,
           CONVERT(decimal(19,4), ISNULL(d.unit_price, 0)),
           CONVERT(decimal(19,4), ISNULL(d.qty_po, 0) * ISNULL(d.unit_price, 0)),
           CONVERT(decimal(19,4), ISNULL(d.qty_rcv, 0) * ISNULL(d.unit_price, 0)),
           CONVERT(decimal(19,4), CASE WHEN ISNULL(d.qty_po, 0) > ISNULL(d.qty_rcv, 0) THEN (d.qty_po - ISNULL(d.qty_rcv, 0)) * ISNULL(d.unit_price, 0) ELSE 0 END),
           CASE WHEN ISNULL(d.qty_rcv, 0) > ISNULL(d.qty_po, 0) THEN 'OVER_RECEIVED' WHEN ISNULL(d.qty_rcv, 0) = ISNULL(d.qty_po, 0) THEN 'FULLY_RECEIVED' WHEN ISNULL(d.qty_rcv, 0) > 0 THEN 'PARTIAL' ELSE 'UNRECEIVED' END
    FROM dbo.a_po_hdr h
    INNER JOIN dbo.a_po_det d ON d.po_no = h.po_no
    LEFT JOIN dbo.a_suppliers s ON s.supp_code = h.supp_code
    WHERE (@supplier_mode = 'ALL' OR (@supplier_mode = 'SELECTED' AND CHARINDEX('|' + LTRIM(RTRIM(h.supp_code)) + '|', '|' + ISNULL(@supplier_codes, '') + '|') > 0))
      AND @supplier_mode <> 'NONE' AND (@po_date_from IS NULL OR h.po_date >= @po_date_from) AND (@po_date_to IS NULL OR h.po_date < DATEADD(day, 1, @po_date_to))
      AND (@delivery_date_from IS NULL OR h.po_del_date >= @delivery_date_from) AND (@delivery_date_to IS NULL OR h.po_del_date < DATEADD(day, 1, @delivery_date_to))
      AND (@po_status IS NULL OR @po_status = 'ALL' OR LTRIM(RTRIM(h.status)) = @po_status)
      AND (@po_type IS NULL OR @po_type = 'ALL' OR LTRIM(RTRIM(h.po_type)) = @po_type)
      AND (@item_code IS NULL OR LTRIM(RTRIM(d.item_code)) = @item_code)
      AND (@item_desc IS NULL OR d.item_desc LIKE '%' + @item_desc + '%')
      AND (@po_no IS NULL OR LTRIM(RTRIM(h.po_no)) = @po_no)
      AND (@purchaser IS NULL OR LTRIM(RTRIM(h.user_id)) = @purchaser)
      AND (@branch_name IS NULL OR LTRIM(RTRIM(h.branchname)) = @branch_name);

    IF @balance_status IS NOT NULL AND @balance_status <> 'ALL'
        DELETE FROM #Lines WHERE NOT ((@balance_status = 'OPEN' AND QtyFulfilled < QtyPo) OR BalanceStatus = @balance_status);

    ;WITH R AS
    (
      SELECT @report_type ReportType, PoNo, PoDate, PoDeliveryDate, PoType, PoStatus, PoStatusName, SuppCode, SuppName, BranchName, Purchaser,
             PoLineNo, CAST(NULL AS int) LineCount, CAST(NULL AS int) PoCount, ItemCode, ItemDesc, PoUm, QtyPo, QtyFulfilled, BalanceQty, UnitPrice, PoAmount, FulfilledAmount, BalanceAmount, BalanceStatus
      FROM #Lines WHERE @report_type IN ('PO_TRACKING','PO_BALANCE') AND (@report_type <> 'PO_BALANCE' OR BalanceQty > 0)
      UNION ALL
      SELECT @report_type, PoNo, MAX(PoDate), MAX(PoDeliveryDate), MAX(PoType), MAX(PoStatus), MAX(PoStatusName), MAX(SuppCode), MAX(SuppName), MAX(BranchName), MAX(Purchaser), NULL, COUNT(*), 1, NULL,NULL,NULL,NULL,NULL,NULL,NULL,SUM(PoAmount),SUM(FulfilledAmount),SUM(BalanceAmount),NULL
      FROM #Lines WHERE @report_type = 'PO_SUMMARY' GROUP BY PoNo
      UNION ALL
      SELECT @report_type,NULL,NULL,NULL,NULL,NULL,NULL,SuppCode,MAX(SuppName),NULL,NULL,NULL,COUNT(*),COUNT(DISTINCT PoNo),NULL,NULL,NULL,NULL,NULL,NULL,NULL,SUM(PoAmount),SUM(FulfilledAmount),SUM(BalanceAmount),NULL
      FROM #Lines WHERE @report_type = 'PO_BALANCE_SUPPLIER' AND BalanceQty > 0 GROUP BY SuppCode
      UNION ALL
      SELECT @report_type,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,COUNT(*),COUNT(DISTINCT PoNo),ItemCode,MAX(ItemDesc),PoUm,SUM(QtyPo),SUM(QtyFulfilled),SUM(BalanceQty),NULL,SUM(PoAmount),SUM(FulfilledAmount),SUM(BalanceAmount),NULL
      FROM #Lines WHERE @report_type = 'PO_SUMMARY_ITEM' GROUP BY ItemCode, PoUm
    ), N AS (SELECT R.*, ROW_NUMBER() OVER (ORDER BY ISNULL(PoDate, '19000101') DESC, ISNULL(PoNo, ''), ISNULL(SuppCode, ''), ISNULL(ItemCode, ''), ISNULL(PoLineNo, 0)) RowNo, COUNT_BIG(*) OVER () TotalCount FROM R)
    SELECT ReportType,PoNo,PoDate,PoDeliveryDate,PoType,PoStatus,PoStatusName,SuppCode,SuppName,BranchName,Purchaser,PoLineNo,LineCount,PoCount,ItemCode,ItemDesc,PoUm,QtyPo,QtyFulfilled,BalanceQty,UnitPrice,PoAmount,FulfilledAmount,BalanceAmount,BalanceStatus,TotalCount
    FROM N WHERE RowNo > @skip AND RowNo <= @skip + @take ORDER BY RowNo;
    IF @report_type IN ('PO_SUMMARY','PO_BALANCE_SUPPLIER','PO_SUMMARY_ITEM')
    BEGIN
      SELECT CASE @report_type WHEN 'PO_SUMMARY' THEN COUNT(DISTINCT PoNo) WHEN 'PO_BALANCE_SUPPLIER' THEN COUNT(DISTINCT SuppCode) ELSE COUNT(DISTINCT ISNULL(ItemCode,'') + '|' + ISNULL(PoUm,'')) END AS Total FROM #Lines WHERE @report_type <> 'PO_BALANCE_SUPPLIER' OR BalanceQty > 0;
    END
    ELSE
    BEGIN
      SELECT COUNT_BIG(*) AS Total FROM #Lines WHERE @report_type <> 'PO_BALANCE' OR BalanceQty > 0;
    END
END;
GO
