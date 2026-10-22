import type {
  AppUser,
  CashAdvanceRequest,
  CashAdvanceRequestType,
  CustodianFundSummary,
  Employee,
  PettyCashReceiptDetail,
  PettyCashTransportationDetail,
} from "./types/CashAdvance";

export const pettyCashFundAmount = 20000;
export const pettyCashRequestLimit = 2000;

export const pettyCashRequestTypes: CashAdvanceRequestType[] = ["petty_cash", "petty_cash_advance"];

const inactivePettyCashStatuses = new Set<CashAdvanceRequest["status"]>(["rejected"]);
const completedReplenishmentStatuses = new Set<CashAdvanceRequest["status"]>(["replenished"]);

export const isPettyCashRequestType = (requestType?: CashAdvanceRequestType): boolean =>
  requestType === "petty_cash" || requestType === "petty_cash_advance";

export const isPettyCashReplenishment = (request: CashAdvanceRequest): boolean =>
  request.requestType === "petty_cash_replenishment";

export const isPettyCashRequest = (request: CashAdvanceRequest): boolean =>
  isPettyCashRequestType(request.requestType);

export const isRfpSourcedCashAdvance = (request: CashAdvanceRequest): boolean => {
  if (request.requestType === "cash_advance") {
    return true;
  }

  if (request.requestType === "petty_cash_replenishment") {
    return false;
  }

  const sourceSystem = request.sourceSystem.trim().toLowerCase();
  const isRfpSource = sourceSystem === "rfp system" || sourceSystem === "cash advance transfer";

  if (isRfpSource) {
    return true;
  }

  if (isPettyCashRequestType(request.requestType)) {
    return request.custodian === undefined && request.requestNumber.trim().toLowerCase().startsWith("ca-");
  }

  return false;
};

export const isPettyCashWorkflowRequest = (request: CashAdvanceRequest): boolean =>
  isPettyCashRequest(request) && !isRfpSourcedCashAdvance(request);

export const hasPettyCashReturnAmount = (request: CashAdvanceRequest): boolean =>
  isPettyCashWorkflowRequest(request) &&
  request.status === "pending_custodian_liquidation_review" &&
  (request.returnAmount ?? 0) > 0;

export const needsPettyCashReturnAcknowledgement = (request: CashAdvanceRequest): boolean =>
  hasPettyCashReturnAmount(request) && request.requestType !== "petty_cash_advance" && request.acknowledgementReceipt?.status !== "acknowledged";

export const getPettyCashRequestTypeLabel = (requestType?: CashAdvanceRequestType): string => {
  if (requestType === "petty_cash_advance") {
    return "Petty Cash Advance";
  }

  if (requestType === "petty_cash") {
    return "Petty Cash Reimbursement";
  }

  if (requestType === "petty_cash_replenishment") {
    return "Petty Cash Replenishment";
  }

  return "Cash Advance";
};

export const getPettyCashReceiptTotal = (receiptDetails: PettyCashReceiptDetail[] = []): number =>
  receiptDetails.reduce((sum, detail) => sum + detail.amount, 0);

export const getPettyCashTransportationTotal = (
  transportationDetails: PettyCashTransportationDetail[] = [],
): number => transportationDetails.reduce((sum, detail) => sum + detail.amount, 0);

export const getPettyCashActualSpentAmount = (
  receiptDetails: PettyCashReceiptDetail[] = [],
  transportationDetails: PettyCashTransportationDetail[] = [],
): number => getPettyCashReceiptTotal(receiptDetails) + getPettyCashTransportationTotal(transportationDetails);

const roundPettyCashAmount = (amount: number): number => Math.round(amount * 100) / 100;

