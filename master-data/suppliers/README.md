# Supplier Master database deployment

Target database: the `INVENTORY` connection (`RISCDB` in the inspected local development configuration).

The live database reports compatibility level `100`, so these scripts use SQL Server 2008-compatible procedure syntax and `ROW_NUMBER()` paging. They do not use `CREATE OR ALTER`, `THROW`, `OFFSET/FETCH`, `STRING_AGG`, or `FORMAT`.

## Deployment order

1. `001_supplier_permissions.sql`
2. `002_usp_Supplier_Query.sql`
3. `003_usp_Supplier_GetByCode.sql`
4. `004_usp_Supplier_Validate.sql`
5. `005_usp_Supplier_Create.sql`
6. `006_usp_Supplier_Update.sql`
7. `007_usp_Supplier_SetActiveStatus.sql`
8. `008_supplier_lookups.sql`
9. `009_supplier_verification.sql` — authorized development/test database only

Scripts 002-008 create a harmless stub only when a procedure is absent and then use `ALTER PROCEDURE`, making repeat deployments possible without dropping objects.

Script 001 registers the permission keys but deliberately does not assign them to hardcoded roles or departments. Existing security administration must grant `SUPPLIER_VIEW`, `SUPPLIER_CREATE`, `SUPPLIER_EDIT`, `SUPPLIER_ACTIVATE`, and `SUPPLIER_DEACTIVATE` as appropriate; accounts marked with the existing administrator flag retain their established administrative override.

## Verified legacy contract

- `dbo.a_suppliers` remains the only supplier master. No table, column, type, trigger, or legacy supplier procedure is replaced.
- Supplier codes are manually supplied, normalized to uppercase, immutable after creation, and protected by the existing `PK_a_suppliers` key.
- `a_supp_group`, `a_terms`, `a_currency`, and active (`CHRX_APFLG = 'Y'`) `AP_CHRX` rows are the authoritative lookups.
- Terms, currency, TIN, and tax profile remain optional because the current schema and data allow them. A supplied lookup value must exist.
- TIN comparisons ignore case, spaces, hyphens, periods, slashes, and parentheses. New suppliers and changed TIN values cannot duplicate another normalized TIN. An unchanged normalized TIN remains editable so existing legacy shared-TIN records are not stranded.
- Duplicate-TIN enforcement uses serializable locking but remains a best-effort legacy safeguard: the existing duplicate data prevents an authoritative normalized unique index. Reassess a normalized persisted key only through a separately approved data-cleansing migration.
- Similar names produce a warning rather than a hard failure because current data already contains legitimate duplicate names.
- Create always sets `active_flag = 'Y'`. Only the status procedure can deactivate or reactivate; there is no delete procedure.
- `date_changed` is the optimistic-concurrency token. The procedures force it to advance, but SQL `datetime` is still weaker than `rowversion` and legacy writers that do not honor the token can bypass optimistic checks.
- The Supplier TaxProfile is a default only. These scripts do not alter VP detail-level tax handling.

## Index decision

No index is added. The inspected table has 994 rows plus an existing primary key and indexes on supplier name, supplier group, and currency. Existing normalized-TIN duplicates prevent a unique normalized-TIN index, and the current volume does not justify extra write overhead for status/terms/tax filters. Reassess with an actual execution plan if volume grows materially.

## Verification and rollback

`009_supplier_verification.sql` performs command, validation, concurrency, lifecycle, lookup, paging, and search checks with unique test codes, then removes only those generated test rows. Do not run it in production.

No automated rollback script is supplied because dropping procedures or permission metadata could break a deployed API. Use a forward-correction deployment. The module does not modify PO, RR, VP, ADP, CD, COA, journal, or posting objects, so their existing supplier references and historical rows remain intact.
