IF OBJECT_ID(N'dbo.usp_Supplier_Query', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_Supplier_Query AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.usp_Supplier_Query
    @Search             VARCHAR(100) = NULL,
    @SupplierGroupCode  VARCHAR(5) = NULL,
    @TermsCode          VARCHAR(4) = NULL,
    @CurrencyCode       VARCHAR(5) = NULL,
    @TaxProfileCode     VARCHAR(15) = NULL,
    @ActiveFlag         VARCHAR(3) = 'Y',
    @Skip               INT = 0,
    @Take               INT = 50,
    @SortField          VARCHAR(40) = 'SupplierName',
    @SortDirection      VARCHAR(4) = 'ASC'
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), '');
    SET @SupplierGroupCode = NULLIF(UPPER(LTRIM(RTRIM(@SupplierGroupCode))), '');
    SET @TermsCode = NULLIF(UPPER(LTRIM(RTRIM(@TermsCode))), '');
    SET @CurrencyCode = NULLIF(UPPER(LTRIM(RTRIM(@CurrencyCode))), '');
    SET @TaxProfileCode = NULLIF(UPPER(LTRIM(RTRIM(@TaxProfileCode))), '');
    SET @ActiveFlag = UPPER(LTRIM(RTRIM(ISNULL(@ActiveFlag, 'Y'))));
    SET @SortField = LTRIM(RTRIM(ISNULL(@SortField, 'SupplierName')));
    SET @SortDirection = UPPER(LTRIM(RTRIM(ISNULL(@SortDirection, 'ASC'))));

    IF @Skip < 0 OR @Take < 1 OR @Take > 250
    BEGIN
        RAISERROR('SUPPLIER_INVALID_PAGING: Skip must be non-negative and Take must be between 1 and 250.', 16, 1);
        RETURN;
    END;

    IF @ActiveFlag NOT IN ('ALL', 'Y', 'N')
    BEGIN
        RAISERROR('SUPPLIER_INVALID_STATUS: ActiveFlag must be ALL, Y, or N.', 16, 1);
        RETURN;
    END;

    IF @SortDirection NOT IN ('ASC', 'DESC')
    BEGIN
        RAISERROR('SUPPLIER_INVALID_SORT: SortDirection must be ASC or DESC.', 16, 1);
        RETURN;
    END;

    IF @SortField NOT IN
    (
        'SupplierCode', 'SupplierName', 'SupplierGroupName', 'ContactPerson',
        'Telephone', 'Email', 'TinNo', 'TermsCode', 'CurrencyCode',
        'TaxProfileCode', 'ActiveFlag', 'ModifiedBy', 'ModifiedDate'
    )
    BEGIN
        RAISERROR('SUPPLIER_INVALID_SORT: The requested sort field is not supported.', 16, 1);
        RETURN;
    END;

    ;WITH Filtered AS
    (
        SELECT
            SupplierCode = LTRIM(RTRIM(s.supp_code)),
            SupplierName = LTRIM(RTRIM(s.supp_name)),
            SupplierGroupCode = LTRIM(RTRIM(s.sup_group_code)),
            SupplierGroupName = LTRIM(RTRIM(ISNULL(g.sup_group_desc, ''))),
            ContactPerson = NULLIF(LTRIM(RTRIM(s.contact)), ''),
            Telephone = NULLIF(LTRIM(RTRIM(s.tel_no)), ''),
            Email = NULLIF(LTRIM(RTRIM(s.email)), ''),
            TinNo = NULLIF(LTRIM(RTRIM(s.tin_no)), ''),
            TermsCode = NULLIF(LTRIM(RTRIM(s.terms)), ''),
            TermsDescription = NULLIF(LTRIM(RTRIM(t.term_description)), ''),
            CurrencyCode = NULLIF(LTRIM(RTRIM(s.curr_code)), ''),
            CurrencyDescription = NULLIF(LTRIM(RTRIM(c.curr_desc)), ''),
            TaxProfileCode = NULLIF(LTRIM(RTRIM(s.chrx_no)), ''),
            TaxProfileDescription = NULLIF(LTRIM(RTRIM(tp.CHRX_DESC)), ''),
            ActiveFlag = s.active_flag,
            ModifiedBy = LTRIM(RTRIM(s.user_id)),
            ModifiedDate = s.date_changed
        FROM dbo.a_suppliers AS s
        LEFT JOIN dbo.a_supp_group AS g
            ON g.sup_group_code = s.sup_group_code
        LEFT JOIN dbo.a_terms AS t
            ON t.term_code = s.terms
        LEFT JOIN dbo.a_currency AS c
            ON c.curr_code = s.curr_code
        LEFT JOIN
        (
            SELECT CHRX_NO, MAX(CHRX_DESC) AS CHRX_DESC
            FROM dbo.AP_CHRX
            GROUP BY CHRX_NO
        ) AS tp
            ON tp.CHRX_NO = s.chrx_no
        WHERE (@ActiveFlag = 'ALL' OR s.active_flag = @ActiveFlag)
          AND (@SupplierGroupCode IS NULL OR s.sup_group_code = @SupplierGroupCode)
          AND (@TermsCode IS NULL OR s.terms = @TermsCode)
          AND (@CurrencyCode IS NULL OR s.curr_code = @CurrencyCode)
          AND (@TaxProfileCode IS NULL OR s.chrx_no = @TaxProfileCode)
          AND
          (
              @Search IS NULL
              OR s.supp_code LIKE '%' + @Search + '%'
              OR s.supp_name LIKE '%' + @Search + '%'
              OR s.tin_no LIKE '%' + @Search + '%'
              OR s.contact LIKE '%' + @Search + '%'
              OR s.email LIKE '%' + @Search + '%'
          )
    ),
    Numbered AS
    (
        SELECT
            SupplierCode,
            SupplierName,
            SupplierGroupCode,
            SupplierGroupName,
            ContactPerson,
            Telephone,
            Email,
            TinNo,
            TermsCode,
            TermsDescription,
            CurrencyCode,
            CurrencyDescription,
            TaxProfileCode,
            TaxProfileDescription,
            ActiveFlag,
            ModifiedBy,
            ModifiedDate,
            TotalCount = COUNT_BIG(*) OVER (),
            RowNumber = ROW_NUMBER() OVER
            (
                ORDER BY
                    CASE WHEN @SortField = 'SupplierCode' AND @SortDirection = 'ASC' THEN SupplierCode END ASC,
                    CASE WHEN @SortField = 'SupplierCode' AND @SortDirection = 'DESC' THEN SupplierCode END DESC,
                    CASE WHEN @SortField = 'SupplierName' AND @SortDirection = 'ASC' THEN SupplierName END ASC,
                    CASE WHEN @SortField = 'SupplierName' AND @SortDirection = 'DESC' THEN SupplierName END DESC,
                    CASE WHEN @SortField = 'SupplierGroupName' AND @SortDirection = 'ASC' THEN SupplierGroupName END ASC,
                    CASE WHEN @SortField = 'SupplierGroupName' AND @SortDirection = 'DESC' THEN SupplierGroupName END DESC,
                    CASE WHEN @SortField = 'ContactPerson' AND @SortDirection = 'ASC' THEN ContactPerson END ASC,
                    CASE WHEN @SortField = 'ContactPerson' AND @SortDirection = 'DESC' THEN ContactPerson END DESC,
                    CASE WHEN @SortField = 'Telephone' AND @SortDirection = 'ASC' THEN Telephone END ASC,
                    CASE WHEN @SortField = 'Telephone' AND @SortDirection = 'DESC' THEN Telephone END DESC,
                    CASE WHEN @SortField = 'Email' AND @SortDirection = 'ASC' THEN Email END ASC,
                    CASE WHEN @SortField = 'Email' AND @SortDirection = 'DESC' THEN Email END DESC,
                    CASE WHEN @SortField = 'TinNo' AND @SortDirection = 'ASC' THEN TinNo END ASC,
                    CASE WHEN @SortField = 'TinNo' AND @SortDirection = 'DESC' THEN TinNo END DESC,
                    CASE WHEN @SortField = 'TermsCode' AND @SortDirection = 'ASC' THEN TermsCode END ASC,
                    CASE WHEN @SortField = 'TermsCode' AND @SortDirection = 'DESC' THEN TermsCode END DESC,
                    CASE WHEN @SortField = 'CurrencyCode' AND @SortDirection = 'ASC' THEN CurrencyCode END ASC,
                    CASE WHEN @SortField = 'CurrencyCode' AND @SortDirection = 'DESC' THEN CurrencyCode END DESC,
                    CASE WHEN @SortField = 'TaxProfileCode' AND @SortDirection = 'ASC' THEN TaxProfileCode END ASC,
                    CASE WHEN @SortField = 'TaxProfileCode' AND @SortDirection = 'DESC' THEN TaxProfileCode END DESC,
                    CASE WHEN @SortField = 'ActiveFlag' AND @SortDirection = 'ASC' THEN ActiveFlag END ASC,
                    CASE WHEN @SortField = 'ActiveFlag' AND @SortDirection = 'DESC' THEN ActiveFlag END DESC,
                    CASE WHEN @SortField = 'ModifiedBy' AND @SortDirection = 'ASC' THEN ModifiedBy END ASC,
                    CASE WHEN @SortField = 'ModifiedBy' AND @SortDirection = 'DESC' THEN ModifiedBy END DESC,
                    CASE WHEN @SortField = 'ModifiedDate' AND @SortDirection = 'ASC' THEN ModifiedDate END ASC,
                    CASE WHEN @SortField = 'ModifiedDate' AND @SortDirection = 'DESC' THEN ModifiedDate END DESC,
                    SupplierCode ASC
            )
        FROM Filtered
    )
    SELECT
        SupplierCode,
        SupplierName,
        SupplierGroupCode,
        SupplierGroupName,
        ContactPerson,
        Telephone,
        Email,
        TinNo,
        TermsCode,
        TermsDescription,
        CurrencyCode,
        CurrencyDescription,
        TaxProfileCode,
        TaxProfileDescription,
        ActiveFlag,
        ModifiedBy,
        ModifiedDate,
        TotalCount
    FROM Numbered
    WHERE RowNumber > CONVERT(BIGINT, @Skip)
      AND RowNumber <= CONVERT(BIGINT, @Skip) + CONVERT(BIGINT, @Take)
    ORDER BY RowNumber;

    SELECT COUNT_BIG(*)
    FROM dbo.a_suppliers AS s
    WHERE (@ActiveFlag = 'ALL' OR s.active_flag = @ActiveFlag)
      AND (@SupplierGroupCode IS NULL OR s.sup_group_code = @SupplierGroupCode)
      AND (@TermsCode IS NULL OR s.terms = @TermsCode)
      AND (@CurrencyCode IS NULL OR s.curr_code = @CurrencyCode)
      AND (@TaxProfileCode IS NULL OR s.chrx_no = @TaxProfileCode)
      AND
      (
          @Search IS NULL
          OR s.supp_code LIKE '%' + @Search + '%'
          OR s.supp_name LIKE '%' + @Search + '%'
          OR s.tin_no LIKE '%' + @Search + '%'
          OR s.contact LIKE '%' + @Search + '%'
          OR s.email LIKE '%' + @Search + '%'
      );
END;
GO
