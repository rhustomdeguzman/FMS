import type { FormEvent } from "react";
import { useMemo, useState } from "react";
import { roleLabels } from "../../auth/roleConfig";
import { demoPassword } from "../../data/mockData";
import type { AppUser, DataMode } from "../../types/CashAdvance";
import Avatar from "../Avatar";

interface LoginPageProps {
  users: AppUser[];
  dataMode: DataMode;
  isLoadingUsers?: boolean;
  usersError?: string;
  onReloadUsers?: () => void;
  onDataModeChange: (mode: DataMode) => void;
  onLogin: (username: string, password: string) => Promise<void> | void;
}

export default function LoginPage({
  users,
  dataMode,
  isLoadingUsers = false,
  onLogin,
}: LoginPageProps) {
  const sortedUsers = useMemo(
    () => [...users].sort((a, b) => a.name.localeCompare(b.name, "en", { sensitivity: "base" })),
    [users],
  );
  const [username, setUsername] = useState(sortedUsers[0]?.username ?? "");
  const [password, setPassword] = useState(demoPassword);
  const [error, setError] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const selectedUsername = users.some((user) => user.username === username) ? username : sortedUsers[0]?.username ?? "";

  const selectedUser = useMemo(
    () => users.find((user) => user.username === selectedUsername) ?? null,
    [users, selectedUsername],
  );

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();

    if (!selectedUser) {
      setError(dataMode === "live" ? "No API user is selected." : "No demo user is selected.");
      return;
    }

    setError("");
    setIsSubmitting(true);

    try {
      await onLogin(selectedUser.username, password);
    } catch (loginError) {
      setError(loginError instanceof Error ? loginError.message : "Unable to sign in.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-[#f3f6f9] px-4 py-10 text-[#17243f]">
      <div className="w-full max-w-2xl overflow-hidden rounded-lg border border-[#d9e1e8] bg-white shadow-sm">
        <div className="grid">
          {/* <section className="border-b border-[#d9e1e8] p-8 lg:border-b-0 lg:border-r">
            <div className="max-w-2xl">
              <p className="text-sm font-semibold uppercase tracking-wide text-[#0b6f68]">For Demo Access</p>
              <h1 className="mt-3 text-3xl font-bold text-[#17243f]">Fund Management System</h1>
              <p className="mt-3 text-[#5c6b7a]">
                Please select a demo user.
              </p>
            </div>

            <div className="mt-6">
              <p className="text-sm font-semibold text-[#17243f]">Data Mode</p>
              <div className="mt-2 grid max-w-xs rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] p-1">
                {dataModeOptions.map((option) => (
                  <button
                    key={option.value}
                    type="button"
                    onClick={() => onDataModeChange(option.value)}
                    className={
                      "rounded-md px-3 py-2 text-sm font-semibold transition " +
                      (dataMode === option.value
                        ? "bg-[#0bb7a5] text-white shadow-sm"
                        : "text-[#5c6b7a] hover:text-[#17243f]")
                    }
                  >
                    {option.label}
                  </button>
                ))}
              </div>
            </div>

            {dataMode === "live" && usersError && (
              <div className="mt-4 rounded-lg border border-[#ffd1dd] bg-[#fff0f4] p-4 text-sm text-[#d30f42]">
                <p>{usersError}</p>
                {onReloadUsers && (
                  <button
                    type="button"
                    onClick={onReloadUsers}
                    className="mt-3 rounded-lg bg-[#d30f42] px-3 py-2 text-sm font-semibold text-white hover:bg-[#b80d39]"
                  >
                    Retry API Users
                  </button>
                )}
              </div>
            )}
          </section> */}

          <form onSubmit={handleSubmit} className="p-8">
            <h2 className="text-xl font-bold text-[#17243f]">Fund Management Login</h2>
            {/* <p className="mt-1 text-sm text-[#5c6b7a]">{passwordHelper}</p> */}

            <label className="mt-6 block text-sm font-semibold text-[#17243f]" htmlFor="username">
              User
            </label>
            <select
              id="username"
              value={selectedUsername}
              onChange={(event) => setUsername(event.target.value)}
              disabled={isLoadingUsers || users.length === 0}
              className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none disabled:cursor-not-allowed disabled:bg-[#eef2f7]"
            >
              {sortedUsers.map((user) => (
                <option key={user.id} value={user.username}>
                  {user.name} - {roleLabels[user.role]} - {user.department}
                </option>
              ))}
            </select>

            <label className="mt-5 block text-sm font-semibold text-[#17243f]" htmlFor="password">
              Password
            </label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none"
            />

            {error && <p className="mt-4 rounded-lg bg-[#fff0f4] px-3 py-2 text-sm text-[#d30f42]">{error}</p>}

            {isLoadingUsers && (
              <p className="mt-4 rounded-lg bg-[#eef2f7] px-3 py-2 text-sm text-[#5c6b7a]">Loading API users...</p>
            )}

            {selectedUser && (
              <div className="mt-6 rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] p-4">
                <div className="flex items-center gap-3">
                  <Avatar employee={selectedUser} />
                  <div>
                    <p className="font-semibold text-[#17243f]">{selectedUser.name}</p>
                    <p className="text-sm text-[#5c6b7a]">
                      {selectedUser.title} - {selectedUser.department}
                    </p>
                  </div>
                </div>
              </div>
            )}

            <button
              type="submit"
              disabled={isSubmitting || isLoadingUsers || !selectedUser}
              className="mt-6 w-full rounded-lg bg-[#0bb7a5] px-4 py-3 text-sm font-semibold text-white shadow-sm hover:bg-[#099988] disabled:cursor-not-allowed disabled:opacity-50"
            >
              {isSubmitting ? "Signing in..." : "Sign in"}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}
