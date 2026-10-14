CREATE OR ALTER PROCEDURE dbo.usp_MaterialIssuance_UpsertBatch
 @issue_no VARCHAR(10)=NULL OUTPUT,@expected_row_version VARBINARY(8)=NULL,@issue_date DATE,
 @whse_code VARCHAR(5),@source_type CHAR(3),@reference VARCHAR(20),@source_no VARCHAR(20)=NULL,
 @so_no VARCHAR(10)=NULL,@cc_code VARCHAR(5)=NULL,@wc_code VARCHAR(5)=NULL,@supp_code VARCHAR(6)=NULL,
 @remarks VARCHAR(500)=NULL,@target_status CHAR(1),@user_id VARCHAR(10),
 @details dbo.MaterialIssuanceDetailBatchType READONLY
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF @target_status NOT IN('N','A') THROW 51100,'Target status must be N or A.',1;
 IF @source_type NOT IN('PRD','JOB','PRJ','DPT','JOT','DIR') THROW 51101,'Invalid material issuance source type.',1;
 IF @source_type='JOT' AND NULLIF(LTRIM(RTRIM(@supp_code)),'') IS NULL THROW 51102,'JOT material release requires a supplier.',1;
 IF NULLIF(LTRIM(RTRIM(@whse_code)),'') IS NULL OR NULLIF(LTRIM(RTRIM(@reference)),'') IS NULL THROW 51103,'Warehouse and reference are required.',1;
 IF NOT EXISTS(SELECT 1 FROM @details) OR EXISTS(SELECT 1 FROM @details WHERE qty_iss<=0 OR conv_factor<=0)
   THROW 51104,'At least one valid positive detail is required.',1;
 IF EXISTS(SELECT 1 FROM @details GROUP BY item_code HAVING COUNT(*)>1) THROW 51105,'Duplicate item codes are not allowed in one material issuance.',1;
 IF EXISTS(SELECT 1 FROM @details GROUP BY issue_seq HAVING COUNT(*)>1) THROW 51106,'Duplicate issue sequences are not allowed.',1;

 BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @new BIT=CASE WHEN NULLIF(LTRIM(RTRIM(@issue_no)),'') IS NULL THEN 1 ELSE 0 END,
          @current CHAR(1),@next INT,@fy INT=YEAR(@issue_date),@fp INT=MONTH(@issue_date);
  IF @new=1
  BEGIN
   UPDATE dbo.a_issue_number_series WITH(UPDLOCK,HOLDLOCK)
   SET @next=last_no=last_no+1,date_changed=SYSUTCDATETIME() WHERE series_key='MI';
   IF @next IS NULL THROW 51107,'Material issuance number series is not configured.',1;
   IF @next>9999999 THROW 51108,'Material issuance number series is exhausted.',1;
   SET @issue_no='MI'+RIGHT('0000000'+CONVERT(VARCHAR(7),@next),7);
   IF EXISTS(SELECT 1 FROM dbo.a_issue_hdr WITH(UPDLOCK,HOLDLOCK) WHERE issue_no=@issue_no)
      THROW 51109,'Generated material issuance number already exists.',1;
  END
  ELSE
  BEGIN
   SELECT @current=status FROM dbo.a_issue_hdr WITH(UPDLOCK,HOLDLOCK) WHERE issue_no=@issue_no;
   IF @current IS NULL THROW 51110,'Material issuance was not found.',1;
   IF @current<>'N' OR EXISTS(SELECT 1 FROM dbo.a_issue_hdr WHERE issue_no=@issue_no AND no_of_reverts>0)
      THROW 51111,'Only an active Draft material issuance can be edited or posted.',1;
   IF @expected_row_version IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.a_issue_hdr WHERE issue_no=@issue_no AND row_version=@expected_row_version)
      THROW 51112,'Material issuance has changed. Reload before saving.',1;
  END;

  IF @target_status='A'
  BEGIN
   IF EXISTS(
    SELECT 1 FROM @details d OUTER APPLY(
     SELECT TOP(1) m.map_id FROM dbo.a_issue_account_map m
     WHERE m.is_active=1 AND m.source_type=@source_type AND (m.item_code=d.item_code OR m.item_code IS NULL)
     ORDER BY CASE WHEN m.item_code IS NULL THEN 1 ELSE 0 END) x WHERE x.map_id IS NULL)
      THROW 51114,'A debit/inventory account mapping is missing for one or more materials.',1;
  END;

  IF @new=1
   INSERT dbo.a_issue_hdr(issue_no,cust_code,issue_date,fiscal_year,fiscal_period,whse_code,supp_code,cc_code,wc_code,
    reference,invoice_no,loading_plan_no,seal_no,container_type_code,container_no,destination_code,status,trans_type,
    remarks,user_id,date_changed,reverted_by,no_of_reverts,cancelled_by,cancel_reason,so_no,source_no)
   VALUES(@issue_no,'',@issue_date,@fy,@fp,@whse_code,ISNULL(@supp_code,''),@cc_code,@wc_code,@reference,'','','','','','',
    @target_status,@source_type,@remarks,@user_id,GETDATE(),'',0,'','',ISNULL(@so_no,''),@source_no);
  ELSE
  BEGIN
   UPDATE dbo.a_issue_hdr SET issue_date=@issue_date,fiscal_year=@fy,fiscal_period=@fp,whse_code=@whse_code,
    supp_code=ISNULL(@supp_code,''),cc_code=@cc_code,wc_code=@wc_code,reference=@reference,so_no=ISNULL(@so_no,''),
    source_no=@source_no,trans_type=@source_type,remarks=@remarks,status=@target_status,updated_by=@user_id,
    updated_date=GETDATE(),date_changed=GETDATE() WHERE issue_no=@issue_no;
   DELETE dbo.a_issue_det WHERE issue_no=@issue_no;
  END;

  INSERT dbo.a_issue_det(issue_no,issue_seq,line_type,item_desc,item_code,qty_iss,base_um,unit_price,disc_1,disc_2,disc_3,
   conv_factor,issue_um,user_id,date_changed,remarks)
  SELECT @issue_no,issue_seq,'S',item_desc,item_code,qty_iss,base_um,0,0,0,0,conv_factor,issue_um,@user_id,GETDATE(),remarks
  FROM @details ORDER BY issue_seq;

  IF @target_status='A'
  BEGIN
   DECLARE @seq INT,@item VARCHAR(20),@need DECIMAL(18,4),@baseum CHAR(3),@issueqty DECIMAL(18,4),
    @lotrow INT,@lotno CHAR(10),@avail DECIMAL(18,4),@take DECIMAL(18,4),@cost DECIMAL(18,4),
    @allocation BIGINT,@begqty DECIMAL(18,4),@begcost DECIMAL(18,4),@newqty DECIMAL(18,4),@newcost DECIMAL(18,4);
   DECLARE detail_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT issue_seq,item_code,ROUND(qty_iss*conv_factor,4),base_um,qty_iss FROM @details ORDER BY issue_seq;
   OPEN detail_cursor; FETCH NEXT FROM detail_cursor INTO @seq,@item,@need,@baseum,@issueqty;
   WHILE @@FETCH_STATUS=0
   BEGIN
    DECLARE @required DECIMAL(18,4)=@need,@detailvalue DECIMAL(18,4)=0;
    WHILE @need>0
    BEGIN
     SET @lotrow=NULL;
     SELECT TOP(1) @lotrow=row_no,@lotno=trans_no,@avail=base_qty-qty_issued,@cost=unit_cost
     FROM dbo.a_rr_lot WITH(UPDLOCK,HOLDLOCK,ROWLOCK)
     WHERE whse_code=@whse_code AND item_code=@item AND base_qty>qty_issued
     ORDER BY trans_date,row_no;
     IF @lotrow IS NULL THROW 51115,'Insufficient FIFO receipt-layer stock for material issuance.',1;
     IF @cost<=0 THROW 51117,'The next FIFO receipt layer has no valid unit cost. Correct receipt costing before posting.',1;
     SET @take=CASE WHEN @avail<@need THEN @avail ELSE @need END;
     UPDATE dbo.a_rr_lot SET qty_issued=qty_issued+@take,date_changed=GETDATE(),user_id=@user_id WHERE row_no=@lotrow;
     INSERT dbo.a_issue_lot(issue_no,issue_seq,rr_lot_row_no,rr_no,item_code,whse_code,allocated_base_qty,unit_cost,issue_value,created_by)
     VALUES(@issue_no,@seq,@lotrow,@lotno,@item,@whse_code,@take,@cost,ROUND(@take*@cost,4),@user_id);
     SET @allocation=SCOPE_IDENTITY(); SET @detailvalue=@detailvalue+ROUND(@take*@cost,4);

     SELECT @begqty=qty_rcv-qty_issued,@begcost=on_hand_cost
     FROM dbo.a_whse_item WITH(UPDLOCK,HOLDLOCK) WHERE whse_code=@whse_code AND item_code=@item;
     IF @begqty IS NULL OR @begqty<@take OR @begcost+0.0001<ROUND(@take*@cost,4)
       THROW 51116,'Warehouse balance is insufficient or inconsistent with FIFO layers.',1;
     SET @newqty=@begqty-@take; SET @newcost=ROUND(@begcost-ROUND(@take*@cost,4),4);
     UPDATE dbo.a_whse_item SET qty_issued=qty_issued+@take,qty_for_issue=qty_for_issue-@take,
      on_hand_cost=@newcost,user_id=@user_id,date_changed=GETDATE()
      WHERE whse_code=@whse_code AND item_code=@item;
     INSERT dbo.a_issue_inventory_movement(issue_no,issue_seq,allocation_id,movement_type,movement_date,whse_code,item_code,base_um,
      base_qty,unit_cost,movement_value,beg_bal_qty,beg_bal_cost,end_bal_qty,end_bal_cost,user_id)
     VALUES(@issue_no,@seq,@allocation,'OUT',@issue_date,@whse_code,@item,@baseum,-@take,@cost,-ROUND(@take*@cost,4),
      @begqty,@begcost,@newqty,@newcost,@user_id);
     INSERT dbo.a_inv_hst(trans_type,trans_no,trans_date,trans_line_no,cc_code,whse_code,ref_trans_type,reference,item_code,
      beg_bal_qty,beg_bal_cost,trans_qty,base_um,po_conv_factor,pr_conv_factor,wc_code,unit_cost,unit_price,rr_lot_no,
      rr_lot_trans_type,remarks,user_id,date_changed,fiscal_year,fiscal_period,cust_code,loading_plan_no,issue_um,issue_conv_factor)
     SELECT 'ISS',@issue_no,@issue_date,@seq,@cc_code,@whse_code,@source_type,@reference,@item,@begqty,@begcost,-@take,@baseum,
      1,1,@wc_code,@cost,@cost,@lotno,'RR',LEFT(ISNULL(@remarks,''),100),@user_id,GETDATE(),@fy,@fp,'','',d.issue_um,d.conv_factor
     FROM @details d WHERE d.issue_seq=@seq;
     SET @need=ROUND(@need-@take,4);
    END;
    UPDATE dbo.a_issue_det SET unit_price=CASE WHEN @issueqty=0 THEN 0 ELSE ROUND(@detailvalue/@issueqty,4) END
     WHERE issue_no=@issue_no AND issue_seq=@seq;
    FETCH NEXT FROM detail_cursor INTO @seq,@item,@need,@baseum,@issueqty;
   END;
   CLOSE detail_cursor; DEALLOCATE detail_cursor;

   DECLARE @j VARCHAR(15)='MI-'+@issue_no,@total DECIMAL(18,4);
   SELECT @total=SUM(issue_value) FROM dbo.a_issue_lot WHERE issue_no=@issue_no AND is_active=1;
   INSERT dbo.a_issue_gl_hdr(journal_no,issue_no,journal_type,journal_date,source_type,total_debit,total_credit,created_by)
   VALUES(@j,@issue_no,'POST',@issue_date,@source_type,@total,@total,@user_id);
   ;WITH mapped AS(
    SELECT l.issue_seq,l.issue_value,m.debit_account,m.inventory_account
    FROM dbo.a_issue_lot l CROSS APPLY(SELECT TOP(1) x.debit_account,x.inventory_account FROM dbo.a_issue_account_map x
     WHERE x.is_active=1 AND x.source_type=@source_type AND (x.item_code=l.item_code OR x.item_code IS NULL)
     ORDER BY CASE WHEN x.item_code IS NULL THEN 1 ELSE 0 END) m
    WHERE l.issue_no=@issue_no AND l.is_active=1),
   lines AS(SELECT debit_account account_code,SUM(issue_value) amount,0 side FROM mapped GROUP BY debit_account
    UNION ALL SELECT inventory_account,SUM(issue_value),1 FROM mapped GROUP BY inventory_account)
   INSERT dbo.a_issue_gl_det(journal_no,line_no,account_code,debit,credit,reference,narration)
   SELECT @j,ROW_NUMBER() OVER(ORDER BY side,account_code),account_code,CASE WHEN side=0 THEN amount ELSE 0 END,
    CASE WHEN side=1 THEN amount ELSE 0 END,@issue_no,'Material issuance '+@issue_no FROM lines;

   EXEC dbo.usp_MaterialIssuance_PostLegacyJournal @journal_no=@j,@issue_no=@issue_no,@journal_date=@issue_date,
    @fiscal_year=@fy,@fiscal_period=@fp,@user_id=@user_id;
   UPDATE dbo.a_issue_hdr SET processed_by=@user_id,processed_date=GETDATE() WHERE issue_no=@issue_no;
  END;

  DECLARE @rv VARBINARY(8); SELECT @rv=row_version FROM dbo.a_issue_hdr WHERE issue_no=@issue_no;
  COMMIT;
  SELECT LTRIM(RTRIM(@issue_no)) IssueNo,@target_status Status,@target_status EffectiveStatus,@rv RowVersion,
   CASE WHEN @target_status='A' THEN 'Material issuance posted successfully.' ELSE 'Material issuance draft saved successfully.' END Message;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  IF CURSOR_STATUS('local','detail_cursor')>=-1 BEGIN CLOSE detail_cursor; DEALLOCATE detail_cursor; END;
  THROW;
 END CATCH
END;
GO
