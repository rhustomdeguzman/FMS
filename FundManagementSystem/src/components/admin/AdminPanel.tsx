import { type ReactNode, useMemo, useState } from "react";
import { roleLabels } from "../../auth/roleConfig";
import type {
  AppUser,
  CreateAppUserInput,
  CustodianFundSummary,
  DepartmentCustodianAssignment,
  UpdateAppUserInput,
  UserRole,
} from "../../types/CashAdvance";

interface AdminPanelProps {
  users: AppUser[];
  custodianFunds: CustodianFundSummary[];
  departmentCustodians: DepartmentCustodianAssignment[];
  isLiveMode: boolean;
  isSubmitting: boolean;
  onCreateUser: (user: CreateAppUserInput) => void;
  onUpdateUser: (userId: string, user: UpdateAppUserInput) => void;
  onUpdateCustodianFund: (userId: string, pettyCashFundAmount: number) => void;
  onAssignDepartmentCustodian: (departmentCode: string, custodianUserId: string) => void;
}

const roleOptions: UserRole[] = ["admin", "requestor", "department_head", "accounting", "cashier", "custodian"];
const defaultCustodianFundAmount = 20000;
const tablePageSize = 5;

const formatCurrency = (amount: number) => `PHP ${amount.toLocaleString()}`;
const getPageCount = (rowCount: number) => Math.max(1, Math.ceil(rowCount / tablePageSize));
const clampPage = (page: number, rowCount: number) => Math.min(Math.max(page, 1), getPageCount(rowCount));

const blankCreateForm = {
  username: "",
  password: "",
  displayName: "",
  department: "",
  role: "requestor" as UserRole,
  title: "",
  pettyCashFundAmount: String(defaultCustodianFundAmount),
};

