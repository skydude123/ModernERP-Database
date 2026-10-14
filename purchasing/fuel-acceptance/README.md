# Simple Fuel Consumption Acceptance

Deploy `FuelAcceptance_Full.sql` in a controlled non-production database first.
The script creates the schema, TVP, sequences, lookup/read procedures, atomic
save/upsert, post, reverse, and Voucher Payable source procedure.

Fuel Acceptance is deliberately non-stocking. Save, post, and reverse do not
update inventory, warehouse, PO received quantities, receiving, or GL tables.
Posted (`A`) documents are exposed by `dbo.usp_FuelAcceptance_OpenForVP`.
Reversed (`R`) documents retain their audit trail and release the PO for a
replacement Fuel Acceptance.

The header stores an authoritative PO amount snapshot. Save/upsert recomputes
that amount from `dbo.a_po_det`, rejects Fuel Acceptance totals above it, and
recomputes every fuel, VAT, EWT, and net amount instead of trusting the browser.

Before production deployment, confirm the legacy PO columns used by the script:
`a_po_hdr.po_no`, `po_date`, `supp_code`, `branchname`, `status`, `po_type`, and
`a_po_det.po_no`, `item_desc`, `qty_po`, `unit_price`. The module expects `BRANCH.branchname`,
`a_suppliers.supp_code/supp_name`, and `TaxScheme.vat_type/tax_name`.

Stored procedures use the SQL Server 2012-compatible create-stub/alter pattern.

If an older Fuel Acceptance prototype was already deployed, use a reviewed
migration instead of running this fresh-schema script over incompatible tables.
SQL Server user-defined table types cannot be altered in place.
