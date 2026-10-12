/*
    sql-server-inventory-demo
    04_functions.sql - Scalar function + inline table-valued function

    Idempotent: CREATE OR ALTER FUNCTION.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE InventoryDemo;
GO

/* Scalar function: current inventory value of a single product across all warehouses */
CREATE OR ALTER FUNCTION dbo.fn_StockValue
(
    @ProductId INT
)
RETURNS DECIMAL(14,2)
AS
BEGIN
    DECLARE @value DECIMAL(14,2);

    SELECT @value = CONVERT(DECIMAL(14,2), COALESCE(SUM(s.Quantity * p.UnitPrice), 0))
    FROM dbo.Stock AS s
    INNER JOIN dbo.Products AS p ON p.ProductId = s.ProductId
    WHERE s.ProductId = @ProductId;

    RETURN COALESCE(@value, 0);
END;
GO

/* Inline table-valued function: active products in a category */
CREATE OR ALTER FUNCTION dbo.fn_ProductsByCategory
(
    @CategoryId INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        p.ProductId,
        p.Sku,
        p.Name      AS ProductName,
        p.UnitPrice,
        p.ReorderLevel,
        dbo.fn_StockValue(p.ProductId) AS StockValue
    FROM dbo.Products AS p
    WHERE p.CategoryId = @CategoryId
      AND p.IsActive = 1
);
GO

PRINT '04_functions.sql OK';
GO
