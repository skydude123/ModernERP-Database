/*
    Supplier Master permission metadata.
    Role and department grants remain an administrator-controlled deployment
    decision; this script does not hardcode role names.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'MASTER_DATA')
    BEGIN
        INSERT dbo.sec_modules
            (module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES
            ('MASTER_DATA', 'Master Data', NULL, NULL, 93, 1, 1);
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'SUPPLIER_VIEW')
    BEGIN
        INSERT dbo.sec_modules
            (module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES
            ('SUPPLIER_VIEW', 'Supplier Listing', '/master-data/suppliers', 'MASTER_DATA', 94, 1, 1);
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'SUPPLIER_CREATE')
    BEGIN
        INSERT dbo.sec_modules
            (module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES
            ('SUPPLIER_CREATE', 'Supplier Entry', '/master-data/suppliers/new', 'MASTER_DATA', 95, 1, 1);
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'SUPPLIER_EDIT')
    BEGIN
        INSERT dbo.sec_modules
            (module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES
            ('SUPPLIER_EDIT', 'Edit Supplier', '/master-data/suppliers/:supplierCode', 'MASTER_DATA', 96, 0, 1);
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'SUPPLIER_ACTIVATE')
    BEGIN
        INSERT dbo.sec_modules
            (module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES
            ('SUPPLIER_ACTIVATE', 'Activate Supplier', NULL, 'MASTER_DATA', 97, 0, 1);
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'SUPPLIER_DEACTIVATE')
    BEGIN
        INSERT dbo.sec_modules
            (module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES
            ('SUPPLIER_DEACTIVATE', 'Deactivate Supplier', NULL, 'MASTER_DATA', 98, 0, 1);
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    DECLARE @ErrorMessage NVARCHAR(4000);
    SET @ErrorMessage = ERROR_MESSAGE();
    RAISERROR(@ErrorMessage, 16, 1);
END CATCH;
GO
