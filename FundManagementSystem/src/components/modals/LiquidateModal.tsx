import { useEffect, useState } from "react";
import {
  fetchApiBusinessPartners,
  fetchApiCompanies,
  fetchApiExpenseTypes,
  fetchApiProfitCenters,
  fetchApiProjects,
} from "../../services/fundManagementApi";
import { isPettyCashWorkflowRequest, isRfpSourcedCashAdvance } from "../../pettyCash";
import { getAcknowledgedTransferAmount, getTransferAllocationRows } from "../../transferAllocation";
import type {
  BusinessPartner,
  CashAdvanceReceiptDetail,
  CashAdvanceRequest,
  CompanyReference,
  ExpenseTypeReference,
  PettyCashReceiptDetail,
  PettyCashTransportationDetail,
  ProfitCenterReference,
  ProjectReference,
} from "../../types/CashAdvance";

interface LiquidateModalProps {
  request: CashAdvanceRequest;
  onClose: () => void;
  isSubmitting?: boolean;
  onLiquidate: (
    requestId: string,
    amountSpent: number,
    receiptDetails: CashAdvanceReceiptDetail[],
    pettyCashReceiptDetails: PettyCashReceiptDetail[],
    pettyCashTransportationDetails: PettyCashTransportationDetail[],
    notes: string,
    attachments: File[],
    replaceExistingAttachments: boolean,
  ) => void;
}

interface ReceiptDetailRow {
  id: string;
  vendorCode: string;
  vendor: string;
  description: string;
  projectCode: string;
  project: string;
  profitCenterCode: string;
  profitCenter: string;
  amount: string;
  invoiceRef: string;
  expenseTypeCode: string;
  expenseType: string;
}

interface PettyCashReceiptRow {
  id: string;
  orNumber: string;
  company: string;
  tin: string;
  address: string;
  natureOfExpenseCode: string;
  natureOfExpense: string;
  costCenterCode: string;
  costCenter: string;
  amount: string;
  orDate: string;
}

interface PettyCashTransportationRow {
  id: string;
  description: string;
  from: string;
  to: string;
  transactionDate: string;
  amount: string;
}

type ReceiptDetailField = Exclude<
  keyof ReceiptDetailRow,
  | "id"
  | "vendorCode"
  | "vendor"
  | "projectCode"
  | "project"
  | "profitCenterCode"
  | "profitCenter"
  | "expenseTypeCode"
  | "expenseType"
>;

type PettyCashReceiptField = Exclude<keyof PettyCashReceiptRow, "id">;
type PettyCashTransportationField = Exclude<keyof PettyCashTransportationRow, "id">;

const createReceiptDetailRow = (): ReceiptDetailRow => ({
  id: `receipt-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  vendorCode: "",
  vendor: "",
  description: "",
  projectCode: "",
  project: "",
  profitCenterCode: "",
  profitCenter: "",
  amount: "",
  invoiceRef: "",
  expenseTypeCode: "",
  expenseType: "",
});

const createPettyCashReceiptRow = (): PettyCashReceiptRow => ({
  id: `pc-receipt-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  orNumber: "",
  company: "",
  tin: "",
  address: "",
  natureOfExpenseCode: "",
  natureOfExpense: "",
  costCenterCode: "",
  costCenter: "",
  amount: "",
  orDate: "",
});

const createPettyCashTransportationRow = (): PettyCashTransportationRow => ({
  id: `pc-transport-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  description: "",
  from: "",
  to: "",
  transactionDate: "",
  amount: "",
});

const toReceiptDetailRow = (detail: CashAdvanceReceiptDetail): ReceiptDetailRow => ({
  id: detail.id || `receipt-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  vendorCode: detail.vendorCode ?? detail.vendor,
  vendor: detail.vendor,
  description: detail.description,
  projectCode: detail.projectCode ?? detail.project,
  project: detail.project,
  profitCenterCode: detail.profitCenterCode ?? detail.profitCenter,
  profitCenter: detail.profitCenter,
  amount: detail.amount > 0 ? String(detail.amount) : "",
  invoiceRef: detail.invoiceRef,
  expenseTypeCode: detail.expenseTypeCode ?? detail.expenseType,
  expenseType: detail.expenseType,
});

const toPettyCashReceiptRow = (detail: PettyCashReceiptDetail): PettyCashReceiptRow => ({
  id: detail.id || `pc-receipt-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  orNumber: detail.orNumber,
  company: detail.company,
  tin: detail.tin,
  address: detail.address,
  natureOfExpenseCode: detail.natureOfExpenseCode ?? detail.natureOfExpense,
  natureOfExpense: detail.natureOfExpense,
  costCenterCode: detail.costCenterCode ?? detail.costCenter,
  costCenter: detail.costCenter,
  amount: detail.amount > 0 ? String(detail.amount) : "",
  orDate: detail.orDate,
});

const toPettyCashTransportationRow = (
  detail: PettyCashTransportationDetail,
): PettyCashTransportationRow => ({
  id: detail.id || `pc-transport-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  description: detail.description,
  from: detail.from,
  to: detail.to,
  transactionDate: detail.transactionDate,
  amount: detail.amount > 0 ? String(detail.amount) : "",
});

const createInitialReceiptRows = (request: CashAdvanceRequest): ReceiptDetailRow[] =>
  request.receiptDetails && request.receiptDetails.length > 0
    ? request.receiptDetails.map(toReceiptDetailRow)
    : [createReceiptDetailRow()];

const createInitialPettyCashReceiptRows = (request: CashAdvanceRequest): PettyCashReceiptRow[] =>
  request.pettyCashReceiptDetails && request.pettyCashReceiptDetails.length > 0
    ? request.pettyCashReceiptDetails.map(toPettyCashReceiptRow)
    : [createPettyCashReceiptRow()];

