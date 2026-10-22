import CustodianReturnModal from "../components/modals/CustodianReturnModal";
import { type Dispatch, type SetStateAction, useMemo, useState } from "react";
import { useEffect } from "react";
import { getAllowedTabs, getVisibleRequests } from "../auth/roleConfig";
import { buildAcknowledgementReceiptPrintHtml } from "../acknowledgementReceiptPrint";
import ApprovalQueue from "../components/requests/ApprovalQueue";
import AdminPanel from "../components/admin/AdminPanel";
import AppShell from "../components/layout/AppShell";
import CashierPanel from "../components/cashier/CashierPanel";
import CustodianPanel from "../components/custodian/CustodianPanel";
import DashboardCharts from "../components/dashboard/DashboardCharts";
import DashboardOverview from "../components/dashboard/DashboardOverview";
import PrintNotificationStash from "../components/dashboard/PrintNotificationStash";
import AcknowledgementReceiptModal from "../components/modals/AcknowledgementReceiptModal";
import CashierReceiptModal from "../components/modals/CashierReceiptModal";
import ReceiptNumberModal from "../components/modals/ReceiptNumberModal";
import HistoryModal from "../components/modals/HistoryModal";
import LiquidateModal from "../components/modals/LiquidateModal";
import PettyCashRequestModal from "../components/modals/PettyCashRequestModal";
import RequestDetailsModal from "../components/modals/RequestDetailsModal";
import RfpAttachmentModal from "../components/modals/RfpAttachmentModal";
import ReturnReasonModal from "../components/modals/ReturnReasonModal";
import TransferModal from "../components/modals/TransferModal";
import RequestCard from "../components/RequestCard";
import ApprovalHistoryTable from "../components/requests/ApprovalHistoryTable";
import RequestTable from "../components/requests/RequestTable";
import { getCashierUser } from "../data/mockData";
import { getPendingLiquidationAmount } from "../liquidationAmounts";
import {
  buildCustodianFundSummaries,
  getCustodianFundSummary,
  getPettyCashActualSpentAmount,
  getPettyCashRequestMaximum,
  hasPettyCashReturnAmount,
  isPettyCashWorkflowRequest,
  isRfpSourcedCashAdvance,
  needsPettyCashReturnAcknowledgement,
  pettyCashRequestLimit,
  splitPettyCashDetailsByAmount,
} from "../pettyCash";
import { buildDemoRequestPrintHtml, isDepartmentApprovalPrintAvailable } from "../requestPrint";
import { downloadApiAccountingReport, fetchApiReceiptDocumentNumber, getApiRequestPrintUrl } from "../services/fundManagementApi";
import type {
  AcknowledgementReceipt,
  AccountingReportPeriod,
  AppUser,
  CashAdvanceReceiptDetail,
  CashAdvanceRequest,
  CashAdvanceRequestType,
  CreateAppUserInput,
  DataMode,
  DashboardMetrics,
  DashboardTab,
  DepartmentCustodianAssignment,
  Employee,
  PendingTransfer,
  PettyCashReceiptDetail,
  PettyCashTransportationDetail,
  RfpDecision,
  TransactionHistory,
  UpdateAppUserInput,
} from "../types/CashAdvance";

interface LiveWorkflowApi {
  refreshRequests: () => Promise<void>;
  refreshUsers?: () => Promise<void>;
  submitLiquidation: (
    requestId: string,
    amountSpent: number,
    notes: string,
    receiptDetails: CashAdvanceReceiptDetail[],
    pettyCashReceiptDetails: PettyCashReceiptDetail[],
    pettyCashTransportationDetails: PettyCashTransportationDetail[],
    attachments: File[],
    replaceExistingAttachments: boolean,
  ) => Promise<void>;
  submitRfpAttachment: (requestId: string, notes: string, attachments: File[]) => Promise<void>;
  departmentDecision: (
    requestId: string,
    approved: boolean,
    notes: string,
    rfpDecision?: RfpDecision,
    companyId?: number,
  ) => Promise<void>;
  accountingDecision: (requestId: string, approved: boolean, notes: string) => Promise<void>;
  transferRequest: (
    requestId: string,
    toUserId: string,
    amount: number,
    transferWholeRequest: boolean,
    notes: string,
  ) => Promise<void>;
  respondToTransfer: (requestId: string, transferId: string, accepted: boolean, notes: string) => Promise<void>;
  createCashierReceipt: (
    requestId: string,
    receiptNumber: string,
    depositSlipAttachment: File | null,
    depositDate: string,
    depositAmount: number,
    depositoryBank: string,
    notes: string,
  ) => Promise<void>;
  createCustodianReceipt?: (requestId: string, receiptNumber: string, notes: string) => Promise<void>;
  closeCashierLiquidation: (requestId: string, notes: string) => Promise<void>;
  createPettyCashRequest?: (
    requestType: CashAdvanceRequestType,
    requestorUserId: string,
    custodianUserId: string,
    amount: number,
    purpose: string,
    pettyCashReceiptDetails: PettyCashReceiptDetail[],
    pettyCashTransportationDetails: PettyCashTransportationDetail[],
    attachment: File | null,
    companyId?: number,
  ) => Promise<void>;
  custodianDecision?: (requestId: string, userId: string, approved: boolean, notes: string, returnedAmount?: number) => Promise<void>;
  createPettyCashReplenishment?: (custodianUserId: string, amount: number, notes: string) => Promise<void>;
  submitPettyCashReplenishmentCv?: (requestId: string, custodianUserId: string, cvNumber: string) => Promise<void>;
  createUser?: (user: CreateAppUserInput) => Promise<void>;
  updateUser?: (userId: string, user: UpdateAppUserInput) => Promise<void>;
  updateCustodianFund?: (userId: string, pettyCashFundAmount: number) => Promise<void>;
  updateDepartmentCustodian?: (departmentCode: string, custodianUserId: string) => Promise<void>;
  refreshDepartmentCustodians?: () => Promise<void>;
}

interface DashboardProps {
  user: AppUser;
  dataMode: DataMode;
  requests: CashAdvanceRequest[];
  approvalHistoryRequests: CashAdvanceRequest[];
  setRequests: Dispatch<SetStateAction<CashAdvanceRequest[]>>;
  users: AppUser[];
  departmentCustodians: DepartmentCustodianAssignment[];
  liveWorkflow?: LiveWorkflowApi;
  onLogout: () => void;
}

interface ReturnDecision {
  request: CashAdvanceRequest;
  reviewer: "department" | "accounting";
}

const createHistoryId = () => `h-${Date.now()}-${Math.random().toString(16).slice(2)}`;
const createTransferId = () => `tr-${Date.now()}-${Math.random().toString(16).slice(2)}`;
const createCustodianLiquidationReceiptNumber = (request: CashAdvanceRequest) => `LIQ-${request.requestNumber}`;

const getPendingTransfers = (request: CashAdvanceRequest): PendingTransfer[] =>
  request.pendingTransfers ?? (request.pendingTransfer ? [request.pendingTransfer] : []);

const getPendingMetricAmount = (request: CashAdvanceRequest, user: AppUser) => {
  if (user.role === "requestor" && request.currentOwner.id !== user.id) {
    return 0;
  }

  return getPendingLiquidationAmount(request);
};

const buildMetrics = (requests: CashAdvanceRequest[], user: AppUser): DashboardMetrics => ({
  pendingLiquidation: requests.filter((request) => request.status === "pending_liquidation").length,
  partialLiquidation: requests.filter((request) => request.status === "partially_liquidated").length,
  pendingDepartmentApproval: requests.filter((request) => request.status === "pending_department_approval").length,
  pendingRfpDepartmentApproval: requests.filter((request) => request.status === "pending_rfp_department_approval").length,
  pendingAccountingReview: requests.filter((request) => request.status === "pending_accounting_review").length,
  pendingCashierReturn: requests.filter(
    (request) => request.status === "pending_cashier_return" || request.status === "pending_cashier_closure",
  ).length,
  totalPendingAmount: requests.reduce((sum, request) => sum + getPendingMetricAmount(request, user), 0),
  totalRequests: requests.length,
});

const buildReturnNotes = (reviewerLabel: string, reason: string) =>
  `${reviewerLabel} returned the request for correction. Reason: ${reason}`;

const getReturnedLiquidationAmount = (request: CashAdvanceRequest) =>
  request.remainingAmount > 0 ? request.remainingAmount : request.amount;

const normalizeDepartment = (department: string) => department.trim().toLowerCase();

const toEmployee = (user: AppUser): Employee => ({
  id: user.id,
  name: user.name,
  department: user.department,
  departmentCode: user.departmentCode,
  avatar: user.avatar,
  pettyCashFundAmount: user.pettyCashFundAmount,
});

const createPettyCashRequestNumber = (requests: CashAdvanceRequest[]) =>
  `PC-${new Date().getFullYear()}-${String(
    requests.filter((request) => request.requestType === "petty_cash" || request.requestType === "petty_cash_advance").length + 1,
  ).padStart(3, "0")}`;

const buildPettyCashExcessPurpose = (request: CashAdvanceRequest) => {
  const purpose = `Excess reimbursement for ${request.requestNumber}: ${request.purpose}`;
  return purpose.length > 500 ? `${purpose.slice(0, 497)}...` : purpose;
};

const createPettyCashExcessRequest = (
  sourceRequest: CashAdvanceRequest,
  requests: CashAdvanceRequest[],
  excessAmount: number,
  pettyCashReceiptDetails: PettyCashReceiptDetail[],
  pettyCashTransportationDetails: PettyCashTransportationDetail[],
): CashAdvanceRequest => ({
  id: `pc-excess-${Date.now()}-${Math.random().toString(16).slice(2)}`,
  originalRequestId: sourceRequest.id,
  requestNumber: createPettyCashRequestNumber(requests),
  referenceNumber: sourceRequest.requestNumber,
  requestType: "petty_cash",
  amount: excessAmount,
  remainingAmount: excessAmount,
  liquidatedAmount: 0,
  purpose: buildPettyCashExcessPurpose(sourceRequest),
  sourceSystem: "Petty Cash",
  createdAt: new Date(),
  status: "pending_department_approval",
  requestorDepartmentApproverName: sourceRequest.requestorDepartmentApproverName,
  custodian: sourceRequest.custodian,
  currentOwner: sourceRequest.originalOwner,
  originalOwner: sourceRequest.originalOwner,
  department: sourceRequest.department,
  pettyCashReceiptDetails,
  pettyCashTransportationDetails,
  attachmentNames: sourceRequest.attachmentNames,
  attachments: sourceRequest.attachments,
  history: [
    {
      id: createHistoryId(),
      timestamp: new Date(),
      action: "petty_cash_requested",
      fromEmployee: sourceRequest.originalOwner,
      toEmployee: sourceRequest.custodian,
      amount: excessAmount,
      notes: `Excess petty cash reimbursement created from ${sourceRequest.requestNumber}.`,
    },
  ],
  dueDate: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
});

const createPettyCashReplenishmentNumber = (requests: CashAdvanceRequest[]) =>
  `PCR-${new Date().getFullYear()}-${String(
    requests.filter((request) => request.requestType === "petty_cash_replenishment").length + 1,
  ).padStart(3, "0")}`;

