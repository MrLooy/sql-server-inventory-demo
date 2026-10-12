/*
    sql-server-inventory-demo
    05_procedures.sql - Stored procedures

    Demonstrates: SET NOCOUNT ON, TRY/CATCH, explicit transactions, THROW,
    OUTPUT parameters, MERGE (upsert), and validation.

    Idempotent: CREATE OR ALTER PROCEDURE.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE InventoryDemo;
GO

/* ============================================================
   usp_ReceivePurchaseOrder
   Receives a purchase order: adds each line to Stock, records an
   'IN' movement, then marks the PO as RECEIVED. All inside one
   transaction; rolls back and rethrows on any error.
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.usp_ReceivePurchaseOrder
(
    @PoId       INT,
    @MovedBy    NVARCHAR(80) = NULL,
    @LinesTotal INT = NULL OUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @status NVARCHAR(10);
    DECLARE @actor NVARCHAR(80) = COALESCE(@MovedBy, N'system');

    DECLARE @lines TABLE (ProductId INT NOT NULL, Quantity INT NOT NULL);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @status = Status
        FROM dbo.PurchaseOrders WITH (UPDLOCK, HOLDLOCK)
        WHERE PoId = @PoId;

        IF @status IS NULL
            THROW 50001, 'Purchase order not found.', 1;

        IF @status NOT IN ('DRAFT', 'SENT')
            THROW 50002, 'Purchase order can only be received when DRAFT or SENT.', 1;

        INSERT INTO @lines (ProductId, Quantity)
        SELECT ProductId, SUM(Quantity)
        FROM dbo.PurchaseOrderLines
        WHERE PoId = @PoId
        GROUP BY ProductId;

        IF NOT EXISTS (SELECT 1 FROM @lines)
            THROW 50003, 'Purchase order has no lines.', 1;

        /* Upsert each line into Stock and log an IN movement */
        MERGE dbo.Stock AS target
        USING (SELECT ProductId, Quantity FROM @lines) AS src
            ON target.WarehouseId = 1 AND target.ProductId = src.ProductId
        WHEN MATCHED THEN
            UPDATE SET target.Quantity  = target.Quantity + src.Quantity,
                       target.UpdatedAt = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (WarehouseId, ProductId, Quantity, UpdatedAt)
            VALUES (1, src.ProductId, src.Quantity, SYSUTCDATETIME());

        INSERT INTO dbo.StockMovements (ProductId, WarehouseId, QtyChange, MovementType, Reason, MovedBy)
        SELECT ProductId, 1, Quantity, N'IN', CONCAT(N'Received PO ', @PoId), @actor
        FROM @lines;

        SELECT @LinesTotal = COUNT(*) FROM dbo.PurchaseOrderLines WHERE PoId = @PoId;

        UPDATE dbo.PurchaseOrders
        SET Status = N'RECEIVED',
            ReceivedAt = SYSUTCDATETIME()
        WHERE PoId = @PoId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

