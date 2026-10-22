import { useState } from "react";
import { useEffect } from "react";
import {
  getActualSpentAmount,
  getLiquidationBaseAmount,
  getPendingLiquidationAmount,
} from "../../liquidationAmounts";
import {
  getPettyCashActualSpentAmount,
  getPettyCashRequestTypeLabel,
  isPettyCashWorkflowRequest,
} from "../../pettyCash";
import { getDepartmentApprovalEvent, getRequestReferenceNumber, isDepartmentApprovalPrintAvailable } from "../../requestPrint";
import { getAcknowledgedTransferAmount, getTransferAllocationRows } from "../../transferAllocation";
import type { AppUser, AttachmentMeta, CashAdvanceRequest, RfpDecision, TransactionHistory, UserRole } from "../../types/CashAdvance";
import Avatar from "../Avatar";
import StatusBadge from "../StatusBadge";
import RfpCompanySelect from "../requests/RfpCompanySelect";

interface RequestDetailsModalProps {
  request: CashAdvanceRequest;
  currentUserRole: UserRole;
  users: AppUser[];
  onClose: () => void;
  approveLabel?: string;
  rejectLabel?: string;
  liquidateLabel?: string;
  onApprove?: (request: CashAdvanceRequest, rfpDecision?: RfpDecision, waiveReason?: string, companyId?: number) => void;
  isLiveMode?: boolean;
  onReject?: (request: CashAdvanceRequest) => boolean | void;
  onLiquidate?: (request: CashAdvanceRequest) => void;
  onUploadRfp?: (request: CashAdvanceRequest) => void;
  onTransfer?: (request: CashAdvanceRequest) => void;
  onCreateReceipt?: (request: CashAdvanceRequest) => void;
  onPrint?: (request: CashAdvanceRequest) => void;
}

type AttachmentPreviewItem = AttachmentMeta & {
  sourceLabel: string;
};

const formatCurrency = (amount?: number) => `PHP ${(amount ?? 0).toLocaleString()}`;

const getLatestReturnEvent = (history: TransactionHistory[]) =>
  [...history].reverse().find((event) => event.action === "returned");

const createPreviewUrl = (downloadUrl?: string) => {
  if (!downloadUrl) {
    return undefined;
  }

  return `${downloadUrl}${downloadUrl.includes("?") ? "&" : "?"}preview=true`;
};

