# Fund Management System

React and TypeScript frontend with an ASP.NET Core API and SQL Server database scripts.

## API

1. Install the .NET 8 SDK and configure SQL Server.
2. Copy `FundManagementAPI/FundManagementAPI/appsettings.example.json` to `appsettings.json` in the same directory and enter your database connection details. The local configuration is excluded from Git.
3. Follow the database setup and migration instructions in `FundManagementAPI/FundManagementAPI/Database/README.md`.
4. Run `dotnet run --project FundManagementAPI/FundManagementAPI`.

## Frontend

1. In `FundManagementSystem`, run `npm ci`.
2. Copy `.env.example` to `.env.local` if an API URL override is needed.
3. Run `npm run dev` for development or `npm run build` for a production build.

Dependencies, generated builds, runtime uploads, logs, and local credentials are excluded from this repository.
