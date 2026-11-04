-- VIVO Super Brand Day Jakarta - single import query (Power BI "import mode" style)
-- Returns ONE row with ONE column `j` (compact JSON). Rows inside are "|"-delimited strings.
-- Edit the period here:
WITH p AS (SELECT DATE '2026-11-01' AS s, DATE '2026-11-30' AS e),

tgt AS (
  SELECT Site AS site, `Target Device` AS td, `Target Above Low` AS tal
  FROM `e-smart-433113.master_data.target_sbd_vivo_jakarta`
),

svs AS (
  SELECT order_date AS d, site_code AS site, store_name, tsh, lob, line,
         IFNULL(NULLIF(Model_Type, ''), 'OTHER') AS model,
         IFNULL(NULLIF(LEFT(price_segment, 2), ''), '00') AS seg,
         SUM_quantity AS q, SUM_total_nett_amount_with_tax AS a
  FROM `e-smart-433113.region_data.sales_vs_stock`
  WHERE brandname = 'VIVO' AND Product_Category = 'Device'
),
svs_t AS (SELECT * FROM svs WHERE site IN (SELECT site FROM tgt)),

-- SALES source: sales_all_retail, segment = price_category_GFK (Above Low = MID/HIGH/FLAGSHIP)
sar AS (
  SELECT order_date AS d, site_code AS site,
         IFNULL(NULLIF(Model_Type, ''), 'OTHER') AS model,
         IFNULL(NULLIF(LEFT(price_category_GFK, 2), ''), '00') AS seg,
         quantity AS q, total_nett_amount_with_tax AS a
  FROM `e-smart-433113.region_data.sales_all_retail`
  WHERE brandname = 'VIVO' AND Product_Category = 'Device'
    AND site_code IN (SELECT site FROM tgt)
),

asof AS (SELECT MAX(d) AS sales_asof FROM sar),
stk_date AS (SELECT MAX(d) AS stock_date FROM svs WHERE line = 'stock'),

stores AS (
  SELECT site, ARRAY_AGG(STRUCT(store_name, tsh, lob) ORDER BY d DESC LIMIT 1)[OFFSET(0)] AS s
  FROM svs_t GROUP BY site
),

-- current period, daily x site x segment x model
cur AS (
  SELECT d, site, seg, model, SUM(q) q, SUM(a) a
  FROM sar, p WHERE d BETWEEN p.s AND p.e
  GROUP BY ALL
),
-- baselines: previous month and same month last year (site x segment)
prev_m AS (
  SELECT site, seg, SUM(q) q, SUM(a) a
  FROM sar, p WHERE d BETWEEN DATE_SUB(p.s, INTERVAL 1 MONTH) AND DATE_SUB(p.s, INTERVAL 1 DAY)
  GROUP BY ALL
),
prev_y AS (
  SELECT site, seg, SUM(q) q, SUM(a) a
  FROM sar, p WHERE d BETWEEN DATE_SUB(p.s, INTERVAL 1 YEAR) AND DATE_SUB(p.e, INTERVAL 1 YEAR)
  GROUP BY ALL
),
-- latest stock snapshot (store + DC). Stock has no selling price, so its segment is sales_vs_stock.price_segment.
stk AS (
  SELECT line, site, seg, model, SUM(q) q
  FROM svs_t, stk_date WHERE line IN ('stock', 'stock_dc') AND d = stk_date.stock_date
  GROUP BY ALL
),

