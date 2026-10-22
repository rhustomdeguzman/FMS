using FundManagementAPI.Models;

namespace FundManagementAPI.Repositories;

public static class RfpExcessAllocation
{
    public static List<CreateRfpDetail> Allocate(IEnumerable<CreateRfpDetail> rows, decimal excessAmount, string requestNumber)
    {
        var firstRow = rows.FirstOrDefault()
            ?? throw new InvalidOperationException("At least one request detail row is required to determine the RFP cost center.");
        if (excessAmount <= 0)
            throw new InvalidOperationException("The RFP excess amount must be greater than zero.");
        return [new CreateRfpDetail
        {
            Capex = "2",
            CostCenter = firstRow.CostCenter,
            Project = "H.O.",
            BillRef = requestNumber,
            IntRef = "",
            Amount = excessAmount,
            Remarks = "For Reimbursement"
        }];
    }
}
