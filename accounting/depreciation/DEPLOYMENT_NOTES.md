# Depreciation deployment

Run scripts `000` through `011` in filename order in a controlled non-production
database. Script `000` is read-only. Back up the target database and review its
results before continuing.

The source-controlled fixed-asset contract is `dbo.a_asset_master`; this package
does not rename or modify its columns. Posting uses the additive, balanced
`a_dep_journal_hdr` / `a_dep_journal_dtl` journal boundary because the supplied
legacy database backups are binary and their `TWB_JRNL*` / `GJ_*` column contracts
are not versioned in this repository. Before production deployment, the accounting
owner must either:

1. confirm these tables are the approved journal source consumed by Trial Balance; or
2. replace only the journal insert section in `007` and `008` with the site's
   existing journal-posting adapter, preserving the transaction, idempotency,
   debit/credit direction, and `a_dep_run_journal_link`.

Do not deploy posting to production until that controlled accounting integration
review is complete. A `.trdp` is intentionally not fabricated. Create
`DepreciationSchedule.trdp` in Telerik Report Designer 2026 Q2, use named
connection `TwinBeeErpReporting`, procedure `dbo.usp_Depreciation_ReportData`,
parameter `dep_run_no`, and visible title `DEPRECIATION SCHEDULE`.
