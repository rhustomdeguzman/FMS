import type {
  AcknowledgementReceipt,
  AccountingReportPeriod,
  AppUser,
  AttachmentMeta,
  BusinessPartner,
  CashAdvanceReceiptDetail,
  CashAdvanceRequest,
  CashAdvanceRequestType,
  CashAdvanceStatus,
  CompanyReference,
  CreateAppUserInput,
  DepartmentCustodianAssignment,
  Employee,
  ExpenseTypeReference,
  PendingTransfer,
  PettyCashReceiptDetail,
  PettyCashTransportationDetail,
  ProfitCenterReference,
  ProjectReference,
  TransactionAction,
  TransferAllocation,
  TransferAllocationStatus,
  UpdateAppUserInput,
  UserRole,
} from "../types/CashAdvance";

const apiBaseUrl = (import.meta.env.VITE_FUND_MANAGEMENT_API_URL ?? "").replace(/\/$/, "");

type ApiObject = Record<string, unknown>;

const userRoles: UserRole[] = ["admin", "requestor", "department_head", "accounting", "cashier", "custodian"];
const cashAdvanceRequestTypes: CashAdvanceRequestType[] = [
  "cash_advance",
  "petty_cash",
  "petty_cash_advance",
  "petty_cash_replenishment",
];
const cashAdvanceStatuses: CashAdvanceStatus[] = [
  "pending_liquidation",
  "pending_department_approval",
  "pending_cashier_return",
  "pending_cashier_closure",
  "pending_accounting_review",
  "pending_rfp_department_approval",
  "pending_rfp_attachment",
  "pending_custodian_approval",
  "pending_custodian_liquidation_review",
  "partially_liquidated",
  "fully_liquidated",
  "transferred",
  "rfp_created",
  "pending_replenishment",
  "replenished",
  "rejected",
];

const transactionActions: TransactionAction[] = [
  "created",
  "approved_by_department_head",
  "approved_by_accounting",
  "liquidation_submitted",
  "sent_to_accounting",
  "returned",
  "rejected",
  "transfer_requested",
  "transfer_acknowledged",
  "transfer_denied",
  "transferred",
  "partially_liquidated",
  "fully_liquidated",
  "excess_created",
  "rfp_created",
  "rfp_waived",
  "rfp_attachment_uploaded",
  "return_to_cashier",
  "acknowledged",
  "petty_cash_requested",
  "approved_by_custodian",
  "petty_cash_released",
  "petty_cash_replenishment_created",
  "petty_cash_replenished",
];

const transferAllocationStatuses: TransferAllocationStatus[] = ["acknowledged", "pending", "denied"];

const readValue = (source: ApiObject, camelName: string, pascalName: string): unknown =>
  source[camelName] ?? source[pascalName];

const readNumberArray = (source: ApiObject, camelName: string, pascalName: string): number[] => {
  const value = readValue(source, camelName, pascalName);
  return Array.isArray(value) ? value.filter((item): item is number => typeof item === "number") : [];
};

const readString = (source: ApiObject, camelName: string, pascalName: string, fallback = ""): string => {
  const value = readValue(source, camelName, pascalName);
  return typeof value === "string" ? value : fallback;
};

const readStringOrNumber = (source: ApiObject, camelName: string, pascalName: string, fallback = ""): string => {
  const value = readValue(source, camelName, pascalName);
  if (typeof value === "string") {
    return value;
  }

  return typeof value === "number" ? String(value) : fallback;
};

const readNumber = (source: ApiObject, camelName: string, pascalName: string, fallback = 0): number => {
  const value = readValue(source, camelName, pascalName);
  return typeof value === "number" ? value : fallback;
};

const readOptionalNumber = (source: ApiObject, camelName: string, pascalName: string): number | undefined => {
  const value = readValue(source, camelName, pascalName);
  return typeof value === "number" ? value : undefined;
};

