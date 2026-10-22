using FundManagementAPI.Models;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text;

namespace FundManagementAPI.Services;

public sealed class RequestPrintService(IWebHostEnvironment environment)
{
    private readonly IWebHostEnvironment _environment = environment;
    public async Task<byte[]> BuildPdfAsync(
        CashAdvanceWorkflowRequestDto request,
        CashAdvanceHistoryDto approvalEvent,
        CancellationToken cancellationToken,
        bool requireHtmlRenderer = false,
        string? referenceNumber = null)
    {
        if (referenceNumber is not null)
            request = request with { RfpRequestNumber = referenceNumber };
        var renderRoot = Path.Combine(Path.GetTempPath(), "FundManagementAPI", "request-print");
        Directory.CreateDirectory(renderRoot);
        var pdfPath = Path.Combine(renderRoot, Guid.NewGuid().ToString("N") + ".pdf");
        var html = await BuildDepartmentApprovalPrintHtmlAsync(request, approvalEvent, cancellationToken);

        try
        {
            var renderedFromHtml = await TryRenderHtmlToPdfAsync(html, pdfPath, cancellationToken);
            if (renderedFromHtml)
            {
                return await System.IO.File.ReadAllBytesAsync(pdfPath, cancellationToken);
            }

            if (requireHtmlRenderer)
                throw new InvalidOperationException("Unable to render the request Print PDF. Install Edge or Chrome on the API server, or configure FMS_HTML_TO_PDF_BROWSER.");
            return BuildFallbackDepartmentApprovalPrintPdf(request, approvalEvent);
        }
        finally
        {
            TryDeleteFile(pdfPath);
        }
    }

    private async Task<string> BuildDepartmentApprovalPrintHtmlAsync(
        CashAdvanceWorkflowRequestDto request,
        CashAdvanceHistoryDto approvalEvent,
        CancellationToken cancellationToken)
    {
        var templatePath = Path.Combine(_environment.ContentRootPath, "Templates", "DepartmentApprovedRequest.html");
        var template = await System.IO.File.ReadAllTextAsync(templatePath, cancellationToken);
        var receiptTotal = request.ReceiptDetails.Sum(detail => detail.Amount);
        var dueDate = request.DueDate ?? request.AuditDate.AddDays(10);
        var tokens = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["ReferenceNumber"] = HtmlEncode(GetReferenceNumber(request)),
            ["Purpose"] = HtmlEncode(request.Purpose),
            ["RequestorName"] = HtmlEncode(request.RequestorName),
            ["Source"] = "RFP System",
            ["CreatedAt"] = HtmlEncode(FormatDateTime(request.AuditDate)),
            ["DueDate"] = HtmlEncode(FormatDate(dueDate)),
            ["DepartmentApprover"] = HtmlEncode(FormatDepartmentApprover(request, approvalEvent)),
            ["ReceiptRows"] = BuildReceiptDetailRowsHtml(request.ReceiptDetails),
            ["ReceiptTotal"] = HtmlEncode(FormatCurrency(receiptTotal)),
            ["GeneratedAt"] = HtmlEncode(FormatDateTime(GetAuditDate()))
        };

        foreach (var token in tokens)
        {
            template = template.Replace("{{" + token.Key + "}}", token.Value, StringComparison.OrdinalIgnoreCase);
        }

