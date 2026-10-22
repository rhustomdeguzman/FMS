using System.Data;
using System.Globalization;
using FundManagementAPI.Models;
using FundManagementAPI.Services;
using Microsoft.Data.SqlClient;

namespace FundManagementAPI.Repositories;

public sealed class RfpRepository(IConfiguration configuration, RfpAttachmentService attachments)
{
    public async Task DecideDepartmentAsync(int requestId, WorkflowDecisionRequest decision, CancellationToken cancellationToken)
    {
        await using var connection = new SqlConnection(configuration.GetConnectionString("FundManagementDatabase")
            ?? throw new InvalidOperationException("FundManagementDatabase is not configured."));
        await connection.OpenAsync(cancellationToken);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
        int statusId;
        decimal excessAmount;
        decimal baseAmount;
        await using (var state = new SqlCommand("dbo.sp_Rfp_GetDecisionState", connection, transaction) { CommandType = CommandType.StoredProcedure })
        {
            state.Parameters.Add("@Id", SqlDbType.Int).Value = requestId;
            await using var reader = await state.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
                throw new InvalidOperationException("Cash advance request was not found.");
            statusId = Convert.ToInt32(reader["StatusId"]);
            baseAmount = Convert.ToDecimal(reader["BaseAmount"]);
            excessAmount = statusId == 5
                ? (reader["ExcessAmount"] is DBNull ? 0 : Convert.ToDecimal(reader["ExcessAmount"]))
                : Math.Max((reader["AmountSpent"] is DBNull ? 0 : Convert.ToDecimal(reader["AmountSpent"])) - baseAmount, 0);
        }

        var createRfp = decision.Approved && (statusId is 1 or 5) && excessAmount > 0 &&
            (decision.RfpDecision is null || string.Equals(decision.RfpDecision.Trim(), "create", StringComparison.OrdinalIgnoreCase));
        if (createRfp && decision.CompanyId is not null)
        {
            await using var company = new SqlCommand("dbo.sp_Rfp_SetCompany", connection, transaction) { CommandType = CommandType.StoredProcedure };
            company.Parameters.Add("@CompanyId", SqlDbType.Int).Value = decision.CompanyId.Value;
            company.Parameters.Add("@Id", SqlDbType.Int).Value = requestId;
            await company.ExecuteNonQueryAsync(cancellationToken);
        }
        var request = createRfp
    ? await LoadRequestAsync(connection, transaction, requestId, excessAmount, cancellationToken)
    : null;

        await using (var approval = new SqlCommand("dbo.sp_Rfp_DepartmentDecision", connection, transaction) { CommandType = CommandType.StoredProcedure })
        {
            approval.Parameters.Add("@CashAdvanceRequestId", SqlDbType.Int).Value = requestId;
            approval.Parameters.Add("@ApproverUserId", SqlDbType.Int).Value = decision.UserId;
            approval.Parameters.Add("@Approved", SqlDbType.Bit).Value = decision.Approved;
            approval.Parameters.Add("@Notes", SqlDbType.NVarChar, 1000).Value = decision.Notes ?? (object)DBNull.Value;
            approval.Parameters.Add("@RfpDecision", SqlDbType.NVarChar, 20).Value = decision.RfpDecision ?? (object)DBNull.Value;
            await approval.ExecuteNonQueryAsync(cancellationToken);
        }
        RfpAttachmentService.PublishedFiles? publication = null;
        try
        {
            if (request is not null)
            {
                request.AttachmentFolder = RfpFileNames.NewFolder();
                var rfNumber = await CreateAsync(connection, transaction, request, cancellationToken);
                await using var link = new SqlCommand("dbo.sp_Rfp_LinkRequest", connection, transaction) { CommandType = CommandType.StoredProcedure };
                link.Parameters.Add("@Number", SqlDbType.NVarChar, 50).Value = rfNumber;
                link.Parameters.Add("@Id", SqlDbType.Int).Value = requestId;
                await link.ExecuteNonQueryAsync(cancellationToken);
                publication = await attachments.PublishAsync(connection, transaction, requestId, rfNumber, request.AttachmentFolder, cancellationToken);
            }
            await transaction.CommitAsync(cancellationToken);
            publication?.Complete();
        }
        finally { publication?.Dispose(); }
    }