const readOptionalDate = (
  source: ApiObject,
  camelName: string,
  pascalName: string,
  ...fallbackNames: string[]
): Date | undefined => {
  const value = [camelName, pascalName, ...fallbackNames].map((name) => source[name]).find((item) => item !== undefined);
  if (typeof value !== "string") {
    return undefined;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
};

const readObject = (source: ApiObject, camelName: string, pascalName: string): ApiObject | undefined => {
  const value = readValue(source, camelName, pascalName);
  return value && typeof value === "object" && !Array.isArray(value) ? (value as ApiObject) : undefined;
};

const readArray = (source: ApiObject, camelName: string, pascalName: string): ApiObject[] => {
  const value = readValue(source, camelName, pascalName);
  return Array.isArray(value) ? value.filter((item): item is ApiObject => item && typeof item === "object") : [];
};

const initialsFor = (name: string) =>
  name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("") || "U";

const toUserRole = (role: string): UserRole =>
  userRoles.includes(role as UserRole) ? (role as UserRole) : "requestor";

const toCashAdvanceStatus = (status: string): CashAdvanceStatus =>
  cashAdvanceStatuses.includes(status as CashAdvanceStatus) ? (status as CashAdvanceStatus) : "pending_liquidation";

const toCashAdvanceRequestType = (requestType: string): CashAdvanceRequestType =>
  cashAdvanceRequestTypes.includes(requestType as CashAdvanceRequestType)
    ? (requestType as CashAdvanceRequestType)
    : "cash_advance";

const toTransactionAction = (action: string): TransactionAction =>
  transactionActions.includes(action as TransactionAction) ? (action as TransactionAction) : "created";

const toTransferAllocationStatus = (status: string): TransferAllocationStatus =>
  transferAllocationStatuses.includes(status as TransferAllocationStatus)
    ? (status as TransferAllocationStatus)
    : "pending";

const statusToHistoryAction = (status: CashAdvanceStatus): TransactionAction => {
  if (status === "pending_department_approval") return "liquidation_submitted";
  if (status === "pending_cashier_return") return "return_to_cashier";
  if (status === "pending_cashier_closure") return "approved_by_accounting";
  if (status === "pending_accounting_review") return "approved_by_department_head";
  if (status === "pending_rfp_department_approval") return "approved_by_accounting";
  if (status === "pending_rfp_attachment") return "rfp_created";
  if (status === "pending_custodian_approval") return "approved_by_department_head";
  if (status === "pending_custodian_liquidation_review") return "approved_by_department_head";
  if (status === "fully_liquidated") return "fully_liquidated";
  if (status === "rfp_created") return "rfp_created";
  if (status === "pending_replenishment") return "petty_cash_replenishment_created";
  if (status === "replenished") return "petty_cash_replenished";
  if (status === "rejected") return "rejected";
  if (status === "transferred") return "transferred";
  return "created";
};

const toAppUser = (apiUser: ApiObject): AppUser => {
  const id = String(readNumber(apiUser, "userId", "UserId"));
  const name = readString(apiUser, "displayName", "DisplayName", "Unnamed User");

  return {
    id,
    username: readString(apiUser, "username", "Username"),
    name,
    department: readString(apiUser, "department", "Department"),
    departmentCode: readOptionalNumber(apiUser, "departmentCode", "DepartmentCode"),
    departmentGroups: readNumberArray(apiUser, "departmentGroups", "DepartmentGroups"),
    role: toUserRole(readString(apiUser, "role", "Role")),
    roleCode: readOptionalNumber(apiUser, "roleCode", "RoleCode"),
    title: readString(apiUser, "title", "Title"),
    avatar: initialsFor(name),
    pettyCashFundAmount: readOptionalNumber(apiUser, "pettyCashFundAmount", "PettyCashFundAmount"),
  };
};

const toDepartmentCustodianAssignment = (apiAssignment: ApiObject): DepartmentCustodianAssignment => {
  const custodianUserId = readOptionalNumber(apiAssignment, "custodianUserId", "CustodianUserId");

  return {
    departmentCode: String(readNumber(apiAssignment, "departmentCode", "DepartmentCode")),
    departmentName: readString(apiAssignment, "departmentName", "DepartmentName"),
    custodianUserId: custodianUserId === undefined ? undefined : String(custodianUserId),
    custodianName: readString(apiAssignment, "custodianName", "CustodianName") || undefined,
    custodianDepartment: readString(apiAssignment, "custodianDepartment", "CustodianDepartment") || undefined,
    custodianFundAmount: readOptionalNumber(apiAssignment, "custodianFundAmount", "CustodianFundAmount"),
  };
};

const createApiEmployee = (id: number, name: string, department: string): Employee => ({
  id: String(id),
  name,
  department,
  avatar: initialsFor(name),
});

const addDays = (date: Date, days: number) => {
  const nextDate = new Date(date);
  nextDate.setDate(nextDate.getDate() + days);
  return nextDate;
};

const toAttachment = (apiAttachment: ApiObject): AttachmentMeta => {
  const id = String(readNumber(apiAttachment, "attachmentId", "AttachmentId"));
  return {
    id,
    fileName: readString(apiAttachment, "fileName", "FileName", "Attachment"),
    contentType: readString(apiAttachment, "contentType", "ContentType", "application/octet-stream"),
    fileSize: readNumber(apiAttachment, "fileSizeBytes", "FileSizeBytes"),
    downloadUrl: apiBaseUrl + "/api/cash-advance/attachments/" + id,
  };
};

const toReceiptDetail = (apiReceiptDetail: ApiObject, index: number): CashAdvanceReceiptDetail => ({
  id: String(readNumber(apiReceiptDetail, "receiptDetailId", "ReceiptDetailId", index + 1)),
  vendorCode: readString(apiReceiptDetail, "vendorCode", "VendorCode") || undefined,
  vendor: readString(apiReceiptDetail, "vendor", "Vendor"),
  description: readString(apiReceiptDetail, "description", "Description"),
  projectCode: readString(apiReceiptDetail, "projectCode", "ProjectCode") || undefined,
  project: readString(apiReceiptDetail, "project", "Project"),
  profitCenterCode: readString(apiReceiptDetail, "profitCenterCode", "ProfitCenterCode") || undefined,
  profitCenter: readString(apiReceiptDetail, "profitCenter", "ProfitCenter"),
  amount: readNumber(apiReceiptDetail, "amount", "Amount"),
  invoiceRef: readString(apiReceiptDetail, "invoiceRef", "InvoiceRef"),
  expenseTypeCode: readString(apiReceiptDetail, "expenseTypeCode", "ExpenseTypeCode") || undefined,
  expenseType: readString(apiReceiptDetail, "expenseType", "ExpenseType"),
  createdAt: readOptionalDate(apiReceiptDetail, "auditDate", "AuditDate"),
});

const toPettyCashReceiptDetail = (apiReceiptDetail: ApiObject, index: number): PettyCashReceiptDetail => ({
  id: String(readNumber(apiReceiptDetail, "pettyCashReceiptDetailId", "PettyCashReceiptDetailId", index + 1)),
  orNumber: readString(apiReceiptDetail, "orNumber", "OrNumber"),
  company: readString(apiReceiptDetail, "company", "Company"),
  tin: readString(apiReceiptDetail, "tin", "Tin"),
  address: readString(apiReceiptDetail, "address", "Address"),
  natureOfExpenseCode: readString(apiReceiptDetail, "natureOfExpenseCode", "NatureOfExpenseCode") || undefined,
  natureOfExpense: readString(apiReceiptDetail, "natureOfExpense", "NatureOfExpense"),
  costCenterCode: readString(apiReceiptDetail, "costCenterCode", "CostCenterCode") || undefined,
  costCenter: readString(apiReceiptDetail, "costCenter", "CostCenter"),
  taxType: readString(apiReceiptDetail, "taxType", "TaxType") || undefined,
  amount: readNumber(apiReceiptDetail, "amount", "Amount"),
  orDate: readString(apiReceiptDetail, "orDate", "OrDate"),
});

const toPettyCashTransportationDetail = (
  apiTransportationDetail: ApiObject,
  index: number,
): PettyCashTransportationDetail => ({
  id: String(
    readNumber(apiTransportationDetail, "pettyCashTransportationDetailId", "PettyCashTransportationDetailId", index + 1),
  ),
  description: readString(apiTransportationDetail, "description", "Description"),
  from: readString(apiTransportationDetail, "from", "From"),
  to: readString(apiTransportationDetail, "to", "To"),
  transactionDate: readString(apiTransportationDetail, "transactionDate", "TransactionDate"),
  amount: readNumber(apiTransportationDetail, "amount", "Amount"),
});

const toApiReceiptDetailsJson = (receiptDetails: CashAdvanceReceiptDetail[]) =>
  JSON.stringify(
    receiptDetails.map((detail) => ({
      Vendor: detail.vendor,
      VendorCode: detail.vendorCode,
      Description: detail.description,
      ProjectCode: detail.projectCode,
      Project: detail.project,
      ProfitCenterCode: detail.profitCenterCode,
      ProfitCenter: detail.profitCenter,
      Amount: detail.amount,
      InvoiceRef: detail.invoiceRef,
      ExpenseTypeCode: detail.expenseTypeCode,
      ExpenseType: detail.expenseType,
    })),
  );

const toApiPettyCashReceiptDetails = (receiptDetails: PettyCashReceiptDetail[]) =>
  receiptDetails.map((detail) => ({
    orNumber: detail.orNumber,
    company: detail.company,
    tin: detail.tin,
    address: detail.address,
    natureOfExpenseCode: detail.natureOfExpenseCode,
    natureOfExpense: detail.natureOfExpense,
    costCenterCode: detail.costCenterCode,
    costCenter: detail.costCenter,
    taxType: detail.taxType,
    amount: detail.amount,
    orDate: detail.orDate,
  }));

const toApiPettyCashTransportationDetails = (transportationDetails: PettyCashTransportationDetail[]) =>
  transportationDetails.map((detail) => ({
    description: detail.description,
    from: detail.from,
    to: detail.to,
    transactionDate: detail.transactionDate,
    amount: detail.amount,
  }));

const toAcknowledgementReceipt = (
  apiReceipt: ApiObject | undefined,
  requestId: string,
  requestNumber: string,
  requestor: Employee,
  isCustodianReturnReceipt = false,
): AcknowledgementReceipt | undefined => {
  if (!apiReceipt) {
    return undefined;
  }

  const id = String(readNumber(apiReceipt, "receiptId", "ReceiptId"));
  const attachmentFileName = readString(apiReceipt, "attachmentFileName", "AttachmentFileName");
  const depositSlipFileName = readString(apiReceipt, "depositSlipFileName", "DepositSlipFileName");

  return {
    id,
    receiptNumber: readString(apiReceipt, "receiptNumber", "ReceiptNumber"),
    requestId,
    requestNumber,
    requestor,
    returnAmount: readNumber(apiReceipt, "returnAmount", "ReturnAmount"),
    issuedAt: readOptionalDate(apiReceipt, "auditDate", "AuditDate") ?? new Date(),
    status: depositSlipFileName || isCustodianReturnReceipt ? "acknowledged" : "pending",
    attachmentFileName: attachmentFileName || undefined,
    attachmentDownloadUrl: attachmentFileName ? apiBaseUrl + "/api/cash-advance/cashier-receipts/" + id + "/attachment" : undefined,
    attachmentContentType: readString(apiReceipt, "attachmentContentType", "AttachmentContentType") || undefined,
    attachmentFileSize: readOptionalNumber(apiReceipt, "attachmentFileSizeBytes", "AttachmentFileSizeBytes"),
    depositSlipFileName: depositSlipFileName || undefined,
    depositSlipDownloadUrl: depositSlipFileName ? apiBaseUrl + "/api/cash-advance/cashier-receipts/" + id + "/deposit-slip" : undefined,
    depositSlipContentType: readString(apiReceipt, "depositSlipContentType", "DepositSlipContentType") || undefined,
    depositSlipFileSize: readOptionalNumber(apiReceipt, "depositSlipFileSizeBytes", "DepositSlipFileSizeBytes"),
    depositDate: readOptionalDate(apiReceipt, "depositDate", "DepositDate"),
    depositAmount: readOptionalNumber(apiReceipt, "depositAmount", "DepositAmount"),
    depositoryBank: readString(apiReceipt, "depositoryBank", "DepositoryBank") || undefined,
  };
};

const toHistoryEmployee = (apiHistory: ApiObject, fallbackDepartment: string): Employee | undefined => {
  const actorUserId = readOptionalNumber(apiHistory, "actorUserId", "ActorUserId");
  if (actorUserId == null) {
    return undefined;
  }

  const actorName = readString(apiHistory, "actorName", "ActorName", "System");
  return createApiEmployee(
    actorUserId,
    actorName,
    readString(apiHistory, "actorDepartment", "ActorDepartment", fallbackDepartment),
  );
};

const toHistoryEvent = (
  apiHistory: ApiObject,
  index: number,
  fallbackTimestamp: Date,
  fallbackDepartment: string,
) => ({
  id: String(readNumber(apiHistory, "historyId", "HistoryId", index)),
  timestamp: readOptionalDate(apiHistory, "auditDate", "AuditDate") ?? fallbackTimestamp,
  action: toTransactionAction(readString(apiHistory, "action", "Action")),
  fromEmployee: toHistoryEmployee(apiHistory, fallbackDepartment),
  amount: readOptionalNumber(apiHistory, "amount", "Amount"),
  notes: readString(apiHistory, "notes", "Notes") || undefined,
});

const toPendingTransfer = (apiRequest: ApiObject, fallbackDepartment: string, fallbackRequestId = "request") => {
  const toUserId = readOptionalNumber(apiRequest, "pendingTransferToUserId", "PendingTransferToUserId");
  const fromUserId = readOptionalNumber(apiRequest, "pendingTransferFromUserId", "PendingTransferFromUserId");
  const amount = readOptionalNumber(apiRequest, "pendingTransferAmount", "PendingTransferAmount");

  if (toUserId == null || fromUserId == null || amount == null) {
    return undefined;
  }

  const fromEmployee = createApiEmployee(
    fromUserId,
    readString(apiRequest, "pendingTransferFromName", "PendingTransferFromName", "Transferor"),
    readString(apiRequest, "pendingTransferFromDepartment", "PendingTransferFromDepartment", fallbackDepartment),
  );
  const toEmployee = createApiEmployee(
    toUserId,
    readString(apiRequest, "pendingTransferToName", "PendingTransferToName", "Receiver"),
    readString(apiRequest, "pendingTransferToDepartment", "PendingTransferToDepartment", fallbackDepartment),
  );

  return {
    id: readStringOrNumber(apiRequest, "pendingTransferId", "PendingTransferId", `${fallbackRequestId}-pending-transfer`),
    fromEmployee,
    toEmployee,
    amount,
    isWholeRequest: Boolean(readValue(apiRequest, "pendingTransferIsWholeRequest", "PendingTransferIsWholeRequest")),
    requestedAt: readOptionalDate(apiRequest, "pendingTransferRequestedAt", "PendingTransferRequestedAt") ?? new Date(),
    notes: readString(apiRequest, "pendingTransferNotes", "PendingTransferNotes") || undefined,
  };
};

const toPendingTransfers = (apiRequest: ApiObject, fallbackDepartment: string, fallbackRequestId: string) => {
  const pendingTransfers = readArray(apiRequest, "pendingTransfers", "PendingTransfers")
    .map((item, index): PendingTransfer | undefined => {
      const transfer = toPendingTransfer(item, fallbackDepartment, `${fallbackRequestId}-pending-transfer-${index + 1}`);
      return transfer ? { ...transfer, id: transfer.id || `${fallbackRequestId}-pending-transfer-${index + 1}` } : undefined;
    })
    .filter((item): item is PendingTransfer => item !== undefined);

  const singlePendingTransfer = toPendingTransfer(apiRequest, fallbackDepartment, `${fallbackRequestId}-pending-transfer`);
  return pendingTransfers.length > 0 ? pendingTransfers : singlePendingTransfer ? [singlePendingTransfer] : [];
};

const toTransferAllocation = (
  apiTransfer: ApiObject,
  fallbackDepartment: string,
  fallbackId: string,
): TransferAllocation | undefined => {
  const fromUserId = readOptionalNumber(apiTransfer, "transferFromUserId", "TransferFromUserId");
  const toUserId = readOptionalNumber(apiTransfer, "transferToUserId", "TransferToUserId");
  const amount = readOptionalNumber(apiTransfer, "transferAmount", "TransferAmount");

  if (fromUserId == null || toUserId == null || amount == null) {
    return undefined;
  }

  const transferId = readOptionalNumber(apiTransfer, "transferId", "TransferId");
  const fromEmployee = createApiEmployee(
    fromUserId,
    readString(apiTransfer, "transferFromName", "TransferFromName", "Transferor"),
    readString(apiTransfer, "transferFromDepartment", "TransferFromDepartment", fallbackDepartment),
  );
  const toEmployee = createApiEmployee(
    toUserId,
    readString(apiTransfer, "transferToName", "TransferToName", "Receiver"),
    readString(apiTransfer, "transferToDepartment", "TransferToDepartment", fallbackDepartment),
  );

  return {
    id: transferId == null ? fallbackId : String(transferId),
    fromEmployee,
    toEmployee,
    amount,
    isWholeRequest: Boolean(readValue(apiTransfer, "transferIsWholeRequest", "TransferIsWholeRequest")),
    status: toTransferAllocationStatus(readString(apiTransfer, "transferStatus", "TransferStatus", "pending")),
    requestedAt: readOptionalDate(apiTransfer, "transferRequestedAt", "TransferRequestedAt") ?? new Date(),
    respondedAt: readOptionalDate(apiTransfer, "transferRespondedAt", "TransferRespondedAt"),
    notes: readString(apiTransfer, "transferNotes", "TransferNotes") || undefined,
    responseNotes: readString(apiTransfer, "transferResponseNotes", "TransferResponseNotes") || undefined,
  };
};

const toTransferAllocations = (
  apiRequest: ApiObject,
  fallbackDepartment: string,
  fallbackRequestId: string,
): TransferAllocation[] =>
  readArray(apiRequest, "transferAllocations", "TransferAllocations")
    .map((item, index) => toTransferAllocation(item, fallbackDepartment, `${fallbackRequestId}-transfer-${index + 1}`))
    .filter((item): item is TransferAllocation => item !== undefined);

const toCashAdvanceRequest = (apiRequest: ApiObject): CashAdvanceRequest => {
  const requestId = readNumber(apiRequest, "cashAdvanceRequestId", "CashAdvanceRequestId");
  const id = String(requestId);
  const amount = readNumber(apiRequest, "amount", "Amount");
  const amountSpent = readOptionalNumber(apiRequest, "amountSpent", "AmountSpent");
  const returnAmount = readOptionalNumber(apiRequest, "returnAmount", "ReturnAmount");
  const excessAmount = readOptionalNumber(apiRequest, "excessAmount", "ExcessAmount");
  const department = readString(apiRequest, "department", "Department");
  const status = toCashAdvanceStatus(readString(apiRequest, "status", "Status"));
  const requestType = toCashAdvanceRequestType(readString(apiRequest, "requestType", "RequestType", "cash_advance"));
  const requestNumber = readString(apiRequest, "requestNumber", "RequestNumber", id);
  const referenceNumber = readString(apiRequest, "rfpRequestNumber", "RfpRequestNumber") || requestNumber;
  const payeeUserId = readNumber(apiRequest, "payeeUserId", "PayeeUserId");
  const originalRequestId = readOptionalNumber(
    apiRequest,
    "originalCashAdvanceRequestId",
    "OriginalCashAdvanceRequestId",
  );
  const requestor = createApiEmployee(
    readNumber(apiRequest, "requestorUserId", "RequestorUserId"),
    readString(apiRequest, "requestorName", "RequestorName", "Requestor"),
    department,
  );
  const currentOwner = createApiEmployee(
    readNumber(apiRequest, "currentOwnerUserId", "CurrentOwnerUserId", Number(requestor.id)),
    readString(apiRequest, "currentOwnerName", "CurrentOwnerName", requestor.name),
    readString(apiRequest, "currentOwnerDepartment", "CurrentOwnerDepartment", department),
  );
  const custodianUserId = readOptionalNumber(apiRequest, "custodianUserId", "CustodianUserId");
  const custodian =
    custodianUserId == null
      ? undefined
      : createApiEmployee(
          custodianUserId,
          readString(apiRequest, "custodianName", "CustodianName", "Custodian"),
          readString(apiRequest, "custodianDepartment", "CustodianDepartment", "Accounting"),
        );
  const createdAt = readOptionalDate(apiRequest, "auditDate", "AuditDate") ?? new Date();
  const updatedAt =
    readOptionalDate(apiRequest, "updatedAt", "UpdatedAt") ??
    readOptionalDate(apiRequest, "liquidatedAt", "LiquidatedAt") ??
    createdAt;
  const remainingAmount =
    readOptionalNumber(apiRequest, "remainingAmount", "RemainingAmount") ??
    (status === "pending_liquidation" ? amount : Math.max(amount - (amountSpent ?? 0), 0));
  const attachments = readArray(apiRequest, "attachments", "Attachments").map(toAttachment);
  const receiptDetails = readArray(apiRequest, "receiptDetails", "ReceiptDetails").map(toReceiptDetail);
  const pettyCashReceiptDetails = readArray(apiRequest, "pettyCashReceiptDetails", "PettyCashReceiptDetails").map(
    toPettyCashReceiptDetail,
  );
  const pettyCashTransportationDetails = readArray(
    apiRequest,
    "pettyCashTransportationDetails",
    "PettyCashTransportationDetails",
  ).map(toPettyCashTransportationDetail);
  const apiHistory = readArray(apiRequest, "history", "History").map((historyItem, index) =>
    toHistoryEvent(historyItem, index, updatedAt, department),
  );
  const pendingTransfers = toPendingTransfers(apiRequest, department, id);
  const transferAllocations = toTransferAllocations(apiRequest, department, id);
  const pendingTransfer = pendingTransfers[0];
  const acknowledgementReceipt = toAcknowledgementReceipt(
    readObject(apiRequest, "acknowledgementReceipt", "AcknowledgementReceipt"),
    id,
    requestNumber,
    requestor,
    requestType === "petty_cash" || requestType === "petty_cash_advance",
  );
  const liquidatedAmount =
    amountSpent == null
      ? 0
      : Math.min(
          amount,
          amountSpent + (acknowledgementReceipt?.status === "acknowledged" ? returnAmount ?? 0 : 0),
        );

  return {
    id,
    originalRequestId: originalRequestId == null ? undefined : String(originalRequestId),
    requestNumber,
    referenceNumber,
    payeeUserId: payeeUserId > 0 ? String(payeeUserId) : undefined,
    printToken: readString(apiRequest, "printToken", "PrintToken"),
    requestType,
    cvNumber: readString(apiRequest, "cvNumber", "CvNumber") || undefined,
    companyId:
      readOptionalNumber(apiRequest, "companyId", "CompanyId") ??
      readOptionalNumber(apiRequest, "companyID", "CompanyID") ??
      undefined,
    companyCode: readString(apiRequest, "companyCode", "CompanyCode") || undefined,
    amount,
    remainingAmount,
    liquidatedAmount,
    purpose: readString(apiRequest, "purpose", "Purpose"),
    sourceSystem:
      readString(apiRequest, "sourceSystem", "SourceSystem") ||
      (requestType === "cash_advance" || requestType === "petty_cash_replenishment" ? "RFP System" : "Petty Cash"),
    createdAt,
    status,
    custodian,
    requestorDepartmentApproverName:
      readString(apiRequest, "requestorDepartmentApproverName", "RequestorDepartmentApproverName") || undefined,
    currentOwner,
    originalOwner: requestor,
    department,
    liquidationAmount: amountSpent,
    attachmentNames: attachments.map((attachment) => attachment.fileName),
    attachments,
    receiptDetails,
    pettyCashReceiptDetails,
    pettyCashTransportationDetails,
    returnAmount,
    excessAmount,
    acknowledgementReceipt,
    pendingTransfer,
    pendingTransfers,
    transferAllocations,
    rfpDecision: readString(apiRequest, "rfpDecision", "RfpDecision") === "waive" ? "waive" : readString(apiRequest, "rfpDecision", "RfpDecision") === "create" ? "create" : undefined,
    rfpWaiveReason: readString(apiRequest, "rfpWaiveReason", "RfpWaiveReason") || undefined,
    history:
      apiHistory.length > 0
        ? apiHistory
        : [
            {
              id: "api-history-" + requestId + "-" + status,
              timestamp: updatedAt,
              action: statusToHistoryAction(status),
              fromEmployee: currentOwner,
              amount: amountSpent ?? amount,
              notes: "Loaded from FundManagementAPI.",
            },
          ],
    dueDate: readOptionalDate(apiRequest, "dueDate", "DueDate") ?? addDays(createdAt, 10),
  };
};

export const fetchApiReceiptDocumentNumber = async (): Promise<string> => {
  const result = await apiFetch<{ docNo: string }>("/api/cash-advance/receipt-document-number", { cache: "no-store" });
  if (!result.docNo?.trim()) throw new Error("Document control did not return a receipt number.");
  return result.docNo;
};

const apiFetch = async <T>(path: string, init?: RequestInit): Promise<T> => {
  const isFormData = init?.body instanceof FormData;
  const response = await fetch(apiBaseUrl + path, {
    credentials: "include",
    ...init,
    headers: isFormData
      ? init?.headers
      : {
          "Content-Type": "application/json",
          ...init?.headers,
        },
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || "API request failed with status " + response.status + ".");
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
};

const readFileNameFromContentDisposition = (contentDisposition: string | null): string | undefined => {
  if (!contentDisposition) {
    return undefined;
  }

  const utf8FileName = contentDisposition.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
  if (utf8FileName) {
    return decodeURIComponent(utf8FileName.replaceAll("\"", ""));
  }

  return contentDisposition.match(/filename="?([^";]+)"?/i)?.[1];
};

const downloadBlob = (blob: Blob, fileName: string) => {
  if (typeof window === "undefined") {
    return;
  }

  const objectUrl = window.URL.createObjectURL(blob);
  const link = document.createElement("a");

  try {
    link.href = objectUrl;
    link.download = fileName;
    document.body.appendChild(link);
    link.click();
  } finally {
    link.remove();
    window.URL.revokeObjectURL(objectUrl);
  }
};

export const fetchApiUsers = async (): Promise<AppUser[]> => {
  const users = await apiFetch<ApiObject[]>("/api/auth/users");
  return users.map(toAppUser);
};

export const fetchApiDepartmentCustodians = async (): Promise<DepartmentCustodianAssignment[]> => {
  const assignments = await apiFetch<ApiObject[]>("/api/auth/department-custodians");
  return assignments.map(toDepartmentCustodianAssignment);
};

export const updateApiDepartmentCustodian = async (
  adminUserId: string,
  departmentCode: string,
  custodianUserId: string,
): Promise<DepartmentCustodianAssignment> => {
  const response = await apiFetch<ApiObject>("/api/auth/departments/" + departmentCode + "/custodian", {
    method: "PUT",
    body: JSON.stringify({
      adminUserId: Number(adminUserId),
      custodianUserId: Number(custodianUserId),
    }),
  });

  return toDepartmentCustodianAssignment(response);
};

export const createApiUser = async (adminUserId: string, user: CreateAppUserInput): Promise<AppUser> => {
  const response = await apiFetch<ApiObject>("/api/auth/users", {
    method: "POST",
    body: JSON.stringify({
      adminUserId: Number(adminUserId),
      username: user.username,
      password: user.password,
      displayName: user.displayName,
      department: user.department,
      role: user.role,
      title: user.title,
      pettyCashFundAmount: user.role === "custodian" ? user.pettyCashFundAmount : undefined,
    }),
  });

  return toAppUser(response);
};

export const updateApiUser = async (
  adminUserId: string,
  userId: string,
  user: UpdateAppUserInput,
): Promise<AppUser> => {
  const response = await apiFetch<ApiObject>("/api/auth/users/" + userId, {
    method: "PUT",
    body: JSON.stringify({
      adminUserId: Number(adminUserId),
      username: user.username,
      displayName: user.displayName,
      department: user.department,
      role: user.role,
      title: user.title,
      password: user.password,
      pettyCashFundAmount: user.role === "custodian" ? user.pettyCashFundAmount : undefined,
    }),
  });

  return toAppUser(response);
};

export const updateApiCustodianFund = async (
  adminUserId: string,
  userId: string,
  pettyCashFundAmount: number,
): Promise<AppUser> => {
  const response = await apiFetch<ApiObject>("/api/auth/users/" + userId + "/custodian-fund", {
    method: "PUT",
    body: JSON.stringify({
      adminUserId: Number(adminUserId),
      pettyCashFundAmount,
    }),
  });

  return toAppUser(response);
};

export const fetchApiSession = async (): Promise<AppUser | null> => {
  const response = await fetch(apiBaseUrl + "/api/auth/session", { credentials: "include", cache: "no-store" });
  if (response.status === 401 || response.status === 404) return null;
  if (!response.ok) throw new Error("Unable to validate the SSO session.");
  const data = (await response.json()) as ApiObject;
  const user = readValue(data, "user", "User");
  return user && typeof user === "object" ? toAppUser(user as ApiObject) : null;
};

export const loginApiUser = async (username: string, password: string): Promise<AppUser> => {
  const response = await apiFetch<ApiObject>("/api/auth/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
  const apiUser = readValue(response, "user", "User");

  if (!apiUser || typeof apiUser !== "object") {
    throw new Error("The API login response did not include a user.");
  }

  return toAppUser(apiUser as ApiObject);
};

export const fetchApiRequests = async (user: AppUser): Promise<CashAdvanceRequest[]> => {
  const params = new URLSearchParams({
    userId: user.id,
    role: user.role,
    department: user.department,
  });
  const requests = await apiFetch<ApiObject[]>("/api/cash-advance?" + params.toString());
  return requests.map(toCashAdvanceRequest);
};

export const fetchApiApprovalHistory = async (user: AppUser): Promise<CashAdvanceRequest[]> => {
  const params = new URLSearchParams({
    userId: user.id,
    role: user.role,
    department: user.department,
  });
  const requests = await apiFetch<ApiObject[]>("/api/cash-advance/approval-history?" + params.toString());
  return requests.map(toCashAdvanceRequest);
};

export const downloadApiAccountingReport = async (
  user: AppUser,
  period: AccountingReportPeriod,
): Promise<void> => {
  const params = new URLSearchParams({
    userId: user.id,
    role: user.role,
    periodMode: period.mode,
  });

  if (period.mode === "month") {
    params.set("month", period.month);
  }

  if (period.mode === "year") {
    params.set("year", period.year);
  }

  if (period.mode === "range") {
    params.set("from", period.from);
    params.set("to", period.to);
  }

  const response = await fetch(apiBaseUrl + "/api/cash-advance/accounting-report?" + params.toString(), { credentials: "include" });
  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || "Unable to generate the accounting report.");
  }

  const blob = await response.blob();
  const fileName = readFileNameFromContentDisposition(response.headers.get("content-disposition")) ?? "AccountingReport.xls";
  downloadBlob(blob, fileName);
};

