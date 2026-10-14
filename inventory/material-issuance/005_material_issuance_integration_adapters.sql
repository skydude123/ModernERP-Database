/*
The live RISCDB inspected on 2026-07-30 uses dbo.twb_rawmats as the journal
detail equivalent. Its contract is also used by dbo.trg_IssueToProduction.
*/
CREATE OR ALTER PROCEDURE dbo.usp_MaterialIssuance_PostLegacyJournal
 @journal_no VARCHAR(15),@issue_no VARCHAR(10),@journal_date DATE,
 @fiscal_year INT,@fiscal_period INT,@user_id VARCHAR(10)
AS
BEGIN
 SET NOCOUNT ON;
 IF OBJECT_ID('dbo.twb_rawmats','U') IS NULL
   THROW 51150,'Verified legacy GL detail target dbo.twb_rawmats is missing.',1;
 IF EXISTS(SELECT 1 FROM dbo.TWB_JRNLhdr WHERE Jrnl_id=@journal_no) RETURN;

 DECLARE @amount DECIMAL(18,2);
 SELECT @amount=SUM(ROUND(debit,2)) FROM dbo.a_issue_gl_det WHERE journal_no=@journal_no;
 INSERT dbo.TWB_JRNLhdr(Jrnl_id,Refcode,EntryDate,Partlr,BookCode,FiscalYearID,FiscalPeriodID,
  BRANCH_CODE,Posted,InvoiceNo,Amount,Ref_Type,Ref_ID,Date_Changed)
 VALUES(@journal_no,@issue_no,@journal_date,'Material Issuance '+@issue_no,'INV',@fiscal_year,@fiscal_period,
  NULL,1,@issue_no,@amount,'I',@issue_no,GETDATE());

 ;WITH rounded AS
 (
  SELECT line_no,account_code,ROUND(debit,2) AS debit,ROUND(credit,2) AS credit,
    MAX(CASE WHEN credit>0 THEN line_no END) OVER() AS last_credit_line
  FROM dbo.a_issue_gl_det WHERE journal_no=@journal_no
 )
 INSERT dbo.twb_rawmats(jrnl_lineno,Jrnl_id,Fiscalyearid,Fiscalperiodid,AccountID,Debit,Credit,
  Date_changed,datetran,stk_holder,BookCode,twbaux,issue_no)
 SELECT line_no,@journal_no,@fiscal_year,@fiscal_period,account_code,debit,
  CASE WHEN line_no=last_credit_line THEN credit+(@amount-(SELECT SUM(r2.credit) FROM rounded r2)) ELSE credit END,
  GETDATE(),@journal_date,NULL,'INV',NULL,@issue_no
 FROM rounded;
END;
GO
