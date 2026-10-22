import { useState } from "react";
import type { CashAdvanceRequest } from "../../types/CashAdvance";

interface ReturnReasonModalProps {
  request: CashAdvanceRequest;
  reviewerLabel: string;
  isSubmitting: boolean;
  errorMessage?: string;
  onClose: () => void;
  onSubmit: (reason: string) => void;
}

export default function ReturnReasonModal({
  request,
  reviewerLabel,
  isSubmitting,
  errorMessage,
  onClose,
  onSubmit,
}: ReturnReasonModalProps) {
  const [reason, setReason] = useState("");
  const [validationError, setValidationError] = useState("");

  const trimmedReason = reason.trim();

  const submitReason = () => {
    if (trimmedReason.length === 0) {
      setValidationError("Return reason is required.");
      return;
    }

    setValidationError("");
    onSubmit(trimmedReason);
  };

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/50 p-4">
      <div className="w-full max-w-lg overflow-hidden rounded-lg bg-white shadow-xl">
        <div className="border-b border-[#d9e1e8] p-6">
          <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">{reviewerLabel} Return</p>
          <h2 className="mt-1 text-xl font-bold text-[#17243f]">Return this request?</h2>
          <p className="mt-2 text-sm text-[#5c6b7a]">
            {request.requestNumber} will go back to the requestor for correction. The reason will be shown in
            Request Details.
          </p>
        </div>

        <div className="space-y-4 p-6">
          <div className="rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] px-4 py-3">
            <p className="text-sm font-semibold text-[#17243f]">{request.purpose}</p>
            <p className="mt-1 text-xs font-medium uppercase tracking-wide text-[#5c6b7a]">
              {request.department} - {request.currentOwner.name}
            </p>
          </div>

          <div>
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="return-reason">
              Reason for return <span className="text-rose-400">*</span>
            </label>
            <textarea
              id="return-reason"
              value={reason}
              onChange={(event) => {
                setReason(event.target.value);
                if (validationError) {
                  setValidationError("");
                }
              }}
              rows={5}
              placeholder="Example: Please correct the invoice reference and replace the unreadable receipt."
              className="mt-2 w-full resize-none rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
            <div className="mt-2 flex items-center justify-between gap-3 text-xs">
              <p className="text-[#d30f42]">{validationError}</p>
              <p className="shrink-0 text-[#5c6b7a]">{trimmedReason.length} characters</p>
            </div>
          </div>
          {errorMessage && (
            <p className="rounded-lg border border-[#ffb3c6] bg-[#fff0f4] px-3 py-2 text-sm font-semibold text-[#d30f42]">
              {errorMessage}
            </p>
          )}
        </div>

        <div className="flex gap-3 border-t border-[#d9e1e8] p-6">
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9] disabled:cursor-not-allowed disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={submitReason}
            disabled={isSubmitting}
            className="flex-1 rounded-lg bg-[#ff1550] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#e51147] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isSubmitting ? "Returning..." : "Return Request"}
          </button>
        </div>
      </div>
    </div>
  );
}