const toBusinessPartner = (apiPartner: ApiObject): BusinessPartner => ({
  bpCode:
    readString(apiPartner, "bpCode", "BpCode") ||
    readString(apiPartner, "bP_Code", "BP_Code") ||
    readString(apiPartner, "code", "Code"),
  bpName:
    readString(apiPartner, "bpName", "BpName") ||
    readString(apiPartner, "bP_Name", "BP_Name") ||
    readString(apiPartner, "name", "Name"),
});

export const fetchApiBusinessPartners = async (companyId?: number): Promise<BusinessPartner[]> => {
  const query = companyId ? "?companyId=" + encodeURIComponent(String(companyId)) : "";
  const partners = await apiFetch<ApiObject[]>("/api/cash-advance/business-partners" + query);
  return partners.map(toBusinessPartner).filter((partner) => partner.bpCode && partner.bpName);
};

const toCompanyReference = (apiCompany: ApiObject): CompanyReference => ({
  id: readOptionalNumber(apiCompany, "companyId", "CompanyId") ?? readOptionalNumber(apiCompany, "id", "ID"),
  name: readString(apiCompany, "name", "Name"),
});

export const fetchApiCompanies = async (): Promise<CompanyReference[]> => {
  const seen = new Set<string>();
  const companies = await apiFetch<ApiObject[]>("/api/cash-advance/companies");

  return companies
    .map(toCompanyReference)
    .filter((company) => {
      const normalizedName = company.name.trim();
      const normalizedKey =
        company.id === undefined ? "name:" + normalizedName.toLocaleLowerCase() : "id:" + String(company.id);
      if (!normalizedName || seen.has(normalizedKey)) {
        return false;
      }

      seen.add(normalizedKey);
      return true;
    });
};

