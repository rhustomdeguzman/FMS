import { useState } from "react";
import { getTransferAdjustedRequestAmount, getTransferredOutAmount } from "../../liquidationAmounts";
import type { CashAdvanceRequest, RfpDecision } from "../../types/CashAdvance";
import StatusBadge from "../StatusBadge";
import RfpCompanySelect from "./RfpCompanySelect";

interface ApprovalQueueProps {
  title: string;
  description: string;
  requests: CashAdvanceRequest[];
  approveLabel: string;
  rejectLabel: string;
  emptyMessage: string;
  onApprove: (request: CashAdvanceRequest, rfpDecision?: RfpDecision, waiveReason?: string, companyId?: number) => void;
  isLiveMode?: boolean;
  onReject: (request: CashAdvanceRequest) => boolean | void;
  onHistory: (request: CashAdvanceRequest) => void;
  onOpenDetails: (request: CashAdvanceRequest) => void;
}

export default function ApprovalQueue({
  title,
  description,
  requests,
  approveLabel,
  rejectLabel,
  emptyMessage,
  onApprove,
  onReject,
  onHistory,
  onOpenDetails,
  isLiveMode = false,
}: ApprovalQueueProps) {
  const [approvalRequest, setApprovalRequest] = useState<CashAdvanceRequest | null>(null);
  const [rfpDecision, setRfpDecision] = useState<RfpDecision>("create");
  const [waiveReason, setWaiveReason] = useState("");
  const [rfpCompanyId, setRfpCompanyId] = useState<number>();
  const needsRfpDecision =
    approvalRequest !== null &&
    (approvalRequest.status === "pending_department_approval" ||
      approvalRequest.status === "pending_rfp_department_approval") &&
    (approvalRequest.excessAmount ?? 0) > 0;
  const isWaiveReasonMissing = needsRfpDecision && rfpDecision === "waive" && waiveReason.trim().length === 0;
  const needsCompany = isLiveMode && needsRfpDecision && rfpDecision === "create" && !approvalRequest?.companyId;
  const isCompanyMissing = needsCompany && !rfpCompanyId;

  const openApproval = (request: CashAdvanceRequest) => {
    setApprovalRequest(request);
    setRfpDecision("create");
    setWaiveReason("");
    setRfpCompanyId(undefined);
  };

  const confirmApproval = () => {
    if (approvalRequest && !isWaiveReasonMissing && !isCompanyMissing) {
      onApprove(
        approvalRequest,
        needsRfpDecision ? rfpDecision : undefined,
        needsRfpDecision && rfpDecision === "waive" ? waiveReason.trim() : undefined,
        needsCompany ? rfpCompanyId : undefined,
      );
      setApprovalRequest(null);
    }
  };

  return (
    <section className="space-y-5">
      <div>
        <h2 className="text-xl font-bold text-[#17243f]">{title}</h2>
        <p className="mt-1 text-sm text-[#5c6b7a]">{description}</p>
      </div>

      <div className="grid gap-4">
        {requests.map((request) => {
          const displayAmount = getTransferAdjustedRequestAmount(request);
          const transferredAmount = getTransferredOutAmount(request);

          return (
            <article
              key={request.id}
              role="button"
              tabIndex={0}
              onClick={() => onOpenDetails(request)}
              onKeyDown={(event) => {
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault();
                  onOpenDetails(request);
                }
              }}
              className="cursor-pointer rounded-lg border border-[#d9e1e8] bg-white p-5 shadow-sm transition hover:border-[#0bb7a5]"
            >
              <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-3">
                    <h3 className="font-bold text-[#17243f]">{request.requestNumber}</h3>
                    <StatusBadge status={request.status} request={request} />
                  </div>
                  <p className="mt-2 text-sm text-[#5c6b7a]">{request.purpose}</p>
                  <p className="mt-2 text-xs font-medium uppercase tracking-wide text-[#5c6b7a]">
                    {request.department} - {request.currentOwner.name} - {request.sourceSystem}
                  </p>
                </div>

                <div className="flex shrink-0 flex-col gap-3 sm:flex-row sm:items-center">
                  <div className="rounded-lg bg-[#fff4c7] px-4 py-3 text-right">
                    <p className="text-xs font-medium uppercase tracking-wide text-[#9a6500]">Amount</p>
                    <p className="font-bold text-[#17243f]">PHP {displayAmount.toLocaleString()}</p>
                    {transferredAmount > 0 && (
                      <p className="text-xs font-semibold text-[#08786f]">PHP {transferredAmount.toLocaleString()} transferred</p>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={(event) => {
                      event.stopPropagation();
                      openApproval(request);
                    }}
                    className="rounded-lg bg-[#0bb7a5] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
                  >
                    {approveLabel}
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
                  <button
                    type="button"
                    onClick={(event) => {
                      event.stopPropagation();
                      onHistory(request);
                    }}
                    className="rounded-lg border border-[#d9e1e8] px-4 py-2 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
                  >
                    History
                  </button>
                </div>
              </div>
            </article>
          );
        })}
      </div>

      {requests.length === 0 && (
        <div className="rounded-lg border border-dashed border-[#b9c8d4] bg-white px-5 py-12 text-center text-sm text-[#5c6b7a]">
          {emptyMessage}
        </div>
      )}

      {approvalRequest && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="w-full max-w-md rounded-lg bg-white shadow-xl">
            <div className="border-b border-[#d9e1e8] p-6">
              <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">Confirm Approval</p>
              <h3 className="mt-1 text-xl font-bold text-[#17243f]">Approve this request?</h3>
              <p className="mt-2 text-sm text-[#5c6b7a]">
                {approvalRequest.requestNumber} will move to the next step in the workflow.
              </p>
            </div>
            <div className="space-y-4 p-6">
              {needsRfpDecision && (
                <>
                  <div>
                    <label className="block text-sm font-semibold text-[#17243f]" htmlFor="rfp-decision">
                      RFP Action
                    </label>
                    <select
                      id="rfp-decision"
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
                      <label className="block text-sm font-semibold text-[#17243f]" htmlFor="rfp-waive-reason">
                        Reason
                      </label>
                      <textarea
                        id="rfp-waive-reason"
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
                onClick={() => setApprovalRequest(null)}
                className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
              >
                No
              </button>
              <button
                type="button"
                onClick={confirmApproval}
                disabled={isWaiveReasonMissing || isCompanyMissing}
                className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
              >
                Approve
              </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
