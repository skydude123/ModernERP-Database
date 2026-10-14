SET NOCOUNT ON;
GO


/* ============================================================
   PROCEDURE: dbo.usp_Depreciation_QueryRuns
   PURPOSE  : Retrieve depreciation runs with filters,
              sorting, searching, and pagination
   ============================================================ */

IF OBJECT_ID(
       'dbo.usp_Depreciation_QueryRuns',
       'P'
   ) IS NULL
BEGIN
    EXEC
    (
        'CREATE PROCEDURE dbo.usp_Depreciation_QueryRuns
         AS
         BEGIN
             SET NOCOUNT ON;
         END;'
    );
END;
GO


ALTER PROCEDURE dbo.usp_Depreciation_QueryRuns
(
    @period_from         CHAR(6)       = NULL,
    @period_to           CHAR(6)       = NULL,
    @run_date_from       DATE          = NULL,
    @run_date_to         DATE          = NULL,
    @status              VARCHAR(15)   = 'ALL',
    @branch_code         VARCHAR(50)   = NULL,
    @asset_category_code VARCHAR(30)   = NULL,
    @method_code         VARCHAR(30)   = NULL,
    @search              NVARCHAR(100) = NULL,
    @skip                INT           = 0,
    @take                INT           = 50,
    @sort_field          VARCHAR(30)   = 'runDate',
    @sort_dir            VARCHAR(4)    = 'desc'
)
AS
BEGIN
    SET NOCOUNT ON;


    /* ========================================================
       Validate pagination parameters
       ======================================================== */

    IF @skip < 0
    BEGIN
        SET @skip = 0;
    END;

    IF @take < 1
    BEGIN
        SET @take = 50;
    END;

    IF @take > 200
    BEGIN
        SET @take = 200;
    END;


    /* ========================================================
       Clean optional parameters
       ======================================================== */

    SET @period_from =
        NULLIF(
            LTRIM(RTRIM(@period_from)),
            ''
        );

    SET @period_to =
        NULLIF(
            LTRIM(RTRIM(@period_to)),
            ''
        );

    SET @branch_code =
        NULLIF(
            LTRIM(RTRIM(@branch_code)),
            ''
        );

    SET @asset_category_code =
        NULLIF(
            LTRIM(RTRIM(@asset_category_code)),
            ''
        );

    SET @method_code =
        NULLIF(
            LTRIM(RTRIM(@method_code)),
            ''
        );

    SET @search =
        NULLIF(
            LTRIM(RTRIM(@search)),
            N''
        );

    SET @status =
        UPPER(
            ISNULL(
                NULLIF(
                    LTRIM(RTRIM(@status)),
                    ''
                ),
                'ALL'
            )
        );

    SET @sort_field =
        ISNULL(
            NULLIF(
                LTRIM(RTRIM(@sort_field)),
                ''
            ),
            'runDate'
        );

    SET @sort_dir =
        LOWER(
            ISNULL(
                NULLIF(
                    LTRIM(RTRIM(@sort_dir)),
                    ''
                ),
                'desc'
            )
        );


    /* Only ASC and DESC are allowed */

    IF @sort_dir NOT IN ('asc', 'desc')
    BEGIN
        SET @sort_dir = 'desc';
    END;


    /* ========================================================
       Retrieve filtered records
       ======================================================== */

    ;WITH SourceData AS
    (
        SELECT
            h.*,

            COUNT(*) OVER ()
                AS [TotalCount]

        FROM dbo.a_dep_run_hdr AS h

        WHERE
            /* Period From */
            (
                @period_from IS NULL
                OR h.period_key >= @period_from
            )

            /* Period To */
            AND
            (
                @period_to IS NULL
                OR h.period_key <= @period_to
            )

            /* Run Date From */
            AND
            (
                @run_date_from IS NULL
                OR h.run_date >= @run_date_from
            )

            /* Run Date To */
            AND
            (
                @run_date_to IS NULL
                OR h.run_date <= @run_date_to
            )

            /* Status */
            AND
            (
                @status = 'ALL'
                OR h.status = @status
            )

            /* Branch */
            AND
            (
                @branch_code IS NULL
                OR h.branch_code = @branch_code
            )

            /* Asset Category */
            AND
            (
                @asset_category_code IS NULL
                OR h.asset_category_code =
                    @asset_category_code
            )

            /* Depreciation Method */
            AND
            (
                @method_code IS NULL
                OR h.method_code = @method_code
            )

            /* General Search */
            AND
            (
                @search IS NULL

                OR h.dep_run_no LIKE
                    N'%' + @search + N'%'

                OR h.journal_no LIKE
                    N'%' + @search + N'%'

                OR h.remarks LIKE
                    N'%' + @search + N'%'

                OR EXISTS
                (
                    SELECT
                        1

                    FROM dbo.a_dep_run_dtl AS d

                    WHERE
                        d.dep_run_no = h.dep_run_no

                        AND
                        (
                            d.asset_code LIKE
                                N'%' + @search + N'%'

                            OR d.asset_description LIKE
                                N'%' + @search + N'%'
                        )
                )
            )
    ),
    NumberedData AS
    (
        SELECT
            SourceData.*,

            ROW_NUMBER() OVER
            (
                ORDER BY

                    /* Period Key - Ascending */
                    CASE
                        WHEN @sort_field = 'periodKey'
                             AND @sort_dir = 'asc'
                        THEN period_key
                    END ASC,

                    /* Period Key - Descending */
                    CASE
                        WHEN @sort_field = 'periodKey'
                             AND @sort_dir = 'desc'
                        THEN period_key
                    END DESC,

                    /* Current Depreciation - Ascending */
                    CASE
                        WHEN @sort_field = 'currentDepreciation'
                             AND @sort_dir = 'asc'
                        THEN total_current_depreciation
                    END ASC,

                    /* Current Depreciation - Descending */
                    CASE
                        WHEN @sort_field = 'currentDepreciation'
                             AND @sort_dir = 'desc'
                        THEN total_current_depreciation
                    END DESC,

                    /* Run Date - Ascending */
                    CASE
                        WHEN @sort_field = 'runDate'
                             AND @sort_dir = 'asc'
                        THEN run_date
                    END ASC,

                    /* Run Date - Descending */
                    CASE
                        WHEN @sort_field = 'runDate'
                             AND @sort_dir = 'desc'
                        THEN run_date
                    END DESC,

                    /* Default tie breaker */
                    dep_run_no DESC

            ) AS [RowNumber]

        FROM SourceData
    )

    /* ========================================================
       Final paginated result
       ======================================================== */

    SELECT
        dep_run_no
            AS [DepRunNo],

        period_key
            AS [PeriodKey],

        run_date
            AS [RunDate],

        branch_code
            AS [BranchCode],

        asset_category_code
            AS [AssetCategoryCode],

        method_code
            AS [MethodCode],

        status
            AS [Status],

        asset_count
            AS [AssetCount],

        total_acquisition_cost
            AS [TotalAcquisitionCost],

        total_current_depreciation
            AS [TotalCurrentDepreciation],

        total_closing_net_book_value
            AS [TotalClosingNetBookValue],

        journal_no
            AS [JournalNo],

        prepared_by
            AS [PreparedBy],

        approved_by
            AS [ApprovedBy],

        posted_by
            AS [PostedBy],

        posted_at
            AS [PostedAt],

        reversal_journal_no
            AS [ReversalJournalNo],

        remarks
            AS [Remarks],

        TotalCount
            AS [TotalCount]

    FROM NumberedData

    WHERE
        RowNumber > @skip
        AND RowNumber <= (@skip + @take)

    ORDER BY
        RowNumber;