const toProjectReference = (apiProject: ApiObject): ProjectReference => ({
  projCode: readString(apiProject, "projCode", "ProjCode") || readString(apiProject, "code", "Code"),
  projName: readString(apiProject, "projName", "ProjName") || readString(apiProject, "name", "Name"),
});

export const fetchApiProjects = async (companyId?: number): Promise<ProjectReference[]> => {
  const query = companyId ? "?companyId=" + encodeURIComponent(String(companyId)) : "";
  const projects = await apiFetch<ApiObject[]>("/api/cash-advance/projects" + query);
  return projects.map(toProjectReference).filter((project) => project.projCode && project.projName);
};

const toProfitCenterReference = (apiProfitCenter: ApiObject): ProfitCenterReference => ({
  ocrCode: readString(apiProfitCenter, "ocrCode", "OcrCode") || readString(apiProfitCenter, "code", "Code"),
  ocrName: readString(apiProfitCenter, "ocrName", "OcrName") || readString(apiProfitCenter, "name", "Name"),
});

export const fetchApiProfitCenters = async (companyId?: number): Promise<ProfitCenterReference[]> => {
  const query = companyId ? "?companyId=" + encodeURIComponent(String(companyId)) : "";
  const profitCenters = await apiFetch<ApiObject[]>("/api/cash-advance/profit-centers" + query);
  return profitCenters
    .map(toProfitCenterReference)
    .filter((profitCenter) => profitCenter.ocrCode && profitCenter.ocrName);
};

