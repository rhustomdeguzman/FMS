import type { AcknowledgementReceipt, CashAdvanceRequest } from "../../types/CashAdvance";
import { isPettyCashWorkflowRequest } from "../../pettyCash";

interface AcknowledgementReceiptModalProps {
  receipt: AcknowledgementReceipt;
  request: CashAdvanceRequest;
  onClose: () => void;
  onPrint: () => void;
}

export default function AcknowledgementReceiptModal({
  receipt,
  request,
  onClose,
  onPrint,
}: AcknowledgementReceiptModalProps) {
  const isPettyCash = isPettyCashWorkflowRequest(request);
  const actualSpent = request.liquidationAmount ?? Math.max(request.liquidatedAmount - receipt.returnAmount, 0);
  const liquidatedTotal = Math.min(
    request.amount,
    actualSpent + (receipt.status === "acknowledged" ? receipt.returnAmount : 0),
  );

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="w-full max-w-lg rounded-lg bg-white shadow-xl">
        <div className="flex items-start justify-between gap-4 border-b border-[#d9e1e8] p-6">
          <div>
            <h2 className="text-xl font-bold text-[#17243f]">Acknowledgement Receipt</h2>
            <p className="mt-1 text-sm text-[#5c6b7a]">{receipt.receiptNumber}</p>
          </div>
          <span
            className={`rounded-full border px-3 py-1 text-xs font-semibold ${
              receipt.status === "acknowledged"
                ? "border-[#00df72] bg-[#e4fff0] text-[#047a40]"
                : "border-[#ffc400] bg-[#fff4c7] text-[#9a6500]"
            }`}
          >
            {receipt.status === "acknowledged" ? "Acknowledged" : "Pending"}
          </span>
        </div>

        <div id="receipt-print-area" className="space-y-5 p-6">
          <div className="border-b border-dashed border-[#b9c8d4] pb-4 text-center">
            <h3 className="font-bold text-[#17243f]">Cash Return Acknowledgement</h3>
            <p className="mt-1 text-xs text-[#5c6b7a]">Fund Management System</p>
          </div>

          <div className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Receipt No.</p>
              <p className="font-semibold text-[#17243f]">{receipt.receiptNumber}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Date Issued</p>
              <p className="font-semibold text-[#17243f]">{receipt.issuedAt.toLocaleDateString("en-PH")}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Request No.</p>
              <p className="font-semibold text-[#17243f]">{receipt.requestNumber}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Original Amount</p>
              <p className="font-semibold text-[#17243f]">PHP {request.amount.toLocaleString()}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Actual Spent</p>
              <p className="font-semibold text-[#17243f]">PHP {actualSpent.toLocaleString()}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Return Amount</p>
              <p className="font-bold text-[#d30f42]">PHP {receipt.returnAmount.toLocaleString()}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Liquidated</p>
              <p className="font-bold text-[#047a40]">PHP {liquidatedTotal.toLocaleString()}</p>
            </div>
            <div className="col-span-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Acknowledgement Receipt PDF</p>
              <p className="font-semibold text-[#17243f]">{receipt.attachmentFileName ?? "No attachment"}</p>
            </div>
            <div className="col-span-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Deposit Slip</p>
              <p className="font-semibold text-[#17243f]">
                {receipt.depositSlipFileName ?? (isPettyCash ? "Not required for custodian return" : "No deposit slip attached")}
              </p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Deposit Date</p>
              <p className="font-semibold text-[#17243f]">
                {receipt.depositDate ? receipt.depositDate.toLocaleDateString("en-PH") : "Not set"}
              </p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Deposit Amount</p>
              <p className="font-semibold text-[#17243f]">
                {receipt.depositAmount == null ? "Not set" : `PHP ${receipt.depositAmount.toLocaleString()}`}
              </p>
            </div>
            <div className="col-span-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Depository Bank</p>
              <p className="font-semibold text-[#17243f]">{receipt.depositoryBank ?? "Not set"}</p>
            </div>
          </div>

          <p className="rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] p-4 text-sm text-[#5c6b7a]">
            This certifies that {receipt.requestor.name} returned PHP {receipt.returnAmount.toLocaleString()} from
            {isPettyCash ? " petty cash request " : " cash advance request "}{receipt.requestNumber}.
          </p>

          {receipt.status === "acknowledged" && receipt.acknowledgedBy && (
            <div className="rounded-lg border border-[#00df72] bg-[#e4fff0] p-4 text-sm text-[#047a40]">
              Acknowledged by {receipt.acknowledgedBy.name} on {receipt.acknowledgedAt?.toLocaleString("en-PH")}.
              {receipt.notes && <p className="mt-2">{receipt.notes}</p>}
            </div>
          )}
        </div>

        <div className="flex gap-3 border-t border-[#d9e1e8] p-6">
          <button
            type="button"
            onClick={onClose}
            className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
          >
            Close
          </button>
          <button
            type="button"
            onClick={onPrint}
            className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
          >
            Print
          </button>
        </div>
      </div>
    </div>
  );
}
