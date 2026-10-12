/*
    sql-server-inventory-demo
    07_seed.sql - Fictional sample data

    Idempotent: clears all tables (children first), reseeds identities and
    inserts fresh data inside a transaction. All names/companies are fictional.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

USE InventoryDemo;
GO

BEGIN TRANSACTION;

/* ---------- Clear (children before parents) ---------- */
DELETE FROM dbo.PurchaseOrderLines;
DELETE FROM dbo.PurchaseOrders;
DELETE FROM dbo.StockMovements;
DELETE FROM dbo.Stock;
DELETE FROM dbo.Products;
DELETE FROM dbo.Warehouses;
DELETE FROM dbo.Categories;
DELETE FROM dbo.Suppliers;
DELETE FROM dbo.AuditLog;

/* ---------- Seed Categories ---------- */
SET IDENTITY_INSERT dbo.Categories ON;
INSERT INTO dbo.Categories (CategoryId, Name, Description) VALUES
    (1, N'Computers',       N'Laptops and desktop computers'),
    (2, N'Peripherals',     N'Keyboards, mice, monitors and other peripherals'),
    (3, N'Office Supplies', N'Paper, pens and consumables');
SET IDENTITY_INSERT dbo.Categories OFF;

/* ---------- Seed Suppliers ---------- */
SET IDENTITY_INSERT dbo.Suppliers ON;
INSERT INTO dbo.Suppliers (SupplierId, Name, TaxId, Email, Phone, IsActive) VALUES
    (1, N'Andes Tech Supply SAC',  N'20481234567', N'sales@andestech.example',  N'+51 900 000 001', 1),
    (2, N'Lima Office Goods EIRL', N'20559876543', N'ventas@limaoffice.example', N'+51 900 000 002', 1),
    (3, N'Global Components SRL',  N'20601122334', N'contact@globalcomp.example', N'+51 900 000 003', 0);
SET IDENTITY_INSERT dbo.Suppliers OFF;

/* ---------- Seed Warehouses ---------- */
SET IDENTITY_INSERT dbo.Warehouses ON;
INSERT INTO dbo.Warehouses (WarehouseId, Code, Name, City) VALUES
    (1, N'WH-LIM', N'Lima Central Warehouse', N'Lima'),
    (2, N'WH-ARE', N'Arequipa Warehouse',     N'Arequipa');
SET IDENTITY_INSERT dbo.Warehouses OFF;

/* ---------- Seed Products (8) ---------- */
SET IDENTITY_INSERT dbo.Products ON;
INSERT INTO dbo.Products (ProductId, Sku, Name, CategoryId, UnitPrice, ReorderLevel, IsActive) VALUES
    (1, N'SKU-1001', N'Laptop Pro 14',         1, 3500.00, 5,  1),
    (2, N'SKU-1002', N'Laptop Air 13',         1, 2900.00, 4,  1),
    (3, N'SKU-2001', N'Wireless Mouse',        2,   45.50, 20, 1),
    (4, N'SKU-2002', N'Mechanical Keyboard',   2,  180.00, 10, 1),
    (5, N'SKU-2003', N'27-inch Monitor',       2,  950.00, 6,  1),
    (6, N'SKU-3001', N'A4 Paper Pack (500)',   3,   12.90, 50, 1),
    (7, N'SKU-3002', N'Ballpoint Pens (box)',  3,    8.50, 40, 1),
    (8, N'SKU-3003', N'Printer Toner Black',   3,  220.00, 8,  1);
SET IDENTITY_INSERT dbo.Products OFF;

/* ---------- Seed Stock (two warehouses) ---------- */
INSERT INTO dbo.Stock (WarehouseId, ProductId, Quantity) VALUES
    (1, 1,  12), (1, 2,  4), (1, 3,  60), (1, 4,  25),
    (1, 5,   3), (1, 6, 120), (1, 7,  35), (1, 8,   2),
    (2, 1,   6), (2, 2,   9), (2, 3,  40), (2, 4,  10),
    (2, 5,   0), (2, 6,  80), (2, 7,  50), (2, 8,   9);

/* ---------- Seed StockMovements (spread over the last ~25 days) ---------- */
INSERT INTO dbo.StockMovements (ProductId, WarehouseId, QtyChange, MovementType, Reason, MovedBy, MovedAt) VALUES
    (1, 1,   8, N'IN',  N'Initial stock',        N'seed', DATEADD(DAY, -25, SYSUTCDATETIME())),
    (3, 1,  50, N'IN',  N'Initial stock',        N'seed', DATEADD(DAY, -25, SYSUTCDATETIME())),
    (6, 1, 100, N'IN',  N'Initial stock',        N'seed', DATEADD(DAY, -24, SYSUTCDATETIME())),
    (3, 1, -10, N'OUT', N'Office replenishment', N'admin', DATEADD(DAY, -20, SYSUTCDATETIME())),
    (6, 1, -20, N'OUT', N'Office replenishment', N'admin', DATEADD(DAY, -18, SYSUTCDATETIME())),
    (1, 1,  -3, N'OUT', N'Customer order #1042', N'admin', DATEADD(DAY, -12, SYSUTCDATETIME())),
    (4, 2,  10, N'IN',  N'Transfer from Lima',   N'admin', DATEADD(DAY, -10, SYSUTCDATETIME())),
    (5, 1,  -1, N'OUT', N'Warranty replacement', N'admin', DATEADD(DAY,  -7, SYSUTCDATETIME())),
    (3, 2, -25, N'OUT', N'Customer order #1051', N'admin', DATEADD(DAY,  -4, SYSUTCDATETIME())),
    (7, 1,  -5, N'OUT', N'Stationery request',   N'admin', DATEADD(DAY,  -2, SYSUTCDATETIME()));

/* ---------- Seed a RECEIVED purchase order ---------- */
SET IDENTITY_INSERT dbo.PurchaseOrders ON;
INSERT INTO dbo.PurchaseOrders (PoId, PoNumber, SupplierId, Status, CreatedAt, ReceivedAt) VALUES
    (1, N'PO-1000', 2, N'RECEIVED', DATEADD(DAY, -15, SYSUTCDATETIME()), DATEADD(DAY, -14, SYSUTCDATETIME()));
SET IDENTITY_INSERT dbo.PurchaseOrders OFF;

INSERT INTO dbo.PurchaseOrderLines (PoId, LineNumber, ProductId, Quantity, UnitCost) VALUES
    (1, 1, 6, 100, 10.50),
    (1, 2, 7,  50,  7.00);

/* ---------- Seed a SENT purchase order ready to be received ---------- */
SET IDENTITY_INSERT dbo.PurchaseOrders ON;
INSERT INTO dbo.PurchaseOrders (PoId, PoNumber, SupplierId, Status, CreatedAt) VALUES
    (2, N'PO-1001', 1, N'SENT', DATEADD(DAY, -3, SYSUTCDATETIME()));
SET IDENTITY_INSERT dbo.PurchaseOrders OFF;

INSERT INTO dbo.PurchaseOrderLines (PoId, LineNumber, ProductId, Quantity, UnitCost) VALUES
    (2, 1, 1,  5, 3100.00),
    (2, 2, 5,  4,  820.00);

COMMIT TRANSACTION;

PRINT '07_seed.sql OK';
GO
