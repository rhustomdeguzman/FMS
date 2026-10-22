import type { AppUser, CashAdvanceRequest, DashboardTab, UserRole } from "../types/CashAdvance";
import { isPettyCashWorkflowRequest } from "../pettyCash";

export const roleLabels: Record<UserRole, string> = {
  admin: "Admin",
  requestor: "Requestor",
  department_head: "Department Head",
  accounting: "Accounting",
  cashier: "Cashier",
  custodian: "Custodian",
};

export const roleDescriptions: Record<UserRole, string> = {
  admin: "Manage users, roles, custodian funds, and view all workflow tabs.",
  requestor: "Create, track, transfer, and liquidate your assigned cash advances.",
  department_head: "Approve liquidations, claim RFP cash advance custody, and choose Create RFP or Waive RFP for overspent excess.",
  accounting: "Check department-approved liquidations and close the original cash advance amount.",
  cashier: "Attach returned-cash receipts and close liquidations after accounting approval.",
  custodian: "Release petty cash, review petty cash liquidations, and create replenishment RFP requests.",
};

export const tabLabels: Record<DashboardTab, string> = {
  dashboard: "Dashboard",
  "my-requests": "For Liquidation",
  "department-review": "Department Review",
  "approval-history": "Approval History",
  accounting: "Accounting",
  "all-requests": "All Requests",
  cashier: "Cashier",
  custodian: "Custodian",
  admin: "Admin",
};

export const tabIcons: Record<DashboardTab, string> = {
  dashboard: "M3 13h8V3H3v10Zm0 8h8v-6H3v6Zm10 0h8V11h-8v10Zm0-18v6h8V3h-8Z",
  "my-requests": "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm3 5h8M8 12h8M8 16h5",
  "department-review": "M12 3 3 8l9 5 9-5-9-5Zm-7 9 7 4 7-4M5 16l7 4 7-4",
  "approval-history": "M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11",
  accounting: "M4 4h16v4H4V4Zm0 7h16v9H4v-9Zm4 3h2m3 0h3M8 17h2m3 0h3",
  "all-requests": "M4 6h16M4 12h16M4 18h16",
  cashier: "M5 7h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2Zm0 4h16M7 15h3",
  custodian: "M12 3 4 7v5c0 4.4 3.2 8.2 8 9 4.8-.8 8-4.6 8-9V7l-8-4Zm-3 9h6m-6 4h6",
  admin: "M12 3l8 4v5c0 4.4-3.2 8.2-8 9-4.8-.8-8-4.6-8-9V7l8-4Zm0 5v8m-4-4h8",
};

export const getAllowedTabs = (role: UserRole): DashboardTab[] => {
  if (role === "admin") {
    return [
      "dashboard",
      "my-requests",
      "department-review",
      "approval-history",
      "accounting",
      "all-requests",
      "cashier",
      "custodian",
      "admin",
    ];
  }

  if (role === "requestor") {
    return ["dashboard", "my-requests"];
  }

  if (role === "department_head") {
    return ["dashboard", "my-requests", "department-review", "approval-history", "all-requests"];
  }

  if (role === "accounting") {
    return ["dashboard", "accounting", "approval-history"];
  }

  if (role === "custodian") {
    return ["dashboard", "custodian", "approval-history", "all-requests"];
  }

  return ["dashboard", "cashier", "approval-history"];
};

export const getVisibleRequests = (requests: CashAdvanceRequest[], user: AppUser): CashAdvanceRequest[] => {
  const isPendingTransferReceiver = (request: CashAdvanceRequest) =>
    (request.pendingTransfers ?? (request.pendingTransfer ? [request.pendingTransfer] : [])).some(
      (transfer) => transfer.toEmployee.id === user.id,
    );

  if (user.role === "admin") {
    return requests;
  }

  if (user.role === "requestor") {
    return requests.filter(
      (request) =>
        request.currentOwner.id === user.id ||
        request.originalOwner.id === user.id ||
        isPendingTransferReceiver(request),
    );
  }

  if (user.role === "department_head") {
    return requests.filter(
      (request) =>
        request.currentOwner.id === user.id ||
        request.department === user.department ||
        isPendingTransferReceiver(request),
    );
  }

  if (user.role === "cashier") {
    return requests.filter(
      (request) =>
        isPendingTransferReceiver(request) ||
        request.status === "pending_cashier_return" ||
        request.status === "pending_cashier_closure" ||
        (!isPettyCashWorkflowRequest(request) && request.acknowledgementReceipt?.status === "acknowledged"),
    );
  }

  if (user.role === "custodian") {
    return requests.filter(
      (request) =>
        request.custodian?.id === user.id ||
        request.currentOwner.id === user.id ||
        request.originalOwner.id === user.id,
    );
  }

  return requests;
};

