using Inventory.Api.Data;
using Inventory.Api.Models;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("Inventory")
    ?? Environment.GetEnvironmentVariable("CONNECTION_STRING")
    ?? "Server=(localdb)\\MSSQLLocalDB;Database=InventoryDemo;Integrated Security=True;TrustServerCertificate=True";

builder.Services.AddSingleton(new InventoryRepository(connectionString));

var app = builder.Build();

/* Turn expected database validation errors (THROW / constraint violations)
   into HTTP 400 problem+json instead of a raw 500. */
app.UseExceptionHandler(errorApp =>
{
    errorApp.Run(async context =>
    {
        var feature = context.Features.Get<IExceptionHandlerFeature>();
        var error = feature?.Error;

        var isValidationError = error is SqlException sql &&
            (sql.Number is >= 50000 and < 51000 or 547 or 2601 or 2627);

        context.Response.StatusCode = isValidationError
            ? StatusCodes.Status400BadRequest
            : StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/problem+json";

        if (isValidationError && error is SqlException valid)
        {
            await context.Response.WriteAsJsonAsync(new
            {
                type = "https://tools.ietf.org/html/rfc9110#section-15.5.1",
                title = "Database validation error",
                status = 400,
                detail = valid.Message,
                sqlErrorNumber = valid.Number
            });
        }
        else
        {
            await context.Response.WriteAsJsonAsync(new
            {
                type = "https://tools.ietf.org/html/rfc9110#section-15.6.1",
                title = "Unexpected error",
                status = 500,
                detail = error?.Message
            });
        }
    });
});

app.MapGet("/", () => Results.Ok(new
{
    service = "Inventory API",
    storedProcedures = new[]
    {
        "usp_LowStockReport", "usp_GetProductMovementJson",
        "usp_ReceivePurchaseOrder", "usp_AdjustStock"
    },
    endpoints = new[]
    {
        "GET  /products",
        "GET  /stock/{warehouseId}",
        "GET  /reports/low-stock?categoryId=",
        "GET  /reports/movements?from=&to=",
        "POST /purchase-orders/{id}/receive?movedBy=",
        "POST /stock/adjust"
    }
}));

app.MapGet("/health", async (InventoryRepository repo, CancellationToken ct) =>
{
    var products = await repo.GetProductsAsync(ct);
    return Results.Ok(new { status = "healthy", productCount = products.Count });
});

app.MapGet("/products", async (InventoryRepository repo, CancellationToken ct) =>
    Results.Ok(await repo.GetProductsAsync(ct)));

app.MapGet("/stock/{warehouseId:int}", async (int warehouseId, InventoryRepository repo, CancellationToken ct) =>
    Results.Ok(await repo.GetStockAsync(warehouseId, ct)));

app.MapGet("/reports/low-stock", async (int? categoryId, InventoryRepository repo, CancellationToken ct) =>
    Results.Ok(await repo.GetLowStockAsync(categoryId, ct)));

app.MapGet("/reports/movements", async (DateTime? from, DateTime? to, InventoryRepository repo, CancellationToken ct) =>
{
    var fromDate = from ?? DateTime.UtcNow.AddDays(-30);
    var toDate = to ?? DateTime.UtcNow.AddDays(1);
    var json = await repo.GetMovementsJsonAsync(fromDate, toDate, ct);
    return Results.Content(json, "application/json");
});

app.MapPost("/purchase-orders/{id:int}/receive", async (int id, string? movedBy, InventoryRepository repo, CancellationToken ct) =>
    Results.Ok(await repo.ReceivePurchaseOrderAsync(id, movedBy, ct)));

app.MapPost("/stock/adjust", async (AdjustStockRequest request, InventoryRepository repo, CancellationToken ct) =>
    Results.Ok(await repo.AdjustStockAsync(request, ct)));

app.Run();
