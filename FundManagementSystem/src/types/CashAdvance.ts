export type UserRole = "admin" | "requestor" | "department_head" | "accounting" | "cashier" | "custodian";

export type DataMode = "demo" | "live";

export type RfpDecision = "create" | "waive";

export type AccountingReportPeriod =
  | { mode: "all" }
  | { mode: "month"; month: string }
  | { mode: "year"; year: string }
  | { mode: "range"; from: string; to: string };

export type DashboardTab =
  | "dashboard"
  | "my-requests"
  | "department-review"
  | "approval-history"
  | "accounting"
  | "all-requests"
  | "cashier"
  | "custodian"
  | "admin";

export interface Employee {
  id: string;
  name: string;
  department: string;
  departmentCode?: number;
  departmentGroups?: number[];
  avatar: string;
  pettyCashFundAmount?: number;
}

export interface AppUser extends Employee {
  username: string;
  title: string;
  role: UserRole;
  roleCode?: number;
}

export interface DepartmentCustodianAssignment {
  departmentCode: string;
  departmentName: string;
  custodianUserId?: string;
  custodianName?: string;
  custodianDepartment?: string;
  custodianFundAmount?: number;
}

export interface CreateAppUserInput {
  username: string;
  password: string;
  displayName: string;
  department: string;
  role: UserRole;
  title: string;
  pettyCashFundAmount?: number;
}

export interface UpdateAppUserInput {
  username: string;
  displayName: string;
  department: string;
  role: UserRole;
  title: string;
  password?: string;
  pettyCashFundAmount?: number;
}

export type CashAdvanceRequestType = "cash_advance" | "petty_cash" | "petty_cash_advance" | "petty_cash_replenishment";

export type TransactionAction =
  | "created"
  | "approved_by_department_head"
  | "approved_by_accounting"
  | "liquidation_submitted"
  | "sent_to_accounting"
  | "returned"
  | "rejected"
  | "transfer_requested"
  | "transfer_acknowledged"
  | "transfer_denied"
  | "transferred"
  | "partially_liquidated"
  | "fully_liquidated"
  | "excess_created"
  | "rfp_created"
  | "rfp_waived"
  | "rfp_attachment_uploaded"
  | "return_to_cashier"
  | "acknowledged"
  | "petty_cash_requested"
  | "approved_by_custodian"
  | "petty_cash_released"
  | "petty_cash_replenishment_created"
  | "petty_cash_replenished";

export interface TransactionHistory {
  id: string;
  timestamp: Date;
  action: TransactionAction;
  fromEmployee?: Employee;
  toEmployee?: Employee;
  amount?: number;
  notes?: string;
}

export interface AttachmentMeta {
  id: string;
  fileName: string;
  downloadUrl?: string;
  contentType?: string;
  fileSize?: number;
}

export interface CashAdvanceReceiptDetail {
  id: string;
  vendorCode?: string;
  vendor: string;
  description: string;
  projectCode?: string;
  project: string;
  profitCenterCode?: string;
  profitCenter: string;
  amount: number;
  invoiceRef: string;
  expenseTypeCode?: string;
  expenseType: string;
  createdAt?: Date;
}

export interface PettyCashReceiptDetail {
  id: string;
  orNumber: string;
  company: string;
  tin: string;
  address: string;
  natureOfExpenseCode?: string;
  natureOfExpense: string;
  costCenterCode?: string;
  costCenter: string;
  taxType?: string;
  amount: number;
  orDate: string;
}

export interface PettyCashTransportationDetail {
  id: string;
  description: string;
  from: string;
  to: string;
  transactionDate: string;
  amount: number;
}

export interface BusinessPartner {
  bpCode: string;
  bpName: string;
}

export interface CompanyReference {
  id?: number;
  name: string;
}

export interface ProjectReference {
  projCode: string;
  projName: string;
}

export interface ProfitCenterReference {
  ocrCode: string;
  ocrName: string;
}

