# VIVO Super Brand Day · Jakarta dashboard

A static web dashboard (GitHub Pages) using **import mode** like Power BI: one BigQuery query pulls a small,
pre-aggregated extract (`data/sbd.json`, ~20 KB). Every filter, sort and hover then runs in the browser
at **zero BigQuery cost**. Data only changes when you press **Run workflow**.

| File | What it is |
|---|---|
| `index.html` | The dashboard (no external libraries) |
| `data/sbd.json` | The imported extract |
| `sql/import.sql` | The single import query. **Edit the period here** (`DATE '2026-11-01'` / `DATE '2026-11-30'`) |
| `scripts/refresh.py` | Dry-runs the query (cost check), runs it with a 2 GB billing cap, writes `data/sbd.json` |
| `.github/workflows/refresh.yml` | The "Refresh data" button + Pages deploy |

**Cost per refresh:** about 0.84 GB scanned, roughly Rp 85 on demand, or free within BigQuery's 1 TB/month free tier.

---

## One-time setup (about 15 minutes)

### 1. Google Cloud: a read-only service account
1. Open https://console.cloud.google.com/iam-admin/serviceaccounts?project=e-smart-433113, then **Create service account**.
   Name: `sbd-dashboard-reader`.
2. Grant two roles: **BigQuery Data Viewer** and **BigQuery Job User**. Then **Done**.
3. Open the account, go to **Keys**, then **Add key → Create new key → JSON**. A `.json` file downloads.
   Treat it like a password. Never commit it to the repo.

> If your org blocks key creation (policy `iam.disableServiceAccountKeyCreation`), ask IT for an exception
> or for Workload Identity Federation instead.

### 2. GitHub repo
1. Create a repo, e.g. `sbd-vivo-dashboard`, and upload all files in this folder (keep the `.github` folder).
2. **Settings → Secrets and variables → Actions → New repository secret**.
   Name: `GCP_SA_KEY`. Value: paste the whole content of the JSON key file.
3. **Settings → Pages → Build and deployment → Source: GitHub Actions**.
4. In `index.html`, set `const GITHUB_REPO = "your-username/sbd-vivo-dashboard";` so the
   **Refresh data** button on the page opens the workflow.

### 3. First run
**Actions → Refresh data → Run workflow**. After about 1 minute the site is live at
`https://<your-username>.github.io/sbd-vivo-dashboard/`.

---

## Daily use
- **Refresh:** click **Refresh data** on the page (or go to Actions → Refresh data), then **Run workflow**. Wait about 1 minute and reload.
- **New period or new targets:** update `master_data.target_sbd_vivo_jakarta` in BigQuery, edit the two dates
  in `sql/import.sql`, then run the workflow.
- **Automatic refresh later:** uncomment the `schedule` block in `.github/workflows/refresh.yml`.

## ⚠ Visibility
GitHub Pages sites are **public** unless the org has GitHub Enterprise Cloud with private Pages.
Anyone with the URL can see the store names and figures. Check with IT/data governance before sharing.

## Definitions
- **Target Device:** all VIVO `Product_Category = Device` qty sold per store, 1–30 Nov (`region_data.sales_all_retail`).
- **Target Above Low:** the same, where `price_category_GFK` is not LOW (MID + HIGH + FLAGSHIP).
- **Today:** intraday PAID POS orders from `sales_daily`. That table has no GFK field, so the same GFK bands are applied
  to the nett unit price incl. tax (≤ Rp 3 jt Low, ≤ 5 jt Mid, ≤ 9 jt High, above that Flagship). Today's rows are only
  added when their date is after the last date in `sales_all_retail`, so nothing is counted twice.
- **Stock:** `sales_vs_stock` (store + DC). Stock has no selling price, so for the Above Low view it is split by `price_segment`.
- **Pace / status:** completed-day sales vs target × (completed days ÷ 30). On pace ≥ 100%, Slightly behind 80–99%, Behind < 80%.
- **Need / day:** remaining gap ÷ remaining days (including today). Calendar days, since stores trade daily.
- **Stock vs gap:** latest store stock for the segment compared with the store's remaining gap.
