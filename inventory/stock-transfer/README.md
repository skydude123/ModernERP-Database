# Stock Transfer deployment

Run the scripts in this order:

1. `000_stock_transfer_preflight.sql` (read-only validation)
2. `001_stock_transfer_schema.sql`
3. `002_stock_transfer_queries.sql`
4. `003_usp_StockTransfer_UpsertBatch.sql`
5. `005_stock_transfer_permissions.sql`

After controlled deployment, run `004_stock_transfer_smoke_tests.sql` in a
non-production session. It selects an eligible item/warehouse pair, verifies a
Draft and Post path, and rolls back every control-number, document, inventory,
and history change before returning.

Grant the new `INVENTORY_TRANSFER_VIEW`, `INVENTORY_TRANSFER_EDIT`, and
`INVENTORY_TRANSFER_POST` modules to the intended roles/users through the
existing security administration process; the deployment script registers the
modules but deliberately does not assign business permissions.

The warehouse lookup is intentionally sourced from `dbo.a_whse` using
`whse_code` and `whse_desc`. The inspected RISCDB has one `dbo.c_company` row
and uses its `st_no` column as a six-digit numeric control. Although the legacy
header key is `CHAR(10)`, existing stock-transfer numbers are six digits, so the
procedure preserves that deployed format.

Posting uses `qty_rcv - qty_issued` as on-hand base quantity and treats
`a_whse_item.on_hand_cost` as extended total cost, matching the working Material
Issuance integration. It writes paired `STO` and `STI` rows to `dbo.a_inv_hst`
inside the same transaction. No journal entry is created because an internal
warehouse transfer does not change enterprise inventory value and no existing
warehouse-to-inventory-control-account mapping was found in the module pattern.

The schema change is forward-only: SQL Server rowversion and posted cost
snapshots cannot be safely removed after clients begin relying on them.
