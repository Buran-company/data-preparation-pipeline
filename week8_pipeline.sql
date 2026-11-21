-- Week 8 Practice Lab 4: Data Preparation Pipeline

-- 0. Sources
CREATE TEMP TABLE w8_orders_raw AS
SELECT * FROM UNNEST([
 STRUCT(1 AS source_row_id, 'O100' AS order_id, 1 AS line_no,
   'C01' AS customer_id, '2026-10-01' AS order_date_raw,
   '2' AS quantity_raw, '25.00' AS unit_price_raw,
   '0' AS discount_raw, 'Completed' AS status_raw,
   TIMESTAMP '2026-10-02 08:00:00+00' AS updated_at),
 (2,'O100',1,'C01','2026-10-01','2','25.00','0','Completed',TIMESTAMP '2026-10-02 08:00:00+00'),
 (3,'O101',1,' c02 ','2026-10-02','1','100','0.10','complete',TIMESTAMP '2026-10-03 08:00:00+00'),
 (4,'O102',1,'C03','2026-10-03',NULL,'40',NULL,'Completed',TIMESTAMP '2026-10-04 08:00:00+00'),
 (5,'O103',1,'C04','2026-02-30','3','20','0','Completed',TIMESTAMP '2026-10-05 08:00:00+00'),
 (6,'O104',1,'C99','2026-10-05','1','80','0','Completed',TIMESTAMP '2026-10-06 08:00:00+00'),
 (7,'O105',1,'C01','2026-10-05','0','15','0','Completed',TIMESTAMP '2026-10-06 08:00:00+00'),
 (8,'O106',1,'','2026-10-06','2','bad','0','Completed',TIMESTAMP '2026-10-07 08:00:00+00'),
 (9,'O107',1,'C02','2026-10-07','1','2000','0','Completed',TIMESTAMP '2026-10-08 08:00:00+00'),
 (10,'O108',1,'C03','2026-10-07','1','50','0','Cancelled',TIMESTAMP '2026-10-08 08:00:00+00'),
 (11,'O101',1,'C02','2026-10-02','1','100','0.20','Completed',TIMESTAMP '2026-10-09 08:00:00+00'),
 (12,'O100',2,'C01','2026-10-01','1','10','0','Completed',TIMESTAMP '2026-10-02 08:00:00+00')
]);

CREATE TEMP TABLE w8_customers_raw AS
SELECT * FROM UNNEST([
 STRUCT(101 AS source_row_id, 'C01' AS customer_id,
   'North' AS region, TIMESTAMP '2026-10-01 07:00:00+00' AS updated_at),
 (102,' c02 ','South',TIMESTAMP '2026-10-01 07:00:00+00'),
 (103,'C02','South',TIMESTAMP '2026-10-04 07:00:00+00'),
 (104,'C03','West',TIMESTAMP '2026-10-01 07:00:00+00'),
 (105,'C04','East',TIMESTAMP '2026-10-01 07:00:00+00')
]);

-- 1. Profiling
SELECT
  COUNT(*) AS raw_order_rows,
  COUNT(DISTINCT order_id) AS distinct_orders,
  (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, line_no FROM w8_orders_raw)) AS distinct_line_keys
FROM w8_orders_raw;

SELECT order_id, line_no, COUNT(*) AS versions,
  ARRAY_AGG(source_row_id ORDER BY source_row_id) AS source_row_ids
FROM w8_orders_raw
GROUP BY order_id, line_no
HAVING COUNT(*) > 1;

SELECT status_raw, COUNT(*) AS row_count
FROM w8_orders_raw
GROUP BY status_raw;