/* ============================================================
   usp_AdjustStock
   Applies a signed quantity change (IN/OUT/ADJUST) to one product
   in one warehouse. Rejects changes that would drive stock negative.
   Returns the resulting quantity via OUTPUT.
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.usp_AdjustStock
(
    @ProductId   INT,
    @WarehouseId INT,
    @QtyChange   INT,
    @Reason      NVARCHAR(200) = NULL,
    @MovedBy     NVARCHAR(80)  = NULL,
    @NewQuantity INT = NULL OUT
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @QtyChange = 0
        THROW 50010, 'QtyChange must be non-zero.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Products WHERE ProductId = @ProductId)
        THROW 50011, 'Product not found.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Warehouses WHERE WarehouseId = @WarehouseId)
        THROW 50012, 'Warehouse not found.', 1;

    DECLARE @type NVARCHAR(10) =
        CASE WHEN @QtyChange > 0 THEN N'IN' ELSE N'OUT' END;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @current INT =
        (
            SELECT Quantity FROM dbo.Stock WITH (UPDLOCK, HOLDLOCK)
            WHERE ProductId = @ProductId AND WarehouseId = @WarehouseId
        );

        SET @current = COALESCE(@current, 0);

        IF @current + @QtyChange < 0
            THROW 50013, 'Adjustment would result in negative stock.', 1;

        MERGE dbo.Stock AS target
        USING (SELECT @WarehouseId AS WarehouseId, @ProductId AS ProductId) AS src
            ON target.WarehouseId = src.WarehouseId AND target.ProductId = src.ProductId
        WHEN MATCHED THEN
            UPDATE SET target.Quantity  = target.Quantity + @QtyChange,
                       target.UpdatedAt = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (WarehouseId, ProductId, Quantity, UpdatedAt)
            VALUES (@WarehouseId, @ProductId, @QtyChange, SYSUTCDATETIME());

        INSERT INTO dbo.StockMovements (ProductId, WarehouseId, QtyChange, MovementType, Reason, MovedBy)
        VALUES (@ProductId, @WarehouseId, @QtyChange,
                CASE WHEN @Reason LIKE N'%adjust%' THEN N'ADJUST' ELSE @type END,
                @Reason, @MovedBy);

        SET @NewQuantity = @current + @QtyChange;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

/* ============================================================
   usp_LowStockReport
   Optional category filter. Uses a CTE and a window function to
   rank products by how far below the reorder level they are.
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.usp_LowStockReport
(
    @CategoryId INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    WITH Totals AS
    (
        SELECT
            p.ProductId,
            p.Sku,
            p.Name AS ProductName,
            p.CategoryId,
            p.ReorderLevel,
            COALESCE(SUM(s.Quantity), 0) AS TotalQuantity
        FROM dbo.Products AS p
        LEFT JOIN dbo.Stock AS s ON s.ProductId = p.ProductId
        WHERE p.IsActive = 1
          AND (@CategoryId IS NULL OR p.CategoryId = @CategoryId)
        GROUP BY p.ProductId, p.Sku, p.Name, p.CategoryId, p.ReorderLevel
    )
    SELECT
        t.ProductId,
        t.Sku,
        t.ProductName,
        c.Name AS CategoryName,
        t.ReorderLevel,
        t.TotalQuantity,
        t.TotalQuantity - t.ReorderLevel AS UnitsBelowReorder,
        RANK() OVER (ORDER BY (t.TotalQuantity - t.ReorderLevel) ASC) AS SeverityRank
    FROM Totals AS t
    INNER JOIN dbo.Categories AS c ON c.CategoryId = t.CategoryId
    WHERE t.TotalQuantity <= t.ReorderLevel
    ORDER BY SeverityRank, t.ProductName;
END;
GO

/* ============================================================
   usp_GetProductMovementJson
   Returns stock movements in a date range as a JSON array
   (FOR JSON PATH). Handy for API/ETL consumers.
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.usp_GetProductMovementJson
(
    @From DATETIME2,
    @To   DATETIME2
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        m.MovementId,
        m.MovedAt,
        m.MovementType,
        p.Sku,
        p.Name  AS ProductName,
        w.Code  AS WarehouseCode,
        m.QtyChange,
        m.Reason,
        m.MovedBy
    FROM dbo.StockMovements AS m
    INNER JOIN dbo.Products   AS p ON p.ProductId   = m.ProductId
    INNER JOIN dbo.Warehouses AS w ON w.WarehouseId = m.WarehouseId
    WHERE m.MovedAt >= @From AND m.MovedAt < @To
    ORDER BY m.MovedAt
    FOR JSON PATH, ROOT('movements');
END;
GO

/* ============================================================
   usp_UpsertSupplier
   Inserts a supplier or updates it when @SupplierId is provided.
   Uses MERGE. Returns the affected id via OUTPUT.
   NOTE: MERGE has known concurrency pitfalls; for high-throughput
   writes prefer an explicit IF EXISTS/UPDATE/INSERT with locking.
   Shown here to demonstrate the pattern.
   ============================================================ */
CREATE OR ALTER PROCEDURE dbo.usp_UpsertSupplier
(
    @SupplierId INT = NULL OUT,
    @Name       NVARCHAR(120),
    @TaxId      NVARCHAR(20),
    @Email      NVARCHAR(160) = NULL,
    @Phone      NVARCHAR(40)  = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @changes TABLE (Action NVARCHAR(10), SupplierId INT);

    BEGIN TRY
        BEGIN TRANSACTION;

        MERGE dbo.Suppliers AS target
        USING (SELECT @SupplierId AS SupplierId, @Name AS Name, @TaxId AS TaxId,
                      @Email AS Email, @Phone AS Phone) AS src
            ON target.SupplierId = src.SupplierId
        WHEN MATCHED THEN
            UPDATE SET Name = src.Name, TaxId = src.TaxId, Email = src.Email, Phone = src.Phone
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (Name, TaxId, Email, Phone)
            VALUES (src.Name, src.TaxId, src.Email, src.Phone)
        OUTPUT $action, INSERTED.SupplierId
        INTO @changes (Action, SupplierId);

        SELECT @SupplierId = SupplierId FROM @changes WHERE Action = N'INSERT';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

PRINT '05_procedures.sql OK';
GO
