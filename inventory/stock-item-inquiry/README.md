# Stock Item Inquiry database deployment

Deploy to the inventory database in this order:

1. `001_stock_item_inquiry_queries.sql`
2. `002_stock_item_inquiry_index.sql`

All four procedures are read-only. The index script adds one narrow composite
index for Stock Card filtering and ordering. Existing `a_whse_item` and
`a_rr_lot` indexes already support their inquiry predicates, so no duplicates
are created.

The live schema has no persisted `stock_on_hand` column. Warehouse on-hand is
therefore calculated as `qty_rcv - qty_issued`, matching the current material
issuance and stock-transfer posting procedures. `date_changed` is returned only
as audit metadata and is never used as the Stock Card reporting-period filter.
