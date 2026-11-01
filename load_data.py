import pandas as pd
from sqlalchemy import create_engine
import os

# CHANGE these to your own MySQL details
USER = "root"
PASSWORD = "NewPassword123"
HOST = "localhost"
DB = "olist"

engine = create_engine(f"mysql+pymysql://{USER}:{PASSWORD}@{HOST}/{DB}")

DATA_DIR = "data"
files = {
    "customers":    "olist_customers_dataset.csv",
    "geolocation":  "olist_geolocation_dataset.csv",
    "order_items":  "olist_order_items_dataset.csv",
    "payments":     "olist_order_payments_dataset.csv",
    "reviews":      "olist_order_reviews_dataset.csv",
    "orders":       "olist_orders_dataset.csv",
    "products":     "olist_products_dataset.csv",
    "sellers":      "olist_sellers_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}

for table, filename in files.items():
    df = pd.read_csv(os.path.join(DATA_DIR, filename))
    df.to_sql(f"raw_{table}", engine, if_exists="replace",
              index=False, chunksize=10000)
    print(f"{table:22} rows: {df.shape[0]:>9,}  cols: {df.shape[1]}")

print("Done.")