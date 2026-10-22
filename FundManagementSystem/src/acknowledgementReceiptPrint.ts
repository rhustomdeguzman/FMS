import type { AppUser, CashAdvanceRequest } from "./types/CashAdvance";

interface AcknowledgementReceiptPrintOptions {
  variant?: "cashier" | "custodian" | "custodian_liquidation" | "custodian_release";
  receiptNumber?: string;
}

type SimpleReceiptKind = "return" | "liquidation" | "release";

const acknowledgementReceiptTemplate = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Acknowledgement Receipt</title>

    <style>
        * {
            box-sizing: border-box;
        }

        html,
        body {
            margin: 0;
            padding: 0;
            background: #9e9e9e;
            font-family: Arial, Helvetica, sans-serif;
        }

        .page-frame {
            width: 918px;
            height: 1188px;
            margin: 13px auto;
            overflow: hidden;
            background: #fff;
            box-shadow: 1px 1px 3px #333;
        }

        .page {
            position: relative;
            width: 612pt;
            height: 792pt;
            overflow: hidden;
            background: #fff;
            transform: scale(1.125);
            transform-origin: left top;
        }

        .print-area {
            position: absolute;
            left: 18pt;
            bottom: 18pt;
            width: 576pt;
            height: 756pt;
            overflow: hidden;
        }

        .field {
            position: absolute;
            margin: 0;
            color: #000;
            white-space: nowrap;
            line-height: 0.938477;
            font-weight: 700;
            transform: translateY(10.6pt);
        }

        .font-large {
            font-size: 7.8pt;
        }

        .font-medium {
            font-size: 6.95pt;
        }

        .font-small {
            font-size: 6.05pt;
        }

        .date {
            left: 404pt;
            bottom: 667.65pt;
        }

        .payee {
            left: 219pt;
            bottom: 651.6pt;
        }

        .amount-words {
            left: 158pt;
            bottom: 612.6pt;
        }

        .main-amount {
            left: 165pt;
            bottom: 597.65pt;
        }

        .property {
            left: 195pt;
            bottom: 639.6pt;
        }

        .amount-one {
            left: 372pt;
            bottom: 518.65pt;
        }

        .amount-two {
            left: 372pt;
            bottom: 573.65pt;
        }

        .reference {
            left: 163pt;
            bottom: 574.6pt;
        }

        .prepared-by {
            left: 407.75pt;
            bottom: 481.6pt;
        }

        .category-right {
            left: 336pt;
            bottom: 598.6pt;
        }

        .category-left {
            left: 0;
            bottom: 687.55pt;
        }

        .bottom-amount {
            left: 68pt;
            bottom: 686.6pt;
        }

        .main-amount,
        .amount-one,
        .amount-two,
        .reference,
        .category-right,
        .category-left,
        .bottom-amount {
            transform: translateY(7.8pt);
        }

        @media print {
            @page {
                size: 8.5in 11in;
                margin: 0;
            }

            html,
            body {
                width: 8.5in;
                height: 11in;
                background: #fff;
            }

            .page-frame {
                width: 612pt;
                height: 792pt;
                margin: 0;
                box-shadow: none;
            }

            .page {
                transform: none;
            }
        }
    </style>
</head>
<body>
    <main class="page-frame">
        <section class="page">
            <div class="print-area">
                <p class="field font-large date">AR# {{Receipt Number}}<br>{{Date Today}}</p>

                <p class="field font-medium payee">
                    {{Requestor}}
                </p>

                <p class="field font-medium amount-words">
                    {{Amount in Words}}
                </p>

                <p class="field font-large main-amount">{{Return Amount}}</p>

                <p class="field font-medium property">
                    {{Department}}
                </p>

                <p class="field font-large amount-one">{{Return Amount}}</p>
                <p class="field font-large amount-two">{{Return Amount}}</p>

                <p class="field font-medium reference">
                    Cash
                </p>

                <p class="field font-medium prepared-by">
                    {{Cashier User}}
                </p>

                <p class="field font-medium category-right">{{Request No.}}</p>
                <p class="field font-small category-left">{{Request No.}}</p>
                <p class="field font-medium bottom-amount">{{Return Amount}}</p>
            </div>
        </section>
    </main>
    <script>
        window.addEventListener("load", function () {
            window.setTimeout(function () {
                window.print();
            }, 250);
        });
    </script>
