SET NOCOUNT ON;
GO
IF OBJECT_ID('dbo.usp_Depreciation_SaveDraft','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_SaveDraft AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_SaveDraft
 @dep_run_no VARCHAR(30)=NULL,@period_key CHAR(6),@run_date DATE,@branch_code VARCHAR(50)=NULL,
 @asset_category_code VARCHAR(30)=NULL,@method_code VARCHAR(30)=NULL,@convention VARCHAR(20),
 @include_zero BIT,@remarks NVARCHAR(500)=NULL,@user_id VARCHAR(50),@expected_row_version VARCHAR(16)=NULL,
 @details dbo.DepreciationRunDetailType READONLY
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 IF NOT EXISTS(SELECT 1 FROM @details WHERE is_selected=1) RAISERROR('Select at least one asset.',16,1);
 DECLARE @period_start DATE=DATEFROMPARTS(CONVERT(INT,LEFT(@period_key,4)),CONVERT(INT,RIGHT(@period_key,2)),1);
 DECLARE @period_end DATE=EOMONTH(@period_start);
 BEGIN TRY
  BEGIN TRAN;
  IF NULLIF(@dep_run_no,'') IS NULL
  BEGIN
   UPDATE dbo.a_dep_run_series WITH(UPDLOCK,HOLDLOCK) SET last_no=last_no+1,updated_at=SYSUTCDATETIME() WHERE series_key='DEP';
   SELECT @dep_run_no='DEP-'+@period_key+'-'+RIGHT('000000'+CONVERT(VARCHAR(6),last_no),6) FROM dbo.a_dep_run_series WHERE series_key='DEP';
   INSERT dbo.a_dep_run_hdr(dep_run_no,period_key,period_start,period_end,run_date,branch_code,asset_category_code,method_code,
    depreciation_convention,include_zero_amount,status,remarks,prepared_by)
   VALUES(@dep_run_no,@period_key,@period_start,@period_end,@run_date,@branch_code,@asset_category_code,@method_code,
    @convention,@include_zero,'DRAFT',@remarks,@user_id);
  END
  ELSE
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.a_dep_run_hdr WITH(UPDLOCK,HOLDLOCK) WHERE dep_run_no=@dep_run_no AND status='DRAFT'
      AND row_version=CONVERT(VARBINARY(8),@expected_row_version,2))
    RAISERROR('The draft changed, is read-only, or no longer exists.',16,1);
   UPDATE dbo.a_dep_run_hdr SET period_key=@period_key,period_start=@period_start,period_end=@period_end,run_date=@run_date,
    branch_code=@branch_code,asset_category_code=@asset_category_code,method_code=@method_code,
    depreciation_convention=@convention,include_zero_amount=@include_zero,remarks=@remarks,updated_at=SYSUTCDATETIME()
   WHERE dep_run_no=@dep_run_no;
   DELETE dbo.a_dep_run_dtl WHERE dep_run_no=@dep_run_no;
  END;

  ;WITH base AS
  (
   SELECT x.line_no,x.is_selected,a.*,
    ISNULL((SELECT SUM(s.current_depreciation) FROM dbo.a_dep_schedule s WHERE s.asset_id=a.asset_master_id AND s.is_active=1),0) opening_acc,
    ISNULL((SELECT COUNT(*) FROM dbo.a_dep_schedule s WHERE s.asset_id=a.asset_master_id AND s.is_active=1 AND s.current_depreciation>0),0) periods_before
   FROM @details x JOIN dbo.a_asset_master a ON a.asset_master_id=x.asset_id
  ), calc AS
  (
   SELECT b.*,b.acquisition_cost-b.opening_acc opening_nbv,
    CASE WHEN b.depreciation_method_code='NONE' THEN 'NONDEP' ELSE b.depreciation_method_code END normalized_method,
    CAST(CASE WHEN b.depreciation_method_code='SL' THEN 1.0/NULLIF(b.useful_life_months,0)
              WHEN b.depreciation_method_code='DDB' THEN 2.0/NULLIF(b.useful_life_months,0) ELSE 0 END AS DECIMAL(19,8)) rate
   FROM base b
  ), amount AS
  (
   SELECT c.*,CAST(CASE WHEN normalized_method='NONDEP' THEN 0
    WHEN normalized_method='SL' THEN ROUND((acquisition_cost-residual_value)/NULLIF(useful_life_months,0),2)
    WHEN normalized_method='DDB' THEN ROUND(opening_nbv*2.0/NULLIF(useful_life_months,0),2) ELSE 0 END AS DECIMAL(19,4)) raw_amount
   FROM calc c
  )
  INSERT dbo.a_dep_run_dtl(dep_run_no,line_no,asset_id,asset_code,asset_description,asset_category_code,branch_code,
   location_code,custodian_code,acquisition_date,in_service_date,depreciation_start_date,method_code,convention,
   acquisition_cost,residual_value,useful_life_months,periods_depreciated_before,opening_accumulated_depreciation,
   opening_net_book_value,depreciation_rate,current_depreciation,closing_accumulated_depreciation,closing_net_book_value,
   asset_cost_account,depreciation_expense_account,accumulated_depreciation_account,is_selected,eligibility_status,
   eligibility_message)
  SELECT @dep_run_no,line_no,asset_master_id,asset_no,description,asset_category_code,branch_name,asset_location_code,
   custodian_code,CAST(created_at AS DATE),in_service_date,depreciation_start_date,normalized_method,@convention,
   acquisition_cost,residual_value,useful_life_months,periods_before,opening_acc,opening_nbv,rate,
   CASE WHEN raw_amount>opening_nbv-residual_value THEN opening_nbv-residual_value ELSE raw_amount END,
   opening_acc+CASE WHEN raw_amount>opening_nbv-residual_value THEN opening_nbv-residual_value ELSE raw_amount END,
   opening_nbv-CASE WHEN raw_amount>opening_nbv-residual_value THEN opening_nbv-residual_value ELSE raw_amount END,
   asset_cost_account,depreciation_expense_account,accumulated_depreciation_account,is_selected,
   CASE WHEN status='ACTIVE' AND acquisition_cost>0 AND residual_value BETWEEN 0 AND acquisition_cost
     AND normalized_method IN('SL','DDB','NONDEP') AND (normalized_method='NONDEP' OR useful_life_months>0)
     AND depreciation_start_date IS NOT NULL
     AND ((@convention='FULL_MONTH' AND depreciation_start_date<=@period_end)
       OR (@convention='NEXT_MONTH' AND DATEADD(MONTH,1,DATEADD(DAY,1-DAY(depreciation_start_date),depreciation_start_date))<=@period_start))
     AND (normalized_method='NONDEP' OR opening_nbv>residual_value)
     AND NULLIF(LTRIM(RTRIM(depreciation_expense_account)),'') IS NOT NULL
     AND NULLIF(LTRIM(RTRIM(accumulated_depreciation_account)),'') IS NOT NULL
     AND NOT EXISTS(SELECT 1 FROM dbo.a_dep_schedule s WHERE s.asset_id=asset_master_id AND s.period_key=@period_key AND s.is_active=1)
     THEN 'ELIGIBLE' ELSE 'INELIGIBLE' END,
   CASE WHEN status<>'ACTIVE' THEN 'Asset is not active.'
     WHEN residual_value<0 OR residual_value>acquisition_cost THEN 'Residual value is invalid.'
     WHEN normalized_method NOT IN('SL','DDB','NONDEP') THEN 'Unsupported depreciation method.'
     WHEN normalized_method<>'NONDEP' AND useful_life_months<=0 THEN 'Useful life is invalid.'
     WHEN depreciation_start_date IS NULL THEN 'Depreciation start date is required.'
     WHEN @convention='FULL_MONTH' AND depreciation_start_date>@period_end THEN 'Asset has not reached its depreciation start date.'
     WHEN @convention='NEXT_MONTH' AND DATEADD(MONTH,1,DATEADD(DAY,1-DAY(depreciation_start_date),depreciation_start_date))>@period_start THEN 'Asset is not eligible until the next month.'
     WHEN normalized_method<>'NONDEP' AND opening_nbv<=residual_value THEN 'Asset is fully depreciated.'
     WHEN NULLIF(LTRIM(RTRIM(depreciation_expense_account)),'') IS NULL OR NULLIF(LTRIM(RTRIM(accumulated_depreciation_account)),'') IS NULL THEN 'Posting accounts are required.'
     WHEN EXISTS(SELECT 1 FROM dbo.a_dep_schedule s WHERE s.asset_id=asset_master_id AND s.period_key=@period_key AND s.is_active=1) THEN 'Duplicate asset-period.'
     ELSE NULL END
  FROM amount;

  IF EXISTS(SELECT 1 FROM dbo.a_dep_run_dtl WHERE dep_run_no=@dep_run_no AND is_selected=1 AND eligibility_status<>'ELIGIBLE')
   RAISERROR('Selected assets contain server validation errors. Recalculate before saving.',16,1);
  IF NOT EXISTS(SELECT 1 FROM dbo.a_dep_run_dtl WHERE dep_run_no=@dep_run_no AND is_selected=1 AND (current_depreciation>0 OR (@include_zero=1 AND method_code='NONDEP')))
   RAISERROR('The draft has no selected depreciable or included non-depreciating assets.',16,1);

  UPDATE h SET asset_count=x.asset_count,total_acquisition_cost=x.cost,total_opening_accumulated_depreciation=x.open_acc,
   total_current_depreciation=x.current_dep,total_closing_accumulated_depreciation=x.close_acc,
   total_closing_net_book_value=x.close_nbv
  FROM dbo.a_dep_run_hdr h CROSS APPLY
  (SELECT COUNT(*) asset_count,SUM(acquisition_cost) cost,SUM(opening_accumulated_depreciation) open_acc,
    SUM(current_depreciation) current_dep,SUM(closing_accumulated_depreciation) close_acc,SUM(closing_net_book_value) close_nbv
   FROM dbo.a_dep_run_dtl d WHERE d.dep_run_no=h.dep_run_no AND d.is_selected=1 AND d.eligibility_status='ELIGIBLE') x
  WHERE h.dep_run_no=@dep_run_no;
  COMMIT;
  SELECT dep_run_no DepRunNo,status Status,CONVERT(VARCHAR(16),row_version,2) RowVersion,journal_no JournalNo,
   reversal_journal_no ReversalJournalNo,'Depreciation draft saved.' Message FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no;
 END TRY
 BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH
