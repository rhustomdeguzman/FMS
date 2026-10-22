# FineReport RFP creation

In live mode, **Confirm Approval** with RFP Action **Create RFP** creates the
FineReport RFP through the existing department-decision endpoint. There is no
standalone creation form or endpoint. Waive, Return and ordinary approvals do
not create FineReport records.

If the request has no company saved, its existing approval dialog requires a
company selection for Create RFP. The server validates and saves that selection
in the same transaction. Requests with a stored company reuse it.

The server reads the saved request and receipt details. It resolves the current
owner's FineReport requestor ID by email and uses the owner's unique FMS
DepartmentCode assignment as ReqGrp (falling back to the original header's
ReqGroup). FineReport requestor DeptGroup is not required. It copies company and
sets PurOfDisbursement to `Reimbursement for Excess amount in <RequestNumber>`,
and reuses original FineReport payee/recommendation/
metadata when available. Without original header metadata,
payee defaults to the current owner and Recommendation `1` uses the stored
procedure's existing department approval routing. Missing requestor/company/group
mapping fails approval without writing any records.

Excess RFPs contain exactly one reimbursement detail row. Its Amount is the full
excess, Capex is `2`, CostCenter is the first saved request row's cost center,
Project is `H.O.`, BillRef is the FMS RequestNumber, Remarks is `For Reimbursement`,
and IntRef is empty. Request rows are ordered by their saved IDs; regular details
use ProfitCenterCode for the cost center, and petty cash receipts use CostCenter.
Header TotalAmount equals the excess. The original request details are unchanged.

The server fixes AltPayeeCode to `N/A`, TypeOfExpense to `51`, Payment_Terms
to `12`, and Request_Type to `Cash Advance`. It calls the header procedure once,
then Details once with the returned RFNo and DtlCount `0`.
Approval, header, detail inserts and the FMS RFP number update share a transaction;
failed rows roll back approval as well as all RFP inserts. The returned RFNo
replaces the generated placeholder RFP number on the existing FMS request.
The request row is locked before checking its status, preventing repeated
Confirm Approval submissions from creating duplicate RFPs after approval.
An exclusive header table lock protects the legacy MAX(RF_Number) allocation
and return value from concurrent writers until commit.

The existing procedure resolves the saved PayeeCode using company and PayeeName
and creates an email queue entry during header creation.

## RFP files

Each new RFP header receives AttachFolder `Cash_Advance_<32 random alphanumeric characters>`.
After the header returns RFNo, the API uses that same number for details and all
filenames. A shared RequestPrintService powers both the existing Print button
and the saved PDF. Publication requires the HTML renderer (Edge or Chrome), so
it never saves the shortened text fallback as the RFP document.
The saved PDF's REF NO uses the original FMS RequestNumber (`RFP-...`), while its
filename and the new RFP detail records use the newly generated RFNo.

The saved Print PDF is named:
`[RFP<number>] [<company name>] [<payee>] [Requestor] - RFP<number>D.pdf`.
Liquidation attachments retain their original filename after the same bracketed
prefix. Duplicate filenames receive `(2)`, `(3)`, etc. Invalid Windows filename
characters are replaced, and long names are bounded to filesystem limits.

Files are copied directly into the existing directory:
`\\192.168.127.72\d$\xampp\htdocs\NewORFPv3\public\Request For Payment`.
No physical subfolder is created. AttachFolder remains the logical grouping
identifier in the header and temporary_files records. Existing files receive
no changes; filename collisions use a numbered suffix.
The API account must have write access to this destination and read access to
its local Uploads directory. Configure `RfpAttachments:DestinationRoot` to override
the destination, or `FMS_HTML_TO_PDF_BROWSER` to select the PDF browser executable.

Every PDF or copied attachment gets a FineReport.dbo.temporary_files record with
folder equal to AttachFolder, filename equal to its saved name, filetype
`Requestor`, and created_at/updated_at set by GETDATE(). SQL registration remains
in the approval transaction. Failure rolls back SQL changes and attempts to remove
only the files created for that failed approval; cleanup failures are logged.
Original liquidation attachments remain in their existing storage.
