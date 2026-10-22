import { useCallback, useEffect, useState } from "react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import LoginPage from "./components/login/LoginPage";
import { demoPassword, generateInitialRequests, users as demoUsers } from "./data/mockData";
import Dashboard from "./Pages/Dashboard";
import {
  closeApiCashierLiquidation,
  createApiUser,
  createApiPettyCashReplenishment,
  createApiPettyCashRequest,
  createApiCashierReceipt,
  createApiCustodianReceipt,
  decideApiCustodian,
  decideApiAccounting,
  decideApiDepartment,
  fetchApiApprovalHistory,
  fetchApiDepartmentCustodians,
  fetchApiRequests,
  fetchApiUsers,
  fetchApiSession,
  loginApiUser,
  respondApiTransfer,
  submitApiPettyCashReplenishmentCv,
  submitApiLiquidation,
  submitApiRfpAttachment,
  transferApiCashAdvance,
  updateApiCustodianFund,
  updateApiDepartmentCustodian,
  updateApiUser,
} from "./services/fundManagementApi";
import type {
  AppUser,
  CashAdvanceReceiptDetail,
  CashAdvanceRequest,
  CashAdvanceRequestType,
  CreateAppUserInput,
  DataMode,
  DepartmentCustodianAssignment,
  PettyCashReceiptDetail,
  PettyCashTransportationDetail,
  RfpDecision,
  UpdateAppUserInput,
} from "./types/CashAdvance";

const liveRequestRefreshMs = 5000;

const defaultDataMode: DataMode = "live";

const getInitialRequestsForMode = (mode: DataMode): CashAdvanceRequest[] =>
  mode === "demo" ? generateInitialRequests() : [];

const buildDemoDepartmentCustodians = (users: AppUser[]): DepartmentCustodianAssignment[] => {
  const custodians = users.filter((user) => user.role === "custodian");
  const firstCustodian = custodians[0];
  const departments = Array.from(new Set(users.map((user) => user.department))).sort((left, right) =>
    left.localeCompare(right),
  );

  return departments.map((department, index) => {
    const assignedCustodian = custodians.find((custodian) => custodian.department === department) ?? firstCustodian;

    return {
      departmentCode: String(users.find((user) => user.department === department)?.departmentCode ?? index + 1),
      departmentName: department,
      custodianUserId: assignedCustodian?.id,
      custodianName: assignedCustodian?.name,
      custodianDepartment: assignedCustodian?.department,
      custodianFundAmount: assignedCustodian?.pettyCashFundAmount,
    };
  });
};

