import type { ReactNode } from "react";
import { tabIcons, tabLabels } from "../../auth/roleConfig";
import type { AppUser, DashboardTab, DataMode } from "../../types/CashAdvance";
import Avatar from "../Avatar";
import Icon from "../Icon";
import logo from "../../assets/cli-low.png";


interface AppShellProps {
  user: AppUser;
  dataMode: DataMode;
  tabs: DashboardTab[];
  activeTab: DashboardTab;
  tabPendingCounts?: Partial<Record<DashboardTab, number>>;
  headerNotification?: ReactNode;
  onTabChange: (tab: DashboardTab) => void;
  onLogout: () => void;
  children: ReactNode;
}

export default function AppShell({
  user,
  tabs,
  activeTab,
  tabPendingCounts = {},
  headerNotification,
  onTabChange,
  onLogout,
  children,
}: AppShellProps) {
  return (
    <div className="min-h-screen bg-[#f3f6f9] text-[#17243f]">
      <header className="sticky top-0 z-40 border-b border-[#d9e1e8] bg-white">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
          <div className="flex items-center gap-4">
            <div className="flex h-10 w-10 items-center justify-center">
              <img src={logo} alt="Logo" />
            </div>
            <div>
              <h1 className="text-lg font-bold text-[#17243f]">Fund Management System</h1>
              <p className="text-sm text-[#5c6b7a]">Cash advance liquidation and approvals</p>
            </div>
          </div>

          <div className="flex items-center gap-4">
            {/* <span className="hidden rounded-lg border border-[#d9e1e8] bg-[#f3f6f9] px-3 py-2 text-xs font-bold uppercase tracking-wide text-[#17243f] sm:inline-flex">
              {modeLabel}
            </span> */}
            <div className="hidden text-right sm:block">
              <p className="text-sm font-semibold text-[#17243f]">{user.name}</p>
              <p className="text-xs text-[#5c6b7a]">
                {user.title} - {user.department}
              </p>
            </div>
            <Avatar employee={user} />
            {headerNotification}
            <button
              type="button"
              onClick={onLogout}
              className="rounded-lg bg-[#0bb7a5] px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-[#099988]"
            >
              Logout
            </button>
          </div>
        </div>
      <nav className="border-y border-[#d9e1e8] bg-white">
        <div className="mx-auto flex max-w-7xl gap-1 overflow-x-auto px-6">
          {tabs.map((tab) => {
            const pendingCount = tabPendingCounts[tab] ?? 0;

            return (
              <button
                key={tab}
                type="button"
                onClick={() => onTabChange(tab)}
                className={`relative flex items-center gap-2 border-b-2 px-4 py-4 text-sm font-semibold transition-colors ${
                  activeTab === tab
                    ? "border-[#0bb7a5] text-[#17243f]"
                    : "border-transparent text-[#5c6b7a] hover:text-[#17243f]"
                }`}
              >
                <Icon path={tabIcons[tab]} className="h-4 w-4" />
                {tabLabels[tab]}
                {pendingCount > 0 && (
                  <span className="ml-1 inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-[#ff1550] px-1 text-xs font-bold text-white">
                    {pendingCount}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </nav>
      </header>

      

      <main className="mx-auto max-w-7xl px-6 py-8">{children}</main>
    </div>
  );
}
