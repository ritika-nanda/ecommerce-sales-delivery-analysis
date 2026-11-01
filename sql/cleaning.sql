-- =====================================================================
-- Project : E-commerce Sales & Delivery Analysis (Olist dataset)
-- File    : 01_cleaning.sql
-- Purpose : Build clean_ tables from the untouched raw_ tables
-- Run     : after load_data.py has created the raw_ tables
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- 1. clean_orders
--    Issue : all dates are stored as text
--    Fix   : convert to DATETIME, add delivery metrics
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean_orders;
CREATE TABLE clean_orders AS
SELECT
  CAST(order_id AS CHAR(32))    AS order_id,
  CAST(customer_id AS CHAR(32)) AS customer_id,
  order_status,
  STR_TO_DATE(order_purchase_timestamp,      '%Y-%m-%d %H:%i:%s') AS purchase_ts,
  STR_TO_DATE(order_approved_at,             '%Y-%m-%d %H:%i:%s') AS approved_ts,
  STR_TO_DATE(order_delivered_carrier_date,  '%Y-%m-%d %H:%i:%s') AS carrier_ts,
  STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s') AS delivered_ts,
  STR_TO_DATE(order_estimated_delivery_date, '%Y-%m-%d %H:%i:%s') AS estimated_ts
FROM raw_orders;

ALTER TABLE clean_orders ADD PRIMARY KEY (order_id);

ALTER TABLE clean_orders
  ADD COLUMN delivery_days INT,
  ADD COLUMN delay_days INT,
  ADD COLUMN is_late TINYINT;

-- Workbench blocks UPDATE without a key filter unless safe updates is off
SET SQL_SAFE_UPDATES = 0;

-- Delivery metrics are only meaningful for delivered orders
UPDATE clean_orders
SET delivery_days = DATEDIFF(delivered_ts, purchase_ts),
    delay_days    = DATEDIFF(delivered_ts, estimated_ts),
    is_late       = (delivered_ts > estimated_ts)
WHERE order_status = 'delivered' AND delivered_ts IS NOT NULL;

-- ---------------------------------------------------------------------
-- 2. clean_reviews
--    Issue : some orders have several reviews (would double-count on join)
--    Fix   : keep the latest review per order
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean_reviews;
CREATE TABLE clean_reviews AS
SELECT order_id, review_id, review_score,
       review_creation_date, review_answer_timestamp
FROM (
  SELECT
    CAST(order_id AS CHAR(32))  AS order_id,
    CAST(review_id AS CHAR(32)) AS review_id,
    review_score,
    STR_TO_DATE(review_creation_date,    '%Y-%m-%d %H:%i:%s') AS review_creation_date,
    STR_TO_DATE(review_answer_timestamp, '%Y-%m-%d %H:%i:%s') AS review_answer_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY order_id
      ORDER BY review_answer_timestamp DESC, review_id
    ) AS rn
  FROM raw_reviews
) t
WHERE rn = 1;

ALTER TABLE clean_reviews ADD PRIMARY KEY (order_id);

-- ---------------------------------------------------------------------
-- 3. clean_geolocation
--    Issue : ~1M rows for ~19K zip prefixes (joins would multiply rows)
--    Fix   : one row per zip prefix, averaged coordinates
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean_geolocation;
CREATE TABLE clean_geolocation AS
SELECT
  geolocation_zip_code_prefix AS zip_prefix,
  AVG(geolocation_lat)        AS lat,
  AVG(geolocation_lng)        AS lng,
  MAX(geolocation_state)      AS state
FROM raw_geolocation
GROUP BY geolocation_zip_code_prefix;

ALTER TABLE clean_geolocation ADD PRIMARY KEY (zip_prefix);

-- ---------------------------------------------------------------------
-- 4. clean_products
--    Issue : Portuguese category names, some missing or untranslated
--    Fix   : English name, else Portuguese name, else 'unknown'
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean_products;
CREATE TABLE clean_products AS
SELECT
  CAST(p.product_id AS CHAR(32)) AS product_id,
  COALESCE(t.product_category_name_english,
           p.product_category_name,
           'unknown') AS category,
  p.product_weight_g, p.product_length_cm,
  p.product_height_cm, p.product_width_cm,
  p.product_photos_qty
FROM raw_products p
LEFT JOIN raw_category_translation t
  ON p.product_category_name = t.product_category_name;

ALTER TABLE clean_products ADD PRIMARY KEY (product_id);

-- ---------------------------------------------------------------------
-- 5. clean_order_items
--    Fix : proper types, item_total = price + freight
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean_order_items;
CREATE TABLE clean_order_items AS
SELECT
  CAST(order_id AS CHAR(32))   AS order_id,
  order_item_id,
  CAST(product_id AS CHAR(32)) AS product_id,
  CAST(seller_id AS CHAR(32))  AS seller_id,
  price, freight_value,
  price + freight_value        AS item_total
FROM raw_order_items;

ALTER TABLE clean_order_items ADD PRIMARY KEY (order_id, order_item_id);

-- ---------------------------------------------------------------------
-- 6. clean_customers
--    Note : customer_id is unique PER ORDER; customer_unique_id identifies
--           the real person (needed for repeat-customer analysis)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean_customers;
CREATE TABLE clean_customers AS
SELECT
  CAST(customer_id AS CHAR(32))        AS customer_id,
  CAST(customer_unique_id AS CHAR(32)) AS customer_unique_id,
  customer_zip_code_prefix             AS zip_prefix,
  LOWER(TRIM(customer_city))           AS city,
  customer_state                       AS state
FROM raw_customers;

ALTER TABLE clean_customers ADD PRIMARY KEY (customer_id);

-- ---------------------------------------------------------------------
-- 7. clean_sellers
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS clean_sellers;
CREATE TABLE clean_sellers AS
SELECT
  CAST(seller_id AS CHAR(32))  AS seller_id,
  seller_zip_code_prefix       AS zip_prefix,
  LOWER(TRIM(seller_city))     AS city,
  seller_state                 AS state
FROM raw_sellers;

ALTER TABLE clean_sellers ADD PRIMARY KEY (seller_id);

-- ---------------------------------------------------------------------
-- 8. Verification
-- ---------------------------------------------------------------------
SELECT 'clean_orders' AS table_name, COUNT(*) AS row_count FROM clean_orders              -- 99,441
UNION ALL SELECT 'clean_reviews',     COUNT(*) FROM clean_reviews                         -- fewer than 99,224
UNION ALL SELECT 'clean_geolocation', COUNT(*) FROM clean_geolocation                     -- ~19,015
UNION ALL SELECT 'clean_products',    COUNT(*) FROM clean_products                        -- 32,951
UNION ALL SELECT 'clean_order_items', COUNT(*) FROM clean_order_items                     -- 112,650
UNION ALL SELECT 'clean_customers',   COUNT(*) FROM clean_customers                       -- 99,441
UNION ALL SELECT 'clean_sellers',     COUNT(*) FROM clean_sellers;                        -- 3,095

SELECT order_id, purchase_ts, delivered_ts, delivery_days, is_late
FROM clean_orders
WHERE order_status = 'delivered'
LIMIT 5;