const toExpenseTypeReference = (apiExpenseType: ApiObject): ExpenseTypeReference => ({
  expenseCode: readString(apiExpenseType, "expenseCode", "ExpenseCode"),
  expenseName: readString(apiExpenseType, "expenseName", "ExpenseName"),
});

export const fetchApiExpenseTypes = async (): Promise<ExpenseTypeReference[]> => {
  const expenseTypes = await apiFetch<ApiObject[]>("/api/cash-advance/expense-types");
  return expenseTypes
    .map(toExpenseTypeReference)
    .filter((expenseType) => expenseType.expenseCode && expenseType.expenseName);
};

export const getApiRequestPrintUrl = (request: CashAdvanceRequest, user: AppUser): string => {
  const printToken = request.printToken?.trim();
  if (!printToken) {
    throw new Error("This request is not available to print yet.");
  }

  const params = new URLSearchParams({
    userId: user.id,
    role: user.role,
    department: user.department,
  });

  return apiBaseUrl + "/api/cash-advance/" + encodeURIComponent(printToken) + "/print?" + params.toString();
};

export const submitApiLiquidation = (
  requestId: string,
  userId: string,
  amountSpent: number,
  notes: string,
  receiptDetails: CashAdvanceReceiptDetail[],
  pettyCashReceiptDetails: PettyCashReceiptDetail[],
  pettyCashTransportationDetails: PettyCashTransportationDetail[],
  attachments: File[],
  replaceExistingAttachments: boolean,
): Promise<void> => {
  const formData = new FormData();
  formData.append("UserId", userId);
  formData.append("AmountSpent", String(amountSpent));
  formData.append("Notes", notes);
  formData.append("ReceiptDetailsJson", toApiReceiptDetailsJson(receiptDetails));
  formData.append("PettyCashReceiptDetailsJson", JSON.stringify(toApiPettyCashReceiptDetails(pettyCashReceiptDetails)));
  formData.append(
    "PettyCashTransportationDetailsJson",
    JSON.stringify(toApiPettyCashTransportationDetails(pettyCashTransportationDetails)),
  );
  formData.append("ReplaceExistingAttachments", String(replaceExistingAttachments));
  attachments.forEach((attachment) => formData.append("Attachments", attachment));

  return apiFetch<void>("/api/cash-advance/" + requestId + "/liquidation", {
    method: "POST",
    body: formData,
  });
};

