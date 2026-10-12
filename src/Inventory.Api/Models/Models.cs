namespace Inventory.Api.Models;

public sealed record Product(
    int ProductId,
    string Sku,
    string Name,
    int CategoryId,
    decimal UnitPrice,
    int ReorderLevel,
    bool IsActive);

public sealed record StockOnHand(
    int WarehouseId,
    string WarehouseCode,
    string WarehouseName,
    int ProductId,
    string Sku,
    string ProductName,
    string CategoryName,
    int Quantity,
    int ReorderLevel,
    decimal UnitPrice,
    decimal StockValue,
    DateTime UpdatedAt);

public sealed record LowStockItem(
    int ProductId,
    string Sku,
    string ProductName,
    string CategoryName,
    int ReorderLevel,
    int TotalQuantity,
    int StockMargin,
    long SeverityRank);

public sealed record AdjustStockRequest(
    int ProductId,
    int WarehouseId,
    int QtyChange,
    string? Reason,
    string? MovedBy);

public sealed record AdjustStockResult(
    int ProductId,
    int WarehouseId,
    int NewQuantity,
    string MovementType);

public sealed record ReceiveResult(
    int PoId,
    string PoNumber,
    string Status,
    int LinesTotal);
