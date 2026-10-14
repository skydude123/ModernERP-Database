SET NOCOUNT ON;

DECLARE @required TABLE(object_name SYSNAME, object_type CHAR(2));
INSERT @required VALUES
('dbo.a_issue_hdr','U'),('dbo.a_issue_det','U'),('dbo.a_rr_lot','U'),
('dbo.a_whse_item','U'),('dbo.a_inv_hst','U'),('dbo.a_suppliers','U'),
('dbo.TWB_ChaAcct','U'),('dbo.TWB_JRNLhdr','U'),('dbo.twb_rawmats','U');

SELECT object_name,
       CASE WHEN OBJECT_ID(object_name, object_type) IS NULL THEN 'MISSING' ELSE 'OK' END AS result
FROM @required
ORDER BY object_name;

IF EXISTS (SELECT 1 FROM @required WHERE OBJECT_ID(object_name, object_type) IS NULL)
    RAISERROR('Material Issuance prerequisites are missing. Review the result set before deployment.',16,1);

IF OBJECT_ID('dbo.TWB_JRNLdtl','U') IS NULL
    PRINT 'INFO: dbo.TWB_JRNLdtl is absent; the verified legacy equivalent dbo.twb_rawmats is used.';
GO