export const submitApiRfpAttachment = (
  requestId: string,
  notes: string,
  attachments: File[],
): Promise<void> => {
  const formData = new FormData();
  formData.append("Notes", notes);
  attachments.forEach((attachment) => formData.append("Attachments", attachment));

  return apiFetch<void>("/api/cash-advance/" + requestId + "/rfp-attachment", {
    method: "POST",
    body: formData,
  });
};

export const transferApiCashAdvance = (
  requestId: string,
  toUserId: string,
  amount: number,
  transferWholeRequest: boolean,
  notes: string,
): Promise<void> =>
  apiFetch<void>("/api/cash-advance/" + requestId + "/transfer", {
    method: "POST",
    body: JSON.stringify({
      toUserId: Number(toUserId),
      amount,
      transferWholeRequest,
      notes,
    }),
  });

export const respondApiTransfer = (
  requestId: string,
  receiverUserId: string,
  accepted: boolean,
  notes: string,
  transferId?: string,
): Promise<void> =>
  apiFetch<void>("/api/cash-advance/" + requestId + "/transfer-response", {
    method: "POST",
    body: JSON.stringify({
      transferId,
      receiverUserId: Number(receiverUserId),
      accepted,
      notes,
    }),
  });

export const decideApiDepartment = (
  requestId: string,
  userId: string,
  approved: boolean,
  notes: string,
  rfpDecision?: "create" | "waive",
  companyId?: number,
): Promise<void> =>
  apiFetch<void>("/api/cash-advance/" + requestId + "/department-decision", {
    method: "POST",
    body: JSON.stringify({ userId: Number(userId), approved, notes, rfpDecision, companyId }),
  });

