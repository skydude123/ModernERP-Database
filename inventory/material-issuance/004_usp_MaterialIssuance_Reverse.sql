CREATE OR ALTER PROCEDURE dbo.usp_MaterialIssuance_Reverse
 @issue_no VARCHAR(10),@expected_row_version VARBINARY(8),@reason NVARCHAR(500),@user_id VARCHAR(10)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF LEN(LTRIM(RTRIM(ISNULL(@reason,''))))<5 THROW 51130,'A meaningful reversal reason is required.',1;
 BEGIN TRY
  BEGIN TRANSACTION;
  DECLARE @date DATE,@fy INT,@fp INT,@source CHAR(3),@whse VARCHAR(5),@ref VARCHAR(20),
    @reversal_date DATE=CONVERT(DATE,GETDATE()),@reversal_fy INT,@reversal_fp INT;
  SELECT @date=issue_date,@fy=fiscal_year,@fp=fiscal_period,@source=trans_type,@whse=whse_code,@ref=reference
  FROM dbo.a_issue_hdr WITH(UPDLOCK,HOLDLOCK)
  WHERE issue_no=@issue_no AND status='A' AND no_of_reverts=0 AND row_version=@expected_row_version;
  IF @date IS NULL THROW 51131,'Only an unchanged active Posted material issuance can be reversed.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.m_fiscal_period
    WHERE fiscal_year=@fy AND fiscal_period=@fp AND (current_period_flag='Y' OR previous_period_flag='Y'))
    THROW 51132,'The inventory/accounting period is closed for reversal.',1;
  SELECT @reversal_fy=fiscal_year,@reversal_fp=fiscal_period
  FROM dbo.m_fiscal_period
  WHERE @reversal_date>=CONVERT(DATE,date_from) AND @reversal_date<=CONVERT(DATE,date_to)
    AND (current_period_flag='Y' OR previous_period_flag='Y');
  IF @reversal_fy IS NULL THROW 51136,'No open inventory/accounting period contains the reversal date.',1;

  DECLARE @allocation BIGINT,@seq INT,@lotrow INT,@item VARCHAR(20),@qty DECIMAL(18,4),@cost DECIMAL(18,4),
   @value DECIMAL(18,4),@baseum CHAR(3),@begqty DECIMAL(18,4),@begcost DECIMAL(18,4),@newqty DECIMAL(18,4),@newcost DECIMAL(18,4);
  DECLARE reverse_cursor CURSOR LOCAL FAST_FORWARD FOR
   SELECT l.allocation_id,l.issue_seq,l.rr_lot_row_no,l.item_code,l.allocated_base_qty,l.unit_cost,l.issue_value,d.base_um
   FROM dbo.a_issue_lot l JOIN dbo.a_issue_det d ON d.issue_no=l.issue_no AND d.issue_seq=l.issue_seq
   WHERE l.issue_no=@issue_no AND l.is_active=1 ORDER BY l.allocation_id;
  OPEN reverse_cursor; FETCH NEXT FROM reverse_cursor INTO @allocation,@seq,@lotrow,@item,@qty,@cost,@value,@baseum;
  WHILE @@FETCH_STATUS=0
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.a_rr_lot WITH(UPDLOCK,HOLDLOCK) WHERE row_no=@lotrow AND qty_issued>=@qty)
      THROW 51133,'FIFO receipt layer no longer contains the issued quantity.',1;
   SELECT @begqty=qty_rcv-qty_issued,@begcost=on_hand_cost FROM dbo.a_whse_item WITH(UPDLOCK,HOLDLOCK)
    WHERE whse_code=@whse AND item_code=@item;
   IF @begqty IS NULL THROW 51134,'Warehouse item balance was not found.',1;
   SET @newqty=@begqty+@qty; SET @newcost=ROUND(@begcost+@value,4);
   UPDATE dbo.a_rr_lot SET qty_issued=qty_issued-@qty,user_id=@user_id,date_changed=GETDATE() WHERE row_no=@lotrow;
   UPDATE dbo.a_whse_item SET qty_issued=qty_issued-@qty,qty_for_issue=qty_for_issue+@qty,
    on_hand_cost=@newcost,user_id=@user_id,date_changed=GETDATE()
    WHERE whse_code=@whse AND item_code=@item;
   INSERT dbo.a_issue_inventory_movement(issue_no,issue_seq,allocation_id,movement_type,movement_date,whse_code,item_code,base_um,
    base_qty,unit_cost,movement_value,beg_bal_qty,beg_bal_cost,end_bal_qty,end_bal_cost,user_id)
   VALUES(@issue_no,@seq,@allocation,'REV',GETDATE(),@whse,@item,@baseum,@qty,@cost,@value,@begqty,@begcost,@newqty,@newcost,@user_id);
   INSERT dbo.a_inv_hst(trans_type,trans_no,trans_date,trans_line_no,whse_code,ref_trans_type,reference,item_code,beg_bal_qty,
    beg_bal_cost,trans_qty,base_um,po_conv_factor,pr_conv_factor,unit_cost,unit_price,rr_lot_no,rr_lot_trans_type,remarks,
    user_id,date_changed,fiscal_year,fiscal_period,cust_code,loading_plan_no,issue_um,issue_conv_factor)
   SELECT 'IRV',@issue_no,@reversal_date,@seq,@whse,@source,@ref,@item,@begqty,@begcost,@qty,@baseum,1,1,@cost,@cost,l.rr_no,
    'RR',LEFT(@reason,100),@user_id,GETDATE(),@reversal_fy,@reversal_fp,'','',d.issue_um,d.conv_factor
   FROM dbo.a_issue_lot l JOIN dbo.a_issue_det d ON d.issue_no=l.issue_no AND d.issue_seq=l.issue_seq WHERE l.allocation_id=@allocation;
   UPDATE dbo.a_issue_lot SET is_active=0,reversed_at=SYSUTCDATETIME() WHERE allocation_id=@allocation;
   FETCH NEXT FROM reverse_cursor INTO @allocation,@seq,@lotrow,@item,@qty,@cost,@value,@baseum;
  END;
  CLOSE reverse_cursor; DEALLOCATE reverse_cursor;

  DECLARE @original VARCHAR(15)='MI-'+@issue_no,@journal VARCHAR(15)='MR-'+@issue_no,@total DECIMAL(18,4);
  SELECT @total=total_debit FROM dbo.a_issue_gl_hdr WHERE journal_no=@original;
  IF @total IS NULL THROW 51135,'Original material issuance journal was not found.',1;
  INSERT dbo.a_issue_gl_hdr(journal_no,issue_no,journal_type,journal_date,source_type,total_debit,total_credit,created_by)
  VALUES(@journal,@issue_no,'REVERSAL',@reversal_date,@source,@total,@total,@user_id);
  INSERT dbo.a_issue_gl_det(journal_no,line_no,account_code,debit,credit,reference,narration)
  SELECT @journal,line_no,account_code,credit,debit,@issue_no,'Reversal: '+@reason FROM dbo.a_issue_gl_det WHERE journal_no=@original;
  EXEC dbo.usp_MaterialIssuance_PostLegacyJournal @journal_no=@journal,@issue_no=@issue_no,@journal_date=@reversal_date,
   @fiscal_year=@reversal_fy,@fiscal_period=@reversal_fp,@user_id=@user_id;
  INSERT dbo.a_issue_reversal_log(issue_no,reason,reversed_by,original_row_version)
  VALUES(@issue_no,LTRIM(RTRIM(@reason)),@user_id,@expected_row_version);
  UPDATE dbo.a_issue_hdr SET reverted_by=@user_id,reverted_when=GETDATE(),revert_remarks=@reason,
   no_of_reverts=no_of_reverts+1,updated_by=@user_id,updated_date=GETDATE() WHERE issue_no=@issue_no;
  DECLARE @rv VARBINARY(8); SELECT @rv=row_version FROM dbo.a_issue_hdr WHERE issue_no=@issue_no;
  COMMIT;
  SELECT LTRIM(RTRIM(@issue_no)) IssueNo,'A' Status,'R' EffectiveStatus,@rv RowVersion,'Material issuance reversed successfully.' Message;
 END TRY
 BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  IF CURSOR_STATUS('local','reverse_cursor')>=-1 BEGIN CLOSE reverse_cursor; DEALLOCATE reverse_cursor; END;
  THROW;
 END CATCH
END;
GO
