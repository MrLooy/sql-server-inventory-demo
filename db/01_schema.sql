/*
    sql-server-inventory-demo
    01_schema.sql - Database + schema (DDL)

    Idempotent: safe to re-run. Drops demo objects (children first) and recreates
    a clean, normalized (3NF) schema. Run scripts 01..08 in order.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF DB_ID('InventoryDemo') IS NULL
    CREATE DATABASE InventoryDemo;
GO

USE InventoryDemo;
GO

/* ---------- Drop existing objects (children before parents) ---------- */
DROP TABLE IF EXISTS dbo.PurchaseOrderLines;
DROP TABLE IF EXISTS dbo.PurchaseOrders;
DROP TABLE IF EXISTS dbo.StockMovements;
DROP TABLE IF EXISTS dbo.Stock;
DROP TABLE IF EXISTS dbo.Products;
DROP TABLE IF EXISTS dbo.Warehouses;
DROP TABLE IF EXISTS dbo.Categories;
DROP TABLE IF EXISTS dbo.Suppliers;
DROP TABLE IF EXISTS dbo.AuditLog;
DROP SEQUENCE IF EXISTS dbo.seq_PoNumber;
GO

/* ---------- Sequence used to generate PO numbers ---------- */
CREATE SEQUENCE dbo.seq_PoNumber
    AS INT
    START WITH 1000
    INCREMENT BY 1
    CACHE 50;
GO

/* ---------- Categories ---------- */
CREATE TABLE dbo.Categories
(
    CategoryId  INT IDENTITY(1,1) NOT NULL,
    Name        NVARCHAR(80)  NOT NULL,
    Description NVARCHAR(300) NULL,
    CreatedAt   DATETIME2(3)  NOT NULL CONSTRAINT DF_Categories_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Categories PRIMARY KEY CLUSTERED (CategoryId),
    CONSTRAINT UQ_Categories_Name UNIQUE (Name),
    CONSTRAINT CK_Categories_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(Name))) > 0)
);
GO

/* ---------- Suppliers ---------- */
CREATE TABLE dbo.Suppliers
(
    SupplierId INT IDENTITY(1,1) NOT NULL,
    Name       NVARCHAR(120) NOT NULL,
    TaxId      NVARCHAR(20)  NOT NULL,
    Email      NVARCHAR(160) NULL,
    Phone      NVARCHAR(40)  NULL,
    IsActive   BIT           NOT NULL CONSTRAINT DF_Suppliers_IsActive DEFAULT (1),
    CreatedAt  DATETIME2(3)  NOT NULL CONSTRAINT DF_Suppliers_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Suppliers PRIMARY KEY CLUSTERED (SupplierId),
    CONSTRAINT UQ_Suppliers_TaxId UNIQUE (TaxId),
    CONSTRAINT CK_Suppliers_Email CHECK (Email IS NULL OR Email LIKE '%_@_%._%')
);
GO

/* ---------- Warehouses ---------- */
CREATE TABLE dbo.Warehouses
(
    WarehouseId INT IDENTITY(1,1) NOT NULL,
    Code        NVARCHAR(10) NOT NULL,
    Name        NVARCHAR(80) NOT NULL,
    City        NVARCHAR(80) NULL,
    CONSTRAINT PK_Warehouses PRIMARY KEY CLUSTERED (WarehouseId),
    CONSTRAINT UQ_Warehouses_Code UNIQUE (Code)
);
GO

/* ---------- Products ---------- */
CREATE TABLE dbo.Products
(
    ProductId    INT IDENTITY(1,1) NOT NULL,
    Sku          NVARCHAR(30)  NOT NULL,
    Name         NVARCHAR(120) NOT NULL,
    CategoryId   INT           NOT NULL,
    UnitPrice    DECIMAL(10,2) NOT NULL,
    ReorderLevel INT           NOT NULL CONSTRAINT DF_Products_ReorderLevel DEFAULT (0),
    IsActive     BIT           NOT NULL CONSTRAINT DF_Products_IsActive DEFAULT (1),
    RowVersion   ROWVERSION    NOT NULL,
    CreatedAt    DATETIME2(3)  NOT NULL CONSTRAINT DF_Products_CreatedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt    DATETIME2(3)  NOT NULL CONSTRAINT DF_Products_UpdatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Products PRIMARY KEY CLUSTERED (ProductId),
    CONSTRAINT UQ_Products_Sku UNIQUE (Sku),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryId) REFERENCES dbo.Categories (CategoryId),
    CONSTRAINT CK_Products_UnitPrice CHECK (UnitPrice > 0),
    CONSTRAINT CK_Products_ReorderLevel CHECK (ReorderLevel >= 0)
);
GO

