import type { ReactNode } from "react";

interface StatCardProps {
  title: string;
  value: string | number;
  tone: "amber" | "blue" | "cyan" | "emerald" | "indigo" | "rose" | "slate";
  icon: ReactNode;
  isActive?: boolean;
  onClick?: () => void;
}

const toneClasses = {
  amber: "bg-amber-400 text-white",
  blue: "bg-blue-400 text-white",
  cyan: "bg-cyan-400 text-white",
  emerald: "bg-teal-500 text-white",
  indigo: "bg-indigo-400 text-white",
  rose: "bg-rose-500 text-white",
  slate: "bg-slate-400 text-white",
};

export default function StatCard({ title, value, tone, icon, isActive = false, onClick }: StatCardProps) {
  const className = `w-full rounded-lg border bg-white p-5 text-left shadow-sm transition ${
    isActive ? "border-[#0bb7a5] ring-2 ring-[#0bb7a5]/25" : "border-[#d9e1e8]"
  } ${onClick ? "cursor-pointer hover:border-[#0bb7a5] hover:shadow-md" : ""}`;
  const content = (
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="text-sm font-medium text-wh">{title}</p>
          <p className="mt-1 text-2xl font-bold text-[#17243f]">{value}</p>
        </div>
        <div className={`flex h-11 w-11 items-center justify-center rounded-lg ${toneClasses[tone]}`}>
          {icon}
        </div>
      </div>
  );

  if (onClick) {
    return (
      <button type="button" onClick={onClick} className={className} aria-pressed={isActive}>
        {content}
      </button>
    );
  }

  return <div className={className}>{content}</div>;
}
