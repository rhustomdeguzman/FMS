import type { AcknowledgementReceipt, CashAdvanceRequest } from "../../types/CashAdvance";
import { isPettyCashWorkflowRequest } from "../../pettyCash";
import StatusBadge from "../StatusBadge";

interface CashierPanelProps {
  requests: CashAdvanceRequest[];
  onCreateReceipt: (request: CashAdvanceRequest) => void;
  onCloseLiquidation: (request: CashAdvanceRequest) => void;
  onViewReceipt: (receipt: AcknowledgementReceipt, request: CashAdvanceRequest) => void;
  onOpenDetails: (request: CashAdvanceRequest) => void;
}

export default function CashierPanel({
  requests,
  onCreateReceipt,
  onCloseLiquidation,
  onViewReceipt,
  onOpenDetails,
}: CashierPanelProps) {
  const pendingReturns = requests.filter((request) => request.status === "pending_cashier_return");
  const pendingClosures = requests.filter((request) => request.status === "pending_cashier_closure");
  const acknowledged = requests.filter(
    (request) => !isPettyCashWorkflowRequest(request) && request.acknowledgementReceipt?.status === "acknowledged",
  );
  const totalPending = pendingReturns.reduce((sum, request) => sum + (request.returnAmount ?? 0), 0);

  return (
    <section className="space-y-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-xl font-bold text-[#17243f]">Cashier Dashboard</h2>
          <p className="mt-1 text-sm text-[#5c6b7a]">Create acknowledgement receipt drafts, upload deposit slips, then close after accounting approval.</p>
        </div>
        <div className="rounded-lg border border-[#ff1550] bg-[#fff0f4] px-4 py-3 text-right">
          <p className="text-xs font-semibold uppercase tracking-wide text-[#d30f42]">Pending Returns</p>
          <p className="text-xl font-bold text-[#17243f]">PHP {totalPending.toLocaleString()}</p>
        </div>
      </div>

      <div className="grid gap-4">
        {pendingReturns.map((request) => (
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
              <div>
                <div className="flex flex-wrap items-center gap-3">
                  <h3 className="font-bold text-[#17243f]">{request.requestNumber}</h3>
                  <StatusBadge status={request.status} request={request} />
                </div>
                <p className="mt-2 text-sm text-[#5c6b7a]">{request.purpose}</p>
                <p className="mt-2 text-sm font-semibold text-[#d30f42]">
                  Return amount: PHP {(request.returnAmount ?? 0).toLocaleString()}
                </p>
                {request.acknowledgementReceipt && (
                  <p className="mt-1 text-xs font-semibold text-[#0b6f68]">
                    Draft AR: {request.acknowledgementReceipt.receiptNumber}
                  </p>
                )}
              </div>
              <div className="flex flex-wrap gap-2">
                {request.acknowledgementReceipt && (
                  <button
                    type="button"
                    onClick={(event) => {
                      event.stopPropagation();
                      onViewReceipt(request.acknowledgementReceipt!, request);
                    }}
                    className="rounded-lg bg-[#ff1550] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#e51147]"
                  >
                    View Receipt
                  </button>
                )}
                <button
                  type="button"
                  onClick={(event) => {
                    event.stopPropagation();
                    onCreateReceipt(request);
                  }}
                  className="rounded-lg bg-[#0bb7a5] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
                >
                  {request.acknowledgementReceipt ? "Continue Draft" : "Create AR"}
                </button>
              </div>
            </div>
          </article>
        ))}
      </div>

      {pendingReturns.length === 0 && (
        <div className="rounded-lg border border-dashed border-[#b9c8d4] bg-white px-5 py-12 text-center text-sm text-[#5c6b7a]">
          No cash returns are waiting for acknowledgement receipt.
        </div>
      )}

      <div className="rounded-lg border border-[#d9e1e8] bg-white p-5 shadow-sm">
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h3 className="font-bold text-[#17243f]">Incoming Payments</h3>
          </div>
          <span className="rounded-lg bg-[#f3f6f9] px-3 py-2 text-sm font-semibold text-[#17243f]">
            {pendingClosures.length} pending
          </span>
        </div>
        <div className="mt-4 grid gap-3">
          {pendingClosures.map((request) => (
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
              className="cursor-pointer rounded-lg border border-[#d9e1e8] bg-white p-4 transition hover:border-[#0bb7a5]"
            >
              <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                <div>
                  <div className="flex flex-wrap items-center gap-3">
                    <h4 className="font-bold text-[#17243f]">{request.requestNumber}</h4>
                    <StatusBadge status={request.status} request={request} />
                  </div>
                  <p className="mt-2 text-sm text-[#5c6b7a]">{request.purpose}</p>
                  <p className="mt-2 text-sm font-semibold text-[#08786f]">
                    Returned amount: PHP {(request.returnAmount ?? 0).toLocaleString()}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  {/* {request.acknowledgementReceipt && (
                    <button
                      type="button"
                      onClick={(event) => {
                        event.stopPropagation();
                        onViewReceipt(request.acknowledgementReceipt!, request);
                      }}
                      className="rounded-lg border border-[#d9e1e8] px-4 py-2 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
                    >
                      View Receipt
                    </button>
                  )} */}
                  <button
                    type="button"
                    onClick={(event) => {
                      event.stopPropagation();
                      onCloseLiquidation(request);
                    }}
                    className="rounded-lg bg-[#0bb7a5] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
                  >
                    Complete
                  </button>
                </div>
              </div>
            </article>
          ))}
          {pendingClosures.length === 0 && (
            <p className="rounded-lg border border-dashed border-[#b9c8d4] px-5 py-8 text-center text-sm text-[#5c6b7a]">
              No liquidations are waiting for cashier closure.
            </p>
          )}
        </div>
      </div>

      <div className="rounded-lg border border-[#d9e1e8] bg-white p-5 shadow-sm">
        <h3 className="font-bold text-[#17243f]">Generated Acknowledgement Receipts</h3>
        <div className="mt-4 divide-y divide-[#eef2f7]">
          {acknowledged.map((request) => (
            <button
              type="button"
              key={request.id}
              onClick={() => request.acknowledgementReceipt && onViewReceipt(request.acknowledgementReceipt, request)}
              className="flex w-full justify-between gap-4 py-3 text-left hover:bg-[#f3f6f9]"
            >
              <span className="font-semibold text-[#17243f]">{request.requestNumber}</span>
              <span className="text-sm text-[#5c6b7a]">{request.acknowledgementReceipt?.receiptNumber}</span>
            </button>
          ))}
          {acknowledged.length === 0 && <p className="py-5 text-sm text-[#5c6b7a]">No completed cashier acknowledgements yet.</p>}
        </div>
      </div>
    </section>
  );
}
