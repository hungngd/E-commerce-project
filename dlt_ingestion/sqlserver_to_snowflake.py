import dlt
from dlt.sources.sql_database import sql_database

source = sql_database(
    schema="e_commerce"
)

pipeline = dlt.pipeline(
    pipeline_name="ecommerce_pipeline",
    destination="snowflake",
    dataset_name="raw_ecommerce"
)

load_info = pipeline.run(
    source,
    write_disposition="replace"
)

print(load_info)