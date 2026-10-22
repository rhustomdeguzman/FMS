namespace FundManagementAPI.Services;

public static class RfpFileNames
{
    public static string NewFolder() => "Cash_Advance_" + Guid.NewGuid().ToString("N");

    public static string RfpNumber(string number) => number.StartsWith("RFP", StringComparison.OrdinalIgnoreCase) ? number : "RFP" + number;

    public static string Build(string number, string company, string payee, string originalName, int duplicate = 1)
    {
        var prefix = $"[{Clean(RfpNumber(number), 32)}] [{Clean(company, 64)}] [{Clean(payee, 64)}] [Requestor] - ";
        var extension = Clean(Path.GetExtension(originalName), 20);
        var suffix = duplicate > 1 ? $" ({duplicate})" : "";
        var baseName = Clean(Path.GetFileNameWithoutExtension(originalName), Math.Max(1, 255 - prefix.Length - extension.Length - suffix.Length));
        return prefix + baseName + suffix + extension;
    }

    private static string Clean(string value, int limit)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var clean = new string(value.Select(character => invalid.Contains(character) || char.IsControl(character) ? '_' : character).ToArray()).Trim();
        if (clean.Length > limit) clean = clean[..limit].TrimEnd(' ');
        return clean;
    }
}
