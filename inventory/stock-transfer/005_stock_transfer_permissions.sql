SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'INVENTORY_TRANSFER_VIEW')
        INSERT dbo.sec_modules(module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES('INVENTORY_TRANSFER_VIEW', 'Stock Transfer', '/stock-transfers', 'INVENTORY', 920, 1, 1);

    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'INVENTORY_TRANSFER_EDIT')
        INSERT dbo.sec_modules(module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES('INVENTORY_TRANSFER_EDIT', 'Edit Stock Transfer', NULL, 'INVENTORY_TRANSFER_VIEW', 921, 0, 1);

    IF NOT EXISTS (SELECT 1 FROM dbo.sec_modules WHERE module_code = 'INVENTORY_TRANSFER_POST')
        INSERT dbo.sec_modules(module_code, module_name, route_path, parent_module_code, sort_order, is_menu, is_active)
        VALUES('INVENTORY_TRANSFER_POST', 'Post Stock Transfer', NULL, 'INVENTORY_TRANSFER_VIEW', 922, 0, 1);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
