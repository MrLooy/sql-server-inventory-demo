/*
    sql-server-inventory-demo
    03_views.sql - Reporting views

    Idempotent: CREATE OR ALTER VIEW.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE InventoryDemo;
GO

/* Current stock per warehouse with unit price and extended value */
CREATE OR ALTER VIEW dbo.vw_StockOnHand
AS
SELECT
    s.WarehouseId,
    w.Code                AS WarehouseCode,
    w.Name                AS WarehouseName,
    s.ProductId,
    p.Sku,
    p.Name                AS ProductName,
    c.Name                AS CategoryName,
    s.Quantity,
    p.ReorderLevel,
    p.UnitPrice,
    CONVERT(DECIMAL(14,2), s.Quantity * p.UnitPrice) AS StockValue,
    s.UpdatedAt
FROM dbo.Stock AS s
INNER JOIN dbo.Warehouses AS w ON w.WarehouseId = s.WarehouseId
INNER JOIN dbo.Products   AS p ON p.ProductId   = s.ProductId
INNER JOIN dbo.Categories AS c ON c.CategoryId  = p.CategoryId;
GO

/* Products whose total quantity across warehouses is at or below reorder level */
CREATE OR ALTER VIEW dbo.vw_LowStock
AS
SELECT
    p.ProductId,
    p.Sku,
    p.Name                AS ProductName,
    c.Name                AS CategoryName,
    p.ReorderLevel,
    COALESCE(SUM(s.Quantity), 0) AS TotalQuantity,
    COALESCE(SUM(s.Quantity), 0) - p.ReorderLevel AS UnitsBelowReorder
FROM dbo.Products AS p
INNER JOIN dbo.Categories AS c ON c.CategoryId = p.CategoryId
LEFT JOIN dbo.Stock AS s ON s.ProductId = p.ProductId
WHERE p.IsActive = 1
GROUP BY p.ProductId, p.Sku, p.Name, c.Name, p.ReorderLevel
HAVING COALESCE(SUM(s.Quantity), 0) <= p.ReorderLevel;
GO

/* Total inventory valuation per warehouse */
CREATE OR ALTER VIEW dbo.vw_StockValuation
AS
SELECT
    w.WarehouseId,
    w.Code AS WarehouseCode,
    w.Name AS WarehouseName,
    COUNT(DISTINCT s.ProductId)                              AS DistinctProducts,
    COALESCE(SUM(s.Quantity), 0)                             AS TotalUnits,
    CONVERT(DECIMAL(16,2), COALESCE(SUM(s.Quantity * p.UnitPrice), 0)) AS TotalValue
FROM dbo.Warehouses AS w
LEFT JOIN dbo.Stock    AS s ON s.WarehouseId = w.WarehouseId
LEFT JOIN dbo.Products AS p ON p.ProductId   = s.ProductId
GROUP BY w.WarehouseId, w.Code, w.Name;
GO

/* Movement history joined to product/warehouse names */
CREATE OR ALTER VIEW dbo.vw_ProductMovementSummary
AS
SELECT
    m.MovementId,
    m.MovedAt,
    m.MovementType,
    p.Sku,
    p.Name       AS ProductName,
    w.Code       AS WarehouseCode,
    m.QtyChange,
    m.Reason,
    m.MovedBy
FROM dbo.StockMovements AS m
INNER JOIN dbo.Products   AS p ON p.ProductId   = m.ProductId
INNER JOIN dbo.Warehouses AS w ON w.WarehouseId = m.WarehouseId;
GO

PRINT '03_views.sql OK';
GO
