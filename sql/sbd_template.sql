-- VIVO Super Brand Day - import query TEMPLATE (Power BI "import mode" style), shared by all areas.
-- scripts/refresh.py fills the placeholders (marked with double @) per area (see EVENTS there) and writes data/<area>.json.
-- Returns ONE row with ONE column `j` (compact JSON). Rows inside are "|"-delimited strings.
-- Sales = VIVO Device, ket_po = 'Non PO' only. Above Low = price_category_GFK not LOW.
-- V80 Lite = Model_Type_Detail 'V80 LITE'. Borongan = one POS / order number with > 3 units of the same model.
WITH p AS (SELECT DATE '@@START@@' AS s, DATE '@@END@@' AS e,
                  DATE '@@PREV_START@@' AS ps, DATE '@@PREV_END@@' AS pe),

tgt AS (
  SELECT Site AS site, `Target Device` AS td, `Target Above Low` AS tal, @@V80_TARGET@@ AS tv80
  FROM `e-smart-433113.@@TARGET_TABLE@@`
),

-- stock + store attributes
svs AS (
  SELECT order_date AS d, site_code AS site, store_name, tsh, lob, line,
         IF(Model_Type_Detail = 'V80 LITE', 'V80 LITE', IFNULL(NULLIF(Model_Type, ''), 'OTHER')) AS model,
         IFNULL(NULLIF(LEFT(price_segment, 2), ''), '00') AS seg,
         IF(Model_Type_Detail = 'V80 LITE', 1, 0) AS x,
         SUM_quantity AS q
  FROM `e-smart-433113.region_data.sales_vs_stock`
  WHERE brandname = 'VIVO' AND Product_Category = 'Device'
),
svs_t AS (SELECT * FROM svs WHERE site IN (SELECT site FROM tgt)),

-- SALES: sales_all_retail, Non PO only
sar0 AS (
  SELECT order_date AS d, site_code AS site, pos_number AS pos, IFNULL(NULLIF(Model_Type, ''), 'OTHER') AS mt,
         IF(Model_Type_Detail = 'V80 LITE', 'V80 LITE', IFNULL(NULLIF(Model_Type, ''), 'OTHER')) AS model,
         IFNULL(NULLIF(LEFT(price_category_GFK, 2), ''), '00') AS seg,
         IF(Model_Type_Detail = 'V80 LITE', 1, 0) AS x,
         quantity AS q, total_nett_amount_with_tax AS a
  FROM `e-smart-433113.region_data.sales_all_retail`
  WHERE brandname = 'VIVO' AND Product_Category = 'Device'
    AND ket_po = 'Non PO'
    AND site_code IN (SELECT site FROM tgt)
),
sar AS (SELECT *, IF(SUM(q) OVER (PARTITION BY site, pos, mt) > 3, 1, 0) AS b FROM sar0),

asof AS (SELECT MAX(d) AS sales_asof FROM sar),
stk_date AS (SELECT MAX(d) AS stock_date FROM svs WHERE line = 'stock'),

stores AS (
  SELECT site, ARRAY_AGG(STRUCT(store_name, tsh, lob) ORDER BY d DESC LIMIT 1)[OFFSET(0)] AS s
  FROM svs_t GROUP BY site
),

cur AS (SELECT d, site, seg, model, x, b, SUM(q) q, SUM(a) a FROM sar, p WHERE d BETWEEN p.s AND p.e GROUP BY ALL),
prev_m AS (SELECT site, seg, x, b, SUM(q) q, SUM(a) a FROM sar, p WHERE d BETWEEN p.ps AND p.pe GROUP BY ALL),
prev_y AS (SELECT site, seg, x, b, SUM(q) q, SUM(a) a FROM sar, p
           WHERE d BETWEEN DATE_SUB(p.s, INTERVAL 1 YEAR) AND DATE_SUB(p.e, INTERVAL 1 YEAR) GROUP BY ALL),
stk AS (SELECT line, site, seg, model, x, SUM(q) q FROM svs_t, stk_date
        WHERE line IN ('stock', 'stock_dc') AND d = stk_date.stock_date GROUP BY ALL),

-- TODAY: sales_daily (PAID, Non PO); GFK band from nett unit price incl. tax
today0 AS (
  SELECT PARSE_DATE('%Y/%m/%d', sd.`Date`) AS d, sd.`Site Code` AS site, sd.`Order Number` AS pos, IFNULL(sd.model_type, 'OTHER') AS mt,
         IF(sd.model_type_detail = 'V80 LITE', 'V80 LITE', IFNULL(sd.model_type, 'OTHER')) AS model,
         CASE WHEN SAFE_DIVIDE(sd.`Total Amount`, sd.Quantity) <= 3000000 THEN '01'
              WHEN SAFE_DIVIDE(sd.`Total Amount`, sd.Quantity) <= 5000000 THEN '02'
              WHEN SAFE_DIVIDE(sd.`Total Amount`, sd.Quantity) <= 9000000 THEN '03'
              ELSE '04' END AS seg,
         IF(sd.model_type_detail = 'V80 LITE', 1, 0) AS x,
         SUM(sd.Quantity) q, SUM(sd.`Total Amount`) a
  FROM `e-smart-433113.region_data.sales_daily` sd
  WHERE sd.brandname = 'VIVO' AND sd.product_category = 'Device'
    AND sd.`Order Status` = 'PAID' AND sd.Ket_PO = 'Non PO'
    AND sd.`Site Code` IN (SELECT site FROM tgt)
  GROUP BY ALL
),
today AS (SELECT *, IF(SUM(q) OVER (PARTITION BY site, pos, mt) > 3, 1, 0) AS b FROM today0),
today_f AS (SELECT t.* FROM today t, asof, p WHERE t.d > asof.sales_asof AND t.d BETWEEN p.s AND p.e),