SELECT
  COUNTIF(quantity_raw IS NULL) AS missing_quantity,
  COUNTIF(discount_raw IS NULL) AS missing_discount,
  COUNTIF(NULLIF(TRIM(customer_id), '') IS NULL) AS blank_customer_id,
  COUNTIF(order_date_raw IS NOT NULL AND SAFE_CAST(TRIM(order_date_raw) AS DATE) IS NULL) AS bad_dates,
  COUNTIF(quantity_raw IS NOT NULL AND SAFE_CAST(TRIM(quantity_raw) AS INT64) IS NULL) AS bad_quantities,
  COUNTIF(unit_price_raw IS NOT NULL AND SAFE_CAST(TRIM(unit_price_raw) AS NUMERIC) IS NULL) AS bad_prices,
  COUNTIF(discount_raw IS NOT NULL AND SAFE_CAST(TRIM(discount_raw) AS NUMERIC) IS NULL) AS bad_discounts
FROM w8_orders_raw;

SELECT 'orders' AS source,
  COUNT(DISTINCT customer_id) AS raw_ids,
  COUNT(DISTINCT NULLIF(UPPER(TRIM(customer_id)), '')) AS normalized_ids
FROM w8_orders_raw
UNION ALL
SELECT 'customers', COUNT(DISTINCT customer_id),
  COUNT(DISTINCT NULLIF(UPPER(TRIM(customer_id)), ''))
FROM w8_customers_raw;

SELECT * FROM w8_customers_raw
WHERE UPPER(TRIM(customer_id)) IN (
  SELECT UPPER(TRIM(customer_id)) FROM w8_customers_raw
  GROUP BY 1 HAVING COUNT(*) > 1);

-- 2. Standardize and parse
CREATE TEMP TABLE w8_orders_typed AS
SELECT r.*,
  NULLIF(UPPER(TRIM(r.customer_id)), '') AS customer_key,
  SAFE_CAST(TRIM(r.order_date_raw) AS DATE) AS order_date,
  SAFE_CAST(TRIM(r.quantity_raw) AS INT64) AS quantity,
  SAFE_CAST(TRIM(r.unit_price_raw) AS NUMERIC) AS unit_price,
  IF(NULLIF(TRIM(r.discount_raw), '') IS NULL, NUMERIC '0',
     SAFE_CAST(TRIM(r.discount_raw) AS NUMERIC)) AS discount,
  CASE LOWER(TRIM(r.status_raw))
    WHEN 'complete' THEN 'Completed'
    WHEN 'completed' THEN 'Completed'
    WHEN 'cancelled' THEN 'Cancelled'
    ELSE 'Unrecognized'
  END AS status
FROM w8_orders_raw AS r;

-- 3. Keep the latest version of each order line and customer
CREATE TEMP TABLE w8_orders_ranked AS
SELECT *,
  ROW_NUMBER() OVER (PARTITION BY order_id, line_no
                     ORDER BY updated_at DESC, source_row_id DESC) AS version_rank,
  COUNT(*) OVER (PARTITION BY order_id, line_no) AS versions
FROM w8_orders_typed;

SELECT order_id, line_no, source_row_id, discount_raw, updated_at,
  version_rank = 1 AS retained
FROM w8_orders_ranked
WHERE versions > 1
ORDER BY order_id, version_rank;

CREATE TEMP TABLE w8_orders_latest AS
SELECT * EXCEPT(version_rank, versions) FROM w8_orders_ranked WHERE version_rank = 1;

CREATE TEMP TABLE w8_customers_clean AS
SELECT
  NULLIF(UPPER(TRIM(customer_id)), '') AS customer_key,
  COALESCE(NULLIF(TRIM(region), ''), 'Unknown') AS region,
  source_row_id AS customer_source_row_id
FROM w8_customers_raw
WHERE NULLIF(UPPER(TRIM(customer_id)), '') IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY NULLIF(UPPER(TRIM(customer_id)), '')
                           ORDER BY updated_at DESC, source_row_id DESC) = 1;

