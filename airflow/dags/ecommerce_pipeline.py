import sys
from datetime import datetime

from airflow.sdk import dag, task
from cosmos import DbtTaskGroup, ExecutionConfig, ProfileConfig, ProjectConfig

DBT_PROJECT_PATH = "/usr/local/airflow/include/dbt_ecommerce"
DLT_PATH = "/usr/local/airflow/include/dlt_ingestion"
DBT_EXECUTABLE = "/usr/local/airflow/dbt_venv/bin/dbt"

profile_config = ProfileConfig(
    profile_name="dbt_ecommerce",
    target_name="dev",
    profiles_yml_filepath=f"{DBT_PROJECT_PATH}/profiles.yml",
)


@dag(
    dag_id="ecommerce_pipeline",
    schedule="@daily",
    start_date=datetime(2026, 11, 1),
    catchup=False,
    max_active_runs=1,
    tags=["ecommerce"],
)
def ecommerce_pipeline():

    @task(retries=2)
    def load_raw_with_dlt():
        sys.path.insert(0, DLT_PATH)
        from sqlserver_to_snowflake import run_pipeline

        run_pipeline()

    dbt_transform = DbtTaskGroup(
        group_id="dbt_transform",
        project_config=ProjectConfig(DBT_PROJECT_PATH, partial_parse=False),
        profile_config=profile_config,
        execution_config=ExecutionConfig(dbt_executable_path=DBT_EXECUTABLE),
    )

    load_raw_with_dlt() >> dbt_transform


ecommerce_pipeline()