END;
GO



/* ============================================================
   PROCEDURE: dbo.usp_Depreciation_GetRunByNo
   PURPOSE  : Retrieve depreciation header, details,
              journal preview, and validation messages
   ============================================================ */

IF OBJECT_ID(
       'dbo.usp_Depreciation_GetRunByNo',
       'P'
   ) IS NULL
BEGIN
    EXEC
    (
        'CREATE PROCEDURE dbo.usp_Depreciation_GetRunByNo
         AS
         BEGIN
             SET NOCOUNT ON;
         END;'
    );
END;
GO


ALTER PROCEDURE dbo.usp_Depreciation_GetRunByNo
(
    @dep_run_no VARCHAR(30)
)
AS
BEGIN
    SET NOCOUNT ON;


    /* ========================================================
       Clean and validate depreciation run number
       ======================================================== */

    SET @dep_run_no =
        NULLIF(
            LTRIM(RTRIM(@dep_run_no)),
            ''
        );


    /* ========================================================
       RESULT SET 1: Depreciation Run Header
       ======================================================== */

    SELECT
        h.dep_run_no
            AS [DepRunNo],

        h.period_key
            AS [PeriodKey],

        h.period_start
            AS [PeriodStart],

        h.period_end
            AS [PeriodEnd],

        h.run_date
            AS [RunDate],

        h.branch_code
            AS [BranchCode],

        h.asset_category_code
            AS [AssetCategoryCode],

        h.method_code
            AS [MethodCode],

        h.depreciation_convention
            AS [DepreciationConvention],

        h.include_zero_amount
            AS [IncludeZeroAmount],

        h.status
            AS [Status],

        h.asset_count
            AS [AssetCount],

        h.total_acquisition_cost
            AS [TotalAcquisitionCost],

        h.total_opening_accumulated_depreciation
            AS [TotalOpeningAccumulatedDepreciation],

        h.total_current_depreciation
            AS [TotalCurrentDepreciation],

        h.total_closing_accumulated_depreciation
            AS [TotalClosingAccumulatedDepreciation],

        h.total_closing_net_book_value
            AS [TotalClosingNetBookValue],

        h.journal_no
            AS [JournalNo],

        h.reversal_journal_no
            AS [ReversalJournalNo],

        h.remarks
            AS [Remarks],

        h.prepared_by
            AS [PreparedBy],

        h.submitted_by
            AS [SubmittedBy],

        h.approved_by
            AS [ApprovedBy],

        h.posted_by
            AS [PostedBy],

        h.reversed_by
            AS [ReversedBy],

        h.created_at
            AS [CreatedAt],

        h.submitted_at
            AS [SubmittedAt],

        h.approved_at
            AS [ApprovedAt],

        h.posted_at
            AS [PostedAt],

        h.reversed_at
            AS [ReversedAt],

        CONVERT(
            VARCHAR(16),
            h.row_version,
            2
        ) AS [RowVersion]

    FROM dbo.a_dep_run_hdr AS h

    WHERE
        h.dep_run_no = @dep_run_no;


    /* ========================================================
       RESULT SET 2: Depreciation Run Details

       Important:
       Use AS [LineNo] because LINENO is treated as a keyword.
       ======================================================== */

    SELECT
        d.line_no
            AS [LineNo],

        d.asset_id
            AS [AssetId],

        d.asset_code
            AS [AssetCode],

        d.asset_description
            AS [AssetDescription],

        d.asset_category_code
            AS [AssetCategoryCode],

        d.branch_code
            AS [BranchCode],

        d.location_code
            AS [LocationCode],

        d.custodian_code
            AS [CustodianCode],

        d.acquisition_date
            AS [AcquisitionDate],

        d.in_service_date
            AS [InServiceDate],

        d.depreciation_start_date
            AS [DepreciationStartDate],

        d.method_code
            AS [MethodCode],

        d.convention
            AS [Convention],

        d.acquisition_cost
            AS [AcquisitionCost],

        d.residual_value
            AS [ResidualValue],

        d.useful_life_months
            AS [UsefulLifeMonths],

        d.periods_depreciated_before
            AS [PeriodsDepreciatedBefore],

        d.opening_accumulated_depreciation
            AS [OpeningAccumulatedDepreciation],

        d.opening_net_book_value
            AS [OpeningNetBookValue],

        d.depreciation_rate
            AS [DepreciationRate],

        d.current_depreciation
            AS [CurrentDepreciation],

        d.closing_accumulated_depreciation
            AS [ClosingAccumulatedDepreciation],

        d.closing_net_book_value
            AS [ClosingNetBookValue],

        d.asset_cost_account
            AS [AssetCostAccount],

        d.depreciation_expense_account
            AS [DepreciationExpenseAccount],

        d.accumulated_depreciation_account
            AS [AccumulatedDepreciationAccount],

        d.is_selected
            AS [IsSelected],

        d.eligibility_status
            AS [EligibilityStatus],

        d.eligibility_message
            AS [EligibilityMessage],

        d.posting_status
            AS [PostingStatus],

        d.journal_line_reference
            AS [JournalLineReference]

    FROM dbo.a_dep_run_dtl AS d

    WHERE
        d.dep_run_no = @dep_run_no

    ORDER BY
        d.line_no;


    /* ========================================================
       RESULT SET 3: Proposed Journal Entry

       Debit:
           Depreciation Expense

       Credit:
           Accumulated Depreciation
       ======================================================== */

    ;WITH AccountGrouping AS
    (
        SELECT
            d.branch_code,

            d.depreciation_expense_account
                AS [ExpenseAccount],

            d.accumulated_depreciation_account
                AS [AccumulatedAccount],

            SUM(d.current_depreciation)
                AS [Amount]

        FROM dbo.a_dep_run_dtl AS d

        WHERE
            d.dep_run_no = @dep_run_no
            AND d.is_selected = 1
            AND d.current_depreciation > 0

        GROUP BY
            d.branch_code,
            d.depreciation_expense_account,
            d.accumulated_depreciation_account
    ),
    JournalLines AS
    (
        /* Debit line */
        SELECT
            g.branch_code
                AS [BranchCode],

            g.ExpenseAccount
                AS [AccountCode],

            g.Amount
                AS [Debit],

            CAST(0 AS DECIMAL(19, 4))
                AS [Credit],

            CAST(
                'Depreciation expense'
                AS VARCHAR(100)
            ) AS [Narration],

            1 AS [SortOrder]

        FROM AccountGrouping AS g


        UNION ALL


        /* Credit line */
        SELECT
            g.branch_code
                AS [BranchCode],

            g.AccumulatedAccount
                AS [AccountCode],

            CAST(0 AS DECIMAL(19, 4))
                AS [Debit],

            g.Amount
                AS [Credit],

            CAST(
                'Accumulated depreciation'
                AS VARCHAR(100)
            ) AS [Narration],

            2 AS [SortOrder]

        FROM AccountGrouping AS g
    )

    SELECT
        ROW_NUMBER() OVER
        (
            ORDER BY
                j.BranchCode,
                j.AccountCode,
                j.SortOrder
        ) AS [LineNo],

        j.BranchCode
            AS [BranchCode],

        j.AccountCode
            AS [AccountCode],

        j.AccountCode
            AS [AccountName],

        j.Debit
            AS [Debit],

        j.Credit
            AS [Credit],

        @dep_run_no
            AS [Reference],

        j.Narration
            AS [Narration]

    FROM JournalLines AS j

    ORDER BY
        j.BranchCode,
        j.AccountCode,
        j.SortOrder;


    /* ========================================================
       RESULT SET 4: Asset Validation Messages
       ======================================================== */

    SELECT
        d.asset_id
            AS [AssetId],

        d.asset_code
            AS [AssetCode],

        CASE
            WHEN d.eligibility_status = 'ELIGIBLE'
                THEN 'INFO'

            ELSE 'ERROR'
        END AS [Severity],

        d.eligibility_status
            AS [Code],

        ISNULL(
            d.eligibility_message,
            'Eligible'
        ) AS [Message]

    FROM dbo.a_dep_run_dtl AS d

    WHERE
        d.dep_run_no = @dep_run_no
        AND d.eligibility_status <> 'ELIGIBLE';