</body>
</html>`;

const simpleTwoCopyAcknowledgementReceiptTemplate = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Acknowledgement Receipt</title>
    <style>
        * {
            box-sizing: border-box;
        }

        html,
        body {
            margin: 0;
            padding: 0;
            background: #9e9e9e;
            font-family: Arial, Helvetica, sans-serif;
            color: #111;
        }

        .page-frame {
            width: 8.5in;
            min-height: 11in;
            margin: 16px auto;
            background: #fff;
            box-shadow: 0 1px 4px rgba(0, 0, 0, 0.35);
        }

        .page {
            width: 8.5in;
            height: 11in;
            padding: 0.35in 0.45in;
            display: grid;
            grid-template-rows: 1fr 1fr;
            gap: 0.22in;
        }

        .copy {
            border: 1px solid #111;
            padding: 0.18in 0.22in;
            display: flex;
            flex-direction: column;
            min-height: 0;
        }

        .copy-header {
            display: flex;
            justify-content: space-between;
            gap: 16px;
            border-bottom: 1px solid #111;
            padding-bottom: 8px;
        }

        .copy-label {
            font-size: 10px;
            font-weight: 700;
            letter-spacing: 0;
            text-transform: uppercase;
        }

        h1 {
            margin: 0;
            font-size: 18px;
            line-height: 1.2;
            text-transform: uppercase;
        }

        .meta {
            margin-top: 3px;
            font-size: 11px;
            line-height: 1.35;
        }

        .summary {
            margin: 12px 0 10px;
            font-size: 12px;
            line-height: 1.55;
        }

        .amount {
            margin: 0 0 10px;
            border: 1px solid #111;
            padding: 8px 10px;
            font-size: 14px;
            font-weight: 700;
            text-align: center;
        }

        .details {
            width: 100%;
            border-collapse: collapse;
            font-size: 11px;
        }

        .details td {
            border: 1px solid #555;
            padding: 5px 7px;
            vertical-align: top;
        }

        .details .label {
            width: 31%;
            background: #f2f2f2;
            font-weight: 700;
        }

        .line-section {
            margin-top: 8px;
        }

        .section-title {
            display: flex;
            justify-content: space-between;
            gap: 12px;
            margin: 0 0 4px;
            font-size: 10px;
            font-weight: 700;
            text-transform: uppercase;
        }

        .line-items {
            width: 100%;
            border-collapse: collapse;
            font-size: 9px;
            line-height: 1.22;
        }

        .line-items th,
        .line-items td {
            border: 1px solid #777;
            padding: 3px 4px;
            vertical-align: top;
        }

        .line-items th {
            background: #f2f2f2;
            text-align: left;
        }

        .text-right {
            text-align: right;
            white-space: nowrap;
        }

        .empty-lines {
            margin: 0;
            border: 1px solid #777;
            padding: 5px 7px;
            font-size: 9px;
            color: #444;
        }

        .signature-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 26px;
            margin-top: auto;
            padding-top: 18px;
            font-size: 11px;
        }

        .signature-line {
            border-top: 1px solid #111;
            padding-top: 5px;
            text-align: center;
        }

        @media print {
            @page {
                size: 8.5in 11in;
                margin: 0;
            }

            html,
            body {
                width: 8.5in;
                height: 11in;
                background: #fff;
            }

            .page-frame {
                margin: 0;
                box-shadow: none;
            }
        }
    </style>
</head>
<body>
    <main class="page-frame">
        <section class="page">
            {{Receipt Copies}}
        </section>
    </main>
    <script>
        window.addEventListener("load", function () {
            window.setTimeout(function () {
                window.print();
            }, 250);
        });
    </script>
</body>
</html>`;

const belowTwenty = [
  "Zero",
  "One",
  "Two",
  "Three",
  "Four",
  "Five",
  "Six",
  "Seven",
  "Eight",
  "Nine",
  "Ten",
  "Eleven",
  "Twelve",
  "Thirteen",
  "Fourteen",
  "Fifteen",
  "Sixteen",
  "Seventeen",
  "Eighteen",
  "Nineteen",
];

const tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"];
const thousands = ["", "Thousand", "Million", "Billion"];

const escapeHtml = (value: string) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

const formatDate = (date: Date) =>
  date.toLocaleDateString("en-PH", {
    year: "numeric",
    month: "long",
    day: "2-digit",
  });

const formatCurrency = (amount: number) =>
  `PHP ${amount.toLocaleString("en-PH", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;

const firstPositiveAmount = (...amounts: Array<number | undefined>) =>
  amounts.find((amount) => amount !== undefined && Number.isFinite(amount) && amount > 0) ?? 0;

const formatOptionalDate = (value: string) => {
  if (!value) {
    return "";
  }

  const date = new Date(`${value}T00:00:00`);
  return Number.isNaN(date.getTime()) ? value : formatDate(date);
};

const wordsBelowThousand = (value: number): string => {
  const words: string[] = [];
  const hundreds = Math.floor(value / 100);
  const remainder = value % 100;

  if (hundreds > 0) {
    words.push(`${belowTwenty[hundreds]} Hundred`);
  }

  if (remainder >= 20) {
    const tensWord = tens[Math.floor(remainder / 10)];
    const ones = remainder % 10;
    words.push(ones > 0 ? `${tensWord} ${belowTwenty[ones]}` : tensWord);
  } else if (remainder > 0 || words.length === 0) {
    words.push(belowTwenty[remainder]);
  }

  return words.join(" ");
};

const wholeNumberToWords = (value: number): string => {
  if (value === 0) {
    return belowTwenty[0];
  }

  const words: string[] = [];
  let remaining = value;
  let groupIndex = 0;

  while (remaining > 0) {
    const group = remaining % 1000;
    if (group > 0) {
      const scale = thousands[groupIndex];
      words.unshift([wordsBelowThousand(group), scale].filter(Boolean).join(" "));
    }

    remaining = Math.floor(remaining / 1000);
    groupIndex += 1;
  }

  return words.join(" ");
};

const amountToWords = (amount: number): string => {
  const roundedCents = Math.round(amount * 100);
  const pesos = Math.floor(roundedCents / 100);
  const centavos = roundedCents % 100;
  const centavoText = centavos > 0 ? ` AND ${String(centavos).padStart(2, "0")}/100` : "";

  return `${wholeNumberToWords(pesos).toUpperCase()} PESOS${centavoText} ONLY`;
};

const getRequestTypeLabel = (request: CashAdvanceRequest) => {
  if (request.requestType === "petty_cash") return "Petty Cash";
  if (request.requestType === "petty_cash_advance") return "Petty Cash Advance";
  if (request.requestType === "petty_cash_replenishment") return "Petty Cash Replenishment";
  return "Cash Advance";
};

const buildReturnReceiptBody = () => `
                <table class="details">
                    <tbody>
                        <tr>
                            <td class="label">Date</td>
                            <td>{{Date Today}}</td>
                        </tr>
                        <tr>
                            <td class="label">Department</td>
                            <td>{{Department}}</td>
                        </tr>
                        <tr>
                            <td class="label">Request Type</td>
                            <td>{{Request Type}}</td>
                        </tr>
                        <tr>
                            <td class="label">Cash Advance Amount</td>
                            <td>{{Cash Advance Amount}}</td>
                        </tr>
                        <tr>
                            <td class="label">Actual Amount Spent</td>
                            <td>{{Actual Amount Spent}}</td>
                        </tr>
                        <tr>
                            <td class="label">Amount Returned</td>
                            <td>{{Return Amount}}</td>
                        </tr>
                    </tbody>
                </table>`;

const buildPettyCashLiquidationReceiptBody = (request: CashAdvanceRequest) => {
  const receiptDetails = request.pettyCashReceiptDetails ?? [];
  const transportationDetails = request.pettyCashTransportationDetails ?? [];
  const receiptTotal = receiptDetails.reduce((sum, detail) => sum + detail.amount, 0);
  const transportationTotal = transportationDetails.reduce((sum, detail) => sum + detail.amount, 0);
  const receiptRows =
    receiptDetails.length > 0
      ? receiptDetails
          .map(
            (detail) => `
                        <tr>
                            <td>${escapeHtml(detail.orNumber)}</td>
                            <td>${escapeHtml(detail.company)}</td>
                            <td>${escapeHtml(detail.natureOfExpense)}</td>
                            <td>${escapeHtml(formatOptionalDate(detail.orDate))}</td>
                            <td class="text-right">${escapeHtml(formatCurrency(detail.amount))}</td>
                        </tr>`,
          )
          .join("")
      : "";
  const transportationRows =
    transportationDetails.length > 0
      ? transportationDetails
          .map(
            (detail) => `
                        <tr>
                            <td>${escapeHtml(formatOptionalDate(detail.transactionDate))}</td>
                            <td>${escapeHtml(detail.description)}</td>
                            <td>${escapeHtml([detail.from, detail.to].filter(Boolean).join(" to "))}</td>
                            <td class="text-right">${escapeHtml(formatCurrency(detail.amount))}</td>
                        </tr>`,
          )
          .join("")
      : "";

  return `
                <div class="line-section">
                    <p class="section-title">
                        <span>Receipt Details</span>
                        <span>${escapeHtml(formatCurrency(receiptTotal))}</span>
                    </p>
                    ${
                      receiptRows
                        ? `<table class="line-items">
                    <thead>
                        <tr>
                            <th>OR No.</th>
                            <th>Company</th>
                            <th>Expense</th>
                            <th>Date</th>
                            <th class="text-right">Amount</th>
                        </tr>
                    </thead>
                    <tbody>${receiptRows}
                    </tbody>
                </table>`
                        : `<p class="empty-lines">No receipt details submitted.</p>`
                    }
                </div>
                <div class="line-section">
                    <p class="section-title">
                        <span>Transportation Expenses</span>
                        <span>${escapeHtml(formatCurrency(transportationTotal))}</span>
                    </p>
                    ${
                      transportationRows
                        ? `<table class="line-items">
                    <thead>
                        <tr>
                            <th>Date</th>
                            <th>Description</th>
                            <th>Route</th>
                            <th class="text-right">Amount</th>
                        </tr>
                    </thead>
                    <tbody>${transportationRows}
                    </tbody>
                </table>`
                        : `<p class="empty-lines">No transportation expenses submitted.</p>`
                    }
                </div>`;
};

const buildPettyCashAdvanceLiquidationReceiptBody = () => `
                <table class="details">
                    <tbody>
                        <tr>
                            <td class="label">Purpose</td>
                            <td>{{Purpose}}</td>
                        </tr>
                        <tr>
                            <td class="label">Amount</td>
                            <td>{{Acknowledged Amount}}</td>
                        </tr>
                    </tbody>
                </table>`;

const buildPettyCashAdvanceReleaseReceiptBody = () => `
                <table class="details">
                    <tbody>
                        <tr>
                            <td class="label">Date</td>
                            <td>{{Date Today}}</td>
                        </tr>
                        <tr>
                            <td class="label">Department</td>
                            <td>{{Department}}</td>
                        </tr>
                        <tr>
                            <td class="label">Request Type</td>
                            <td>{{Request Type}}</td>
                        </tr>
                        <tr>
                            <td class="label">Purpose</td>
                            <td>{{Purpose}}</td>
                        </tr>
                        <tr>
                            <td class="label">Released Amount</td>
                            <td>{{Acknowledged Amount}}</td>
                        </tr>
                    </tbody>
                </table>`;

const buildLiquidationReceiptBody = (request: CashAdvanceRequest) =>
  request.requestType === "petty_cash"
    ? buildPettyCashLiquidationReceiptBody(request)
    : buildPettyCashAdvanceLiquidationReceiptBody();

const buildSimpleReceiptCopy = (
  copyLabel: string,
  kind: SimpleReceiptKind,
  bodyHtml: string,
) => `
            <article class="copy">
                <div class="copy-header">
                    <div>
                        <h1>Acknowledgement Receipt</h1>
                        <p class="meta">Receipt No.: {{Receipt No.}}<br>Request No.: {{Request No.}}</p>
                    </div>
                    <div class="copy-label">${copyLabel}</div>
                </div>
                <p class="summary">
                    ${
                      kind === "return"
                        ? "This acknowledges that {{Requestor}} returned the excess petty cash amount to {{Custodian User}} for request {{Request No.}}."
                        : kind === "release"
                          ? "This acknowledges that {{Custodian User}} released the petty cash advance to {{Requestor}} for request {{Request No.}}."
                          : "This acknowledges that {{Custodian User}} approved and accepted the petty cash liquidation submitted by {{Requestor}} for request {{Request No.}}."
                    }
                </p>
                <p class="amount">{{Acknowledged Amount}} ({{Amount in Words}})</p>
                ${bodyHtml}
                <div class="signature-grid">
                    <div class="signature-line">${
                      kind === "return"
                        ? "Received by / Custodian"
                        : kind === "release"
                          ? "Released by / Custodian"
                          : "Approved by / Custodian"
                    }</div>
                    <div class="signature-line">${
                      kind === "return" ? "Returned by / Requestor" : "Acknowledged by / Requestor"
                    }</div>
                </div>
            </article>`;

const buildCustodianAcknowledgementReceiptPrintHtml = (
  request: CashAdvanceRequest,
  custodian: AppUser,
  receiptNumber: string,
) => {
  const returnAmount = request.returnAmount ?? 0;
  const actualSpent = request.liquidationAmount ?? request.liquidatedAmount;
  const referenceNumber = request.referenceNumber?.trim() || request.requestNumber;
  const returnReceiptBody = buildReturnReceiptBody();
  const copies = [
    buildSimpleReceiptCopy("Custodian Copy", "return", returnReceiptBody),
    buildSimpleReceiptCopy("Requestor Copy", "return", returnReceiptBody),
  ].join("");
  const tokens: Record<string, string> = {
    "Date Today": formatDate(new Date()),
    "Receipt No.": receiptNumber,
    Requestor: request.originalOwner.name,
    "Amount in Words": amountToWords(returnAmount),
    "Acknowledged Amount": formatCurrency(returnAmount),
    "Return Amount": formatCurrency(returnAmount),
    Department: request.originalOwner.department || request.department,
    "Request No.": referenceNumber,
    "Custodian User": custodian.name,
    "Cash Advance Amount": formatCurrency(request.amount),
    "Actual Amount Spent": formatCurrency(actualSpent),
    "Request Type": getRequestTypeLabel(request),
  };

  return Object.entries(tokens).reduce(
    (html, [key, value]) => html.replaceAll(`{{${key}}}`, escapeHtml(value)),
    simpleTwoCopyAcknowledgementReceiptTemplate.replace("{{Receipt Copies}}", copies),
  );
};

const buildCustodianLiquidationAcknowledgementReceiptPrintHtml = (
  request: CashAdvanceRequest,
  custodian: AppUser,
  receiptNumber: string,
) => {
  const pettyCashReceiptTotal = (request.pettyCashReceiptDetails ?? []).reduce(
    (sum, detail) => sum + detail.amount,
    0,
  );
  const pettyCashTransportationTotal = (request.pettyCashTransportationDetails ?? []).reduce(
    (sum, detail) => sum + detail.amount,
    0,
  );
  const pettyCashDetailTotal = pettyCashReceiptTotal + pettyCashTransportationTotal;
  const liquidationAmount =
    request.requestType === "petty_cash_advance"
      ? firstPositiveAmount(request.amount, request.liquidationAmount, request.liquidatedAmount)
      : firstPositiveAmount(pettyCashDetailTotal, request.liquidationAmount, request.liquidatedAmount, request.amount);
  const returnAmount = request.returnAmount ?? 0;
  const referenceNumber = request.referenceNumber?.trim() || request.requestNumber;
  const liquidationReceiptBody = buildLiquidationReceiptBody(request);
  const copies = [
    buildSimpleReceiptCopy("Custodian Copy", "liquidation", liquidationReceiptBody),
    buildSimpleReceiptCopy("Requestor Copy", "liquidation", liquidationReceiptBody),
  ].join("");
  const tokens: Record<string, string> = {
    "Date Today": formatDate(new Date()),
    "Receipt No.": receiptNumber,
    Requestor: request.originalOwner.name,
    "Amount in Words": amountToWords(liquidationAmount),
    "Acknowledged Amount": formatCurrency(liquidationAmount),
    "Return Amount": formatCurrency(returnAmount),
    Department: request.originalOwner.department || request.department,
    "Request No.": referenceNumber,
    "Custodian User": custodian.name,
    "Cash Advance Amount": formatCurrency(request.amount),
    "Actual Amount Spent": formatCurrency(liquidationAmount),
    "Request Type": getRequestTypeLabel(request),
    Purpose: request.purpose,
  };

  return Object.entries(tokens).reduce(
    (html, [key, value]) => html.replaceAll(`{{${key}}}`, escapeHtml(value)),
    simpleTwoCopyAcknowledgementReceiptTemplate.replace("{{Receipt Copies}}", copies),
  );
};

const buildCustodianReleaseAcknowledgementReceiptPrintHtml = (
  request: CashAdvanceRequest,
  custodian: AppUser,
  receiptNumber: string,
) => {
  const releaseAmount = request.amount;
  const referenceNumber = request.referenceNumber?.trim() || request.requestNumber;
  const releaseReceiptBody = buildPettyCashAdvanceReleaseReceiptBody();
  const copies = [
    buildSimpleReceiptCopy("Custodian Copy", "release", releaseReceiptBody),
    buildSimpleReceiptCopy("Requestor Copy", "release", releaseReceiptBody),
  ].join("");
  const tokens: Record<string, string> = {
    "Date Today": formatDate(new Date()),
    "Receipt No.": receiptNumber,
    Requestor: request.originalOwner.name,
    "Amount in Words": amountToWords(releaseAmount),
    "Acknowledged Amount": formatCurrency(releaseAmount),
    Department: request.originalOwner.department || request.department,
    "Request No.": referenceNumber,
    "Custodian User": custodian.name,
    "Request Type": getRequestTypeLabel(request),
    Purpose: request.purpose,
  };

  return Object.entries(tokens).reduce(
    (html, [key, value]) => html.replaceAll(`{{${key}}}`, escapeHtml(value)),
    simpleTwoCopyAcknowledgementReceiptTemplate.replace("{{Receipt Copies}}", copies),
  );
};

export const buildAcknowledgementReceiptPrintHtml = (
  request: CashAdvanceRequest,
  issuer: AppUser,
  options: AcknowledgementReceiptPrintOptions = {},
): string => {
  if (options.variant === "custodian") {
    return buildCustodianAcknowledgementReceiptPrintHtml(
      request,
      issuer,
      options.receiptNumber?.trim() || request.acknowledgementReceipt?.receiptNumber || request.requestNumber,
    );
  }

  if (options.variant === "custodian_liquidation") {
    return buildCustodianLiquidationAcknowledgementReceiptPrintHtml(
      request,
      issuer,
      options.receiptNumber?.trim() || request.requestNumber,
    );
  }

  if (options.variant === "custodian_release") {
    return buildCustodianReleaseAcknowledgementReceiptPrintHtml(
      request,
      issuer,
      options.receiptNumber?.trim() || request.requestNumber,
    );
  }

  const returnAmount = request.returnAmount ?? 0;
  const referenceNumber = request.referenceNumber?.trim() || request.requestNumber;
  const tokens: Record<string, string> = {
    "Date Today": formatDate(new Date()),
    Requestor: request.currentOwner.name,
    "Amount in Words": amountToWords(returnAmount),
    "Return Amount": formatCurrency(returnAmount),
    Department: request.currentOwner.department || request.department,
    "Request No.": referenceNumber,
    "Cashier User": issuer.name,
    "Receipt Number": options.receiptNumber?.trim() || request.acknowledgementReceipt?.receiptNumber || "",
  };

  return Object.entries(tokens).reduce(
    (html, [key, value]) => html.replaceAll(`{{${key}}}`, escapeHtml(value)),
    acknowledgementReceiptTemplate,
  );
};
