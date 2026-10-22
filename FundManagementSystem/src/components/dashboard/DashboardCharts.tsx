import type { CashAdvanceRequest } from "../../types/CashAdvance";
import { getTransferAdjustedRequestAmount } from "../../liquidationAmounts";

interface DashboardChartsProps {
  requests: CashAdvanceRequest[];
  pendingLiquidationCount: number;
  approvalQueueCount: number;
  pendingLiquidationLabel?: string;
  approvalQueueLabel?: string;
}

const monthLabels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const currencyFormatter = new Intl.NumberFormat("en-PH", {
  maximumFractionDigits: 0,
});

const compactCurrencyFormatter = new Intl.NumberFormat("en-PH", {
  notation: "compact",
  maximumFractionDigits: 1,
});

const toCurrency = (amount: number) => `PHP ${currencyFormatter.format(amount)}`;
const toCompactCurrency = (amount: number) => `PHP ${compactCurrencyFormatter.format(amount)}`;
const toPaddedCount = (count: number) => (count < 10 ? `0${count}` : String(count));

const buildMonthlyFundData = (requests: CashAdvanceRequest[]) => {
  const currentYear = new Date().getFullYear();
  const totals = monthLabels.map((month) => ({ month, amount: 0 }));

  requests.forEach((request) => {
    if (request.createdAt.getFullYear() !== currentYear) {
      return;
    }

    totals[request.createdAt.getMonth()].amount += getTransferAdjustedRequestAmount(request);
  });

  return totals;
};

export default function DashboardCharts({
  requests,
  pendingLiquidationCount,
  approvalQueueCount,
  pendingLiquidationLabel = "Pending Liquidation",
  approvalQueueLabel = "Approval Queue",
}: DashboardChartsProps) {
  const monthlyFundData = buildMonthlyFundData(requests);
  const maxAmount = Math.max(...monthlyFundData.map((item) => item.amount), 0);
  const chartMax = maxAmount > 0 ? maxAmount : 1;

  return (
    <section className="grid gap-5 lg:grid-cols-[minmax(320px,0.75fr)_minmax(0,1.45fr)]">
      <div className="rounded-lg bg-teal-600 p-6 text-white shadow-sm">
        <h3 className="text-md mb-2 font-normal">Request Summary</h3>
        <hr className="mb-6 border-t border-white/30" />
        <div className="grid grid-cols-2 gap-4">
          <div className="flex flex-col items-center gap-4">
            <div className="flex h-32 w-32 items-center justify-center rounded-full border-[14px] border-[#4ade80] text-4xl font-bold">
              {toPaddedCount(pendingLiquidationCount)}
            </div>
            <div className="flex items-center gap-2 text-center text-sm font-semibold">
              <span className="h-3 w-3 shrink-0 rounded-full bg-[#4ade80]" />
              <span>{pendingLiquidationLabel}</span>
            </div>
          </div>
          <div className="flex flex-col items-center gap-4">
            <div className="flex h-32 w-32 items-center justify-center rounded-full border-[14px] border-[#f7ce3b] text-4xl font-bold">
              {toPaddedCount(approvalQueueCount)}
            </div>
            <div className="flex items-center gap-2 text-center text-sm font-semibold">
              <span className="h-3 w-3 shrink-0 rounded-full bg-[#f7ce3b]" />
              <span>{approvalQueueLabel}</span>
            </div>
          </div>
        </div>
      </div>

      <div className="rounded-lg border border-[#d9e1e8] bg-white p-4 shadow-sm">
        <div className="mb-3 flex items-center justify-between gap-3">
          <h3 className="text-lg font-semibold text-[#17243f]">Monthly Fund Request Summary</h3>
          <span className="text-xs font-semibold text-[#5c6b7a]">{new Date().getFullYear()}</span>
        </div>
        <div className="relative h-64 overflow-hidden">
          <div className="absolute left-0 top-3 text-[11px] font-semibold text-[#7a8896]">
            {toCompactCurrency(chartMax)}
          </div>
          <div className="absolute left-0 top-[calc(50%-10px)] text-[11px] font-semibold text-[#7a8896]">
            {toCompactCurrency(chartMax / 2)}
          </div>
          <div className="absolute bottom-8 left-12 right-0 top-4 border-b border-l border-[#d9e1e8]">
            <div className="absolute left-0 right-0 top-0 border-t border-dashed border-[#e5ebf0]" />
            <div className="absolute left-0 right-0 top-1/2 border-t border-dashed border-[#e5ebf0]" />
          </div>
          <div className="absolute bottom-9 left-12 right-0 top-5 grid grid-cols-12 items-end gap-2">
            {monthlyFundData.map((item) => {
              const heightPercent = item.amount === 0 ? 0 : Math.max(6, (item.amount / chartMax) * 100);

              return (
                <div key={item.month} className="flex h-full min-w-0 items-end">
                  <div
                    className="w-full rounded-t-md bg-[#f7ce3b] shadow-sm transition hover:bg-[#eebf22]"
                    style={{ height: `${heightPercent}%` }}
                    title={`${item.month}: ${toCurrency(item.amount)}`}
                    aria-label={`${item.month}: ${toCurrency(item.amount)}`}
                  />
                </div>
              );
            })}
          </div>
          <div className="absolute bottom-0 left-12 right-0 grid grid-cols-12 gap-2">
            {monthlyFundData.map((item) => (
              <span key={item.month} className="truncate text-center text-[11px] font-semibold text-[#5c6b7a]">
                {item.month}
              </span>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
