using FundManagementAPI.Services;

static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
foreach (var invalid in new[] { "", "..", "../invoice.pdf", @"..\invoice.pdf", @"D:\invoice.pdf", "invoice.pdf:stream", "invoice.pdf.", "invoice.pdf " })
{
    try { RfpImportFilePaths.ValidateFileName(invalid); throw new Exception("Unsafe filename accepted: " + invalid); }
    catch (InvalidOperationException) { }
}
Check(RfpImportFilePaths.ValidateFileName("[RFP123] invoice 1.pdf") == "[RFP123] invoice 1.pdf", "Valid filename changed.");
var root = Path.GetFullPath(Path.Combine("tmp", "rfp-import-checks", Guid.NewGuid().ToString("N")));
Directory.CreateDirectory(root);
var source = Path.Combine(root, "source.pdf");
var target = Path.Combine(root, "liquidation", "123", "rfp-import-1.pdf");
var contents = Enumerable.Range(0, 200000).Select(index => (byte)(index % 251)).ToArray();
await File.WriteAllBytesAsync(source, contents);
await Task.WhenAll(Enumerable.Range(0, 4).Select(_ => RfpImportFilePaths.CopyOnceAsync(source, target, CancellationToken.None)));
Check((await File.ReadAllBytesAsync(target)).SequenceEqual(contents), "Concurrent copies corrupted the attachment.");
Check(!Directory.EnumerateFiles(Path.GetDirectoryName(target)!, "*.tmp").Any(), "Temporary copies were left behind.");
File.Delete(source);
await RfpImportFilePaths.CopyOnceAsync(source, target, CancellationToken.None);
Check((await File.ReadAllBytesAsync(target)).SequenceEqual(contents), "Retry must preserve an already copied attachment even if the source is gone.");
var missingTarget = Path.Combine(root, "liquidation", "123", "missing.pdf");
try { await RfpImportFilePaths.CopyOnceAsync(source, missingTarget, CancellationToken.None); throw new Exception("Missing source accepted."); }
catch (FileNotFoundException) { }
Check(!File.Exists(missingTarget), "Missing source created a destination file.");
await File.WriteAllBytesAsync(source, contents);
using var cancelled = new CancellationTokenSource();
cancelled.Cancel();
try { await RfpImportFilePaths.CopyOnceAsync(source, missingTarget, cancelled.Token); throw new Exception("Cancellation ignored."); }
catch (OperationCanceledException) { }
Check(!File.Exists(missingTarget) && !Directory.EnumerateFiles(Path.GetDirectoryName(target)!, "*.tmp").Any(), "Cancelled copy left incomplete files.");
Console.WriteLine("Passed: filename validation, byte preservation, concurrent copying, retry, missing source, cancellation and temporary-file cleanup.");
