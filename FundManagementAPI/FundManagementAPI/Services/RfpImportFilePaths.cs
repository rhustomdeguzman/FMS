namespace FundManagementAPI.Services;

public static class RfpImportFilePaths
{
    public static string ValidateFileName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name is "." or ".." || name.Length > 260
            || name.IndexOfAny(['/', '\\', ':']) >= 0 || name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0
            || name.EndsWith('.') || name.EndsWith(' '))
            throw new InvalidOperationException("Invalid RFP source filename.");
        return name;
    }

    public static async Task CopyOnceAsync(string source, string destination, CancellationToken cancellationToken)
    {
        // Completed copies survive database failures so a retry can register them later.
        if (File.Exists(destination)) return;
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        var temporary = destination + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            await using (var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true))
            await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true))
                await input.CopyToAsync(output, cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            try { File.Move(temporary, destination, overwrite: false); }
            catch (IOException) when (File.Exists(destination)) { /* Another worker completed the same copy. */ }
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