function App() {
  const [dataMode, setDataMode] = useState<DataMode>(defaultDataMode);
  const [isCheckingSession, setIsCheckingSession] = useState(true);
  const [canSwitchUsers, setCanSwitchUsers] = useState(false);
  const [currentUser, setCurrentUser] = useState<AppUser | null>(null);
  const [requests, setRequests] = useState<CashAdvanceRequest[]>(() => getInitialRequestsForMode(defaultDataMode));
  const [approvalHistoryRequests, setApprovalHistoryRequests] = useState<CashAdvanceRequest[]>([]);
  const [liveUsers, setLiveUsers] = useState<AppUser[]>([]);
  const [liveDepartmentCustodians, setLiveDepartmentCustodians] = useState<DepartmentCustodianAssignment[]>([]);
  const [isLoadingLiveUsers, setIsLoadingLiveUsers] = useState(false);
  const [liveUsersError, setLiveUsersError] = useState("");
  const [loadedRequestsUserId, setLoadedRequestsUserId] = useState<string | null>(null);
  const [initialRequestsError, setInitialRequestsError] = useState("");
  const [requestLoadAttempt, setRequestLoadAttempt] = useState(0);

  useEffect(() => {
    if (dataMode !== "live") return;
    let cancelled = false;
    void fetchApiSession().then((user) => {
      if (!cancelled && user) {
        setCanSwitchUsers(user.id === "129");
        if (user.id !== "129" || window.sessionStorage.getItem("fms-sso-signed-out") !== "1") {
          setCurrentUser(user);
        }
      }
    }).catch((error) => console.warn("Unable to restore FMS SSO login.", error))
      .finally(() => { if (!cancelled) setIsCheckingSession(false); });
    return () => { cancelled = true; };
  }, [dataMode]);

  const isAuthenticated = currentUser !== null;
  const activeUsers = dataMode === "demo" ? demoUsers : liveUsers;
  const activeDepartmentCustodians =
    dataMode === "demo" ? buildDemoDepartmentCustodians(demoUsers) : liveDepartmentCustodians;

  const loadLiveUsers = useCallback(async () => {
    setIsLoadingLiveUsers(true);
    setLiveUsersError("");

    try {
      const [users, departmentCustodians] = await Promise.all([
        fetchApiUsers(),
        fetchApiDepartmentCustodians(),
      ]);
      setLiveUsers(users);
      setLiveDepartmentCustodians(departmentCustodians);
      setCurrentUser((currentUser) =>
        currentUser ? users.find((user) => user.id === currentUser.id) ?? currentUser : currentUser,
      );
    } catch (error) {
      setLiveUsers([]);
      setLiveDepartmentCustodians([]);
      setLiveUsersError(error instanceof Error ? error.message : "Unable to load users from FundManagementAPI.");
    } finally {
      setIsLoadingLiveUsers(false);
    }
  }, []);

  useEffect(() => {
    if (dataMode !== "live" || (!currentUser && !canSwitchUsers)) {
      return;
    }

    const loadTimerId = window.setTimeout(() => {
      void loadLiveUsers();
    }, 0);

    return () => window.clearTimeout(loadTimerId);
  }, [dataMode, isAuthenticated, canSwitchUsers, loadLiveUsers]);

  const refreshLiveRequests = useCallback(async (user: AppUser | null = currentUser) => {
    if (!user) {
      return;
    }

    const [latestRequests, latestApprovalHistory] = await Promise.all([
      fetchApiRequests(user),
      fetchApiApprovalHistory(user),
    ]);
    setRequests(latestRequests);
    setApprovalHistoryRequests(latestApprovalHistory);
  }, [currentUser]);

  useEffect(() => {
    if (dataMode !== "live" || !currentUser) {
      return;
    }

    let isDisposed = false;
    let isRefreshing = false;

    const refreshRequestsInBackground = async () => {
      if (isRefreshing) {
        return;
      }

      isRefreshing = true;

      try {
        await Promise.all([
          fetchApiRequests(currentUser).then((latestRequests) => {
            if (!isDisposed) {
              setRequests(latestRequests);
              setLoadedRequestsUserId(currentUser.id);
              setInitialRequestsError("");
            }
          }).catch((error: unknown) => {
            if (!isDisposed) {
              setInitialRequestsError(error instanceof Error ? error.message : "Unable to load dashboard data.");
            }
            throw error;
          }),
          fetchApiApprovalHistory(currentUser).then((latestApprovalHistory) => {
            if (!isDisposed) setApprovalHistoryRequests(latestApprovalHistory);
          }),
        ]);
      } catch (error) {
        console.warn("Unable to auto-refresh FundManagementAPI requests.", error);
      } finally {
        isRefreshing = false;
      }
    };

    const handleVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        void refreshRequestsInBackground();
      }
    };

    // Load immediately after session restoration instead of waiting for polling.
    void refreshRequestsInBackground();

    const refreshIntervalId = window.setInterval(() => {
      if (document.visibilityState === "visible") {
        void refreshRequestsInBackground();
      }
    }, liveRequestRefreshMs);

    window.addEventListener("focus", refreshRequestsInBackground);
    document.addEventListener("visibilitychange", handleVisibilityChange);

    return () => {
      isDisposed = true;
      window.clearInterval(refreshIntervalId);
      window.removeEventListener("focus", refreshRequestsInBackground);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [currentUser, dataMode, requestLoadAttempt]);

  const handleDataModeChange = (nextMode: DataMode) => {
    setCurrentUser(null);
    setLoadedRequestsUserId(null);
    setInitialRequestsError("");
    setDataMode(nextMode);
    setRequests(getInitialRequestsForMode(nextMode));
    setApprovalHistoryRequests([]);
  };

  const handleLogin = async (username: string, password: string) => {
    if (dataMode === "demo") {
      const user = demoUsers.find((item) => item.username === username);
      if (!user || password !== demoPassword) {
        throw new Error("Invalid username or password.");
      }

      setRequests(generateInitialRequests());
      setCurrentUser(user);
      return;
    }

    const user = await loginApiUser(username, password);
    if (canSwitchUsers) {
      // Keep manual logins in memory; a reload returns the switching account to login.
      window.sessionStorage.setItem("fms-sso-signed-out", "1");
    } else {
      window.sessionStorage.removeItem("fms-sso-signed-out");
    }
    const [apiRequests, apiApprovalHistory] = await Promise.all([
      fetchApiRequests(user),
      fetchApiApprovalHistory(user),
    ]);
    setRequests(apiRequests);
    setApprovalHistoryRequests(apiApprovalHistory);
    setLoadedRequestsUserId(user.id);
    setInitialRequestsError("");
    setCurrentUser(user);
  };

  const liveWorkflow =
    dataMode === "live" && currentUser
      ? {
          refreshRequests: () => refreshLiveRequests(currentUser),
          refreshUsers: loadLiveUsers,
          submitLiquidation: (
            requestId: string,
            amountSpent: number,
            notes: string,
            receiptDetails: CashAdvanceReceiptDetail[],
            pettyCashReceiptDetails: PettyCashReceiptDetail[],
            pettyCashTransportationDetails: PettyCashTransportationDetail[],
            attachments: File[],
            replaceExistingAttachments: boolean,
          ) =>
            submitApiLiquidation(
              requestId,
              currentUser.id,
              amountSpent,
              notes,
              receiptDetails,
              pettyCashReceiptDetails,
              pettyCashTransportationDetails,
              attachments,
              replaceExistingAttachments,
            ),
          submitRfpAttachment: (requestId: string, notes: string, attachments: File[]) =>
            submitApiRfpAttachment(requestId, notes, attachments),
          departmentDecision: (requestId: string, approved: boolean, notes: string, rfpDecision?: RfpDecision, companyId?: number) =>
            decideApiDepartment(requestId, currentUser.id, approved, notes, rfpDecision, companyId),
          accountingDecision: (requestId: string, approved: boolean, notes: string) =>
            decideApiAccounting(requestId, currentUser.id, approved, notes),
          createCashierReceipt: (
            requestId: string,
            receiptNumber: string,
            depositSlipAttachment: File | null,
            depositDate: string,
            depositAmount: number,
            depositoryBank: string,
            notes: string,
          ) => createApiCashierReceipt(
            requestId,
            currentUser.id,
            receiptNumber,
            depositSlipAttachment,
            depositDate,
            depositAmount,
            depositoryBank,
            notes,
          ),
          createCustodianReceipt: (requestId: string, receiptNumber: string, notes: string) =>
            createApiCustodianReceipt(requestId, currentUser.id, receiptNumber, notes),
          closeCashierLiquidation: (requestId: string, notes: string) =>
            closeApiCashierLiquidation(requestId, currentUser.id, notes),
          createPettyCashRequest: (
            requestType: CashAdvanceRequestType,
            requestorUserId: string,
            custodianUserId: string,
            amount: number,
            purpose: string,
            pettyCashReceiptDetails: PettyCashReceiptDetail[],
            pettyCashTransportationDetails: PettyCashTransportationDetail[],
            attachment: File | null,
            companyId?: number,
          ) =>
            createApiPettyCashRequest(
              requestType,
              requestorUserId,
              custodianUserId,
              amount,
              purpose,
              pettyCashReceiptDetails,
              pettyCashTransportationDetails,
              attachment,
              companyId,
            ),
          custodianDecision: (requestId: string, userId: string, approved: boolean, notes: string, returnedAmount?: number) =>
            decideApiCustodian(requestId, userId, approved, notes, returnedAmount),
          createPettyCashReplenishment: (custodianUserId: string, amount: number, notes: string) =>
            createApiPettyCashReplenishment(custodianUserId, amount, notes),
          submitPettyCashReplenishmentCv: (requestId: string, custodianUserId: string, cvNumber: string) =>
            submitApiPettyCashReplenishmentCv(requestId, custodianUserId, cvNumber),
          createUser: (user: CreateAppUserInput) => createApiUser(currentUser.id, user).then(() => undefined),
          updateUser: (userId: string, user: UpdateAppUserInput) =>
            updateApiUser(currentUser.id, userId, user).then(() => undefined),
          updateCustodianFund: (userId: string, pettyCashFundAmount: number) =>
            updateApiCustodianFund(currentUser.id, userId, pettyCashFundAmount).then(() => undefined),
          updateDepartmentCustodian: (departmentCode: string, custodianUserId: string) =>
            updateApiDepartmentCustodian(currentUser.id, departmentCode, custodianUserId).then(() => undefined),
          transferRequest: (
            requestId: string,
            toUserId: string,
            amount: number,
            transferWholeRequest: boolean,
            notes: string,
          ) => transferApiCashAdvance(requestId, toUserId, amount, transferWholeRequest, notes),
          respondToTransfer: (requestId: string, transferId: string, accepted: boolean, notes: string) =>
            respondApiTransfer(requestId, currentUser.id, accepted, notes, transferId),
        }
      : undefined;

  if (isCheckingSession) return <main role="status" className="flex min-h-screen items-center justify-center">Checking your session?</main>;

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Navigate to={currentUser || canSwitchUsers ? "/dashboard" : "/404"} replace />} />
        <Route path="/404" element={<main className="flex min-h-screen flex-col items-center justify-center gap-3"><h1 className="text-5xl font-bold">404</h1><p>Page not found.</p></main>} />
        <Route path="*" element={<Navigate to="/404" replace />} />
        <Route
          path="/dashboard"
          element={
            currentUser && dataMode === "live" && loadedRequestsUserId !== currentUser.id ? (
              <main className="flex min-h-screen flex-col items-center justify-center gap-3">
                {initialRequestsError ? (
                  <>
                    <p role="alert">Unable to load dashboard data. Please try again.</p>
                    <button type="button" onClick={() => {
                      setInitialRequestsError("");
                      setRequestLoadAttempt((attempt) => attempt + 1);
                    }} className="rounded-lg bg-[#0bb7a5] px-4 py-2 font-semibold text-white">Retry</button>
                  </>
                ) : <p role="status">Loading dashboard data...</p>}
              </main>
            ) : currentUser ? (
              <Dashboard
                key={currentUser.id}
                user={currentUser}
                dataMode={dataMode}
                requests={requests}
                approvalHistoryRequests={dataMode === "demo" ? requests : approvalHistoryRequests}
                setRequests={setRequests}
                users={activeUsers}
                departmentCustodians={activeDepartmentCustodians}
                liveWorkflow={liveWorkflow}
                onLogout={() => {
                  window.sessionStorage.setItem("fms-sso-signed-out", "1");
                  setLoadedRequestsUserId(null);
                  setInitialRequestsError("");
                  setCurrentUser(null);
                }}
              />
            ) : dataMode === "live" && !canSwitchUsers ? <Navigate to="/404" replace /> : (
              <LoginPage
                users={activeUsers}
                dataMode={dataMode}
                isLoadingUsers={isLoadingLiveUsers}
                usersError={liveUsersError}
                onReloadUsers={loadLiveUsers}
                onDataModeChange={handleDataModeChange}
                onLogin={handleLogin}
              />
            )
          }
        />
      </Routes>
    </BrowserRouter>
  );
}

export default App;