-- 4. Validate and calculate revenue
CREATE TEMP TABLE w8_orders_checked AS
SELECT *,
  ARRAY_TO_STRING([
    IF(order_date IS NULL, 'bad date', NULL),
    IF(quantity IS NULL, 'missing or bad quantity', NULL),
    IF(quantity <= 0, 'quantity not positive', NULL),
    IF(unit_price IS NULL, 'missing or bad price', NULL),
    IF(unit_price < 0, 'negative price', NULL),
    IF(discount IS NULL, 'bad discount', NULL),
    IF(discount < 0 OR discount > 1, 'discount outside 0-1', NULL),
    IF(status = 'Unrecognized', 'unrecognized status', NULL)
  ], '; ') AS rejection_reasons
FROM w8_orders_latest;

CREATE TEMP TABLE w8_rejected_lines AS
SELECT order_id, line_no, source_row_id, customer_id, order_date_raw,
  quantity_raw, unit_price_raw, discount_raw, status_raw, rejection_reasons
FROM w8_orders_checked
WHERE rejection_reasons != '';

CREATE TEMP TABLE w8_completed_lines AS
SELECT * EXCEPT(rejection_reasons),
  quantity * unit_price * (1 - discount) AS revenue
FROM w8_orders_checked
WHERE rejection_reasons = '' AND status = 'Completed';

SELECT status, COUNT(*) AS valid_lines
FROM w8_orders_checked
WHERE rejection_reasons = ''
GROUP BY status;

SELECT order_id, line_no, quantity, unit_price, revenue
FROM w8_completed_lines
ORDER BY revenue DESC;

-- 5. Integrate customers
CREATE TEMP TABLE w8_sales_analytical AS
SELECT
  o.order_id, o.line_no, o.customer_key, o.order_date,
  o.quantity, o.unit_price, o.discount, o.status, o.revenue,
  COALESCE(c.region, 'Unknown') AS region,
  c.customer_key IS NOT NULL AS customer_matched,
  o.source_row_id AS order_source_row_id,
  c.customer_source_row_id
FROM w8_completed_lines AS o
LEFT JOIN w8_customers_clean AS c
  ON o.customer_key = c.customer_key;

-- 6. Reconcile
ASSERT (SELECT COUNT(*) = COUNT(DISTINCT FORMAT('%s|%d', order_id, line_no))
        FROM w8_sales_analytical) AS 'Duplicate order lines';

ASSERT (SELECT COUNT(*) FROM w8_completed_lines) = (SELECT COUNT(*) FROM w8_sales_analytical)
  AND (SELECT SUM(revenue) FROM w8_completed_lines) = (SELECT SUM(revenue) FROM w8_sales_analytical)
  AS 'Join changed lines or revenue';

SELECT
  (SELECT COUNT(*) FROM w8_orders_raw) AS raw_order_rows,
  (SELECT COUNT(*) FROM w8_orders_latest) AS authoritative_lines,
  (SELECT COUNT(*) FROM w8_rejected_lines) AS rejected_lines,
  (SELECT COUNTIF(rejection_reasons = '') FROM w8_orders_checked) AS valid_lines,
  (SELECT COUNT(*) FROM w8_sales_analytical) AS completed_lines,
  (SELECT COUNTIF(customer_matched) FROM w8_sales_analytical) AS matched_lines,
  (SELECT COUNTIF(NOT customer_matched) FROM w8_sales_analytical) AS unmatched_lines,
  (SELECT SUM(revenue) FROM w8_sales_analytical) AS completed_revenue,
  (SELECT SUM(IF(customer_matched, 0, revenue)) FROM w8_sales_analytical) AS unmatched_revenue,
  (SELECT COUNT(*) FROM w8_customers_raw) AS raw_customer_rows,
  (SELECT COUNT(*) FROM w8_customers_clean) AS clean_customers;

SELECT region, COUNT(*) AS line_count, SUM(revenue) AS revenue
FROM w8_sales_analytical
GROUP BY region
UNION ALL
SELECT 'TOTAL', COUNT(*), SUM(revenue) FROM w8_sales_analytical
ORDER BY revenue DESC;

-- 7. Export these two results as CSV
SELECT * FROM w8_sales_analytical ORDER BY order_id, line_no;
SELECT * FROM w8_rejected_lines ORDER BY order_id, line_no;