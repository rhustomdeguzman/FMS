import type { CashAdvanceRequest } from "../../types/CashAdvance";
import { isDepartmentApprovalPrintAvailable } from "../../requestPrint";
import { getTransferAdjustedRequestAmount, getTransferredOutAmount } from "../../liquidationAmounts";
import Avatar from "../Avatar";
import StatusBadge from "../StatusBadge";
import Icon from "../Icon";

interface RequestTableProps {
  requests: CashAdvanceRequest[];
  emptyMessage: string;
  onHistory: (request: CashAdvanceRequest) => void;
  onOpenDetails: (request: CashAdvanceRequest) => void;
  onPrint?: (request: CashAdvanceRequest) => void;
  showOwnerColumn?: boolean;
}

const iconPaths = {
  clock: "M12 8v4l3 3m6-3a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
  list: "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01",
  wallet: "M3 7h18v10H3V7Zm3 3h4",
  check: "M9 12l2 2 4-5m6 3a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
  history: "M12 8v4l3 3m6-3a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
  print: "M6 9V3h12v6M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2M6 14h12v7H6v-7Z",
};

export default function RequestTable({
  requests,
  emptyMessage,
  onHistory,
  onOpenDetails,
  onPrint,
  showOwnerColumn = true,
}: RequestTableProps) {
  return (
    <div className="overflow-hidden rounded-lg border border-[#d9e1e8] bg-white shadow-sm">
      <div className="overflow-x-auto">
        <table className={`w-full ${showOwnerColumn ? "min-w-[900px]" : "min-w-[760px]"}`}>
          <thead className="border-b border-[#17243f] bg-white">
            <tr>
              <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">Request</th>
              {showOwnerColumn && (
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">Owner</th>
              )}
              <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">Amount</th>
              <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">Status</th>
              <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">Source</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white">
            {requests.map((request) => {
              const canPrintRequest = isDepartmentApprovalPrintAvailable(request);
              const displayAmount = getTransferAdjustedRequestAmount(request);
              const transferredAmount = getTransferredOutAmount(request);

              return (
              <tr
                key={request.id}
                onClick={() => onOpenDetails(request)}
                className="cursor-pointer odd:bg-[#eef2f7] even:bg-white hover:bg-[#e2faf6]"
              >
                <td className="px-5 py-4">
                  <p className="font-semibold text-[#17243f]">{request.requestNumber}</p>
                  <p className="max-w-sm truncate text-sm text-[#5c6b7a]">{request.purpose}</p>
                </td>
                {showOwnerColumn && (
                  <td className="px-5 py-4">
                    <div className="flex items-center gap-3">
                      <Avatar employee={request.currentOwner} size="sm" />
                      <div>
                        <p className="text-sm font-semibold text-[#17243f]">{request.currentOwner.name}</p>
                        <p className="text-xs text-[#5c6b7a]">{request.department}</p>
                      </div>
                    </div>
                  </td>
                )}
                <td className="px-5 py-4">
                  <p className="text-sm font-semibold text-[#17243f]">PHP {displayAmount.toLocaleString()}</p>
                  {transferredAmount > 0 && (
                    <p className="text-xs text-[#08786f]">PHP {transferredAmount.toLocaleString()} transferred</p>
                  )}
                </td>
                <td className="px-5 py-4">
                    <StatusBadge status={request.status} request={request} />
                </td>
                <td className="py-4 text-sm text-[#5c6b7a]">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="text-sm font-semibold text-[#17243f]">{request.sourceSystem}</p>
                    <button
                        type="button"
                        onClick={(event) => {
                          event.stopPropagation();
                          onHistory(request);
                        }}
                        className="inline-flex items-center gap-1.5 rounded-lg border border-[#d9e1e8] bg-white px-3 py-2 text-xs font-semibold text-[#17243f] shadow-sm hover:bg-[#eef2f7]"
                      >
                        <Icon path={iconPaths.history} className="h-4 w-4" />
                        History
                    </button>
                    {onPrint && (
                      <button
                        type="button"
                        disabled={!canPrintRequest}
                        onClick={(event) => {
                          event.stopPropagation();
                          if (!canPrintRequest) {
                            return;
                          }
                          onPrint(request);
                        }}
                        title={
                          canPrintRequest
                            ? "Print department-approved request"
                            : "Available after Department approval is approved"
                        }
                        className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-2 text-xs font-semibold shadow-sm ${
                          canPrintRequest
                            ? "bg-[#4e6493] text-white hover:bg-[#24365c]"
                            : "cursor-not-allowed bg-[#d9e1e8] text-[#7a8896] shadow-none"
                        }`}
                      >
                        <Icon path={iconPaths.print} className="h-4 w-4" />
                        Print
                      </button>
                    )}
                  </div>
                </td>
              </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {requests.length === 0 && <p className="px-5 py-12 text-center text-sm text-[#5c6b7a]">{emptyMessage}</p>}
    </div>
  );
}
