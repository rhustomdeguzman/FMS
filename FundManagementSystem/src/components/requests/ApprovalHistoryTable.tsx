import { useMemo, useState } from "react";
import type {
  AccountingReportPeriod,
  AppUser,
  CashAdvanceRequest,
  TransactionAction,
  TransactionHistory,
  UserRole,
} from "../../types/CashAdvance";
import Avatar from "../Avatar";
import Icon from "../Icon";
import StatusBadge from "../StatusBadge";

interface ApprovalHistoryTableProps {
  user: AppUser;
  requests: CashAdvanceRequest[];
  onHistory: (request: CashAdvanceRequest) => void;
  onOpenDetails: (request: CashAdvanceRequest) => void;
  onGenerateAccountingReport?: (period: AccountingReportPeriod) => Promise<void>;
}

interface ApprovalHistoryRow {
  request: CashAdvanceRequest;
  event: TransactionHistory;
}

const historyActionsByRole: Partial<Record<UserRole, TransactionAction[]>> = {
  department_head: ["approved_by_department_head", "rfp_created", "rfp_waived", "returned"],
  accounting: ["approved_by_accounting", "returned"],
  cashier: ["acknowledged", "fully_liquidated"],
  custodian: [
    "petty_cash_released",
    "approved_by_custodian",
    "petty_cash_replenishment_created",
    "petty_cash_replenished",
    "rejected",
    "returned",
  ],
};

const actionLabels: Partial<Record<TransactionAction, string>> = {
  approved_by_department_head: "Department Approved",
  rfp_created: "RFP Created",
  rfp_waived: "RFP Waived",
  approved_by_accounting: "Accounting Approved",
  acknowledged: "Receipt Processed",
  fully_liquidated: "Liquidation Closed",
  returned: "Returned",
  petty_cash_released: "Petty Cash Released",
  approved_by_custodian: "Custodian Approved",
  petty_cash_replenishment_created: "Replenishment RFP Created",
  petty_cash_replenished: "Petty Cash Replenished",
  rejected: "Rejected",
};

const iconPaths = {
  history: "M12 8v4l3 3m6-3a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
  details: "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6Zm0 0v6h6M8 13h8M8 17h5",
  report: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3",
};

const pageSize = 10;