END;
GO



/* ============================================================
   PROCEDURE: dbo.usp_Depreciation_GetRunAudit
   PURPOSE  : Retrieve the workflow and audit information
              of a depreciation run
   ============================================================ */

IF OBJECT_ID(
       'dbo.usp_Depreciation_GetRunAudit',
       'P'
   ) IS NULL
BEGIN
    EXEC
    (
        'CREATE PROCEDURE dbo.usp_Depreciation_GetRunAudit
         AS
         BEGIN
             SET NOCOUNT ON;
         END;'
    );
END;
GO


ALTER PROCEDURE dbo.usp_Depreciation_GetRunAudit
(
    @dep_run_no VARCHAR(30)
)
AS
BEGIN
    SET NOCOUNT ON;


    SET @dep_run_no =
        NULLIF(
            LTRIM(RTRIM(@dep_run_no)),
            ''
        );


    SELECT
        h.prepared_by
            AS [PreparedBy],

        h.created_at
            AS [CreatedAt],

        h.submitted_by
            AS [SubmittedBy],

        h.submitted_at
            AS [SubmittedAt],

        h.approved_by
            AS [ApprovedBy],

        h.approved_at
            AS [ApprovedAt],

        h.posted_by
            AS [PostedBy],

        h.posted_at
            AS [PostedAt],

        h.reversed_by
            AS [ReversedBy],

        h.reversed_at
            AS [ReversedAt],

        h.status
            AS [Status]

    FROM dbo.a_dep_run_hdr AS h

    WHERE
        h.dep_run_no = @dep_run_no;
