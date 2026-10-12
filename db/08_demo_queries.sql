/*
    sql-server-inventory-demo
    08_demo_queries.sql - Reporting / T-SQL feature showcase

    Read-only and safe to re-run. Each query is labeled with the T-SQL
    technique it demonstrates. Run after 07_seed.sql.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE InventoryDemo;
GO

/* ---------------------------------------------------------------
   Q1. CTE + JSON (FOR JSON PATH)
   Movements from the last 30 days returned as one JSON document.
   --------------------------------------------------------------- */
PRINT 'Q1. Movements (last 30 days) as JSON';
WITH Recent AS
(
    SELECT m.MovementId, m.MovedAt, m.MovementType, p.Sku, m.QtyChange
    FROM dbo.StockMovements AS m
    INNER JOIN dbo.Products AS p ON p.ProductId = m.ProductId
    WHERE m.MovedAt >= DATEADD(DAY, -30, SYSUTCDATETIME())
)
SELECT MovementId, MovedAt, MovementType, Sku, QtyChange
FROM Recent
ORDER BY MovedAt
FOR JSON PATH, ROOT('movements');
GO

/* ---------------------------------------------------------------
   Q2. Window functions: ROW_NUMBER + SUM() OVER (running total)
   Running balance of stock movements per product over time.
   --------------------------------------------------------------- */
PRINT 'Q2. Running stock balance per product (window function)';
SELECT
    p.Sku,
    m.MovedAt,
    m.QtyChange,
    SUM(m.QtyChange) OVER (PARTITION BY m.ProductId ORDER BY m.MovedAt, m.MovementId
                           ROWS UNBOUNDED PRECEDING) AS RunningBalance,
    ROW_NUMBER() OVER (PARTITION BY m.ProductId ORDER BY m.MovedAt, m.MovementId) AS MovementNo
FROM dbo.StockMovements AS m
INNER JOIN dbo.Products AS p ON p.ProductId = m.ProductId
ORDER BY p.Sku, MovementNo;
GO

/* ---------------------------------------------------------------
   Q3. RANK + HAVING: low-stock products ranked by severity.
   --------------------------------------------------------------- */
PRINT 'Q3. Low-stock ranking (RANK + HAVING)';
SELECT
    p.Sku,
    p.Name AS ProductName,
    p.ReorderLevel,
    COALESCE(SUM(s.Quantity), 0) AS TotalQuantity,
    RANK() OVER (ORDER BY COALESCE(SUM(s.Quantity), 0) - p.ReorderLevel) AS SeverityRank
FROM dbo.Products AS p
LEFT JOIN dbo.Stock AS s ON s.ProductId = p.ProductId
WHERE p.IsActive = 1
GROUP BY p.ProductId, p.Sku, p.Name, p.ReorderLevel
HAVING COALESCE(SUM(s.Quantity), 0) <= p.ReorderLevel
ORDER BY SeverityRank;
GO

/* ---------------------------------------------------------------
   Q4. PIVOT: current stock per product per warehouse.
   --------------------------------------------------------------- */
PRINT 'Q4. Stock per warehouse (PIVOT)';
SELECT ProductSku, [WH-LIM], [WH-ARE], COALESCE([WH-LIM], 0) + COALESCE([WH-ARE], 0) AS TotalUnits
FROM
(
    SELECT p.Sku AS ProductSku, w.Code AS WarehouseCode, s.Quantity
    FROM dbo.Stock AS s
    INNER JOIN dbo.Products   AS p ON p.ProductId   = s.ProductId
    INNER JOIN dbo.Warehouses AS w ON w.WarehouseId = s.WarehouseId
) AS src
PIVOT
(
    SUM(Quantity) FOR WarehouseCode IN ([WH-LIM], [WH-ARE])
) AS pvt
ORDER BY ProductSku;
GO

/* ---------------------------------------------------------------
   Q5. Conditional aggregation (SUM/COUNT with CASE).
   Inventory value and low-stock count per category.
   --------------------------------------------------------------- */
