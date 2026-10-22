import type { CashAdvanceRequest, CashAdvanceStatus } from "../types/CashAdvance";

const statusMap: Record<CashAdvanceStatus, { className: string; label: string }> = {
  pending_department_approval: {
    className: "bg-amber-400 text-white",
    label: "Department Review",
  },
  pending_rfp_department_approval: {
    className: "bg-amber-400 text-white",
    label: "RFP Department Review",
  },
  pending_rfp_attachment: {
    className: "bg-blue-400 text-white",
    label: "RFP Attachment",
  },
  pending_custodian_approval: {
    className: "bg-cyan-500 text-white",
    label: "Custodian Approval",
  },
  pending_custodian_liquidation_review: {
    className: "bg-cyan-600 text-white",
    label: "Custodian Review",
  },
  pending_accounting_review: {
    className: "bg-amber-400 text-white",
    label: "Accounting Approval",
  },
  pending_liquidation: {
    className: "bg-blue-400 text-white",
    label: "Pending Liquidation",
  },
  partially_liquidated: {
    className: "bg-blue-400 text-white",
    label: "Partially Liquidated",
  },
  fully_liquidated: {
    className: "bg-teal-500 text-white",
    label: "Fully Liquidated",
  },
  transferred: {
    className: "bg-amber-400 text-white",
    label: "Transferred",
  },
  pending_cashier_return: {
    className: "bg-orange-400 text-white",
    label: "Cashier AR / Deposit Slip",
  },
  pending_cashier_closure: {
    className: "bg-orange-500 text-white",
    label: "Cashier Final",
  },
  rfp_created: {
    className: "bg-[#4e6493] text-white",
    label: "RFP Created",
  },
  pending_replenishment: {
    className: "bg-[#9a6500] text-white",
    label: "Pending Replenishment",
  },
  replenished: {
    className: "bg-[#08786f] text-white",
    label: "Replenished",
  },
  rejected: {
    className: "bg-rose-500 text-white",
    label: "Rejected",
  },
};

interface StatusBadgeProps {
  status: CashAdvanceStatus;
  request?: CashAdvanceRequest;
}

export default function StatusBadge({ status, request }: StatusBadgeProps) {
  const pendingTransfers = request?.pendingTransfers ?? (request?.pendingTransfer ? [request.pendingTransfer] : []);
  const meta = pendingTransfers.length > 0
    ? { className: "bg-amber-400 text-white", label: "Pending Acknowledgement" }
    : statusMap[status];

  return (
    <span className={`inline-flex rounded-full border px-3 py-1 text-xs font-semibold ${meta.className}`}>
      {meta.label}
    </span>
  );
}
