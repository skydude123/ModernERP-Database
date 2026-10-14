SET NOCOUNT ON;
SELECT 'POSTED_WITHOUT_ONE_LINK' check_name,h.dep_run_no
FROM dbo.a_dep_run_hdr h LEFT JOIN dbo.a_dep_run_journal_link l ON l.dep_run_no=h.dep_run_no
WHERE h.status='POSTED' GROUP BY h.dep_run_no HAVING COUNT(l.dep_run_no)<>1;
SELECT 'POSTED_DETAIL_WITHOUT_SCHEDULE',d.dep_run_no,d.asset_id
FROM dbo.a_dep_run_dtl d JOIN dbo.a_dep_run_hdr h ON h.dep_run_no=d.dep_run_no
LEFT JOIN dbo.a_dep_schedule s ON s.dep_run_no=d.dep_run_no AND s.asset_id=d.asset_id AND s.is_active=1
WHERE h.status='POSTED' AND d.is_selected=1 AND d.current_depreciation>0 AND s.schedule_id IS NULL;
SELECT 'DUPLICATE_ACTIVE_ASSET_PERIOD',asset_id,period_key,COUNT(*) row_count FROM dbo.a_dep_schedule
WHERE is_active=1 GROUP BY asset_id,period_key HAVING COUNT(*)>1;
SELECT 'UNBALANCED_JOURNAL',journal_no,SUM(debit) debit,SUM(credit) credit FROM dbo.a_dep_journal_dtl
GROUP BY journal_no HAVING SUM(debit)<>SUM(credit);
SELECT 'JOURNAL_BATCH_MISMATCH',h.dep_run_no,h.total_current_depreciation,j.total_debit
FROM dbo.a_dep_run_hdr h JOIN dbo.a_dep_journal_hdr j ON j.journal_no=h.journal_no
WHERE h.total_current_depreciation<>j.total_debit;
SELECT 'NBV_BELOW_RESIDUAL',schedule_id,asset_id,period_key FROM dbo.a_dep_schedule WHERE closing_net_book_value<residual_value;
SELECT 'ACCUMULATION_ABOVE_BASE',schedule_id,asset_id,period_key FROM dbo.a_dep_schedule
WHERE closing_accumulated_depreciation>acquisition_cost-residual_value;
SELECT 'INACTIVE_OR_UNKNOWN_POSTING_ACCOUNT',j.journal_no,j.account_code
FROM dbo.a_dep_journal_dtl j
WHERE EXISTS(SELECT 1 FROM dbo.a_asset_gl_account)
 AND NOT EXISTS(SELECT 1 FROM dbo.a_asset_gl_account a WHERE a.account_code=j.account_code AND a.active_flag='Y');
SELECT 'REVERSED_WITHOUT_JOURNAL',dep_run_no FROM dbo.a_dep_run_hdr WHERE status='REVERSED' AND reversal_journal_no IS NULL;
SELECT 'REVERSED_ACTIVE_SCHEDULE',s.dep_run_no,s.asset_id FROM dbo.a_dep_schedule s
JOIN dbo.a_dep_run_hdr h ON h.dep_run_no=s.dep_run_no WHERE h.status='REVERSED' AND s.is_active=1;

;WITH cases AS
(
 SELECT 'Building Improvement / SL' case_name,CAST(1200000 AS DECIMAL(19,4)) cost,CAST(0 AS DECIMAL(19,4)) residual,120 life,CAST(0 AS DECIMAL(19,4)) opening,'SL' method,CAST(10000 AS DECIMAL(19,4)) expected
 UNION ALL SELECT 'Large-Format Machine / SL',1800000,180000,120,0,'SL',13500
 UNION ALL SELECT 'Car / DDB',1500000,150000,60,300000,'DDB',40000
 UNION ALL SELECT 'Desktop / SL',60000,0,36,0,'SL',1666.67
 UNION ALL SELECT 'Laptop / SL',90000,9000,36,0,'SL',2250
 UNION ALL SELECT 'Land / NONDEP',2000000,0,1,0,'NONDEP',0
), calculated AS
(
 SELECT *,CAST(CASE WHEN method='SL' THEN ROUND((cost-residual)/life,2)
   WHEN method='DDB' THEN ROUND((cost-opening)*2.0/life,2) ELSE 0 END AS DECIMAL(19,4)) raw_amount
 FROM cases
)
SELECT 'CALCULATION_CASE' check_name,case_name,
 CASE WHEN raw_amount>cost-opening-residual THEN cost-opening-residual ELSE raw_amount END actual,expected,
 CASE WHEN CASE WHEN raw_amount>cost-opening-residual THEN cost-opening-residual ELSE raw_amount END=expected THEN 'PASS' ELSE 'FAIL' END result
FROM calculated;