END;
GO



/* ============================================================
   PROCEDURE: dbo.usp_Depreciation_GetAssetHistory
   PURPOSE  : Retrieve depreciation history of one asset
   ============================================================ */

IF OBJECT_ID(
       'dbo.usp_Depreciation_GetAssetHistory',
       'P'
   ) IS NULL
BEGIN
    EXEC
    (
        'CREATE PROCEDURE dbo.usp_Depreciation_GetAssetHistory
         AS
         BEGIN
             SET NOCOUNT ON;
         END;'
    );
END;
GO


ALTER PROCEDURE dbo.usp_Depreciation_GetAssetHistory
(
    @asset_id BIGINT
)
AS
BEGIN
    SET NOCOUNT ON;


    SELECT
        s.asset_id
            AS [AssetId],

        s.dep_run_no
            AS [DepRunNo],

        s.period_key
            AS [PeriodKey],

        h.status
            AS [Status],

        s.current_depreciation
            AS [CurrentDepreciation],

        s.closing_accumulated_depreciation
            AS [ClosingAccumulatedDepreciation],

        s.closing_net_book_value
            AS [ClosingNetBookValue],

        s.journal_no
            AS [JournalNo],

        h.posted_at
            AS [PostedAt]

    FROM dbo.a_dep_schedule AS s

    INNER JOIN dbo.a_dep_run_hdr AS h
        ON h.dep_run_no = s.dep_run_no

    WHERE
        s.asset_id = @asset_id

    ORDER BY
        s.period_key DESC,
        s.schedule_id DESC;
END;
GO