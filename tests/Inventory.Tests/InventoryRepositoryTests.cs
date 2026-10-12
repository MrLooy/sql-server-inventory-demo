using Inventory.Api.Data;
using Inventory.Api.Models;
using Microsoft.Data.SqlClient;
using Xunit;

namespace Inventory.Tests;

public sealed class InventoryRepositoryTests : IClassFixture<DatabaseFixture>
{
    private readonly DatabaseFixture _fixture;
    private readonly InventoryRepository _repository;

    public InventoryRepositoryTests(DatabaseFixture fixture)
    {
        _fixture = fixture;
        _repository = new InventoryRepository(fixture.ConnectionString);
    }

    [Fact]
    public async Task GetProducts_Returns_The_Seeded_Catalog()
    {
        await _fixture.ResetAsync();

        var products = await _repository.GetProductsAsync();

        Assert.Equal(8, products.Count);
        Assert.Contains(products, p => p.Sku == "SKU-1001" && p.Name == "Laptop Pro 14" && p.UnitPrice == 3500.00m);
    }

    [Fact]
    public async Task GetLowStock_Reports_Monitor_With_Negative_StockMargin()
    {
        await _fixture.ResetAsync();

        var lowStock = await _repository.GetLowStockAsync(null);

        var item = Assert.Single(lowStock);
        Assert.Equal("SKU-2003", item.Sku);
        Assert.Equal(6, item.ReorderLevel);
        Assert.Equal(3, item.TotalQuantity);
        Assert.Equal(-3, item.StockMargin);
        Assert.Equal(1, item.SeverityRank);
    }

    [Fact]
    public async Task AdjustStock_Valid_Increase_Updates_Quantity_And_Logs_Movement()
    {
        await _fixture.ResetAsync();

        var result = await _repository.AdjustStockAsync(new AdjustStockRequest(
            ProductId: 1, WarehouseId: 1, QtyChange: 7, Reason: "Cycle count", MovedBy: "tester"));

        Assert.Equal(19, result.NewQuantity); // seed has 12 in warehouse 1
        Assert.Equal("IN", result.MovementType);

        var stock = await _repository.GetStockAsync(1);
        Assert.Equal(19, stock.Single(s => s.ProductId == 1).Quantity);
    }

    [Fact]
    public async Task AdjustStock_Below_Zero_Throws_Business_Error()
    {
        await _fixture.ResetAsync();

        var ex = await Assert.ThrowsAsync<SqlException>(() =>
            _repository.AdjustStockAsync(new AdjustStockRequest(
                ProductId: 5, WarehouseId: 1, QtyChange: -9999, Reason: "bad", MovedBy: "tester")));

        Assert.Equal(50013, ex.Number); // 'Adjustment would result in negative stock.'
    }

    [Fact]
    public async Task ReceivePurchaseOrder_Marks_Received_And_Increases_Stock()
    {
        await _fixture.ResetAsync();

        var result = await _repository.ReceivePurchaseOrderAsync(2, "tester");

        Assert.Equal("PO-1001", result.PoNumber);
        Assert.Equal("RECEIVED", result.Status);
        Assert.Equal(2, result.LinesTotal);

        var stock = await _repository.GetStockAsync(1);
        Assert.Equal(17, stock.Single(s => s.ProductId == 1).Quantity); // 12 + 5
        Assert.Equal(7, stock.Single(s => s.ProductId == 5).Quantity);  // 3 + 4
    }

    [Fact]
    public async Task ReceivePurchaseOrder_On_Unknown_Id_Throws()
    {
        await _fixture.ResetAsync();

        var ex = await Assert.ThrowsAsync<SqlException>(() =>
            _repository.ReceivePurchaseOrderAsync(999, "tester"));

        Assert.Equal(50001, ex.Number); // 'Purchase order not found.'
    }

    [Fact]
    public async Task GetMovementsJson_Returns_A_Movements_Document()
    {
        await _fixture.ResetAsync();

        var json = await _repository.GetMovementsJsonAsync(DateTime.UtcNow.AddYears(-5), DateTime.UtcNow.AddDays(1));

        Assert.Contains("movements", json);
        Assert.Contains("SKU-1001", json);
    }

    [Fact]
    public async Task Inserting_Products_Fires_The_Audit_Trigger()
    {
        await _fixture.ResetAsync();

        await using var connection = new SqlConnection(_fixture.ConnectionString);
        await connection.OpenAsync();
        await using var command = new SqlCommand("SELECT COUNT(*) FROM dbo.AuditLog WHERE TableName = 'Products';", connection);
        var auditRows = Convert.ToInt32(await command.ExecuteScalarAsync());

        Assert.Equal(8, auditRows); // one row per seeded product
    }
}