export const createApiPettyCashRequest = (
  requestType: CashAdvanceRequestType,
  requestorUserId: string,
  custodianUserId: string,
  amount: number,
  purpose: string,
  pettyCashReceiptDetails: PettyCashReceiptDetail[],
  pettyCashTransportationDetails: PettyCashTransportationDetail[],
  attachment: File | null,
  companyId?: number,
): Promise<void> => {
  const formData = new FormData();
  if (companyId !== undefined) formData.append("CompanyId", String(companyId));
  formData.append("RequestType", requestType);
  formData.append("RequestorUserId", requestorUserId);
  formData.append("CustodianUserId", custodianUserId);
  formData.append("Amount", String(amount));
  formData.append("Purpose", purpose);
  formData.append("PettyCashReceiptDetailsJson", JSON.stringify(toApiPettyCashReceiptDetails(pettyCashReceiptDetails)));
  formData.append(
    "PettyCashTransportationDetailsJson",
    JSON.stringify(toApiPettyCashTransportationDetails(pettyCashTransportationDetails)),
  );

  if (attachment) {
    formData.append("Attachments", attachment);
  }

  return apiFetch<void>("/api/cash-advance/petty-cash", {
    method: "POST",
    body: formData,
  });
};

export const decideApiCustodian = (
  requestId: string,
  userId: string,
  approved: boolean,
  notes: string,
  returnedAmount?: number,
): Promise<void> =>
  apiFetch<void>("/api/cash-advance/" + requestId + "/custodian-decision", {
    method: "POST",
    body: JSON.stringify({ userId: Number(userId), approved, notes, returnedAmount }),
  });

