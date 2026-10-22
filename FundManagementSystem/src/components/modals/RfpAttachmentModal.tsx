import { useState } from "react";
import type { CashAdvanceRequest } from "../../types/CashAdvance";

interface RfpAttachmentModalProps {
  request: CashAdvanceRequest;
  onClose: () => void;
  onSubmit: (requestId: string, notes: string, attachments: File[]) => void;
}

export default function RfpAttachmentModal({ request, onClose, onSubmit }: RfpAttachmentModalProps) {
  const [notes, setNotes] = useState("");
  const [attachments, setAttachments] = useState<File[]>([]);
  const canSubmit = attachments.length > 0;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="w-full max-w-xl rounded-lg bg-white shadow-xl">
        <div className="border-b border-[#d9e1e8] p-6">
          <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">RFP Attachment</p>
          <h2 className="mt-1 text-xl font-bold text-[#17243f]">{request.requestNumber}</h2>
          <p className="mt-1 text-sm text-[#5c6b7a]">{request.purpose}</p>
        </div>

        <div className="space-y-5 p-6">
          <div className="grid gap-3 rounded-lg bg-[#f3f6f9] p-4 text-sm sm:grid-cols-2">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Requested Amount</p>
              <p className="mt-1 font-bold text-[#17243f]">PHP {request.amount.toLocaleString()}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Excess Spend</p>
              <p className="mt-1 font-bold text-[#d30f42]">PHP {(request.excessAmount ?? 0).toLocaleString()}</p>
            </div>
          </div>

          <div>
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="rfp-attachments">
              RFP Attachment
            </label>
            <input
              id="rfp-attachments"
              type="file"
              multiple
              onChange={(event) => event.target.files && setAttachments(Array.from(event.target.files))}
              className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm"
            />
            {attachments.length > 0 && (
              <div className="mt-2 text-xs text-[#5c6b7a]">
                {attachments.map((file) => (
                  <p key={file.name}>{file.name}</p>
                ))}
              </div>
            )}
          </div>

          <div>
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="rfp-notes">
              Notes
            </label>
            <textarea
              id="rfp-notes"
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
            onClick={onClose}
            className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => onSubmit(request.id, notes, attachments)}
            disabled={!canSubmit}
            className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
          >
            Submit to Accounting
          </button>
        </div>
      </div>
    </div>
  );
}
