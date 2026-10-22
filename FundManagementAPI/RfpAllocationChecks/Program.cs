using FundManagementAPI.Models;
using FundManagementAPI.Repositories;

static CreateRfpDetail Row(decimal amount, string reference) => new()
{
    Amount = amount, Capex = "2", CostCenter = "CC01", Project = "P01",
    BillRef = reference, IntRef = "Internal", Remarks = "Description"
};
static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

var original = new[] { Row(8000, "A"), Row(4000, "B"), Row(1000, "C") };
original[1].CostCenter = "CC02";
var excess = RfpExcessAllocation.Allocate(original, 3000, "CA-124");
Check(excess.Count == 1 && excess[0].Amount == 3000, "The full excess must be saved in exactly one row.");
Check(excess[0].CostCenter == "CC01", "Use the first request row's cost center.");
Check(excess[0].Capex == "2" && excess[0].Project == "H.O." && excess[0].BillRef == "CA-124" && excess[0].Remarks == "For Reimbursement" && excess[0].IntRef == "", "Reimbursement fields must use the required values.");
Check(original[1].Amount == 4000, "Source details must remain unchanged.");
Check(original[0].Project == "P01" && original[0].BillRef == "A", "Source references must remain unchanged.");
var precise = RfpExcessAllocation.Allocate(new[] { Row(1.0001m, "A"), Row(0.0002m, "B") }, 0.0003m, "CA-125");
Check(precise.Sum(row => row.Amount) == 0.0003m, "Four-decimal amounts must reconcile exactly.");
try
{
    RfpExcessAllocation.Allocate(original, 0, "CA-124");
    throw new Exception("Nonpositive excess must fail.");
}
catch (InvalidOperationException) { }
try
{
    RfpExcessAllocation.Allocate(Array.Empty<CreateRfpDetail>(), 3000, "CA-124");
    throw new Exception("Missing rows must fail.");
}
catch (InvalidOperationException) { }
Console.WriteLine("RFP checks passed: single reimbursement row, first cost center, fixed fields, source preservation, precision, invalid excess, missing rows.");
