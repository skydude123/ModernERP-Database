SET NOCOUNT ON;
GO
IF OBJECT_ID('dbo.usp_Depreciation_Reverse','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_Reverse AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_Reverse @dep_run_no VARCHAR(30),@expected_row_version VARCHAR(16),
 @user_id VARCHAR(50),@reason NVARCHAR(500)
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NULLIF(LTRIM(RTRIM(@reason)),'') IS NULL RAISERROR('A reversal reason is required.',16,1);
 DECLARE @status VARCHAR(15),@period_key CHAR(6),@original VARCHAR(30),@reversal VARCHAR(30),@total DECIMAL(19,4);
 BEGIN TRY
  BEGIN TRAN;
  SELECT @status=status,@period_key=period_key,@original=journal_no,@reversal=reversal_journal_no,@total=total_current_depreciation
  FROM dbo.a_dep_run_hdr WITH(UPDLOCK,HOLDLOCK) WHERE dep_run_no=@dep_run_no;
  IF @status='REVERSED'
  BEGIN
   COMMIT;
   SELECT dep_run_no DepRunNo,status Status,CONVERT(VARCHAR(16),row_version,2) RowVersion,journal_no JournalNo,
    reversal_journal_no ReversalJournalNo,'Depreciation was already reversed; the original result was returned.' Message
   FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no; RETURN;
  END;
  IF @status<>'POSTED' OR NOT EXISTS(SELECT 1 FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no AND row_version=CONVERT(VARBINARY(8),@expected_row_version,2))
   RAISERROR('Only the current posted depreciation run can be reversed.',16,1);
  IF EXISTS(SELECT 1 FROM dbo.a_dep_schedule current_row JOIN dbo.a_dep_schedule later
    ON later.asset_id=current_row.asset_id AND later.is_active=1 AND later.period_key>@period_key
    WHERE current_row.dep_run_no=@dep_run_no AND current_row.is_active=1)
   RAISERROR('A later posted depreciation period exists for an affected asset. Reverse later periods first.',16,1);
  SET @reversal='DEPR-'+REPLACE(@dep_run_no,'DEP-','');
  INSERT dbo.a_dep_journal_hdr(journal_no,journal_date,period_key,source_type,source_no,status,total_debit,total_credit,narration,created_by)
  SELECT @reversal,CAST(SYSUTCDATETIME() AS DATE),period_key,'DEP_REVERSAL',dep_run_no,'POSTED',@total,@total,
   'Reversal: '+@reason,@user_id FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no;
  INSERT dbo.a_dep_journal_dtl(journal_no,line_no,branch_code,account_code,debit,credit,reference,narration)
  SELECT @reversal,line_no,branch_code,account_code,credit,debit,@dep_run_no,'Reversal: '+@reason
  FROM dbo.a_dep_journal_dtl WHERE journal_no=@original;
  UPDATE dbo.a_dep_schedule SET is_active=0,reversed_by_run_no=@dep_run_no,reversed_at=SYSUTCDATETIME()
  WHERE dep_run_no=@dep_run_no AND is_active=1;
  UPDATE dbo.a_dep_run_journal_link SET is_reversed=1,reversal_journal_no=@reversal,reversed_at=SYSUTCDATETIME()
  WHERE dep_run_no=@dep_run_no;
  INSERT dbo.a_dep_run_reversal_log(dep_run_no,original_journal_no,reversal_journal_no,reason,reversed_by)
  VALUES(@dep_run_no,@original,@reversal,@reason,@user_id);
  UPDATE dbo.a_dep_run_hdr SET status='REVERSED',reversal_journal_no=@reversal,reversed_by=@user_id,reversed_at=SYSUTCDATETIME()
  WHERE dep_run_no=@dep_run_no;
  COMMIT;
  SELECT dep_run_no DepRunNo,status Status,CONVERT(VARCHAR(16),row_version,2) RowVersion,journal_no JournalNo,
   reversal_journal_no ReversalJournalNo,'Depreciation reversed successfully.' Message FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no;
 END TRY
 BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH
END;
GO
