import type { CashAdvanceRequest } from "./types/CashAdvance";

export const getActualSpentAmount = (request: CashAdvanceRequest) =>
  request.liquidationAmount ?? request.liquidatedAmount;

export const isReturnAcknowledged = (request: CashAdvanceRequest) =>
  (request.returnAmount ?? 0) > 0 && request.acknowledgementReceipt?.status === "acknowledged";

export const getLiquidationBaseAmount = (request: CashAdvanceRequest) => {
  const actualSpent = getActualSpentAmount(request);
  const hasSubmittedLiquidation =
    request.liquidationAmount !== undefined ||
    request.liquidatedAmount > 0 ||
    request.returnAmount !== undefined ||
    request.excessAmount !== undefined;

  return hasSubmittedLiquidation
    ? Math.max(actualSpent + (request.returnAmount ?? 0) - (request.excessAmount ?? 0), 0)
    : request.remainingAmount;
};

export const getLiquidatedAmount = (request: CashAdvanceRequest) => {
  const baseAmount = getLiquidationBaseAmount(request);
  const actualSpent = Math.min(getActualSpentAmount(request), baseAmount);
  const clearedReturnAmount = isReturnAcknowledged(request) ? request.returnAmount ?? 0 : 0;

  return Math.min(baseAmount, actualSpent + clearedReturnAmount);
};

export const getPendingLiquidationAmount = (request: CashAdvanceRequest) =>
  Math.max(getLiquidationBaseAmount(request) - getLiquidatedAmount(request), 0);

export const getTransferredOutAmount = (request: CashAdvanceRequest) => {
  const acknowledgedPartialTransferAmount = (request.transferAllocations ?? [])
    .filter((allocation) => allocation.status === "acknowledged" && !allocation.isWholeRequest)
    .reduce((sum, allocation) => sum + allocation.amount, 0);

  if (acknowledgedPartialTransferAmount > 0) {
    return Math.min(request.amount, acknowledgedPartialTransferAmount);
  }

  const hasTransferAdjustedBalance =
    request.remainingAmount > 0 &&
    request.remainingAmount < request.amount &&
    request.liquidationAmount === undefined &&
    request.returnAmount === undefined &&
    request.excessAmount === undefined;

  return hasTransferAdjustedBalance ? request.amount - request.remainingAmount : 0;
};

export const getTransferAdjustedRequestAmount = (request: CashAdvanceRequest) =>
  Math.max(request.amount - getTransferredOutAmount(request), 0);