export default function AdminPanel({
  users,
  custodianFunds,
  departmentCustodians,
  isLiveMode,
  isSubmitting,
  onCreateUser,
  onUpdateUser,
  onUpdateCustodianFund,
  onAssignDepartmentCustodian,
}: AdminPanelProps) {
  const [createForm, setCreateForm] = useState(blankCreateForm);
  const [roleEdits, setRoleEdits] = useState<Record<string, UserRole>>({});
  const [displayNameEdits, setDisplayNameEdits] = useState<Record<string, string>>({});
  const [usernameEdits, setUsernameEdits] = useState<Record<string, string>>({});
  const [departmentEdits, setDepartmentEdits] = useState<Record<string, string>>({});
  const [titleEdits, setTitleEdits] = useState<Record<string, string>>({});
  const [fundEdits, setFundEdits] = useState<Record<string, string>>({});
  const [custodianAssignmentEdits, setCustodianAssignmentEdits] = useState<Record<string, string>>({});
  const [rolePage, setRolePage] = useState(1);
  const [departmentCustodianPage, setDepartmentCustodianPage] = useState(1);
  const [formError, setFormError] = useState("");

  const usersById = useMemo(() => new Map(users.map((user) => [user.id, user])), [users]);
  const custodians = useMemo(() => users.filter((user) => user.role === "custodian"), [users]);
  const departmentOptions = useMemo(
    () => departmentCustodians.map((assignment) => assignment.departmentName),
    [departmentCustodians],
  );
  const currentRolePage = clampPage(rolePage, users.length);
  const currentDepartmentCustodianPage = clampPage(departmentCustodianPage, departmentCustodians.length);
  const paginatedUsers = useMemo(
    () => users.slice((currentRolePage - 1) * tablePageSize, currentRolePage * tablePageSize),
    [currentRolePage, users],
  );
  const paginatedDepartmentCustodians = useMemo(
    () =>
      departmentCustodians.slice(
        (currentDepartmentCustodianPage - 1) * tablePageSize,
        currentDepartmentCustodianPage * tablePageSize,
      ),
    [currentDepartmentCustodianPage, departmentCustodians],
  );

  const updateCreateField = (field: keyof typeof createForm, value: string) => {
    setCreateForm((current) => ({ ...current, [field]: value }));
  };

  const handleCreateUser = () => {
    const username = createForm.username.trim();
    const password = createForm.password;
    const displayName = createForm.displayName.trim();
    const department = createForm.department.trim();
    const title = createForm.title.trim();
    const pettyCashFundAmount =
      createForm.role === "custodian" ? Number(createForm.pettyCashFundAmount) : undefined;

    if (!username || !password || !displayName || !department || !title) {
      setFormError("Complete username, password, name, department, and title before adding a user.");
      return;
    }

    if (createForm.role === "custodian" && (!pettyCashFundAmount || pettyCashFundAmount <= 0)) {
      setFormError("Custodian initial fund must be greater than zero.");
      return;
    }

    setFormError("");
    onCreateUser({
      username,
      password,
      displayName,
      department,
      role: createForm.role,
      title,
      pettyCashFundAmount,
    });
    setCreateForm(blankCreateForm);
  };

  const saveRole = (targetUser: AppUser) => {
    const nextUsername = (usernameEdits[targetUser.id] ?? targetUser.username).trim();
    const nextDisplayName = (displayNameEdits[targetUser.id] ?? targetUser.name).trim();
    const nextDepartment = (departmentEdits[targetUser.id] ?? targetUser.department).trim();
    const nextTitle = (titleEdits[targetUser.id] ?? targetUser.title).trim();
    const nextRole = roleEdits[targetUser.id] ?? targetUser.role;
    const pettyCashFundAmount =
      nextRole === "custodian"
        ? Number(fundEdits[targetUser.id] ?? targetUser.pettyCashFundAmount ?? defaultCustodianFundAmount)
        : undefined;
    const assignedDepartments = departmentCustodians
      .filter((assignment) => assignment.custodianUserId === targetUser.id)
      .map((assignment) => assignment.departmentName);

    if (!nextUsername || !nextDisplayName || !nextDepartment || !nextTitle) {
      setFormError("User, username, department, and title are required.");
      return;
    }

    if (
      users.some(
        (user) => user.id !== targetUser.id && user.username.toLowerCase() === nextUsername.toLowerCase(),
      )
    ) {
      setFormError("Username already exists.");
      return;
    }

    if (nextRole === "custodian" && (!pettyCashFundAmount || pettyCashFundAmount <= 0)) {
      setFormError("Custodian initial fund must be greater than zero.");
      return;
    }

    if (targetUser.role === "custodian" && nextRole !== "custodian" && assignedDepartments.length > 0) {
      setFormError(
        `${targetUser.name} is assigned to ${assignedDepartments.join(", ")}. Reassign those departments before changing this role.`,
      );
      return;
    }

    setFormError("");
    onUpdateUser(targetUser.id, {
      username: nextUsername,
      displayName: nextDisplayName,
      department: nextDepartment,
      role: nextRole,
      title: nextTitle,
      pettyCashFundAmount,
    });
  };

  const saveCustodianFund = (custodianId: string) => {
    const fundAmount = Number(fundEdits[custodianId] ?? usersById.get(custodianId)?.pettyCashFundAmount ?? 0);

    if (!fundAmount || fundAmount <= 0) {
      setFormError("Custodian initial fund must be greater than zero.");
      return;
    }

    setFormError("");
    onUpdateCustodianFund(custodianId, fundAmount);
  };

  const saveDepartmentCustodian = (assignment: DepartmentCustodianAssignment) => {
    const custodianUserId = custodianAssignmentEdits[assignment.departmentCode] ?? assignment.custodianUserId ?? "";

    if (!custodianUserId) {
      setFormError("Choose a custodian before saving the department assignment.");
      return;
    }

    setFormError("");
    onAssignDepartmentCustodian(assignment.departmentCode, custodianUserId);
  };

  return (
    <section className="space-y-6">
      <div>
        <h2 className="text-xl font-bold text-[#17243f]">Admin</h2>
        <p className="mt-1 text-sm text-[#5c6b7a]">Manage system users, role access, and custodian petty cash funds.</p>
      </div>

      {!isLiveMode && (
        <div className="rounded-lg border border-[#ffd1dd] bg-[#fff0f4] p-4 text-sm font-semibold text-[#d30f42]">
          Admin changes are available only in Live mode.
        </div>
      )}

      {formError && (
        <div className="rounded-lg border border-[#ffd1dd] bg-[#fff0f4] p-4 text-sm font-semibold text-[#d30f42]">
          {formError}
        </div>
      )}

      <section className="rounded-lg border border-[#d9e1e8] bg-white shadow-sm">
        <div className="border-b border-[#d9e1e8] px-5 py-4">
          <h3 className="font-bold text-[#17243f]">Add User</h3>
        </div>
        <div className="grid gap-4 p-5 md:grid-cols-2 xl:grid-cols-3">
          <Field label="Username">
            <input
              type="text"
              value={createForm.username}
              onChange={(event) => updateCreateField("username", event.target.value)}
              className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
          </Field>
          <Field label="Password">
            <input
              type="password"
              value={createForm.password}
              onChange={(event) => updateCreateField("password", event.target.value)}
              className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
          </Field>
          <Field label="Role">
            <select
              value={createForm.role}
              onChange={(event) => updateCreateField("role", event.target.value)}
              className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
            >
              {roleOptions.map((role) => (
                <option key={role} value={role}>
                  {roleLabels[role]}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Display Name">
            <input
              type="text"
              value={createForm.displayName}
              onChange={(event) => updateCreateField("displayName", event.target.value)}
              className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
          </Field>
          <Field label="Department">
            <select
              value={createForm.department}
              onChange={(event) => updateCreateField("department", event.target.value)}
              disabled={departmentOptions.length === 0}
              className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none disabled:bg-[#eef2f7] disabled:text-[#5c6b7a]"
            >
              <option value="">Select department</option>
              {departmentOptions.map((department) => (
                <option key={department} value={department}>
                  {department}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Title">
            <input
              type="text"
              value={createForm.title}
              onChange={(event) => updateCreateField("title", event.target.value)}
              className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />
          </Field>
          {createForm.role === "custodian" && (
            <Field label="Initial Fund">
              <input
                type="number"
                min={1}
                step="0.01"
                value={createForm.pettyCashFundAmount}
                onChange={(event) => updateCreateField("pettyCashFundAmount", event.target.value)}
                className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
              />
            </Field>
          )}
          <div className="flex items-end">
            <button
              type="button"
              onClick={handleCreateUser}
              disabled={!isLiveMode || isSubmitting}
              className="w-full rounded-lg bg-[#0bb7a5] px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
            >
              Add User
            </button>
          </div>
        </div>
      </section>

      <section className="rounded-lg border border-[#d9e1e8] bg-white shadow-sm">
        <div className="border-b border-[#d9e1e8] px-5 py-4">
          <h3 className="font-bold text-[#17243f]">User Accounts</h3>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-[1220px] w-full text-left text-sm">
            <thead className="bg-[#f3f6f9] text-xs uppercase tracking-wide text-[#5c6b7a]">
              <tr>
                <th className="px-5 py-3 font-semibold">User</th>
                <th className="px-5 py-3 font-semibold">Username</th>
                <th className="px-5 py-3 font-semibold">Department</th>
                <th className="px-5 py-3 font-semibold">Title</th>
                <th className="px-5 py-3 font-semibold">Role</th>
                <th className="px-5 py-3 font-semibold">Initial Fund</th>
                <th className="px-5 py-3 font-semibold"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#eef2f7]">
              {paginatedUsers.map((targetUser) => {
                const selectedRole = roleEdits[targetUser.id] ?? targetUser.role;
                const showFundInput = selectedRole === "custodian";

                return (
                  <tr key={targetUser.id}>
                    <td className="px-5 py-4">
                      <input
                        type="text"
                        value={displayNameEdits[targetUser.id] ?? targetUser.name}
                        onChange={(event) =>
                          setDisplayNameEdits((current) => ({ ...current, [targetUser.id]: event.target.value }))
                        }
                        className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm font-semibold text-[#17243f] focus:border-[#0bb7a5] focus:outline-none"
                        aria-label={`${targetUser.name} display name`}
                      />
                    </td>
                    <td className="px-5 py-4">
                      <input
                        type="text"
                        value={usernameEdits[targetUser.id] ?? targetUser.username}
                        onChange={(event) =>
                          setUsernameEdits((current) => ({ ...current, [targetUser.id]: event.target.value }))
                        }
                        className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm text-[#17243f] focus:border-[#0bb7a5] focus:outline-none"
                        aria-label={`${targetUser.name} username`}
                      />
                    </td>
                    <td className="px-5 py-4">
                      <select
                        value={departmentEdits[targetUser.id] ?? targetUser.department}
                        onChange={(event) =>
                          setDepartmentEdits((current) => ({ ...current, [targetUser.id]: event.target.value }))
                        }
                        disabled={departmentOptions.length === 0}
                        className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm text-[#17243f] focus:border-[#0bb7a5] focus:outline-none disabled:bg-[#eef2f7] disabled:text-[#5c6b7a]"
                        aria-label={`${targetUser.name} department`}
                      >
                        {departmentOptions.map((department) => (
                          <option key={department} value={department}>
                            {department}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td className="px-5 py-4">
                      <input
                        type="text"
                        value={titleEdits[targetUser.id] ?? targetUser.title}
                        onChange={(event) =>
                          setTitleEdits((current) => ({ ...current, [targetUser.id]: event.target.value }))
                        }
                        className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm text-[#17243f] focus:border-[#0bb7a5] focus:outline-none"
                        aria-label={`${targetUser.name} title`}
                      />
                    </td>
                    <td className="px-5 py-4">
                      <select
                        value={selectedRole}
                        onChange={(event) =>
                          setRoleEdits((current) => ({
                            ...current,
                            [targetUser.id]: event.target.value as UserRole,
                          }))
                        }
                        className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                      >
                        {roleOptions.map((role) => (
                          <option key={role} value={role}>
                            {roleLabels[role]}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td className="px-5 py-4">
                      {showFundInput ? (
                        <input
                          type="number"
                          min={1}
                          step="0.01"
                          value={
                            fundEdits[targetUser.id] ??
                            String(targetUser.pettyCashFundAmount ?? defaultCustodianFundAmount)
                          }
                          onChange={(event) =>
                            setFundEdits((current) => ({ ...current, [targetUser.id]: event.target.value }))
                          }
                          className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                        />
                      ) : (
                        <span className="text-[#8b98a5]">N/A</span>
                      )}
                    </td>
                    <td className="px-5 py-4 text-right">
                      <button
                        type="button"
                        onClick={() => saveRole(targetUser)}
                        disabled={!isLiveMode || isSubmitting}
                        className="rounded-lg bg-[#17243f] px-4 py-2 text-sm font-semibold text-white hover:bg-[#243558] disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        Save
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <PaginationControls
          currentPage={currentRolePage}
          totalRows={users.length}
          onPageChange={setRolePage}
        />
      </section>

      <section className="rounded-lg border border-[#d9e1e8] bg-white shadow-sm">
        <div className="border-b border-[#d9e1e8] px-5 py-4">
          <h3 className="font-bold text-[#17243f]">Department Custodian Assignments</h3>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-[840px] w-full text-left text-sm">
            <thead className="bg-[#f3f6f9] text-xs uppercase tracking-wide text-[#5c6b7a]">
              <tr>
                <th className="px-5 py-3 font-semibold">Department</th>
                <th className="px-5 py-3 font-semibold">Assigned Custodian</th>
                <th className="px-5 py-3 font-semibold">Custodian Department</th>
                <th className="px-5 py-3 font-semibold">Custodian Fund</th>
                <th className="px-5 py-3 font-semibold"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#eef2f7]">
              {paginatedDepartmentCustodians.map((assignment) => {
                const selectedCustodianId =
                  custodianAssignmentEdits[assignment.departmentCode] ?? assignment.custodianUserId ?? "";
                const selectedCustodian = usersById.get(selectedCustodianId);

                return (
                  <tr key={assignment.departmentCode}>
                    <td className="px-5 py-4 font-semibold text-[#17243f]">{assignment.departmentName}</td>
                    <td className="px-5 py-4">
                      <select
                        value={selectedCustodianId}
                        onChange={(event) =>
                          setCustodianAssignmentEdits((current) => ({
                            ...current,
                            [assignment.departmentCode]: event.target.value,
                          }))
                        }
                        className="w-full rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                      >
                        <option value="">Unassigned</option>
                        {custodians.map((custodian) => (
                          <option key={custodian.id} value={custodian.id}>
                            {custodian.name}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td className="px-5 py-4 text-[#5c6b7a]">
                      {selectedCustodian?.department ?? assignment.custodianDepartment ?? "N/A"}
                    </td>
                    <td className="px-5 py-4 font-semibold text-[#17243f]">
                      {selectedCustodian?.pettyCashFundAmount
                        ? formatCurrency(selectedCustodian.pettyCashFundAmount)
                        : assignment.custodianFundAmount
                          ? formatCurrency(assignment.custodianFundAmount)
                          : "N/A"}
                    </td>
                    <td className="px-5 py-4 text-right">
                      <button
                        type="button"
                        onClick={() => saveDepartmentCustodian(assignment)}
                        disabled={!isLiveMode || isSubmitting || custodians.length === 0}
                        className="rounded-lg bg-[#17243f] px-4 py-2 text-sm font-semibold text-white hover:bg-[#243558] disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        Save
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          {departmentCustodians.length === 0 && (
            <p className="px-5 py-10 text-center text-sm text-[#5c6b7a]">No departments found.</p>
          )}
        </div>
        <PaginationControls
          currentPage={currentDepartmentCustodianPage}
          totalRows={departmentCustodians.length}
          onPageChange={setDepartmentCustodianPage}
        />
      </section>

      <section className="rounded-lg border border-[#d9e1e8] bg-white shadow-sm">
        <div className="border-b border-[#d9e1e8] px-5 py-4">
          <h3 className="font-bold text-[#17243f]">Custodian Initial Funds</h3>
        </div>
        <div className="divide-y divide-[#eef2f7]">
          {custodianFunds.map((fund) => (
            <div key={fund.custodian.id} className="grid gap-4 p-5 md:grid-cols-[1fr_180px_180px_auto] md:items-center">
              <div>
                <p className="font-semibold text-[#17243f]">{fund.custodian.name}</p>
                <p className="text-sm text-[#5c6b7a]">{fund.custodian.department}</p>
              </div>
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[#5c6b7a]">Current Fund</p>
                <p className="mt-1 font-bold text-[#17243f]">{formatCurrency(fund.fundAmount)}</p>
              </div>
              <input
                type="number"
                min={1}
                step="0.01"
                value={fundEdits[fund.custodian.id] ?? String(fund.fundAmount)}
                onChange={(event) =>
                  setFundEdits((current) => ({ ...current, [fund.custodian.id]: event.target.value }))
                }
                className="rounded-lg border border-[#c8d4df] px-3 py-2 text-sm focus:border-[#0bb7a5] focus:outline-none"
                aria-label={`${fund.custodian.name} initial fund`}
              />
              <button
                type="button"
                onClick={() => saveCustodianFund(fund.custodian.id)}
                disabled={!isLiveMode || isSubmitting}
                className="rounded-lg border border-[#0bb7a5] px-4 py-2 text-sm font-semibold text-[#08786f] hover:bg-[#e2faf6] disabled:cursor-not-allowed disabled:border-[#c8d4df] disabled:text-[#8b98a5]"
              >
                Update Fund
              </button>
            </div>
          ))}
          {custodians.length === 0 && (
            <p className="px-5 py-10 text-center text-sm text-[#5c6b7a]">No custodian users found.</p>
          )}
        </div>
      </section>
    </section>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="block text-sm font-semibold text-[#17243f]">
      <span className="mb-2 block">{label}</span>
      {children}
    </label>
  );
}

function PaginationControls({
  currentPage,
  totalRows,
  onPageChange,
}: {
  currentPage: number;
  totalRows: number;
  onPageChange: (page: number) => void;
}) {
  if (totalRows <= tablePageSize) {
    return null;
  }

  const pageCount = getPageCount(totalRows);
  const firstRow = (currentPage - 1) * tablePageSize + 1;
  const lastRow = Math.min(currentPage * tablePageSize, totalRows);

  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-t border-[#eef2f7] px-5 py-4 text-sm">
      <span className="font-semibold text-[#5c6b7a]">
        Showing {firstRow}-{lastRow} of {totalRows}
      </span>
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => onPageChange(currentPage - 1)}
          disabled={currentPage === 1}
          className="rounded-lg border border-[#c8d4df] px-3 py-2 font-semibold text-[#17243f] hover:bg-[#eef2f7] disabled:cursor-not-allowed disabled:opacity-50"
        >
          Previous
        </button>
        <span className="px-2 font-semibold text-[#5c6b7a]">
          Page {currentPage} of {pageCount}
        </span>
        <button
          type="button"
          onClick={() => onPageChange(currentPage + 1)}
          disabled={currentPage === pageCount}
          className="rounded-lg border border-[#c8d4df] px-3 py-2 font-semibold text-[#17243f] hover:bg-[#eef2f7] disabled:cursor-not-allowed disabled:opacity-50"
        >
          Next
        </button>
      </div>
    </div>
  );
}
