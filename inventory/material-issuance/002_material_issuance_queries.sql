CREATE OR ALTER PROCEDURE dbo.usp_MaterialIssuance_GetWarehouses @search VARCHAR(100)=NULL AS
BEGIN
 SET NOCOUNT ON; SET @search=NULLIF(LTRIM(RTRIM(@search)),'');
 SELECT DISTINCT whse_code AS WhseCode, whse_code AS WhseDesc
 FROM dbo.a_whse_item
 WHERE @search IS NULL OR whse_code LIKE '%'+@search+'%'
 ORDER BY whse_code;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_MaterialIssuance_GetSuppliers @search VARCHAR(100)=NULL AS
BEGIN
 SET NOCOUNT ON; SET @search=NULLIF(LTRIM(RTRIM(@search)),'');
 SELECT supp_code AS SuppCode,supp_name AS SuppName FROM dbo.a_suppliers
 WHERE active_flag='Y' AND (@search IS NULL OR supp_code LIKE '%'+@search+'%' OR supp_name LIKE '%'+@search+'%')
 ORDER BY supp_name;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_MaterialIssuance_GetAvailableMaterials
 @whse_code VARCHAR(5),@search VARCHAR(100)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET @search=NULLIF(LTRIM(RTRIM(@search)),'');
 SELECT TOP(200) LTRIM(RTRIM(l.item_code)) AS ItemCode,
        MAX(LTRIM(RTRIM(d.item_desc))) AS ItemDesc,
        MAX(LTRIM(RTRIM(l.base_um))) AS BaseUm,
        CAST(SUM(l.base_qty-l.qty_issued) AS DECIMAL(18,4)) AS AvailableQty,
        CAST(CASE WHEN SUM(l.base_qty-l.qty_issued)=0 THEN 0
             ELSE SUM((l.base_qty-l.qty_issued)*l.unit_cost)/SUM(l.base_qty-l.qty_issued) END AS DECIMAL(18,4)) AS EstimatedCost
 FROM dbo.a_rr_lot l
 OUTER APPLY(SELECT TOP(1) x.item_desc FROM dbo.a_rr_det x
   WHERE x.rr_no=l.trans_no AND x.item_code=l.item_code ORDER BY x.rr_seq) d
 WHERE l.whse_code=@whse_code AND l.base_qty>l.qty_issued
   AND (@search IS NULL OR l.item_code LIKE '%'+@search+'%' OR d.item_desc LIKE '%'+@search+'%')
 GROUP BY l.item_code ORDER BY ItemCode;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_MaterialIssuance_GetFifoPreview
 @whse_code VARCHAR(5),@item_code VARCHAR(20),@base_qty DECIMAL(18,4)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 SELECT l.row_no AS RrLotRowNo,LTRIM(RTRIM(l.trans_no)) AS RrNo,l.trans_date AS ReceiptDate,
   CAST(l.base_qty-l.qty_issued AS DECIMAL(18,4)) AS AvailableQty,
   CAST(l.unit_cost AS DECIMAL(18,4)) AS UnitCost,
   CAST((l.base_qty-l.qty_issued)*l.unit_cost AS DECIMAL(18,4)) AS AvailableValue
 FROM dbo.a_rr_lot l
 WHERE l.whse_code=@whse_code AND l.item_code=@item_code AND l.base_qty>l.qty_issued
 ORDER BY l.trans_date,l.row_no;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_MaterialIssuance_GetByNo @issue_no VARCHAR(10) AS
