# MODERN ERP Database — SQL Server Instructions

## Scope

These instructions apply to all files under `database/`.

Read the repository root `AGENTS.md` first. Read `server/AGENTS.md` whenever a SQL object is called by C# or changes an API-backed operation.

## Purpose and organization

Store version-controlled SQL Server definitions and deployment scripts here, organized by module and object type where practical:

- Tables
- Constraints
- User-defined table types
- Stored procedures
- Functions
- Views
- Indexes
- Seed or reference data
- Upgrade scripts
- Verification scripts
- Rollback scripts when a safe rollback is possible

Use descriptive filenames and preserve the repository's existing numbering or deployment convention.

## Inspect before editing

Before changing a database object:

1. Locate its current definition.
2. Find every C# repository or service that calls it.
3. Find related table types, tables, views, functions, triggers, and indexes.
4. Confirm parameter names, order, SQL types, lengths, precision, scale, and nullability.
5. Review existing business statuses, branch rules, fiscal-period rules, and audit fields.
6. Determine whether the change is backward compatible.
7. Identify the deployment order and rollback risk.

Do not create a second stored procedure or table type merely to avoid understanding the existing one.

## Safety rules

- Never execute destructive production changes unless explicitly authorized.
- Never include real credentials or production connection strings.
- Do not drop a table, column, constraint, index, procedure, function, view, trigger, or type without explicit approval and dependency review.
- Do not truncate or mass-update business data unless explicitly requested and protected by a controlled migration plan.
- Do not use `WITH (NOLOCK)` as a default performance fix.
- Do not disable constraints or triggers to make a script succeed without understanding the consequences.
- Do not silently change accounting, inventory, tax, posting, or document-number behavior.
- Include clear warnings for irreversible or blocking operations.

## Schema and data types

- Match existing legacy naming where compatibility requires it.
- Use appropriate Unicode types when values can contain Unicode text.
- Define string lengths deliberately.
- Use `decimal` or `numeric` with explicit precision and scale for money, quantity, rate, tax, discount, and totals.
- Do not use `float` or `real` for accounting values.
- Use date and time types consistently with the calling C# contract.
- Define nullability deliberately.
- Add primary keys, foreign keys, unique constraints, defaults, and checks when consistent with the existing schema and deployment risk.
- Preserve branch, warehouse, fiscal, document, source, status, and audit columns required by ERP behavior.

## Stored procedures

For new or modified stored procedures:

- Use `SET NOCOUNT ON`.
- Use explicit schemas, normally `dbo` unless the project uses another schema.
- Use parameterized inputs with correct types and lengths.
- Avoid `SELECT *`.
- Return stable, documented result sets.
- Use deterministic ordering when consumers depend on row order.
- Use `TRY...CATCH` and `SET XACT_ABORT ON` for transactional write procedures where consistent with the project.
- Start and commit a transaction only when the procedure owns the complete atomic operation.
- Avoid nested transaction assumptions; inspect how the C# caller manages transactions.
- Throw or return failures consistently with the repository's established error handling.
- Prevent duplicate processing and invalid status transitions.
- Return generated document identifiers and affected-row information when required by the caller.

## Header-detail and posting operations

For atomic document operations:

- Validate the header.
- Validate that required detail rows exist.
- Validate source documents and allowed statuses.
- Validate branch, warehouse, supplier, customer, account, and period references as applicable.
- Prevent duplicate document numbers.
- Prevent duplicate receiving, payment, liquidation, issuance, or posting.
- Save header, details, inventory movement, subledger, and journal effects inside one controlled transaction when the business process requires all-or-nothing behavior.
- Roll back on any error.
- Preserve audit fields.
- Do not post to accounting from an unapproved or ineligible source document.

## Table-valued parameters

When using a table-valued parameter:

- Keep the SQL type definition aligned exactly with the C# `DataTable`, record, or enumerable mapping.
- Verify column order.
- Verify column names.
- Verify SQL and CLR data types.
- Verify string lengths.
- Verify precision and scale.
- Verify nullability.
- Avoid changing a user-defined table type in place without reviewing dependencies; SQL Server may require controlled drop-and-recreate steps.
- Document the deployment sequence for procedures that depend on the type.

## Query and performance rules

For listing, search, reporting, and grid queries:

- Filter and page on the server.
- Avoid returning unused columns.
- Make predicates SARGable where practical.
- Avoid wrapping indexed filter columns in functions when a range predicate can be used.
- Review joins for multiplicative duplicates.
- Use `EXISTS` instead of unnecessary joins when only existence is required.
- Avoid broad `DISTINCT` as a substitute for fixing join logic.
- Use stable ordering for paging.
- Review indexes for common branch, date, status, supplier, customer, warehouse, document-number, and foreign-key filters.
- Consider write overhead before adding indexes.
- Do not increase command timeout as the primary performance solution.
- For high-volume changes, describe expected locking, blocking, log growth, and deployment impact.

## Concurrency and integrity

- Use unique constraints or other authoritative database protection for critical uniqueness rules.
- Use appropriate isolation and locking behavior for document-number generation and posting.
- Preserve row-version or optimistic concurrency behavior when present.
- Do not rely solely on a pre-check followed by an insert when concurrent requests can race.
- Ensure update and delete operations target the intended key and expected status.
- Verify affected-row counts for state transitions.

## Script quality

- Make scripts repeatable or safely guarded where practical.
- Separate object creation from production data migration when that improves safety.
- Include comments for deployment prerequisites, object dependencies, and non-obvious business rules.
- Do not include commented-out alternate implementations in final scripts.
- End statements consistently according to the project's SQL style.
- Qualify object names with schema.
- Provide a verification query for important deployments.
- Provide a rollback script only when rollback is technically safe; otherwise explain why forward correction is required.

## C# coordination checklist

Before finishing a SQL change, compare it with the calling C# code:

- Stored-procedure name.
- Parameter names and directions.
- SQL types versus CLR types.
- String lengths.
- Decimal precision and scale.
- Nullable behavior.
- Result-set column names.
- Output parameters or return values.
- Transaction ownership.
- Timeout and cancellation behavior.
- TVP definition and row mapping.

Update the C# caller in the same task when the database contract changes.

## Verification

At minimum:

- Review syntax against the target SQL Server version.
- Review object dependencies and deployment order.
- Review transaction and error paths.
- Review duplicate-processing protection.
- Review affected-row logic.
- Review expected indexes and likely query plan.
- Verify result-set columns against C# DTO mappings.
- Verify TVPs against C# row construction.

If a test database connection is available and authorized, execute the script in a controlled non-production environment and run focused verification queries. Never claim execution success when only static review was performed.

## Completion checklist

Before finishing a database task, confirm:

- The script is stored in the correct module and object folder.
- Dependencies and execution order are documented.
- C# parameters and mappings match.
- Transaction ownership is clear.
- Duplicate and invalid-state protection exists.
- Destructive behavior is explicitly authorized or avoided.
- Verification steps are included.
- Deployment and rollback risks are reported.
