using System.ComponentModel.DataAnnotations;

namespace FundManagementAPI.Models;

public sealed class CreateRfpRequest
{
    [Required, StringLength(100)] public string RequestorId { get; set; } = "";
    [Required, StringLength(100)] public string CompanyId { get; set; } = "";
    [Required, StringLength(100)] public string PayeeCode { get; set; } = "";
    [Required, StringLength(200)] public string PayeeName { get; set; } = "";
    [Required, StringLength(500)] public string PurposeOfDisbursement { get; set; } = "";
    [Required, StringLength(100)] public string Recommendation { get; set; } = "";
    [Required, StringLength(100)] public string RequestGroup { get; set; } = "";
    [StringLength(100)] public string? AttachmentFolder { get; set; }
    [Required, MinLength(1)] public List<CreateRfpDetail> Details { get; set; } = [];
}

public sealed class CreateRfpDetail
{
    [Required, StringLength(100)] public string Capex { get; set; } = "";
    [StringLength(10)] public string CostCenter { get; set; } = "";
    [StringLength(20)] public string? Project { get; set; }
    [StringLength(500)] public string? BillRef { get; set; }
    [StringLength(200)] public string? IntRef { get; set; }
    [Range(typeof(decimal), "0.0001", "922337203685477.5807")]
    public decimal Amount { get; set; }
    [StringLength(1000)] public string? Remarks { get; set; }
}