    private static async Task<string> CreateAsync(SqlConnection connection, SqlTransaction transaction,
        CreateRfpRequest request, CancellationToken cancellationToken)
    {
        string rfNumber;
        await using (var header = CreateCommand(connection, transaction, "header"))
        {
            AddText(header, "@RequestorID", request.RequestorId, 100);
            AddText(header, "@CompanyID", request.CompanyId, 100);
            AddText(header, "@PayeeCode", request.PayeeCode, 100);
            AddText(header, "@PayeeName", request.PayeeName, 200);
            AddText(header, "@AltPayeeCode", "N/A", 100);
            AddText(header, "@PurOfDisbursement", request.PurposeOfDisbursement, 500);
            AddText(header, "@TypeOfExpense", "51", 100);
            AddText(header, "@Payment_Terms", "12", 100);
            AddText(header, "@TotalAmount", request.Details.Sum(row => row.Amount).ToString(CultureInfo.InvariantCulture), 100);
            AddText(header, "@Recommendation", request.Recommendation, 100);
            AddText(header, "@ReqGrp", request.RequestGroup, 100);
            AddText(header, "@AttachFolder", request.AttachmentFolder, 100);
            AddText(header, "@Request_Type", "Cash Advance", 100);
            await using var reader = await header.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken) || reader["RFNo"] is DBNull)
            {
                throw new InvalidOperationException("The RFP header procedure did not return RFNo.");
            }
            rfNumber = Convert.ToString(reader["RFNo"], CultureInfo.InvariantCulture)
                ?? throw new InvalidOperationException("The RFP number is missing.");
        }

        for (var index = 0; index < request.Details.Count; index++)
        {
            var row = request.Details[index];
            await using var detail = CreateCommand(connection, transaction, "Details");
            AddText(detail, "@RFNumber", rfNumber, 100);
            AddText(detail, "@Capex", row.Capex, 100);
            AddText(detail, "@CostCenter", row.CostCenter, 10);
            AddText(detail, "@Project", row.Project, 20);
            AddText(detail, "@BillRef", row.BillRef, 500);
            AddText(detail, "@Intref", row.IntRef, 200);
            detail.Parameters.Add("@Amount", SqlDbType.Money).Value = row.Amount;
            AddText(detail, "@Remarks", row.Remarks, 1000);
            detail.Parameters.Add("@DtlCount", SqlDbType.Int).Value = index;
            await detail.ExecuteNonQueryAsync(cancellationToken);
        }

        return rfNumber;
    }

    private static async Task<CreateRfpRequest> LoadRequestAsync(SqlConnection connection, SqlTransaction transaction,
        int requestId, decimal excessAmount, CancellationToken cancellationToken)
    {
        CreateRfpRequest request;
        string requestNumber;
        await using (var context = new SqlCommand("dbo.sp_Rfp_GetRequestContext", connection, transaction) { CommandType = CommandType.StoredProcedure })
        {
            context.Parameters.Add("@Id", SqlDbType.Int).Value = requestId;
            await using var reader = await context.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken)) throw new InvalidOperationException("Cash advance request was not found.");
            string ReadText(string name) => reader[name] is DBNull ? "" : Convert.ToString(reader[name], CultureInfo.InvariantCulture) ?? "";
            requestNumber = ReadText("RequestNumber");
            request = new CreateRfpRequest
            {
                RequestorId = ReadText("FineReportRequestorId"),
                CompanyId = ReadText("CompanyID"),
                PayeeCode = ReadText("PayeeCode"),
                PayeeName = ReadText("PayeeName"),
                PurposeOfDisbursement = $"Reimbursement for Excess amount in {requestNumber}",
                Recommendation = ReadText("Recommendation"),
                RequestGroup = ReadText("RequestGroup"),
                AttachmentFolder = ReadText("Attachment_Folder")
            };
            if (string.IsNullOrWhiteSpace(request.PayeeName)) request.PayeeName = ReadText("DisplayName");
            if (string.IsNullOrWhiteSpace(request.PayeeCode)) request.PayeeCode = "0";
            if (string.IsNullOrWhiteSpace(request.Recommendation)) request.Recommendation = "1";
        }
        if (string.IsNullOrWhiteSpace(request.CompanyId))
            throw new InvalidOperationException("Select the RFP company in Confirm Approval.");
        if (string.IsNullOrWhiteSpace(request.RequestorId))
            throw new InvalidOperationException("The request owner's email is not mapped to a FineReport requestor.");
        if (string.IsNullOrWhiteSpace(request.RequestGroup))
            throw new InvalidOperationException("The request owner needs a single FMS department assignment for RFP routing, or a request group on the original FineReport header.");

        var rows = new List<CreateRfpDetail>();
        await using (var command = new SqlCommand("dbo.sp_Rfp_GetRequestDetails", connection, transaction) { CommandType = CommandType.StoredProcedure })
        {
            command.Parameters.Add("@Id", SqlDbType.Int).Value = requestId;
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                string ReadText(string name) => reader[name] is DBNull ? "" : Convert.ToString(reader[name], CultureInfo.InvariantCulture) ?? "";
                rows.Add(new CreateRfpDetail
                {
                    Capex = ReadText("Capex"),
                    CostCenter = ReadText("CostCenter"),
                    Project = ReadText("Project"),
                    BillRef = ReadText("BillRef"),
                    IntRef = ReadText("IntRef"),
                    Amount = Convert.ToDecimal(reader["Amount"]),
                    Remarks = ReadText("Remarks")
                });
            }
        }
        request.Details = RfpExcessAllocation.Allocate(rows, excessAmount, requestNumber);
        var validationResults = new List<System.ComponentModel.DataAnnotations.ValidationResult>();
        if (!System.ComponentModel.DataAnnotations.Validator.TryValidateObject(request,
                new System.ComponentModel.DataAnnotations.ValidationContext(request), validationResults, true) ||
            request.Details.Any(row => !System.ComponentModel.DataAnnotations.Validator.TryValidateObject(row,
                new System.ComponentModel.DataAnnotations.ValidationContext(row), validationResults, true)))
            throw new InvalidOperationException("Request data cannot be saved to FineReport: " + string.Join(" ", validationResults.Select(result => result.ErrorMessage)));
        return request;
    }

    private static SqlCommand CreateCommand(SqlConnection connection, SqlTransaction transaction, string mode)
    {
        var command = new SqlCommand("dbo.sp_Rfp_SaveData", connection, transaction)
        {
            CommandType = CommandType.StoredProcedure
        };
        AddText(command, "@Mode", mode, 100);
        return command;
    }

    private static void AddText(SqlCommand command, string name, string? value, int size) =>
        command.Parameters.Add(name, SqlDbType.VarChar, size).Value = value ?? (object)DBNull.Value;
}
