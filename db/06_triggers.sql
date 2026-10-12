/*
    sql-server-inventory-demo
    06_triggers.sql - Audit trigger

    Writes one AuditLog row per INSERT / UPDATE / DELETE on Products,
    including a JSON snapshot of the affected rows.

    Idempotent: CREATE OR ALTER TRIGGER.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE InventoryDemo;
GO

CREATE OR ALTER TRIGGER dbo.trg_Products_Audit
ON dbo.Products
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @action NVARCHAR(10) =
        CASE
            WHEN EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted) THEN N'UPDATE'
            WHEN EXISTS (SELECT 1 FROM inserted) THEN N'INSERT'
            ELSE N'DELETE'
        END;

    INSERT INTO dbo.AuditLog (TableName, Action, KeyValue, ChangedBy, Payload)
    SELECT
        N'Products',
        @action,
        CAST(COALESCE(i.ProductId, d.ProductId) AS NVARCHAR(20)),
        SUSER_SNAME(),
        (
            SELECT
                COALESCE(i.ProductId, d.ProductId) AS ProductId,
                COALESCE(i.Sku, d.Sku)             AS Sku,
                COALESCE(i.Name, d.Name)           AS Name,
                COALESCE(i.UnitPrice, d.UnitPrice) AS UnitPrice,
                COALESCE(i.IsActive, d.IsActive)   AS IsActive
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )
    FROM inserted AS i
    FULL OUTER JOIN deleted AS d ON i.ProductId = d.ProductId;
END;
GO

PRINT '06_triggers.sql OK';
GO
