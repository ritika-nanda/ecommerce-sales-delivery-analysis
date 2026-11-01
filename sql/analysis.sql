-- =====================================================================
-- Project : E-commerce Sales & Delivery Analysis (Olist dataset)
-- File    : 02_analysis.sql
-- Purpose : Business questions answered with SQL
-- Run     : after 01_cleaning.sql
--
-- Assumptions
--   * Revenue = SUM(price) on DELIVERED orders only (freight excluded)
--   * Trend analysis uses Jan 2017 - Aug 2018 (2016 and late 2018 have
--     very few orders and would distort growth rates)
-- =====================================================================

USE olist;

-- ---------------------------------------------------------------------
-- Query 1: Business KPIs
-- ---------------------------------------------------------------------
SELECT
  COUNT(DISTINCT o.order_id)                          AS orders,
  COUNT(DISTINCT c.customer_unique_id)                AS unique_customers,
  ROUND(SUM(i.price), 0)                              AS revenue,
  ROUND(SUM(i.price) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM clean_orders o
JOIN clean_order_items i ON o.order_id = i.order_id
JOIN clean_customers c   ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered';

-- ---------------------------------------------------------------------
-- Query 2: Monthly revenue and month-over-month growth (CTE + LAG)
-- ---------------------------------------------------------------------
WITH monthly AS (
  SELECT DATE_FORMAT(o.purchase_ts, '%Y-%m') AS month,
         COUNT(DISTINCT o.order_id)          AS orders,
         ROUND(SUM(i.price), 2)              AS revenue
  FROM clean_orders o
  JOIN clean_order_items i ON o.order_id = i.order_id
  WHERE o.order_status = 'delivered'
    AND o.purchase_ts >= '2017-01-01' AND o.purchase_ts < '2018-09-01'
  GROUP BY DATE_FORMAT(o.purchase_ts, '%Y-%m')
)
SELECT month, orders, revenue,
       LAG(revenue) OVER (ORDER BY month) AS prev_month,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY month))
                 / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly;

-- ---------------------------------------------------------------------
-- Query 3: Category Pareto analysis (window functions, running total)
-- Find the row where cumulative_pct first passes 80
-- ---------------------------------------------------------------------
WITH cat AS (
  SELECT p.category, SUM(i.price) AS revenue
  FROM clean_order_items i
  JOIN clean_orders o   ON i.order_id = o.order_id
  JOIN clean_products p ON i.product_id = p.product_id
  WHERE o.order_status = 'delivered'
  GROUP BY p.category
)
SELECT category,
       ROUND(revenue, 0) AS revenue,
       ROUND(100 * revenue / SUM(revenue) OVER (), 1) AS share_pct,
       ROUND(100 * SUM(revenue) OVER (ORDER BY revenue DESC)
                 / SUM(revenue) OVER (), 1) AS cumulative_pct
FROM cat
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------
-- Query 4: Late vs on-time delivery and review score (headline insight)
-- ---------------------------------------------------------------------
SELECT CASE WHEN o.is_late = 1 THEN 'Late' ELSE 'On time' END AS delivery,
       COUNT(*)                                  AS orders,
       ROUND(AVG(r.review_score), 2)             AS avg_review_score,
       ROUND(100 * AVG(r.review_score <= 2), 1)  AS pct_low_reviews
FROM clean_orders o
JOIN clean_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered' AND o.is_late IS NOT NULL
GROUP BY CASE WHEN o.is_late = 1 THEN 'Late' ELSE 'On time' END;

-- ---------------------------------------------------------------------
-- Query 5: Late delivery rate by state (HAVING filters small states)
-- ---------------------------------------------------------------------
SELECT c.state,
       COUNT(*)                        AS orders,
       ROUND(100 * AVG(o.is_late), 1)  AS late_pct,
       ROUND(AVG(o.delivery_days), 1)  AS avg_delivery_days
FROM clean_orders o
JOIN clean_customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered' AND o.is_late IS NOT NULL
GROUP BY c.state
HAVING COUNT(*) >= 200
ORDER BY late_pct DESC;

-- ---------------------------------------------------------------------
-- Query 6: Top 3 sellers in each state (RANK with PARTITION BY)
-- ---------------------------------------------------------------------
WITH seller_rev AS (
  SELECT s.state, s.seller_id, ROUND(SUM(i.price), 0) AS revenue
  FROM clean_order_items i
  JOIN clean_orders o  ON i.order_id = o.order_id
  JOIN clean_sellers s ON i.seller_id = s.seller_id
  WHERE o.order_status = 'delivered'
  GROUP BY s.state, s.seller_id
),
ranked AS (
  SELECT *, RANK() OVER (PARTITION BY state ORDER BY revenue DESC) AS rnk
  FROM seller_rev
)
SELECT state, rnk, seller_id, revenue
FROM ranked
WHERE rnk <= 3
ORDER BY state, rnk;

-- ---------------------------------------------------------------------
-- Query 7: One-time vs repeat customers (uses customer_unique_id,
-- because customer_id changes with every order)
-- ---------------------------------------------------------------------
WITH cust AS (
  SELECT c.customer_unique_id,
         COUNT(DISTINCT o.order_id) AS orders,
         SUM(i.price)               AS revenue
  FROM clean_orders o
  JOIN clean_customers c   ON o.customer_id = c.customer_id
  JOIN clean_order_items i ON o.order_id = i.order_id
  WHERE o.order_status = 'delivered'
  GROUP BY c.customer_unique_id
)
SELECT CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END AS segment,
       COUNT(*) AS customers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_customers,
       ROUND(SUM(revenue), 0) AS revenue
FROM cust
GROUP BY CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END;

-- ---------------------------------------------------------------------
-- Query 8: Payment methods
-- ---------------------------------------------------------------------
SELECT payment_type,
       COUNT(DISTINCT order_id)            AS orders,
       ROUND(SUM(payment_value), 0)        AS total_value,
       ROUND(AVG(payment_installments), 1) AS avg_installments
FROM raw_payments
GROUP BY payment_type
ORDER BY total_value DESC;

-- ---------------------------------------------------------------------
-- Query 9: RFM-style segmentation with NTILE
-- Frequency is skipped on purpose: almost every customer bought once,
-- so it would add no information. r_score = 4 and m_score = 4 are
-- recent big spenders.
-- ---------------------------------------------------------------------
WITH base AS (
  SELECT c.customer_unique_id,
         MAX(o.purchase_ts) AS last_order,
         SUM(i.price)       AS monetary
  FROM clean_orders o
  JOIN clean_customers c   ON o.customer_id = c.customer_id
  JOIN clean_order_items i ON o.order_id = i.order_id
  WHERE o.order_status = 'delivered'
  GROUP BY c.customer_unique_id
),
scored AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY last_order) AS r_score,
         NTILE(4) OVER (ORDER BY monetary)   AS m_score
  FROM base
)
SELECT r_score, m_score,
       COUNT(*) AS customers,
       ROUND(SUM(monetary), 0) AS revenue
FROM scored
GROUP BY r_score, m_score
ORDER BY r_score DESC, m_score DESC;