        return template;
    }

    private static string BuildReceiptDetailRowsHtml(IReadOnlyList<CashAdvanceReceiptDetailDto> receiptDetails)
    {
        if (receiptDetails.Count == 0)
        {
            return """<tr><td colspan="7" class="empty">No receipt details submitted.</td></tr>""";
        }

        var rows = new StringBuilder();
        foreach (var detail in receiptDetails)
        {
            rows.Append($"""
<tr>
  <td>{HtmlEncode(detail.Vendor)}</td>
  <td>{HtmlEncode(detail.Description)}</td>
  <td>{HtmlEncode(detail.Project)}</td>
  <td>{HtmlEncode(detail.ProfitCenter)}</td>
  <td class="amount">{HtmlEncode(FormatCurrency(detail.Amount))}</td>
  <td>{HtmlEncode(detail.InvoiceRef)}</td>
  <td>{HtmlEncode(detail.ExpenseType)}</td>
</tr>
""");
        }

        return rows.ToString();
    }

    internal static async Task<bool> TryRenderHtmlToPdfAsync(
        string html,
        string pdfPath,
        CancellationToken cancellationToken)
    {
        var browserPath = FindHtmlToPdfBrowserPath();
        if (browserPath is null)
        {
            return false;
        }

        var renderRoot = Path.Combine(Path.GetTempPath(), "FundManagementAPI", "pdf-render");
        Directory.CreateDirectory(renderRoot);
        var renderId = Guid.NewGuid().ToString("N");
        var htmlPath = Path.Combine(renderRoot, renderId + ".html");
        var userDataDirectory = Path.Combine(renderRoot, renderId + "-profile");

        try
        {
            await System.IO.File.WriteAllTextAsync(htmlPath, html, new UTF8Encoding(false), cancellationToken);
            Directory.CreateDirectory(userDataDirectory);

            var startInfo = new ProcessStartInfo(browserPath)
            {
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false
            };

            startInfo.ArgumentList.Add("--headless=new");
            startInfo.ArgumentList.Add("--disable-gpu");
            startInfo.ArgumentList.Add("--no-first-run");
            startInfo.ArgumentList.Add("--disable-background-networking");
            startInfo.ArgumentList.Add("--disable-extensions");
            startInfo.ArgumentList.Add("--no-pdf-header-footer");
            startInfo.ArgumentList.Add("--print-to-pdf-no-header");
            startInfo.ArgumentList.Add("--user-data-dir=" + userDataDirectory);
            startInfo.ArgumentList.Add("--print-to-pdf=" + pdfPath);
            startInfo.ArgumentList.Add(new Uri(htmlPath).AbsoluteUri);

            if (System.IO.File.Exists(pdfPath))
            {
                System.IO.File.Delete(pdfPath);
            }

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return false;
            }

            var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);

            try
            {
                await process.WaitForExitAsync(cancellationToken);
            }
            catch
            {
                TryKillProcess(process);
                throw;
            }

            await Task.WhenAll(outputTask, errorTask);

            return process.ExitCode == 0 &&
                System.IO.File.Exists(pdfPath) &&
                new FileInfo(pdfPath).Length > 0;
        }
        catch when (!cancellationToken.IsCancellationRequested)
        {
            return false;
        }
        finally
        {
            TryDeleteFile(htmlPath);
            TryDeleteDirectory(userDataDirectory);
        }
    }

    private static string? FindHtmlToPdfBrowserPath()
    {
        var candidates = new[]
        {
            Environment.GetEnvironmentVariable("FMS_HTML_TO_PDF_BROWSER"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Microsoft", "Edge", "Application", "msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft", "Edge", "Application", "msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "Edge", "Application", "msedge.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google", "Chrome", "Application", "chrome.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google", "Chrome", "Application", "chrome.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Google", "Chrome", "Application", "chrome.exe")
        };

        return candidates.FirstOrDefault(path => !string.IsNullOrWhiteSpace(path) && System.IO.File.Exists(path));
    }

    private static void TryKillProcess(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // Ignore cleanup failures; the request cancellation or render failure is already being handled.
        }
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (System.IO.File.Exists(path))
            {
                System.IO.File.Delete(path);
            }
        }
        catch
        {
            // Best-effort cleanup only.
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch
        {
            // Best-effort cleanup only.
        }
    }

    private static byte[] BuildFallbackDepartmentApprovalPrintPdf(
        CashAdvanceWorkflowRequestDto request,
        CashAdvanceHistoryDto approvalEvent)
    {
        var dueDate = request.DueDate ?? request.AuditDate.AddDays(10);
        var lines = new List<string>
        {
            "DEPARTMENT APPROVED REQUEST",
            $"Requestor: {request.RequestorName}",
            "Source: RFP System",
            $"Ref No: {GetReferenceNumber(request)}",
            $"Created: {FormatDateTime(request.AuditDate)}",
            $"Due Date: {FormatDate(dueDate)}",
            $"Department Approver: {FormatDepartmentApprover(request, approvalEvent)}",
            "Receipt Details:"
        };

        if (request.ReceiptDetails.Count == 0)
        {
            lines.Add("No receipt details submitted.");
        }
        else
        {
            foreach (var detail in request.ReceiptDetails)
            {
                lines.Add($"{detail.Vendor} | {detail.Description} | {detail.InvoiceRef} | {FormatCurrency(detail.Amount)}");
            }
        }

        return BuildSimplePdf(lines);
    }

    private static byte[] BuildSimplePdf(IEnumerable<string> lines)
    {
        var contentBuilder = new StringBuilder();
        var y = 760;
        foreach (var line in lines.Where(line => line.Length > 0).Take(28))
        {
            var fontSize = line == "DEPARTMENT APPROVED REQUEST" || line == "ACKNOWLEDGEMENT RECEIPT" ? 16 : 11;
            contentBuilder.Append(CultureInfo.InvariantCulture, $"BT /F1 {fontSize} Tf 72 {y} Td ({EscapePdfText(line)}) Tj ET\n");
            y -= 24;
        }

        var content = contentBuilder.ToString();
        var objects = new[]
        {
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
            $"<< /Length {Encoding.ASCII.GetByteCount(content)} >>\nstream\n{content}endstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
        };

        var pdf = new StringBuilder("%PDF-1.4\n");
        var offsets = new List<int> { 0 };
        foreach (var item in objects.Select((value, index) => new { value, index }))
        {
            offsets.Add(Encoding.ASCII.GetByteCount(pdf.ToString()));
            pdf.Append(CultureInfo.InvariantCulture, $"{item.index + 1} 0 obj\n{item.value}\nendobj\n");
        }

        var xrefOffset = Encoding.ASCII.GetByteCount(pdf.ToString());
        pdf.Append(CultureInfo.InvariantCulture, $"xref\n0 {objects.Length + 1}\n");
        pdf.Append("0000000000 65535 f \n");
        foreach (var offset in offsets.Skip(1))
        {
            pdf.Append(CultureInfo.InvariantCulture, $"{offset:0000000000} 00000 n \n");
        }

        pdf.Append(CultureInfo.InvariantCulture, $"trailer\n<< /Size {objects.Length + 1} /Root 1 0 R >>\nstartxref\n{xrefOffset}\n%%EOF");
        return Encoding.ASCII.GetBytes(pdf.ToString());
    }

    private static string GetReferenceNumber(CashAdvanceWorkflowRequestDto request) =>
        string.IsNullOrWhiteSpace(request.RfpRequestNumber) ? request.RequestNumber : request.RfpRequestNumber;

    private static string FormatDepartmentApprover(CashAdvanceWorkflowRequestDto request, CashAdvanceHistoryDto approvalEvent)
    {
        var approverName = string.IsNullOrWhiteSpace(request.RequestorDepartmentApproverName)
            ? approvalEvent.ActorName
            : request.RequestorDepartmentApproverName;

        approverName = string.IsNullOrWhiteSpace(approverName)
            ? "Department approver"
            : approverName;

        return $"{approverName} on {FormatDateTime(approvalEvent.AuditDate)}";
    }

    private static string FormatCurrency(decimal amount) =>
        "PHP " + amount.ToString("N2", CultureInfo.InvariantCulture);

    private static string FormatDate(DateTime date) =>
        date.ToString("MMM dd, yyyy", CultureInfo.InvariantCulture);

    private static string FormatDateTime(DateTime date) =>
        date.ToString("MMM dd, yyyy hh:mm tt", CultureInfo.InvariantCulture);

    private static DateTime GetAuditDate() => DateTime.Now;

    private static string EscapePdfText(string value) =>
        value.Replace("\\", "\\\\").Replace("(", "\\(").Replace(")", "\\)");

    private static string HtmlEncode(string value) => WebUtility.HtmlEncode(value);
}
