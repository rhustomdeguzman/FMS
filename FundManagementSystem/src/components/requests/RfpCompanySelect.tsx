import { useEffect, useState } from "react";
import { fetchApiCompanies } from "../../services/fundManagementApi";
import type { CompanyReference } from "../../types/CashAdvance";

export default function RfpCompanySelect({ value, onChange }: { value?: number; onChange: (value?: number) => void }) {
  const [companies, setCompanies] = useState<CompanyReference[]>([]);
  const [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    fetchApiCompanies().then(result => { if (active) setCompanies(result); }).catch(failure => {
      if (active) setError(failure instanceof Error ? failure.message : "Unable to load companies.");
    });
    return () => { active = false; };
  }, []);
  return (
    <label className="block text-sm font-semibold text-[#17243f]">
      RFP Company
      <select value={value ?? ""} onChange={event => onChange(event.target.value ? Number(event.target.value) : undefined)} className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm focus:border-[#0bb7a5] focus:outline-none">
        <option value="">Select company</option>
        {companies.filter(company => company.id !== undefined).map(company => <option key={company.id} value={company.id}>{company.name}</option>)}
      </select>
      <span className="mt-1 block text-xs font-normal text-[#5c6b7a]">This request has no company saved. Select the company for its RFP.</span>
      {error && <span role="alert" className="mt-1 block text-xs text-rose-600">{error}</span>}
    </label>
  );
}
