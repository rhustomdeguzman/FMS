import { fetchApiCompanies, fetchApiExpenseTypes, fetchApiProfitCenters } from "../../services/fundManagementApi";
import { useEffect, useMemo, useState } from "react";
import {
  getPettyCashRequestMaximum,
  getPettyCashRequestTypeLabel,
  pettyCashRequestLimit,
} from "../../pettyCash";
import type {
  AppUser,
  CompanyReference,
  ExpenseTypeReference,
  ProfitCenterReference,
  CashAdvanceRequestType,
  CustodianFundSummary,
  PettyCashReceiptDetail,
  PettyCashTransportationDetail,
} from "../../types/CashAdvance";

interface PettyCashRequestModalProps {
  isSubmitting?: boolean;
  requestor: AppUser;
  custodianFunds: CustodianFundSummary[];
  onClose: () => void;
  onSubmit: (
    requestType: CashAdvanceRequestType,
    custodianId: string,
    amount: number,
    purpose: string,
    pettyCashReceiptDetails: PettyCashReceiptDetail[],
    pettyCashTransportationDetails: PettyCashTransportationDetail[],
    attachment: File | null,
    companyId?: number,
  ) => void;
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

const requestTypeOptions: CashAdvanceRequestType[] = ["petty_cash", "petty_cash_advance"];

const createReceiptRow = (): PettyCashReceiptRow => ({
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

const createTransportationRow = (): PettyCashTransportationRow => ({
  id: `pc-transport-${Date.now()}-${Math.random().toString(36).slice(2)}`,
  description: "",
  from: "",
  to: "",
  transactionDate: "",
  amount: "",
});

const getRowAmount = (amountText: string) => {
  const amount = Number(amountText);
  return Number.isFinite(amount) ? amount : 0;
};

const isReceiptRowBlank = (row: PettyCashReceiptRow) =>
  row.orNumber.trim().length === 0 &&
  row.company.trim().length === 0 &&
  row.tin.trim().length === 0 &&
  row.address.trim().length === 0 &&
  row.natureOfExpense.trim().length === 0 &&
  row.costCenter.trim().length === 0 &&
  row.amount.trim().length === 0 &&
  row.orDate.trim().length === 0;

const isReceiptRowComplete = (row: PettyCashReceiptRow) =>
  row.orNumber.trim().length > 0 &&
  row.company.trim().length > 0 &&
  row.tin.trim().length > 0 &&
  row.address.trim().length > 0 &&
  row.natureOfExpense.trim().length > 0 &&
  row.costCenter.trim().length > 0 &&
  getRowAmount(row.amount) > 0 &&
  row.orDate.trim().length > 0;

const isTransportationRowBlank = (row: PettyCashTransportationRow) =>
  row.description.trim().length === 0 &&
  row.from.trim().length === 0 &&
  row.to.trim().length === 0 &&
  row.transactionDate.trim().length === 0 &&
  row.amount.trim().length === 0;

const isTransportationRowComplete = (row: PettyCashTransportationRow) =>
  row.description.trim().length > 0 &&
  row.from.trim().length > 0 &&
  row.to.trim().length > 0 &&
  row.transactionDate.trim().length > 0 &&
  getRowAmount(row.amount) > 0;

const toPettyCashReceiptDetail = (row: PettyCashReceiptRow): PettyCashReceiptDetail => ({
  id: row.id,
  orNumber: row.orNumber.trim(),
  company: row.company.trim(),
  tin: row.tin.trim(),
  address: row.address.trim(),
  natureOfExpenseCode: row.natureOfExpenseCode,
  natureOfExpense: row.natureOfExpense.trim(),
  costCenterCode: row.costCenterCode,
  costCenter: row.costCenter.trim(),
  amount: getRowAmount(row.amount),
  orDate: row.orDate,
});

const toPettyCashTransportationDetail = (row: PettyCashTransportationRow): PettyCashTransportationDetail => ({
  id: row.id,
  description: row.description.trim(),
  from: row.from.trim(),
  to: row.to.trim(),
  transactionDate: row.transactionDate,
  amount: getRowAmount(row.amount),
});

export default function PettyCashRequestModal({
  isSubmitting = false,
  requestor,
  custodianFunds,
  onClose,
  onSubmit,
}: PettyCashRequestModalProps) {
  const [requestType, setRequestType] = useState<CashAdvanceRequestType>("petty_cash");
  const [companyId, setCompanyId] = useState<number>();
  const [companies, setCompanies] = useState<CompanyReference[]>([]);
  const [expenseTypes, setExpenseTypes] = useState<ExpenseTypeReference[]>([]);
  const [profitCenters, setProfitCenters] = useState<ProfitCenterReference[]>([]);
  const [referenceError, setReferenceError] = useState("");
  useEffect(() => {
    let cancelled = false;
    void Promise.all([fetchApiCompanies(), fetchApiExpenseTypes()]).then(([companyRows, expenseRows]) => {
      if (!cancelled) { setCompanies(companyRows); setExpenseTypes(expenseRows); }
    }).catch(() => { if (!cancelled) setReferenceError("Unable to load companies and expense types. Close and reopen this form to retry."); });
    return () => { cancelled = true; };
  }, []);
  useEffect(() => {
    let cancelled = false;
    if (companyId === undefined) return;
    void fetchApiProfitCenters(companyId).then((rows) => {
      if (!cancelled) setProfitCenters(rows);
    }).catch(() => { if (!cancelled) setReferenceError("Unable to load profit cost centers. Select the company again to retry."); });
    return () => { cancelled = true; };
  }, [companyId]);
  const [custodianId, setCustodianId] = useState("");
  const [advanceAmount, setAdvanceAmount] = useState("");
  const [purpose, setPurpose] = useState("");
  const [receiptRows, setReceiptRows] = useState<PettyCashReceiptRow[]>([createReceiptRow()]);
  const [transportationRows, setTransportationRows] = useState<PettyCashTransportationRow[]>([]);
  const [attachment, setAttachment] = useState<File | null>(null);
  const [fundError, setFundError] = useState("");
  const selectedCustodianId = custodianFunds.some((fund) => fund.custodian.id === custodianId)
    ? custodianId
    : custodianFunds[0]?.custodian.id ?? "";

  const selectedFund = useMemo(
    () => custodianFunds.find((fund) => fund.custodian.id === selectedCustodianId),
    [custodianFunds, selectedCustodianId],
  );
  const maximumAmount = getPettyCashRequestMaximum(selectedFund?.availableAmount ?? 0);
  const isReimbursement = requestType === "petty_cash";
  const activeReceiptRows = receiptRows.filter((row) => !isReceiptRowBlank(row));
  const activeTransportationRows = transportationRows.filter((row) => !isTransportationRowBlank(row));
  const receiptTotal = activeReceiptRows.reduce((sum, row) => sum + getRowAmount(row.amount), 0);
  const transportationTotal = activeTransportationRows.reduce((sum, row) => sum + getRowAmount(row.amount), 0);
  const actualSpentAmount = receiptTotal + transportationTotal;
  const parsedAdvanceAmount = Number(advanceAmount);
  const requestedAmount = isReimbursement ? actualSpentAmount : parsedAdvanceAmount;
  const hasValidAmount = Number.isFinite(requestedAmount) && requestedAmount > 0;
  const excessAmount = isReimbursement && hasValidAmount ? Math.max(actualSpentAmount - requestedAmount, 0) : 0;
  const isWithinRequestLimit = hasValidAmount && requestedAmount <= pettyCashRequestLimit;
  const hasEnoughActualSpent = !isReimbursement || actualSpentAmount + 0.01 >= requestedAmount;
  const isExcessWithinRequestLimit = !isReimbursement || excessAmount <= pettyCashRequestLimit;
  const isActualWithinFund =
    !isReimbursement || selectedFund === undefined || actualSpentAmount <= selectedFund.availableAmount;
  const hasValidReceiptRows = !isReimbursement || activeReceiptRows.every(isReceiptRowComplete);
  const hasValidTransportationRows = !isReimbursement || activeTransportationRows.every(isTransportationRowComplete);
  const hasReimbursementRows = !isReimbursement || activeReceiptRows.length + activeTransportationRows.length > 0;
  const hasValidPurpose = purpose.trim().length > 0;
  const hasAttachment = attachment !== null && attachment.size > 0;
  const requiresAttachment = isReimbursement;
  const canSubmit =
    selectedFund !== undefined &&
    (!isReimbursement || companyId !== undefined) &&
    hasValidAmount &&
    isWithinRequestLimit &&
    hasEnoughActualSpent &&
    isExcessWithinRequestLimit &&
    isActualWithinFund &&
    hasValidReceiptRows &&
    hasValidTransportationRows &&
    hasReimbursementRows &&
    hasValidPurpose &&
    (!requiresAttachment || hasAttachment);

  const updateReceiptRow = (rowId: string, updates: Partial<PettyCashReceiptRow>) => {
    setFundError("");
    setReceiptRows((rows) => rows.map((row) => (row.id === rowId ? { ...row, ...updates } : row)));
  };

  const updateTransportationRow = (rowId: string, updates: Partial<PettyCashTransportationRow>) => {
    setFundError("");
    setTransportationRows((rows) => rows.map((row) => (row.id === rowId ? { ...row, ...updates } : row)));
  };

  const deleteReceiptRow = (rowId: string) => {
    setFundError("");
    setReceiptRows((rows) => (rows.length === 1 ? [createReceiptRow()] : rows.filter((row) => row.id !== rowId)));
  };

  const deleteTransportationRow = (rowId: string) => {
    setFundError("");
    setTransportationRows((rows) => rows.filter((row) => row.id !== rowId));
  };

  const submit = () => {
    if (isSubmitting) return;
    if (isReimbursement && companyId === undefined) {
      setFundError("Company is required.");
      return;
    }
    if (!selectedFund) {
      setFundError(`No custodian is assigned to ${requestor.department}.`);
      return;
    }

    if (requestedAmount > maximumAmount) {
      setFundError("The assigned department custodian's remaining fund is not enough for this petty cash amount.");
      return;
    }

    if (isReimbursement && actualSpentAmount + 0.01 < requestedAmount) {
      setFundError("Actual spent must be equal to or greater than the petty cash reimbursement amount.");
      return;
    }

    if (isReimbursement && excessAmount > pettyCashRequestLimit) {
      setFundError("The excess amount must be within the petty cash request cap because it creates a new request.");
      return;
    }

    if (isReimbursement && actualSpentAmount > selectedFund.availableAmount) {
      setFundError("The assigned department custodian's remaining fund is not enough for the actual spent amount.");
      return;
    }

    const receiptDetails = isReimbursement ? activeReceiptRows.map(toPettyCashReceiptDetail) : [];
    const transportationDetails = isReimbursement
      ? activeTransportationRows.map(toPettyCashTransportationDetail)
      : [];
    const submittedRequestType: CashAdvanceRequestType = isReimbursement ? "petty_cash" : "petty_cash_advance";
    const submittedPurpose = purpose.trim();

    onSubmit(
      submittedRequestType,
      selectedCustodianId,
      requestedAmount,
      submittedPurpose,
      receiptDetails,
      transportationDetails,
      attachment,
      isReimbursement ? companyId : undefined,
    );
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="flex max-h-[90vh] w-full max-w-6xl flex-col overflow-hidden rounded-lg bg-white shadow-xl">
        <div className="border-b border-[#d9e1e8] p-6">
          <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">Petty Cash</p>
          <h2 className="mt-1 text-xl font-bold text-[#17243f]">New petty cash request</h2>
          <p className="mt-2 text-sm text-[#5c6b7a]">
            {requestor.department} requests are routed to your department approver first, then to the assigned custodian.
          </p>
        </div>

        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto p-6">
          <div className="grid gap-4 lg:grid-cols-2">
            <div>
              <label className="block text-sm font-semibold text-[#17243f]" htmlFor="petty-cash-type">
                Request Type
              </label>
              <select
                id="petty-cash-type"
                value={requestType}
                onChange={(event) => {
                  setFundError("");
                  setRequestType(event.target.value as CashAdvanceRequestType);
                }}
                className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
              >
                {requestTypeOptions.map((option) => (
                  <option key={option} value={option}>
                    {getPettyCashRequestTypeLabel(option)}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-sm font-semibold text-[#17243f]" htmlFor="petty-cash-custodian">
                Assigned Custodian
              </label>
              <select
                id="petty-cash-custodian"
                value={selectedCustodianId}
                disabled={custodianFunds.length <= 1}
                onChange={(event) => {
                  setFundError("");
                  setCustodianId(event.target.value);
                }}
                className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none disabled:bg-[#eef2f7] disabled:text-[#5c6b7a]"
              >
                {custodianFunds.length === 0 && <option value="">No assigned custodian available</option>}
                {custodianFunds.map((fund) => (
                  <option key={fund.custodian.id} value={fund.custodian.id}>
                    {fund.custodian.name}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div>
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="petty-cash-purpose">
              Purpose
            </label>
            <textarea
              id="petty-cash-purpose"
              value={purpose}
              onChange={(event) => {
                setFundError("");
                setPurpose(event.target.value);
              }}
              rows={3}
              className="mt-2 w-full resize-none rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
          </div>

          {isReimbursement && (
            <div>
              <label className="block text-sm font-semibold text-[#17243f]" htmlFor="petty-cash-company">Company<span className="text-rose-400">*</span></label>
              <select id="petty-cash-company" required value={companyId ?? ""}
                onChange={(event) => {
                  setCompanyId(event.target.value ? Number(event.target.value) : undefined);
                  setProfitCenters([]);
                  setReferenceError("");
                  setFundError("");
                  setReceiptRows((rows) => rows.map((row) => ({ ...row, costCenterCode: "", costCenter: "" })));
                }}
                className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm">
                <option value="">Select company</option>
                {companies.filter((company) => company.id !== undefined).map((company) => <option key={company.id} value={company.id}>{company.name}</option>)}
              </select>
              {referenceError && <p className="mt-2 text-xs text-[#d30f42]">{referenceError}</p>}
            </div>
          )}
          {isReimbursement ? (
            <>
              <div className="rounded-lg border border-[#c8d4df] bg-[#f8fafc] px-4 py-3">
                <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Actual Spent</p>
                <p className="mt-2 text-lg font-bold text-[#17243f]">PHP {actualSpentAmount.toLocaleString()}</p>
                <p className="mt-1 text-xs text-[#5c6b7a]">
                  Reimbursement amount is calculated from receipt and transportation details.
                </p>
              </div>

              <section className="rounded-lg border border-[#c8d4df] bg-white p-4">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h3 className="font-bold text-[#17243f]">Receipt Details</h3>
                    <p className="mt-1 text-sm text-[#5c6b7a]">Total: PHP {receiptTotal.toLocaleString()}</p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setReceiptRows((rows) => [...rows, createReceiptRow()])}
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
                    {receiptRows.map((row) => (
                      <div
                        key={row.id}
                        className="grid grid-cols-[130px_190px_150px_220px_220px_150px_120px_130px_80px] gap-2"
                      >
                        <input
                          type="text"
                          value={row.orNumber}
                          onChange={(event) => updateReceiptRow(row.id, { orNumber: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="OR number"
                        />
                        <input
                          type="text"
                          value={row.company}
                          onChange={(event) => updateReceiptRow(row.id, { company: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Company"
                        />
                        <input
                          type="text"
                          value={row.tin}
                          onChange={(event) => updateReceiptRow(row.id, { tin: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="TIN"
                        />
                        <input
                          type="text"
                          value={row.address}
                          onChange={(event) => updateReceiptRow(row.id, { address: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Address"
                        />
                        <select
                          value={row.natureOfExpenseCode}
                          required
                          disabled={companyId === undefined}
                          onChange={(event) => {
                            const selected = expenseTypes.find((option) => option.expenseCode === event.target.value);
                            updateReceiptRow(row.id, { natureOfExpenseCode: selected?.expenseCode ?? "", natureOfExpense: selected?.expenseName ?? "" });
                          }}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm"
                          aria-label="Type of Expense">
                          <option value="">{companyId === undefined ? "Select company first" : "Select expense"}</option>
                          {expenseTypes.map((option) => <option key={option.expenseCode} value={option.expenseCode}>{option.expenseName}</option>)}
                        </select>
                        <select
                          value={row.costCenterCode}
                          required
                          disabled={companyId === undefined}
                          onChange={(event) => {
                            const selected = profitCenters.find((option) => option.ocrCode === event.target.value);
                            updateReceiptRow(row.id, { costCenterCode: selected?.ocrCode ?? "", costCenter: selected?.ocrName ?? "" });
                          }}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm"
                          aria-label="Profit Cost Center">
                          <option value="">{companyId === undefined ? "Select company first" : "Select center"}</option>
                          {profitCenters.map((option) => <option key={option.ocrCode} value={option.ocrCode}>{option.ocrName}</option>)}
                        </select>
                        <input
                          type="number"
                          min={0}
                          step="0.01"
                          value={row.amount}
                          onChange={(event) => updateReceiptRow(row.id, { amount: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Amount"
                        />
                        <input
                          type="date"
                          value={row.orDate}
                          onChange={(event) => updateReceiptRow(row.id, { orDate: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="OR date"
                        />
                        <button
                          type="button"
                          onClick={() => deleteReceiptRow(row.id)}
                          className="rounded-lg border border-[#ffb3c6] px-3 py-2 text-xs font-semibold text-[#d30f42] hover:bg-[#fff0f4]"
                        >
                          Del
                        </button>
                      </div>
                    ))}
                  </div>
                </div>

                {!hasValidReceiptRows && (
                  <p className="mt-3 text-xs font-semibold text-[#d30f42]">
                    Complete every filled receipt row before submitting.
                  </p>
                )}
              </section>

              <section className="rounded-lg border border-[#c8d4df] bg-white p-4">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <h3 className="font-bold text-[#17243f]">Transportation Expenses</h3>
                    <p className="mt-1 text-sm text-[#5c6b7a]">
                      Total: PHP {transportationTotal.toLocaleString()}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setTransportationRows((rows) => [...rows, createTransportationRow()])}
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
                    {transportationRows.map((row) => (
                      <div key={row.id} className="grid grid-cols-[150px_220px_150px_150px_120px_80px] gap-2">
                        <input
                          type="date"
                          value={row.transactionDate}
                          onChange={(event) =>
                            updateTransportationRow(row.id, { transactionDate: event.target.value })
                          }
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation transaction date"
                        />
                        <input
                          type="text"
                          value={row.description}
                          onChange={(event) => updateTransportationRow(row.id, { description: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation description"
                        />
                        <input
                          type="text"
                          value={row.from}
                          onChange={(event) => updateTransportationRow(row.id, { from: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation from"
                        />
                        <input
                          type="text"
                          value={row.to}
                          onChange={(event) => updateTransportationRow(row.id, { to: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation to"
                        />
                        <input
                          type="number"
                          min={0}
                          step="0.01"
                          value={row.amount}
                          onChange={(event) => updateTransportationRow(row.id, { amount: event.target.value })}
                          className="rounded-lg border border-[#c8d4df] px-2 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                          aria-label="Transportation amount"
                        />
                        <button
                          type="button"
                          onClick={() => deleteTransportationRow(row.id)}
                          className="rounded-lg border border-[#ffb3c6] px-3 py-2 text-xs font-semibold text-[#d30f42] hover:bg-[#fff0f4]"
                        >
                          Del
                        </button>
                      </div>
                    ))}
                    {transportationRows.length === 0 && (
                      <p className="rounded-lg bg-[#f3f6f9] px-4 py-5 text-center text-sm text-[#5c6b7a]">
                        No transportation expense rows added.
                      </p>
                    )}
                  </div>
                </div>

                {!hasValidTransportationRows && (
                  <p className="mt-3 text-xs font-semibold text-[#d30f42]">
                    Complete every transportation row before submitting.
                  </p>
                )}
              </section>

            </>
          ) : (
            <div className="grid gap-4 lg:grid-cols-2">
              <div>
                <label className="block text-sm font-semibold text-[#17243f]" htmlFor="petty-cash-amount">
                  Amount
                </label>
                <input
                  id="petty-cash-amount"
                  type="number"
                  min={1}
                  max={pettyCashRequestLimit}
                  step="0.01"
                  value={advanceAmount}
                  onChange={(event) => {
                    setFundError("");
                    setAdvanceAmount(event.target.value);
                  }}
                  className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
                />
              </div>
            </div>
          )}

          <section className="rounded-lg border border-[#c8d4df] bg-white p-4">
            <label className="block text-sm font-semibold text-[#17243f]" htmlFor="petty-cash-attachment">
              Attachment
            </label>
            <input
              id="petty-cash-attachment"
              type="file"
              required={requiresAttachment}
              onChange={(event) => {
                setFundError("");
                setAttachment(event.target.files?.[0] ?? null);
              }}
              className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
            {attachment ? (
              <p className="mt-2 text-xs font-semibold text-[#5c6b7a]">Selected: {attachment.name}</p>
            ) : requiresAttachment ? (
              <p className="mt-2 text-xs font-semibold text-[#d30f42]">Attachment is required.</p>
            ) : (
              <p className="mt-2 text-xs font-semibold text-[#5c6b7a]"></p>
            )}
          </section>

          <div className="rounded-lg bg-[#f3f6f9] px-4 py-3 text-sm">
            <div className="flex justify-between gap-4">
              <span className="font-semibold text-[#17243f]">Request Amount</span>
              <span className="font-bold text-[#08786f]">PHP {(requestedAmount || 0).toLocaleString()}</span>
            </div>
            <p className="mt-2 text-xs font-semibold text-[#5c6b7a]">
              Maximum PHP {pettyCashRequestLimit.toLocaleString()} per request.
            </p>
            {!isWithinRequestLimit && requestedAmount > 0 && (
              <p className="mt-2 text-xs font-semibold text-[#d30f42]">
                Amount must be within the PHP {pettyCashRequestLimit.toLocaleString()} cap.
              </p>
            )}
            {isReimbursement && !hasEnoughActualSpent && requestedAmount > 0 && (
              <p className="mt-2 text-xs font-semibold text-[#d30f42]">
                Actual spent must be equal to or greater than the request amount.
              </p>
            )}
            {isReimbursement && excessAmount > 0 && isExcessWithinRequestLimit && (
              <div className="mt-2 flex justify-between gap-4 text-xs font-semibold text-[#5c6b7a]">
                <span>Excess for New Petty Cash</span>
                <span>PHP {excessAmount.toLocaleString()}</span>
              </div>
            )}
            {isReimbursement && !isExcessWithinRequestLimit && (
              <p className="mt-2 text-xs font-semibold text-[#d30f42]">
                Excess must be within the PHP {pettyCashRequestLimit.toLocaleString()} cap.
              </p>
            )}
            {isReimbursement && !isActualWithinFund && (
              <p className="mt-2 text-xs font-semibold text-[#d30f42]">
                Actual spent exceeds the custodian's remaining fund.
              </p>
            )}
            {fundError && <p className="mt-2 text-xs font-semibold text-[#d30f42]">{fundError}</p>}
            {!hasReimbursementRows && (
              <p className="mt-2 text-xs font-semibold text-[#d30f42]">
                Add at least one receipt or transportation row before submitting.
              </p>
            )}
          </div>
        </div>

        <div className="flex gap-3 border-t border-[#d9e1e8] p-6">
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
            disabled={!canSubmit || isSubmitting}
            onClick={submit}
            className="flex-1 rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {isSubmitting ? "Submitting..." : "Submit"}
          </button>
        </div>
      </div>
      {isSubmitting && (
        <div className="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4" role="status" aria-live="polite">
          <div className="w-full max-w-sm rounded-lg bg-white px-6 py-8 text-center shadow-xl">
            <div className="mx-auto h-10 w-10 animate-spin rounded-full border-4 border-[#d9e1e8] border-t-[#0bb7a5]" aria-hidden="true" />
            <h3 className="mt-5 text-lg font-bold text-[#17243f]">Submitting petty cash request</h3>
            <p className="mt-2 text-sm text-[#5c6b7a]">Saving your request and attachment. Please wait until processing is complete.</p>
          </div>
        </div>
      )}
    </div>
  );
}
