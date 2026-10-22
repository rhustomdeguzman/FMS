import { useMemo, useState } from "react";
import { roleLabels } from "../../auth/roleConfig";
import { getPendingLiquidationAmount } from "../../liquidationAmounts";
import type { AppUser, CashAdvanceRequest, CashAdvanceStatus, DashboardMetrics } from "../../types/CashAdvance";
import Icon from "../Icon";
import RequestTable from "../requests/RequestTable";
import DashboardCharts from "./DashboardCharts";
import StatCard from "./StatCard";

interface DashboardOverviewProps {
  user: AppUser;
  metrics: DashboardMetrics;
  requests: CashAdvanceRequest[];
  approvalRequests?: CashAdvanceRequest[];
  onOpenHistory: (request: CashAdvanceRequest) => void;
  onOpenDetails: (request: CashAdvanceRequest) => void;
  onOpenCashier: () => void;
  onPrint?: (request: CashAdvanceRequest) => void;
}

const pageSize = 10;
type DashboardRequestFilter = "all" | "pending_liquidation" | "approval_queue" | "pending_amount";

const approvalQueueStatuses = new Set<CashAdvanceStatus>([
  "pending_department_approval",
  "pending_rfp_department_approval",
  "pending_rfp_attachment",
  "pending_accounting_review",
  "transferred",
  "pending_cashier_closure",
]);

const pendingAmountExcludedStatuses = new Set<CashAdvanceStatus>(["rfp_created", "rejected", "fully_liquidated"]);

const filterLabels: Record<DashboardRequestFilter, string> = {
  all: "All requests",
  pending_liquidation: "Pending Liquidation",
  approval_queue: "Approval Queue",
  pending_amount: "Pending Amount",
};

const matchesDashboardFilter = (request: CashAdvanceRequest, filter: DashboardRequestFilter) => {
  if (filter === "pending_liquidation") {
    return request.status === "pending_liquidation";
  }

  if (filter === "approval_queue") {
    return approvalQueueStatuses.has(request.status);
  }

  if (filter === "pending_amount") {
    return !pendingAmountExcludedStatuses.has(request.status);
  }

  return true;
};

const toSearchText = (request: CashAdvanceRequest) =>
  [
    request.requestNumber,
    request.purpose,
    request.status.replaceAll("_", " "),
    request.currentOwner.name,
    request.originalOwner.name,
    request.department,
    request.sourceSystem,
  ]
    .join(" ")
    .toLowerCase();

const iconPaths = {
  clock: "M12 8v4l3 3m6-3a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
  list: "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01",
  wallet: "M3 7h18v10H3V7Zm3 3h4",
  check: "M9 12l2 2 4-5m6 3a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
};