const createInitialPettyCashTransportationRows = (
  request: CashAdvanceRequest,
): PettyCashTransportationRow[] =>
  request.pettyCashTransportationDetails && request.pettyCashTransportationDetails.length > 0
    ? request.pettyCashTransportationDetails.map(toPettyCashTransportationRow)
    : [];

const getCompanyOptionValue = (company: CompanyReference) =>
  company.id === undefined ? company.name : String(company.id);

const getReceiptAmount = (row: ReceiptDetailRow) => {
  const amount = Number(row.amount);
  return Number.isFinite(amount) ? amount : 0;
};

const getPettyCashRowAmount = (amountText: string) => {
  const amount = Number(amountText);
  return Number.isFinite(amount) ? amount : 0;
};

const formatCurrency = (amount: number) =>
  `PHP ${amount.toLocaleString("en-PH", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const isReceiptRowComplete = (row: ReceiptDetailRow) =>
  row.vendorCode.trim().length > 0 &&
  row.vendor.trim().length > 0 &&
  row.description.trim().length > 0 &&
  row.projectCode.trim().length > 0 &&
  row.project.trim().length > 0 &&
  row.profitCenterCode.trim().length > 0 &&
  row.profitCenter.trim().length > 0 &&
  getReceiptAmount(row) > 0 &&
  row.invoiceRef.trim().length > 0 &&
  row.expenseTypeCode.trim().length > 0 &&
  row.expenseType.trim().length > 0;

const isPettyCashReceiptRowBlank = (row: PettyCashReceiptRow) =>
  row.orNumber.trim().length === 0 &&
  row.company.trim().length === 0 &&
  row.tin.trim().length === 0 &&
  row.address.trim().length === 0 &&
  row.natureOfExpenseCode.trim().length === 0 &&
  row.natureOfExpense.trim().length === 0 &&
  row.costCenterCode.trim().length === 0 &&
  row.costCenter.trim().length === 0 &&
  row.amount.trim().length === 0 &&
  row.orDate.trim().length === 0;

const isPettyCashReceiptRowComplete = (row: PettyCashReceiptRow) =>
  row.orNumber.trim().length > 0 &&
  row.company.trim().length > 0 &&
  row.tin.trim().length > 0 &&
  row.address.trim().length > 0 &&
  row.natureOfExpenseCode.trim().length > 0 &&
  row.natureOfExpense.trim().length > 0 &&
  row.costCenterCode.trim().length > 0 &&
  row.costCenter.trim().length > 0 &&
  getPettyCashRowAmount(row.amount) > 0 &&
  row.orDate.trim().length > 0;

const isPettyCashTransportationRowBlank = (row: PettyCashTransportationRow) =>
  row.description.trim().length === 0 &&
  row.from.trim().length === 0 &&
  row.to.trim().length === 0 &&
  row.transactionDate.trim().length === 0 &&
  row.amount.trim().length === 0;

const isPettyCashTransportationRowComplete = (row: PettyCashTransportationRow) =>
  row.description.trim().length > 0 &&
  row.from.trim().length > 0 &&
  row.to.trim().length > 0 &&
  row.transactionDate.trim().length > 0 &&
  getPettyCashRowAmount(row.amount) > 0;

const toPettyCashReceiptDetail = (row: PettyCashReceiptRow): PettyCashReceiptDetail => ({
  id: row.id,
  orNumber: row.orNumber.trim(),
  company: row.company.trim(),
  tin: row.tin.trim(),
  address: row.address.trim(),
  natureOfExpenseCode: row.natureOfExpenseCode.trim(),
  natureOfExpense: row.natureOfExpense.trim(),
  costCenterCode: row.costCenterCode.trim(),
  costCenter: row.costCenter.trim(),
  amount: getPettyCashRowAmount(row.amount),
  orDate: row.orDate,
});

const toPettyCashTransportationDetail = (
  row: PettyCashTransportationRow,
): PettyCashTransportationDetail => ({
  id: row.id,
  description: row.description.trim(),
  from: row.from.trim(),
  to: row.to.trim(),
  transactionDate: row.transactionDate,
  amount: getPettyCashRowAmount(row.amount),
});

const isReturnedRequest = (request: CashAdvanceRequest) =>
  request.status === "pending_liquidation" && request.history.some((event) => event.action === "returned");

export default function LiquidateModal({
  request,
  onClose,
  isSubmitting = false,
  onLiquidate,
}: LiquidateModalProps) {
  const [receiptRows, setReceiptRows] = useState<ReceiptDetailRow[]>(() => createInitialReceiptRows(request));
  const [pettyCashReceiptRows, setPettyCashReceiptRows] = useState<PettyCashReceiptRow[]>(() =>
    createInitialPettyCashReceiptRows(request),
  );
  const [pettyCashTransportationRows, setPettyCashTransportationRows] = useState<PettyCashTransportationRow[]>(() =>
    createInitialPettyCashTransportationRows(request),
  );
  const [selectedCompanyKey, setSelectedCompanyKey] = useState(() =>
    request.companyId === undefined ? "" : String(request.companyId),
  );
  const [businessPartners, setBusinessPartners] = useState<BusinessPartner[]>([]);
  const [companies, setCompanies] = useState<CompanyReference[]>([]);
  const [projects, setProjects] = useState<ProjectReference[]>([]);
  const [profitCenters, setProfitCenters] = useState<ProfitCenterReference[]>([]);
  const [expenseTypes, setExpenseTypes] = useState<ExpenseTypeReference[]>([]);
  const [notes, setNotes] = useState("");
  const [attachments, setAttachments] = useState<File[]>([]);
  const [replaceExistingAttachments, setReplaceExistingAttachments] = useState(false);

  const existingAttachmentNames =
    request.attachments && request.attachments.length > 0
      ? request.attachments.map((attachment) => attachment.fileName)
      : request.attachmentNames ?? [];
  const canReplaceExistingAttachments = isReturnedRequest(request) && existingAttachmentNames.length > 0;
  const shouldReplaceExistingAttachments = canReplaceExistingAttachments && replaceExistingAttachments;
  const needsNewAttachments = existingAttachmentNames.length === 0 || shouldReplaceExistingAttachments;
  const usesRfpLiquidationDetails = isRfpSourcedCashAdvance(request);
  const usesPettyCashLiquidationDetails =
    request.requestType === "petty_cash_advance" && !usesRfpLiquidationDetails;
  const usesReceiptDetails = usesPettyCashLiquidationDetails || usesRfpLiquidationDetails;
  const isPettyCash = isPettyCashWorkflowRequest(request);
  const selectedCompanyReference = companies.find((company) => getCompanyOptionValue(company) === selectedCompanyKey);
  const selectedCompanyId =
    selectedCompanyReference?.id ??
    (request.companyId !== undefined && selectedCompanyKey === String(request.companyId) ? request.companyId : undefined);
  const hasRequestCompanyId = typeof request.companyId === "number" && Number.isFinite(request.companyId);
  const hasSelectedCompanyId = typeof selectedCompanyId === "number" && Number.isFinite(selectedCompanyId);
  const activePettyCashReceiptRows = pettyCashReceiptRows.filter((row) => !isPettyCashReceiptRowBlank(row));
  const activePettyCashTransportationRows = pettyCashTransportationRows.filter(
    (row) => !isPettyCashTransportationRowBlank(row),
  );
  const receiptTotal = receiptRows.reduce((sum, row) => sum + getReceiptAmount(row), 0);
  const pettyCashReceiptTotal = activePettyCashReceiptRows.reduce(
    (sum, row) => sum + getPettyCashRowAmount(row.amount),
    0,
  );
  const pettyCashTransportationTotal = activePettyCashTransportationRows.reduce(
    (sum, row) => sum + getPettyCashRowAmount(row.amount),
    0,
  );
  const amountSpent = usesPettyCashLiquidationDetails
    ? pettyCashReceiptTotal + pettyCashTransportationTotal
    : usesRfpLiquidationDetails
      ? receiptTotal
      : 0;
  const hasValidAmountSpent = amountSpent > 0;
  const transferredAmount = Math.max(request.amount - request.remainingAmount, 0);
  const acknowledgedTransferredAmount = getAcknowledgedTransferAmount(request, transferredAmount);
  const transferAllocationRows = getTransferAllocationRows(request, transferredAmount);
  const amountDifference = amountSpent - request.remainingAmount;
  const returnAmount = Math.max(request.remainingAmount - amountSpent, 0);
  const excessAmount = Math.max(amountSpent - request.remainingAmount, 0);
  const isUnder = amountDifference < -0.01;
  const isExact = Math.abs(amountDifference) <= 0.01;
  const isExcess = amountDifference > 0.01;
  const showCashAdvanceExcess = isExcess && !isPettyCash;
  const receiptDetails: CashAdvanceReceiptDetail[] = usesRfpLiquidationDetails
    ? receiptRows.map((row) => ({
        id: row.id,
        vendorCode: row.vendorCode,
        vendor: row.vendor,
        description: row.description.trim(),
        projectCode: row.projectCode,
        project: row.project,
        profitCenterCode: row.profitCenterCode,
        profitCenter: row.profitCenter,
        amount: getReceiptAmount(row),
        invoiceRef: row.invoiceRef.trim(),
        expenseTypeCode: row.expenseTypeCode,
        expenseType: row.expenseType,
      }))
    : [];
  const pettyCashReceiptDetails = activePettyCashReceiptRows.map(toPettyCashReceiptDetail);
  const pettyCashTransportationDetails = activePettyCashTransportationRows.map(toPettyCashTransportationDetail);
  const hasValidReceiptRows = receiptRows.length > 0 && receiptRows.every(isReceiptRowComplete);
  const hasValidPettyCashReceiptRows = activePettyCashReceiptRows.every(isPettyCashReceiptRowComplete);
  const hasValidPettyCashTransportationRows = activePettyCashTransportationRows.every(
    isPettyCashTransportationRowComplete,
  );
  const hasPettyCashDetailRows = pettyCashReceiptDetails.length + pettyCashTransportationDetails.length > 0;
  const isWithinPettyCashLimit = !isPettyCash || amountSpent <= request.remainingAmount;
  const canSubmit =
    hasValidAmountSpent &&
    (usesPettyCashLiquidationDetails
      ? hasValidPettyCashReceiptRows && hasValidPettyCashTransportationRows && hasPettyCashDetailRows
      : usesRfpLiquidationDetails && hasValidReceiptRows) &&
    isWithinPettyCashLimit &&
    (!needsNewAttachments || attachments.length > 0);

  useEffect(() => {
    let isMounted = true;

    const loadReferences = async () => {
      const [companyResult, expenseTypeResult] = await Promise.allSettled([
        fetchApiCompanies(),
        fetchApiExpenseTypes(),
      ]);

      if (!isMounted) {
        return;
      }

      if (companyResult.status === "fulfilled" && companyResult.value.length > 0) {
        setCompanies(companyResult.value);
      } else if (companyResult.status === "rejected") {
        console.warn("Unable to load companies.", companyResult.reason);
      }

      if (expenseTypeResult.status === "fulfilled" && expenseTypeResult.value.length > 0) {
        setExpenseTypes(expenseTypeResult.value);
      } else if (expenseTypeResult.status === "rejected") {
        console.warn("Unable to load expense types.", expenseTypeResult.reason);
      }
    };

    void loadReferences();

    return () => {
      isMounted = false;
    };
  }, []);

  useEffect(() => {
    if (!usesReceiptDetails || !hasSelectedCompanyId || selectedCompanyId === undefined) {
      return;
    }

    const companyId = selectedCompanyId;
    let isMounted = true;

    const loadCompanyReferences = async () => {
      const [businessPartnerResult, projectResult, profitCenterResult] = await Promise.allSettled([
        fetchApiBusinessPartners(companyId),
        fetchApiProjects(companyId),
        fetchApiProfitCenters(companyId),
      ]);

      if (!isMounted) {
        return;
      }

      if (businessPartnerResult.status === "fulfilled") {
        setBusinessPartners(businessPartnerResult.value);
      } else {
        console.warn("Unable to load business partners.", businessPartnerResult.reason);
      }

      if (projectResult.status === "fulfilled") {
        setProjects(projectResult.value);
      } else {
        console.warn("Unable to load projects.", projectResult.reason);
      }

      if (profitCenterResult.status === "fulfilled") {
        setProfitCenters(profitCenterResult.value);
      } else {
        console.warn("Unable to load profit centers.", profitCenterResult.reason);
      }
    };

    void loadCompanyReferences();

    return () => {
      isMounted = false;
    };
  }, [hasSelectedCompanyId, selectedCompanyId, usesReceiptDetails]);

  const updateReceiptRow = (rowId: string, field: ReceiptDetailField, value: string) => {
    setReceiptRows((rows) => rows.map((row) => (row.id === rowId ? { ...row, [field]: value } : row)));
  };

  const updateReceiptVendor = (rowId: string, vendorCode: string) => {
    const selectedPartner = businessPartners.find((partner) => partner.bpCode === vendorCode);

    setReceiptRows((rows) =>
      rows.map((row) =>
        row.id === rowId
          ? {
              ...row,
              vendorCode,
              vendor: selectedPartner?.bpName ?? "",
            }
          : row,
      ),
    );
  };

  const updateReceiptProject = (rowId: string, projectCode: string) => {
    const selectedProject = projects.find((project) => project.projCode === projectCode);

    setReceiptRows((rows) =>
      rows.map((row) =>
        row.id === rowId
          ? {
              ...row,
              projectCode,
              project: selectedProject?.projName ?? "",
            }
          : row,
      ),
    );
  };

  const updateReceiptProfitCenter = (rowId: string, profitCenterCode: string) => {
    const selectedProfitCenter = profitCenters.find((profitCenter) => profitCenter.ocrCode === profitCenterCode);

    setReceiptRows((rows) =>
      rows.map((row) =>
        row.id === rowId
          ? {
              ...row,
              profitCenterCode,
              profitCenter: selectedProfitCenter?.ocrName ?? "",
            }
          : row,
      ),
    );
  };

  const updateReceiptExpenseType = (rowId: string, expenseTypeCode: string) => {
    const selectedExpenseType = expenseTypes.find((expenseType) => expenseType.expenseCode === expenseTypeCode);

    setReceiptRows((rows) =>
      rows.map((row) =>
        row.id === rowId
          ? {
              ...row,
              expenseTypeCode,
              expenseType: selectedExpenseType?.expenseName ?? "",
            }
          : row,
      ),
    );
  };

  const addReceiptRow = () => {
    setReceiptRows((rows) => [...rows, createReceiptDetailRow()]);
  };

  const deleteReceiptRow = (rowId: string) => {
    setReceiptRows((rows) =>
      rows.length === 1 ? [createReceiptDetailRow()] : rows.filter((row) => row.id !== rowId),
    );
  };

  const updatePettyCashReceiptRow = (
    rowId: string,
    field: PettyCashReceiptField,
    value: string,
  ) => {
    setPettyCashReceiptRows((rows) =>
      rows.map((row) => (row.id === rowId ? { ...row, [field]: value } : row)),
    );
  };

  const updatePettyCashExpenseType = (rowId: string, expenseTypeCode: string) => {
    const selectedExpenseType = expenseTypes.find((expenseType) => expenseType.expenseCode === expenseTypeCode);

    setPettyCashReceiptRows((rows) =>
      rows.map((row) =>
        row.id === rowId
          ? {
              ...row,
              natureOfExpenseCode: expenseTypeCode,
              natureOfExpense: selectedExpenseType?.expenseName ?? "",
            }
          : row,
      ),
    );
  };

  const updatePettyCashProfitCostCenter = (rowId: string, costCenterCode: string) => {
    const selectedProfitCenter = profitCenters.find((profitCenter) => profitCenter.ocrCode === costCenterCode);

    setPettyCashReceiptRows((rows) =>
      rows.map((row) =>
        row.id === rowId
          ? {
              ...row,
              costCenterCode,
              costCenter: selectedProfitCenter?.ocrName ?? "",
            }
          : row,
      ),
    );
  };

  const updateSelectedCompany = (companyKey: string) => {
    if (companyKey === selectedCompanyKey) {
      return;
    }

    setSelectedCompanyKey(companyKey);
    setBusinessPartners([]);
    setProjects([]);
    setProfitCenters([]);
    setPettyCashReceiptRows((rows) =>
      rows.map((row) =>
        row.costCenterCode || row.costCenter
          ? {
              ...row,
              costCenterCode: "",
              costCenter: "",
            }
          : row,
      ),
    );
    setReceiptRows((rows) =>
      rows.map((row) =>
        row.vendorCode || row.vendor || row.projectCode || row.project || row.profitCenterCode || row.profitCenter
          ? {
              ...row,
              vendorCode: "",
              vendor: "",
              projectCode: "",
              project: "",
              profitCenterCode: "",
              profitCenter: "",
            }
          : row,
      ),
    );
  };

  const updatePettyCashTransportationRow = (
    rowId: string,
    field: PettyCashTransportationField,
    value: string,
  ) => {
    setPettyCashTransportationRows((rows) =>
      rows.map((row) => (row.id === rowId ? { ...row, [field]: value } : row)),
    );
  };

  const addPettyCashReceiptRow = () => {
    setPettyCashReceiptRows((rows) => [...rows, createPettyCashReceiptRow()]);
  };

  const addPettyCashTransportationRow = () => {
    setPettyCashTransportationRows((rows) => [...rows, createPettyCashTransportationRow()]);
  };

  const deletePettyCashReceiptRow = (rowId: string) => {
    setPettyCashReceiptRows((rows) =>
      rows.length === 1 ? [createPettyCashReceiptRow()] : rows.filter((row) => row.id !== rowId),
    );
  };

  const deletePettyCashTransportationRow = (rowId: string) => {
    setPettyCashTransportationRows((rows) => rows.filter((row) => row.id !== rowId));
  };

  const keepExistingAttachments = () => {
    setReplaceExistingAttachments(false);
    setAttachments([]);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="flex max-h-[90vh] w-full max-w-[1600px] flex-col overflow-hidden rounded-lg bg-white shadow-xl">
        <div className="shrink-0 border-b border-[#d9e1e8] p-6">
          <h2 className="text-xl font-bold text-[#17243f]">Liquidate Request</h2>
          <p className="mt-1 text-sm text-[#5c6b7a]">{request.requestNumber}</p>
        </div>

        <div className="shrink-0 border-b border-[#d9e1e8] px-6 py-4">
          <div className="rounded-lg bg-[#f3f6f9] p-4 text-sm">
            <div className="flex justify-between">
              <span className="text-[#5c6b7a]">Original Amount</span>
              <span className="font-semibold text-[#17243f]">PHP {request.amount.toLocaleString()}</span>
            </div>
            {acknowledgedTransferredAmount > 0 && (
              <div className="mt-2 flex justify-between">
                <span className="text-[#5c6b7a]">Transferred Amount</span>
                <span className="font-semibold text-[#17243f]">PHP {acknowledgedTransferredAmount.toLocaleString()}</span>
              </div>
            )}
            <div className="mt-2 flex justify-between">
              <span className="text-[#5c6b7a]">{isPettyCash ? "Released Amount" : "Available to Liquidate"}</span>
              <span className="font-semibold text-[#08786f]">PHP {request.remainingAmount.toLocaleString()}</span>
            </div>
          </div>
        </div>

        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-6">
          {transferAllocationRows.length > 0 && (
            <div className="rounded-lg border border-[#c8d4df] bg-white p-4 text-sm">
              <p className="font-bold text-[#17243f]">Transfer Allocation</p>
              {transferAllocationRows.map((allocation) => (
                <div key={allocation.id} className="mt-3 flex justify-between gap-4">
                  <span className="text-[#5c6b7a]">
                    Receiver: {allocation.receiverName}
                    <span className="ml-1 text-xs">
                      ({allocation.status === "pending" ? "pending acknowledgement" : "acknowledged"})
                    </span>
                  </span>
                  <span
                    className={`shrink-0 font-semibold ${
                      allocation.status === "pending" ? "text-[#9a6500]" : "text-[#17243f]"
                    }`}
                  >
                    PHP {allocation.amount.toLocaleString()}
                  </span>
                </div>
              ))}
            </div>
          )}

          {usesReceiptDetails && (
            <div className="grid gap-2 sm:max-w-md">
              <label className="text-sm font-semibold text-[#17243f]" htmlFor="liquidation-company">
                Company
              </label>
              <select
                id="liquidation-company"
                value={selectedCompanyKey}
                onChange={(event) => updateSelectedCompany(event.target.value)}
                disabled={hasRequestCompanyId}
                className="w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none disabled:bg-[#f3f6f9] disabled:text-[#5c6b7a]"
              >
                <option value="">Select company</option>
                {companies.map((company) => (
                  <option key={getCompanyOptionValue(company)} value={getCompanyOptionValue(company)}>
                    {company.name}
                  </option>
                ))}
              </select>
            </div>
          )}

          {usesPettyCashLiquidationDetails ? (
            <>
              <div className="rounded-lg border border-[#c8d4df] bg-white p-4">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h3 className="font-bold text-[#17243f]">Receipt Details</h3>
                    <p className="mt-1 text-sm text-[#5c6b7a]">
                      Total: {formatCurrency(pettyCashReceiptTotal)}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={addPettyCashReceiptRow}
                    className="rounded-lg bg-[#17243f] px-3 py-2 text-xs font-semibold text-white hover:bg-[#243558]"
                  >
                    Add Row
                  </button>
                </div>
                <div className="mt-4 overflow-x-auto">
                  <div className="min-w-[1280px] space-y-2">
                    <div className="grid grid-cols-[130px_190px_150px_220px_220px_150px_120px_130px_80px] gap-2 text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">
                      <span>OR#<span className="text-rose-400">*</span></span>
                      <span>Company<span className="text-rose-400">*</span></span>
                      <span>TIN<span className="text-rose-400">*</span></span>
                      <span>Address<span className="text-rose-400">*</span></span>
                      <span>Type of Expense<span className="text-rose-400">*</span></span>
                      <span>Profit Cost Center<span className="text-rose-400">*</span></span>
                      <span>Amount<span className="text-rose-400">*</span></span>
                      <span>OR Date<span className="text-rose-400">*</span></span>
                      <span></span>
                    </div>
                    {pettyCashReceiptRows.map((row) => (
                      <div
                        key={row.id}
                        className="grid grid-cols-[130px_190px_150px_220px_220px_150px_120px_130px_80px] gap-2"
                      >
                        <input
                          type="text"
                          value={row.orNumber}
                          onChange={(event) => updatePettyCashReceiptRow(row.id, "orNumber", event.target.value)}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="OR number"
                        />
                        <input
                          type="text"
                          value={row.company}
                          onChange={(event) => updatePettyCashReceiptRow(row.id, "company", event.target.value)}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Company"
                        />
                        <input
                          type="text"
                          value={row.tin}
                          onChange={(event) => updatePettyCashReceiptRow(row.id, "tin", event.target.value)}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="TIN"
                        />
                        <input
                          type="text"
                          value={row.address}
                          onChange={(event) => updatePettyCashReceiptRow(row.id, "address", event.target.value)}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Address"
                        />
                        <select
                          value={row.natureOfExpenseCode}
                          onChange={(event) => updatePettyCashExpenseType(row.id, event.target.value)}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Type of Expense"
                        >
                          <option value="">Select expense</option>
                          {row.natureOfExpense &&
                            row.natureOfExpenseCode &&
                            !expenseTypes.some((expenseType) => expenseType.expenseCode === row.natureOfExpenseCode) && (
                              <option value={row.natureOfExpenseCode}>{row.natureOfExpense}</option>
                            )}
                          {expenseTypes.map((expenseType) => (
                            <option key={expenseType.expenseCode} value={expenseType.expenseCode}>
                              {expenseType.expenseName}
                            </option>
                          ))}
                        </select>
                        <select
                          value={row.costCenterCode}
                          onChange={(event) => updatePettyCashProfitCostCenter(row.id, event.target.value)}
                          disabled={!hasSelectedCompanyId}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none disabled:bg-[#f3f6f9] disabled:text-[#8a98a8]"
                          aria-label="Profit Cost Center"
                        >
                          <option value="">{hasSelectedCompanyId ? "Select center" : "Select company first"}</option>
                          {row.costCenter &&
                            row.costCenterCode &&
                            !profitCenters.some((profitCenter) => profitCenter.ocrCode === row.costCenterCode) && (
                              <option value={row.costCenterCode}>{row.costCenter}</option>
                            )}
                          {profitCenters.map((profitCenter) => (
                            <option key={profitCenter.ocrCode} value={profitCenter.ocrCode}>
                              {profitCenter.ocrName}
                            </option>
                          ))}
                        </select>
                        <input
                          type="number"
                          min={0}
                          step="0.01"
                          value={row.amount}
                          onChange={(event) => updatePettyCashReceiptRow(row.id, "amount", event.target.value)}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Receipt amount"
                        />
                        <input
                          type="date"
                          value={row.orDate}
                          onChange={(event) => updatePettyCashReceiptRow(row.id, "orDate", event.target.value)}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="OR date"
                        />
                        <button
                          type="button"
                          onClick={() => deletePettyCashReceiptRow(row.id)}
                          className="rounded-lg border border-[#ffb3c6] px-3 py-2 text-xs font-semibold text-[#d30f42] hover:bg-[#fff0f4]"
                        >
                          Del
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
                {!hasValidPettyCashReceiptRows && (
                  <p className="mt-3 text-xs font-semibold text-[#d30f42]">
                    Complete every filled receipt row before submitting.
                  </p>
                )}
              </div>

              <div className="rounded-lg border border-[#c8d4df] bg-white p-4">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h3 className="font-bold text-[#17243f]">Transportation Expenses</h3>
                    <p className="mt-1 text-sm text-[#5c6b7a]">
                      Total: {formatCurrency(pettyCashTransportationTotal)}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={addPettyCashTransportationRow}
                    className="rounded-lg bg-[#17243f] px-3 py-2 text-xs font-semibold text-white hover:bg-[#243558]"
                  >
                    Add Row
                  </button>
                </div>
                <div className="mt-4 overflow-x-auto">
                  <div className="min-w-[920px] space-y-2">
                    <div className="grid grid-cols-[150px_220px_150px_150px_120px_80px] gap-2 text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">
                      <span>Transaction Date</span>
                      <span>Description</span>
                      <span>From</span>
                      <span>To</span>
                      <span>Amount</span>
                      <span></span>
                    </div>
                    {pettyCashTransportationRows.map((row) => (
                      <div key={row.id} className="grid grid-cols-[150px_220px_150px_150px_120px_80px] gap-2">
                        <input
                          type="date"
                          value={row.transactionDate}
                          onChange={(event) =>
                            updatePettyCashTransportationRow(row.id, "transactionDate", event.target.value)
                          }
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation transaction date"
                        />
                        <input
                          type="text"
                          value={row.description}
                          onChange={(event) =>
                            updatePettyCashTransportationRow(row.id, "description", event.target.value)
                          }
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation description"
                        />
                        <input
                          type="text"
                          value={row.from}
                          onChange={(event) => updatePettyCashTransportationRow(row.id, "from", event.target.value)}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation from"
                        />
                        <input
                          type="text"
                          value={row.to}
                          onChange={(event) => updatePettyCashTransportationRow(row.id, "to", event.target.value)}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation to"
                        />
                        <input
                          type="number"
                          min={0}
                          step="0.01"
                          value={row.amount}
                          onChange={(event) =>
                            updatePettyCashTransportationRow(row.id, "amount", event.target.value)
                          }
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation amount"
                        />
                        <button
                          type="button"
                          onClick={() => deletePettyCashTransportationRow(row.id)}
                          className="rounded-lg border border-[#ffb3c6] px-3 py-2 text-xs font-semibold text-[#d30f42] hover:bg-[#fff0f4]"
                        >
                          Del
                        </button>
                      </div>
                    ))}
                    {pettyCashTransportationRows.length === 0 && (
                      <p className="rounded-lg bg-[#f3f6f9] px-4 py-5 text-center text-sm text-[#5c6b7a]">
                        No transportation expense rows added.
                      </p>
                    )}
                  </div>
                </div>
                {!hasValidPettyCashTransportationRows && (
                  <p className="mt-3 text-xs font-semibold text-[#d30f42]">
                    Complete every transportation row before submitting.
                  </p>
                )}
              </div>

              {!hasPettyCashDetailRows && (
                <p className="rounded-lg border border-[#ff1550] bg-[#fff0f4] px-3 py-2 text-sm text-[#d30f42]">
                  Add at least one receipt or transportation row before submitting.
                </p>
              )}
            </>
          ) : usesRfpLiquidationDetails ? (
            <div className="rounded-lg border border-[#c8d4df] bg-white p-4">
            <h3 className="font-bold text-[#17243f]">Receipt Details</h3>
            <div className="mt-4 overflow-x-auto">
              <div className="min-w-[1340px] space-y-2">
                <div className="grid grid-cols-[150px_220px_220px_150px_130px_150px_260px_80px] gap-2 text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">
                  <span>Vendor<span className="text-rose-400">*</span></span>
                  <span>Description<span className="text-rose-400">*</span></span>
                  <span>Project<span className="text-rose-400">*</span></span>
                  <span>Profit Cost Center<span className="text-rose-400">*</span></span>
                  <span>Amount<span className="text-rose-400">*</span></span>
                  <span>Invoice Ref.<span className="text-rose-400">*</span></span>
                  <span>Type of Expense<span className="text-rose-400">*</span></span>
                  <span></span>
                </div>
                {receiptRows.map((row) => (
                  <div
                    key={row.id}
                    className="grid grid-cols-[150px_220px_220px_150px_130px_150px_260px_80px] gap-2"
                  >
                    <select
                      value={row.vendorCode}
                      onChange={(event) => updateReceiptVendor(row.id, event.target.value)}
                      disabled={!hasSelectedCompanyId}
                      className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none disabled:bg-[#f3f6f9] disabled:text-[#8a98a8]"
                      aria-label="Vendor"
                    >
                      <option value="">{hasSelectedCompanyId ? "Select vendor" : "Select company first"}</option>
                      {row.vendor &&
                        row.vendorCode &&
                        !businessPartners.some((partner) => partner.bpCode === row.vendorCode) && (
                        <option value={row.vendorCode}>
                          {row.vendor}
                        </option>
                      )}
                      {businessPartners.map((partner) => (
                        <option key={partner.bpCode} value={partner.bpCode}>
                          {partner.bpName}
                        </option>
                      ))}
                    </select>
                    <input
                      type="text"
                      value={row.description}
                      onChange={(event) => updateReceiptRow(row.id, "description", event.target.value)}
                      className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                      aria-label="Description"
                    />
                    <select
                      value={row.projectCode}
                      onChange={(event) => updateReceiptProject(row.id, event.target.value)}
                      disabled={!hasSelectedCompanyId}
                      className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none disabled:bg-[#f3f6f9] disabled:text-[#8a98a8]"
                      aria-label="Project"
                    >
                      <option value="">{hasSelectedCompanyId ? "Select project" : "Select company first"}</option>
                      {row.project &&
                        row.projectCode &&
                        !projects.some((project) => project.projCode === row.projectCode) && (
                        <option value={row.projectCode}>
                          {row.project}
                        </option>
                      )}
                      {projects.map((project) => (
                        <option key={project.projCode} value={project.projCode}>
                          {project.projName}
                        </option>
                      ))}
                    </select>
                    <select
                      value={row.profitCenterCode}
                      onChange={(event) => updateReceiptProfitCenter(row.id, event.target.value)}
                      disabled={!hasSelectedCompanyId}
                      className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none disabled:bg-[#f3f6f9] disabled:text-[#8a98a8]"
                      aria-label="Profit Cost Center"
                    >
                      <option value="">{hasSelectedCompanyId ? "Select center" : "Select company first"}</option>
                      {row.profitCenter &&
                        row.profitCenterCode &&
                        !profitCenters.some((profitCenter) => profitCenter.ocrCode === row.profitCenterCode) && (
                        <option value={row.profitCenterCode}>
                          {row.profitCenter}
                        </option>
                      )}
                      {profitCenters.map((profitCenter) => (
                        <option key={profitCenter.ocrCode} value={profitCenter.ocrCode}>
                          {profitCenter.ocrName}
                        </option>
                      ))}
                    </select>
                    <input
                      type="number"
                      value={row.amount}
                      min={0}
                      step="0.01"
                      onChange={(event) => updateReceiptRow(row.id, "amount", event.target.value)}
                      className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                      aria-label="Amount"
                    />
                    <input
                      type="text"
                      value={row.invoiceRef}
                      onChange={(event) => updateReceiptRow(row.id, "invoiceRef", event.target.value)}
                      className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                      aria-label="Invoice Ref."
                    />
                    <select
                      value={row.expenseTypeCode}
                      onChange={(event) => updateReceiptExpenseType(row.id, event.target.value)}
                      className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                      aria-label="Type of Expense"
                    >
                      <option value="">Select type</option>
                      {row.expenseType &&
                        row.expenseTypeCode &&
                        !expenseTypes.some((expenseType) => expenseType.expenseCode === row.expenseTypeCode) && (
                        <option value={row.expenseTypeCode}>
                          {row.expenseType}
                        </option>
                      )}
                      {expenseTypes.map((expenseType) => (
                        <option key={expenseType.expenseCode} value={expenseType.expenseCode}>
                          {expenseType.expenseName}
                        </option>
                      ))}
                    </select>
                    <button
                      type="button"
                      onClick={() => deleteReceiptRow(row.id)}
                      className="rounded-lg border border-[#ffb3c6] px-3 py-2 text-xs font-semibold text-[#d30f42] hover:bg-[#fff0f4]"
                    >
                      Del
                    </button>
                  </div>
                ))}
                <button
                  type="button"
                  onClick={addReceiptRow}
                  className="w-[150px] rounded-lg bg-[#17243f] px-3 py-2 text-xs font-semibold text-white hover:bg-[#243558]"
                >
                  Add Row
                </button>
              </div>
            </div>
            </div>
          ) : null}

          <div>
            <div className="rounded-lg bg-[#f3f6f9] px-4 py-3 text-sm">
              <div className="flex justify-between gap-4">
                <span className="font-semibold text-[#17243f]">Actual Amount Spent</span>
                <span className="font-bold text-[#08786f]">{formatCurrency(amountSpent)}</span>
              </div>
            </div>
            {isUnder && amountSpent > 0 && (
              <p className="mt-3 rounded-lg border border-[#ff1550] bg-[#fff0f4] px-3 py-2 text-sm text-[#d30f42]">
                PHP {returnAmount.toLocaleString()} need to return.
              </p>
            )}
            {isExact && (
              <p className="mt-3 rounded-lg border border-[#00df72] bg-[#e4fff0] px-3 py-2 text-sm text-[#047a40]">
                Exact amount.
              </p>
            )}
            {showCashAdvanceExcess && (
              <p className="mt-3 rounded-lg border border-[#ffc400] bg-[#fff4c7] px-3 py-2 text-sm text-[#9a6500]">
                PHP {excessAmount.toLocaleString()} Overspend.
              </p>
            )}
            {isPettyCash && !isWithinPettyCashLimit && (
              <p className="mt-3 rounded-lg border border-[#ff1550] bg-[#fff0f4] px-3 py-2 text-sm text-[#d30f42]">
                Petty cash liquidation cannot exceed the released amount. Reduce receipt rows by PHP{" "}
                {excessAmount.toLocaleString()} or create a separate petty cash request for the excess.
              </p>
            )}
          </div>

          <div>
            {canReplaceExistingAttachments && (
              <div className="mb-4 rounded-lg border border-[#d9e1e8] bg-[#f8fafc] p-4">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="font-semibold text-[#17243f]">Existing receipt attachments</p>
                    <p className="mt-1 text-sm text-[#5c6b7a]">
                      Keep the current files or replace them with corrected receipts.
                    </p>
                  </div>
                  <div className="flex rounded-lg border border-[#c8d4df] bg-white p-1 text-xs font-semibold">
                    <button
                      type="button"
                      onClick={keepExistingAttachments}
                      className={`rounded-md px-3 py-2 ${
                        !shouldReplaceExistingAttachments ? "bg-[#17243f] text-white" : "text-[#5c6b7a] hover:bg-[#f3f6f9]"
                      }`}
                    >
                      Keep
                    </button>
                    <button
                      type="button"
                      onClick={() => setReplaceExistingAttachments(true)}
                      className={`rounded-md px-3 py-2 ${
                        shouldReplaceExistingAttachments ? "bg-[#17243f] text-white" : "text-[#5c6b7a] hover:bg-[#f3f6f9]"
                      }`}
                    >
                      Replace
                    </button>
                  </div>
                </div>
                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  {existingAttachmentNames.map((fileName) => (
                    <p key={fileName} className="rounded-lg border border-[#e3e9ef] bg-white px-3 py-2 text-xs text-[#5c6b7a]">
                      {fileName}
                    </p>
                  ))}
                </div>
              </div>
            )}
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="attachments">
              {shouldReplaceExistingAttachments ? "Replacement Receipts" : "Attach Receipts"}{" "}
              {needsNewAttachments && <span className="text-rose-400">*</span>}
            </label>
            {(!canReplaceExistingAttachments || shouldReplaceExistingAttachments) ? (
              <input
                id="attachments"
                type="file"
                multiple
                onChange={(event) => event.target.files && setAttachments(Array.from(event.target.files))}
                className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm"
              />
            ) : (
              <p className="mt-2 rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] px-3 py-3 text-sm text-[#5c6b7a]">
                Existing receipt attachments will be kept. Choose Replace to upload corrected files.
              </p>
            )}
            {attachments.length > 0 && (
              <div className="mt-2 text-xs text-[#5c6b7a]">
                {attachments.map((file) => (
                  <p key={file.name}>{file.name}</p>
                ))}
              </div>
            )}
            {attachments.length === 0 && existingAttachmentNames.length > 0 && !canReplaceExistingAttachments && (
              <div className="mt-2 rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] px-3 py-2 text-xs text-[#5c6b7a]">
                <p className="font-semibold text-[#17243f]">Existing receipts</p>
                {existingAttachmentNames.map((fileName) => (
                  <p key={fileName}>{fileName}</p>
                ))}
              </div>
            )}
            {shouldReplaceExistingAttachments && attachments.length === 0 && (
              <p className="mt-2 text-xs font-semibold text-[#d30f42]">
                Upload at least one replacement receipt before resubmitting.
              </p>
            )}
          </div>

          <div>
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="notes">
              Notes
            </label>
            <textarea
              id="notes"
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              rows={3}
              className="mt-2 w-full resize-none rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
          </div>
        </div>

        <div className="flex shrink-0 gap-3 border-t border-[#d9e1e8] p-6">
          <button
            type="button"
            onClick={onClose}
            disabled={isSubmitting}
            className="flex-1 rounded-lg border border-[#d9e1e8] px-4 py-3 text-sm font-semibold text-[#17243f] hover:bg-[#f3f6f9]"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={() => {
              if (isSubmitting) {
                return;
              }

              onLiquidate(
                request.id,
                amountSpent,
                receiptDetails,
                pettyCashReceiptDetails,
                pettyCashTransportationDetails,
                notes,
                attachments,
                shouldReplaceExistingAttachments,
              );
            }}
            disabled={!canSubmit || isSubmitting}
            className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isSubmitting ? "Processing..." : "Submit to Department"}
          </button>
        </div>
      </div>

      {isSubmitting && (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="liquidation-processing-title"
        >
          <div className="w-full max-w-sm rounded-lg bg-white px-6 py-8 text-center shadow-xl">
            <div
              className="mx-auto h-10 w-10 animate-spin rounded-full border-4 border-[#d9e1e8] border-t-[#0bb7a5]"
              aria-hidden="true"
            />
            <h3 id="liquidation-processing-title" className="mt-5 text-lg font-bold text-[#17243f]">
              Processing liquidation
            </h3>
            <p className="mt-2 text-sm text-[#5c6b7a]">
              Submitting {request.requestNumber}. Please wait until processing is complete.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
