FROM astrocrpublic.azurecr.io/runtime:3.3-12

# Driver ODBC 18 cho SQL Server, dlt cần để đọc dữ liệu nguồn
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl gnupg unixodbc \
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
 && curl -fsSL https://packages.microsoft.com/config/debian/12/prod.list \
    -o /etc/apt/sources.list.d/mssql-release.list \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
 && rm -rf /var/lib/apt/lists/*
USER astro

# venv riêng cho dbt, tách khỏi thư viện của Airflow
RUN python -m venv dbt_venv \
 && . dbt_venv/bin/activate \
 && pip install --no-cache-dir dbt-core==1.12.6 dbt-snowflake==1.12.5 \
 && deactivate