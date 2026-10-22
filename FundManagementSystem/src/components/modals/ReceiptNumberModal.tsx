import { useEffect, useState } from "react";

interface Props {
  loadNumber?: () => Promise<string>;
  onClose: () => void;
  onPrint: (receiptNumber: string) => void;
}

export default function ReceiptNumberModal({ loadNumber, onClose, onPrint }: Props) {
  const [number, setNumber] = useState("");
  const [loading, setLoading] = useState(Boolean(loadNumber));
  const [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    if (loadNumber) {
      loadNumber().then(value => { if (active) setNumber(value); })
        .catch(reason => { if (active) setError(reason instanceof Error ? reason.message : "Unable to load receipt number."); })
        .finally(() => { if (active) setLoading(false); });
    }
    return () => { active = false; };
  }, [loadNumber]);
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <form role="dialog" aria-modal="true" aria-labelledby="receipt-number-title"
        className="w-full max-w-md rounded-lg bg-white p-6 shadow-xl"
        onSubmit={event => {
          event.preventDefault();
          if (loading || !number.trim()) return;
          try { onPrint(number.trim()); }
          catch (reason) { setError(reason instanceof Error ? reason.message : "Unable to open print preview."); }
        }}>
        <h2 id="receipt-number-title" className="text-xl font-bold text-[#17243f]">Receipt Number</h2>
        <label htmlFor="ar-receipt-number" className="mt-5 block text-sm font-semibold">Receipt Number</label>
        <input id="ar-receipt-number" autoFocus required type="text" value={number}
          disabled={loading} onChange={event => setNumber(event.target.value)}
          className="mt-2 w-full rounded-lg border border-[#c8d4df] px-3 py-3 text-sm" />
        {loading && <p role="status" className="mt-2 text-sm">Loading receipt number…</p>}
        {error && <p role="alert" className="mt-2 text-sm text-red-600">{error}</p>}
        <div className="mt-6 flex justify-end gap-3">
          <button type="button" onClick={onClose} className="rounded-lg border px-4 py-2">Cancel</button>
          <button type="submit" disabled={loading || !number.trim()}
            className="rounded-lg bg-[#0b6f68] px-4 py-2 text-white disabled:opacity-50">Print</button>
        </div>
      </form>
    </div>
  );
}
