import type { Employee } from "../types/CashAdvance";

interface AvatarProps {
  employee: Employee;
  size?: "sm" | "md" | "lg";
}

const sizeClasses = {
  sm: "h-8 w-8 text-xs",
  md: "h-10 w-10 text-sm",
  lg: "h-12 w-12 text-base",
};

export default function Avatar({ employee, size = "md" }: AvatarProps) {
  return (
    <div
      className={`${sizeClasses[size]} flex shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-yellow-200 to-amber-600 font-semibold text-white`}
      title={employee.name}
    >
      {employee.avatar}
    </div>
  );
}