export default function DashboardOverview({
  user,
  metrics,
  requests,
  approvalRequests,
  onOpenHistory,
  onOpenDetails,
  onOpenCashier,
  onPrint,
}: DashboardOverviewProps) {
  const [searchTerm, setSearchTerm] = useState("");
  const [currentPage, setCurrentPage] = useState(1);
  const [requestFilter, setRequestFilter] = useState<DashboardRequestFilter>("all");
  const normalizedSearchTerm = searchTerm.trim().toLowerCase();
  const pendingLiquidationCount = useMemo(
    () => requests.filter((request) => matchesDashboardFilter(request, "pending_liquidation")).length,
    [requests],
  );
  const approvalQueueCount = useMemo(
    () => approvalRequests?.length ?? requests.filter((request) => matchesDashboardFilter(request, "approval_queue")).length,
    [approvalRequests, requests],
  );
  const pendingAmountTotal = useMemo(
    () =>
      requests
        .filter((request) => matchesDashboardFilter(request, "pending_amount"))
        .reduce((sum, request) => sum + getPendingLiquidationAmount(request), 0),
    [requests],
  );
  const attentionRequests = useMemo(
    () =>
      [...(requestFilter === "approval_queue" && approvalRequests !== undefined ? approvalRequests : requests)]
        .filter((request) => requestFilter === "approval_queue" && approvalRequests !== undefined || matchesDashboardFilter(request, requestFilter))
        .sort((first, second) => second.createdAt.getTime() - first.createdAt.getTime())
        .filter((request) => normalizedSearchTerm.length === 0 || toSearchText(request).includes(normalizedSearchTerm)),
    [approvalRequests, normalizedSearchTerm, requestFilter, requests],
  );
  const totalPages = Math.max(1, Math.ceil(attentionRequests.length / pageSize));
  const safeCurrentPage = Math.min(currentPage, totalPages);
  const pageStartIndex = (safeCurrentPage - 1) * pageSize;
  const paginatedRequests = attentionRequests.slice(pageStartIndex, pageStartIndex + pageSize);
  const selectRequestFilter = (nextFilter: DashboardRequestFilter) => {
    setRequestFilter(nextFilter);
    setCurrentPage(1);
  };

  return (
    <div className="space-y-8">
      <section>
        <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">
          {roleLabels[user.role]} dashboard
        </p>
        <h2 className="mt-1 text-2xl font-bold text-[#17243f]">Welcome, {user.name}</h2>
        <p className="mt-2 max-w-3xl text-sm text-[#5c6b7a]">
          Don't forget to complete your pending actions to ensure timely processing.
        </p>
      </section>

      <DashboardCharts
        requests={requests}
        pendingLiquidationCount={pendingLiquidationCount}
        approvalQueueCount={approvalQueueCount}
      />

      <section className="grid gap-5 md:grid-cols-2 xl:grid-cols-4">
        <StatCard
          title="Pending Liquidation"
          value={pendingLiquidationCount}
          tone="blue"
          icon={<Icon path={iconPaths.clock} />}
          isActive={requestFilter === "pending_liquidation"}
          onClick={() => selectRequestFilter("pending_liquidation")}
        />
        <StatCard
          title="Approval Queue"
          value={approvalQueueCount}          
          tone="amber"
          icon={<Icon path={iconPaths.check} />}
          isActive={requestFilter === "approval_queue"}
          onClick={() => selectRequestFilter("approval_queue")}
        />
        <StatCard
          title="Pending Amount"
          value={`PHP ${pendingAmountTotal.toLocaleString()}`}
          tone="emerald"
          icon={<Icon path={iconPaths.wallet} />}
          isActive={requestFilter === "pending_amount"}
          onClick={() => selectRequestFilter("pending_amount")}
        />
        <StatCard
          title="Total Requests"
          value={requests.length}
          tone="rose"
          icon={<Icon path={iconPaths.list} />}
          isActive={requestFilter === "all"}
          onClick={() => selectRequestFilter("all")}
        />
      </section>

      <section>
        <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <h3 className="text-lg font-bold text-[#17243f]">All Requests</h3>
            <p className="text-sm text-[#5c6b7a]">
              {user.role === "accounting"
                ? "All requests sorted by latest created date."
                : "Your requests sorted by latest created date."}
              {requestFilter !== "all" ? ` Showing ${filterLabels[requestFilter]}.` : ""}
            </p>
          </div>
          <div className="flex w-full flex-col gap-3 sm:flex-row lg:w-auto">
            <label className="sr-only" htmlFor="request-search">Search requests</label>
            <input
              id="request-search"
              type="search"
              value={searchTerm}
              onChange={(event) => {
                setSearchTerm(event.target.value);
                setCurrentPage(1);
              }}
              placeholder="Search requests"
              className="min-h-10 w-full rounded-lg border border-[#c8d4df] px-3 text-sm text-[#17243f] outline-none focus:border-[#0bb7a5] sm:w-72"
            />
            {metrics.pendingCashierReturn > 0 && user.role === "cashier" && (
              <button
                type="button"
                onClick={onOpenCashier}
                className="rounded-lg bg-[#ff1550] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#e51147]"
              >
                Open Cashier Queue
              </button>
            )}
          </div>
        </div>

        <RequestTable
          requests={paginatedRequests}
          emptyMessage={
            normalizedSearchTerm || requestFilter !== "all"
              ? "No requests match the selected filter."
              : "No requests found."
          }
          onHistory={onOpenHistory}
          onOpenDetails={onOpenDetails}
          onPrint={onPrint}
          showOwnerColumn={user.role === "accounting"}
        />

        {attentionRequests.length > pageSize && (
          <div className="mt-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-sm font-semibold text-[#5c6b7a]">
              Showing {pageStartIndex + 1}-{Math.min(pageStartIndex + pageSize, attentionRequests.length)} of{" "}
              {attentionRequests.length}
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
    </div>
  );
}
