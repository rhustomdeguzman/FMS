using System.Data;
using Microsoft.Data.SqlClient;

namespace FundManagementAPI.Data;

public sealed class SqlDataAccess : ISqlDataAccess
{
    private const string RequiredSetOptionsSql = """
        SET ANSI_NULLS ON;
        SET ANSI_PADDING ON;
        SET ANSI_WARNINGS ON;
        SET ARITHABORT ON;
        SET CONCAT_NULL_YIELDS_NULL ON;
        SET QUOTED_IDENTIFIER ON;
        SET NUMERIC_ROUNDABORT OFF;
        """;

    private readonly string _connectionString;

    public SqlDataAccess(IConfiguration configuration)
    {
        _connectionString = configuration.GetConnectionString("FundManagementDatabase")
            ?? throw new InvalidOperationException("Connection string 'FundManagementDatabase' was not configured.");
    }

    public async Task<IReadOnlyList<T>> QueryAsync<T>(
        string storedProcedure,
        IEnumerable<SqlParameter> parameters,
        Func<SqlDataReader, T> map,
        CancellationToken cancellationToken = default)
    {
        var results = new List<T>();

        await using var connection = new SqlConnection(_connectionString);
        await using var command = CreateCommand(connection, storedProcedure, parameters);

        await OpenConfiguredConnectionAsync(connection, cancellationToken);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            results.Add(map(reader));
        }

        return results;
    }

    public async Task<T?> QuerySingleAsync<T>(
        string storedProcedure,
        IEnumerable<SqlParameter> parameters,
        Func<SqlDataReader, T> map,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await using var command = CreateCommand(connection, storedProcedure, parameters);

        await OpenConfiguredConnectionAsync(connection, cancellationToken);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        return await reader.ReadAsync(cancellationToken) ? map(reader) : default;
    }

    public async Task ExecuteAsync(
        string storedProcedure,
        IEnumerable<SqlParameter> parameters,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(_connectionString);
        await using var command = CreateCommand(connection, storedProcedure, parameters);

        await OpenConfiguredConnectionAsync(connection, cancellationToken);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task OpenConfiguredConnectionAsync(
        SqlConnection connection,
        CancellationToken cancellationToken)
    {
        await connection.OpenAsync(cancellationToken);

        await using var setOptionsCommand = new SqlCommand(RequiredSetOptionsSql, connection)
        {
            CommandType = CommandType.Text
        };

        await setOptionsCommand.ExecuteNonQueryAsync(cancellationToken);
    }

    private static SqlCommand CreateCommand(
        SqlConnection connection,
        string storedProcedure,
        IEnumerable<SqlParameter> parameters)
    {
        var command = new SqlCommand(storedProcedure, connection)
        {
            CommandType = CommandType.StoredProcedure
        };

        command.Parameters.AddRange(parameters.ToArray());
        return command;
    }
}
