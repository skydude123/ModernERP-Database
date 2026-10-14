# Material Issuance deployment

Run `000` as a read-only preflight, then deploy `001`, `002`, `005`, `003`,
`004`, and `006` in that order. Populate `dbo.a_issue_account_map` under accounting
change control before posting.

The inspected `RISCDB` has no `dbo.TWB_JRNLdtl`; its verified equivalent is
`dbo.twb_rawmats`, also used by the existing issuance trigger. The adapter
writes `TWB_JRNLhdr` plus `twb_rawmats` and keeps the higher precision module
journal as the audit source.
