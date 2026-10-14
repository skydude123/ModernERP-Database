SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 IF NOT EXISTS(SELECT 1 FROM dbo.sec_modules WHERE module_code='INVENTORY_ISSUE_VIEW')
  INSERT dbo.sec_modules(module_code,module_name,route_path,parent_module_code,sort_order,is_menu,is_active)
  VALUES('INVENTORY_ISSUE_VIEW','Material Issuance','/inventory/material-issuance','INVENTORY',910,1,1);
 IF NOT EXISTS(SELECT 1 FROM dbo.sec_modules WHERE module_code='INVENTORY_ISSUE_EDIT')
  INSERT dbo.sec_modules(module_code,module_name,route_path,parent_module_code,sort_order,is_menu,is_active)
  VALUES('INVENTORY_ISSUE_EDIT','Edit Material Issuance',NULL,'INVENTORY_ISSUE_VIEW',911,0,1);
 IF NOT EXISTS(SELECT 1 FROM dbo.sec_modules WHERE module_code='INVENTORY_ISSUE_POST')
  INSERT dbo.sec_modules(module_code,module_name,route_path,parent_module_code,sort_order,is_menu,is_active)
  VALUES('INVENTORY_ISSUE_POST','Post Material Issuance',NULL,'INVENTORY_ISSUE_VIEW',912,0,1);
 IF NOT EXISTS(SELECT 1 FROM dbo.sec_modules WHERE module_code='INVENTORY_ISSUE_REVERSE')
  INSERT dbo.sec_modules(module_code,module_name,route_path,parent_module_code,sort_order,is_menu,is_active)
  VALUES('INVENTORY_ISSUE_REVERSE','Reverse Material Issuance',NULL,'INVENTORY_ISSUE_VIEW',913,0,1);
 IF NOT EXISTS(SELECT 1 FROM dbo.sec_modules WHERE module_code='INVENTORY_ISSUE_DIRECT')
  INSERT dbo.sec_modules(module_code,module_name,route_path,parent_module_code,sort_order,is_menu,is_active)
  VALUES('INVENTORY_ISSUE_DIRECT','Direct Material Issuance',NULL,'INVENTORY_ISSUE_VIEW',914,0,1);
 COMMIT;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
GO
