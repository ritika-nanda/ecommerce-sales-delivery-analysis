# E-commerce Sales & Delivery Analysis

End-to-end analysis of the Olist Brazilian e-commerce dataset using **MySQL, Python (Pandas, Seaborn) and Tableau**.

**Live dashboards:** [Tableau Public link]

## Business question
Where does revenue come from, why do some customers leave poor reviews, and how can delivery performance improve?

## Data
[Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle): 8 related tables, about 100K orders, 2016 to 2018. The raw files are not included in this repo.

## Approach
1. **Load:** raw CSVs loaded into MySQL as `raw_` tables (never modified) with `load_data.py`
2. **Clean:** SQL builds `clean_` tables (`sql/01_cleaning.sql`)
3. **Analyze:** 9 SQL queries using CTEs, window functions and joins (`sql/02_analysis.sql`)
4. **Explore:** Python EDA in `notebooks/01_eda.ipynb`
5. **Visualize:** 2 Tableau dashboards

## Data cleaning log
| Table | Issue | Decision |
|---|---|---|
| orders | Dates stored as text | Converted to DATETIME; added `delivery_days`, `delay_days`, `is_late` |
| orders | Missing delivery dates | Kept as NULL; delivery metrics calculated for delivered orders only |
| reviews | Multiple reviews per order | Kept the latest review per order (`ROW_NUMBER`) |
| geolocation | About 1M rows for about 19K zip prefixes | Averaged lat/lng per zip prefix |
| products | Missing or untranslated categories | English name, then Portuguese name, then `unknown` |
| customers | `customer_id` changes per order | Used `customer_unique_id` for repeat-customer analysis |

## Key assumptions
- Revenue = `SUM(price)` on **delivered** orders only (freight excluded)
- Trend analysis uses **Jan 2017 to Aug 2018**, because 2016 and late 2018 have very few orders

## Key findings
- **Late deliveries hurt reviews:** late orders averaged **2.57 stars vs 4.29** for on-time orders, a gap of about 1.7 stars
- **Worst states for late delivery** (states with 200+ orders): **Alagoas 23.9%, Maranhão 19.7%, Piauí 16.0%**, all in the Northeast
- **Revenue is concentrated:** **18 of 74 categories** generate 80% of revenue
- **Scale:** 96,211 delivered orders and R$13.18M revenue (Jan 2017 to Aug 2018), average order value about R$137
- **Late-delivery rate peaked around March 2018** at about 20% of items
- **Retention:** [N]% of customers bought only once (from Query 7)

## Recommendations
1. Prioritize logistics and carrier performance in the Northeast states with the highest late rates
2. Make delivery estimates more accurate in those states, so fewer orders count as late
3. Launch a retention campaign for one-time buyers, since repeat purchases are rare
4. Focus inventory and marketing on the top-revenue categories

## Dashboards
![Executive overview](screenshots/dashboard1.png)
![Delivery and customer experience](screenshots/dashboard2.png)

## Repo structure
```
├── load_data.py          # loads CSVs into MySQL
├── sql/
│   ├── 01_cleaning.sql
│   └── 02_analysis.sql
├── notebooks/
│   └── 01_eda.ipynb
└── screenshots/
```

## How to reproduce
1. Download the dataset from Kaggle into a `data/` folder
2. Create a MySQL database named `olist`
3. Set your credentials in `load_data.py`, then run `python load_data.py`
4. Run `sql/01_cleaning.sql`, then `sql/02_analysis.sql`
5. Open the notebook

## Notes
Tableau figures are item-level (one row per order item), while the notebook figures are order-level, so small differences can appear between them.