export const splitPettyCashDetailsByAmount = (
  receiptDetails: PettyCashReceiptDetail[],
  transportationDetails: PettyCashTransportationDetail[],
  baseAmount: number,
) => {
  let remainingBaseAmount = Math.max(baseAmount, 0);
  const baseReceiptDetails: PettyCashReceiptDetail[] = [];
  const excessReceiptDetails: PettyCashReceiptDetail[] = [];
  const baseTransportationDetails: PettyCashTransportationDetail[] = [];
  const excessTransportationDetails: PettyCashTransportationDetail[] = [];

  const splitDetail = <T extends { id: string; amount: number }>(detail: T): [T | undefined, T | undefined] => {
    const detailAmount = Math.max(detail.amount, 0);
    const baseDetailAmount = Math.min(detailAmount, remainingBaseAmount);
    remainingBaseAmount = roundPettyCashAmount(remainingBaseAmount - baseDetailAmount);
    const excessDetailAmount = roundPettyCashAmount(detailAmount - baseDetailAmount);

    return [
      baseDetailAmount > 0 ? { ...detail, amount: roundPettyCashAmount(baseDetailAmount) } : undefined,
      excessDetailAmount > 0 ? { ...detail, id: `${detail.id}-excess`, amount: excessDetailAmount } : undefined,
    ];
  };

  receiptDetails.forEach((detail) => {
    const [baseDetail, excessDetail] = splitDetail(detail);
    if (baseDetail) {
      baseReceiptDetails.push(baseDetail);
    }
    if (excessDetail) {
      excessReceiptDetails.push(excessDetail);
    }
  });

  transportationDetails.forEach((detail) => {
    const [baseDetail, excessDetail] = splitDetail(detail);
    if (baseDetail) {
      baseTransportationDetails.push(baseDetail);
    }
    if (excessDetail) {
      excessTransportationDetails.push(excessDetail);
    }
  });

  return {
    baseReceiptDetails,
    baseTransportationDetails,
    excessReceiptDetails,
    excessTransportationDetails,
  };
};

const getRequestCustodianId = (request: CashAdvanceRequest) => request.custodian?.id;

const getUsedFundAmount = (request: CashAdvanceRequest) => {
  if (inactivePettyCashStatuses.has(request.status)) {
    return 0;
  }

  if (request.requestType === "petty_cash" && request.status !== "fully_liquidated") {
    return 0;
  }

  if (request.status === "fully_liquidated") {
    return request.liquidationAmount ?? request.amount - (request.returnAmount ?? 0);
  }

  return request.amount;
};

export const buildCustodianFundSummaries = (
  custodians: AppUser[],
  requests: CashAdvanceRequest[],
): CustodianFundSummary[] =>
  custodians.map((custodian) => {
    const assignedFundAmount = custodian.pettyCashFundAmount ?? pettyCashFundAmount;
    const custodianRequests = requests.filter(
      (request) => isPettyCashWorkflowRequest(request) && getRequestCustodianId(request) === custodian.id,
    );
    const replenishments = requests.filter(
      (request) => isPettyCashReplenishment(request) && getRequestCustodianId(request) === custodian.id,
    );
    const pendingRequestAmount = custodianRequests
      .filter(
        (request) =>
          (request.status === "pending_department_approval" || request.status === "pending_custodian_approval") &&
          request.liquidationAmount === undefined,
      )
      .reduce((sum, request) => sum + request.amount, 0);
    const replenishmentRequestedAmount = replenishments
      .filter((request) => request.status !== "rejected" && !completedReplenishmentStatuses.has(request.status))
      .reduce((sum, request) => sum + request.amount, 0);
    const replenishmentCompletedAmount = replenishments
      .filter((request) => completedReplenishmentStatuses.has(request.status))
      .reduce((sum, request) => sum + request.amount, 0);
    const usedAmount = Math.max(
      0,
      custodianRequests.reduce((sum, request) => sum + getUsedFundAmount(request), 0) - replenishmentCompletedAmount,
    );

    return {
      custodian,
      fundAmount: assignedFundAmount,
      usedAmount,
      pendingRequestAmount,
      replenishmentRequestedAmount,
      availableAmount: Math.max(assignedFundAmount - usedAmount, 0),
    };
  });

export const getCustodianFundSummary = (
  custodian: Employee,
  custodians: AppUser[],
  requests: CashAdvanceRequest[],
): CustodianFundSummary =>
  buildCustodianFundSummaries(custodians, requests).find((summary) => summary.custodian.id === custodian.id) ?? {
    custodian,
    fundAmount: custodian.pettyCashFundAmount ?? pettyCashFundAmount,
    usedAmount: 0,
    availableAmount: custodian.pettyCashFundAmount ?? pettyCashFundAmount,
    pendingRequestAmount: 0,
    replenishmentRequestedAmount: 0,
  };

export const getPettyCashRequestMaximum = (availableAmount: number): number =>
  Math.max(Math.min(pettyCashRequestLimit, availableAmount), 0);
