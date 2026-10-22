import { useState } from "react";
import type { AppUser, CashAdvanceRequest } from "../../types/CashAdvance";

interface TransferModalProps {
  request: CashAdvanceRequest;
  currentUser: AppUser;
  employees: AppUser[];
  isSubmitting?: boolean;
  onClose: () => void;
  onTransfer: (
    requestId: string,
    toEmployeeId: string,
    amount: number,
    notes: string,
    transferWholeRequest: boolean,
  ) => void;
}

const transferModes = [
  {
    id: "full",
    label: "Full Transfer",
    description: "Transfer the full requested amount.",
  },
  {
    id: "partial",
    label: "Partial Transfer",
    description: "Transfer a Partial Amount to other Employee.",
  },
] as const;

export default function TransferModal({
  request,
  currentUser,
  employees,
  isSubmitting = false,
  onClose,
  onTransfer,
}: TransferModalProps) {
  const availableEmployees = employees.filter(
    (employee) =>
      employee.id !== currentUser.id &&
      employee.role === "department_head" &&
      employee.department.trim().toLocaleLowerCase() === request.department.trim().toLocaleLowerCase(),
  );
  const [toEmployeeId, setToEmployeeId] = useState(availableEmployees[0]?.id ?? "");
  const [amountInput, setAmountInput] = useState(String(Math.max(1, Math.floor(request.remainingAmount / 2))));
  const [transferType, setTransferType] = useState<"full" | "partial">("full");
  const [notes, setNotes] = useState("");

  const parsedAmount = amountInput.trim() === "" ? 0 : Number(amountInput);
  const amount = Number.isFinite(parsedAmount) ? parsedAmount : 0;
  const transferAmount = transferType === "full" ? request.remainingAmount : amount;
  const selectedEmployee = availableEmployees.find((employee) => employee.id === toEmployeeId);
  const isTransferAmountInvalid =
    transferAmount <= 0 ||
    transferAmount > request.remainingAmount;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="w-full max-w-lg rounded-lg bg-white shadow-xl">
        <div className="border-b border-[#d9e1e8] p-6">
          <h2 className="text-xl font-bold text-[#17243f]">Transfer Request</h2>
          <p className="mt-1 text-sm text-[#5c6b7a]">{request.requestNumber}</p>
        </div>

        <div className="space-y-5 p-6">
          <div>
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="toEmployee">
              Transfer To
            </label>
            <select
              id="toEmployee"
              disabled={isSubmitting}
              value={toEmployeeId}
              onChange={(event) => setToEmployeeId(event.target.value)}
              className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
            >
              {availableEmployees.length > 0 ? (
                availableEmployees.map((employee) => (
                  <option key={employee.id} value={employee.id}>
                    {employee.name} - {employee.department}
                  </option>
                ))
              ) : (
                <option value="">No department approver assigned to this request's department</option>
              )}
            </select>
          </div>

          <div>
            <p className="text-sm font-semibold text-[#17243f]">Transfer Type</p>
            <div className="mt-2 grid gap-3 sm:grid-cols-2">
              {transferModes.map((mode) => (
                <button
                  type="button"
                  key={mode.id}
                  disabled={isSubmitting}
                  onClick={() => setTransferType(mode.id)}
                  className={`min-h-[116px] rounded-lg border px-4 py-3 text-left text-sm ${
                    transferType === mode.id
                      ? "border-[#0bb7a5] bg-[#e2faf6] text-[#17243f]"
                      : "border-[#d9e1e8] text-[#5c6b7a] hover:bg-[#f3f6f9]"
                  }`}
                >
                  <span className="block font-bold text-[#17243f]">{mode.label}</span>
                  <span className="mt-2 block leading-5">{mode.description}</span>
                </button>
              ))}
            </div>
          </div>

          {transferType === "partial" && (
            <div>
              <label className="block text-sm font-semibold text-[#17243f]" htmlFor="transferAmount">
                Transfer Amount <span className="text-rose-400">*</span>
              </label>
              <input
                id="transferAmount"
                disabled={isSubmitting}
                type="number"
                min={1}
                max={request.remainingAmount}
                value={amountInput}
                onChange={(event) => setAmountInput(event.target.value)}
                className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
              />
            </div>
          )}

          <div>
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="transferNotes">
              Notes
            </label>
            <textarea
              id="transferNotes"
              disabled={isSubmitting}
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              rows={3}
              className="mt-2 w-full resize-none rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
          </div>

          <div className="rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] p-4 text-sm">
            <p className="font-semibold text-[#17243f]">
              PHP {transferAmount.toLocaleString()} will be sent for acknowledgement
              {selectedEmployee ? ` to ${selectedEmployee.name}` : ""}.
            </p>
            <p className="mt-1 text-[#5c6b7a]">The receiver must acknowledge it before the cash advance is moved.</p>
          </div>
        </div>

        <div className="flex gap-3 border-t border-[#d9e1e8] p-6">
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => {
              if (!isSubmitting) {
                onTransfer(request.id, toEmployeeId, transferAmount, notes, transferType === "full");
              }
            }}
            disabled={isSubmitting || !toEmployeeId || isTransferAmountInvalid}
            aria-busy={isSubmitting}
            className="flex flex-1 items-center justify-center gap-2 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isSubmitting && (
              <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white" aria-hidden="true" />
            )}
            <span role="status">{isSubmitting ? "Transferring..." : "Confirm Transfer"}</span>
          </button>
        </div>
      </div>
    </div>
  );
}