const canClaimRfpLiquidationCustody = (request: CashAdvanceRequest, user: AppUser) =>
  (request.payeeUserId === user.id ||
    (user.role === "department_head" &&
      normalizeDepartment(request.department) === normalizeDepartment(user.department))) &&
  request.currentOwner.id !== user.id &&
  isRfpSourcedCashAdvance(request) &&
  request.remainingAmount > 0 &&
  ["pending_liquidation", "partially_liquidated"].includes(request.status) &&
  getPendingTransfers(request).length === 0;

const isVisiblePersonalRequest = (request: CashAdvanceRequest, user: AppUser) => {
  if (request.currentOwner.id === user.id || getPendingTransfers(request).some((transfer) => transfer.toEmployee.id === user.id)) {
    return true;
  }

  if (canClaimRfpLiquidationCustody(request, user)) {
    return true;
  }

  return false;
};

export default function Dashboard({
  user,
  dataMode,
  requests,
  approvalHistoryRequests,
  setRequests,
  users,
  departmentCustodians,
  liveWorkflow,
  onLogout,
}: DashboardProps) {
  const [activeTab, setActiveTab] = useState<DashboardTab>("dashboard");

  useEffect(() => {
    // Browser history can restore this page without mounting React again.
    const handlePageShow = () => setActiveTab("dashboard");
    window.addEventListener("pageshow", handlePageShow);
    return () => window.removeEventListener("pageshow", handlePageShow);
  }, []);

  const [liquidateRequest, setLiquidateRequest] = useState<CashAdvanceRequest | null>(null);
  const [rfpAttachmentRequestId, setRfpAttachmentRequestId] = useState<string | null>(null);
  const [transferRequest, setTransferRequest] = useState<CashAdvanceRequest | null>(null);
  const [historyRequest, setHistoryRequest] = useState<CashAdvanceRequest | null>(null);
  const [detailsRequestId, setDetailsRequestId] = useState<string | null>(null);
  const [receiptRequestId, setReceiptRequestId] = useState<string | null>(null);
  const [receiptNumberRequest, setReceiptNumberRequest] = useState<CashAdvanceRequest | null>(null);
  const [printedReceiptNumber, setPrintedReceiptNumber] = useState("");
  const [receiptView, setReceiptView] = useState<{
    receipt: AcknowledgementReceipt;
    request: CashAdvanceRequest;
  } | null>(null);
  const [returnDecision, setReturnDecision] = useState<ReturnDecision | null>(null);
  const [custodianReturnRequest, setCustodianReturnRequest] = useState<CashAdvanceRequest | null>(null);
  const [isPettyCashRequestOpen, setIsPettyCashRequestOpen] = useState(false);
  const [actionError, setActionError] = useState("");
  const [isSyncing, setIsSyncing] = useState(false);
  const [approvingRequestNumber, setApprovingRequestNumber] = useState<string | null>(null);

  const tabs = useMemo(() => getAllowedTabs(user.role), [user.role]);
  const visibleRequests = useMemo(() => getVisibleRequests(requests, user), [requests, user]);
  const myRequests = useMemo(
    () => requests.filter((request) => isVisiblePersonalRequest(request, user)),
    [requests, user],
  );
  const printableRequests = useMemo(
    () => {
      if (user.role === "requestor") {
        return myRequests.filter(isDepartmentApprovalPrintAvailable);
      }

      return [];
    },
    [myRequests, user.role],
  );
  const pendingTransferAcknowledgements = useMemo(
    () =>
      myRequests.filter((request) =>
        getPendingTransfers(request).some((transfer) => transfer.toEmployee.id === user.id),
      ),
    [myRequests, user.id],
  );
  const pendingReceiptAcknowledgements = useMemo(
    () => {
      if (user.role === "cashier") {
        return requests.filter(
          (request) =>
            request.status === "pending_cashier_return" &&
            request.acknowledgementReceipt?.status !== "acknowledged",
        );
      }

      if (user.role === "custodian") {
        return requests.filter(
          (request) =>
            request.custodian?.id === user.id &&
            needsPettyCashReturnAcknowledgement(request),
        );
      }

      return [];
    },
    [requests, user.id, user.role],
  );
  const myPendingLiquidationRequests = useMemo(
    () =>
      myRequests.filter(
        (request) => {
          const isOwnerAction =
            request.currentOwner.id === user.id &&
            ["pending_liquidation", "partially_liquidated", "pending_rfp_attachment"].includes(request.status);

          return (
            (isOwnerAction || canClaimRfpLiquidationCustody(request, user)) &&
            getPendingTransfers(request).length === 0
          );
        },
      ),
    [myRequests, user.department, user.id, user.role],
  );
  const dashboardRequests = user.role === "accounting" || user.role === "admin" ? visibleRequests : myRequests;
  const metrics = useMemo(() => buildMetrics(visibleRequests, user), [visibleRequests, user]);
  const cashierPendingCount = requests.filter(
    (request) => request.status === "pending_cashier_return" || request.status === "pending_cashier_closure",
  ).length;
  const knownRequests = useMemo(
    () => [
      ...requests,
      ...approvalHistoryRequests.filter(
        (approvalHistoryRequest) => !requests.some((request) => request.id === approvalHistoryRequest.id),
      ),
    ],
    [approvalHistoryRequests, requests],
  );
  const detailsRequest = useMemo(
    () => knownRequests.find((request) => request.id === detailsRequestId) ?? null,
    [knownRequests, detailsRequestId],
  );
  const receiptRequest = useMemo(
    () => requests.find((request) => request.id === receiptRequestId) ?? null,
    [requests, receiptRequestId],
  );
  const isCustodianReceiptRequest =
    receiptRequest !== null &&
    isPettyCashWorkflowRequest(receiptRequest) &&
    receiptRequest.status === "pending_custodian_liquidation_review";
  const rfpAttachmentRequest = useMemo(
    () => requests.find((request) => request.id === rfpAttachmentRequestId) ?? null,
    [requests, rfpAttachmentRequestId],
  );
  const custodians = useMemo(() => users.filter((item) => item.role === "custodian"), [users]);
  const custodianFunds = useMemo(
    () => buildCustodianFundSummaries(custodians, requests),
    [custodians, requests],
  );
  const departmentCustodian = useMemo(
    () =>
      departmentCustodians.find((assignment) =>
        user.departmentCode !== undefined
          ? assignment.departmentCode === String(user.departmentCode)
          : normalizeDepartment(assignment.departmentName) === normalizeDepartment(user.department),
      ),
    [departmentCustodians, user.department, user.departmentCode],
  );
  const departmentCustodianFunds = useMemo(
    () => custodianFunds.filter((fund) => fund.custodian.id === departmentCustodian?.custodianUserId),
    [custodianFunds, departmentCustodian?.custodianUserId],
  );
  const currentCustodianFund = useMemo(
    () => getCustodianFundSummary(user, custodians, requests),
    [custodians, requests, user],
  );
  const departmentQueue = visibleRequests.filter(
    (request) =>
      request.status === "pending_department_approval" || request.status === "pending_rfp_department_approval",
  );
  const custodianQueue = visibleRequests.filter(
    (request) =>
      isPettyCashWorkflowRequest(request) &&
      (user.role === "admin" || request.custodian?.id === user.id) &&
      (request.status === "pending_custodian_approval" ||
        request.status === "pending_custodian_liquidation_review"),
  );
  const custodianChartRequests = visibleRequests.filter(
    (request) =>
      (user.role === "admin" || request.custodian?.id === user.id) &&
      (request.requestType === "petty_cash" || request.requestType === "petty_cash_advance"),
  );
  const custodianReplenishmentRequests = visibleRequests.filter(
    (request) =>
      request.requestType === "petty_cash_replenishment" &&
      (user.role === "admin" || request.custodian?.id === user.id),
  );
  const custodianPanelRequests = [...custodianChartRequests, ...custodianReplenishmentRequests];
  const displayedCustodianFund =
    user.role === "admin" ? custodianFunds[0] ?? currentCustodianFund : currentCustodianFund;
  const custodianApprovalCount = custodianChartRequests.filter(
    (request) => request.status === "pending_custodian_approval",
  ).length;
  const custodianLiquidationReviewCount = custodianChartRequests.filter(
    (request) => request.status === "pending_custodian_liquidation_review",
  ).length;
  const custodianPendingReplenishmentCount = custodianReplenishmentRequests.filter(
    (request) => request.status === "pending_replenishment",
  ).length;
  const accountingQueue = requests.filter((request) => request.status === "pending_accounting_review");
  const tabPendingCounts: Partial<Record<DashboardTab, number>> = {
    "my-requests": myPendingLiquidationRequests.length,
    "department-review": departmentQueue.length,
    custodian: custodianQueue.length + custodianPendingReplenishmentCount,
    accounting: accountingQueue.length,
    cashier: cashierPendingCount,
  };
  const cashierUser = getCashierUser();

  const runLiveWorkflow = async (action: () => Promise<void>, onSuccess?: () => void) => {
    if (!liveWorkflow) {
      return;
    }

    setIsSyncing(true);
    setActionError("");

    try {
      await action();
      await liveWorkflow.refreshRequests();
      onSuccess?.();
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "Live Data action failed.");
    } finally {
      setIsSyncing(false);
    }
  };

  const runApprovalWorkflow = (
    request: CashAdvanceRequest,
    action: () => Promise<void>,
    onSuccess?: () => void,
  ) => {
    setApprovingRequestNumber(request.requestNumber);
    void runLiveWorkflow(action, onSuccess).finally(() => setApprovingRequestNumber(null));
  };

  const runAdminWorkflow = (action: () => Promise<void>) => {
    if (user.role !== "admin" || dataMode !== "live" || !liveWorkflow) {
      setActionError("Admin changes are available only for the admin account in Live mode.");
      return;
    }

    void runLiveWorkflow(async () => {
      await action();
      await liveWorkflow.refreshUsers?.();
      await liveWorkflow.refreshDepartmentCustodians?.();
    });
  };

  const handleAdminCreateUser = (newUser: CreateAppUserInput) => {
    if (!liveWorkflow?.createUser) {
      setActionError("User management API is not available.");
      return;
    }

    runAdminWorkflow(() => liveWorkflow.createUser?.(newUser) ?? Promise.resolve());
  };

  const handleAdminUpdateUser = (userId: string, updatedUser: UpdateAppUserInput) => {
    if (!liveWorkflow?.updateUser) {
      setActionError("User management API is not available.");
      return;
    }

    runAdminWorkflow(() => liveWorkflow.updateUser?.(userId, updatedUser) ?? Promise.resolve());
  };

  const handleAdminUpdateCustodianFund = (userId: string, pettyCashFundAmount: number) => {
    if (!liveWorkflow?.updateCustodianFund) {
      setActionError("Custodian fund API is not available.");
      return;
    }

    runAdminWorkflow(() => liveWorkflow.updateCustodianFund?.(userId, pettyCashFundAmount) ?? Promise.resolve());
  };

  const handleAdminAssignDepartmentCustodian = (departmentCode: string, custodianUserId: string) => {
    if (!liveWorkflow?.updateDepartmentCustodian) {
      setActionError("Department custodian assignment API is not available.");
      return;
    }

    runAdminWorkflow(
      () => liveWorkflow.updateDepartmentCustodian?.(departmentCode, custodianUserId) ?? Promise.resolve(),
    );
  };

  const handlePrintRequest = (request: CashAdvanceRequest) => {
    if (!isDepartmentApprovalPrintAvailable(request) || typeof window === "undefined") {
      return;
    }

    if (dataMode === "live") {
      try {
        window.open(getApiRequestPrintUrl(request, user), "_blank", "noopener,noreferrer");
      } catch (error) {
        setActionError(error instanceof Error ? error.message : "This request is not available to print yet.");
      }
      return;
    }

    const printWindow = window.open("", "_blank");
    if (!printWindow) {
      setActionError("Unable to open the print view. Please allow pop-ups for this site.");
      return;
    }

    printWindow.document.open();
    printWindow.document.write(buildDemoRequestPrintHtml(request));
    printWindow.document.close();
    printWindow.focus();
    printWindow.setTimeout(() => printWindow.print(), 250);
  };

  const handleGenerateAccountingReport = async (period: AccountingReportPeriod) => {
    if (dataMode !== "live" || user.role !== "accounting") {
      throw new Error("Accounting report export is only available in Live Data mode.");
    }

    await downloadApiAccountingReport(user, period);
  };

  const handleCreateAcknowledgementReceipt = (request: CashAdvanceRequest) => {
    if (!request.acknowledgementReceipt) {
      setReceiptNumberRequest(request);
      return;
    }
    setPrintedReceiptNumber(request.acknowledgementReceipt.receiptNumber);
    setReceiptRequestId(request.id);
  };

  const handlePrintNewReceipt = (receiptNumber: string) => {
    const request = receiptNumberRequest;
    if (!request) return;
    if (typeof window !== "undefined") {
      const printWindow = window.open("", "_blank");

      if (printWindow) {
        const isCustodianReturn =
          isPettyCashWorkflowRequest(request) && request.status === "pending_custodian_liquidation_review";
        printWindow.document.open();
        printWindow.document.write(
          buildAcknowledgementReceiptPrintHtml(
            request,
            user,
            isCustodianReturn
              ? { variant: "custodian", receiptNumber }
              : { receiptNumber },
          ),
        );
        printWindow.document.close();
        printWindow.focus();
      } else {
        throw new Error("Unable to open the acknowledgement receipt print view. Please allow pop-ups for this site.");
      }
    }

    setPrintedReceiptNumber(receiptNumber);
    setReceiptNumberRequest(null);
    setReceiptRequestId(request.id);
  };

  const handlePrintAcknowledgementReceipt = (
    request: CashAdvanceRequest,
    receipt: AcknowledgementReceipt,
  ) => {
    if (typeof window === "undefined") {
      return;
    }

    const printWindow = window.open("", "_blank");
    if (!printWindow) {
      setActionError("Unable to open the acknowledgement receipt print view. Please allow pop-ups for this site.");
      return;
    }

    const isCustodianReturn =
      isPettyCashWorkflowRequest(request) && (request.returnAmount ?? 0) > 0;
    printWindow.document.open();
    printWindow.document.write(
      buildAcknowledgementReceiptPrintHtml(
        request,
        user,
        isCustodianReturn
          ? { variant: "custodian", receiptNumber: receipt.receiptNumber }
          : { receiptNumber: receipt.receiptNumber },
      ),
    );
    printWindow.document.close();
    printWindow.focus();
  };

  const shouldPrintCustodianLiquidationAcknowledgement = (request: CashAdvanceRequest, approved: boolean) =>
    approved &&
    !(request.requestType === "petty_cash_advance" && hasPettyCashReturnAmount(request)) &&
    isPettyCashWorkflowRequest(request) &&
    (request.status === "pending_custodian_liquidation_review" ||
      (request.requestType === "petty_cash" && request.status === "pending_custodian_approval"));

  const openAcknowledgementReceiptPrintWindow = () => {
    if (typeof window === "undefined") {
      return null;
    }

    return window.open("", "_blank");
  };

  const handlePrintCustodianLiquidationAcknowledgement = (
    request: CashAdvanceRequest,
    printWindow: Window | null = null,
  ) => {
    if (typeof window === "undefined") {
      return;
    }

    const targetWindow = printWindow ?? window.open("", "_blank");
    if (!targetWindow) {
      setActionError("Unable to open the acknowledgement receipt print view. Please allow pop-ups for this site.");
      return;
    }

    targetWindow.document.open();
    targetWindow.document.write(
      buildAcknowledgementReceiptPrintHtml(request, user, {
        variant: "custodian_liquidation",
        receiptNumber: createCustodianLiquidationReceiptNumber(request),
      }),
    );
    targetWindow.document.close();
    targetWindow.focus();
  };

  const handleCreatePettyCashRequest = (
    requestType: CashAdvanceRequestType,
    custodianId: string,
    amount: number,
    purpose: string,
    pettyCashReceiptDetails: PettyCashReceiptDetail[],
    pettyCashTransportationDetails: PettyCashTransportationDetail[],
    attachment: File | null,
    companyId?: number,
  ) => {
    const selectedCustodian = custodians.find((custodian) => custodian.id === custodianId);
    const selectedFund = departmentCustodianFunds.find((fund) => fund.custodian.id === custodianId);
    const maximumAmount = getPettyCashRequestMaximum(selectedFund?.availableAmount ?? 0);
    const actualSpentAmount =
      requestType === "petty_cash"
        ? getPettyCashActualSpentAmount(pettyCashReceiptDetails, pettyCashTransportationDetails)
        : amount;
    const reimbursementExcessAmount = requestType === "petty_cash" ? Math.max(actualSpentAmount - amount, 0) : 0;

    if (!selectedCustodian || !selectedFund) {
      setActionError("No custodian is assigned to your department.");
      return;
    }

    if (amount <= 0 || amount > maximumAmount || amount > pettyCashRequestLimit) {
      setActionError(
        `Petty cash amount must be within the PHP ${pettyCashRequestLimit.toLocaleString()} cap and the custodian's available fund.`,
      );
      return;
    }

    if (requestType === "petty_cash" && actualSpentAmount + 0.01 < amount) {
      setActionError("Actual spent must be equal to or greater than the petty cash reimbursement amount.");
      return;
    }

    if (requestType === "petty_cash" && reimbursementExcessAmount > pettyCashRequestLimit) {
      setActionError("The reimbursement excess must be within the petty cash request cap because it creates a new request.");
      return;
    }

    if (requestType === "petty_cash" && actualSpentAmount > selectedFund.availableAmount) {
      setActionError("Petty cash actual spent amount exceeds the custodian's available fund.");
      return;
    }

    if (dataMode === "live" && liveWorkflow?.createPettyCashRequest) {
      void runLiveWorkflow(
        () =>
          liveWorkflow.createPettyCashRequest?.(
            requestType,
            user.id,
            custodianId,
            amount,
            purpose,
            pettyCashReceiptDetails,
            pettyCashTransportationDetails,
            attachment,
            companyId,
          ) ?? Promise.resolve(),
        () => setIsPettyCashRequestOpen(false),
      );
      return;
    }

    const custodianEmployee = toEmployee(selectedCustodian);
    const departmentApprover = users.find(
      (candidate) =>
        candidate.role === "department_head" &&
        normalizeDepartment(candidate.department) === normalizeDepartment(user.department),
    );

    setRequests((current) => [
      {
        id: `pc-${Date.now()}`,
        requestNumber: createPettyCashRequestNumber(current),
        requestType,
        companyId,
        amount,
        remainingAmount: amount,
        liquidatedAmount: 0,
        purpose,
        sourceSystem: "Petty Cash",
        createdAt: new Date(),
        status: "pending_department_approval",
        requestorDepartmentApproverName: departmentApprover?.name,
        custodian: custodianEmployee,
        currentOwner: user,
        originalOwner: user,
        department: user.department,
        pettyCashReceiptDetails,
        pettyCashTransportationDetails,
        attachmentNames: attachment ? [attachment.name] : undefined,
        attachments: attachment
          ? [
              {
                id: `pc-attachment-${Date.now()}`,
                fileName: attachment.name,
                contentType: attachment.type || "application/octet-stream",
                fileSize: attachment.size,
              },
            ]
          : undefined,
        history: [
            {
              id: createHistoryId(),
              timestamp: new Date(),
              action: "petty_cash_requested",
              fromEmployee: user,
              toEmployee: custodianEmployee,
              amount,
              notes:
                reimbursementExcessAmount > 0
                  ? "Petty cash reimbursement submitted for department approval with excess actual spent."
                  : "Petty cash request submitted for department approval.",
            },
          ],
        dueDate: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
      ...current,
    ]);

    setIsPettyCashRequestOpen(false);
  };

  const handleCreatePettyCashReplenishment = (amount: number, notes: string) => {
    if (user.role !== "custodian") {
      return;
    }

    if (amount <= 0) {
      setActionError("Replenishment amount must be greater than zero.");
      return;
    }

    if (dataMode === "live" && liveWorkflow?.createPettyCashReplenishment) {
      void runLiveWorkflow(() => liveWorkflow.createPettyCashReplenishment?.(user.id, amount, notes) ?? Promise.resolve());
      return;
    }

    setRequests((current) => [
      {
        id: `pcr-${Date.now()}`,
        requestNumber: createPettyCashReplenishmentNumber(current),
        referenceNumber: createPettyCashReplenishmentNumber(current),
        requestType: "petty_cash_replenishment",
        amount,
        remainingAmount: 0,
        liquidatedAmount: 0,
        purpose: notes || "Petty cash fund replenishment",
        sourceSystem: "RFP System",
        createdAt: new Date(),
        status: "pending_replenishment",
        custodian: user,
        currentOwner: user,
        originalOwner: user,
        department: user.department,
        history: [
          {
            id: createHistoryId(),
            timestamp: new Date(),
            action: "petty_cash_replenishment_created",
            fromEmployee: user,
            amount,
            notes: notes || "Custodian created a replenishment RFP request.",
          },
          {
            id: createHistoryId(),
            timestamp: new Date(),
            action: "rfp_created",
            fromEmployee: user,
            amount,
            notes: "Replenishment RFP request created.",
          },
        ],
        dueDate: new Date(),
      },
      ...current,
    ]);
  };

  const handleSubmitPettyCashReplenishmentCv = (request: CashAdvanceRequest, cvNumber: string) => {
    const trimmedCvNumber = cvNumber.trim();

    if (user.role !== "custodian" || request.custodian?.id !== user.id) {
      setActionError("Only the assigned custodian can submit the CV Number for replenishment.");
      return;
    }

    if (request.requestType !== "petty_cash_replenishment" || request.status !== "pending_replenishment") {
      setActionError("This request is not pending replenishment.");
      return;
    }

    if (!trimmedCvNumber) {
      setActionError("CV Number is required.");
      return;
    }

    if (dataMode === "live" && liveWorkflow?.submitPettyCashReplenishmentCv) {
      void runLiveWorkflow(() =>
        liveWorkflow.submitPettyCashReplenishmentCv?.(request.id, user.id, trimmedCvNumber) ?? Promise.resolve(),
      );
      return;
    }

    setRequests((current) =>
      current.map((item) =>
        item.id === request.id
          ? {
              ...item,
              status: "replenished" as const,
              cvNumber: trimmedCvNumber,
              history: [
                ...item.history,
                {
                  id: createHistoryId(),
                  timestamp: new Date(),
                  action: "petty_cash_replenished" as const,
                  fromEmployee: user,
                  amount: item.amount,
                  notes: `CV Number ${trimmedCvNumber} submitted. Petty cash fund replenished.`,
                },
              ],
            }
          : item,
      ),
    );
  };

  const handleDepartmentDecision = (
    request: CashAdvanceRequest,
    approved: boolean,
    returnReason?: string,
    rfpDecision: RfpDecision = "create",
    waiveReason?: string,
    companyId?: number,
  ): boolean | void => {
    if (!approved && !returnReason) {
      setActionError("");
      setReturnDecision({ request, reviewer: "department" });
      return false;
    }

    const returnNotes = returnReason ? buildReturnNotes("Department", returnReason) : "";
    const needsRfpDecision =
      (request.status === "pending_department_approval" || request.status === "pending_rfp_department_approval") &&
      (request.excessAmount ?? 0) > 0;
    const trimmedWaiveReason = waiveReason?.trim() ?? "";

    if (approved && needsRfpDecision && rfpDecision === "waive" && trimmedWaiveReason.length === 0) {
      setActionError("Reason is required to waive RFP.");
      return false;
    }

    if (dataMode === "live" && liveWorkflow) {
      const notes = approved
        ? needsRfpDecision && rfpDecision === "waive"
          ? trimmedWaiveReason
          : "Approved by department head."
        : returnNotes;
      const approveOrReturn = () =>
        liveWorkflow.departmentDecision(request.id, approved, notes, needsRfpDecision ? rfpDecision : undefined, companyId);

      if (approved) {
        runApprovalWorkflow(request, approveOrReturn);
      } else {
        void runLiveWorkflow(approveOrReturn, () => setReturnDecision(null));
      }
      return true;
    }

    if (request.department !== user.department) {
      return false;
    }

    setRequests((current) =>
      current.flatMap((item) => {
        if (item.id !== request.id) {
          return [item];
        }

        if (
          isPettyCashWorkflowRequest(item) &&
          item.status === "pending_department_approval" &&
          item.liquidationAmount == null
        ) {
          const pettyCashHistory: TransactionHistory = {
            id: createHistoryId(),
            timestamp: new Date(),
            action: approved ? "approved_by_department_head" : "rejected",
            fromEmployee: user,
            toEmployee: item.custodian,
            amount: item.amount,
            notes: approved
              ? "Department approved the petty cash request. Routed to custodian."
              : returnNotes,
          };

          return [
            {
              ...item,
              status: approved ? "pending_custodian_approval" : "rejected",
              remainingAmount: approved ? item.amount : 0,
              history: [...item.history, pettyCashHistory],
            },
          ];
        }

        if (item.status === "pending_rfp_department_approval") {
          const decisionHistory: TransactionHistory = {
            id: createHistoryId(),
            timestamp: new Date(),
            action: approved ? (rfpDecision === "waive" ? "rfp_waived" : "rfp_created") : "returned",
            fromEmployee: user,
            amount: item.excessAmount,
            notes: approved
              ? rfpDecision === "waive"
                ? trimmedWaiveReason
                : "Department approved RFP creation. Requestor must upload the RFP attachment."
              : returnNotes,
          };

          if (!approved) {
            return [
              {
                ...item,
                status: "pending_liquidation" as const,
                remainingAmount: getReturnedLiquidationAmount(item),
                returnAmount: undefined,
                excessAmount: undefined,
                history: [...item.history, decisionHistory],
              },
            ];
          }

          if (!item.excessAmount || item.excessAmount <= 0) {
            return [
              {
                ...item,
                status: "fully_liquidated" as const,
                history: [...item.history, decisionHistory],
              },
            ];
          }

          return [
            {
              ...item,
              status: rfpDecision === "waive" ? "fully_liquidated" : "pending_rfp_attachment",
              rfpDecision,
              rfpWaiveReason: rfpDecision === "waive" ? trimmedWaiveReason : undefined,
              history: [...item.history, decisionHistory],
            },
          ];
        }

        const amountSpent = item.liquidationAmount ?? 0;
        const liquidationBaseAmount = item.remainingAmount > 0 ? item.remainingAmount : item.amount;
        const returnAmount = Math.max(liquidationBaseAmount - amountSpent, 0);
        const excessAmount = Math.max(amountSpent - liquidationBaseAmount, 0);
        const history: TransactionHistory = {
          id: createHistoryId(),
          timestamp: new Date(),
          action: approved ? "approved_by_department_head" : "returned",
          fromEmployee: user,
          amount: amountSpent,
          notes: approved
            ? "Department approved submitted liquidation."
            : returnNotes,
        };

        if (!approved) {
          return [
            {
              ...item,
              status: "pending_liquidation" as const,
              remainingAmount: getReturnedLiquidationAmount(item),
              returnAmount: undefined,
              excessAmount: undefined,
              history: [...item.history, history],
            },
          ];
        }

        if (excessAmount > 0) {
          const rfpHistory: TransactionHistory = {
            id: createHistoryId(),
            timestamp: new Date(),
            action: rfpDecision === "waive" ? "rfp_waived" : "rfp_created",
            fromEmployee: user,
            amount: excessAmount,
            notes:
              rfpDecision === "waive"
                ? trimmedWaiveReason
                : "Department approved RFP creation. Requestor must upload the RFP attachment.",
          };
          const sentToAccountingHistory: TransactionHistory = {
            id: createHistoryId(),
            timestamp: new Date(),
            action: "sent_to_accounting",
            fromEmployee: user,
            amount: amountSpent,
            notes: "RFP waived. Sent to accounting for closure.",
          };

          return [
            {
              ...item,
              status: rfpDecision === "waive" ? "pending_accounting_review" : "pending_rfp_attachment",
              remainingAmount: 0,
              liquidatedAmount: Math.min(amountSpent, liquidationBaseAmount),
              returnAmount: undefined,
              excessAmount,
              rfpDecision,
              rfpWaiveReason: rfpDecision === "waive" ? trimmedWaiveReason : undefined,
              history: [
                ...item.history,
                history,
                rfpHistory,
                ...(rfpDecision === "waive" ? [sentToAccountingHistory] : []),
              ],
            },
          ];
        }

        if (isPettyCashWorkflowRequest(item)) {
          return [
            {
              ...item,
              status: "pending_custodian_liquidation_review" as const,
              remainingAmount: 0,
              liquidatedAmount: amountSpent,
              returnAmount: returnAmount > 0 ? returnAmount : undefined,
              excessAmount: undefined,
              history: [...item.history, history],
            },
          ];
        }

        const nextStatus = returnAmount > 0 ? "pending_cashier_return" : "pending_accounting_review";

        return [
          {
            ...item,
            status: nextStatus as CashAdvanceRequest["status"],
            remainingAmount: 0,
            liquidatedAmount: Math.min(amountSpent, liquidationBaseAmount),
            returnAmount: returnAmount > 0 ? returnAmount : undefined,
            excessAmount: excessAmount > 0 ? excessAmount : undefined,
            history: [
              ...item.history,
              history,
              {
                id: createHistoryId(),
                timestamp: new Date(),
                action: "sent_to_accounting" as const,
                fromEmployee: user,
                amount: amountSpent,
                notes:
                  excessAmount > 0
                    ? "Department approved the overspend liquidation. Accounting must approve the original cash advance before the excess returns to department for RFP review."
                    : returnAmount > 0
                      ? "Department approved the under-spent liquidation. Cashier must create the acknowledgement receipt and upload the deposit slip before accounting approval."
                      : "Exact liquidation. Sent to accounting for closure.",
              },
            ],
          },
        ];
      }),
    );

    if (!approved) {
      setReturnDecision(null);
    }

    return true;
  };

  const handleAccountingDecision = (
    request: CashAdvanceRequest,
    approved: boolean,
    returnReason?: string,
  ): boolean | void => {
    if (!approved && !returnReason) {
      setActionError("");
      setReturnDecision({ request, reviewer: "accounting" });
      return false;
    }

    const returnNotes = returnReason ? buildReturnNotes("Accounting", returnReason) : "";

    if (dataMode === "live" && liveWorkflow) {
      const notes = approved ? "Approved by accounting." : returnNotes;
      const approveOrReturn = () => liveWorkflow.accountingDecision(request.id, approved, notes);

      if (approved) {
        runApprovalWorkflow(request, approveOrReturn);
      } else {
        void runLiveWorkflow(approveOrReturn, () => setReturnDecision(null));
      }
      return true;
    }

    setRequests((current) =>
      current.map((item) => {
        if (item.id !== request.id) {
          return item;
        }

        const excessAmount = item.excessAmount ?? 0;
        const returnAmount = item.returnAmount ?? 0;
        const history: TransactionHistory = {
          id: createHistoryId(),
          timestamp: new Date(),
          action: approved ? "approved_by_accounting" : "returned",
          fromEmployee: user,
          amount: item.liquidationAmount,
          notes: approved ? "Accounting approved liquidation for closure." : returnNotes,
        };

        if (!approved) {
          if (excessAmount > 0 && item.rfpDecision === "create") {
            return {
              ...item,
              status: "pending_rfp_attachment" as const,
              history: [...item.history, history],
            };
          }

          return {
            ...item,
            status: "pending_liquidation" as const,
            remainingAmount: getReturnedLiquidationAmount(item),
            returnAmount: undefined,
            excessAmount: undefined,
            history: [...item.history, history],
          };
        }

        if (approved && excessAmount > 0) {
          if (item.rfpDecision) {
            return {
              ...item,
              status: "fully_liquidated" as const,
              liquidatedAmount: item.liquidationAmount ?? item.liquidatedAmount,
              remainingAmount: 0,
              history: [...item.history, history],
            };
          }

          return {
            ...item,
            status: "pending_rfp_department_approval" as const,
            liquidatedAmount: item.amount,
            remainingAmount: 0,
            history: [
              ...item.history,
              history,
              {
                id: createHistoryId(),
                timestamp: new Date(),
                action: "sent_to_accounting" as const,
                fromEmployee: user,
                amount: excessAmount,
                notes: "Original request is liquidated. Excess spend now needs department approval for RFP creation.",
              },
            ],
          };
        }

        if (approved && returnAmount > 0 && !item.acknowledgementReceipt) {
          return {
            ...item,
            status: "pending_cashier_return" as const,
            remainingAmount: 0,
            liquidatedAmount: getPendingLiquidationAmount(item) > 0
              ? item.liquidationAmount ?? item.liquidatedAmount
              : item.liquidatedAmount,
            history: [
              ...item.history,
              history,
              {
                id: createHistoryId(),
                timestamp: new Date(),
                action: "return_to_cashier" as const,
                fromEmployee: user,
                toEmployee: cashierUser,
                amount: returnAmount,
                notes: "Accounting approved the under-spent liquidation. Cashier must attach the acknowledgement receipt.",
              },
            ],
          };
        }

        if (approved && returnAmount > 0) {
          return {
            ...item,
            status: "pending_cashier_closure" as const,
            remainingAmount: 0,
            liquidatedAmount: item.liquidationAmount ?? item.liquidatedAmount,
            history: [
              ...item.history,
              history,
              {
                id: createHistoryId(),
                timestamp: new Date(),
                action: "return_to_cashier" as const,
                fromEmployee: user,
                toEmployee: cashierUser,
                amount: returnAmount,
                notes: "Final accounting approval complete. Cashier must close the liquidation.",
              },
            ],
          };
        }

        return {
          ...item,
          status: "fully_liquidated" as const,
          remainingAmount: 0,
          liquidatedAmount: item.liquidationAmount ?? item.liquidatedAmount,
          history: [...item.history, history],
        };
      }),
    );

    if (!approved) {
      setReturnDecision(null);
    }

    return true;
  };

  const handleLiquidate = (
    requestId: string,
    amountSpent: number,
    receiptDetails: CashAdvanceReceiptDetail[],
    pettyCashReceiptDetails: PettyCashReceiptDetail[],
    pettyCashTransportationDetails: PettyCashTransportationDetail[],
    notes: string,
    attachments: File[],
    replaceExistingAttachments: boolean,
  ) => {
    const attachmentNames = attachments.map((file) => file.name);
    const shouldReplaceAttachments = replaceExistingAttachments && attachmentNames.length > 0;
    const attachmentNote =
      attachmentNames.length > 0
        ? ` ${shouldReplaceAttachments ? "Replacement attachments" : "Attachments"}: ${attachmentNames.join(", ")}.`
        : "";
    const receiptNote = receiptDetails.length > 0 ? `Receipt detail rows: ${receiptDetails.length}.` : "";
    const pettyCashDetailNote =
      pettyCashReceiptDetails.length + pettyCashTransportationDetails.length > 0
        ? `Petty cash receipt rows: ${pettyCashReceiptDetails.length}. Transportation rows: ${pettyCashTransportationDetails.length}.`
        : "";
    const baseNotes = [receiptNote, pettyCashDetailNote, notes.trim(), attachmentNote.trim()].filter(Boolean).join(" ");
    const selectedRequest = requests.find((item) => item.id === requestId);
    const shouldClaimLiquidationCustody =
      selectedRequest !== undefined && canClaimRfpLiquidationCustody(selectedRequest, user);
    const shouldAutoApproveDepartment =
      user.role === "department_head" &&
      selectedRequest !== undefined &&
      (selectedRequest.currentOwner.id === user.id || shouldClaimLiquidationCustody);
    const autoApprovalNotes = shouldClaimLiquidationCustody
      ? "Auto-approved by department head after taking full custody."
      : "Auto-approved by department head requestor.";

    if (selectedRequest && getPendingTransfers(selectedRequest).length > 0) {
      setActionError("Liquidation is disabled until all pending transfers are acknowledged or denied.");
      setLiquidateRequest(null);
      return;
    }

    if (
      selectedRequest &&
      isPettyCashWorkflowRequest(selectedRequest) &&
      amountSpent > selectedRequest.remainingAmount
    ) {
      setActionError("Petty cash liquidation cannot exceed the released amount.");
      setLiquidateRequest(null);
      return;
    }

    if (dataMode === "live" && liveWorkflow) {
      void runLiveWorkflow(
        async () => {
          await liveWorkflow.submitLiquidation(
            requestId,
            amountSpent,
            baseNotes.trim(),
            receiptDetails,
            pettyCashReceiptDetails,
            pettyCashTransportationDetails,
            attachments,
            shouldReplaceAttachments,
          );

          if (shouldAutoApproveDepartment) {
            await liveWorkflow.departmentDecision(requestId, true, autoApprovalNotes, "create");
          }
        },
        () => setLiquidateRequest(null),
      );
      return;
    }

    setRequests((current) => {
      const request = current.find((item) => item.id === requestId);
      if (!request) {
        return current;
      }

      return current.map((item) =>
        item.id === requestId
          ? (() => {
              const returnAmount = Math.max(item.remainingAmount - amountSpent, 0);
              const excessAmount = Math.max(amountSpent - item.remainingAmount, 0);
              const liquidatingOwner = shouldClaimLiquidationCustody ? toEmployee(user) : item.currentOwner;
              const liquidationHistory: TransactionHistory = {
                id: createHistoryId(),
                timestamp: new Date(),
                action: "liquidation_submitted" as const,
                fromEmployee: liquidatingOwner,
                amount: amountSpent,
                notes: shouldAutoApproveDepartment
                  ? `${baseNotes} Auto-submitted and department-approved.`
                  : `${baseNotes} Submitted to department approver.`,
              };
              const approvedHistory: TransactionHistory = {
                id: createHistoryId(),
                timestamp: new Date(),
                action: "approved_by_department_head" as const,
                fromEmployee: user,
                amount: amountSpent,
                notes: autoApprovalNotes,
              };

              if (shouldAutoApproveDepartment && excessAmount > 0) {
                return {
                  ...item,
                  currentOwner: liquidatingOwner,
                  status: "pending_rfp_attachment" as const,
                  liquidationAmount: amountSpent,
                  liquidationNotes: baseNotes,
                  attachmentNames:
                    attachmentNames.length > 0
                      ? shouldReplaceAttachments
                        ? attachmentNames
                        : [...(item.attachmentNames ?? []), ...attachmentNames]
                      : item.attachmentNames,
                  receiptDetails,
                  remainingAmount: 0,
                  liquidatedAmount: Math.min(amountSpent, item.remainingAmount),
                  returnAmount: undefined,
                  excessAmount,
                  rfpDecision: "create" as const,
                  rfpWaiveReason: undefined,
                  history: [
                    ...item.history,
                    liquidationHistory,
                    approvedHistory,
                    {
                      id: createHistoryId(),
                      timestamp: new Date(),
                      action: "rfp_created" as const,
                      fromEmployee: user,
                      amount: excessAmount,
                      notes: "Auto-approved RFP creation. Requestor must upload the RFP attachment.",
                    },
                  ],
                };
              }

              if (isPettyCashWorkflowRequest(item)) {
                return {
                  ...item,
                  currentOwner: liquidatingOwner,
                  status: shouldAutoApproveDepartment
                    ? "pending_custodian_liquidation_review" as const
                    : "pending_department_approval" as const,
                  liquidationAmount: amountSpent,
                  liquidationNotes: baseNotes,
                  attachmentNames:
                    attachmentNames.length > 0
                      ? shouldReplaceAttachments
                        ? attachmentNames
                        : [...(item.attachmentNames ?? []), ...attachmentNames]
                      : item.attachmentNames,
                  receiptDetails: [],
                  pettyCashReceiptDetails,
                  pettyCashTransportationDetails,
                  remainingAmount: 0,
                  liquidatedAmount: amountSpent,
                  returnAmount: returnAmount > 0 ? returnAmount : undefined,
                  excessAmount: undefined,
                  history: [
                    ...item.history,
                    liquidationHistory,
                    ...(shouldAutoApproveDepartment ? [approvedHistory] : []),
                  ],
                };
              }

              if (shouldAutoApproveDepartment) {
                const nextStatus = returnAmount > 0 ? "pending_cashier_return" : "pending_accounting_review";

                return {
                  ...item,
                  currentOwner: liquidatingOwner,
                  status: nextStatus as CashAdvanceRequest["status"],
                  liquidationAmount: amountSpent,
                  liquidationNotes: baseNotes,
                  attachmentNames:
                    attachmentNames.length > 0
                      ? shouldReplaceAttachments
                        ? attachmentNames
                        : [...(item.attachmentNames ?? []), ...attachmentNames]
                      : item.attachmentNames,
                  receiptDetails,
                  remainingAmount: 0,
                  liquidatedAmount: Math.min(amountSpent, item.remainingAmount),
                  returnAmount: returnAmount > 0 ? returnAmount : undefined,
                  excessAmount: undefined,
                  history: [
                    ...item.history,
                    liquidationHistory,
                    approvedHistory,
                    {
                      id: createHistoryId(),
                      timestamp: new Date(),
                      action: "sent_to_accounting" as const,
                      fromEmployee: user,
                      amount: amountSpent,
                      notes:
                        returnAmount > 0
                          ? "Auto-approved under-spent liquidation. Cashier must create the acknowledgement receipt and upload the deposit slip before accounting approval."
                          : "Auto-approved exact liquidation. Sent to accounting for closure.",
                    },
                  ],
                };
              }

              return {
                ...item,
                currentOwner: liquidatingOwner,
                status: "pending_department_approval" as const,
                liquidationAmount: amountSpent,
                liquidationNotes: baseNotes,
                attachmentNames:
                  attachmentNames.length > 0
                    ? shouldReplaceAttachments
                      ? attachmentNames
                      : [...(item.attachmentNames ?? []), ...attachmentNames]
                    : item.attachmentNames,
                receiptDetails,
                returnAmount: returnAmount > 0 ? returnAmount : undefined,
                excessAmount: excessAmount > 0 ? excessAmount : undefined,
                history: [...item.history, liquidationHistory],
              };
            })()
          : item,
      );
    });

    setLiquidateRequest(null);
  };

  const handleRfpAttachmentUpload = (requestId: string, notes: string, attachments: File[]) => {
    if (attachments.length === 0) {
      setActionError("RFP attachment is required.");
      return;
    }

    const attachmentNames = attachments.map((file) => file.name);
    const attachmentNote = `RFP attachment: ${attachmentNames.join(", ")}.`;
    const baseNotes = [attachmentNote, notes.trim()].filter(Boolean).join(" ");

    if (dataMode === "live" && liveWorkflow) {
      void runLiveWorkflow(
        () => liveWorkflow.submitRfpAttachment(requestId, baseNotes, attachments),
        () => setRfpAttachmentRequestId(null),
      );
      return;
    }

    setRequests((current) =>
      current.map((item) =>
        item.id === requestId
          ? {
              ...item,
              status: "pending_accounting_review" as const,
              attachmentNames: [...(item.attachmentNames ?? []), ...attachmentNames],
              history: [
                ...item.history,
                {
                  id: createHistoryId(),
                  timestamp: new Date(),
                  action: "rfp_attachment_uploaded" as const,
                  fromEmployee: item.currentOwner,
                  amount: item.excessAmount,
                  notes: baseNotes,
                },
              ],
            }
          : item,
      ),
    );

    setRfpAttachmentRequestId(null);
  };

  const handleTransfer = (
    requestId: string,
    toEmployeeId: string,
    amount: number,
    notes: string,
    transferWholeRequest: boolean,
  ) => {
    const selectedRequest = requests.find((item) => item.id === requestId);
    const toEmployee = users.find(
      (employee) =>
        employee.id === toEmployeeId && employee.role === "department_head",
    );

    if (!selectedRequest) {
      setActionError("Cash advance request was not found.");
      return;
    }

    if (!toEmployee) {
      setActionError("Transfer is only allowed to a department approver.");
      return;
    }

    const belongsToRequestDepartment =
      toEmployee.department.trim().toLocaleLowerCase() === selectedRequest.department.trim().toLocaleLowerCase();
    if (!belongsToRequestDepartment) {
      setActionError("Transfer is only allowed to an employee in the request's department.");
      return;
    }

    if (dataMode === "live" && liveWorkflow) {
      void runLiveWorkflow(
        () => liveWorkflow.transferRequest(requestId, toEmployeeId, amount, transferWholeRequest, notes),
        () => setTransferRequest(null),
      );
      return;
    }

    setRequests((current) => {
      const request = current.find((item) => item.id === requestId);
      if (!request) {
        return current;
      }

      const transferAmount = transferWholeRequest ? request.remainingAmount : amount;
      if (transferAmount <= 0 || transferAmount > request.remainingAmount) {
        setActionError("Transfer amount must be within the available remaining balance.");
        return current;
      }

      return current.map((item) =>
        item.id === requestId
          ? (() => {
              const pendingTransfer: PendingTransfer = {
                id: createTransferId(),
                fromEmployee: item.currentOwner,
                toEmployee,
                amount: transferAmount,
                isWholeRequest: transferWholeRequest,
                requestedAt: new Date(),
                notes,
              };
              const pendingTransfers = [...getPendingTransfers(item), pendingTransfer];

              return {
                ...item,
                remainingAmount: item.remainingAmount - transferAmount,
                pendingTransfer: pendingTransfers[0],
                pendingTransfers,
                history: [
                  ...item.history,
                  {
                    id: createHistoryId(),
                    timestamp: new Date(),
                    action: "transfer_requested" as const,
                    fromEmployee: item.currentOwner,
                    toEmployee,
                    amount: transferAmount,
                    notes:
                      notes ||
                      `${transferWholeRequest ? "Whole available balance" : "Partial"} transfer requested for ${
                        toEmployee.name
                      }.`,
                  },
                ],
              };
            })()
          : item,
      );
    });

    setTransferRequest(null);
  };

  const handleTransferResponse = (request: CashAdvanceRequest, accepted: boolean, transferId?: string) => {
    const pendingTransfer = getPendingTransfers(request).find(
      (transfer) => transfer.toEmployee.id === user.id && (transferId == null || transfer.id === transferId),
    );

    if (!pendingTransfer) {
      return;
    }

    if (dataMode === "live" && liveWorkflow) {
      const notes = accepted ? "Transfer acknowledged by receiver." : "Transfer denied by receiver.";
      void runLiveWorkflow(() => liveWorkflow.respondToTransfer(request.id, pendingTransfer.id, accepted, notes));
      return;
    }

    setRequests((current) => {
      if (!accepted) {
        return current.map((item) =>
          item.id === request.id
            ? (() => {
                const pendingTransfers = getPendingTransfers(item).filter((transfer) => transfer.id !== pendingTransfer.id);

                return {
                  ...item,
                  remainingAmount: item.remainingAmount + pendingTransfer.amount,
                  pendingTransfer: pendingTransfers[0],
                  pendingTransfers,
                  history: [
                    ...item.history,
                    {
                      id: createHistoryId(),
                      timestamp: new Date(),
                      action: "transfer_denied" as const,
                      fromEmployee: user,
                      toEmployee: pendingTransfer.fromEmployee,
                      amount: pendingTransfer.amount,
                      notes: `Transfer denied by ${user.name}. Amount returned to ${pendingTransfer.fromEmployee.name}.`,
                    },
                  ],
                };
              })()
            : item,
        );
      }

      if (pendingTransfer.isWholeRequest) {
        return current.map((item) =>
          item.id === request.id
            ? (() => {
                const pendingTransfers = getPendingTransfers(item).filter((transfer) => transfer.id !== pendingTransfer.id);

                return {
                  ...item,
                  currentOwner: pendingTransfer.toEmployee,
                  department: pendingTransfer.toEmployee.department,
                  remainingAmount: item.remainingAmount + pendingTransfer.amount,
                  pendingTransfer: pendingTransfers[0],
                  pendingTransfers,
                  history: [
                    ...item.history,
                    {
                      id: createHistoryId(),
                      timestamp: new Date(),
                      action: "transfer_acknowledged" as const,
                      fromEmployee: user,
                      toEmployee: pendingTransfer.fromEmployee,
                      amount: pendingTransfer.amount,
                      notes: `Whole request transfer acknowledged by ${user.name}.`,
                    },
                  ],
                };
              })()
            : item,
        );
      }

      const splitRequest: CashAdvanceRequest = {
        id: `${Date.now()}`,
        originalRequestId: request.id,
        requestNumber: `${request.requestNumber}-T`,
        amount: pendingTransfer.amount,
        remainingAmount: pendingTransfer.amount,
        liquidatedAmount: 0,
        purpose: request.purpose,
        sourceSystem: "Cash Advance Transfer",
        createdAt: new Date(),
        status: "pending_liquidation",
        currentOwner: pendingTransfer.toEmployee,
        originalOwner: request.originalOwner,
        department: pendingTransfer.toEmployee.department,
        history: [
          {
            id: createHistoryId(),
            timestamp: new Date(),
            action: "transfer_acknowledged",
            fromEmployee: user,
            toEmployee: pendingTransfer.fromEmployee,
            amount: pendingTransfer.amount,
            notes: `Partial transfer accepted from ${request.requestNumber}.`,
          },
        ],
        dueDate: request.dueDate,
      };

      return [
        ...current.map((item) =>
          item.id === request.id
            ? (() => {
                const pendingTransfers = getPendingTransfers(item).filter((transfer) => transfer.id !== pendingTransfer.id);

                return {
                  ...item,
                  pendingTransfer: pendingTransfers[0],
                  pendingTransfers,
                  history: [
                    ...item.history,
                    {
                      id: createHistoryId(),
                      timestamp: new Date(),
                      action: "transfer_acknowledged" as const,
                      fromEmployee: user,
                      toEmployee: pendingTransfer.fromEmployee,
                      amount: pendingTransfer.amount,
                      notes: `Partial transfer acknowledged by ${user.name}.`,
                    },
                  ],
                };
              })()
            : item,
        ),
        splitRequest,
      ];
    });
  };

  const handleCreateReceipt = (
    requestId: string,
    receiptNumber: string,
    depositSlipAttachment: File | null,
    depositDate: string,
    depositAmount: number,
    depositoryBank: string,
    notes: string,
  ) => {
    const requestForReceipt = requests.find((request) => request.id === requestId);
    const isCustodianReturnReceipt =
      requestForReceipt !== undefined &&
      isPettyCashWorkflowRequest(requestForReceipt) &&
      requestForReceipt.status === "pending_custodian_liquidation_review";

    if (!requestForReceipt) {
      setActionError("Request was not found for acknowledgement receipt.");
      return;
    }

    if (dataMode === "live" && liveWorkflow) {
      if (isCustodianReturnReceipt) {
        if (!liveWorkflow.createCustodianReceipt) {
          setActionError("Custodian acknowledgement receipt is not available in Live Data mode.");
          return;
        }

        void runLiveWorkflow(
          () => liveWorkflow.createCustodianReceipt?.(requestId, receiptNumber, notes) ?? Promise.resolve(),
          () => setReceiptRequestId(null),
        );
        return;
      }

      void runLiveWorkflow(
        () =>
          liveWorkflow.createCashierReceipt(
            requestId,
            receiptNumber,
            depositSlipAttachment,
            depositDate,
            depositAmount,
            depositoryBank,
            notes,
          ),
        () => setReceiptRequestId(null),
      );
      return;
    }

    if (isCustodianReturnReceipt) {
      setRequests((current) =>
        current.map((request) => {
          if (request.id !== requestId || !hasPettyCashReturnAmount(request)) {
            return request;
          }

          const acknowledgedReceipt: AcknowledgementReceipt = {
            receiptNumber,
            requestId: request.id,
            requestNumber: request.requestNumber,
            requestor: request.currentOwner,
            returnAmount: request.returnAmount ?? 0,
            issuedAt: new Date(),
            status: "acknowledged",
            acknowledgedBy: user,
            acknowledgedAt: new Date(),
            notes,
          };

          return {
            ...request,
            acknowledgementReceipt: acknowledgedReceipt,
            history: [
              ...request.history,
              {
                id: createHistoryId(),
                timestamp: new Date(),
                action: "acknowledged" as const,
                fromEmployee: request.currentOwner,
                toEmployee: user,
                amount: request.returnAmount,
                notes:
                  notes ||
                  `Custodian acknowledged returned excess petty cash with acknowledgement receipt ${receiptNumber}.`,
              },
            ],
          };
        }),
      );

      setReceiptRequestId(null);
      return;
    }

    const depositSlipFileName = depositSlipAttachment?.name;
    const hasDepositSlipArAttachment = Boolean(depositSlipFileName);
    const parsedDepositDate = depositDate ? new Date(`${depositDate}T00:00:00`) : undefined;
    const safeDepositDate =
      parsedDepositDate && !Number.isNaN(parsedDepositDate.getTime()) ? parsedDepositDate : undefined;
    const safeDepositoryBank = depositoryBank.trim();

    setRequests((current) =>
      current.map((request) => {
        if (request.id !== requestId || request.status !== "pending_cashier_return") {
          return request;
        }

        const acknowledgedReceipt: AcknowledgementReceipt = {
          receiptNumber,
          requestId: request.id,
          requestNumber: request.requestNumber,
          requestor: request.currentOwner,
          returnAmount: request.returnAmount ?? 0,
          issuedAt: new Date(),
          status: hasDepositSlipArAttachment ? "acknowledged" : "pending",
          acknowledgedBy: hasDepositSlipArAttachment ? cashierUser : undefined,
          acknowledgedAt: hasDepositSlipArAttachment ? new Date() : undefined,
          depositSlipFileName: depositSlipFileName || undefined,
          depositSlipContentType: depositSlipAttachment?.type || undefined,
          depositSlipFileSize: depositSlipAttachment?.size,
          depositDate: safeDepositDate,
          depositAmount: depositAmount > 0 ? depositAmount : undefined,
          depositoryBank: safeDepositoryBank || undefined,
          notes,
        };

        return {
          ...request,
          status: hasDepositSlipArAttachment ? "pending_accounting_review" as const : "pending_cashier_return" as const,
          liquidatedAmount: hasDepositSlipArAttachment
            ? Math.min(
                request.amount,
                (request.liquidationAmount ?? request.liquidatedAmount) + (request.returnAmount ?? 0),
              )
            : request.liquidatedAmount,
          acknowledgementReceipt: acknowledgedReceipt,
          history: [
            ...request.history,
            {
              id: createHistoryId(),
              timestamp: new Date(),
              action: "acknowledged" as const,
              fromEmployee: request.currentOwner,
              toEmployee: cashierUser,
              amount: request.returnAmount,
              notes: hasDepositSlipArAttachment
                ? `Cashier uploaded Deposit Slip/AR attachment ${depositSlipFileName}. Sent to accounting.${notes ? ` ${notes}` : ""}`
                : `Cashier saved acknowledgement receipt ${receiptNumber} as draft. Deposit Slip/AR attachment pending.${notes ? ` ${notes}` : ""}`,
            },
          ],
        };
      }),
    );

    setReceiptRequestId(null);
  };

  const handleCashierCloseLiquidation = (request: CashAdvanceRequest) => {
    const notes = "Cashier closed liquidation after final accounting approval.";

    if (dataMode === "live" && liveWorkflow) {
      void runLiveWorkflow(() => liveWorkflow.closeCashierLiquidation(request.id, notes));
      return;
    }

    setRequests((current) =>
      current.map((item) =>
        item.id === request.id && item.status === "pending_cashier_closure"
          ? {
              ...item,
              status: "fully_liquidated" as const,
              remainingAmount: 0,
              history: [
                ...item.history,
                {
                  id: createHistoryId(),
                  timestamp: new Date(),
                  action: "fully_liquidated" as const,
                  fromEmployee: cashierUser,
                  amount: item.returnAmount,
                  notes,
                },
              ],
            }
          : item,
      ),
    );
  };

  const handleCustodianDecision = (request: CashAdvanceRequest, approved: boolean, returnedAmount?: number) => {
    if (isSyncing) return;
    const requiresCashReturn = request.requestType === "petty_cash_advance" && hasPettyCashReturnAmount(request);
    if (approved && requiresCashReturn && returnedAmount === undefined) {
      setActionError("");
      setCustodianReturnRequest(request);
      return;
    }
    if (approved && requiresCashReturn && (!Number.isFinite(returnedAmount) || Math.abs((returnedAmount ?? 0) - (request.returnAmount ?? 0)) >= 0.005)) {
      setActionError("Cash received must match the expected cash return.");
      return;
    }
    const isInitialCustodianApproval = request.status === "pending_custodian_approval";
    const isReimbursement = request.requestType === "petty_cash";
    const notes =
      isInitialCustodianApproval
        ? approved
          ? isReimbursement
            ? "Custodian approved the petty cash reimbursement."
            : "Custodian approved and released petty cash advance."
          : "Custodian rejected the petty cash request."
        : approved
          ? "Custodian approved the petty cash liquidation."
          : "Custodian returned the petty cash liquidation for correction.";

    if (approved && needsPettyCashReturnAcknowledgement(request)) {
      setActionError("Create the acknowledgement receipt before approving this petty cash liquidation.");
      return;
    }

    const shouldPrintLiquidationAcknowledgement = shouldPrintCustodianLiquidationAcknowledgement(request, approved);
    const liquidationAcknowledgementPrintWindow = shouldPrintLiquidationAcknowledgement
      ? openAcknowledgementReceiptPrintWindow()
      : null;

    if (dataMode === "live" && liveWorkflow?.custodianDecision) {
      const approveOrReject = () =>
        liveWorkflow.custodianDecision?.(request.id, user.id, approved, notes, returnedAmount) ?? Promise.resolve();
      const onSuccess = () => {
        setCustodianReturnRequest(null);
        if (shouldPrintLiquidationAcknowledgement) {
          handlePrintCustodianLiquidationAcknowledgement(request, liquidationAcknowledgementPrintWindow);
        }
      };

      if (approved) {
        runApprovalWorkflow(request, approveOrReject, onSuccess);
      } else {
        void runLiveWorkflow(approveOrReject, onSuccess);
      }
      return;
    }

    setRequests((current) =>
      current.flatMap((item) => {
        if (item.id !== request.id || item.custodian?.id !== user.id || !isPettyCashWorkflowRequest(item)) {
          return [item];
        }

        if (item.status === "pending_custodian_approval") {
          if (item.requestType === "petty_cash") {
            const actualSpentAmount = getPettyCashActualSpentAmount(
              item.pettyCashReceiptDetails,
              item.pettyCashTransportationDetails,
            );
            const excessAmount = approved ? Math.max(actualSpentAmount - item.amount, 0) : 0;
            const splitDetails =
              excessAmount > 0
                ? splitPettyCashDetailsByAmount(
                    item.pettyCashReceiptDetails ?? [],
                    item.pettyCashTransportationDetails ?? [],
                    item.amount,
                  )
                : undefined;
            const excessRequest =
              splitDetails && excessAmount > 0
                ? createPettyCashExcessRequest(
                    item,
                    current,
                    excessAmount,
                    splitDetails.excessReceiptDetails,
                    splitDetails.excessTransportationDetails,
                  )
                : undefined;
            const reimbursementHistory = approved
              ? [
                  ...item.history,
                  {
                    id: createHistoryId(),
                    timestamp: new Date(),
                    action: "approved_by_custodian" as const,
                    fromEmployee: user,
                    toEmployee: item.originalOwner,
                    amount: item.amount,
                    notes,
                  },
                  {
                    id: createHistoryId(),
                    timestamp: new Date(),
                    action: "fully_liquidated" as const,
                    fromEmployee: user,
                    amount: item.amount,
                    notes: "Petty cash reimbursement closed by custodian.",
                  },
                  ...(excessRequest
                    ? [
                        {
                          id: createHistoryId(),
                          timestamp: new Date(),
                          action: "excess_created" as const,
                          fromEmployee: user,
                          toEmployee: item.originalOwner,
                          amount: excessAmount,
                          notes: `Created ${excessRequest.requestNumber} for the excess petty cash reimbursement.`,
                        },
                      ]
                    : []),
                ]
              : [
                  ...item.history,
                  {
                    id: createHistoryId(),
                    timestamp: new Date(),
                    action: "rejected" as const,
                    fromEmployee: user,
                    toEmployee: item.originalOwner,
                    amount: item.amount,
                    notes,
                  },
                ];
            const updatedRequest: CashAdvanceRequest = {
              ...item,
              status: approved ? "fully_liquidated" as const : "rejected" as const,
              currentOwner: item.originalOwner,
              remainingAmount: 0,
              liquidatedAmount: approved ? item.amount : item.liquidatedAmount,
              liquidationAmount: approved ? item.amount : item.liquidationAmount,
              pettyCashReceiptDetails: splitDetails?.baseReceiptDetails ?? item.pettyCashReceiptDetails,
              pettyCashTransportationDetails:
                splitDetails?.baseTransportationDetails ?? item.pettyCashTransportationDetails,
              returnAmount: undefined,
              excessAmount: excessRequest ? excessAmount : undefined,
              history: reimbursementHistory,
            };

            return excessRequest ? [excessRequest, updatedRequest] : [updatedRequest];
          }

          return [
            {
              ...item,
              status: approved ? "pending_liquidation" as const : "rejected" as const,
              currentOwner: item.originalOwner,
              remainingAmount: approved ? item.amount : 0,
              history: [
                ...item.history,
                {
                  id: createHistoryId(),
                  timestamp: new Date(),
                  action: approved ? "petty_cash_released" as const : "rejected" as const,
                  fromEmployee: user,
                  toEmployee: item.originalOwner,
                  amount: item.amount,
                  notes,
                },
              ],
            },
          ];
        }

        if (item.status === "pending_custodian_liquidation_review") {
          if (!approved) {
            return [
              {
                ...item,
                status: "pending_liquidation" as const,
                remainingAmount: getReturnedLiquidationAmount(item),
                returnAmount: undefined,
                excessAmount: undefined,
                history: [
                  ...item.history,
                  {
                    id: createHistoryId(),
                    timestamp: new Date(),
                    action: "returned" as const,
                    fromEmployee: user,
                    toEmployee: item.originalOwner,
                    amount: item.liquidationAmount,
                    notes,
                  },
                ],
              },
            ];
          }

          return [
            {
              ...item,
              status: "fully_liquidated" as const,
              remainingAmount: 0,
              liquidatedAmount: item.liquidationAmount ?? item.liquidatedAmount,
              history: [
                ...item.history,
                ...(returnedAmount !== undefined ? [{ id: createHistoryId(), timestamp: new Date(), action: "acknowledged" as const, fromEmployee: user, amount: returnedAmount, notes: "Custodian received the unspent petty cash advance balance." }] : []),
                {
                  id: createHistoryId(),
                  timestamp: new Date(),
                  action: "approved_by_custodian" as const,
                  fromEmployee: user,
                  toEmployee: item.originalOwner,
                  amount: item.liquidationAmount,
                  notes,
                },
                {
                  id: createHistoryId(),
                  timestamp: new Date(),
                  action: "fully_liquidated" as const,
                  fromEmployee: user,
                  amount: item.liquidationAmount,
                  notes: "Petty cash liquidation closed by custodian.",
                },
              ],
            },
          ];
        }

        return [item];
      }),
    );

    setCustodianReturnRequest(null);
    if (shouldPrintLiquidationAcknowledgement) {
      handlePrintCustodianLiquidationAcknowledgement(request, liquidationAcknowledgementPrintWindow);
    }
  };

  const canDecideDetailsRequest =
    detailsRequest !== null &&
    ((user.role === "department_head" &&
      detailsRequest.department === user.department &&
      (detailsRequest.status === "pending_department_approval" ||
        detailsRequest.status === "pending_rfp_department_approval")) ||
      (user.role === "accounting" && detailsRequest.status === "pending_accounting_review") ||
      (user.role === "custodian" &&
        detailsRequest.custodian?.id === user.id &&
        (detailsRequest.status === "pending_custodian_approval" ||
          detailsRequest.status === "pending_custodian_liquidation_review")));
  const canCloseDetailsRequest =
    detailsRequest !== null && user.role === "cashier" && detailsRequest.status === "pending_cashier_closure";
  const canRespondToDetailsTransfer =
    detailsRequest !== null && getPendingTransfers(detailsRequest).some((transfer) => transfer.toEmployee.id === user.id);
  const detailsRequestHasPendingTransfers = detailsRequest !== null && getPendingTransfers(detailsRequest).length > 0;
  const canUseDetailsOwnerActions =
    detailsRequest !== null &&
    detailsRequest.currentOwner.id === user.id &&
    detailsRequest.remainingAmount > 0 &&
    ["pending_liquidation", "partially_liquidated"].includes(detailsRequest.status);
  const canClaimDetailsRfpLiquidationCustody =
    detailsRequest !== null && canClaimRfpLiquidationCustody(detailsRequest, user);
  const canUploadRfpDetailsRequest =
    detailsRequest !== null &&
    detailsRequest.currentOwner.id === user.id &&
    detailsRequest.status === "pending_rfp_attachment";
  const canLiquidateDetailsRequest =
    (canUseDetailsOwnerActions || canClaimDetailsRfpLiquidationCustody) && !detailsRequestHasPendingTransfers;
  const canTransferDetailsRequest = canUseDetailsOwnerActions;
  const detailsNeedsCustodianReturnAcknowledgement =
    detailsRequest !== null &&
    user.role === "custodian" &&
    detailsRequest.custodian?.id === user.id &&
    needsPettyCashReturnAcknowledgement(detailsRequest);

  const approveDetailsRequest = (request: CashAdvanceRequest, rfpDecision?: RfpDecision, waiveReason?: string, companyId?: number) => {
    if (user.role === "department_head") {
      handleDepartmentDecision(request, true, undefined, rfpDecision, waiveReason, companyId);
      return;
    }

    if (user.role === "accounting") {
      handleAccountingDecision(request, true);
      return;
    }

    if (user.role === "cashier") {
      handleCashierCloseLiquidation(request);
      return;
    }

    if (user.role === "custodian") {
      handleCustodianDecision(request, true);
    }
  };

  const rejectDetailsRequest = (request: CashAdvanceRequest) => {
    if (user.role === "department_head") {
      handleDepartmentDecision(request, false);
      return;
    }

    if (user.role === "accounting") {
      handleAccountingDecision(request, false);
      return;
    }

    if (user.role === "custodian") {
      handleCustodianDecision(request, false);
    }
  };

  return (
    <AppShell
      user={user}
      dataMode={dataMode}
      tabs={tabs}
      activeTab={activeTab}
      tabPendingCounts={tabPendingCounts}
      onTabChange={setActiveTab}
      headerNotification={
        <PrintNotificationStash
          requests={printableRequests}
          pendingTransferAcknowledgements={pendingTransferAcknowledgements}
          pendingReceiptAcknowledgements={pendingReceiptAcknowledgements}
          onPrint={handlePrintRequest}
          onOpenDetails={(request) => setDetailsRequestId(request.id)}
          onOpenAcknowledgement={(request) => setDetailsRequestId(request.id)}
          onCreateReceipt={handleCreateAcknowledgementReceipt}
        />
      }
      onLogout={onLogout}
    >
      {(actionError || isSyncing) && (
        <div className="mb-6 rounded-lg border border-[#d9e1e8] bg-white px-4 py-3 text-sm font-semibold text-[#17243f] shadow-sm">
          {isSyncing ? "Syncing with FundManagementAPI..." : actionError}
        </div>
      )}
      {activeTab === "dashboard" && (
        <DashboardOverview
          user={user}
          metrics={metrics}
          requests={dashboardRequests}
          approvalRequests={user.role === "department_head" ? departmentQueue : undefined}
          onOpenHistory={setHistoryRequest}
          onOpenDetails={(request) => setDetailsRequestId(request.id)}
          onOpenCashier={() => setActiveTab("cashier")}
          onPrint={handlePrintRequest}
        />
      )}

      {activeTab === "my-requests" && (
        <section>
          <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h2 className="text-xl font-bold text-[#17243f]">Pending action</h2>
              <p className="mt-1 text-sm text-[#5c6b7a]">Cash advances assigned to you or available for custody.</p>
            </div>
            {user.role === "requestor" && (
              <button
                type="button"
                onClick={() => setIsPettyCashRequestOpen(true)}
                className="rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
              >
                New Petty Cash
              </button>
            )}
          </div>
          <div className="mt-6 grid gap-5 md:grid-cols-2 xl:grid-cols-3">
            {myPendingLiquidationRequests.map((request) => (
              <RequestCard
                key={request.id}
                request={request}
                onOpenDetails={(request) => setDetailsRequestId(request.id)}
              />
            ))}
          </div>
          {myPendingLiquidationRequests.length === 0 && (
            <div className="mt-6 rounded-lg border border-dashed border-[#b9c8d4] bg-white p-12 text-center text-sm text-[#5c6b7a]">
              No pending requests are assigned to you.
            </div>
          )}
        </section>
      )}

      {activeTab === "department-review" && (
        <ApprovalQueue
          title="Department Review"
          description="For your approval."
          requests={departmentQueue}
          approveLabel="Approve"
          rejectLabel="Return"
          emptyMessage="No liquidation or RFP requests are waiting for department approval."
          isLiveMode={dataMode === "live"}
          onApprove={(request, rfpDecision, waiveReason, companyId) =>
            handleDepartmentDecision(request, true, undefined, rfpDecision, waiveReason, companyId)
          }
          onReject={(request) => handleDepartmentDecision(request, false)}
          onHistory={setHistoryRequest}
          onOpenDetails={(request) => setDetailsRequestId(request.id)}
        />
      )}

      {activeTab === "accounting" && (
        <ApprovalQueue
          title="For Accounting Review"
          description="Review and process pending requests awaiting accounting approval."
          requests={accountingQueue}
          approveLabel="Approve"
          rejectLabel="Return"
          emptyMessage="No pending request."
          onApprove={(request) => handleAccountingDecision(request, true)}
          onReject={(request) => handleAccountingDecision(request, false)}
          onHistory={setHistoryRequest}
          onOpenDetails={(request) => setDetailsRequestId(request.id)}
        />
      )}

      {activeTab === "approval-history" && (
        <ApprovalHistoryTable
          user={user}
          requests={approvalHistoryRequests}
          onHistory={setHistoryRequest}
          onOpenDetails={(request) => setDetailsRequestId(request.id)}
          onGenerateAccountingReport={
            dataMode === "live" && user.role === "accounting" ? handleGenerateAccountingReport : undefined
          }
        />
      )}

      {activeTab === "all-requests" && (
        <section>
          <div className="mb-6 flex items-end justify-between gap-4">
            <div>
              <h2 className="text-xl font-bold text-[#17243f]">All Visible Requests</h2>
              <p className="mt-1 text-sm text-[#5c6b7a]">
                {user.role === "admin" ? "All requests across the system." : "This list is limited by your role."}
              </p>
            </div>
            <p className="text-sm font-semibold text-[#5c6b7a]">{visibleRequests.length} total</p>
          </div>
          <RequestTable
            requests={visibleRequests}
            emptyMessage="No visible requests."
            onHistory={setHistoryRequest}
            onOpenDetails={(request) => setDetailsRequestId(request.id)}
            onPrint={handlePrintRequest}
          />
        </section>
      )}

      {activeTab === "cashier" && (
        <CashierPanel
          requests={requests}
          onCreateReceipt={handleCreateAcknowledgementReceipt}
          onCloseLiquidation={handleCashierCloseLiquidation}
          onViewReceipt={(receipt, request) => setReceiptView({ receipt, request })}
          onOpenDetails={(request) => setDetailsRequestId(request.id)}
        />
      )}

      {activeTab === "custodian" && (
        <div className="space-y-6">
          <DashboardCharts
            requests={custodianChartRequests}
            pendingLiquidationCount={custodianLiquidationReviewCount}
            approvalQueueCount={custodianApprovalCount}
            pendingLiquidationLabel="Liquidation Review"
            approvalQueueLabel="Custodian Approval"
          />
          <CustodianPanel
            fundSummary={displayedCustodianFund}
            requests={custodianPanelRequests}
            onApprove={(request) => handleCustodianDecision(request, true)}
            onReject={(request) => handleCustodianDecision(request, false)}
            onCreateReceipt={handleCreateAcknowledgementReceipt}
            onViewReceipt={(receipt, request) => setReceiptView({ receipt, request })}
            onOpenDetails={(request) => setDetailsRequestId(request.id)}
            onReplenish={handleCreatePettyCashReplenishment}
            onSubmitReplenishmentCv={handleSubmitPettyCashReplenishmentCv}
          />
        </div>
      )}

      {activeTab === "admin" && (
        <AdminPanel
          users={users}
          custodianFunds={custodianFunds}
          departmentCustodians={departmentCustodians}
          isLiveMode={dataMode === "live"}
          isSubmitting={isSyncing}
          onCreateUser={handleAdminCreateUser}
          onUpdateUser={handleAdminUpdateUser}
          onUpdateCustodianFund={handleAdminUpdateCustodianFund}
          onAssignDepartmentCustodian={handleAdminAssignDepartmentCustodian}
        />
      )}

      {custodianReturnRequest && (
        <CustodianReturnModal key={custodianReturnRequest.id} request={custodianReturnRequest} isSubmitting={isSyncing} errorMessage={actionError}
          onClose={() => { if (!isSyncing) setCustodianReturnRequest(null); }}
          onSubmit={(amount) => handleCustodianDecision(custodianReturnRequest, true, amount)} />
      )}
      {isPettyCashRequestOpen && (
        <PettyCashRequestModal
          isSubmitting={isSyncing}
          requestor={user}
          custodianFunds={departmentCustodianFunds}
          onClose={() => setIsPettyCashRequestOpen(false)}
          onSubmit={handleCreatePettyCashRequest}
        />
      )}

      {liquidateRequest && (
        <LiquidateModal
          request={liquidateRequest}
          onClose={() => setLiquidateRequest(null)}
          isSubmitting={isSyncing}
          onLiquidate={handleLiquidate}
        />
      )}

      {transferRequest && (
        <TransferModal
          request={transferRequest}
          currentUser={user}
          employees={users}
          isSubmitting={isSyncing}
          onClose={() => setTransferRequest(null)}
          onTransfer={handleTransfer}
        />
      )}

      {rfpAttachmentRequest && (
        <RfpAttachmentModal
          request={rfpAttachmentRequest}
          onClose={() => setRfpAttachmentRequestId(null)}
          onSubmit={handleRfpAttachmentUpload}
        />
      )}

      {historyRequest && (
        <HistoryModal
          request={historyRequest}
          onClose={() => setHistoryRequest(null)}
          onViewReceipt={(receipt) => setReceiptView({ receipt, request: historyRequest })}
        />
      )}

      {detailsRequest && (
        <RequestDetailsModal
          isLiveMode={dataMode === "live"}
          request={detailsRequest}
          currentUserRole={user.role}
          users={users}
          onClose={() => setDetailsRequestId(null)}
          approveLabel={
            canRespondToDetailsTransfer
              ? "Acknowledge Transfer"
                : canCloseDetailsRequest
                ? "Close Liquidation"
                : user.role === "custodian" && detailsRequest.status === "pending_custodian_approval"
                  ? detailsRequest.requestType === "petty_cash"
                    ? "Approve Reimbursement"
                    : "Approve Release"
                  : user.role === "custodian" && detailsRequest.status === "pending_custodian_liquidation_review"
                    ? "Approve Liquidation"
                    : "Approve"
          }
          rejectLabel={
            canRespondToDetailsTransfer
              ? "Deny Transfer"
              : user.role === "custodian" && detailsRequest.status === "pending_custodian_approval"
                ? "Reject"
                : "Return"
          }
          onApprove={
            canRespondToDetailsTransfer
              ? (request) => handleTransferResponse(request, true)
              : (canDecideDetailsRequest && !detailsNeedsCustodianReturnAcknowledgement) || canCloseDetailsRequest
                ? approveDetailsRequest
                : undefined
          }
          onReject={
            canRespondToDetailsTransfer
              ? (request) => handleTransferResponse(request, false)
              : canDecideDetailsRequest
                ? rejectDetailsRequest
                : undefined
          }
          liquidateLabel={canClaimDetailsRfpLiquidationCustody ? "Get Full Custody & Liquidate" : "Liquidate"}
          onLiquidate={canLiquidateDetailsRequest ? setLiquidateRequest : undefined}
          onUploadRfp={canUploadRfpDetailsRequest ? (request) => setRfpAttachmentRequestId(request.id) : undefined}
          onTransfer={canTransferDetailsRequest ? setTransferRequest : undefined}
          onCreateReceipt={detailsNeedsCustodianReturnAcknowledgement ? handleCreateAcknowledgementReceipt : undefined}
          onPrint={handlePrintRequest}
        />
      )}

      {returnDecision && (
        <ReturnReasonModal
          request={returnDecision.request}
          reviewerLabel={returnDecision.reviewer === "department" ? "Department" : "Accounting"}
          isSubmitting={isSyncing}
          errorMessage={actionError}
          onClose={() => setReturnDecision(null)}
          onSubmit={(reason) => {
            if (returnDecision.reviewer === "department") {
              handleDepartmentDecision(returnDecision.request, false, reason);
              return;
            }

            handleAccountingDecision(returnDecision.request, false, reason);
          }}
        />
      )}

      {receiptNumberRequest && (
        <ReceiptNumberModal key={receiptNumberRequest.id}
          loadNumber={dataMode === "live" ? fetchApiReceiptDocumentNumber : undefined}
          onClose={() => setReceiptNumberRequest(null)} onPrint={handlePrintNewReceipt} />
      )}

      {receiptRequest && (
        <CashierReceiptModal
          request={receiptRequest}
          initialReceiptNumber={printedReceiptNumber}
          variant={isCustodianReceiptRequest ? "custodian" : "cashier"}
          onClose={() => setReceiptRequestId(null)}
          onSubmit={handleCreateReceipt}
        />
      )}

      {receiptView && (
        <AcknowledgementReceiptModal
          receipt={receiptView.receipt}
          request={receiptView.request}
          onClose={() => setReceiptView(null)}
          onPrint={() => handlePrintAcknowledgementReceipt(receiptView.request, receiptView.receipt)}
        />
      )}

      {approvingRequestNumber && (
        <div
          className="fixed inset-0 z-[80] flex items-center justify-center bg-black/60 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="approval-processing-title"
        >
          <div className="w-full max-w-sm rounded-lg bg-white px-6 py-8 text-center shadow-xl">
            <div
              className="mx-auto h-10 w-10 animate-spin rounded-full border-4 border-[#d9e1e8] border-t-[#0bb7a5]"
              aria-hidden="true"
            />
            <h3 id="approval-processing-title" className="mt-5 text-lg font-bold text-[#17243f]">
              Processing approval
            </h3>
            <p className="mt-2 text-sm text-[#5c6b7a]">
              Approving {approvingRequestNumber}. Please wait until processing is complete.
            </p>
          </div>
        </div>
      )}
    </AppShell>
  );
}
