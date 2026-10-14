SET NOCOUNT ON;
GO


/* ============================================================
   PROCEDURE: dbo.usp_Depreciation_Preview

   PURPOSE:
       1. Validate assets
       2. Calculate depreciation
       3. Generate proposed journal entries
       4. Return validation errors and warnings
   ============================================================ */

IF OBJECT_ID(
       'dbo.usp_Depreciation_Preview',
       'P'
   ) IS NULL
BEGIN
    EXEC
    (
        'CREATE PROCEDURE dbo.usp_Depreciation_Preview
         AS
         BEGIN
             SET NOCOUNT ON;
         END;'
    );
END;
GO


ALTER PROCEDURE dbo.usp_Depreciation_Preview
(
    @period_key          CHAR(6),
    @branch_code         VARCHAR(50) = NULL,
    @asset_category_code VARCHAR(30) = NULL,
    @method_code         VARCHAR(30) = NULL,
    @convention          VARCHAR(20) = 'FULL_MONTH',
    @include_zero        BIT = 0,
    @selected_asset_ids  dbo.DepreciationAssetIdType READONLY
)
AS
BEGIN
    SET NOCOUNT ON;


    /* ========================================================
       1. Clean input parameters
       ======================================================== */

    SET @period_key =
        NULLIF(
            LTRIM(RTRIM(@period_key)),
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
        UPPER(
            NULLIF(
                LTRIM(RTRIM(@method_code)),
                ''
            )
        );

    SET @convention =
        UPPER(
            ISNULL(
                NULLIF(
                    LTRIM(RTRIM(@convention)),
                    ''
                ),
                'FULL_MONTH'
            )
        );

    SET @include_zero =
        ISNULL(
            @include_zero,
            0
        );


    /* ========================================================
       2. Validate period format
       ======================================================== */

    IF
    (
        @period_key IS NULL
        OR LEN(@period_key) <> 6
        OR @period_key LIKE '%[^0-9]%'
    )
    BEGIN
        RAISERROR(
            'Period must use YYYYMM format.',
            16,
            1
        );

        RETURN;
    END;


    /* ========================================================
       3. Validate depreciation convention
       ======================================================== */

    IF @convention NOT IN
    (
        'FULL_MONTH',
        'NEXT_MONTH'
    )
    BEGIN
        RAISERROR(
            'Unsupported depreciation convention.',
            16,
            1
        );

        RETURN;
    END;


    /* ========================================================
       4. Declare period variables

       Compatible replacement for:
           TRY_CONVERT
           DATEFROMPARTS
           EOMONTH
       ======================================================== */

    DECLARE @period_year  INT;
    DECLARE @period_month INT;
    DECLARE @period_start DATE;
    DECLARE @period_end   DATE;
    DECLARE @has_accounts BIT;


    SET @period_year =
        CONVERT(
            INT,
            LEFT(@period_key, 4)
        );

    SET @period_month =
        CONVERT(
            INT,
            RIGHT(@period_key, 2)
        );


    /* Validate year */

    IF @period_year NOT BETWEEN 1 AND 9999
    BEGIN
        RAISERROR(
            'The year portion of the period is invalid.',
            16,
            1
        );

        RETURN;
    END;


    /* Validate month */

    IF @period_month NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR(
            'The month portion of the period must be between 01 and 12.',
            16,
            1
        );

        RETURN;
    END;


    /* First day of the selected period */

    SET @period_start =
        CONVERT(
            DATE,
            @period_key + '01',
            112
        );


    /* Last day of the selected period */

    SET @period_end =
        DATEADD(
            DAY,
            -1,
            DATEADD(
                MONTH,
                1,
                @period_start
            )
        );


    /* ========================================================
       5. Check if active GL account mappings exist
       ======================================================== */

    IF EXISTS
    (
        SELECT 1
        FROM dbo.a_asset_gl_account AS gl_account
        WHERE gl_account.active_flag = 'Y'
    )
    BEGIN
        SET @has_accounts = 1;
    END;
    ELSE
    BEGIN
        SET @has_accounts = 0;
    END;


    /* ========================================================
       6. Read source asset data
       ======================================================== */

    ;WITH SourceData AS
    (
        SELECT
            asset.asset_master_id
                AS [asset_id],

            asset.asset_no
                AS [asset_code],

            asset.description
                AS [asset_description],

            asset.asset_category_code
                AS [asset_category_code],

            asset.branch_name
                AS [branch_code],

            asset.asset_location_code
                AS [location_code],

            asset.custodian_code
                AS [custodian_code],

            CAST(
                asset.created_at AS DATE
            ) AS [acquisition_date],

            asset.in_service_date
                AS [in_service_date],

            asset.depreciation_start_date
                AS [depreciation_start_date],

            CASE
                WHEN asset.depreciation_method_code IN
                (
                    'NONE',
                    'NONDEP'
                )
                    THEN 'NONDEP'

                ELSE asset.depreciation_method_code
            END AS [method_code],

            ISNULL(
                asset.acquisition_cost,
                0
            ) AS [acquisition_cost],

            ISNULL(
                asset.residual_value,
                0
            ) AS [residual_value],

            asset.useful_life_months
                AS [useful_life_months],

            asset.asset_cost_account
                AS [asset_cost_account],

            asset.depreciation_expense_account
                AS [depreciation_expense_account],

            asset.accumulated_depreciation_account
                AS [accumulated_depreciation_account],

            asset.status
                AS [status],


            /* Opening accumulated depreciation */

            ISNULL
            (
                (
                    SELECT
                        SUM(schedule.current_depreciation)

                    FROM dbo.a_dep_schedule AS schedule

                    WHERE
                        schedule.asset_id =
                            asset.asset_master_id

                        AND schedule.is_active = 1
                ),
                0
            ) AS [opening_acc],


            /* Number of previously depreciated periods */

            ISNULL
            (
                (
                    SELECT
                        COUNT(*)

                    FROM dbo.a_dep_schedule AS schedule

                    WHERE
                        schedule.asset_id =
                            asset.asset_master_id

                        AND schedule.is_active = 1

                        AND schedule.current_depreciation > 0
                ),
                0
            ) AS [periods_before],


            /* Asset selection status */

            CASE
                WHEN EXISTS
                (
                    SELECT 1

                    FROM @selected_asset_ids AS selected

                    WHERE
                        selected.asset_id =
                            asset.asset_master_id
                )
                OR NOT EXISTS
                (
                    SELECT 1
                    FROM @selected_asset_ids
                )
                    THEN CAST(1 AS BIT)

                ELSE CAST(0 AS BIT)
            END AS [is_selected],


            /* Check duplicate depreciation period */

            CASE
                WHEN EXISTS
                (
                    SELECT 1

                    FROM dbo.a_dep_schedule AS schedule

                    WHERE
                        schedule.asset_id =
                            asset.asset_master_id

                        AND schedule.period_key =
                            @period_key

                        AND schedule.is_active = 1
                )
                    THEN 1

                ELSE 0
            END AS [duplicate_period]

        FROM dbo.a_asset_master AS asset

        WHERE
            (
                @branch_code IS NULL
                OR asset.branch_name = @branch_code
            )

            AND
            (
                @asset_category_code IS NULL
                OR asset.asset_category_code =
                    @asset_category_code
            )

            AND
            (
                @method_code IS NULL

                OR
                (
                    @method_code = 'NONDEP'

                    AND asset.depreciation_method_code IN
                    (
                        'NONE',
                        'NONDEP'
                    )
                )

                OR
                (
                    @method_code <> 'NONDEP'

                    AND asset.depreciation_method_code =
                        @method_code
                )
            )
    ),


    /* ========================================================
       7. Validate every asset
       ======================================================== */

    ValidatedData AS
    (
        SELECT
            source.*,

            source.acquisition_cost -
            source.opening_acc
                AS [opening_nbv],

            CASE
                WHEN source.status <> 'ACTIVE'
                    THEN
                        'Asset is not active.'

                WHEN source.acquisition_cost <= 0
                    THEN
                        'Acquisition cost must be positive.'

                WHEN
                (
                    source.residual_value < 0
                    OR source.residual_value >
                       source.acquisition_cost
                )
                    THEN
                        'Residual value is outside the valid range.'

                WHEN source.method_code NOT IN
                (
                    'SL',
                    'DDB',
                    'NONDEP'
                )
                    THEN
                        'Unsupported depreciation method.'

                WHEN
                (
                    source.method_code <> 'NONDEP'
                    AND ISNULL(
                            source.useful_life_months,
                            0
                        ) <= 0
                )
                    THEN
                        'Useful life must be greater than zero.'

                WHEN source.depreciation_start_date IS NULL
                    THEN
                        'Depreciation start date is required.'

                WHEN
                (
                    @convention = 'FULL_MONTH'
                    AND source.depreciation_start_date >
                        @period_end
                )
                    THEN
                        'Asset has not reached its depreciation start date.'

                WHEN
                (
                    @convention = 'NEXT_MONTH'

                    AND DATEADD
                    (
                        MONTH,
                        1,

                        DATEADD
                        (
                            DAY,
                            1 - DAY(
                                source.depreciation_start_date
                            ),
                            source.depreciation_start_date
                        )
                    ) > @period_start
                )
                    THEN
                        'Asset is not eligible until the next month.'

                WHEN source.duplicate_period = 1
                    THEN
                        'An active schedule already exists for this asset and period.'

                WHEN
                (
                    source.opening_acc >
                    source.acquisition_cost -
                    source.residual_value
                )
                    THEN
                        'Opening accumulated depreciation exceeds depreciable cost.'

                WHEN
                (
                    source.method_code <> 'NONDEP'

                    AND source.acquisition_cost -
                        source.opening_acc <=
                        source.residual_value
                )
                    THEN
                        'Asset is fully depreciated.'

                WHEN
                (
                    source.method_code <> 'NONDEP'

                    AND
                    (
                        NULLIF
                        (
                            LTRIM(
                                RTRIM(
                                    source.depreciation_expense_account
                                )
                            ),
                            ''
                        ) IS NULL

                        OR NULLIF
                        (
                            LTRIM(
                                RTRIM(
                                    source.accumulated_depreciation_account
                                )
                            ),
                            ''
                        ) IS NULL
                    )
                )
                    THEN
                        'Depreciation posting accounts are required.'

                WHEN
                (
                    source.method_code <> 'NONDEP'
                    AND @has_accounts = 1

                    AND NOT EXISTS
                    (
                        SELECT 1

                        FROM dbo.a_asset_gl_account AS gl_account

                        WHERE
                            gl_account.account_code =
                                source.depreciation_expense_account

                            AND gl_account.active_flag = 'Y'
                    )
                )
                    THEN
                        'Depreciation expense account is inactive or non-posting.'

                WHEN
                (
                    source.method_code <> 'NONDEP'
                    AND @has_accounts = 1

                    AND NOT EXISTS
                    (
                        SELECT 1

                        FROM dbo.a_asset_gl_account AS gl_account

                        WHERE
                            gl_account.account_code =
                                source.accumulated_depreciation_account

                            AND gl_account.active_flag = 'Y'
                    )
                )
                    THEN
                        'Accumulated depreciation account is inactive or non-posting.'

                ELSE NULL
            END AS [validation_message]

        FROM SourceData AS source
    ),


    /* ========================================================
       8. Calculate depreciation rate and raw amount
       ======================================================== */

    CalculatedData AS
    (
        SELECT
            validated.*,

            CAST
            (
                CASE
                    WHEN
                    (
                        validated.method_code = 'SL'
                        AND ISNULL(
                                validated.useful_life_months,
                                0
                            ) > 0
                    )
                        THEN
                            1.0 /
                            validated.useful_life_months

                    WHEN
                    (
                        validated.method_code = 'DDB'
                        AND ISNULL(
                                validated.useful_life_months,
                                0
                            ) > 0
                    )
                        THEN
                            2.0 /
                            validated.useful_life_months

                    ELSE 0
                END

                AS DECIMAL(19, 8)
            ) AS [depreciation_rate],

            CAST
            (
                CASE
                    WHEN
                    (
                        validated.validation_message IS NOT NULL
                        OR validated.method_code = 'NONDEP'
                    )
                        THEN 0

                    WHEN validated.method_code = 'SL'
                        THEN ROUND
                        (
                            (
                                validated.acquisition_cost -
                                validated.residual_value
                            )
                            /
                            NULLIF(
                                validated.useful_life_months,
                                0
                            ),
                            2
                        )

                    WHEN validated.method_code = 'DDB'
                        THEN ROUND
                        (
                            validated.opening_nbv *
                            2.0
                            /
                            NULLIF(
                                validated.useful_life_months,
                                0
                            ),
                            2
                        )

                    ELSE 0
                END

                AS DECIMAL(19, 4)
            ) AS [raw_depreciation]

        FROM ValidatedData AS validated
    )


    /* ========================================================
       9. Store calculations in temporary table
       ======================================================== */

    SELECT
        ROW_NUMBER() OVER
        (
            ORDER BY
                calculated.asset_code,
                calculated.asset_id
        ) AS [line_no],

        calculated.*,

        CAST
        (
            CASE
                WHEN calculated.validation_message IS NOT NULL
                    THEN 0

                WHEN calculated.method_code = 'NONDEP'
                    THEN 0

                WHEN calculated.raw_depreciation <= 0
                    THEN 0

                WHEN
                (
                    calculated.opening_nbv <=
                    calculated.residual_value
                )
                    THEN 0

                WHEN
                (
                    calculated.raw_depreciation >
                    calculated.opening_nbv -
                    calculated.residual_value
                )
                    THEN
                        calculated.opening_nbv -
                        calculated.residual_value

                ELSE calculated.raw_depreciation
            END

            AS DECIMAL(19, 4)
        ) AS [current_depreciation]

    INTO #CalculatedAssets

    FROM CalculatedData AS calculated

    WHERE
        @include_zero = 1
        OR calculated.method_code <> 'NONDEP';


    /* ========================================================
       RESULT SET 1: Asset depreciation calculations
       ======================================================== */

    SELECT
        calculated.line_no
            AS [LineNo],

        calculated.asset_id
            AS [AssetId],

        calculated.asset_code
            AS [AssetCode],

        calculated.asset_description
            AS [AssetDescription],

        calculated.asset_category_code
            AS [AssetCategoryCode],

        calculated.branch_code
            AS [BranchCode],

        calculated.location_code
            AS [LocationCode],

        calculated.custodian_code
            AS [CustodianCode],

        calculated.acquisition_date
            AS [AcquisitionDate],

        calculated.in_service_date
            AS [InServiceDate],

        calculated.depreciation_start_date
            AS [DepreciationStartDate],

        calculated.method_code
            AS [MethodCode],

        @convention
            AS [Convention],

        calculated.acquisition_cost
            AS [AcquisitionCost],

        calculated.residual_value
            AS [ResidualValue],

        calculated.useful_life_months
            AS [UsefulLifeMonths],

        calculated.periods_before
            AS [PeriodsDepreciatedBefore],

        calculated.opening_acc
            AS [OpeningAccumulatedDepreciation],

        calculated.opening_nbv
            AS [OpeningNetBookValue],

        calculated.depreciation_rate
            AS [DepreciationRate],

        calculated.current_depreciation
            AS [CurrentDepreciation],

        calculated.opening_acc +
        calculated.current_depreciation
            AS [ClosingAccumulatedDepreciation],

        calculated.opening_nbv -
        calculated.current_depreciation
            AS [ClosingNetBookValue],

        calculated.asset_cost_account
            AS [AssetCostAccount],

        calculated.depreciation_expense_account
            AS [DepreciationExpenseAccount],

        calculated.accumulated_depreciation_account
            AS [AccumulatedDepreciationAccount],

        calculated.is_selected
            AS [IsSelected],

        CASE
            WHEN calculated.validation_message IS NULL
                THEN 'ELIGIBLE'

            ELSE 'INELIGIBLE'
        END AS [EligibilityStatus],

        calculated.validation_message
            AS [EligibilityMessage]

    FROM #CalculatedAssets AS calculated

    ORDER BY
        calculated.line_no;


    /* ========================================================
       RESULT SET 2: Proposed journal entries
       ======================================================== */

    ;WITH AccountGrouping AS
    (
        SELECT
            calculated.branch_code
                AS [BranchCode],

            calculated.depreciation_expense_account
                AS [ExpenseAccount],

            calculated.accumulated_depreciation_account
                AS [AccumulatedAccount],

            SUM(
                calculated.current_depreciation
            ) AS [Amount]

        FROM #CalculatedAssets AS calculated

        WHERE
            calculated.is_selected = 1
            AND calculated.validation_message IS NULL
            AND calculated.current_depreciation > 0

        GROUP BY
            calculated.branch_code,
            calculated.depreciation_expense_account,
            calculated.accumulated_depreciation_account
    ),
    JournalLines AS
    (
        /* Debit: Depreciation expense */

        SELECT
            grouped.BranchCode
                AS [BranchCode],

            grouped.ExpenseAccount
                AS [AccountCode],

            grouped.Amount
                AS [Debit],

            CAST(
                0 AS DECIMAL(19, 4)
            ) AS [Credit],

            CAST(
                'Depreciation expense'
                AS VARCHAR(100)
            ) AS [Narration],

            1 AS [SortOrder]

        FROM AccountGrouping AS grouped


        UNION ALL


        /* Credit: Accumulated depreciation */

        SELECT
            grouped.BranchCode
                AS [BranchCode],

            grouped.AccumulatedAccount
                AS [AccountCode],

            CAST(
                0 AS DECIMAL(19, 4)
            ) AS [Debit],

            grouped.Amount
                AS [Credit],

            CAST(
                'Accumulated depreciation'
                AS VARCHAR(100)
            ) AS [Narration],

            2 AS [SortOrder]

        FROM AccountGrouping AS grouped
    )

    SELECT
        ROW_NUMBER() OVER
        (
            ORDER BY
                journal.BranchCode,
                journal.AccountCode,
                journal.SortOrder
        ) AS [LineNo],

        journal.BranchCode
            AS [BranchCode],

        journal.AccountCode
            AS [AccountCode],

        journal.AccountCode
            AS [AccountName],

        journal.Debit
            AS [Debit],

        journal.Credit
            AS [Credit],

        @period_key
            AS [Reference],

        journal.Narration
            AS [Narration]

    FROM JournalLines AS journal

    ORDER BY
        journal.BranchCode,
        journal.AccountCode,
        journal.SortOrder;


    /* ========================================================
       RESULT SET 3: Validation errors and warnings
       ======================================================== */

    SELECT
        calculated.asset_id
            AS [AssetId],

        calculated.asset_code
            AS [AssetCode],

        'ERROR'
            AS [Severity],

        'ASSET_INELIGIBLE'
            AS [Code],

        calculated.validation_message
            AS [Message]

    FROM #CalculatedAssets AS calculated

    WHERE
        calculated.validation_message IS NOT NULL


    UNION ALL


    SELECT
        calculated.asset_id
            AS [AssetId],

        calculated.asset_code
            AS [AssetCode],

        'WARNING'
            AS [Severity],

        'NON_DEPRECIATING'
            AS [Code],

        'Non-depreciating asset creates no GL line.'
            AS [Message]

    FROM #CalculatedAssets AS calculated

    WHERE
        calculated.validation_message IS NULL
        AND calculated.method_code = 'NONDEP';

END;
GO



/* ============================================================
   PROCEDURE: dbo.usp_Depreciation_GetEligibleAssets

   PURPOSE:
       Retrieve assets eligible for the selected
       depreciation period.
   ============================================================ */

IF OBJECT_ID(
       'dbo.usp_Depreciation_GetEligibleAssets',
       'P'
   ) IS NULL
BEGIN
    EXEC
    (
        'CREATE PROCEDURE dbo.usp_Depreciation_GetEligibleAssets
         AS
         BEGIN
             SET NOCOUNT ON;
         END;'
    );
END;
GO


ALTER PROCEDURE dbo.usp_Depreciation_GetEligibleAssets
(
    @period_key          CHAR(6),
    @branch_code         VARCHAR(50) = NULL,
    @asset_category_code VARCHAR(30) = NULL,
    @method_code         VARCHAR(30) = NULL,
    @convention          VARCHAR(20) = 'FULL_MONTH',
    @include_zero        BIT = 0,
    @selected_asset_ids  dbo.DepreciationAssetIdType READONLY
)
AS
BEGIN
    SET NOCOUNT ON;


    /* ========================================================
       1. Clean parameters
       ======================================================== */

    SET @period_key =
        NULLIF(
            LTRIM(RTRIM(@period_key)),
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
        UPPER(
            NULLIF(
                LTRIM(RTRIM(@method_code)),
                ''
            )
        );

    SET @convention =
        UPPER(
            ISNULL(
                NULLIF(
                    LTRIM(RTRIM(@convention)),
                    ''
                ),
                'FULL_MONTH'
            )
        );

    SET @include_zero =
        ISNULL(
            @include_zero,
            0
        );


    /* ========================================================
       2. Validate period format
       ======================================================== */

    IF
    (
        @period_key IS NULL
        OR LEN(@period_key) <> 6
        OR @period_key LIKE '%[^0-9]%'
    )
    BEGIN
        RAISERROR(
            'Period must use YYYYMM format.',
            16,
            1
        );

        RETURN;
    END;


    /* ========================================================
       3. Validate depreciation convention
       ======================================================== */

    IF @convention NOT IN
    (
        'FULL_MONTH',
        'NEXT_MONTH'
    )
    BEGIN
        RAISERROR(
            'Unsupported depreciation convention.',
            16,
            1
        );

        RETURN;
    END;


    /* ========================================================
       4. Declare and resolve period dates
       ======================================================== */

    DECLARE @period_year  INT;
    DECLARE @period_month INT;
    DECLARE @period_start DATE;
    DECLARE @period_end   DATE;


    SET @period_year =
        CONVERT(
            INT,
            LEFT(@period_key, 4)
        );

    SET @period_month =
        CONVERT(
            INT,
            RIGHT(@period_key, 2)
        );


    IF @period_year NOT BETWEEN 1 AND 9999
    BEGIN
        RAISERROR(
            'The year portion of the period is invalid.',
            16,
            1
        );

        RETURN;
    END;


    IF @period_month NOT BETWEEN 1 AND 12
    BEGIN
        RAISERROR(
            'The month portion of the period must be between 01 and 12.',
            16,
            1
        );

        RETURN;
    END;


    SET @period_start =
        CONVERT(
            DATE,
            @period_key + '01',
            112
        );


    SET @period_end =
        DATEADD(
            DAY,
            -1,
            DATEADD(
                MONTH,
                1,
                @period_start
            )
        );


    /* ========================================================
       5. Return eligible assets
       ======================================================== */

    SELECT
        ROW_NUMBER() OVER
        (
            ORDER BY
                asset.asset_no,
                asset.asset_master_id
        ) AS [LineNo],

        asset.asset_master_id
            AS [AssetId],

        asset.asset_no
            AS [AssetCode],

        asset.description
            AS [AssetDescription],

        asset.asset_category_code
            AS [AssetCategoryCode],

        asset.branch_name
            AS [BranchCode],

        asset.asset_location_code
            AS [LocationCode],

        asset.custodian_code
            AS [CustodianCode],

        CAST(
            asset.created_at AS DATE
        ) AS [AcquisitionDate],

        asset.in_service_date
            AS [InServiceDate],

        asset.depreciation_start_date
            AS [DepreciationStartDate],

        CASE
            WHEN asset.depreciation_method_code IN
            (
                'NONE',
                'NONDEP'
            )
                THEN 'NONDEP'

            ELSE asset.depreciation_method_code
        END AS [MethodCode],

        @convention
            AS [Convention],

        asset.acquisition_cost
            AS [AcquisitionCost],

        asset.residual_value
            AS [ResidualValue],

        asset.useful_life_months
            AS [UsefulLifeMonths],

        0
            AS [PeriodsDepreciatedBefore],

        CAST(
            0 AS DECIMAL(19, 4)
        ) AS [OpeningAccumulatedDepreciation],

        asset.acquisition_cost
            AS [OpeningNetBookValue],

        CAST(
            0 AS DECIMAL(19, 8)
        ) AS [DepreciationRate],

        CAST(
            0 AS DECIMAL(19, 4)
        ) AS [CurrentDepreciation],

        CAST(
            0 AS DECIMAL(19, 4)
        ) AS [ClosingAccumulatedDepreciation],

        asset.acquisition_cost
            AS [ClosingNetBookValue],

        asset.asset_cost_account
            AS [AssetCostAccount],

        asset.depreciation_expense_account
            AS [DepreciationExpenseAccount],

        asset.accumulated_depreciation_account
            AS [AccumulatedDepreciationAccount],

        CASE
            WHEN EXISTS
            (
                SELECT 1

                FROM @selected_asset_ids AS selected

                WHERE
                    selected.asset_id =
                        asset.asset_master_id
            )
            OR NOT EXISTS
            (
                SELECT 1
                FROM @selected_asset_ids
            )
                THEN CAST(1 AS BIT)

            ELSE CAST(0 AS BIT)
        END AS [IsSelected],

        'ELIGIBLE'
            AS [EligibilityStatus],

        CAST(
            NULL AS NVARCHAR(500)
        ) AS [EligibilityMessage]

    FROM dbo.a_asset_master AS asset

    WHERE
        asset.status = 'ACTIVE'

        AND asset.acquisition_cost > 0

        AND ISNULL(
                asset.residual_value,
                0
            )
            BETWEEN 0
            AND asset.acquisition_cost

        AND
        (
            asset.depreciation_method_code IN
            (
                'SL',
                'DDB'
            )

            OR
            (
                @include_zero = 1

                AND asset.depreciation_method_code IN
                (
                    'NONE',
                    'NONDEP'
                )
            )
        )

        AND
        (
            asset.depreciation_method_code IN
            (
                'NONE',
                'NONDEP'
            )

            OR ISNULL(
                   asset.useful_life_months,
                   0
               ) > 0
        )

        AND asset.depreciation_start_date IS NOT NULL

        AND
        (
            (
                @convention = 'FULL_MONTH'

                AND asset.depreciation_start_date <=
                    @period_end
            )

            OR
            (
                @convention = 'NEXT_MONTH'

                AND DATEADD
                (
                    MONTH,
                    1,

                    DATEADD
                    (
                        DAY,
                        1 - DAY(
                            asset.depreciation_start_date
                        ),
                        asset.depreciation_start_date
                    )
                ) <= @period_start
            )
        )

        AND
        (
            @branch_code IS NULL
            OR asset.branch_name = @branch_code
        )

        AND
        (
            @asset_category_code IS NULL
            OR asset.asset_category_code =
                @asset_category_code
        )

        AND
        (
            @method_code IS NULL

            OR
            (
                @method_code = 'NONDEP'

                AND asset.depreciation_method_code IN
                (
                    'NONE',
                    'NONDEP'
                )
            )

            OR
            (
                @method_code <> 'NONDEP'

                AND asset.depreciation_method_code =
                    @method_code
            )
        )

        AND NOT EXISTS
        (
            SELECT 1

            FROM dbo.a_dep_schedule AS schedule

            WHERE
                schedule.asset_id =
                    asset.asset_master_id

                AND schedule.period_key =
                    @period_key

                AND schedule.is_active = 1
        )

    ORDER BY
        asset.asset_no,
        asset.asset_master_id;

END;
GO