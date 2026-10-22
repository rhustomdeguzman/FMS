import { useMemo, useState } from "react";
import {
  getPettyCashRequestTypeLabel,
  hasPettyCashReturnAmount,
  isPettyCashReplenishment,
  isPettyCashWorkflowRequest,
  needsPettyCashReturnAcknowledgement,
} from "../../pettyCash";
import type { AcknowledgementReceipt, CashAdvanceRequest, CustodianFundSummary } from "../../types/CashAdvance";
import StatusBadge from "../StatusBadge";

interface CustodianPanelProps {
  fundSummary: CustodianFundSummary;
  requests: CashAdvanceRequest[];
  onApprove: (request: CashAdvanceRequest) => void;
  onReject: (request: CashAdvanceRequest) => void;
  onCreateReceipt: (request: CashAdvanceRequest) => void;
  onViewReceipt: (receipt: AcknowledgementReceipt, request: CashAdvanceRequest) => void;
  onOpenDetails: (request: CashAdvanceRequest) => void;
  onReplenish: (amount: number, notes: string) => void;
  onSubmitReplenishmentCv: (request: CashAdvanceRequest, cvNumber: string) => void;
}

const formatCurrency = (amount: number) => `PHP ${amount.toLocaleString()}`;

const replenishmentExportHeaders = [
  "Request Number",
  "Request Type",
  "OR Number",
  "Company",
  "TIN",
  "Address",
  "Type of Expense",
  "Profit Cost Center",
  "Amount",
  "Tax Type",
  "OR Date",
  "Transaction Date",
  "Description",
  "From Location",
  "To Location",
] as const;

type ReplenishmentExportHeader = (typeof replenishmentExportHeaders)[number];
type ReplenishmentExportRow = Record<ReplenishmentExportHeader, string | number>;

const custodianHandledActions = new Set(["approved_by_custodian", "petty_cash_released"]);

const formatDate = (value?: string | Date) => {
  if (!value) {
    return "";
  }

  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? "" : value.toISOString().slice(0, 10);
  }

  const dateValue = value.split("T")[0];
  return dateValue || value;
};

const escapeHtml = (value: string | number) =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;");

