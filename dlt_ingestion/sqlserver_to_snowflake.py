import dlt
from dlt.sources.sql_database import sql_database
from dotenv import load_dotenv

load_dotenv()  # tìm file .env từ thư mục chứa script trở lên


def run_pipeline():
    source = sql_database(schema="e_commerce")

    pipeline = dlt.pipeline(
        pipeline_name="ecommerce_pipeline",
        destination="snowflake",
        dataset_name="raw_ecommerce",
    )

    load_info = pipeline.run(source, write_disposition="replace")
    print(load_info)
    return load_info


if __name__ == "__main__":
    run_pipeline()