const isImageFile = (attachment: AttachmentPreviewItem) => {
  const contentType = attachment.contentType?.toLowerCase() ?? "";
  const fileName = attachment.fileName.toLowerCase();

  return (
    contentType.startsWith("image/") ||
    [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"].some((extension) => fileName.endsWith(extension))
  );
};

const isPdfFile = (attachment: AttachmentPreviewItem) => {
  const contentType = attachment.contentType?.toLowerCase() ?? "";
  return contentType.includes("pdf") || attachment.fileName.toLowerCase().endsWith(".pdf");
};

const formatFileSize = (fileSize?: number) => {
  if (!fileSize) {
    return undefined;
  }

  if (fileSize < 1024 * 1024) {
    return `${Math.ceil(fileSize / 1024)} KB`;
  }

  return `${(fileSize / (1024 * 1024)).toFixed(1)} MB`;
};

export default function RequestDetailsModal({
  request,
  currentUserRole,
  users,
  onClose,
  approveLabel = "Approve",
  rejectLabel = "Return",
  liquidateLabel = "Liquidate",
  onApprove,
  onReject,
  onLiquidate,
  onUploadRfp,
  onTransfer,
  onCreateReceipt,
  onPrint,
  isLiveMode = false,
}: RequestDetailsModalProps) {
  const [showApproveConfirm, setShowApproveConfirm] = useState(false);
  const [rfpDecision, setRfpDecision] = useState<RfpDecision>("create");
  const [waiveReason, setWaiveReason] = useState("");
  const [rfpCompanyId, setRfpCompanyId] = useState<number>();
  const [previewAttachmentId, setPreviewAttachmentId] = useState<string | null>(null);

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    return () => {
      document.body.style.overflow = previousOverflow;
    };
  }, []);

  const attachments: AttachmentMeta[] = request.attachments ?? (request.attachmentNames ?? []).map((fileName) => ({ id: fileName, fileName }));
  const pendingTransfers = request.pendingTransfers ?? (request.pendingTransfer ? [request.pendingTransfer] : []);
  const receipt = request.acknowledgementReceipt;
  const depositSlipAttachment: AttachmentPreviewItem | undefined = receipt?.depositSlipFileName
    ? {
        id: `deposit-slip-${receipt.id ?? receipt.receiptNumber}`,
        fileName: receipt.depositSlipFileName,
        downloadUrl: receipt.depositSlipDownloadUrl,
        contentType: receipt.depositSlipContentType,
        fileSize: receipt.depositSlipFileSize,
        sourceLabel: "Deposit Slip/AR",
      }
    : undefined;
  const previewAttachments: AttachmentPreviewItem[] = [
    ...attachments.map((attachment) => ({
      ...attachment,
      sourceLabel: "Uploaded by requestor",
    })),
    ...(depositSlipAttachment ? [depositSlipAttachment] : []),
  ];
  const selectedAttachment = previewAttachments.find((attachment) => attachment.id === previewAttachmentId) ?? null;
  const selectedPreviewUrl = createPreviewUrl(selectedAttachment?.downloadUrl);
  const selectedFileSize = formatFileSize(selectedAttachment?.fileSize);
  const canInlinePreview =
    selectedAttachment !== null && (isImageFile(selectedAttachment) || isPdfFile(selectedAttachment));
  const amountSpent = getActualSpentAmount(request);
  const liquidationBaseAmount = getLiquidationBaseAmount(request);
  const pendingLiquidationAmount = getPendingLiquidationAmount(request);
  const receiptDetails = request.receiptDetails ?? [];
  const receiptDetailsTotal = receiptDetails.reduce((sum, detail) => sum + detail.amount, 0);
  const pettyCashReceiptDetails = request.pettyCashReceiptDetails ?? [];
  const pettyCashReceiptDetailsTotal = pettyCashReceiptDetails.reduce((sum, detail) => sum + detail.amount, 0);
  const pettyCashTransportationDetails = request.pettyCashTransportationDetails ?? [];
  const pettyCashTransportationDetailsTotal = pettyCashTransportationDetails.reduce(
    (sum, detail) => sum + detail.amount,
    0,
  );
  const pettyCashActualSpentAmount = getPettyCashActualSpentAmount(
    pettyCashReceiptDetails,
    pettyCashTransportationDetails,
  );
  const displayedAmountSpent =
    request.requestType === "petty_cash" ? pettyCashActualSpentAmount : amountSpent;
  const displayedExcessAmount =
    request.requestType === "petty_cash"
      ? Math.max(request.excessAmount ?? 0, pettyCashActualSpentAmount - request.amount)
      : request.excessAmount;
  const transferredAmount = Math.max(request.amount - liquidationBaseAmount, 0);
  const acknowledgedTransferredAmount = getAcknowledgedTransferAmount(request, transferredAmount);
  const transferAllocationRows = getTransferAllocationRows(request, transferredAmount);
  const canDecide = onApprove !== undefined || onReject !== undefined;
  const canPrint =
    (currentUserRole === "requestor" || currentUserRole === "accounting") &&
    onPrint !== undefined &&
    isDepartmentApprovalPrintAvailable(request);
  const hasWorkflowActions =
    canDecide ||
    canPrint ||
    onLiquidate !== undefined ||
    onUploadRfp !== undefined ||
    onTransfer !== undefined ||
    onCreateReceipt !== undefined;
  const isTransferAcknowledgement = approveLabel.toLowerCase().includes("acknowledge");
  const isCashierClosure = approveLabel.toLowerCase().includes("close liquidation");
  const needsRfpDecision =
    (request.status === "pending_department_approval" || request.status === "pending_rfp_department_approval") &&
    (request.excessAmount ?? 0) > 0 &&
    !isTransferAcknowledgement &&
    !isCashierClosure;
  const isWaiveReasonMissing = needsRfpDecision && rfpDecision === "waive" && waiveReason.trim().length === 0;
  const needsCompany = isLiveMode && needsRfpDecision && rfpDecision === "create" && !request.companyId;
  const isCompanyMissing = needsCompany && !rfpCompanyId;
  const latestReturnEvent = getLatestReturnEvent(request.history);
  const returnReason = request.status === "pending_liquidation" ? latestReturnEvent?.notes : undefined;
  const departmentApprovalEvent = getDepartmentApprovalEvent(request);
  const originalRequestor = users.find((candidate) => candidate.id === request.originalOwner.id);
  const requestorDepartment = originalRequestor?.department ?? request.originalOwner.department;
  const requestorDepartmentApprover = users.find(
    (candidate) =>
      candidate.role === "department_head" &&
      candidate.department.trim().toLowerCase() === requestorDepartment.trim().toLowerCase(),
  );
  const requestorDepartmentApproverName =
    requestorDepartmentApprover?.name ?? request.requestorDepartmentApproverName;
  const referenceNumber = getRequestReferenceNumber(request);
  const isPettyCash = isPettyCashWorkflowRequest(request);

  const confirmApprove = () => {
    if (isWaiveReasonMissing || isCompanyMissing) {
      return;
    }

    onApprove?.(
      request,
      needsRfpDecision ? rfpDecision : undefined,
      needsRfpDecision && rfpDecision === "waive" ? waiveReason.trim() : undefined,
      needsCompany ? rfpCompanyId : undefined,
    );
    setShowApproveConfirm(false);
    onClose();
  };

  const rejectRequest = () => {
    const result = onReject?.(request);
    if (result !== false) {
      onClose();
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="flex max-h-[90vh] w-[96vw] max-w-none flex-col overflow-hidden rounded-lg bg-white shadow-xl">
        <div className="flex items-start justify-between gap-4 border-b border-[#d9e1e8] p-6">
          <div>
            <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">Request Details</p>
            <h2 className="mt-1 text-xl font-bold text-[#17243f]">{request.requestNumber}</h2>
            <p className="mt-1 text-sm text-[#5c6b7a]">{request.purpose}</p>
          </div>
          <StatusBadge status={request.status} request={request} />
        </div>

        <div className="grid min-h-0 flex-1 lg:grid-cols-2">
        <div className="space-y-6 overflow-y-auto p-6">
          <section className="grid gap-4 md:grid-cols-2">
            <div className="rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Requestor</p>
              <div className="mt-3 flex items-center gap-3">
                <Avatar employee={request.originalOwner} />
                <div>
                  <p className="font-semibold text-[#17243f]">{request.originalOwner.name}</p>
                  <p className="text-sm text-[#5c6b7a]">{request.department}</p>
                </div>
              </div>
            </div>

            <div className="rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] p-4 text-sm">
              <div className="flex justify-between gap-4">
                <span className="text-[#5c6b7a]">Source</span>
                <span className="font-semibold text-[#17243f]">{request.sourceSystem}</span>
              </div>
              {request.requestType && (
                <div className="mt-2 flex justify-between gap-4">
                  <span className="text-[#5c6b7a]">Type</span>
                  <span className="font-semibold text-[#17243f]">{getPettyCashRequestTypeLabel(request.requestType)}</span>
                </div>
              )}
              {(isPettyCash || request.requestType === "petty_cash_replenishment") && request.custodian && (
                <div className="mt-2 flex justify-between gap-4">
                  <span className="text-[#5c6b7a]">Custodian</span>
                  <span className="text-right font-semibold text-[#17243f]">{request.custodian.name}</span>
                </div>
              )}
              <div className="mt-2 flex justify-between gap-4">
                <span className="text-[#5c6b7a]">Ref. No</span>
                <span className="font-semibold text-[#17243f]">{referenceNumber}</span>
              </div>
              {request.requestType === "petty_cash_replenishment" && request.cvNumber && (
                <div className="mt-2 flex justify-between gap-4">
                  <span className="text-[#5c6b7a]">CV Number</span>
                  <span className="font-semibold text-[#17243f]">{request.cvNumber}</span>
                </div>
              )}
              <div className="mt-2 flex justify-between gap-4">
                <span className="text-[#5c6b7a]">Created</span>
                <span className="font-semibold text-[#17243f]">{request.createdAt.toLocaleDateString("en-PH")}</span>
              </div>
              <div className="mt-2 flex justify-between gap-4">
                <span className="text-[#5c6b7a]">Due Date</span>
                <span className="font-semibold text-[#17243f]">{request.dueDate.toLocaleDateString("en-PH")}</span>
              </div>
              {departmentApprovalEvent && (
                <div className="mt-2 flex justify-between gap-4">
                  <span className="text-[#5c6b7a]">Dept. Approver</span>
                  <span className="text-right font-semibold text-[#17243f]">
                    {requestorDepartmentApproverName ??
                      departmentApprovalEvent.fromEmployee?.name ??
                      "Department approver"}
                    <span className="block text-xs font-medium text-[#5c6b7a]">
                      {departmentApprovalEvent.timestamp.toLocaleDateString("en-PH")}
                    </span>
                  </span>
                </div>
              )}
            </div>
          </section>
          <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            <div className="rounded-lg bg-[#e8f1ff] p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#245b9c]">Requested</p>
              <p className="mt-1 font-bold text-[#17243f]">{formatCurrency(request.amount)}</p>
            </div>
            <div className="rounded-lg bg-[#eef2f7] p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Transferred</p>
              <p className="mt-1 font-bold text-[#17243f]">{formatCurrency(acknowledgedTransferredAmount)}</p>
            </div>
            <div className="rounded-lg bg-[#e4fff0] p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#047a40]">Remaining</p>
              <p className="mt-1 font-bold text-[#17243f]">{formatCurrency(pendingLiquidationAmount)}</p>
            </div>
            <div className="rounded-lg bg-[#e2faf6] p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#08786f]">Spent</p>
              <p className="mt-1 font-bold text-[#17243f]">{formatCurrency(displayedAmountSpent)}</p>
            </div>
            <div className="rounded-lg bg-[#fff0f4] p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#d30f42]">Return</p>
              <p className="mt-1 font-bold text-[#17243f]">{formatCurrency(request.returnAmount)}</p>
            </div>
            <div className="rounded-lg bg-[#fff4c7] p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#9a6500]">Excess</p>
              <p className="mt-1 font-bold text-[#17243f]">{formatCurrency(displayedExcessAmount)}</p>
            </div>
          </section>
          {returnReason && (
            <section className="rounded-lg border border-[#ffbf00] bg-[#fff8d9] p-4">
              <h3 className="font-bold text-[#17243f]">Return Reason</h3>
              <p className="mt-2 text-sm text-[#5c6b7a]">{returnReason}</p>
              {latestReturnEvent?.fromEmployee && (
                <p className="mt-2 text-xs font-semibold uppercase tracking-wide text-[#9a6500]">
                  Returned by {latestReturnEvent.fromEmployee.name}
                </p>
              )}
            </section>
          )}
          {transferAllocationRows.length > 0 && (
            <section className="rounded-lg border border-[#c8d4df] bg-white p-4">
              <h3 className="font-bold text-[#17243f]">Transfer Allocation</h3>
              <div className="mt-3 space-y-2 text-sm">
                {transferAllocationRows.map((allocation) => (
                  <div key={allocation.id} className="flex justify-between gap-4">
                    <span className="text-[#5c6b7a]">
                      Receiver: {allocation.receiverName}
                      <span className="ml-1 text-xs">
                        ({allocation.status === "pending" ? "pending acknowledgement" : "acknowledged"})
                      </span>
                    </span>
                    <span
                      className={`shrink-0 font-semibold ${
                        allocation.status === "pending" ? "text-[#9a6500]" : "text-[#17243f]"
                      }`}
                    >
                      {formatCurrency(allocation.amount)}
                    </span>
                  </div>
                ))}
                <div className="flex justify-between gap-4 border-t border-[#eef2f7] pt-2">
                  <span className="font-semibold text-[#17243f]">Available/liquidated by owner</span>
                  <span className="shrink-0 font-semibold text-[#08786f]">{formatCurrency(liquidationBaseAmount)}</span>
                </div>
              </div>
            </section>
          )}
          {pendingTransfers.length > 0 && (
            <section className="rounded-lg border border-[#ffbf00] bg-[#fff8d9] p-4">
              <h3 className="font-bold text-[#17243f]">Pending Transfers</h3>
              <div className="mt-3 space-y-3">
                {pendingTransfers.map((pendingTransfer) => (
                  <div key={pendingTransfer.id} className="rounded-lg bg-white/70 p-3">
                    <p className="text-sm text-[#5c6b7a]">
                      {pendingTransfer.isWholeRequest ? "Whole request" : "Partial"} transfer of{" "}
                      <span className="font-semibold text-[#17243f]">{formatCurrency(pendingTransfer.amount)}</span>{" "}
                      from {pendingTransfer.fromEmployee.name} to {pendingTransfer.toEmployee.name}.
                    </p>
                    {pendingTransfer.notes && (
                      <p className="mt-2 text-sm text-[#5c6b7a]">{pendingTransfer.notes}</p>
                    )}
                  </div>
                ))}
              </div>
            </section>
          )}

          <section>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h3 className="font-bold text-[#17243f]">
                {pettyCashReceiptDetails.length > 0 ? "Petty Cash Receipts" : "Receipt Details"}
              </h3>
              {pettyCashReceiptDetails.length > 0 ? (
                <p className="text-sm font-semibold text-[#08786f]">
                  Total: {formatCurrency(pettyCashReceiptDetailsTotal)}
                </p>
              ) : (
                receiptDetails.length > 0 && (
                  <p className="text-sm font-semibold text-[#08786f]">Total: {formatCurrency(receiptDetailsTotal)}</p>
                )
              )}
            </div>
            <div className="mt-3 overflow-x-auto rounded-lg border border-[#d9e1e8] bg-white">
              {pettyCashReceiptDetails.length > 0 ? (
                <table className="min-w-[1120px] w-full text-left text-sm">
                  <thead className="bg-[#f3f6f9] text-xs uppercase tracking-wide text-[#5c6b7a]">
                    <tr>
                      <th className="px-3 py-3 font-semibold">OR#</th>
                      <th className="px-3 py-3 font-semibold">Company</th>
                      <th className="px-3 py-3 font-semibold">TIN</th>
                      <th className="px-3 py-3 font-semibold">Address</th>
                      <th className="px-3 py-3 font-semibold">Type of Expense</th>
                      <th className="px-3 py-3 font-semibold">Profit Cost Center</th>
                      <th className="px-3 py-3 font-semibold">Amount</th>
                      <th className="px-3 py-3 font-semibold">OR Date</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#eef2f7]">
                    {pettyCashReceiptDetails.map((detail) => (
                      <tr key={detail.id}>
                        <td className="px-3 py-3 font-semibold text-[#17243f]">{detail.orNumber}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.company}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.tin}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.address}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.natureOfExpense}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.costCenter}</td>
                        <td className="px-3 py-3 font-semibold text-[#08786f]">{formatCurrency(detail.amount)}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">
                          {detail.orDate ? new Date(detail.orDate).toLocaleDateString("en-PH") : ""}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : receiptDetails.length > 0 ? (
                <table className="min-w-[1050px] w-full text-left text-sm">
                  <thead className="bg-[#f3f6f9] text-xs uppercase tracking-wide text-[#5c6b7a]">
                    <tr>
                      <th className="px-3 py-3 font-semibold">Vendor</th>
                      <th className="px-3 py-3 font-semibold">Description</th>
                      <th className="px-3 py-3 font-semibold">Project</th>
                      <th className="px-3 py-3 font-semibold">Profit Cost Center</th>
                      <th className="px-3 py-3 font-semibold">Amount</th>
                      <th className="px-3 py-3 font-semibold">Invoice Ref.</th>
                      <th className="px-3 py-3 font-semibold">Type of Expense</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#eef2f7]">
                    {receiptDetails.map((detail) => (
                      <tr key={detail.id}>
                        <td className="px-3 py-3 font-semibold text-[#17243f]">{detail.vendor}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.description}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.project}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.profitCenter}</td>
                        <td className="px-3 py-3 font-semibold text-[#08786f]">{formatCurrency(detail.amount)}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.invoiceRef}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.expenseType}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : (
                <p className="px-4 py-8 text-center text-sm text-[#5c6b7a]">No receipt details submitted yet.</p>
              )}
            </div>
          </section>

          {pettyCashTransportationDetails.length > 0 && (
            <section>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <h3 className="font-bold text-[#17243f]">Transportation Expenses</h3>
                <p className="text-sm font-semibold text-[#08786f]">
                  Total: {formatCurrency(pettyCashTransportationDetailsTotal)}
                </p>
              </div>
              <div className="mt-3 overflow-x-auto rounded-lg border border-[#d9e1e8] bg-white">
                <table className="min-w-[900px] w-full text-left text-sm">
                  <thead className="bg-[#f3f6f9] text-xs uppercase tracking-wide text-[#5c6b7a]">
                    <tr>
                      <th className="px-3 py-3 font-semibold">Transaction Date</th>
                      <th className="px-3 py-3 font-semibold">Description</th>
                      <th className="px-3 py-3 font-semibold">From</th>
                      <th className="px-3 py-3 font-semibold">To</th>
                      <th className="px-3 py-3 font-semibold">Amount</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-[#eef2f7]">
                    {pettyCashTransportationDetails.map((detail) => (
                      <tr key={detail.id}>
                        <td className="px-3 py-3 text-[#5c6b7a]">
                          {detail.transactionDate ? new Date(detail.transactionDate).toLocaleDateString("en-PH") : ""}
                        </td>
                        <td className="px-3 py-3 font-semibold text-[#17243f]">{detail.description}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.from}</td>
                        <td className="px-3 py-3 text-[#5c6b7a]">{detail.to}</td>
                        <td className="px-3 py-3 font-semibold text-[#08786f]">{formatCurrency(detail.amount)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          )}

          <section>
            <h3 className="font-bold text-[#17243f]">Liquidation Notes</h3>
            <p className="mt-2 rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] p-4 text-sm text-[#5c6b7a]">
              {request.liquidationNotes || "No liquidation notes submitted yet."}
            </p>
          </section>

          <section>
            <h3 className="font-bold text-[#17243f]">Requestor Attachments</h3>
            <div className="mt-3 rounded-lg border border-[#d9e1e8] bg-white">
              {attachments.length > 0 ? (
                <div className="divide-y divide-[#eef2f7]">
                  {attachments.map((attachment) => (
                    <div
                      key={attachment.id}
                      className="flex flex-col gap-3 px-4 py-3 sm:flex-row sm:items-center sm:justify-between"
                    >
                      <div className="min-w-0">
                        <p className="font-semibold text-[#17243f]">{attachment.fileName}</p>
                        <p className="text-xs text-[#5c6b7a]">
                          Uploaded by requestor
                          {formatFileSize(attachment.fileSize) ? ` - ${formatFileSize(attachment.fileSize)}` : ""}
                        </p>
                      </div>
                      <div className="flex shrink-0 gap-2">
                        <button
                          type="button"
                          disabled={!attachment.downloadUrl}
                          onClick={() => setPreviewAttachmentId(attachment.id)}
                          className="rounded-full border border-[#0bb7a5] px-3 py-1 text-xs font-semibold text-[#08786f] hover:bg-[#e2faf6] disabled:cursor-not-allowed disabled:border-[#c8d4df] disabled:text-[#8b98a5]"
                        >
                          Preview
                        </button>
                        {attachment.downloadUrl ? (
                          <a
                            href={attachment.downloadUrl}
                            target="_blank"
                            rel="noreferrer"
                            className="rounded-full bg-[#0bb7a5] px-3 py-1 text-xs font-semibold text-white hover:bg-[#099988]"
                          >
                            Download
                          </a>
                        ) : (
                          <button
                            type="button"
                            disabled
                            className="rounded-full bg-[#d9e1e8] px-3 py-1 text-xs font-semibold text-[#5c6b7a]"
                          >
                            Download
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="px-4 py-8 text-center text-sm text-[#5c6b7a]">No attachments uploaded yet.</p>
              )}
            </div>
          </section>

          {receipt && (
            <section className="rounded-lg border border-[#00df72] bg-[#e4fff0] p-4">
              <h3 className="font-bold text-[#17243f]">
                {isPettyCash ? "Custodian Acknowledgement" : "Cashier's Attachment"}
              </h3>
              <p className="mt-2 text-sm text-[#047a40]">
                {receipt.receiptNumber} was created for {formatCurrency(receipt.returnAmount)}.
              </p>
              <div className="mt-3 rounded-lg border border-[#b9f4d0] bg-white/70 px-4 py-3">
                {depositSlipAttachment ? (
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <div className="min-w-0">
                      <p className="font-semibold text-[#17243f]">{depositSlipAttachment.fileName}</p>
                      <p className="text-xs text-[#047a40]">
                        Deposit Slip/AR
                        {formatFileSize(depositSlipAttachment.fileSize) ? ` - ${formatFileSize(depositSlipAttachment.fileSize)}` : ""}
                      </p>
                    </div>
                    <div className="flex shrink-0 gap-2">
                      <button
                        type="button"
                        disabled={!depositSlipAttachment.downloadUrl}
                        onClick={() => setPreviewAttachmentId(depositSlipAttachment.id)}
                        className="rounded-full border border-[#0bb7a5] px-3 py-1 text-xs font-semibold text-[#08786f] hover:bg-[#e2faf6] disabled:cursor-not-allowed disabled:border-[#c8d4df] disabled:text-[#8b98a5]"
                      >
                        Preview
                      </button>
                      {depositSlipAttachment.downloadUrl ? (
                        <a
                          href={depositSlipAttachment.downloadUrl}
                          target="_blank"
                          rel="noreferrer"
                          className="rounded-full bg-[#0bb7a5] px-3 py-1 text-xs font-semibold text-white hover:bg-[#099988]"
                        >
                          Download
                        </a>
                      ) : (
                        <button
                          type="button"
                          disabled
                          className="rounded-full bg-[#d9e1e8] px-3 py-1 text-xs font-semibold text-[#5c6b7a]"
                        >
                          Download
                        </button>
                      )}
                    </div>
                  </div>
                ) : (
                  <p className="text-sm text-[#047a40]">
                    {isPettyCash ? "Returned excess cash acknowledged by custodian." : "Deposit Slip/AR attachment pending."}
                  </p>
                )}
              </div>
            </section>
          )}
        </div>

          <aside className="overflow-y-auto border-t border-[#d9e1e8] bg-[#f8fafc] p-6 lg:border-l lg:border-t-0">
            <div className="lg:sticky lg:top-6">
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">Attachment Preview</p>
                  <h3 className="mt-1 truncate text-lg font-bold text-[#17243f]">
                    {selectedAttachment?.fileName ?? "Select an attachment"}
                  </h3>
                  {selectedAttachment && (
                    <p className="mt-1 text-xs text-[#5c6b7a]">
                      {selectedAttachment.sourceLabel}
                      {selectedFileSize ? ` - ${selectedFileSize}` : ""}
                    </p>
                  )}
                </div>
                {selectedAttachment?.downloadUrl && (
                  <a
                    href={selectedAttachment.downloadUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="shrink-0 rounded-full bg-[#0bb7a5] px-3 py-1 text-xs font-semibold text-white hover:bg-[#099988]"
                  >
                    Download
                  </a>
                )}
              </div>

              <div className="mt-4 flex h-[420px] items-center justify-center overflow-hidden rounded-lg border border-[#d9e1e8] bg-white lg:h-[calc(90vh-260px)]">
                {selectedAttachment && selectedPreviewUrl ? (
                  canInlinePreview ? (
                    isImageFile(selectedAttachment) ? (
                      <img
                        src={selectedPreviewUrl}
                        alt={selectedAttachment.fileName}
                        className="h-full w-full object-contain"
                      />
                    ) : (
                      <iframe
                        src={selectedPreviewUrl}
                        title={selectedAttachment.fileName}
                        className="h-full w-full"
                      />
                    )
                  ) : (
                    <div className="px-6 text-center text-sm text-[#5c6b7a]">
                      <p className="font-semibold text-[#17243f]">Preview unavailable</p>
                      <p className="mt-2">Use Download to open this file.</p>
                    </div>
                  )
                ) : (
                  <div className="px-6 text-center text-sm text-[#5c6b7a]">
                    <p className="font-semibold text-[#17243f]">No preview selected</p>
                    <p className="mt-2">Click Preview beside an attachment to view it here.</p>
                  </div>
                )}
              </div>
            </div>
          </aside>
        </div>

        <div className="flex flex-col gap-3 border-t border-[#d9e1e8] p-6 sm:flex-row">
          {onLiquidate && (
            <button
              type="button"
              onClick={() => {
                onLiquidate(request);
                onClose();
              }}
              className="flex-1 rounded-lg bg-[#ff1550] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#e51147]"
            >
              {liquidateLabel}
            </button>
          )}
          {onTransfer && (
            <button
              type="button"
              onClick={() => {
                onTransfer(request);
                onClose();
              }}
              className="flex-1 rounded-lg bg-slate-500 border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-white hover:bg-slate-600"
            >
              Transfer
            </button>
          )}
          {onUploadRfp && (
            <button
              type="button"
              onClick={() => {
                onUploadRfp(request);
                onClose();
              }}
              className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
            >
              Upload RFP
            </button>
          )}
          {canPrint && (
            <button
              type="button"
              onClick={() => onPrint(request)}
              className="flex-1 rounded-lg bg-[#4e6493] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#24365c]"
            >
              Print
            </button>
          )}
          {onCreateReceipt && (
            <button
              type="button"
              onClick={() => onCreateReceipt(request)}
              className="flex-1 rounded-lg bg-[#4e6493] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#24365c]"
            >
              {receipt ? "Continue AR" : "Create AR"}
            </button>
          )}
          {canDecide && (
            <>
              {onApprove && (
                <button
                  type="button"
                  onClick={() => {
                    setRfpDecision("create");
                    setWaiveReason("");
                    setShowApproveConfirm(true);
                  }}
                  className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
                >
                  {approveLabel}
                </button>
              )}
              {onReject && (
                <button
                  type="button"
                  onClick={rejectRequest}
                  className="flex-1 rounded-lg border border-[#ff1550] px-4 py-3 text-sm font-semibold text-[#ff1550] hover:bg-[#fff0f4]"
                >
                  {rejectLabel}
                </button>
              )}
            </>
          )}
          <button
            type="button"
            onClick={onClose}
            className={`rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9] ${
              hasWorkflowActions ? "flex-1" : "w-full"
            }`}
          >
            Close
          </button>
        </div>
      </div>

      {showApproveConfirm && (
        <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4">
          <div className="w-full max-w-md rounded-lg bg-white shadow-xl">
            <div className="border-b border-[#d9e1e8] p-6">
              <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">
                {isTransferAcknowledgement ? "Confirm Transfer" : isCashierClosure ? "Confirm Closure" : "Confirm Approval"}
              </p>
              <h3 className="mt-1 text-xl font-bold text-[#17243f]">
                {isTransferAcknowledgement
                  ? "Acknowledge this transfer?"
                  : isCashierClosure
                    ? "Close this liquidation?"
                    : "Approve this request?"}
              </h3>
              <p className="mt-2 text-sm text-[#5c6b7a]">
                {isTransferAcknowledgement
                  ? `${request.requestNumber} will be assigned or split after acknowledgement.`
                  : isCashierClosure
                    ? `${request.requestNumber} will be marked as fully liquidated.`
                    : `${request.requestNumber} will move to the next step in the workflow.`}
              </p>
            </div>
            <div className="space-y-4 p-6">
              {needsRfpDecision && (
                <>
                  <div>
                    <label className="block text-sm font-semibold text-[#17243f]" htmlFor="details-rfp-decision">
                      RFP Action
                    </label>
                    <select
                      id="details-rfp-decision"
                      value={rfpDecision}
                      onChange={(event) => setRfpDecision(event.target.value as RfpDecision)}
                      className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
                    >
                      <option value="create">Create RFP</option>
                      <option value="waive">Waive RFP</option>
                    </select>
                  </div>
                  {needsCompany && <RfpCompanySelect value={rfpCompanyId} onChange={setRfpCompanyId} />}
                  {rfpDecision === "waive" && (
                    <div>
                      <label className="block text-sm font-semibold text-[#17243f]" htmlFor="details-rfp-waive-reason">
                        Reason
                      </label>
                      <textarea
                        id="details-rfp-waive-reason"
                        value={waiveReason}
                        onChange={(event) => setWaiveReason(event.target.value)}
                        rows={3}
                        className="mt-2 w-full resize-none rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
                      />
                      {isWaiveReasonMissing && (
                        <p className="mt-2 text-xs font-semibold text-[#d30f42]">Reason is required to waive RFP.</p>
                      )}
                    </div>
                  )}
                </>
              )}
              <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setShowApproveConfirm(false)}
                className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
              >
                No
              </button>
              <button
                type="button"
                onClick={confirmApprove}
                disabled={isWaiveReasonMissing || isCompanyMissing}
                className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
              >
                {isTransferAcknowledgement || isCashierClosure ? "Yes" : "Approve"}
              </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