export const createApiPettyCashReplenishment = (
  custodianUserId: string,
  amount: number,
  notes: string,
): Promise<void> =>
  apiFetch<void>("/api/cash-advance/petty-cash/replenishment", {
    method: "POST",
    body: JSON.stringify({
      custodianUserId: Number(custodianUserId),
      amount,
      notes,
    }),
  });

export const submitApiPettyCashReplenishmentCv = (
  requestId: string,
  custodianUserId: string,
  cvNumber: string,
): Promise<void> =>
  apiFetch<void>("/api/cash-advance/" + requestId + "/petty-cash/replenishment-cv", {
    method: "POST",
    body: JSON.stringify({
      custodianUserId: Number(custodianUserId),
      cvNumber,
    }),
  });

export const createApiCashierReceipt = (
  requestId: string,
  cashierUserId: string,
  receiptNumber: string,
  depositSlipAttachment: File | null,
  depositDate: string,
  depositAmount: number,
  depositoryBank: string,
  notes: string,
): Promise<void> => {
  const formData = new FormData();
  formData.append("CashierUserId", cashierUserId);
  formData.append("ReceiptNumber", receiptNumber);
  if (depositSlipAttachment) {
    formData.append("DepositSlip", depositSlipAttachment);
  }
  if (depositDate) {
    formData.append("DepositDate", depositDate);
  }
  if (depositAmount > 0) {
    formData.append("DepositAmount", String(depositAmount));
  }
  if (depositoryBank) {
    formData.append("DepositoryBank", depositoryBank);
  }
  formData.append("Notes", notes);

  return apiFetch<void>("/api/cash-advance/" + requestId + "/cashier-receipt", {
    method: "POST",
    body: formData,
  });
};

export const createApiCustodianReceipt = (
  requestId: string,
  custodianUserId: string,
  receiptNumber: string,
  notes: string,
): Promise<void> => {
  const formData = new FormData();
  formData.append("CustodianUserId", custodianUserId);
  formData.append("ReceiptNumber", receiptNumber);
  formData.append("Notes", notes);

  return apiFetch<void>("/api/cash-advance/" + requestId + "/custodian-receipt", {
    method: "POST",
    body: formData,
  });
};

export const closeApiCashierLiquidation = (requestId: string, userId: string, notes: string): Promise<void> =>
  apiFetch<void>("/api/cash-advance/" + requestId + "/cashier-closure", {
    method: "POST",
    body: JSON.stringify({ userId: Number(userId), approved: true, notes }),
  });

export const decideApiAccounting = (requestId: string, userId: string, approved: boolean, notes: string): Promise<void> =>
  apiFetch<void>("/api/cash-advance/" + requestId + "/accounting-decision", {
    method: "POST",
    body: JSON.stringify({ userId: Number(userId), approved, notes }),
  });