const currentMonthValue = () => {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}`;
};

const formatDateTime = (date: Date) =>
  date.toLocaleString("en-PH", {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "numeric",
    minute: "2-digit",
  });

const isFallbackActorMatch = (request: CashAdvanceRequest, user: AppUser, action: TransactionAction) => {
  if (user.role === "department_head") {
    return request.department === user.department && (historyActionsByRole.department_head?.includes(action) ?? false);
  }

  return historyActionsByRole[user.role]?.includes(action) ?? false;
};

const getUserHistoryEvents = (request: CashAdvanceRequest, user: AppUser) => {
  const roleActions = historyActionsByRole[user.role] ?? [];

  return request.history.filter((event) => {
    if (!roleActions.includes(event.action)) {
      return false;
    }

    return event.fromEmployee?.id === user.id || (!event.fromEmployee && isFallbackActorMatch(request, user, event.action));
  });
};

const getApprovalHistoryRows = (requests: CashAdvanceRequest[], user: AppUser): ApprovalHistoryRow[] =>
  requests
    .map((request): ApprovalHistoryRow | undefined => {
      const latestEvent = getUserHistoryEvents(request, user).sort(
        (left, right) => right.timestamp.getTime() - left.timestamp.getTime(),
      )[0];

      return latestEvent ? { request, event: latestEvent } : undefined;
    })
    .filter((row): row is ApprovalHistoryRow => row !== undefined)
    .sort((left, right) => right.event.timestamp.getTime() - left.event.timestamp.getTime());

const getActionLabel = (action: TransactionAction) => actionLabels[action] ?? action.replaceAll("_", " ");

const toSearchText = ({ request, event }: ApprovalHistoryRow) =>
  [
    request.requestNumber,
    request.purpose,
    request.status.replaceAll("_", " "),
    request.currentOwner.name,
    request.originalOwner.name,
    request.department,
    request.sourceSystem,
    getActionLabel(event.action),
    event.notes ?? "",
    event.amount == null ? "" : String(event.amount),
    formatDateTime(event.timestamp),
  ]
    .join(" ")
    .toLowerCase();

export default function ApprovalHistoryTable({
  user,
  requests,
  onHistory,
  onOpenDetails,
  onGenerateAccountingReport,
}: ApprovalHistoryTableProps) {
  const [searchTerm, setSearchTerm] = useState("");
  const [currentPage, setCurrentPage] = useState(1);
  const [reportMode, setReportMode] = useState<AccountingReportPeriod["mode"]>("all");
  const [reportMonth, setReportMonth] = useState(currentMonthValue);
  const [reportYear, setReportYear] = useState(String(new Date().getFullYear()));
  const [reportFrom, setReportFrom] = useState("");
  const [reportTo, setReportTo] = useState("");
  const [reportError, setReportError] = useState("");
  const [isGeneratingReport, setIsGeneratingReport] = useState(false);
  const normalizedSearchTerm = searchTerm.trim().toLowerCase();
  const rows = useMemo(() => getApprovalHistoryRows(requests, user), [requests, user]);
  const filteredRows = useMemo(
    () =>
      rows.filter((row) => normalizedSearchTerm.length === 0 || toSearchText(row).includes(normalizedSearchTerm)),
    [normalizedSearchTerm, rows],
  );
  const totalPages = Math.max(1, Math.ceil(filteredRows.length / pageSize));
  const safeCurrentPage = Math.min(currentPage, totalPages);
  const pageStartIndex = (safeCurrentPage - 1) * pageSize;
  const paginatedRows = filteredRows.slice(pageStartIndex, pageStartIndex + pageSize);
  const canGenerateAccountingReport = user.role === "accounting" && onGenerateAccountingReport !== undefined;

  const buildReportPeriod = (): AccountingReportPeriod | undefined => {
    if (reportMode === "all") {
      return { mode: "all" };
    }

    if (reportMode === "month") {
      if (!reportMonth) {
        setReportError("Select a month.");
        return undefined;
      }

      return { mode: "month", month: reportMonth };
    }

    if (reportMode === "year") {
      if (!/^\d{4}$/.test(reportYear)) {
        setReportError("Enter a valid year.");
        return undefined;
      }

      return { mode: "year", year: reportYear };
    }

    if (!reportFrom || !reportTo) {
      setReportError("Select a from and to date.");
      return undefined;
    }

    if (reportFrom > reportTo) {
      setReportError("From date cannot be later than to date.");
      return undefined;
    }

    return { mode: "range", from: reportFrom, to: reportTo };
  };

  const handleGenerateReport = async () => {
    if (!onGenerateAccountingReport) {
      return;
    }

    setReportError("");
    const period = buildReportPeriod();
    if (!period) {
      return;
    }

    setIsGeneratingReport(true);
    try {
      await onGenerateAccountingReport(period);
    } catch (error) {
      setReportError(error instanceof Error ? error.message : "Unable to generate report.");
    } finally {
      setIsGeneratingReport(false);
    }
  };

  return (
    <section>
      <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <h2 className="text-xl font-bold text-[#17243f]">Approval History</h2>
          <p className="mt-1 text-sm text-[#5c6b7a]">Requests you approved, returned, or processed.</p>
        </div>
        <div className="flex w-full flex-col gap-3 sm:flex-row sm:items-center lg:w-auto">
          <label className="sr-only" htmlFor="approval-history-search">
            Search approval history
          </label>
          <input
            id="approval-history-search"
            type="search"
            value={searchTerm}
            onChange={(event) => {
              setSearchTerm(event.target.value);
              setCurrentPage(1);
            }}
            placeholder="Search approval history"
            className="min-h-10 w-full rounded-lg border border-[#c8d4df] px-3 text-sm text-[#17243f] outline-none focus:border-[#0bb7a5] sm:w-72"
          />
          <p className="text-sm font-semibold text-[#5c6b7a]">
            {filteredRows.length} processed
          </p>
        </div>
      </div>

      {canGenerateAccountingReport && (
        <div className="mb-6 rounded-lg border border-[#d9e1e8] bg-white p-4 shadow-sm">
          <div className="flex flex-col gap-3 lg:flex-row lg:items-end">
            <label className="flex flex-col gap-1 text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">
              Period
              <select
                value={reportMode}
                onChange={(event) => {
                  setReportMode(event.target.value as AccountingReportPeriod["mode"]);
                  setReportError("");
                }}
                className="min-h-10 rounded-lg border border-[#c8d4df] bg-white px-3 text-sm font-semibold normal-case tracking-normal text-[#17243f] outline-none focus:border-[#0bb7a5]"
              >
                <option value="all">All</option>
                <option value="month">Month</option>
                <option value="year">Year</option>
                <option value="range">From / To</option>
              </select>
            </label>

            {reportMode === "month" && (
              <label className="flex flex-col gap-1 text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">
                Month
                <input
                  type="month"
                  value={reportMonth}
                  onChange={(event) => {
                    setReportMonth(event.target.value);
                    setReportError("");
                  }}
                  className="min-h-10 rounded-lg border border-[#c8d4df] px-3 text-sm font-semibold normal-case tracking-normal text-[#17243f] outline-none focus:border-[#0bb7a5]"
                />
              </label>
            )}

            {reportMode === "year" && (
              <label className="flex flex-col gap-1 text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">
                Year
                <input
                  type="number"
                  min="1900"
                  max="9999"
                  value={reportYear}
                  onChange={(event) => {
                    setReportYear(event.target.value);
                    setReportError("");
                  }}
                  className="min-h-10 w-32 rounded-lg border border-[#c8d4df] px-3 text-sm font-semibold normal-case tracking-normal text-[#17243f] outline-none focus:border-[#0bb7a5]"
                />
              </label>
            )}

            {reportMode === "range" && (
              <>
                <label className="flex flex-col gap-1 text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">
                  From
                  <input
                    type="date"
                    value={reportFrom}
                    onChange={(event) => {
                      setReportFrom(event.target.value);
                      setReportError("");
                    }}
                    className="min-h-10 rounded-lg border border-[#c8d4df] px-3 text-sm font-semibold normal-case tracking-normal text-[#17243f] outline-none focus:border-[#0bb7a5]"
                  />
                </label>
                <label className="flex flex-col gap-1 text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">
                  To
                  <input
                    type="date"
                    value={reportTo}
                    onChange={(event) => {
                      setReportTo(event.target.value);
                      setReportError("");
                    }}
                    className="min-h-10 rounded-lg border border-[#c8d4df] px-3 text-sm font-semibold normal-case tracking-normal text-[#17243f] outline-none focus:border-[#0bb7a5]"
                  />
                </label>
              </>
            )}

            <button
              type="button"
              onClick={handleGenerateReport}
              disabled={isGeneratingReport}
              className="inline-flex min-h-10 items-center justify-center gap-2 rounded-lg bg-[#17243f] px-4 text-sm font-semibold text-white shadow-sm hover:bg-[#223459] disabled:cursor-not-allowed disabled:opacity-60"
            >
              <Icon path={iconPaths.report} className="h-4 w-4" />
              {isGeneratingReport ? "Generating..." : "Generate Report"}
            </button>
          </div>
          {reportError && <p className="mt-3 text-sm font-semibold text-[#b42318]">{reportError}</p>}
        </div>
      )}

      <div className="overflow-hidden rounded-lg border border-[#d9e1e8] bg-white shadow-sm">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1040px]">
            <thead className="border-b border-[#17243f] bg-white">
              <tr>
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">
                  Request
                </th>
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">
                  Owner
                </th>
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">
                  Amount
                </th>
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">
                  Status
                </th>
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">
                  Processed
                </th>
                <th className="px-5 py-3 text-left text-xs font-semibold uppercase tracking-wide text-[#17243f]">
                  Action
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-white">
              {paginatedRows.map(({ request, event }) => (
                <tr
                  key={`${request.id}-${event.id}`}
                  onClick={() => onOpenDetails(request)}
                  className="cursor-pointer odd:bg-[#eef2f7] even:bg-white hover:bg-[#e2faf6]"
                >
                  <td className="px-5 py-4">
                    <p className="font-semibold text-[#17243f]">{request.requestNumber}</p>
                    <p className="max-w-xs truncate text-sm text-[#5c6b7a]">{request.purpose}</p>
                  </td>
                  <td className="px-5 py-4">
                    <div className="flex items-center gap-3">
                      <Avatar employee={request.currentOwner} size="sm" />
                      <div>
                        <p className="text-sm font-semibold text-[#17243f]">{request.currentOwner.name}</p>
                        <p className="text-xs text-[#5c6b7a]">{request.department}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-5 py-4">
                    <p className="text-sm font-semibold text-[#17243f]">PHP {request.amount.toLocaleString()}</p>
                    {event.amount != null && (
                      <p className="text-xs text-[#08786f]">Action: PHP {event.amount.toLocaleString()}</p>
                    )}
                  </td>
                  <td className="px-5 py-4">
                    <StatusBadge status={request.status} request={request} />
                  </td>
                  <td className="px-5 py-4 text-sm font-semibold text-[#17243f]">
                    {formatDateTime(event.timestamp)}
                  </td>
                  <td className="py-4 pr-5 text-sm text-[#5c6b7a]">
                    <div className="flex flex-wrap items-center gap-2">
                      <button
                        type="button"
                        onClick={(clickEvent) => {
                          clickEvent.stopPropagation();
                          onOpenDetails(request);
                        }}
                        className="inline-flex items-center gap-1.5 rounded-lg border border-[#d9e1e8] bg-white px-3 py-2 text-xs font-semibold text-[#17243f] shadow-sm hover:bg-[#eef2f7]"
                      >
                        <Icon path={iconPaths.details} className="h-4 w-4" />
                        Details
                      </button>
                      <button
                        type="button"
                        onClick={(clickEvent) => {
                          clickEvent.stopPropagation();
                          onHistory(request);
                        }}
                        className="inline-flex items-center gap-1.5 rounded-lg border border-[#d9e1e8] bg-white px-3 py-2 text-xs font-semibold text-[#17243f] shadow-sm hover:bg-[#eef2f7]"
                      >
                        <Icon path={iconPaths.history} className="h-4 w-4" />
                        History
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {filteredRows.length === 0 && (
          <p className="px-5 py-12 text-center text-sm text-[#5c6b7a]">
            {rows.length === 0 ? "No approved or processed requests yet." : "No approval history matches your search."}
          </p>
        )}
      </div>

      {filteredRows.length > pageSize && (
        <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-sm font-semibold text-[#5c6b7a]">
            Showing {pageStartIndex + 1}-{Math.min(pageStartIndex + pageSize, filteredRows.length)} of{" "}
            {filteredRows.length}
          </p>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setCurrentPage((page) => Math.max(1, page - 1))}
              disabled={safeCurrentPage === 1}
              className="rounded-lg border border-[#d9e1e8] px-3 py-2 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9] disabled:cursor-not-allowed disabled:opacity-50"
            >
              Previous
            </button>
            <span className="min-w-20 rounded-lg bg-[#f3f6f9] px-3 py-2 text-center text-sm font-semibold text-[#17243f]">
              {safeCurrentPage} / {totalPages}
            </span>
            <button
              type="button"
              onClick={() => setCurrentPage((page) => Math.min(totalPages, page + 1))}
              disabled={safeCurrentPage === totalPages}
              className="rounded-lg border border-[#d9e1e8] px-3 py-2 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9] disabled:cursor-not-allowed disabled:opacity-50"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
