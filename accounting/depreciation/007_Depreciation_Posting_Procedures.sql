SET NOCOUNT ON;
GO
IF OBJECT_ID('dbo.usp_Depreciation_Post','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_Post AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_Post @dep_run_no VARCHAR(30),@expected_row_version VARCHAR(16),
 @user_id VARCHAR(50),@reason NVARCHAR(500)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @status VARCHAR(15),@period_key CHAR(6),@journal_no VARCHAR(30),@total DECIMAL(19,4);
 BEGIN TRY
  BEGIN TRAN;
  SELECT @status=status,@period_key=period_key,@journal_no=journal_no,@total=total_current_depreciation
  FROM dbo.a_dep_run_hdr WITH(UPDLOCK,HOLDLOCK) WHERE dep_run_no=@dep_run_no;
  IF @status='POSTED'
  BEGIN
   COMMIT;
   SELECT dep_run_no DepRunNo,status Status,CONVERT(VARCHAR(16),row_version,2) RowVersion,journal_no JournalNo,
    reversal_journal_no ReversalJournalNo,'Depreciation was already posted; the original result was returned.' Message
   FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no; RETURN;
  END;
  IF @status<>'APPROVED' OR NOT EXISTS(SELECT 1 FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no AND row_version=CONVERT(VARBINARY(8),@expected_row_version,2))
   RAISERROR('Only the current approved depreciation run can be posted.',16,1);
  IF @total<=0 RAISERROR('There is no positive depreciation amount to post.',16,1);
  IF EXISTS(SELECT 1 FROM dbo.a_dep_run_dtl d JOIN dbo.a_asset_master a WITH(UPDLOCK,HOLDLOCK) ON a.asset_master_id=d.asset_id
    OUTER APPLY(SELECT ISNULL(SUM(s.current_depreciation),0) opening_acc FROM dbo.a_dep_schedule s WITH(UPDLOCK,HOLDLOCK) WHERE s.asset_id=a.asset_master_id AND s.is_active=1) oa
    CROSS APPLY(SELECT a.acquisition_cost-oa.opening_acc opening_nbv) nbv
    CROSS APPLY(SELECT CAST(CASE WHEN a.depreciation_method_code='SL' THEN ROUND((a.acquisition_cost-a.residual_value)/NULLIF(a.useful_life_months,0),2)
      WHEN a.depreciation_method_code='DDB' THEN ROUND(nbv.opening_nbv*2.0/NULLIF(a.useful_life_months,0),2) ELSE 0 END AS DECIMAL(19,4)) raw_amount) ca
    WHERE d.dep_run_no=@dep_run_no AND d.is_selected=1 AND
     (a.status<>'ACTIVE' OR a.acquisition_cost<>d.acquisition_cost OR a.residual_value<>d.residual_value
      OR a.useful_life_months<>d.useful_life_months OR a.depreciation_method_code<>CASE WHEN d.method_code='NONDEP' THEN 'NONE' ELSE d.method_code END
      OR a.depreciation_expense_account<>d.depreciation_expense_account
      OR a.accumulated_depreciation_account<>d.accumulated_depreciation_account
      OR oa.opening_acc<>d.opening_accumulated_depreciation
      OR CASE WHEN ca.raw_amount>nbv.opening_nbv-a.residual_value THEN nbv.opening_nbv-a.residual_value ELSE ca.raw_amount END<>d.current_depreciation))
   RAISERROR('An asset or account changed after approval. Return the batch to Draft and recalculate.',16,1);
  IF EXISTS(SELECT 1 FROM dbo.a_dep_run_dtl d WHERE d.dep_run_no=@dep_run_no AND d.is_selected=1
    AND EXISTS(SELECT 1 FROM dbo.a_dep_schedule s WITH(UPDLOCK,HOLDLOCK) WHERE s.asset_id=d.asset_id AND s.period_key=@period_key AND s.is_active=1))
   RAISERROR('A posted schedule already exists for one or more asset-periods.',16,1);
  IF EXISTS(SELECT 1 FROM dbo.a_dep_run_dtl d WHERE d.dep_run_no=@dep_run_no AND d.is_selected=1 AND d.current_depreciation>0
    AND (NULLIF(d.depreciation_expense_account,'') IS NULL OR NULLIF(d.accumulated_depreciation_account,'') IS NULL))
   RAISERROR('Every posted line requires expense and accumulated depreciation accounts.',16,1);
  IF EXISTS(SELECT 1 FROM dbo.a_asset_gl_account)
   AND EXISTS(SELECT 1 FROM dbo.a_dep_run_dtl d WHERE d.dep_run_no=@dep_run_no AND d.is_selected=1 AND d.current_depreciation>0
    AND (NOT EXISTS(SELECT 1 FROM dbo.a_asset_gl_account g WHERE g.account_code=d.depreciation_expense_account AND g.active_flag='Y')
      OR NOT EXISTS(SELECT 1 FROM dbo.a_asset_gl_account g WHERE g.account_code=d.accumulated_depreciation_account AND g.active_flag='Y')))
   RAISERROR('A depreciation account is inactive or is not an approved posting account.',16,1);

  SET @journal_no='DEPJ-'+REPLACE(@dep_run_no,'DEP-','');
  INSERT dbo.a_dep_journal_hdr(journal_no,journal_date,period_key,source_type,source_no,status,total_debit,total_credit,narration,created_by)
  SELECT @journal_no,period_end,period_key,'DEPRECIATION',dep_run_no,'POSTED',@total,@total,
   'Monthly depreciation '+period_key,@user_id FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no;
  ;WITH g AS
  (
   SELECT branch_code,depreciation_expense_account expense,accumulated_depreciation_account accumulated,SUM(current_depreciation) amount
   FROM dbo.a_dep_run_dtl WHERE dep_run_no=@dep_run_no AND is_selected=1 AND current_depreciation>0
   GROUP BY branch_code,depreciation_expense_account,accumulated_depreciation_account
  ), l AS
  (
   SELECT branch_code,expense account_code,amount debit,CAST(0 AS DECIMAL(19,4)) credit,1 side FROM g
   UNION ALL SELECT branch_code,accumulated,0,amount,2 FROM g
  )
  INSERT dbo.a_dep_journal_dtl(journal_no,line_no,branch_code,account_code,debit,credit,reference,narration)
  SELECT @journal_no,ROW_NUMBER() OVER(ORDER BY branch_code,account_code,side),branch_code,account_code,debit,credit,
   @dep_run_no,CASE side WHEN 1 THEN 'Depreciation expense' ELSE 'Accumulated depreciation' END FROM l;
  IF (SELECT SUM(debit-credit) FROM dbo.a_dep_journal_dtl WHERE journal_no=@journal_no)<>0
   RAISERROR('The depreciation journal is not balanced.',16,1);

  INSERT dbo.a_dep_schedule(dep_run_no,asset_id,period_key,acquisition_cost,residual_value,
   opening_accumulated_depreciation,current_depreciation,closing_accumulated_depreciation,
   closing_net_book_value,journal_no)
  SELECT dep_run_no,asset_id,@period_key,acquisition_cost,residual_value,opening_accumulated_depreciation,
   current_depreciation,closing_accumulated_depreciation,closing_net_book_value,@journal_no
  FROM dbo.a_dep_run_dtl WHERE dep_run_no=@dep_run_no AND is_selected=1 AND current_depreciation>0;
  INSERT dbo.a_dep_run_journal_link(dep_run_no,journal_no,posted_at) VALUES(@dep_run_no,@journal_no,SYSUTCDATETIME());
  UPDATE dbo.a_dep_run_dtl SET posting_status=CASE WHEN current_depreciation>0 THEN 'POSTED' ELSE 'NO_GL' END,
   journal_line_reference=CASE WHEN current_depreciation>0 THEN @journal_no+'-'+CONVERT(VARCHAR(20),asset_id) END
  WHERE dep_run_no=@dep_run_no AND is_selected=1;
  UPDATE dbo.a_dep_run_hdr SET status='POSTED',journal_no=@journal_no,posted_by=@user_id,posted_at=SYSUTCDATETIME()
  WHERE dep_run_no=@dep_run_no;
  COMMIT;
  SELECT dep_run_no DepRunNo,status Status,CONVERT(VARCHAR(16),row_version,2) RowVersion,journal_no JournalNo,
   reversal_journal_no ReversalJournalNo,'Depreciation posted successfully.' Message FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no;
 END TRY
 BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH
END;
GO
