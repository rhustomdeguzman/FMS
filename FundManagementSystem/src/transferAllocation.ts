import type { CashAdvanceRequest } from "./types/CashAdvance";

export interface TransferAllocationRow {
  id: string;
  receiverName: string;
  amount: number;
  status: "acknowledged" | "pending";
}

export const getTransferAllocationRows = (
  request: CashAdvanceRequest,
  transferredAmount: number,
): TransferAllocationRow[] => {
  const apiAllocationRows = (request.transferAllocations ?? [])
    .filter((allocation) => allocation.status !== "denied")
    .map((allocation) => ({
      id: `transfer-${allocation.id}`,
      receiverName: allocation.toEmployee.name,
      amount: allocation.amount,
      status: allocation.status === "pending" ? ("pending" as const) : ("acknowledged" as const),
    }));

  if (apiAllocationRows.length > 0) {
    return apiAllocationRows;
  }

  const pendingTransfers = request.pendingTransfers ?? (request.pendingTransfer ? [request.pendingTransfer] : []);
  const acknowledgedRows = request.history
    .filter((event) => event.action === "transfer_acknowledged" && event.amount != null && event.amount > 0)
    .map((event, index) => ({
      id: `acknowledged-${event.id}-${index}`,
      receiverName: event.fromEmployee?.name ?? event.toEmployee?.name ?? "Receiver",
      amount: event.amount ?? 0,
      status: "acknowledged" as const,
    }));
  const pendingRows = pendingTransfers.map((transfer) => ({
    id: `pending-${transfer.id}`,
    receiverName: transfer.toEmployee.name,
    amount: transfer.amount,
    status: "pending" as const,
  }));
  const allocatedAmount = [...acknowledgedRows, ...pendingRows].reduce((sum, row) => sum + row.amount, 0);
  const unassignedAcknowledgedAmount = Math.max(transferredAmount - allocatedAmount, 0);
  const fallbackReceiverName =
    request.currentOwner.id !== request.originalOwner.id ? request.currentOwner.name : "Receiver";

  return [
    ...acknowledgedRows,
    ...(unassignedAcknowledgedAmount > 0
      ? [
          {
            id: "acknowledged-unassigned",
            receiverName: fallbackReceiverName,
            amount: unassignedAcknowledgedAmount,
            status: "acknowledged" as const,
          },
        ]
      : []),
    ...pendingRows,
  ];
};

export const getAcknowledgedTransferAmount = (request: CashAdvanceRequest, transferredAmount: number) =>
  getTransferAllocationRows(request, transferredAmount)
    .filter((allocation) => allocation.status === "acknowledged")
    .reduce((sum, allocation) => sum + allocation.amount, 0);
