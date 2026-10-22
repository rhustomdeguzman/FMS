using Microsoft.Data.SqlClient;

namespace FundManagementAPI.Data;

public interface ISqlDataAccess
{
    Task<IReadOnlyList<T>> QueryAsync<T>(
        string storedProcedure,
        IEnumerable<SqlParameter> parameters,
        Func<SqlDataReader, T> map,
        CancellationToken cancellationToken = default);

    Task<T?> QuerySingleAsync<T>(
        string storedProcedure,
        IEnumerable<SqlParameter> parameters,
        Func<SqlDataReader, T> map,
        CancellationToken cancellationToken = default);

    Task ExecuteAsync(
        string storedProcedure,
        IEnumerable<SqlParameter> parameters,
        CancellationToken cancellationToken = default);
}
