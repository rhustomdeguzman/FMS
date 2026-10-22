import type { CashAdvanceRequest } from "../types/CashAdvance";
import { getPettyCashRequestTypeLabel } from "../pettyCash";
import StatusBadge from "./StatusBadge";

const initialRenderTime = Date.now();
const millisecondsPerDay = 1000 * 60 * 60 * 24;

interface RequestCardProps {
  request: CashAdvanceRequest;
  onOpenDetails: (request: CashAdvanceRequest) => void;
}

export default function RequestCard({
  request,
  onOpenDetails,
}: RequestCardProps) {
  const progress = request.amount === 0 ? 0 : ((request.amount - request.remainingAmount) / request.amount) * 100;
  const daysUntilDue = Math.ceil((request.dueDate.getTime() - initialRenderTime) / millisecondsPerDay);

  return (
    <button
      type="button"
      onClick={() => onOpenDetails(request)}
      className="block w-full rounded-lg border border-[#d9e1e8] bg-white p-4 text-left shadow-sm transition hover:border-[#0bb7a5] hover:bg-[#f8fafc]"
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="text-sm font-bold text-[#17243f]">{request.requestNumber}</p>
          <p className="mt-1 line-clamp-2 text-sm text-[#5c6b7a]">{request.purpose}</p>
        </div>
        <StatusBadge status={request.status} request={request} />
      </div>

      <div className="mt-4 space-y-2">
        <div className="flex justify-between gap-4 text-sm">
          <span className="text-[#5c6b7a]">Request Type</span>
          <span className="text-right font-semibold text-[#17243f]">{getPettyCashRequestTypeLabel(request.requestType)}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-[#5c6b7a]">Original Amount</span>
          <span className="font-semibold text-[#17243f]">PHP {request.amount.toLocaleString()}</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-[#5c6b7a]">Remaining</span>
          <span className="font-semibold text-[#08786f]">PHP {request.remainingAmount.toLocaleString()}</span>
        </div>
        {request.returnAmount != null && request.returnAmount > 0 && (
          <div className="flex justify-between text-sm">
            <span className="text-[#5c6b7a]">Cash Return</span>
            <span className="font-semibold text-[#d30f42]">PHP {request.returnAmount.toLocaleString()}</span>
          </div>
        )}
      </div>

      <div className="mt-4">
        <div className="mb-2 flex justify-between text-xs font-medium text-[#5c6b7a]">
          <span>Liquidation Progress</span>
          <span>{Math.max(0, Math.min(100, progress)).toFixed(0)}%</span>
        </div>
        <div className="h-2 overflow-hidden rounded-full bg-[#eef2f7]">
          <div className="h-full rounded-full bg-teal-400" style={{ width: `${Math.max(0, Math.min(100, progress))}%` }} />
        </div>
      </div>

      <div className="mt-4 flex items-center justify-between border-t border-[#eef2f7] pt-3">
        <p className="text-xs font-semibold text-[#5c6b7a]">
          Due {request.dueDate.toLocaleDateString("en-PH")}
        </p>
        <p className={`text-xs font-semibold ${daysUntilDue < 0 ? "text-[#ff1550]" : "text-[#5c6b7a]"}`}>
          {daysUntilDue < 0 ? `${Math.abs(daysUntilDue)} days overdue` : `${daysUntilDue} days left`}
        </p>
      </div>
    </button>
  );
}
