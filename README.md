# VIVO Super Brand Day dashboard (Jakarta + Tangerang - Banten)

Static web dashboard on GitHub Pages using **import mode** like Power BI: one BigQuery query per area pulls a small
extract (`data/<area>.json`). Every filter, sort and hover then runs in the browser at **zero BigQuery cost**.
Use the area switch at the top, or link straight to an area: `.../sbd_vivo/#jakarta`, `.../sbd_vivo/#tangban`.

| File | What it is |
|---|---|
| `index.html` | The dashboard (no external libraries). Areas are listed in `EVENTS` near the top of the script |
| `sql/sbd_template.sql` | The one import query, shared by all areas |
| `scripts/refresh.py` | Fills the template per area (`EVENTS`: dates, target table, reference periods), dry-runs it, runs it, writes `data/<area>.json` |
| `data/jakarta.json`, `data/tangban.json` | The imported extracts |
| `.github/workflows/refresh.yml` | The "Refresh data" button + Pages deploy |

**Cost per refresh:** about 1.2 GB scanned per area (2 areas, about 2.5 GB, roughly Rp 250), or free within BigQuery's 1 TB/month free tier.

## Areas
| Area | Period | Targets (table) |
|---|---|---|
| Jakarta | 1-30 Nov 2026 | Device, Above Low (`master_data.target_sbd_vivo_jakarta`) |
| Tangerang - Banten | 15 Nov-31 Dec 2026 | Device, Above Low, V80 Lite (`master_data.target_sbd_vivo_tangban`) |

## Definitions
- **Sales:** VIVO `Product_Category = Device`, **`ket_po = 'Non PO'` only**: `region_data.sales_all_retail` for completed days, plus
  today's PAID POS orders from `region_data.sales_daily` (only when its date is after the last date in `sales_all_retail`).
- **Target Device:** all VIVO Device qty. **Target Above Low:** `price_category_GFK` not LOW (MID + HIGH + FLAGSHIP).
  **Target V80 Lite:** `Model_Type_Detail = 'V80 LITE'`.
- **Today's price band:** `sales_daily` has no GFK field, so the same bands are applied to nett unit price incl. tax (<= Rp 3 jt Low, <= 5 jt Mid, <= 9 jt High, above Flagship).
- **Borongan:** one POS / order number with **more than 3 units of the same Model_Type**. The switch can show all sales, exclude Borongan or show Borongan only.
- **Status:** actual to date (incl. today) vs target pro-rata for completed days. On pace >= 100%, Slightly behind 80-99%, Behind < 80%.
- **Est. end of period:** actual incl. today + average of completed days x days left after today.
- **Stock:** `sales_vs_stock` (store + DC). Stock has no selling price, so it is split by `price_segment`.
- **Reference columns:** Jakarta = Oct-26 and Nov-25. Tangerang - Banten = the 47 days before the event, and 15 Nov-31 Dec 2025.

## Daily use
Click **Refresh data** on the page (or Actions -> Refresh data -> Run workflow), wait about 1-2 minutes, reload (Ctrl+F5).

## Adding another area
Add an entry to `EVENTS` in `scripts/refresh.py` (dates, target table) **and** in `index.html` (name, file, which targets), then run the workflow.

## Visibility
GitHub Pages sites are **public** unless the org has GitHub Enterprise Cloud with private Pages.
