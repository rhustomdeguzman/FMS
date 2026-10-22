import type { AcknowledgementReceipt, CashAdvanceRequest, TransactionAction } from "../../types/CashAdvance";
import StatusBadge from "../StatusBadge";

interface HistoryModalProps {
  request: CashAdvanceRequest;
  onClose: () => void;
  onViewReceipt: (receipt: AcknowledgementReceipt) => void;
}

const actionLabels: Record<TransactionAction, string> = {
  created: "Created",
  approved_by_department_head: "Department Approved",
  approved_by_accounting: "Accounting Approved",
  liquidation_submitted: "Liquidation Submitted",
  sent_to_accounting: "Sent to Accounting",
  returned: "Returned",
  rejected: "Rejected",
  transfer_requested: "Transfer Requested",
  transfer_acknowledged: "Transfer Acknowledged",
  transfer_denied: "Transfer Denied",
  transferred: "Transferred",
  partially_liquidated: "Partially Liquidated",
  fully_liquidated: "Fully Liquidated",
  excess_created: "Excess RFP Created",
  rfp_created: "RFP Created",
  rfp_waived: "RFP Waived",
  rfp_attachment_uploaded: "RFP Attachment Uploaded",
  return_to_cashier: "Return to Cashier",
  acknowledged: "Cashier Receipt Created",
  petty_cash_requested: "Petty Cash Requested",
  approved_by_custodian: "Custodian Approved",
  petty_cash_released: "Petty Cash Released",
  petty_cash_replenishment_created: "Replenishment RFP Created",
  petty_cash_replenished: "Petty Cash Replenished",
};

export default function HistoryModal({ request, onClose }: HistoryModalProps) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-lg bg-white shadow-xl">
        <div className="flex items-start justify-between gap-4 border-b border-[#d9e1e8] p-6">
          <div>
            <h2 className="text-xl font-bold text-[#17243f]">Request History</h2>
            <p className="mt-1 text-sm text-[#5c6b7a]">{request.requestNumber}</p>
          </div>
          <StatusBadge status={request.status} request={request} />
        </div>

        <div className="p-6">
          <div className="rounded-lg bg-[#f3f6f9] p-4">
            <p className="font-semibold text-[#17243f]">{request.purpose}</p>
            <p className="mt-1 text-sm text-[#5c6b7a]">
              {request.department} - PHP {request.amount.toLocaleString()}
            </p>
          </div>

          <div className="mt-6 space-y-4">
            {request.history.map((event) => (
              <div key={event.id} className="rounded-lg border border-[#d9e1e8] p-4">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <p className="font-semibold text-[#17243f]">{actionLabels[event.action]}</p>
                  <p className="text-xs text-[#5c6b7a]">{event.timestamp.toLocaleString("en-PH")}</p>
                </div>
                {event.amount != null && (
                  <p className="mt-2 text-sm font-semibold text-[#08786f]">Amount: PHP {event.amount.toLocaleString()}</p>
                )}
                {(event.fromEmployee || event.toEmployee) && (
                  <p className="mt-2 text-sm text-[#5c6b7a]">
                    {event.fromEmployee?.name ?? "System"}
                  </p>
                )}
                {event.notes && <p className="mt-2 text-sm text-[#5c6b7a]">{event.notes}</p>}
              </div>
            ))}
          </div>

          {/* {request.acknowledgementReceipt && (
            <button
              type="button"
              onClick={() => onViewReceipt(request.acknowledgementReceipt!)}
              className="mt-6 rounded-lg bg-[#ff1550] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#e51147]"
            >
              View Acknowledgement Receipt
            </button>
          )} */}
        </div>

        <div className="border-t border-[#d9e1e8] p-6">
          <button
            type="button"
            onClick={onClose}
            className="w-full rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
