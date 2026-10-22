# FundManagementSystem Database Setup

This project expects SQL Server 2019 and stored procedures. The API does not create tables at runtime.

## Create The Database

1. Open SQL Server Management Studio.
2. Connect to your SQL Server 2019 instance.
3. Open `FundManagementSystem.sql`.
4. Execute the whole script.

The script creates `FundManagementSystem` if it does not exist, then creates only the cash-advance tables, indexes, and stored procedures used by the API. Tables use the `FMS_` prefix and stored procedures use the `sp_` prefix.

Current tables:

| Table | Purpose |
| --- | --- |
| `FMS_AppUsers` | Simple role-login users |
| `FMS_CashAdvanceStatuses` | Cash advance request status lookup, with `0 = pending_liquidation` |
| `FMS_CashAdvanceRequests` | Cash advance requests, liquidation amounts, workflow status ID, and RFP reference |
| `FMS_CashAdvanceAttachments` | Uploaded liquidation attachment file names |
| `FMS_CashAdvanceAcknowledgementReceipts` | Cashier acknowledgement receipts for returned excess cash |
| `FMS_CashAdvanceHistory` | Workflow action history |
| `FMS_CashAdvanceTransfers` | Transfer requests, acknowledgement or denial status, and split-request reference |

The old fund/investor/subscription/redemption/NAV/distribution/cash-transaction tables and procedures are no longer created by this script. If you already ran the older script before, those old objects may still exist in your database. Back up your database first, then remove those old objects manually only if you are sure you do not need their data.

It also seeds simple role-login users:

| Username | Password | Role |
| --- | --- | --- |
| `requestor` | `password123` | Requestor |
| `depthead` | `password123` | Department Head |
| `accounting` | `password123` | Accounting |
| `cashier` | `password123` | Cashier |

## RFP Repository Stored Procedures

Apply RfpRepositoryStoredProceduresMigration.sql to FMS after the existing RFP workflow and routing migrations, before running the updated API. It moves the repository SQL into stored procedures and preserves transaction locks and SQL options through wrappers around department approval and FineReport saving. The API login needs permission to execute the new procedures and access the existing FineReport objects.

Also apply RfpAttachmentServiceStoredProceduresMigration.sql to FMS before running the updated API. It creates procedures for attachment metadata, liquidation attachment listing, and FineReport file registration used by RfpAttachmentService. The API login needs execute permission for these procedures and access to the existing FineReport objects.

## FineReport User IDs

Apply `RfpPayeeLiquidationAccessMigration.sql` after the existing workflow migrations before deploying the updated API and frontend. It lets a uniquely matched active RFP payee view the cash advance and claim custody when submitting liquidation. Matching ignores case, spaces, commas, and periods; ambiguous names receive no additional access. Transferred child requests are excluded. The script reports the resolved payee user for RFP 53963 (expected user 122). Existing status and pending-transfer checks still apply.

Run `FineReportMainUsersFmsIdMigration.sql` in the FMS database to populate existing `FineReport..Main_Users.FMS_id` values from `dbo.FMS_AppUsers.UserId`, matching trimmed, case-insensitive email addresses. The target column must already exist. Unmatched users remain unchanged; duplicate normalized FMS emails stop the transaction. The script reports the number of updated rows and can be rerun.

Reapply `FineReportRequestorUserImportMigration.sql` to synchronize these IDs during subsequent requestor imports, including users already present in FMS. The executing login needs UPDATE permission on `FineReport..Main_Users`.

## Configure The API Connection

Update `appsettings.json` if your SQL Server name is different:

```json
"ConnectionStrings": {
  "FundManagementDatabase": "Server=localhost;Database=FundManagementSystem;Trusted_Connection=True;TrustServerCertificate=True;"
}
```

For SQL login authentication, use this format instead:

```json
"ConnectionStrings": {
  "FundManagementDatabase": "Server=YOUR_SERVER_NAME;Database=FundManagementSystem;User Id=YOUR_USER;Password=YOUR_PASSWORD;TrustServerCertificate=True;"
}
```

## Run The API

From the solution folder:

```powershell
dotnet restore
dotnet run --project .\FundManagementAPI\FundManagementAPI.csproj
```

Open Swagger at the URL shown in the terminal, usually:

```text
https://localhost:7000/swagger
```

or use `FundManagementAPI.http` from Visual Studio.

## Auth Endpoints

Use `POST /api/auth/login` with:

```json
{
  "username": "requestor",
  "password": "password123"
}
```

Use `GET /api/auth/users` to list configured users.

## Cash Advance Workflow

The workflow script supports this process:

1. Requestor can keep the full cash advance, request a whole transfer to another requestor or department approver, or request a partial transfer.
2. The receiver must acknowledge or deny the transfer. Accepted whole transfers move ownership; accepted partial transfers create a split request. Denied transfers are only recorded in history.
3. Requestor submits liquidation with amount spent and attachments. A same-department department head can also claim full custody of an RFP cash advance and liquidate it.
4. Department head approves or returns the submitted liquidation.
5. If requested amount equals amount spent, the request goes to accounting closure.
6. If requested amount is greater than amount spent, the request goes to accounting first, then cashier receipt creation, then accounting again, then cashier closure.
7. If amount spent is greater than the requested amount, the department head chooses Create RFP or Waive RFP during approval.
8. Create RFP sends the request back to the requestor for the RFP attachment, then accounting approves and closes the transaction.
9. Waive RFP requires a waiver reason, then accounting approves and closes the transaction.

Example: if the requested amount is `10000` and the amount spent is `13000`, the department head chooses whether the excess `3000` needs an RFP. If Create RFP is selected, the requestor uploads the RFP attachment before accounting approval.

Useful endpoints:

```text
GET  /api/cash-advance?userId=1&role=requestor&department=MIS
GET  /api/cash-advance/{printToken}/print?userId=1&role=requestor&department=MIS
POST /api/cash-advance/{id}/transfer
POST /api/cash-advance/{id}/transfer-response
POST /api/cash-advance/{id}/liquidation
POST /api/cash-advance/{id}/rfp-attachment
POST /api/cash-advance/{id}/department-decision
POST /api/cash-advance/{id}/cashier-receipt
POST /api/cash-advance/{id}/accounting-decision
POST /api/cash-advance/{id}/cashier-closure
```