PRINT 'Q5. Category summary (conditional aggregation)';
SELECT
    c.Name AS CategoryName,
    COUNT(DISTINCT p.ProductId) AS ProductCount,
    CONVERT(DECIMAL(16,2), SUM(COALESCE(s.Quantity, 0) * p.UnitPrice)) AS InventoryValue,
    SUM(CASE WHEN COALESCE(s.Quantity, 0) = 0 THEN 1 ELSE 0 END) AS ZeroStockRows,
    SUM(CASE WHEN COALESCE(s.Quantity, 0) <= p.ReorderLevel THEN 1 ELSE 0 END) AS LowStockRows
FROM dbo.Categories AS c
INNER JOIN dbo.Products AS p ON p.CategoryId = c.CategoryId
LEFT JOIN dbo.Stock AS s ON s.ProductId = p.ProductId
GROUP BY c.CategoryId, c.Name
HAVING COUNT(DISTINCT p.ProductId) > 0
ORDER BY InventoryValue DESC;
GO

/* ---------------------------------------------------------------
   Q6. STRING_AGG: comma-separated product list per category.
   --------------------------------------------------------------- */
PRINT 'Q6. Products per category (STRING_AGG)';
SELECT
    c.Name AS CategoryName,
    STRING_AGG(p.Name, N', ') WITHIN GROUP (ORDER BY p.Name) AS Products
FROM dbo.Categories AS c
INNER JOIN dbo.Products AS p ON p.CategoryId = c.CategoryId
WHERE p.IsActive = 1
GROUP BY c.CategoryId, c.Name;
GO

/* ---------------------------------------------------------------
   Q7. OPENJSON: parse a JSON payload and join it back to Products.
   --------------------------------------------------------------- */
PRINT 'Q7. OPENJSON round-trip';
DECLARE @json NVARCHAR(MAX) = N'[
    {"Sku":"SKU-1001","Qty":2},
    {"Sku":"SKU-2001","Qty":15}
]';

SELECT
    p.Sku,
    p.Name AS ProductName,
    j.Qty AS RequestedQty,
    p.UnitPrice,
    CONVERT(DECIMAL(12,2), j.Qty * p.UnitPrice) AS LineValue
FROM OPENJSON(@json)
     WITH (Sku NVARCHAR(30) '$.Sku', Qty INT '$.Qty') AS j
INNER JOIN dbo.Products AS p ON p.Sku = j.Sku;
GO

/* ---------------------------------------------------------------
   Q8. TRY_CONVERT + string-to-date parsing (no error on bad input).
   --------------------------------------------------------------- */
PRINT 'Q8. TRY_CONVERT (safe type conversion)';
SELECT
    val,
    TRY_CONVERT(DATE, val) AS ParsedDate,
    TRY_CONVERT(DECIMAL(10,2), val) AS ParsedNumber
FROM (VALUES (N'2026-01-15'), (N'not-a-date'), (N'123.45'), (N'abc')) AS v(val);
GO

/* ---------------------------------------------------------------
   Q9. Date functions: DATEADD + EOMONTH (month boundaries).
   --------------------------------------------------------------- */
PRINT 'Q9. Month boundaries (EOMONTH)';
SELECT
    SYSUTCDATETIME()                                 AS NowUtc,
    EOMONTH(SYSUTCDATETIME())                        AS EndOfThisMonth,
    DATEADD(DAY, 1, EOMONTH(SYSUTCDATETIME(), -1))   AS StartOfThisMonth,
    EOMONTH(SYSUTCDATETIME(), 1)                     AS EndOfNextMonth;
GO

/* ---------------------------------------------------------------
   Q10. Call the table-valued function joined to a view.
   --------------------------------------------------------------- */
PRINT 'Q10. Table-valued function (fn_ProductsByCategory)';
SELECT c.Name AS CategoryName, f.ProductName, f.UnitPrice, f.StockValue
FROM dbo.fn_ProductsByCategory(2) AS f
CROSS JOIN dbo.Categories AS c
WHERE c.CategoryId = 2
ORDER BY f.StockValue DESC;
GO
