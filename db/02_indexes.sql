/*
    sql-server-inventory-demo
    02_indexes.sql - Nonclustered, covering and filtered indexes

    Idempotent: drops each index if present, then recreates it.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE InventoryDemo;
GO

/* Nonclustered index on the FK column (helps joins by category) */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Products_CategoryId' AND object_id = OBJECT_ID('dbo.Products'))
    DROP INDEX IX_Products_CategoryId ON dbo.Products;
GO
CREATE NONCLUSTERED INDEX IX_Products_CategoryId
    ON dbo.Products (CategoryId)
    INCLUDE (Sku, Name, UnitPrice);
GO

/* Filtered index: only active products (small, hot subset) */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Products_Active_Name' AND object_id = OBJECT_ID('dbo.Products'))
    DROP INDEX IX_Products_Active_Name ON dbo.Products;
GO
CREATE NONCLUSTERED INDEX IX_Products_Active_Name
    ON dbo.Products (Name)
    WHERE IsActive = 1;
GO

/* Covering index for the movement history / running-total queries */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_StockMovements_Product_MovedAt' AND object_id = OBJECT_ID('dbo.StockMovements'))
    DROP INDEX IX_StockMovements_Product_MovedAt ON dbo.StockMovements;
GO
CREATE NONCLUSTERED INDEX IX_StockMovements_Product_MovedAt
    ON dbo.StockMovements (ProductId, MovedAt DESC)
    INCLUDE (WarehouseId, QtyChange, MovementType);
GO

/* Lookup by movement type + date (reporting) */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_StockMovements_Type_MovedAt' AND object_id = OBJECT_ID('dbo.StockMovements'))
    DROP INDEX IX_StockMovements_Type_MovedAt ON dbo.StockMovements;
GO
CREATE NONCLUSTERED INDEX IX_StockMovements_Type_MovedAt
    ON dbo.StockMovements (MovementType, MovedAt DESC)
    INCLUDE (ProductId, WarehouseId, QtyChange);
GO

/* Purchase order workflow lookups */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PurchaseOrders_Status' AND object_id = OBJECT_ID('dbo.PurchaseOrders'))
    DROP INDEX IX_PurchaseOrders_Status ON dbo.PurchaseOrders;
GO
CREATE NONCLUSTERED INDEX IX_PurchaseOrders_Status
    ON dbo.PurchaseOrders (Status)
    INCLUDE (PoNumber, SupplierId, CreatedAt);
GO

PRINT '02_indexes.sql OK';
GO