bor AS (
  SELECT d, site, pos, model, MAX(seg) seg, MAX(x) x, SUM(q) q, SUM(a) a FROM (
    SELECT d, site, pos, model, seg, x, q, a FROM sar, p WHERE b = 1 AND d BETWEEN p.s AND p.e
    UNION ALL
    SELECT d, site, pos, model, seg, x, q, a FROM today_f WHERE b = 1)
  GROUP BY d, site, pos, model
),

-- how far sales_daily is loaded (ALL brands/stores): if it holds today, stores with no VIVO rows are inactive today
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
  '@@EVENT@@' AS event,
  (SELECT CAST(s AS STRING) FROM p) AS period_start,
  (SELECT CAST(e AS STRING) FROM p) AS period_end,
  '@@PREV_LABEL@@' AS prev_label,
  '@@LY_LABEL@@' AS ly_label,
  (SELECT CAST(sales_asof AS STRING) FROM asof) AS sales_asof,
  (SELECT CAST(stock_date AS STRING) FROM stk_date) AS stock_date,
  (SELECT CAST(today_date AS STRING) FROM today_meta) AS today_date,
  (SELECT today_last_time FROM today_meta) AS today_last_time,
  CAST(CURRENT_DATETIME('Asia/Jakarta') AS STRING) AS refreshed_at,
  -- site|store|tsh|lob|target_device|target_above_low|target_v80lite
  ARRAY(SELECT CONCAT(t.site, '|', IFNULL(s.s.store_name, ''), '|', IFNULL(s.s.tsh, ''), '|', IFNULL(s.s.lob, ''), '|',
                      CAST(IFNULL(t.td, 0) AS STRING), '|', CAST(IFNULL(t.tal, 0) AS STRING), '|', CAST(IFNULL(t.tv80, 0) AS STRING))
        FROM tgt t LEFT JOIN stores s USING (site) ORDER BY t.site) AS targets,
  -- yyyymmdd|site|seg|model|qty|amt_mio|borongan|v80lite
  ARRAY(SELECT CONCAT(FORMAT_DATE('%Y%m%d', d), '|', site, '|', seg, '|', model, '|', CAST(q AS STRING), '|',
                      CAST(ROUND(a / 1e6, 1) AS STRING), '|', CAST(b AS STRING), '|', CAST(x AS STRING))
        FROM cur ORDER BY d, site) AS sales,
  ARRAY(SELECT CONCAT(FORMAT_DATE('%Y%m%d', d), '|', site, '|', seg, '|', model, '|', CAST(SUM(q) AS STRING), '|',
                      CAST(ROUND(SUM(a) / 1e6, 1) AS STRING), '|', CAST(b AS STRING), '|', CAST(x AS STRING))
        FROM today_f GROUP BY d, site, seg, model, b, x ORDER BY site) AS today,
  -- site|seg|qty|amt_mio|borongan|v80lite
  ARRAY(SELECT CONCAT(site, '|', seg, '|', CAST(q AS STRING), '|', CAST(ROUND(a / 1e6, 1) AS STRING), '|', CAST(b AS STRING), '|', CAST(x AS STRING))
        FROM prev_m ORDER BY site) AS prev_month,
  ARRAY(SELECT CONCAT(site, '|', seg, '|', CAST(q AS STRING), '|', CAST(ROUND(a / 1e6, 1) AS STRING), '|', CAST(b AS STRING), '|', CAST(x AS STRING))
        FROM prev_y ORDER BY site) AS prev_year,
  -- Borongan orders: yyyymmdd|site|pos_number|model|seg|qty|amt_mio|v80lite
  ARRAY(SELECT CONCAT(FORMAT_DATE('%Y%m%d', d), '|', site, '|', pos, '|', model, '|', seg, '|', CAST(q AS STRING), '|',
                      CAST(ROUND(a / 1e6, 1) AS STRING), '|', CAST(x AS STRING))
        FROM bor ORDER BY d DESC, q DESC) AS borongan,
  -- line|site|seg|model|qty|v80lite
  ARRAY(SELECT CONCAT(line, '|', site, '|', seg, '|', model, '|', CAST(q AS STRING), '|', CAST(x AS STRING))
        FROM stk WHERE q <> 0 ORDER BY line, site) AS stock
)) AS j
