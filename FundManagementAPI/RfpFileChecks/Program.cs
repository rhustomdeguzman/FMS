using System.Text.Json;
using System.Text.RegularExpressions;
using FundManagementAPI.Models;
using FundManagementAPI.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Logging.Abstractions;

static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
var folders = Enumerable.Range(0, 1000).Select(_ => RfpFileNames.NewFolder()).ToArray();
Check(folders.Distinct().Count() == folders.Length && folders.All(folder => Regex.IsMatch(folder, "^Cash_Advance_[a-zA-Z0-9]{32}$")), "Folder identifiers must be unique and alphanumeric.");
var expected = "[RFP52807] [CATHAY LAND, INC.] [MERALCO] [Requestor] - RFP52807D.pdf";
Check(RfpFileNames.Build("52807", "CATHAY LAND, INC.", "MERALCO", "RFP52807D.pdf") == expected, "Generated RF number must appear in the prefix and PDF filename.");
Check(RfpFileNames.Build("RFP52807", "CATHAY LAND, INC.", "MERALCO", "bill.pdf", 2).EndsWith("bill (2).pdf"), "Duplicate attachment names must stay unique.");
var safe = RfpFileNames.Build("52807", "A/B", "Payee:Name", "invoice?.pdf");
Check(!safe.Any(character => Path.GetInvalidFileNameChars().Contains(character)), "Filename must be safe on Windows.");
Check(RfpFileNames.Build("52807", new string('C', 500), new string('P', 500), new string('F', 500) + ".pdf").Length <= 255, "Filename must fit a filesystem component.");

var qaRoot = Path.GetFullPath(Path.Combine("tmp", "pdfs", "rfp-file-checks"));
Directory.CreateDirectory(qaRoot);
var failedFile = Path.Combine(qaRoot, "failed-test.txt");
var existingFile = Path.Combine(qaRoot, "existing-test.txt");
await File.WriteAllTextAsync(existingFile, "existing attachment");
await File.WriteAllTextAsync(failedFile, "test");
using (var publication = new RfpAttachmentService.PublishedFiles(NullLogger.Instance))
    publication.Track(failedFile);
Check(!File.Exists(failedFile) && Directory.Exists(qaRoot) && File.Exists(existingFile), "Failed publication must preserve the shared directory and existing files.");
var committedFile = Path.Combine(qaRoot, "committed-test.txt");
await File.WriteAllTextAsync(committedFile, "test");
using (var publication = new RfpAttachmentService.PublishedFiles(NullLogger.Instance))
{
    publication.Track(committedFile);
    publication.Complete();
}
Check(File.Exists(committedFile), "Committed publication must keep its files.");
File.Delete(committedFile);
File.Delete(existingFile);

var request = JsonSerializer.Deserialize<CashAdvanceWorkflowRequestDto>("""
{
 "CashAdvanceRequestId": 1, "RequestNumber": "RFP-00124", "RfpRequestNumber": "52807", "CompanyId": 1,
 "RequestType": "cash_advance", "SourceSystem": "RFP System", "Amount": 10000, "RemainingAmount": 0,
 "AmountSpent": 13000, "ExcessAmount": 3000, "Purpose": "Reimbursement for Excess amount in CA-124",
 "Department": "MIS", "Status": "pending_rfp_attachment", "RequestorUserId": 1,
 "RequestorName": "Sample Requestor", "RequestorDepartmentApproverName": "Sample Approver",
 "CurrentOwnerUserId": 1, "CurrentOwnerName": "Sample Requestor", "CurrentOwnerDepartment": "MIS",
 "AuditDate": "2026-10-05T09:00:00", "DueDate": "2026-10-15T00:00:00",
 "PendingTransfers": [], "TransferAllocations": [], "Attachments": [], "History": [],
 "PettyCashReceiptDetails": [], "PettyCashTransportationDetails": [],
 "ReceiptDetails": [
  { "ReceiptDetailId": 1, "VendorCode": "V1", "Vendor": "MERALCO", "Description": "Electricity expense",
    "ProjectCode": "HO", "Project": "Head Office", "ProfitCenterCode": "CC1", "ProfitCenter": "MIS",
    "Amount": 13000, "InvoiceRef": "INV-001", "ExpenseTypeCode": "2", "ExpenseType": "Operating expense",
    "AuditDate": "2026-10-05T09:00:00" }
 ]
}
""")!;
var approval = new CashAdvanceHistoryDto(1, "approved_by_department_head", 2, "Sample Approver", "MIS", 13000, "Approved", new DateTime(2026, 10, 5, 10, 0, 0));
var environment = new TestEnvironment { ContentRootPath = Path.GetFullPath("FundManagementAPI/FundManagementAPI") };
var renderer = new RequestPrintService(environment);
using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(45));
var pdf = await renderer.BuildPdfAsync(request, approval, timeout.Token,
    requireHtmlRenderer: true, referenceNumber: request.RequestNumber);
Check(request.RfpRequestNumber == "52807", "The original PDF reference must not replace the generated RFP number on the source request.");
Check(pdf.Length > 1000 && System.Text.Encoding.ASCII.GetString(pdf, 0, 5) == "%PDF-", "Print must produce a complete PDF using the HTML renderer.");
await File.WriteAllBytesAsync(Path.Combine(qaRoot, expected), pdf);
Console.WriteLine("RFP file checks passed: unique folders, generated RF naming, duplicates, safe names, cleanup, committed preservation, shared Print PDF.");

sealed class TestEnvironment : IWebHostEnvironment
{
    public string ApplicationName { get; set; } = "RfpFileChecks";
    public string EnvironmentName { get; set; } = "Development";
    public string ContentRootPath { get; set; } = "";
    public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    public string WebRootPath { get; set; } = "";
    public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
}
