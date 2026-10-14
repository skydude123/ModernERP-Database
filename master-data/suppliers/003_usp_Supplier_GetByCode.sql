IF OBJECT_ID(N'dbo.usp_Supplier_GetByCode', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.usp_Supplier_GetByCode AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.usp_Supplier_GetByCode
    @SupplierCode VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SET @SupplierCode = UPPER(LTRIM(RTRIM(@SupplierCode)));

    SELECT
        SupplierCode = LTRIM(RTRIM(s.supp_code)),
        SupplierName = LTRIM(RTRIM(s.supp_name)),
        SupplierGroupCode = LTRIM(RTRIM(s.sup_group_code)),
        SupplierGroupName = LTRIM(RTRIM(ISNULL(g.sup_group_desc, ''))),
        AddressLine1 = NULLIF(LTRIM(RTRIM(s.address_1)), ''),
        AddressLine2 = NULLIF(LTRIM(RTRIM(s.address_2)), ''),
        AddressLine3 = NULLIF(LTRIM(RTRIM(s.address_3)), ''),
        ContactPerson = NULLIF(LTRIM(RTRIM(s.contact)), ''),
        PositionTitle = NULLIF(LTRIM(RTRIM(s.position_title)), ''),
        Telephone = NULLIF(LTRIM(RTRIM(s.tel_no)), ''),
        Fax = NULLIF(LTRIM(RTRIM(s.fax_no)), ''),
        Email = NULLIF(LTRIM(RTRIM(s.email)), ''),
        TinNo = NULLIF(LTRIM(RTRIM(s.tin_no)), ''),
        TermsCode = NULLIF(LTRIM(RTRIM(s.terms)), ''),
        TermsDescription = NULLIF(LTRIM(RTRIM(t.term_description)), ''),
        CurrencyCode = NULLIF(LTRIM(RTRIM(s.curr_code)), ''),
        CurrencyDescription = NULLIF(LTRIM(RTRIM(c.curr_desc)), ''),
        Website = NULLIF(LTRIM(RTRIM(s.website_add)), ''),
        Specialties = NULLIF(LTRIM(RTRIM(s.specialties)), ''),
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
    WHERE s.supp_code = @SupplierCode;
END;
GO
