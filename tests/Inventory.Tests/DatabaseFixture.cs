using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Xunit;

namespace Inventory.Tests;

/// <summary>
/// Shared fixture: resolves a connection string, and (re)builds the demo
/// database by running the repository's SQL scripts in order. Works against
/// LocalDB locally and against a SQL Server container in CI.
/// </summary>
public sealed class DatabaseFixture : IAsyncLifetime
{
    private static readonly Regex GoSeparator =
        new(@"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);

    private readonly string _scriptsDirectory;

    public string ConnectionString { get; }

    public DatabaseFixture()
    {
        ConnectionString =
            Environment.GetEnvironmentVariable("ConnectionStrings__Inventory")
            ?? Environment.GetEnvironmentVariable("CONNECTION_STRING")
            ?? "Server=(localdb)\\MSSQLLocalDB;Database=InventoryDemo;Integrated Security=True;TrustServerCertificate=True";

        _scriptsDirectory = Path.Combine(AppContext.BaseDirectory, "db");
    }

    public Task InitializeAsync() => RunScriptsAsync(
        "01_schema.sql", "02_indexes.sql", "03_views.sql", "04_functions.sql",
        "05_procedures.sql", "06_triggers.sql", "07_seed.sql");

    public Task DisposeAsync() => Task.CompletedTask;

    /// <summary>Re-runs the seed script to restore deterministic data between tests.</summary>
    public Task ResetAsync() => RunScriptsAsync("07_seed.sql");

    /// <summary>Scripts run against master; each file starts with its own USE.</summary>
    private string MasterConnectionString()
    {
        var builder = new SqlConnectionStringBuilder(ConnectionString) { InitialCatalog = "master" };
        return builder.ConnectionString;
    }

    private async Task RunScriptsAsync(params string[] files)
    {
        foreach (var file in files)
        {
            var path = Path.Combine(_scriptsDirectory, file);
            var script = await File.ReadAllTextAsync(path);

            // One connection per file so USE statements persist across its batches.
            await using var connection = await OpenWithRetryAsync();
            foreach (var batch in GoSeparator.Split(script))
            {
                if (string.IsNullOrWhiteSpace(batch))
                {
                    continue;
                }

                await using var command = new SqlCommand(batch, connection) { CommandTimeout = 180 };
                await command.ExecuteNonQueryAsync();
            }
        }
    }

    private async Task<SqlConnection> OpenWithRetryAsync()
    {
        Exception? lastError = null;
        for (var attempt = 0; attempt < 30; attempt++)
        {
            try
            {
                var connection = new SqlConnection(MasterConnectionString());
                await connection.OpenAsync();
                return connection;
            }
            catch (SqlException ex)
            {
                lastError = ex;
                await Task.Delay(TimeSpan.FromSeconds(2));
            }
        }

        throw new InvalidOperationException("Could not connect to SQL Server in time.", lastError);
    }
}