/* ---------- Stock (composite primary key) ---------- */
CREATE TABLE dbo.Stock
(
    WarehouseId INT          NOT NULL,
    ProductId   INT          NOT NULL,
    Quantity    INT          NOT NULL CONSTRAINT DF_Stock_Quantity DEFAULT (0),
    UpdatedAt   DATETIME2(3) NOT NULL CONSTRAINT DF_Stock_UpdatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Stock PRIMARY KEY CLUSTERED (WarehouseId, ProductId),
    CONSTRAINT FK_Stock_Warehouses FOREIGN KEY (WarehouseId) REFERENCES dbo.Warehouses (WarehouseId),
    CONSTRAINT FK_Stock_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products (ProductId),
    CONSTRAINT CK_Stock_Quantity CHECK (Quantity >= 0)
);
GO

/* ---------- StockMovements (audit trail of quantity changes) ---------- */
CREATE TABLE dbo.StockMovements
(
    MovementId   BIGINT IDENTITY(1,1) NOT NULL,
    ProductId    INT           NOT NULL,
    WarehouseId  INT           NOT NULL,
    QtyChange    INT           NOT NULL,
    MovementType NVARCHAR(10)  NOT NULL,
    Reason       NVARCHAR(200) NULL,
    MovedBy      NVARCHAR(80)  NULL,
    MovedAt      DATETIME2(3)  NOT NULL CONSTRAINT DF_StockMovements_MovedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_StockMovements PRIMARY KEY CLUSTERED (MovementId),
    CONSTRAINT FK_StockMovements_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products (ProductId),
    CONSTRAINT FK_StockMovements_Warehouses FOREIGN KEY (WarehouseId) REFERENCES dbo.Warehouses (WarehouseId),
    CONSTRAINT CK_StockMovements_QtyChange CHECK (QtyChange <> 0),
    CONSTRAINT CK_StockMovements_Type CHECK (MovementType IN ('IN', 'OUT', 'ADJUST'))
);
GO

/* ---------- PurchaseOrders ---------- */
CREATE TABLE dbo.PurchaseOrders
(
    PoId       INT          IDENTITY(1,1) NOT NULL,
    PoNumber   NVARCHAR(20) NOT NULL
               CONSTRAINT DF_PurchaseOrders_PoNumber
               DEFAULT (N'PO-' + CAST(NEXT VALUE FOR dbo.seq_PoNumber AS NVARCHAR(10))),
    SupplierId INT          NOT NULL,
    Status     NVARCHAR(10) NOT NULL CONSTRAINT DF_PurchaseOrders_Status DEFAULT ('DRAFT'),
    CreatedAt  DATETIME2(3) NOT NULL CONSTRAINT DF_PurchaseOrders_CreatedAt DEFAULT SYSUTCDATETIME(),
    ReceivedAt DATETIME2(3) NULL,
    CONSTRAINT PK_PurchaseOrders PRIMARY KEY CLUSTERED (PoId),
    CONSTRAINT UQ_PurchaseOrders_PoNumber UNIQUE (PoNumber),
    CONSTRAINT FK_PurchaseOrders_Suppliers FOREIGN KEY (SupplierId) REFERENCES dbo.Suppliers (SupplierId),
    CONSTRAINT CK_PurchaseOrders_Status CHECK (Status IN ('DRAFT', 'SENT', 'RECEIVED', 'CANCELLED'))
);
GO

/* ---------- PurchaseOrderLines (computed PERSISTED column) ---------- */
CREATE TABLE dbo.PurchaseOrderLines
(
    PoId       INT           NOT NULL,
    LineNumber INT           NOT NULL,
    ProductId  INT           NOT NULL,
    Quantity   INT           NOT NULL,
    UnitCost   DECIMAL(10,2) NOT NULL,
    LineTotal AS (CONVERT(DECIMAL(12,2), Quantity * UnitCost)) PERSISTED,
    CONSTRAINT PK_PurchaseOrderLines PRIMARY KEY CLUSTERED (PoId, LineNumber),
    CONSTRAINT FK_PurchaseOrderLines_PurchaseOrders FOREIGN KEY (PoId) REFERENCES dbo.PurchaseOrders (PoId),
    CONSTRAINT FK_PurchaseOrderLines_Products FOREIGN KEY (ProductId) REFERENCES dbo.Products (ProductId),
    CONSTRAINT CK_PurchaseOrderLines_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_PurchaseOrderLines_UnitCost CHECK (UnitCost > 0)
);
GO

/* ---------- AuditLog (written by triggers) ---------- */
CREATE TABLE dbo.AuditLog
(
    AuditId   BIGINT IDENTITY(1,1) NOT NULL,
    TableName NVARCHAR(128) NOT NULL,
    Action    NVARCHAR(10)  NOT NULL,
    KeyValue  NVARCHAR(200) NULL,
    ChangedBy NVARCHAR(80)  NULL,
    ChangedAt DATETIME2(3)  NOT NULL CONSTRAINT DF_AuditLog_ChangedAt DEFAULT SYSUTCDATETIME(),
    Payload   NVARCHAR(MAX) NULL,
    CONSTRAINT PK_AuditLog PRIMARY KEY CLUSTERED (AuditId)
);
GO

PRINT '01_schema.sql OK';
GO