const downloadReplenishmentExcel = (rows: ReplenishmentExportRow[]) => {
  if (typeof window === "undefined" || rows.length === 0) {
    return;
  }

  const tableHeader = replenishmentExportHeaders
    .map((header) => `<th>${escapeHtml(header)}</th>`)
    .join("");
  const tableRows = rows
    .map(
      (row) =>
        `<tr>${replenishmentExportHeaders
          .map((header) => `<td>${escapeHtml(row[header] ?? "")}</td>`)
          .join("")}</tr>`,
    )
    .join("");
  const workbook = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    table { border-collapse: collapse; font-family: Arial, Helvetica, sans-serif; font-size: 12px; }
    th, td { border: 1px solid #8ea3b7; padding: 6px 8px; mso-number-format: "\\@"; }
    th { background: #dceaf7; font-weight: bold; }
  </style>
</head>
<body>
  <table>
    <thead><tr>${tableHeader}</tr></thead>
    <tbody>${tableRows}</tbody>
  </table>
</body>
</html>`;
  const blob = new Blob(["\ufeff", workbook], { type: "application/vnd.ms-excel;charset=utf-8" });
  const objectUrl = window.URL.createObjectURL(blob);
  const link = document.createElement("a");

  try {
    link.href = objectUrl;
    link.download = `petty-cash-replenishment-${new Date().toISOString().slice(0, 10)}.xls`;
    document.body.appendChild(link);
    link.click();
  } finally {
    link.remove();
    window.URL.revokeObjectURL(objectUrl);
  }
};

const isHandledByCustodian = (request: CashAdvanceRequest, custodianId: string): boolean => {
  if (!isPettyCashWorkflowRequest(request) || request.custodian?.id !== custodianId || request.status === "rejected") {
    return false;
  }

  return (
    request.status === "pending_liquidation" ||
    request.status === "partially_liquidated" ||
    request.status === "pending_custodian_liquidation_review" ||
    request.status === "fully_liquidated" ||
    request.history.some(
      (event) => event.fromEmployee?.id === custodianId && custodianHandledActions.has(event.action),
    )
  );
};

export default function CustodianPanel({
  fundSummary,
  requests,
  onApprove,
  onReject,
  onCreateReceipt,
  onViewReceipt,
  onOpenDetails,
  onReplenish,
  onSubmitReplenishmentCv,
}: CustodianPanelProps) {
  const [showReplenish, setShowReplenish] = useState(false);
  const [replenishNotes, setReplenishNotes] = useState("");
  const [cvNumbers, setCvNumbers] = useState<Record<string, string>>({});
  const replenishmentAmount = Math.max(fundSummary.usedAmount - fundSummary.replenishmentRequestedAmount, 0);
  const canReplenish = replenishmentAmount > 0;
  const custodianRequests = useMemo(
    () => requests.filter((request) => request.custodian?.id === fundSummary.custodian.id),
    [fundSummary.custodian.id, requests],
  );
  const pendingReleaseRequests = custodianRequests.filter((request) => request.status === "pending_custodian_approval");
  const liquidationReviewRequests = custodianRequests.filter(
    (request) => request.status === "pending_custodian_liquidation_review",
  );
  const pendingReplenishmentRequests = useMemo(
    () =>
      custodianRequests.filter(
        (request) =>
          isPettyCashReplenishment(request) &&
          request.status === "pending_replenishment",
      ),
    [custodianRequests],
  );
  const replenishmentSourceRequests = useMemo(
    () => custodianRequests.filter((request) => isHandledByCustodian(request, fundSummary.custodian.id)),
    [custodianRequests, fundSummary.custodian.id],
  );
  const replenishmentReceiptRows = useMemo(
    () =>
      replenishmentSourceRequests.flatMap((request) =>
        (request.pettyCashReceiptDetails ?? []).map((detail) => ({ request, detail })),
      ),
    [replenishmentSourceRequests],
  );
  const replenishmentAdvanceReceiptRows = useMemo(
    () =>
      replenishmentSourceRequests
        .filter((request) => request.requestType === "petty_cash_advance")
        .flatMap((request) => (request.receiptDetails ?? []).map((detail) => ({ request, detail }))),
    [replenishmentSourceRequests],
  );
  const replenishmentTransportationRows = useMemo(
    () =>
      replenishmentSourceRequests.flatMap((request) =>
        (request.pettyCashTransportationDetails ?? []).map((detail) => ({ request, detail })),
      ),
    [replenishmentSourceRequests],
  );
  const replenishmentExportRows = useMemo<ReplenishmentExportRow[]>(
    () => [
      ...replenishmentReceiptRows.map(({ request, detail }) => ({
        "Request Number": request.requestNumber,
        "Request Type": getPettyCashRequestTypeLabel(request.requestType),
        "OR Number": detail.orNumber,
        Company: detail.company,
        TIN: detail.tin,
        Address: detail.address,
        "Type of Expense": detail.natureOfExpense,
        "Profit Cost Center": detail.costCenter,
        Amount: detail.amount,
        "Tax Type": detail.taxType ?? "",
        "OR Date": formatDate(detail.orDate),
        "Transaction Date": "",
        Description: "",
        "From Location": "",
        "To Location": "",
      })),
      ...replenishmentAdvanceReceiptRows.map(({ request, detail }) => ({
        "Request Number": request.requestNumber,
        "Request Type": getPettyCashRequestTypeLabel(request.requestType),
        "OR Number": detail.invoiceRef,
        Company: detail.vendor,
        TIN: detail.vendorCode ?? "",
        Address: "",
        "Type of Expense": detail.expenseType,
        "Profit Cost Center": detail.profitCenterCode ?? detail.profitCenter,
        Amount: detail.amount,
        "Tax Type": "",
        "OR Date": formatDate(detail.createdAt),
        "Transaction Date": "",
        Description: detail.description,
        "From Location": "",
        "To Location": "",
      })),
      ...replenishmentTransportationRows.map(({ request, detail }) => ({
        "Request Number": request.requestNumber,
        "Request Type": getPettyCashRequestTypeLabel(request.requestType),
        "OR Number": "",
        Company: "",
        TIN: "",
        Address: "",
        "Type of Expense": "",
        "Profit Cost Center": "",
        Amount: detail.amount,
        "Tax Type": "",
        "OR Date": "",
        "Transaction Date": formatDate(detail.transactionDate),
        Description: detail.description,
        "From Location": detail.from,
        "To Location": detail.to,
      })),
    ],
    [replenishmentAdvanceReceiptRows, replenishmentReceiptRows, replenishmentTransportationRows],
  );
  const replenishmentDetailTotal = useMemo(
    () =>
      replenishmentExportRows.reduce((sum, row) => {
        const amount = typeof row.Amount === "number" ? row.Amount : Number(row.Amount);
        return sum + (Number.isFinite(amount) ? amount : 0);
      }, 0),
    [replenishmentExportRows],
  );
  const replenishmentReceiptRowCount = replenishmentReceiptRows.length + replenishmentAdvanceReceiptRows.length;

  const openReplenish = () => {
    setReplenishNotes("");
    setShowReplenish(true);
  };

  const submitCvNumber = (request: CashAdvanceRequest) => {
    const cvNumber = cvNumbers[request.id]?.trim() ?? "";

    if (!cvNumber) {
      return;
    }

    onSubmitReplenishmentCv(request, cvNumber);
    setCvNumbers((current) => {
      const next = { ...current };
      delete next[request.id];
      return next;
    });
  };

  return (
    <section className="space-y-6">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <h2 className="text-xl font-bold text-[#17243f]">Custodian Fund</h2>
          <p className="mt-1 text-sm text-[#5c6b7a]">Petty cash requests approved by departments are routed here.</p>
        </div>
        <button
          type="button"
          onClick={openReplenish}
          disabled={!canReplenish}
          className="rounded-lg bg-[#17243f] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#243558] disabled:cursor-not-allowed disabled:opacity-50"
        >
          Create RFP
        </button>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded-lg border border-[#d9e1e8] bg-white p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Assigned Fund</p>
          <p className="mt-1 text-xl font-bold text-[#17243f]">{formatCurrency(fundSummary.fundAmount)}</p>
        </div>
        <div className="rounded-lg border border-[#d9e1e8] bg-white p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Available</p>
          <p className="mt-1 text-xl font-bold text-[#08786f]">{formatCurrency(fundSummary.availableAmount)}</p>
        </div>
        <div className="rounded-lg border border-[#d9e1e8] bg-white p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">For Replenishment</p>
          <p className="mt-1 text-xl font-bold text-[#9a6500]">{formatCurrency(fundSummary.usedAmount)}</p>
        </div>
      </div>

      <section className="rounded-lg border border-[#d9e1e8] bg-white shadow-sm">
        <div className="flex flex-col gap-2 border-b border-[#d9e1e8] px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h3 className="font-bold text-[#17243f]">Pending Replenishment</h3>
            <p className="mt-1 text-sm text-[#5c6b7a]">Submit the CV Number to complete fund replenishment.</p>
          </div>
          <p className="text-sm font-semibold text-[#9a6500]">{pendingReplenishmentRequests.length} pending</p>
        </div>
        {pendingReplenishmentRequests.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="min-w-[880px] w-full text-left text-sm">
              <thead className="bg-[#f3f6f9] text-xs uppercase tracking-wide text-[#5c6b7a]">
                <tr>
                  <th className="px-4 py-3 font-semibold">RFP Request</th>
                  <th className="px-4 py-3 font-semibold">Status</th>
                  <th className="px-4 py-3 font-semibold">Purpose</th>
                  <th className="px-4 py-3 font-semibold">Amount</th>
                  <th className="px-4 py-3 font-semibold">CV Number</th>
                  <th className="px-4 py-3 font-semibold text-right">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[#eef2f7]">
                {pendingReplenishmentRequests.map((request) => {
                  const cvNumber = cvNumbers[request.id] ?? "";

                  return (
                    <tr key={request.id}>
                      <td className="px-4 py-3">
                        <button
                          type="button"
                          onClick={() => onOpenDetails(request)}
                          className="font-bold text-[#17243f] hover:text-[#0b6f68]"
                        >
                          {request.requestNumber}
                        </button>
                      </td>
                      <td className="px-4 py-3">
                        <StatusBadge status={request.status} request={request} />
                      </td>
                      <td className="max-w-[260px] px-4 py-3 text-[#5c6b7a]">{request.purpose}</td>
                      <td className="px-4 py-3 font-semibold text-[#08786f]">{formatCurrency(request.amount)}</td>
                      <td className="px-4 py-3">
                        <input
                          value={cvNumber}
                          onChange={(event) =>
                            setCvNumbers((current) => ({ ...current, [request.id]: event.target.value }))
                          }
                          className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          placeholder="Enter CV Number"
                        />
                      </td>
                      <td className="px-4 py-3 text-right">
                        <button
                          type="button"
                          onClick={() => submitCvNumber(request)}
                          disabled={cvNumber.trim().length === 0}
                          className="rounded-lg bg-[#0bb7a5] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
                        >
                          Submit
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="px-5 py-10 text-center text-sm text-[#5c6b7a]">No replenishment RFPs are waiting for CV Number.</p>
        )}
      </section>

      <div className="grid gap-5 xl:grid-cols-2">
        <QueueSection
          title="For Reimbursement / Release"
          emptyMessage="No petty cash requests are waiting for custodian approval."
          requests={pendingReleaseRequests}
          approveLabel="Approve Release"
          rejectLabel="Reject"
          onApprove={onApprove}
          onReject={onReject}
          onCreateReceipt={onCreateReceipt}
          onViewReceipt={onViewReceipt}
          onOpenDetails={onOpenDetails}
        />
        <QueueSection
          title="For Liquidation Review"
          emptyMessage="No petty cash liquidations are waiting for review."
          requests={liquidationReviewRequests}
          approveLabel="Approve Liquidation"
          rejectLabel="Return"
          onApprove={onApprove}
          onReject={onReject}
          onCreateReceipt={onCreateReceipt}
          onViewReceipt={onViewReceipt}
          onOpenDetails={onOpenDetails}
        />
      </div>

      {showReplenish && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="flex max-h-[90vh] w-full max-w-6xl flex-col overflow-hidden rounded-lg bg-white shadow-xl">
            <div className="flex flex-col gap-4 border-b border-[#d9e1e8] p-6 lg:flex-row lg:items-start lg:justify-between">
              <div>
                <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">Replenishment</p>
                <h3 className="mt-1 text-xl font-bold text-[#17243f]">Create RFP request</h3>
                <p className="mt-2 text-sm text-[#5c6b7a]">This creates a petty cash replenishment RFP request.</p>
              </div>
              <button
                type="button"
                onClick={() => downloadReplenishmentExcel(replenishmentExportRows)}
                disabled={replenishmentExportRows.length === 0}
                className="rounded-lg border border-[#0bb7a5] px-4 py-2 text-sm font-semibold text-[#08786f] hover:bg-[#e2faf6] disabled:cursor-not-allowed disabled:border-[#c8d4df] disabled:text-[#8b98a5]"
              >
                Export Excel
              </button>
            </div>
            <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-6">
              <div className="grid gap-4 md:grid-cols-3">
                <div className="rounded-lg bg-[#fff4c7] p-4">
                  <p className="text-xs font-semibold uppercase tracking-wide text-[#9a6500]">For Replenishment</p>
                  <p className="mt-1 text-lg font-bold text-[#17243f]">{formatCurrency(replenishmentAmount)}</p>
                </div>
                <div className="rounded-lg bg-[#f3f6f9] p-4">
                  <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Listed Total</p>
                  <p className="mt-1 text-lg font-bold text-[#17243f]">{formatCurrency(replenishmentDetailTotal)}</p>
                </div>
                <div className="rounded-lg bg-[#e2faf6] p-4">
                  <p className="text-xs font-semibold uppercase tracking-wide text-[#08786f]">Detail Rows</p>
                  <p className="mt-1 text-lg font-bold text-[#17243f]">{replenishmentExportRows.length}</p>
                </div>
              </div>

              <section>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <h4 className="font-bold text-[#17243f]">Receipt Details / Advance Liquidations</h4>
                  <p className="text-sm font-semibold text-[#08786f]">{replenishmentReceiptRowCount} rows</p>
                </div>
                <div className="mt-3 overflow-x-auto rounded-lg border border-[#d9e1e8] bg-white">
                  {replenishmentReceiptRowCount > 0 ? (
                    <table className="min-w-[1420px] w-full text-left text-sm">
                      <thead className="bg-[#f3f6f9] text-xs uppercase tracking-wide text-[#5c6b7a]">
                        <tr>
                          <th className="px-3 py-3 font-semibold">Request Number</th>
                          <th className="px-3 py-3 font-semibold">Request Type</th>
                          <th className="px-3 py-3 font-semibold">OR#</th>
                          <th className="px-3 py-3 font-semibold">Company</th>
                          <th className="px-3 py-3 font-semibold">TIN</th>
                          <th className="px-3 py-3 font-semibold">Address</th>
                          <th className="px-3 py-3 font-semibold">Type of Expense</th>
                          <th className="px-3 py-3 font-semibold">Description</th>
                          <th className="px-3 py-3 font-semibold">Profit Cost Center</th>
                          <th className="px-3 py-3 font-semibold">Tax Type</th>
                          <th className="px-3 py-3 font-semibold">Amount</th>
                          <th className="px-3 py-3 font-semibold">OR Date</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-[#eef2f7]">
                        {replenishmentReceiptRows.map(({ request, detail }) => (
                          <tr key={`${request.id}-receipt-${detail.id}`}>
                            <td className="px-3 py-3 font-semibold text-[#17243f]">{request.requestNumber}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">
                              {getPettyCashRequestTypeLabel(request.requestType)}
                            </td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.orNumber}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.company}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.tin}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.address}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.natureOfExpense}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]"></td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.costCenter}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.taxType ?? ""}</td>
                            <td className="px-3 py-3 font-semibold text-[#08786f]">{formatCurrency(detail.amount)}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{formatDate(detail.orDate)}</td>
                          </tr>
                        ))}
                        {replenishmentAdvanceReceiptRows.map(({ request, detail }) => (
                          <tr key={`${request.id}-advance-receipt-${detail.id}`}>
                            <td className="px-3 py-3 font-semibold text-[#17243f]">{request.requestNumber}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">
                              {getPettyCashRequestTypeLabel(request.requestType)}
                            </td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.invoiceRef}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.vendor}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.vendorCode ?? ""}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]"></td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.expenseType}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.description}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.profitCenterCode ?? detail.profitCenter}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]"></td>
                            <td className="px-3 py-3 font-semibold text-[#08786f]">{formatCurrency(detail.amount)}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{formatDate(detail.createdAt)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  ) : (
                    <p className="px-4 py-8 text-center text-sm text-[#5c6b7a]">No receipt details submitted.</p>
                  )}
                </div>
              </section>

              <section>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <h4 className="font-bold text-[#17243f]">Transportation Expenses</h4>
                  <p className="text-sm font-semibold text-[#08786f]">{replenishmentTransportationRows.length} rows</p>
                </div>
                <div className="mt-3 overflow-x-auto rounded-lg border border-[#d9e1e8] bg-white">
                  {replenishmentTransportationRows.length > 0 ? (
                    <table className="min-w-[980px] w-full text-left text-sm">
                      <thead className="bg-[#f3f6f9] text-xs uppercase tracking-wide text-[#5c6b7a]">
                        <tr>
                          <th className="px-3 py-3 font-semibold">Request Number</th>
                          <th className="px-3 py-3 font-semibold">Request Type</th>
                          <th className="px-3 py-3 font-semibold">Transaction Date</th>
                          <th className="px-3 py-3 font-semibold">Description</th>
                          <th className="px-3 py-3 font-semibold">From Location</th>
                          <th className="px-3 py-3 font-semibold">To Location</th>
                          <th className="px-3 py-3 font-semibold">Amount</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-[#eef2f7]">
                        {replenishmentTransportationRows.map(({ request, detail }) => (
                          <tr key={`${request.id}-transportation-${detail.id}`}>
                            <td className="px-3 py-3 font-semibold text-[#17243f]">{request.requestNumber}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">
                              {getPettyCashRequestTypeLabel(request.requestType)}
                            </td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{formatDate(detail.transactionDate)}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.description}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.from}</td>
                            <td className="px-3 py-3 text-[#5c6b7a]">{detail.to}</td>
                            <td className="px-3 py-3 font-semibold text-[#08786f]">{formatCurrency(detail.amount)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  ) : (
                    <p className="px-4 py-8 text-center text-sm text-[#5c6b7a]">
                      No transportation expenses submitted.
                    </p>
                  )}
                </div>
              </section>
              
              <div>
                <label className="block text-sm font-semibold text-[#17243f]" htmlFor="replenish-notes">
                  Notes
                </label>
                <textarea
                  id="replenish-notes"
                  value={replenishNotes}
                  onChange={(event) => setReplenishNotes(event.target.value)}
                  rows={3}
                  className="mt-2 w-full resize-none rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
                />
              </div>
            </div>
            <div className="flex gap-3 border-t border-[#d9e1e8] p-6">
              <button
                type="button"
                onClick={() => setShowReplenish(false)}
                className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={!canReplenish}
                onClick={() => {
                  onReplenish(replenishmentAmount, replenishNotes.trim());
                  setShowReplenish(false);
                }}
                className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
              >
                Create RFP
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}

interface QueueSectionProps {
  title: string;
  emptyMessage: string;
  requests: CashAdvanceRequest[];
  approveLabel: string;
  rejectLabel: string;
  onApprove: (request: CashAdvanceRequest) => void;
  onReject: (request: CashAdvanceRequest) => void;
  onCreateReceipt: (request: CashAdvanceRequest) => void;
  onViewReceipt: (receipt: AcknowledgementReceipt, request: CashAdvanceRequest) => void;
  onOpenDetails: (request: CashAdvanceRequest) => void;
}

function QueueSection({
  title,
  emptyMessage,
  requests,
  approveLabel,
  rejectLabel,
  onApprove,
  onReject,
  onCreateReceipt,
  onViewReceipt,
  onOpenDetails,
}: QueueSectionProps) {
  return (
    <section className="rounded-lg border border-[#d9e1e8] bg-white shadow-sm">
      <div className="border-b border-[#d9e1e8] px-5 py-4">
        <h3 className="font-bold text-[#17243f]">{title}</h3>
      </div>
      <div className="divide-y divide-[#eef2f7]">
        {requests.map((request) => (
          <QueueItem
            key={request.id}
            request={request}
            approveLabel={approveLabel}
            rejectLabel={rejectLabel}
            onApprove={onApprove}
            onReject={onReject}
            onCreateReceipt={onCreateReceipt}
            onViewReceipt={onViewReceipt}
            onOpenDetails={onOpenDetails}
          />
        ))}
        {requests.length === 0 && <p className="px-5 py-12 text-center text-sm text-[#5c6b7a]">{emptyMessage}</p>}
      </div>
    </section>
  );
}

interface QueueItemProps {
  request: CashAdvanceRequest;
  approveLabel: string;
  rejectLabel: string;
  onApprove: (request: CashAdvanceRequest) => void;
  onReject: (request: CashAdvanceRequest) => void;
  onCreateReceipt: (request: CashAdvanceRequest) => void;
  onViewReceipt: (receipt: AcknowledgementReceipt, request: CashAdvanceRequest) => void;
  onOpenDetails: (request: CashAdvanceRequest) => void;
}

function QueueItem({
  request,
  approveLabel,
  rejectLabel,
  onApprove,
  onReject,
  onCreateReceipt,
  onViewReceipt,
  onOpenDetails,
}: QueueItemProps) {
  const hasReturn = hasPettyCashReturnAmount(request);
  const needsReturnAcknowledgement = needsPettyCashReturnAcknowledgement(request);
  const receipt = request.acknowledgementReceipt;

  return (
    <article
      role="button"
      tabIndex={0}
      onClick={() => onOpenDetails(request)}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          onOpenDetails(request);
        }
      }}
      className="cursor-pointer p-5 hover:bg-[#f8fafc]"
    >
      <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-3">
            <h4 className="font-bold text-[#17243f]">{request.requestNumber}</h4>
            <StatusBadge status={request.status} request={request} />
          </div>
          <p className="mt-2 text-sm text-[#5c6b7a]">{request.purpose}</p>
          <p className="mt-2 text-xs font-medium uppercase tracking-wide text-[#5c6b7a]">
            {getPettyCashRequestTypeLabel(request.requestType)} - {request.originalOwner.name} - {request.department}
          </p>
          {receipt && (
            <p className="mt-2 text-xs font-semibold uppercase tracking-wide text-[#08786f]">
              AR {receipt.receiptNumber} {receipt.status === "acknowledged" ? "acknowledged" : "pending"}
            </p>
          )}
        </div>
        <div className="flex shrink-0 flex-col gap-3 sm:flex-row sm:items-center">
          <div className="flex flex-col gap-2 sm:items-end">
            <div className="rounded-lg bg-[#e2faf6] px-4 py-3 text-right">
              <p className="text-xs font-medium uppercase tracking-wide text-[#08786f]">Amount</p>
              <p className="font-bold text-[#17243f]">PHP {request.amount.toLocaleString()}</p>
            </div>
            {hasReturn && (
              <div className="rounded-lg bg-[#fff0f4] px-4 py-3 text-right">
                <p className="text-xs font-medium uppercase tracking-wide text-[#d30f42]">Return to Custodian</p>
                <p className="font-bold text-[#17243f]">PHP {(request.returnAmount ?? 0).toLocaleString()}</p>
              </div>
            )}
          </div>
          <div className="flex flex-wrap gap-2 sm:max-w-[220px] sm:justify-end">
            {receipt && (
              <button
                type="button"
                onClick={(event) => {
                  event.stopPropagation();
                  onViewReceipt(receipt, request);
                }}
                className="rounded-lg border border-[#0bb7a5] px-4 py-2 text-sm font-semibold text-[#08786f] hover:bg-[#e2faf6]"
              >
                View AR
              </button>
            )}
            {needsReturnAcknowledgement && (
              <button
                type="button"
                onClick={(event) => {
                  event.stopPropagation();
                  onCreateReceipt(request);
                }}
                className="rounded-lg bg-[#4e6493] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#24365c]"
              >
                {receipt ? "Continue AR" : "Create AR"}
              </button>
            )}
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                onApprove(request);
              }}
              disabled={needsReturnAcknowledgement}
              className="rounded-lg bg-[#0bb7a5] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
            >
              {request.requestType === "petty_cash" && request.status === "pending_custodian_approval"
                ? "Reimburse"
                : approveLabel}
            </button>
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                onReject(request);
              }}
              className="rounded-lg border border-[#ff1550] px-4 py-2 text-sm font-semibold text-[#ff1550] hover:bg-[#fff0f4]"
            >
              {rejectLabel}
            </button>
          </div>
        </div>
      </div>
    </article>
  );
}