BEGIN
 SET NOCOUNT ON;
 SELECT LTRIM(RTRIM(h.issue_no)) IssueNo,h.issue_date IssueDate,LTRIM(RTRIM(h.whse_code)) WhseCode,
   LTRIM(RTRIM(h.trans_type)) SourceType,LTRIM(RTRIM(h.reference)) AS [Reference],h.source_no SourceNo,
   NULLIF(LTRIM(RTRIM(h.so_no)),'') SoNo,h.cc_code CcCode,h.wc_code WcCode,
   NULLIF(LTRIM(RTRIM(h.supp_code)),'') SuppCode,CONVERT(VARCHAR(500),h.remarks) Remarks,h.status Status,
   CASE WHEN h.no_of_reverts>0 THEN 'R' ELSE h.status END EffectiveStatus,
   h.fiscal_year FiscalYear,h.fiscal_period FiscalPeriod,h.user_id UserId,h.processed_by PostedBy,
   h.processed_date PostedAt,NULLIF(LTRIM(RTRIM(h.reverted_by)),'') RevertedBy,h.reverted_when RevertedWhen,
   CONVERT(VARCHAR(500),h.revert_remarks) RevertRemarks,h.no_of_reverts NoOfReverts,h.row_version RowVersion
 FROM dbo.a_issue_hdr h WHERE h.issue_no=@issue_no;
 SELECT d.issue_seq IssueSeq,LTRIM(RTRIM(d.item_code)) ItemCode,d.item_desc ItemDesc,d.qty_iss QtyIss,
   LTRIM(RTRIM(d.issue_um)) IssueUm,LTRIM(RTRIM(d.base_um)) BaseUm,d.conv_factor ConvFactor,
   CAST(d.qty_iss*d.conv_factor AS DECIMAL(18,4)) BaseQty,d.unit_price UnitCost,
   CAST(d.qty_iss*d.unit_price AS DECIMAL(18,4)) IssueAmount,d.remarks Remarks,
   m.debit_account DebitAccount,m.inventory_account InventoryAccount
 FROM dbo.a_issue_det d
 OUTER APPLY(SELECT TOP(1) x.debit_account,x.inventory_account FROM dbo.a_issue_account_map x
  JOIN dbo.a_issue_hdr h ON h.issue_no=d.issue_no
  WHERE x.is_active=1 AND x.source_type=h.trans_type AND (x.item_code=d.item_code OR x.item_code IS NULL)
  ORDER BY CASE WHEN x.item_code IS NULL THEN 1 ELSE 0 END) m
 WHERE d.issue_no=@issue_no ORDER BY d.issue_seq;
 SELECT l.issue_seq IssueSeq,l.rr_lot_row_no RrLotRowNo,LTRIM(RTRIM(l.rr_no)) RrNo,
   l.allocated_base_qty AllocatedBaseQty,l.unit_cost UnitCost,l.issue_value IssueValue,l.is_active IsActive
 FROM dbo.a_issue_lot l WHERE l.issue_no=@issue_no ORDER BY l.issue_seq,l.allocation_id;
 SELECT d.line_no AS [LineNo],d.account_code AS [AccountCode],d.debit AS [Debit],d.credit AS [Credit],
   d.reference AS [Reference],d.narration AS Narration
 FROM dbo.a_issue_gl_det d JOIN dbo.a_issue_gl_hdr h ON h.journal_no=d.journal_no
 WHERE h.issue_no=@issue_no ORDER BY h.journal_type,d.line_no;
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_MaterialIssuance_Query
 @date_from DATE=NULL,@date_to DATE=NULL,@status VARCHAR(3)='ALL',@source_type VARCHAR(3)='ALL',
 @whse_code VARCHAR(5)=NULL,@search VARCHAR(100)=NULL,@skip INT=0,@take INT=50
AS
BEGIN
 SET NOCOUNT ON; SET @skip=CASE WHEN @skip<0 THEN 0 ELSE @skip END; SET @take=CASE WHEN @take BETWEEN 1 AND 500 THEN @take ELSE 50 END;
 ;WITH s AS(
 SELECT LTRIM(RTRIM(h.issue_no)) IssueNo,h.issue_date IssueDate,LTRIM(RTRIM(h.whse_code)) WhseCode,
  LTRIM(RTRIM(h.trans_type)) SourceType,LTRIM(RTRIM(h.reference)) AS [Reference],h.source_no SourceNo,
  h.status Status,CASE WHEN h.no_of_reverts>0 THEN 'R' ELSE h.status END EffectiveStatus,
  COUNT(d.issue_seq) LineCount,CAST(ISNULL(SUM(d.qty_iss*d.conv_factor),0) AS DECIMAL(18,4)) TotalBaseQty,
  CAST(ISNULL(SUM(d.qty_iss*d.unit_price),0) AS DECIMAL(18,4)) TotalAmount,h.user_id UserId
 FROM dbo.a_issue_hdr h LEFT JOIN dbo.a_issue_det d ON d.issue_no=h.issue_no
 WHERE (@date_from IS NULL OR h.issue_date>=@date_from) AND (@date_to IS NULL OR h.issue_date<DATEADD(DAY,1,@date_to))
 AND (@status='ALL' OR (@status='R' AND h.no_of_reverts>0) OR (@status<>'R' AND h.status=@status AND h.no_of_reverts=0))
 AND (@source_type='ALL' OR h.trans_type=@source_type) AND (@whse_code IS NULL OR h.whse_code=@whse_code)
 AND (@search IS NULL OR h.issue_no LIKE '%'+@search+'%' OR h.reference LIKE '%'+@search+'%' OR h.source_no LIKE '%'+@search+'%'
      OR EXISTS(SELECT 1 FROM dbo.a_issue_det x WHERE x.issue_no=h.issue_no AND (x.item_code LIKE '%'+@search+'%' OR x.item_desc LIKE '%'+@search+'%')))
 GROUP BY h.issue_no,h.issue_date,h.whse_code,h.trans_type,h.reference,h.source_no,h.status,h.no_of_reverts,h.user_id),
 p AS(SELECT *,COUNT(1) OVER() TotalCount FROM s)
 SELECT * FROM p ORDER BY IssueDate DESC,IssueNo DESC OFFSET @skip ROWS FETCH NEXT @take ROWS ONLY;
END;
GO
