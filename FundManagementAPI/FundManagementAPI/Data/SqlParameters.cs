using System.Data;
using Microsoft.Data.SqlClient;

namespace FundManagementAPI.Data;

public static class SqlParameters
{
    public static SqlParameter Int(string name, int value) => new(name, value);

    public static SqlParameter NullableInt(string name, int? value) =>
        new(name, value ?? (object)DBNull.Value) { SqlDbType = SqlDbType.Int };

    public static SqlParameter BigInt(string name, long? value) =>
        new(name, value ?? (object)DBNull.Value) { SqlDbType = SqlDbType.BigInt };

    public static SqlParameter Bit(string name, bool value) => new(name, value);

    public static SqlParameter Decimal(string name, decimal value) => new(name, value);

    public static SqlParameter NullableDecimal(string name, decimal? value) =>
        new(name, value ?? (object)DBNull.Value)
        {
            SqlDbType = SqlDbType.Decimal,
            Precision = 19,
            Scale = 4
        };

    public static SqlParameter NullableDateTime(string name, DateTime? value) =>
        new(name, value ?? (object)DBNull.Value) { SqlDbType = SqlDbType.DateTime };

    public static SqlParameter NVarChar(string name, string? value, int size) =>
        new(name, value ?? (object)DBNull.Value) { Size = size };
}