-- today intraday (POS): GFK band from nett unit price incl. tax (same cut-offs as price_category_GFK)
today AS (
  SELECT PARSE_DATE('%Y/%m/%d', sd.`Date`) AS d, sd.`Site Code` AS site,
         IFNULL(sd.model_type, 'OTHER') AS model,
         CASE WHEN SAFE_DIVIDE(sd.`Total Amount`, sd.Quantity) <= 3000000 THEN '01'
              WHEN SAFE_DIVIDE(sd.`Total Amount`, sd.Quantity) <= 5000000 THEN '02'
              WHEN SAFE_DIVIDE(sd.`Total Amount`, sd.Quantity) <= 9000000 THEN '03'
              ELSE '04' END AS seg,
         SUM(sd.Quantity) q, SUM(sd.`Total Amount`) a, MAX(sd.`Time`) last_t
  FROM `e-smart-433113.region_data.sales_daily` sd
  WHERE sd.brandname = 'VIVO' AND sd.product_category = 'Device'
    AND sd.`Order Status` = 'PAID'
    AND sd.`Site Code` IN (SELECT site FROM tgt)
  GROUP BY ALL
),
today_f AS (SELECT t.* FROM today t, asof, p WHERE t.d > asof.sales_asof AND t.d BETWEEN p.s AND p.e),
-- how far sales_daily is loaded (ALL brands/stores): if it already holds today, stores with no VIVO rows are inactive today
sd_meta AS (
  SELECT d AS sd_date, last_t AS sd_last_time FROM (
    SELECT PARSE_DATE('%Y/%m/%d', `Date`) AS d, MAX(`Time`) AS last_t
    FROM `e-smart-433113.region_data.sales_daily` GROUP BY 1)
  ORDER BY d DESC LIMIT 1
),
today_meta AS (
  SELECT IF(m.sd_date > a.sales_asof AND m.sd_date BETWEEN p.s AND p.e, m.sd_date, NULL) AS today_date,
         IF(m.sd_date > a.sales_asof AND m.sd_date BETWEEN p.s AND p.e, m.sd_last_time, NULL) AS today_last_time
  FROM sd_meta m, asof a, p
)

SELECT TO_JSON_STRING(STRUCT(
  (SELECT CAST(s AS STRING) FROM p) AS period_start,
  (SELECT CAST(e AS STRING) FROM p) AS period_end,
  (SELECT CAST(sales_asof AS STRING) FROM asof) AS sales_asof,
  (SELECT CAST(stock_date AS STRING) FROM stk_date) AS stock_date,
  (SELECT CAST(today_date AS STRING) FROM today_meta) AS today_date,
  (SELECT today_last_time FROM today_meta) AS today_last_time,
  CAST(CURRENT_DATETIME('Asia/Jakarta') AS STRING) AS refreshed_at,
  -- site|store|tsh|lob|target_device|target_above_low
  ARRAY(SELECT CONCAT(t.site, '|', IFNULL(s.s.store_name, ''), '|', IFNULL(s.s.tsh, ''), '|', IFNULL(s.s.lob, ''), '|', CAST(t.td AS STRING), '|', CAST(t.tal AS STRING))
        FROM tgt t LEFT JOIN stores s USING (site) ORDER BY t.site) AS targets,
  -- yyyymmdd|site|seg|model|qty|amt_mio
  ARRAY(SELECT CONCAT(FORMAT_DATE('%Y%m%d', d), '|', site, '|', seg, '|', model, '|', CAST(q AS STRING), '|', CAST(ROUND(a / 1e6, 1) AS STRING))
        FROM cur ORDER BY d, site) AS sales,
  ARRAY(SELECT CONCAT(FORMAT_DATE('%Y%m%d', d), '|', site, '|', seg, '|', model, '|', CAST(q AS STRING), '|', CAST(ROUND(a / 1e6, 1) AS STRING))
        FROM today_f ORDER BY site) AS today,
  -- site|seg|qty|amt_mio
  ARRAY(SELECT CONCAT(site, '|', seg, '|', CAST(q AS STRING), '|', CAST(ROUND(a / 1e6, 1) AS STRING)) FROM prev_m ORDER BY site) AS prev_month,
  ARRAY(SELECT CONCAT(site, '|', seg, '|', CAST(q AS STRING), '|', CAST(ROUND(a / 1e6, 1) AS STRING)) FROM prev_y ORDER BY site) AS prev_year,
  -- line|site|seg|model|qty
  ARRAY(SELECT CONCAT(line, '|', site, '|', seg, '|', model, '|', CAST(q AS STRING)) FROM stk WHERE q <> 0 ORDER BY line, site) AS stock
)) AS j