export interface ExpenseTypeReference {
  expenseCode: string;
  expenseName: string;
}

export interface AcknowledgementReceipt {
  id?: string;
  receiptNumber: string;
  requestId: string;
  requestNumber: string;
  requestor: Employee;
  returnAmount: number;
  issuedAt: Date;
  acknowledgedBy?: Employee;
  acknowledgedAt?: Date;
  status: "pending" | "acknowledged";
  attachmentFileName?: string;
  attachmentDownloadUrl?: string;
  attachmentContentType?: string;
  attachmentFileSize?: number;
  depositSlipFileName?: string;
  depositSlipDownloadUrl?: string;
  depositSlipContentType?: string;
  depositSlipFileSize?: number;
  depositDate?: Date;
  depositAmount?: number;
  depositoryBank?: string;
  notes?: string;
}

export interface PendingTransfer {
  id: string;
  fromEmployee: Employee;
  toEmployee: Employee;
  amount: number;
  isWholeRequest: boolean;
  requestedAt: Date;
  notes?: string;
}

export type TransferAllocationStatus = "acknowledged" | "pending" | "denied";

export interface TransferAllocation {
  id: string;
  fromEmployee: Employee;
  toEmployee: Employee;
  amount: number;
  isWholeRequest: boolean;
  status: TransferAllocationStatus;
  requestedAt: Date;
  respondedAt?: Date;
  notes?: string;
  responseNotes?: string;
}

export type CashAdvanceStatus =
  | "pending_liquidation"
  | "pending_department_approval"
  | "pending_cashier_return"
  | "pending_cashier_closure"
  | "pending_accounting_review"
  | "pending_rfp_department_approval"
  | "pending_rfp_attachment"
  | "pending_custodian_approval"
  | "pending_custodian_liquidation_review"
  | "partially_liquidated"
  | "fully_liquidated"
  | "transferred"
  | "rfp_created"
  | "pending_replenishment"
  | "replenished"
  | "rejected";

export interface CashAdvanceRequest {
  id: string;
  originalRequestId?: string;
  requestNumber: string;
  referenceNumber?: string;
  printToken?: string;
  requestType?: CashAdvanceRequestType;
  companyId?: number;
  companyCode?: string;
  amount: number;
  remainingAmount: number;
  liquidatedAmount: number;
  purpose: string;
  sourceSystem: string;
  createdAt: Date;
  status: CashAdvanceStatus;
  requestorDepartmentApproverName?: string;
  custodian?: Employee;
  currentOwner: Employee;
  payeeUserId?: string;
  originalOwner: Employee;
  department: string;
  history: TransactionHistory[];
  dueDate: Date;
  liquidationAmount?: number;
  liquidationNotes?: string;
  attachmentNames?: string[];
  attachments?: AttachmentMeta[];
  receiptDetails?: CashAdvanceReceiptDetail[];
  pettyCashReceiptDetails?: PettyCashReceiptDetail[];
  pettyCashTransportationDetails?: PettyCashTransportationDetail[];
  returnAmount?: number;
  excessAmount?: number;
  acknowledgementReceipt?: AcknowledgementReceipt;
  pendingTransfer?: PendingTransfer;
  pendingTransfers?: PendingTransfer[];
  transferAllocations?: TransferAllocation[];
  excessRFPId?: string;
  rfpDecision?: RfpDecision;
  rfpWaiveReason?: string;
  cvNumber?: string;
}

export interface DashboardMetrics {
  pendingLiquidation: number;
  partialLiquidation: number;
  pendingDepartmentApproval: number;
  pendingRfpDepartmentApproval: number;
  pendingAccountingReview: number;
  pendingCashierReturn: number;
  totalPendingAmount: number;
  totalRequests: number;
}

export interface CustodianFundSummary {
  custodian: Employee;
  fundAmount: number;
  usedAmount: number;
  availableAmount: number;
  pendingRequestAmount: number;
  replenishmentRequestedAmount: number;
}
