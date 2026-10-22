using System.Data;
using FundManagementAPI.Models;
using FundManagementAPI.Repositories;
using Microsoft.Data.SqlClient;

namespace FundManagementAPI.Services;

public sealed class RfpAttachmentService(IWebHostEnvironment environment, IConfiguration configuration,
    RequestPrintService printer, ILogger<RfpAttachmentService> logger)
{
    private const string DefaultRoot = @"\\192.168.127.72\d$\xampp\htdocs\NewORFPv3\public\Request For Payment";

    public async Task<PublishedFiles> PublishAsync(SqlConnection connection, SqlTransaction transaction,
        int requestId, string rfNumber, string folder, CancellationToken cancellationToken)
    {
        var root = Path.GetFullPath(configuration["RfpAttachments:DestinationRoot"] ?? DefaultRoot);
        var target = root;
        var publication = new PublishedFiles(logger);
        try
        {
            var (company, payee, ownerId, department) = await LoadMetadataAsync(connection, transaction, requestId, rfNumber, cancellationToken);
            var snapshot = await LoadPrintRequestAsync(connection, transaction, requestId, ownerId, department, cancellationToken);
            var approval = snapshot.History.LastOrDefault(item => item.Action is "approved_by_department_head" or "rfp_created" or "rfp_waived")
                ?? throw new InvalidOperationException("The department approval is missing from the request Print data.");
            var pdf = await printer.BuildPdfAsync(snapshot, approval, cancellationToken,
                requireHtmlRenderer: true, referenceNumber: snapshot.RequestNumber);
            var attachments = await LoadAttachmentsAsync(connection, transaction, requestId, cancellationToken);
            if (!Directory.Exists(target))
                throw new InvalidOperationException("The shared Request For Payment directory is unavailable. Check the API account's access.");
            var usedNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string FileName(string original)
            {
                var duplicate = 1;
                string name;
                do { name = RfpFileNames.Build(rfNumber, company, payee, original, duplicate++); }
                while (!usedNames.Add(name) || File.Exists(ChildPath(target, name)));
                return name;
            }
            var printName = FileName(RfpFileNames.RfpNumber(rfNumber) + "D.pdf");
            var pdfPath = ChildPath(target, printName);
            await using (var file = new FileStream(pdfPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true))
            {
                publication.Track(pdfPath);
                await file.WriteAsync(pdf, cancellationToken);
            }
            await RegisterAsync(connection, transaction, folder, printName, cancellationToken);

            var uploadsRoot = Path.GetFullPath(Path.Combine(environment.ContentRootPath, "Uploads"));
            foreach (var attachment in attachments)
            {
                var source = ChildPath(uploadsRoot, attachment.RelativePath);
                var name = FileName(attachment.OriginalFileName);
                var destination = ChildPath(target, name);
                await using (var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true))
                await using (var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true))
                {
                    publication.Track(destination);
                    await input.CopyToAsync(output, cancellationToken);
                }
                await RegisterAsync(connection, transaction, folder, name, cancellationToken);
            }
            return publication;
        }
        catch (Exception error)
        {
            publication.Dispose();
            if (error is IOException or UnauthorizedAccessException)
                throw new InvalidOperationException("Unable to copy RFP attachments to the shared Request For Payment folder. Check the API account's access and that the liquidation attachment files exist.", error);
            throw;
        }
    }

    private static async Task<(string Company, string Payee, int OwnerId, string Department)> LoadMetadataAsync(
        SqlConnection connection, SqlTransaction transaction, int id, string number, CancellationToken cancellationToken)
    {
        await using var command = new SqlCommand("dbo.sp_RfpAttachments_GetMetadata", connection, transaction) { CommandType = CommandType.StoredProcedure };
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
        command.Parameters.Add("@Number", SqlDbType.NVarChar, 50).Value = number;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) throw new InvalidOperationException("The generated RFP company or payee could not be loaded.");
        return (reader.GetString(reader.GetOrdinal("CompanyName")), reader.GetString(reader.GetOrdinal("PayeeName")),
            reader.GetInt32(reader.GetOrdinal("OwnerId")), reader.GetString(reader.GetOrdinal("Department")));
    }

    private static async Task<CashAdvanceWorkflowRequestDto> LoadPrintRequestAsync(SqlConnection connection, SqlTransaction transaction,
        int id, int ownerId, string department, CancellationToken cancellationToken)
    {
        await using var command = new SqlCommand("dbo.sp_CashAdvanceRequests_GetForUser", connection, transaction) { CommandType = CommandType.StoredProcedure };
        command.Parameters.Add("@UserId", SqlDbType.Int).Value = ownerId;
        command.Parameters.Add("@Role", SqlDbType.NVarChar, 50).Value = "requestor";
        command.Parameters.Add("@Department", SqlDbType.NVarChar, 100).Value = department;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
            if (reader.GetInt32(reader.GetOrdinal("CashAdvanceRequestId")) == id)
                return CashAdvanceRepository.MapCashAdvanceWorkflowRequest(reader);
        throw new InvalidOperationException("Unable to load the approved request using the Print data source.");
    }

    private static async Task<List<StoredFileDownload>> LoadAttachmentsAsync(SqlConnection connection, SqlTransaction transaction,
        int id, CancellationToken cancellationToken)
    {
        var attachments = new List<StoredFileDownload>();
        await using var command = new SqlCommand("dbo.sp_RfpAttachments_GetForRequest", connection, transaction) { CommandType = CommandType.StoredProcedure };
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
            attachments.Add(new StoredFileDownload(reader.GetInt32(0), reader.GetString(1), reader.GetString(2), reader.GetString(3)));
        return attachments;
    }

    private static async Task RegisterAsync(SqlConnection connection, SqlTransaction transaction, string folder, string name, CancellationToken cancellationToken)
    {
        await using var command = new SqlCommand("dbo.sp_RfpAttachments_Register", connection, transaction) { CommandType = CommandType.StoredProcedure };
        command.Parameters.Add("@Folder", SqlDbType.VarChar, 500).Value = folder;
        command.Parameters.Add("@FileName", SqlDbType.VarChar, 1000).Value = name;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static string ChildPath(string root, string relative)
    {
        var path = Path.GetFullPath(Path.Combine(root, relative));
        if (!path.StartsWith(Path.TrimEndingDirectorySeparator(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Invalid RFP attachment path.");
        return path;
    }

    public sealed class PublishedFiles(ILogger logger) : IDisposable
    {
        private readonly List<string> files = [];
        private bool completed;
        public void Track(string path) => files.Add(path);
        public void Complete() => completed = true;
        public void Dispose()
        {
            if (completed) return;
            foreach (var file in files)
                try { File.Delete(file); } catch (Exception error) { logger.LogError(error, "Unable to clean failed RFP publication file {File}", file); }
        }
    }
}
