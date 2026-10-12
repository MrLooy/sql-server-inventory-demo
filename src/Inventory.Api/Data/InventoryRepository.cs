using System.Data;
using Inventory.Api.Models;
using Microsoft.Data.SqlClient;

namespace Inventory.Api.Data;

/// <summary>
/// Data access layer. Deliberately uses ADO.NET (Microsoft.Data.SqlClient) with
/// explicit <see cref="SqlParameter"/> types and stored procedures, so the SQL
/// surface is visible instead of hidden behind an ORM.
/// </summary>
public sealed class InventoryRepository
{
    private readonly string _connectionString;

    public InventoryRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    private async Task<SqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }

    public async Task<IReadOnlyList<Product>> GetProductsAsync(CancellationToken ct = default)
    {
        const string sql = """
            SELECT ProductId, Sku, Name, CategoryId, UnitPrice, ReorderLevel, IsActive
            FROM dbo.Products
            ORDER BY Sku;
            """;

        await using var conn = await OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn);
        await using var reader = await cmd.ExecuteReaderAsync(ct);

        var result = new List<Product>();
        var oId = reader.GetOrdinal("ProductId");
        var oSku = reader.GetOrdinal("Sku");
        var oName = reader.GetOrdinal("Name");
        var oCat = reader.GetOrdinal("CategoryId");
        var oPrice = reader.GetOrdinal("UnitPrice");
        var oReorder = reader.GetOrdinal("ReorderLevel");
        var oActive = reader.GetOrdinal("IsActive");

        while (await reader.ReadAsync(ct))
        {
            result.Add(new Product(
                reader.GetInt32(oId),
                reader.GetString(oSku),
                reader.GetString(oName),
                reader.GetInt32(oCat),
                reader.GetDecimal(oPrice),
                reader.GetInt32(oReorder),
                reader.GetBoolean(oActive)));
        }

        return result;
    }

    public async Task<IReadOnlyList<StockOnHand>> GetStockAsync(int warehouseId, CancellationToken ct = default)
    {
        const string sql = """
            SELECT WarehouseId, WarehouseCode, WarehouseName, ProductId, Sku, ProductName,
                   CategoryName, Quantity, ReorderLevel, UnitPrice, StockValue, UpdatedAt
            FROM dbo.vw_StockOnHand
            WHERE WarehouseId = @WarehouseId
            ORDER BY Sku;
            """;

        await using var conn = await OpenAsync(ct);
        await using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.Add("@WarehouseId", SqlDbType.Int).Value = warehouseId;

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var result = new List<StockOnHand>();

        while (await reader.ReadAsync(ct))
        {
            result.Add(new StockOnHand(
                reader.GetInt32(reader.GetOrdinal("WarehouseId")),
                reader.GetString(reader.GetOrdinal("WarehouseCode")),
                reader.GetString(reader.GetOrdinal("WarehouseName")),
                reader.GetInt32(reader.GetOrdinal("ProductId")),
                reader.GetString(reader.GetOrdinal("Sku")),
                reader.GetString(reader.GetOrdinal("ProductName")),
                reader.GetString(reader.GetOrdinal("CategoryName")),
                reader.GetInt32(reader.GetOrdinal("Quantity")),
                reader.GetInt32(reader.GetOrdinal("ReorderLevel")),
                reader.GetDecimal(reader.GetOrdinal("UnitPrice")),
                reader.GetDecimal(reader.GetOrdinal("StockValue")),
                reader.GetDateTime(reader.GetOrdinal("UpdatedAt"))));
        }

        return result;
    }

    public async Task<IReadOnlyList<LowStockItem>> GetLowStockAsync(int? categoryId, CancellationToken ct = default)
    {
        await using var conn = await OpenAsync(ct);
        await using var cmd = new SqlCommand("dbo.usp_LowStockReport", conn)
        {
            CommandType = CommandType.StoredProcedure
        };
        cmd.Parameters.Add("@CategoryId", SqlDbType.Int).Value = (object?)categoryId ?? DBNull.Value;

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        var result = new List<LowStockItem>();

        while (await reader.ReadAsync(ct))
        {
            result.Add(new LowStockItem(
                reader.GetInt32(reader.GetOrdinal("ProductId")),
                reader.GetString(reader.GetOrdinal("Sku")),
                reader.GetString(reader.GetOrdinal("ProductName")),
                reader.GetString(reader.GetOrdinal("CategoryName")),
                reader.GetInt32(reader.GetOrdinal("ReorderLevel")),
                reader.GetInt32(reader.GetOrdinal("TotalQuantity")),
                reader.GetInt32(reader.GetOrdinal("StockMargin")),
                reader.GetInt64(reader.GetOrdinal("SeverityRank"))));
        }

        return result;
    }

    public async Task<string> GetMovementsJsonAsync(DateTime from, DateTime to, CancellationToken ct = default)
    {
        await using var conn = await OpenAsync(ct);
        await using var cmd = new SqlCommand("dbo.usp_GetProductMovementJson", conn)
        {
            CommandType = CommandType.StoredProcedure
        };
        cmd.Parameters.Add("@From", SqlDbType.DateTime2).Value = from;
        cmd.Parameters.Add("@To", SqlDbType.DateTime2).Value = to;

        var json = await cmd.ExecuteScalarAsync(ct);
        return json as string ?? "{\"movements\":[]}";
    }

    public async Task<ReceiveResult> ReceivePurchaseOrderAsync(int poId, string? movedBy, CancellationToken ct = default)
    {
        await using var conn = await OpenAsync(ct);
        await using var cmd = new SqlCommand("dbo.usp_ReceivePurchaseOrder", conn)
        {
            CommandType = CommandType.StoredProcedure
        };
        cmd.Parameters.Add("@PoId", SqlDbType.Int).Value = poId;
        cmd.Parameters.Add("@MovedBy", SqlDbType.NVarChar, 80).Value = (object?)movedBy ?? DBNull.Value;
        var linesParam = cmd.Parameters.Add("@LinesTotal", SqlDbType.Int);
        linesParam.Direction = ParameterDirection.Output;

        await cmd.ExecuteNonQueryAsync(ct);

        var linesTotal = linesParam.Value is int n ? n : 0;

        await using var check = new SqlCommand(
            "SELECT PoNumber, Status FROM dbo.PurchaseOrders WHERE PoId = @PoId;", conn);
        check.Parameters.Add("@PoId", SqlDbType.Int).Value = poId;
        await using var reader = await check.ExecuteReaderAsync(ct);

        if (await reader.ReadAsync(ct))
        {
            return new ReceiveResult(
                poId,
                reader.GetString(reader.GetOrdinal("PoNumber")),
                reader.GetString(reader.GetOrdinal("Status")),
                linesTotal);
        }

        return new ReceiveResult(poId, string.Empty, "UNKNOWN", linesTotal);
    }

    public async Task<AdjustStockResult> AdjustStockAsync(AdjustStockRequest request, CancellationToken ct = default)
    {
        await using var conn = await OpenAsync(ct);
        await using var cmd = new SqlCommand("dbo.usp_AdjustStock", conn)
        {
            CommandType = CommandType.StoredProcedure
        };
        cmd.Parameters.Add("@ProductId", SqlDbType.Int).Value = request.ProductId;
        cmd.Parameters.Add("@WarehouseId", SqlDbType.Int).Value = request.WarehouseId;
        cmd.Parameters.Add("@QtyChange", SqlDbType.Int).Value = request.QtyChange;
        cmd.Parameters.Add("@Reason", SqlDbType.NVarChar, 200).Value = (object?)request.Reason ?? DBNull.Value;
        cmd.Parameters.Add("@MovedBy", SqlDbType.NVarChar, 80).Value = (object?)request.MovedBy ?? DBNull.Value;
        var newQtyParam = cmd.Parameters.Add("@NewQuantity", SqlDbType.Int);
        newQtyParam.Direction = ParameterDirection.Output;

        await cmd.ExecuteNonQueryAsync(ct);

        // Mirror dbo.usp_AdjustStock: 'ADJUST' when the reason mentions it, else IN/OUT by sign.
        var movementType =
            request.Reason is not null && request.Reason.Contains("adjust", StringComparison.OrdinalIgnoreCase)
                ? "ADJUST"
                : request.QtyChange > 0 ? "IN" : "OUT";

        return new AdjustStockResult(
            request.ProductId,
            request.WarehouseId,
            newQtyParam.Value is int q ? q : 0,
            movementType);
    }
}
