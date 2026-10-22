using System.Globalization;
using FundManagementAPI.Models;
using FundManagementAPI.Repositories;

namespace FundManagementAPI.Services;

public sealed class FineReportSignInService(ICashAdvanceRepository repository)
{
    public async Task<AppUserDto?> GetUserAsync(string? cookieUserId, CancellationToken cancellationToken)
    {
        if (!int.TryParse(cookieUserId, NumberStyles.None, CultureInfo.InvariantCulture, out var userId) || userId <= 0)
            return null;

        // Legacy integration: the upstream application supplies the FMS account ID.
        // An unsigned numeric cookie identifies an account but cannot prove identity.
        var users = await repository.GetAppUsersAsync(false, cancellationToken);
        return users.SingleOrDefault(user => user.UserId == userId && user.IsActive);
    }
}
