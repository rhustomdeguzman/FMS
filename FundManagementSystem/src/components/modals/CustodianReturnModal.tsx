import { useState } from "react";
import type { CashAdvanceRequest } from "../../types/CashAdvance";

interface Props {
  request: CashAdvanceRequest;
  isSubmitting: boolean;
  errorMessage: string;
  onClose: () => void;
  onSubmit: (amount: number) => void;
}

export default function CustodianReturnModal({ request, isSubmitting, errorMessage, onClose, onSubmit }: Props) {
  const [amount, setAmount] = useState("");
  const expected = request.returnAmount ?? 0;
  const entered = Number(amount);
  const valid = amount.trim() !== "" && Number.isFinite(entered) && entered > 0 && Math.abs(entered - expected) < 0.005;
  return (
    <div className="fixed inset-0 z-[65] flex items-center justify-center bg-black/50 p-4" role="dialog" aria-modal="true" aria-labelledby="custodian-return-title">
      <div className="w-full max-w-md space-y-4 rounded-lg bg-white p-6 shadow-xl" aria-busy={isSubmitting}>
        <h2 id="custodian-return-title" className="text-xl font-bold text-[#17243f]">Receive excess cash and approve</h2>
        <p className="text-sm text-[#5c6b7a]">{request.requestNumber} — collect the unspent balance before approving this liquidation.</p>
        <p className="font-semibold text-[#17243f]">Expected cash return: PHP {expected.toLocaleString("en-PH", { minimumFractionDigits: 2 })}</p>
        <label className="block text-sm font-semibold text-[#17243f]" htmlFor="custodian-cash-received">Excess cash received</label>
        <input id="custodian-cash-received" type="number" min="0.01" step="0.01" required value={amount} disabled={isSubmitting}
          onChange={(event) => setAmount(event.target.value)} className="w-full rounded-lg border border-[#c8d4df] px-3 py-3" />
        {amount && !valid && <p className="text-sm text-[#d30f42]">Enter the full expected cash return to close the liquidation.</p>}
        {errorMessage && <p role="alert" className="text-sm text-[#d30f42]">{errorMessage}</p>}
        <div className="flex gap-3">
          <button type="button" disabled={isSubmitting} onClick={onClose} className="flex-1 rounded-lg border px-4 py-3">Cancel</button>
          <button type="button" disabled={!valid || isSubmitting} onClick={() => { if (valid && !isSubmitting) onSubmit(entered); }}
            className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 font-semibold text-white disabled:opacity-50">
            {isSubmitting ? "Approving..." : "Receive and Approve"}
          </button>
        </div>
      </div>
    </div>
  );
}
