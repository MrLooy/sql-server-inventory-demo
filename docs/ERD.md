# Entity-Relationship Diagram

```mermaid
erDiagram
    Categories ||--o{ Products : "classifies"
    Suppliers  ||--o{ PurchaseOrders : "supplies"
    Warehouses ||--o{ Stock : "stores"
    Products   ||--o{ Stock : "stocked as"
    Products   ||--o{ StockMovements : "moves"
    Warehouses ||--o{ StockMovements : "located in"
    PurchaseOrders ||--o{ PurchaseOrderLines : "contains"
    Products   ||--o{ PurchaseOrderLines : "ordered as"

    Categories {
        int         CategoryId PK
        nvarchar80  Name
        nvarchar300 Description
        datetime2   CreatedAt
    }
    Suppliers {
        int          SupplierId PK
        nvarchar120  Name
        nvarchar20   TaxId
        nvarchar160  Email
        nvarchar40   Phone
        bit          IsActive
        datetime2    CreatedAt
    }
    Warehouses {
        int         WarehouseId PK
        nvarchar10  Code
        nvarchar80  Name
        nvarchar80  City
    }
    Products {
        int          ProductId PK
        nvarchar30   Sku
        nvarchar120  Name
        int          CategoryId FK
        decimal      UnitPrice
        int          ReorderLevel
        bit          IsActive
        rowversion   RowVersion
        datetime2    CreatedAt
        datetime2    UpdatedAt
    }
    Stock {
        int       WarehouseId PK
        int       ProductId   PK
        int       Quantity
        datetime2 UpdatedAt
    }
    StockMovements {
        bigint      MovementId PK
        int         ProductId FK
        int         WarehouseId FK
        int         QtyChange
        nvarchar10  MovementType
        nvarchar200 Reason
        nvarchar80  MovedBy
        datetime2   MovedAt
    }
    PurchaseOrders {
        int          PoId PK
        nvarchar20   PoNumber
        int          SupplierId FK
        nvarchar10   Status
        datetime2    CreatedAt
        datetime2    ReceivedAt
    }
    PurchaseOrderLines {
        int     PoId PK
        int     LineNumber PK
        int     ProductId FK
        int     Quantity
        decimal UnitCost
        decimal LineTotal
    }
    AuditLog {
        bigint      AuditId PK
        nvarchar128 TableName
        nvarchar10  Action
        nvarchar200 KeyValue
        nvarchar80  ChangedBy
        datetime2   ChangedAt
        nvarcharMAX Payload
    }
```

`PoNumber` has a default that pulls the next value from the sequence
`dbo.seq_PoNumber` (`N'PO-' + CAST(NEXT VALUE FOR dbo.seq_PoNumber AS NVARCHAR(10))`).
`AuditLog` is written by the trigger `dbo.trg_Products_Audit` on `Products`.
