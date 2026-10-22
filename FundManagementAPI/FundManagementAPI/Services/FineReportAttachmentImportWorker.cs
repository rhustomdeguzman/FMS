using System.Data;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.Data.SqlClient;

namespace FundManagementAPI.Services;

public sealed class FineReportAttachmentImportWorker(
    IConfiguration configuration, IWebHostEnvironment environment,
    ILogger<FineReportAttachmentImportWorker> logger) : BackgroundService
{
    private static readonly FileExtensionContentTypeProvider ContentTypes = new();

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!configuration.GetValue("RfpAttachmentImport:Enabled", true)) return;
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await ImportPendingAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception error) { logger.LogError(error, "RFP attachment import failed; it will retry in 30 seconds."); }
            try { await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
        }
    }

    private async Task ImportPendingAsync(CancellationToken cancellationToken)
    {
        await using var connection = new SqlConnection(configuration.GetConnectionString("FundManagementDatabase"));
        await connection.OpenAsync(cancellationToken);
        var pending = new List<(int Id, int RequestId, string FileName)>();
        await using (var command = new SqlCommand("dbo.sp_RfpAttachmentImports_GetPending", connection) { CommandType = CommandType.StoredProcedure })
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
            while (await reader.ReadAsync(cancellationToken))
                pending.Add((reader.GetInt32(0), reader.GetInt32(1), reader.GetString(2)));

        var sourceRoot = configuration["RfpAttachmentImport:SourceRoot"]
            ?? @"D:\xampp\htdocs\NewORFPv3\public\Request For Payment";
        var uploadsRoot = Path.Combine(environment.ContentRootPath, "Uploads");
        foreach (var item in pending)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                // A database filename must name a file directly inside the RFP source directory.
                var name = RfpImportFilePaths.ValidateFileName(item.FileName);
                var source = Path.Combine(sourceRoot, name);
                var storedName = $"rfp-import-{item.Id}{Path.GetExtension(name)}";
                var relativePath = $"liquidation/{item.RequestId}/{storedName}";
                var destination = Path.Combine(uploadsRoot, "liquidation", item.RequestId.ToString(), storedName);
                await RfpImportFilePaths.CopyOnceAsync(source, destination, cancellationToken);
                ContentTypes.TryGetContentType(name, out var contentType);
                await using var complete = new SqlCommand("dbo.sp_RfpAttachmentImports_Complete", connection) { CommandType = CommandType.StoredProcedure };
                complete.Parameters.Add("@ImportId", SqlDbType.Int).Value = item.Id;
                complete.Parameters.Add("@StoredFileName", SqlDbType.NVarChar, 260).Value = storedName;
                complete.Parameters.Add("@RelativePath", SqlDbType.NVarChar, 500).Value = relativePath;
                complete.Parameters.Add("@ContentType", SqlDbType.NVarChar, 100).Value = contentType ?? "application/octet-stream";
                complete.Parameters.Add("@FileSizeBytes", SqlDbType.BigInt).Value = new FileInfo(destination).Length;
                await complete.ExecuteNonQueryAsync(cancellationToken);
                logger.LogInformation("Imported RFP attachment {FileName} for request {RequestId}", name, item.RequestId);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
            catch (Exception error)
            {
                logger.LogError(error, "Unable to import RFP file {FileName} for request {RequestId}; it will retry.", item.FileName, item.RequestId);
            }
        }
    }
}
