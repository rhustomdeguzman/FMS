import type { CashAdvanceRequest, TransactionHistory } from "./types/CashAdvance";

const printApprovalActions = new Set(["approved_by_department_head", "rfp_created", "rfp_waived"]);
const accountingApprovalActions = new Set(["approved_by_accounting"]);
const printableStatuses = new Set<CashAdvanceRequest["status"]>([
  "pending_accounting_review",
  "pending_rfp_attachment",
  "rfp_created",
]);

export const getDepartmentApprovalEvent = (request: CashAdvanceRequest): TransactionHistory | undefined =>
  [...request.history].reverse().find((event) => printApprovalActions.has(event.action));

const hasAccountingApproval = (request: CashAdvanceRequest): boolean =>
  request.history.some((event) => accountingApprovalActions.has(event.action));

export const isDepartmentApprovalPrintAvailable = (request: CashAdvanceRequest): boolean =>
  printableStatuses.has(request.status) &&
  getDepartmentApprovalEvent(request) !== undefined &&
  !hasAccountingApproval(request) &&
  (!Object.prototype.hasOwnProperty.call(request, "printToken") || Boolean(request.printToken?.trim()));

export const getRequestReferenceNumber = (request: CashAdvanceRequest): string =>
  request.referenceNumber?.trim() || request.requestNumber;

const formatCurrency = (amount?: number) => `PHP ${(amount ?? 0).toLocaleString()}`;

const formatDate = (date: Date) => date.toLocaleDateString("en-PH");

const escapeHtml = (value: string) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

const receiptRowsHtml = (request: CashAdvanceRequest) => {
  const receiptDetails = request.receiptDetails ?? [];

  if (receiptDetails.length === 0) {
    return `<tr><td colspan="7" class="empty">No receipt details submitted.</td></tr>`;
  }

  return receiptDetails
    .map(
      (detail) => `
        <tr>
          <td>${escapeHtml(detail.vendor || "-")}</td>
          <td>${escapeHtml(detail.description || "-")}</td>
          <td>${escapeHtml(detail.project || "-")}</td>
          <td>${escapeHtml(detail.profitCenter || "-")}</td>
          <td class="amount">${escapeHtml(formatCurrency(detail.amount))}</td>
          <td>${escapeHtml(detail.invoiceRef || "-")}</td>
          <td>${escapeHtml(detail.expenseType || "-")}</td>
        </tr>
      `,
    )
    .join("");
};

export const buildDemoRequestPrintHtml = (request: CashAdvanceRequest) => {
  const approvalEvent = getDepartmentApprovalEvent(request);
  const approverName = approvalEvent?.fromEmployee?.name ?? "Department approver";
  const approvalDate = approvalEvent?.timestamp ? formatDate(approvalEvent.timestamp) : "-";

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Approved Request ${escapeHtml(getRequestReferenceNumber(request))}</title>
  <style>
    @page { size: A4; margin: 18mm; }
    * { box-sizing: border-box; }
    body { margin: 0; color: #17243f; font-family: Arial, Helvetica, sans-serif; font-size: 12px; line-height: 1.45; }
    h1 { margin: 0; font-size: 22px; }
    .muted { color: #5c6b7a; }
    .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; margin-top: 20px; }
    .field { border: 1px solid #d9e1e8; padding: 10px 12px; border-radius: 6px; }
    .label { color: #5c6b7a; display: block; font-size: 10px; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; }
    .value { display: block; margin-top: 4px; font-weight: 700; }
    table { width: 100%; border-collapse: collapse; margin-top: 16px; }
    th, td { border: 1px solid #d9e1e8; padding: 8px; text-align: left; vertical-align: top; }
    th { background: #f3f6f9; color: #5c6b7a; font-size: 10px; text-transform: uppercase; }
    .amount { text-align: right; white-space: nowrap; }
    .empty { color: #5c6b7a; text-align: center; }
  </style>
</head>
<body>
  <h1>Department Approved Request</h1>
  <p class="muted">${escapeHtml(request.purpose)}</p>
  <section class="grid">
    <div class="field"><span class="label">Requestor</span><span class="value">${escapeHtml(request.originalOwner.name)}</span></div>
    <div class="field"><span class="label">Source</span><span class="value">${escapeHtml(request.sourceSystem)}</span></div>
    <div class="field"><span class="label">Ref No</span><span class="value">${escapeHtml(getRequestReferenceNumber(request))}</span></div>
    <div class="field"><span class="label">Created</span><span class="value">${escapeHtml(formatDate(request.createdAt))}</span></div>
    <div class="field"><span class="label">Due Date</span><span class="value">${escapeHtml(formatDate(request.dueDate))}</span></div>
    <div class="field"><span class="label">Department Approver</span><span class="value">${escapeHtml(approverName)} (${escapeHtml(approvalDate)})</span></div>
  </section>
  <h2>Receipt Details</h2>
  <table>
    <thead>
      <tr>
        <th>Vendor</th>
        <th>Description</th>
        <th>Project</th>
        <th>Profit Cost Center</th>
        <th>Amount</th>
        <th>Invoice Ref.</th>
        <th>Type of Expense</th>
      </tr>
    </thead>
    <tbody>${receiptRowsHtml(request)}</tbody>
  </table>
</body>
</html>`;
};
