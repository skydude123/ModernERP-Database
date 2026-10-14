SET NOCOUNT ON;

DECLARE @required TABLE(object_name SYSNAME, object_type CHAR(2));

INSERT @required(object_name, object_type)
VALUES
    ('dbo.a_stock_transfer_hdr', 'U'),
    ('dbo.a_stock_transfer_det', 'U'),
    ('dbo.a_whse', 'U'),
    ('dbo.a_whse_item', 'U'),
    ('dbo.a_item_master', 'U'),
    ('dbo.a_inv_hst', 'U'),
    ('dbo.c_company', 'U'),
    ('dbo.m_fiscal_period', 'U');

SELECT object_name,
       CASE WHEN OBJECT_ID(object_name, object_type) IS NULL THEN 'MISSING' ELSE 'OK' END AS result
FROM @required
ORDER BY object_name;

IF EXISTS (SELECT 1 FROM @required WHERE OBJECT_ID(object_name, object_type) IS NULL)
    RAISERROR('Stock Transfer prerequisites are missing. Review the result set before deployment.', 16, 1);

IF (SELECT COUNT_BIG(*) FROM dbo.c_company) <> 1
    RAISERROR('Stock Transfer control allocation requires exactly one dbo.c_company row in this deployment.', 16, 1);
GO
