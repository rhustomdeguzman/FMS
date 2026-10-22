import { useState } from "react";
import type { CashAdvanceRequest } from "../../types/CashAdvance";

interface CashierReceiptModalProps {
  request: CashAdvanceRequest;
  initialReceiptNumber?: string;
  variant?: "cashier" | "custodian";
  onClose: () => void;
  onSubmit: (
    requestId: string,
    receiptNumber: string,
    depositSlipAttachment: File | null,
    depositDate: string,
    depositAmount: number,
    depositoryBank: string,
    notes: string,
  ) => void;
}

const toDateInputValue = (date?: Date) => {
  if (!date) {
    return "";
  }

  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

export default function CashierReceiptModal({
  request,
  initialReceiptNumber,
  variant = "cashier",
  onClose,
  onSubmit,
}: CashierReceiptModalProps) {
  const isCustodianReceipt = variant === "custodian";
  const [receiptNumber, setReceiptNumber] = useState(
    () =>
      request.acknowledgementReceipt?.receiptNumber ?? initialReceiptNumber ??
      (isCustodianReceipt ? `ACK-${request.requestNumber}` : `ACK-${request.requestNumber}-${Date.now().toString().slice(-5)}`),
  );
  const [depositSlipFile, setDepositSlipFile] = useState<File | null>(null);
  const [depositDate, setDepositDate] = useState(
    () => toDateInputValue(request.acknowledgementReceipt?.depositDate) || toDateInputValue(new Date()),
  );
  const [depositAmountInput, setDepositAmountInput] = useState(
    () => String(request.acknowledgementReceipt?.depositAmount ?? request.returnAmount ?? ""),
  );
  const [depositoryBank, setDepositoryBank] = useState(request.acknowledgementReceipt?.depositoryBank ?? "");
  const [notes, setNotes] = useState(request.acknowledgementReceipt?.notes ?? "");
  const [showConfirm, setShowConfirm] = useState(false);

  const parsedDepositAmount = depositAmountInput.trim() === "" ? 0 : Number(depositAmountInput);
  const depositAmount = Number.isFinite(parsedDepositAmount) ? parsedDepositAmount : 0;
  const hasDepositSlip = depositSlipFile !== null;
  const hasCompleteDepositDetails =
    depositDate.trim().length > 0 && depositAmount > 0 && depositoryBank.trim().length > 0;
  const canSubmit = receiptNumber.trim().length > 0 && (!hasDepositSlip || hasCompleteDepositDetails);
  const primaryActionLabel = isCustodianReceipt ? "Acknowledge" : hasDepositSlip ? "Proceed" : "Save as Draft";
  const submitReceipt = (depositSlipAttachment: File | null) =>
    onSubmit(
      request.id,
      receiptNumber.trim(),
      depositSlipAttachment,
      depositDate,
      depositAmount,
      depositoryBank.trim(),
      notes.trim(),
    );

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="max-h-[calc(100vh-2rem)] w-full max-w-lg overflow-y-auto rounded-lg bg-white shadow-xl">
        <div className="border-b border-[#d9e1e8] p-6">
          <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">
            {isCustodianReceipt ? "Custodian Acknowledgement" : "Cashier Acknowledgement"}
          </p>
          <h2 className="mt-1 text-xl font-bold text-[#17243f]">Create Acknowledgement Receipt</h2>
          <p className="mt-1 text-sm text-[#5c6b7a]">{request.requestNumber}</p>
        </div>

        <div className="space-y-5 p-6">
          <div className="rounded-lg bg-[#fff0f4] p-4 text-sm">
            <div className="flex justify-between gap-4">
              <span className="text-[#5c6b7a]">Return Amount</span>
              <span className="font-bold text-[#d30f42]">PHP {(request.returnAmount ?? 0).toLocaleString()}</span>
            </div>
            <div className="mt-2 flex justify-between gap-4">
              <span className="text-[#5c6b7a]">Requestor</span>
              <span className="font-semibold text-[#17243f]">{request.currentOwner.name}</span>
            </div>
          </div>

          <div>
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="receiptNumber">
              Receipt Number
            </label>
            <input
              id="receiptNumber"
              type="text"
              value={receiptNumber}
              onChange={(event) => setReceiptNumber(event.target.value)}
              className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
          </div>

          {!isCustodianReceipt && (
            <>
              <div>
                <label className="block text-sm font-semibold text-[#17243f]" htmlFor="depositSlipFile">
                  Deposit Slip/AR Attachment
                  {hasDepositSlip && <span className="text-rose-400"> *</span>}
                </label>
                <input
                  id="depositSlipFile"
                  type="file"
                  accept=".pdf,.jpg,.jpeg,.png"
                  onChange={(event) => setDepositSlipFile(event.target.files?.[0] ?? null)}
                  className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm"
                />
                {depositSlipFile && <p className="mt-2 text-xs text-[#5c6b7a]">{depositSlipFile.name}</p>}
                {!hasDepositSlip && (
                  <p className="mt-2 text-xs text-[#5c6b7a]">
                    Save as draft now, then upload the Deposit Slip/AR attachment later to proceed to Accounting.
                  </p>
                )}
              </div>

              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <label className="block text-sm font-semibold text-[#17243f]" htmlFor="depositDate">
                    Deposit Date {hasDepositSlip && <span className="text-rose-400">*</span>}
                  </label>
                  <input
                    id="depositDate"
                    type="date"
                    value={depositDate}
                    onChange={(event) => setDepositDate(event.target.value)}
                    className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
                  />
                </div>

                <div>
                  <label className="block text-sm font-semibold text-[#17243f]" htmlFor="depositAmount">
                    Deposit Amount {hasDepositSlip && <span className="text-rose-400">*</span>}
                  </label>
                  <input
                    id="depositAmount"
                    type="number"
                    min={0}
                    step="0.01"
                    value={depositAmountInput}
                    onChange={(event) => setDepositAmountInput(event.target.value)}
                    className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-semibold text-[#17243f]" htmlFor="depositoryBank">
                  Depository Bank {hasDepositSlip && <span className="text-rose-400">*</span>}
                </label>
                <input
                  id="depositoryBank"
                  type="text"
                  value={depositoryBank}
                  onChange={(event) => setDepositoryBank(event.target.value)}
                  className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
                />
              </div>
            </>
          )}

          <div>
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="receiptNotes">
              Notes
            </label>
            <textarea
              id="receiptNotes"
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              rows={3}
              className="mt-2 w-full resize-none rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
          </div>
        </div>

        <div className="flex gap-3 border-t border-[#d9e1e8] p-6">
          <button
            type="button"
            disabled={!canSubmit}
            onClick={() => (hasDepositSlip && !isCustodianReceipt ? setShowConfirm(true) : submitReceipt(null))}
            className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {primaryActionLabel}
          </button>
          <button
            type="button"
            onClick={onClose}
            className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
          >
            Cancel
          </button>
        </div>
      </div>

      {showConfirm && depositSlipFile && (
        <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 p-4">
          <div className="w-full max-w-md rounded-lg bg-white shadow-xl">
            <div className="border-b border-[#d9e1e8] p-6">
              <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">Confirm Receipt</p>
              <h3 className="mt-1 text-xl font-bold text-[#17243f]">Proceed to Accounting?</h3>
              <p className="mt-2 text-sm text-[#5c6b7a]">
                {depositSlipFile.name} will be attached as the Deposit Slip/AR file for {request.requestNumber}.
              </p>
            </div>
            <div className="flex gap-3 p-6">
              <button
                type="button"
                onClick={() => setShowConfirm(false)}
                className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
              >
                No
              </button>
              <button
                type="button"
                onClick={() => submitReceipt(depositSlipFile)}
                className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
              >
                Yes, Proceed
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
