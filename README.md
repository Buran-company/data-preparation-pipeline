# data-preparation-pipeline

## Sources

w8_orders_raw (12 rows). one row = one version of row with order data. Key = order_id + line_no. Version is defined by updated_at and source_row_id.
w8_customers_raw (5 rows). one row = one version of a client. Key = customer_id after TRIM and UPPER

## Problems found

Repeats. O100/1 was sent twice without changes (row 2 kept), O101/1 was corrected (discount from 0.1 to 0.2, row 11 kept)
Different status names. For example, "Completed" and "complete"
No quantity for O102, date 2026-02-30 does not exist for O103, quantity 0 for O105, "bad" price for O106
" c02 " and "C02" is the same client. "C99" client was not found in the customer table
O107 price is 2000, another prices are from 10 to 100

## Assumptions

Customer IDs are case- and space-independent
No discount, then it is 0. Wrong discount, then the row will be rejected
The latest version is kept, the choice is made before verification
No client or region, then the region is "Unknown"

## How to run

Paste week8_pipeline.sql into new BigQuery tab and run the whole script
The last 2 results save as w8_sales_analytical.csv and rejected_lines.csv

## Conclusion

Revenue from completed orders is 2220. South is 2080, Unknown 80, North 60
South is leading because of O107, which price is 2000. Without it South and Unknown are equal (both 80)
Without a client, 1 line out of 5 (20%) is 80 of revenue (3.6%)