END;
GO

IF OBJECT_ID('dbo.usp_Depreciation_Transition','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_Transition AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_Transition @dep_run_no VARCHAR(30),@action VARCHAR(15),
 @expected_row_version VARCHAR(16),@user_id VARCHAR(50),@reason NVARCHAR(500)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 DECLARE @from VARCHAR(15),@to VARCHAR(15);
 SELECT @from=status FROM dbo.a_dep_run_hdr WITH(UPDLOCK,HOLDLOCK) WHERE dep_run_no=@dep_run_no AND row_version=CONVERT(VARBINARY(8),@expected_row_version,2);
 IF @from IS NULL RAISERROR('The depreciation run changed or no longer exists.',16,1);
 SET @to=CASE WHEN @action='SUBMIT' AND @from='DRAFT' THEN 'SUBMITTED'
              WHEN @action='APPROVE' AND @from='SUBMITTED' THEN 'APPROVED'
              WHEN @action='CANCEL' AND @from='DRAFT' THEN 'CANCELLED' END;
 IF @to IS NULL RAISERROR('Invalid depreciation workflow transition.',16,1);
 UPDATE dbo.a_dep_run_hdr SET status=@to,
  submitted_by=CASE WHEN @action='SUBMIT' THEN @user_id ELSE submitted_by END,
  submitted_at=CASE WHEN @action='SUBMIT' THEN SYSUTCDATETIME() ELSE submitted_at END,
  approved_by=CASE WHEN @action='APPROVE' THEN @user_id ELSE approved_by END,
  approved_at=CASE WHEN @action='APPROVE' THEN SYSUTCDATETIME() ELSE approved_at END,
  cancelled_by=CASE WHEN @action='CANCEL' THEN @user_id ELSE cancelled_by END,
  cancelled_at=CASE WHEN @action='CANCEL' THEN SYSUTCDATETIME() ELSE cancelled_at END,
  cancellation_reason=CASE WHEN @action='CANCEL' THEN @reason ELSE cancellation_reason END
 WHERE dep_run_no=@dep_run_no;
 SELECT dep_run_no DepRunNo,status Status,CONVERT(VARCHAR(16),row_version,2) RowVersion,journal_no JournalNo,
  reversal_journal_no ReversalJournalNo,'Depreciation run is now '+status+'.' Message FROM dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no;
END;
GO

IF OBJECT_ID('dbo.usp_Depreciation_Submit','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_Submit AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_Submit @dep_run_no VARCHAR(30),@expected_row_version VARCHAR(16),@user_id VARCHAR(50),@reason NVARCHAR(500)=NULL AS
EXEC dbo.usp_Depreciation_Transition @dep_run_no,'SUBMIT',@expected_row_version,@user_id,@reason;
GO
IF OBJECT_ID('dbo.usp_Depreciation_Approve','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_Approve AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_Approve @dep_run_no VARCHAR(30),@expected_row_version VARCHAR(16),@user_id VARCHAR(50),@reason NVARCHAR(500)=NULL AS
EXEC dbo.usp_Depreciation_Transition @dep_run_no,'APPROVE',@expected_row_version,@user_id,@reason;
GO
IF OBJECT_ID('dbo.usp_Depreciation_CancelDraft','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_CancelDraft AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_CancelDraft @dep_run_no VARCHAR(30),@expected_row_version VARCHAR(16),@user_id VARCHAR(50),@reason NVARCHAR(500)=NULL AS
EXEC dbo.usp_Depreciation_Transition @dep_run_no,'CANCEL',@expected_row_version,@user_id,@reason;
GO
IF OBJECT_ID('dbo.usp_Depreciation_DeleteDraft','P') IS NULL EXEC('CREATE PROCEDURE dbo.usp_Depreciation_DeleteDraft AS RETURN 0;');
GO
ALTER PROCEDURE dbo.usp_Depreciation_DeleteDraft @dep_run_no VARCHAR(30),@expected_row_version VARCHAR(16),@user_id VARCHAR(50),@reason NVARCHAR(500)=NULL
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 BEGIN TRY
  BEGIN TRAN;
  IF NOT EXISTS(SELECT 1 FROM dbo.a_dep_run_hdr WITH(UPDLOCK,HOLDLOCK) WHERE dep_run_no=@dep_run_no AND status='DRAFT' AND row_version=CONVERT(VARBINARY(8),@expected_row_version,2))
   RAISERROR('Only an unchanged Draft can be deleted.',16,1);
  DELETE dbo.a_dep_run_dtl WHERE dep_run_no=@dep_run_no;
  DELETE dbo.a_dep_run_hdr WHERE dep_run_no=@dep_run_no;
  COMMIT;
  SELECT @dep_run_no DepRunNo,'DELETED' Status,CAST(NULL AS VARCHAR(16)) RowVersion,CAST(NULL AS VARCHAR(30)) JournalNo,
   CAST(NULL AS VARCHAR(30)) ReversalJournalNo,'Depreciation draft deleted.' Message;
 END TRY
 BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH
END;
GO
