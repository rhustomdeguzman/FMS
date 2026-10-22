import { type KeyboardEvent, useState } from "react";
import type { CashAdvanceRequest } from "../../types/CashAdvance";
import Icon from "../Icon";

interface PrintNotificationStashProps {
  requests: CashAdvanceRequest[];
  pendingTransferAcknowledgements?: CashAdvanceRequest[];
  pendingReceiptAcknowledgements?: CashAdvanceRequest[];
  onPrint: (request: CashAdvanceRequest) => void;
  onOpenDetails?: (request: CashAdvanceRequest) => void;
  onOpenAcknowledgement?: (request: CashAdvanceRequest) => void;
  onCreateReceipt?: (request: CashAdvanceRequest) => void;
}

const notificationIconPath =
  "M15 17h5l-1.4-1.4A2 2 0 0 1 18 14.2V11a6 6 0 1 0-12 0v3.2a2 2 0 0 1-.6 1.4L4 17h5m6 0a3 3 0 0 1-6 0";

export default function PrintNotificationStash({
  requests,
  pendingTransferAcknowledgements = [],
  pendingReceiptAcknowledgements = [],
  onPrint,
  onOpenDetails,
  onOpenAcknowledgement,
  onCreateReceipt,
}: PrintNotificationStashProps) {
  const [isOpen, setIsOpen] = useState(false);
  const printableCount = requests.length;
  const transferAcknowledgementCount = pendingTransferAcknowledgements.length;
  const receiptAcknowledgementCount = pendingReceiptAcknowledgements.length;
  const notificationCount = printableCount + transferAcknowledgementCount + receiptAcknowledgementCount;

  if (notificationCount === 0) {
    return null;
  }

  const openDetails = (request: CashAdvanceRequest) => {
    if (!onOpenDetails) {
      return;
    }

    onOpenDetails(request);
    setIsOpen(false);
  };

  const handleItemKeyDown = (event: KeyboardEvent<HTMLDivElement>, request: CashAdvanceRequest) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    openDetails(request);
  };

  const notificationItemClass = `flex items-center justify-between gap-3 border-b border-[#eef2f7] px-4 py-3 ${
    onOpenDetails ? "cursor-pointer hover:bg-[#f3f6f9]" : ""
  }`;

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setIsOpen((current) => !current)}
        className="relative inline-flex h-10 w-10 items-center justify-center rounded-lg border border-[#d9e1e8] bg-white text-[#17243f] shadow-sm hover:border-[#0bb7a5] hover:bg-[#e2faf6]"
        aria-expanded={isOpen}
        aria-label={`${notificationCount} notifications`}
      >
        <Icon path={notificationIconPath} className="h-5 w-5" />
        <span className="absolute -right-2 -top-2 inline-flex h-6 min-w-6 items-center justify-center rounded-full bg-[#ff1550] px-1.5 text-xs font-bold text-white shadow-sm">
          {notificationCount}
        </span>
      </button>

      {isOpen && (
        <div className="absolute right-0 top-14 z-30 w-[min(92vw,420px)] overflow-hidden rounded-lg border border-[#d9e1e8] bg-white shadow-xl">
          <div className="border-b border-[#d9e1e8] px-4 py-3">
            <p className="text-sm font-bold text-[#17243f]">Notifications</p>
            <p className="mt-1 text-xs text-[#5c6b7a]">
              {notificationCount === 1 ? "1 item needs attention." : `${notificationCount} items need attention.`}
            </p>
          </div>
          <div className="max-h-80 overflow-y-auto">
            {printableCount > 0 && (
              <section>
                <div className="bg-[#f3f6f9] px-4 py-2">
                  <p className="text-xs font-bold uppercase tracking-wide text-[#5c6b7a]">Requests Available To Print</p>
                </div>
                {requests.map((request) => (
                  <div
                    key={`print-${request.id}`}
                    role={onOpenDetails ? "button" : undefined}
                    tabIndex={onOpenDetails ? 0 : undefined}
                    onClick={() => openDetails(request)}
                    onKeyDown={(event) => handleItemKeyDown(event, request)}
                    className={notificationItemClass}
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold text-[#17243f]">{request.requestNumber}</p>
                      <p className="truncate text-xs text-[#5c6b7a]">{request.purpose}</p>
                    </div>
                    <button
                      type="button"
                      onClick={(event) => {
                        event.stopPropagation();
                        onPrint(request);
                        setIsOpen(false);
                      }}
                      className="shrink-0 rounded-lg bg-[#4e6493] px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-[#24365c]"
                    >
                      Print
                    </button>
                  </div>
                ))}
              </section>
            )}

            {transferAcknowledgementCount > 0 && (
              <section>
                <div className="bg-[#fff8d9] px-4 py-2">
                  <p className="text-xs font-bold uppercase tracking-wide text-[#9a6500]">Pending Acknowledgement</p>
                </div>
                {pendingTransferAcknowledgements.map((request) => (
                  <div
                    key={`transfer-${request.id}`}
                    role={onOpenDetails ? "button" : undefined}
                    tabIndex={onOpenDetails ? 0 : undefined}
                    onClick={() => openDetails(request)}
                    onKeyDown={(event) => handleItemKeyDown(event, request)}
                    className={notificationItemClass}
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold text-[#17243f]">{request.requestNumber}</p>
                      <p className="truncate text-xs text-[#5c6b7a]">{request.purpose}</p>
                    </div>
                    {onOpenAcknowledgement && (
                      <button
                        type="button"
                        onClick={(event) => {
                          event.stopPropagation();
                          onOpenAcknowledgement(request);
                          setIsOpen(false);
                        }}
                        className="shrink-0 rounded-lg bg-[#9a6500] px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-[#744c00]"
                      >
                        Acknowledge
                      </button>
                    )}
                  </div>
                ))}
              </section>
            )}

            {receiptAcknowledgementCount > 0 && (
              <section>
                <div className="bg-[#e2faf6] px-4 py-2">
                  <p className="text-xs font-bold uppercase tracking-wide text-[#08786f]">Pending Receipt Acknowledgement</p>
                </div>
                {pendingReceiptAcknowledgements.map((request) => (
                  <div
                    key={`receipt-${request.id}`}
                    role={onOpenDetails ? "button" : undefined}
                    tabIndex={onOpenDetails ? 0 : undefined}
                    onClick={() => openDetails(request)}
                    onKeyDown={(event) => handleItemKeyDown(event, request)}
                    className={`${notificationItemClass} last:border-b-0`}
                  >
                    <div className="min-w-0">
                      <p className="truncate text-sm font-semibold text-[#17243f]">{request.requestNumber}</p>
                      <p className="truncate text-xs text-[#5c6b7a]">
                        PHP {(request.returnAmount ?? 0).toLocaleString()} return
                      </p>
                    </div>
                    {onCreateReceipt && (
                      <button
                        type="button"
                        onClick={(event) => {
                          event.stopPropagation();
                          onCreateReceipt(request);
                          setIsOpen(false);
                        }}
                        className="shrink-0 rounded-lg bg-[#0bb7a5] px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-[#099988]"
                      >
                        {request.acknowledgementReceipt ? "Continue" : "Create AR"}
                      </button>
                    )}
                  </div>
                ))}
              </section>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
