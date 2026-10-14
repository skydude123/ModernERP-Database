SET NOCOUNT ON;

IF TYPE_ID('dbo.DepreciationAssetIdType') IS NULL
    EXEC('CREATE TYPE dbo.DepreciationAssetIdType AS TABLE(asset_id BIGINT NOT NULL PRIMARY KEY);');
GO

IF TYPE_ID('dbo.DepreciationRunDetailType') IS NULL
    EXEC('CREATE TYPE dbo.DepreciationRunDetailType AS TABLE(line_no INT NOT NULL, asset_id BIGINT NOT NULL, is_selected BIT NOT NULL, PRIMARY KEY(line_no), UNIQUE(asset_id));');
GO
