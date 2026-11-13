# E-commerce Data Platform – End-to-End Workflow

Dự án xây dựng một **Modern Data Stack** nhằm đưa dữ liệu từ hệ thống nguồn SQL Server vào Data Warehouse, xử lý và mô hình hóa dữ liệu theo các bài toán kinh doanh, sau đó trực quan hóa kết quả bằng Power BI.

## Overall Architecture

```text
SQL Server
    ↓
   dlt
    ↓
Snowflake
    ↓
   dbt
    ↓
 Airflow
    ↓
Power BI
```

---

## Prerequisites

Cần chuẩn bị trước khi làm theo:

```text
Python 3.12+                     → chạy dlt, dbt trên máy local
ODBC Driver 18 for SQL Server    → để pyodbc kết nối SQL Server
Tài khoản Xóm Dataset            → lấy user/password SQL Server của dataset
Tài khoản Snowflake              → bản trial miễn phí là đủ
Docker Desktop + Astro CLI       → chạy Airflow (bước 14)
Git                              → quản lý code
```

Tài khoản SQL Server của dataset được cấp riêng cho từng người tại [dataset.xomdata.com/account](https://dataset.xomdata.com/account).

> Các lệnh trong tài liệu được viết cho **Windows PowerShell**. Trên macOS / Linux, thay dấu `\` trong đường dẫn bằng `/` và dùng các lệnh tương ứng:
>
> ```text
> .venv\Scripts\Activate.ps1          →  source .venv/bin/activate
> Copy-Item .env.example .env         →  cp .env.example .env
> Get-Command dbt                     →  which dbt
> ```

---

## 1. Setup Python Environment & GitHub Project

Đầu tiên, tạo project và môi trường Python riêng để quản lý các package cần thiết cho pipeline.

### Virtual Environment

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
```

Virtual environment giúp các package của project được tách biệt với Python global trên máy, tránh xung đột version giữa các project khác nhau.

### Cài thư viện từ `requirements.txt`

Toàn bộ thư viện của project được ghim version trong `requirements.txt`, nên ai clone repo cũng cài ra đúng môi trường đã chạy được:

```powershell
pip install -r requirements.txt
```

```text
dlt[snowflake,sql_database]==1.31.0   # ingestion SQL Server → Snowflake
pyodbc==5.3.0                         # driver kết nối SQL Server
dbt-core==1.12.6                      # dbt (ghim riêng để pip không tự chọn bản beta)
dbt-snowflake==1.12.5                 # adapter Snowflake cho dbt
python-dotenv[cli]==1.2.4             # đọc file .env, có lệnh `dotenv run`
black==26.10.1                        # format code Python
sqlfluff==4.5.0                       # lint SQL
```

Kiểm tra dbt đang chạy từ `.venv` chứ không phải Python global:

```powershell
Get-Command dbt
# Source phải là ...\E-commerce-project\.venv\Scripts\dbt.exe

dbt --version
# Core: 1.12.6, snowflake: 1.12.5
```

### GitHub Repository

Project được quản lý bằng Git/GitHub để:

- lưu version của code;
- theo dõi thay đổi;
- dễ chia sẻ hoặc triển khai lại project;
- lưu documentation cho toàn bộ pipeline.

Cấu trúc project hiện tại:

```text
E-commerce-project/
├── dlt_ingestion/
│   └── sqlserver_to_snowflake.py
├── dbt_ecommerce/
│   ├── dbt_project.yml
│   ├── profiles.yml              # Chỉ chứa env_var(), được commit
│   └── models/
│       ├── staging/
│       │   ├── e_com_source.yml
│       │   ├── stg_customer.sql
│       │   ├── stg_ecom_sales.sql
│       │   ├── stg_product.sql
│       │   └── stg_region.sql
│       └── marts/
│           ├── Q1_total_rev_profit.sql
│           ├── ... (Q2 đến Q15)
│           ├── Q16_discount_band_profit.sql
│           └── Q17_yearly_profit_discount_impact.sql
├── airflow/
│   ├── dags/
│   │   └── ecommerce_pipeline.py     # DAG: dlt >> dbt
│   ├── Dockerfile
│   ├── requirements.txt              # Thư viện cho môi trường Airflow
│   └── docker-compose.override.yml   # Mount code dlt, dbt vào container
├── images/
│   └── ProjectArchitecture.png
├── .venv/                        # Không đưa lên GitHub
├── .env                          # Credentials thật, không đưa lên GitHub
├── .env.example                  # Mẫu tên biến, được commit
├── requirements.txt
├── .gitignore
├── README.md
└── Step_By_Step.md
```

---

## 2. Connect dlt to SQL Server

### dlt là gì?

`dlt` là một **data ingestion / data loading framework viết bằng Python**.

Thay vì phải tự viết toàn bộ logic để:

```text
Connect database
→ Extract data
→ Infer schema
→ Normalize data
→ Create destination tables
→ Load data
→ Track pipeline state
```

dlt cung cấp sẵn các abstraction giúp thực hiện những bước này bằng code Python ngắn gọn hơn.

Trong project này:

```text
SQL Server = Source
dlt        = Data ingestion tool
Snowflake  = Destination
```

### SQL Server Source

Source database:

```text
Database: xomdata_dataset
Schema:   e_commerce
```

Các bảng:

```text
customer
ecom_sales
product
region
```

Khai báo source:

```python
from dlt.sources.sql_database import sql_database

source = sql_database(
    schema="e_commerce"
)
```

Sau khi connect thành công:

```python
print(source.resources.keys())
```

kết quả:

```text
dict_keys(['customer', 'ecom_sales', 'product', 'region'])
```

Điều này xác nhận dlt đã kết nối được SQL Server và nhận diện đúng các bảng nguồn.

---

## 3. Store Credentials Securely

Thông tin đăng nhập không được viết trực tiếp trong Python code.

Toàn bộ credentials của project nằm trong một file `.env` ở thư mục gốc, vì biến môi trường là định dạng mà dlt, dbt, Docker (Airflow) và GitHub Actions đều đọc được. Đổi mật khẩu chỉ cần sửa một chỗ.

### `.env` và `.env.example`

`.env.example` được commit, chỉ có tên biến:

```text
# SQL Server (nguồn) - dlt đọc biến này
SOURCES__SQL_DATABASE__CREDENTIALS="mssql+pyodbc://<user>:<password>@<host>:1433/xomdata_dataset?driver=ODBC+Driver+18+for+SQL+Server&Encrypt=yes&TrustServerCertificate=yes"

# Snowflake cho dlt
DESTINATION__SNOWFLAKE__CREDENTIALS__USERNAME=DLT_LOADER_USER
DESTINATION__SNOWFLAKE__CREDENTIALS__PASSWORD=
DESTINATION__SNOWFLAKE__CREDENTIALS__HOST=
DESTINATION__SNOWFLAKE__CREDENTIALS__DATABASE=ECOMMERCE_DB
DESTINATION__SNOWFLAKE__CREDENTIALS__WAREHOUSE=ECOMMERCE_WH
DESTINATION__SNOWFLAKE__CREDENTIALS__ROLE=DLT_LOADER_ROLE

# Snowflake cho dbt
SNOWFLAKE_ACCOUNT=
DBT_SNOWFLAKE_USER=
DBT_SNOWFLAKE_PASSWORD=
DBT_SNOWFLAKE_ROLE=
DBT_SNOWFLAKE_WAREHOUSE=ECOMMERCE_WH
DBT_SNOWFLAKE_DATABASE=ECOMMERCE_DB
DBT_SNOWFLAKE_SCHEMA=
```

Tạo `.env` từ file mẫu rồi điền giá trị thật:

```powershell
Copy-Item .env.example .env
```

Quy ước tên biến của dlt: hai dấu gạch dưới `__` thay cho dấu chấm trong secrets.toml. Ví dụ `DESTINATION__SNOWFLAKE__CREDENTIALS__PASSWORD` tương đương mục `password` trong `[destination.snowflake.credentials]`. Trong chuỗi kết nối SQL Server, mật khẩu có `@` phải đổi thành `%40` vì `@` là ký tự tách mật khẩu với host.

### `profiles.yml` của dbt

`dbt_ecommerce/profiles.yml` được commit vì chỉ chứa tên biến:

```yaml
dbt_ecommerce:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('DBT_SNOWFLAKE_USER') }}"
      password: "{{ env_var('DBT_SNOWFLAKE_PASSWORD') }}"
      role: "{{ env_var('DBT_SNOWFLAKE_ROLE') }}"
      warehouse: "{{ env_var('DBT_SNOWFLAKE_WAREHOUSE') }}"
      database: "{{ env_var('DBT_SNOWFLAKE_DATABASE') }}"
      schema: "{{ env_var('DBT_SNOWFLAKE_SCHEMA') }}"
      threads: 10
```

dbt không tự đọc file `.env`, nên chạy qua lệnh `dotenv` để nạp biến trước:

```powershell
cd dbt_ecommerce
dotenv -f ..\.env run -- dbt debug --profiles-dir .
```

### `.gitignore`

```gitignore
.venv/
.dlt/secrets.toml
.env
.env.*
!.env.example
dbt_ecommerce/.user.yml
```

`!.env.example` phải đứng sau `.env.*`, vì Git đọc từ trên xuống và quy tắc sau đè quy tắc trước. Kiểm tra:

```powershell
git check-ignore -v .env           # phải in ra quy tắc chặn
git check-ignore -v .env.example   # không in gì
```

Mục đích:

> Không đưa virtual environment và các thông tin đăng nhập/private credentials lên GitHub.

---

## 4. Prepare Snowflake

Sau khi source SQL Server đã hoạt động, chuẩn bị Snowflake làm **Data Warehouse**.

Trong Snowflake cần phân biệt:

```text
DATABASE  = nơi tổ chức/lưu dữ liệu

SCHEMA    = nhóm các table bên trong database

WAREHOUSE = compute resource dùng để chạy query/load data
```

### Create Database

```sql
CREATE DATABASE IF NOT EXISTS ECOMMERCE_DB;
```

### Create Warehouse

```sql
CREATE WAREHOUSE IF NOT EXISTS ECOMMERCE_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

`XSMALL` đủ cho project học tập và tiết kiệm Snowflake credits.

`AUTO_SUSPEND = 60` giúp warehouse tự tắt khi không hoạt động.

`AUTO_RESUME = TRUE` cho phép warehouse tự bật lại khi pipeline cần chạy.

---

## 5. Create Role for dlt

Không nên cho pipeline sử dụng trực tiếp `ACCOUNTADMIN`.

Thay vào đó, tạo một custom role riêng:

```text
DLT_LOADER_ROLE
```

Role có thể hiểu là:

> Một tập hợp các quyền mà pipeline được phép sử dụng.

```sql
CREATE ROLE IF NOT EXISTS DLT_LOADER_ROLE;

GRANT USAGE
ON WAREHOUSE ECOMMERCE_WH
TO ROLE DLT_LOADER_ROLE;

GRANT USAGE
ON DATABASE ECOMMERCE_DB
TO ROLE DLT_LOADER_ROLE;

GRANT CREATE SCHEMA
ON DATABASE ECOMMERCE_DB
TO ROLE DLT_LOADER_ROLE;

GRANT ROLE DLT_LOADER_ROLE
TO ROLE SYSADMIN;
```

Role này cho phép dlt:

```text
Use ECOMMERCE_WH
        ↓
Có compute để chạy load/query

Access ECOMMERCE_DB
        ↓
Truy cập database đích

Create Schema
        ↓
Có thể tạo RAW_ECOMMERCE
```

Đây là nguyên tắc **least privilege**:

> Pipeline chỉ được cấp những quyền cần thiết cho nhiệm vụ ingestion, thay vì quyền admin toàn hệ thống.

---

## 6. Create Snowflake User for dlt

Role chỉ định **được làm gì**, nhưng vẫn cần một user để xác định:

> Ai đang đăng nhập?

Tạo:

```text
DLT_LOADER_USER
```

và gán:

```text
DLT_LOADER_USER
        ↓
DLT_LOADER_ROLE
        ↓
ECOMMERCE_WH + ECOMMERCE_DB
```

Ví dụ:

```sql
CREATE USER IF NOT EXISTS DLT_LOADER_USER
    PASSWORD = '<YOUR_PASSWORD>'
    DEFAULT_ROLE = DLT_LOADER_ROLE
    DEFAULT_WAREHOUSE = ECOMMERCE_WH
    DEFAULT_NAMESPACE = ECOMMERCE_DB;

GRANT ROLE DLT_LOADER_ROLE
TO USER DLT_LOADER_USER;
```

Password thật không được lưu trong SQL file trên GitHub.

Credentials của user được lưu trong `.env` (không commit), xem mục 3.

---

## 7. Configure Snowflake Destination

Trong `.env`, khai báo Snowflake destination:

```text
DESTINATION__SNOWFLAKE__CREDENTIALS__USERNAME=DLT_LOADER_USER
DESTINATION__SNOWFLAKE__CREDENTIALS__PASSWORD=<PASSWORD>
DESTINATION__SNOWFLAKE__CREDENTIALS__HOST=<SNOWFLAKE_ACCOUNT_IDENTIFIER>
DESTINATION__SNOWFLAKE__CREDENTIALS__DATABASE=ECOMMERCE_DB
DESTINATION__SNOWFLAKE__CREDENTIALS__WAREHOUSE=ECOMMERCE_WH
DESTINATION__SNOWFLAKE__CREDENTIALS__ROLE=DLT_LOADER_ROLE
```

dlt tự đọc biến môi trường có tiền tố `DESTINATION__` và `SOURCES__`, nhưng không tự mở file `.env`. Script gọi `load_dotenv()` ở đầu để nạp file này (xem mục 12.1).

Lúc này dlt đã có đầy đủ:

```text
Source credentials       → SQL Server
Destination credentials  → Snowflake
```

---

## 8. Create the dlt Pipeline

Pipeline có thể hiểu là **toàn bộ tuyến vận chuyển dữ liệu**.

```python
pipeline = dlt.pipeline(
    pipeline_name="ecommerce_pipeline",
    destination="snowflake",
    dataset_name="raw_ecommerce"
)
```

Trong đó:

```text
pipeline_name
= tên pipeline để dlt quản lý state và metadata

destination
= nơi dữ liệu được load tới

dataset_name
= schema đích trong Snowflake
```

Vì:

```python
dataset_name="raw_ecommerce"
```

nên destination cuối cùng là:

```text
ECOMMERCE_DB.RAW_ECOMMERCE
```

---

## 9. Load Data from SQL Server to Snowflake

Pipeline được thực thi bằng:

```python
pipeline.run(source)
```

Bản chất bên trong:

```text
SQL Server
    ↓
EXTRACT
    ↓
NORMALIZE
    ↓
LOAD
    ↓
Snowflake
```

Sau lần load đầu tiên, Snowflake tự động có:

```text
ECOMMERCE_DB
└── RAW_ECOMMERCE
    ├── CUSTOMER
    ├── ECOM_SALES
    ├── PRODUCT
    ├── REGION
    ├── _DLT_LOADS
    ├── _DLT_PIPELINE_STATE
    └── _DLT_VERSION
```

Các bảng `_DLT_*` được dlt sử dụng để quản lý metadata, schema version, load history và pipeline state.

---

## 10. Choose the Loading Strategy

Kiểm tra source `ecom_sales`:

```text
Minimum order date: 2020-01-01
Maximum order date: 2023-12-31
Total rows:         51,290
```

Dataset được xem là một **historical/static snapshot** trong phạm vi project.

Vì vậy, không cần thiết kế incremental loading phức tạp.

Sử dụng:

```python
load_info = pipeline.run(
    source,
    write_disposition="replace"
)

print(load_info)
```

### Why `replace`?

Nếu sử dụng `append` với một static dataset:

```text
Run 1 → 51,290 rows
Run 2 → 102,580 rows
Run 3 → 153,870 rows
```

có thể tạo duplicate data.

`replace` sẽ full refresh lại RAW tables:

```text
SQL Server snapshot
        ↓
replace
        ↓
Snowflake RAW
```

Nhờ đó Snowflake luôn phản ánh đúng trạng thái hiện tại của source.

---

## 11. Validate Loaded Data

Sau khi load, đối chiếu row count giữa source và destination.

| Table | SQL Server | Snowflake | Status |
|---|---:|---:|---|
| `customer` | 17,415 | 17,415 | ✅ |
| `ecom_sales` | 51,290 | 51,290 | ✅ |
| `product` | 28,356 | 28,356 | ✅ |
| `region` | 3,828 | 3,828 | ✅ |

Tất cả row counts đều khớp.

Do đó:

```text
SQL Server
    ↓
   dlt
    ↓
Snowflake RAW
```

**Ingestion phase completed successfully.**

---

## 12. Transform Data with dbt

Sau khi nạp dữ liệu vào `ECOMMERCE_DB.RAW_ECOMMERCE` bằng dlt, dùng dbt để quản lý nguồn dữ liệu, kiểm tra chất lượng và xây dựng các SQL models phục vụ phân tích.

**Cấu trúc sử dụng trong project:**

```text
SQL Server (e_commerce)
    ↓ dlt
Snowflake: ECOMMERCE_DB.RAW_ECOMMERCE
    ↓ dbt source() / staging views
Snowflake: ECOMMERCE_DB.DBT_DEV.STG_*
    ↓ dbt ref() / marts
Snowflake: ECOMMERCE_DB.DBT_DEV.Q1_* ... Q17_*
```

### 12.1. Full dlt ingestion script

**Đường dẫn:** `dlt_ingestion/sqlserver_to_snowflake.py`

Đây là file Python đã dùng để khai báo nguồn, cấu hình pipeline và thực hiện `replace` load. Cấu hình kết nối riêng tư nằm trong `.env` (không commit).

```python
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
```

Code được gói trong hàm `run_pipeline()` để Airflow import và gọi lại. Khối `if __name__ == "__main__":` giữ cho lệnh `python dlt_ingestion\sqlserver_to_snowflake.py` vẫn chạy được, còn khi bị import thì pipeline không tự chạy.

### 12.2. dbt project configuration

**Đường dẫn:** `dbt_ecommerce/dbt_project.yml`

`name` đặt tên project; `profile` liên kết với cấu hình Snowflake trong `dbt_ecommerce/profiles.yml` (mục 3); các cấu hình `materialized` quy định loại object dbt tạo trong Snowflake.

```yaml
# Name your project! Project names should contain only lowercase characters
# and underscores. A good package name should reflect your organization's
# name or the intended use of these models
name: 'dbt_ecommerce'
version: '1.0.0'

# This setting configures which "profile" dbt uses for this project.
profile: 'dbt_ecommerce'

# These configurations specify where dbt should look for different types of files.
# The `model-paths` config, for example, states that models in this project can be
# found in the "models/" directory. You probably won't need to change these!
model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

clean-targets:         # directories to be removed by `dbt clean`
  - "target"
  - "dbt_packages"


# Configuring models
# Full documentation: https://docs.getdbt.com/docs/configuring-models

# In this example config, we tell dbt to build all models in the example/
# directory as views. These settings can be overridden in the individual model
# files using the `{{ config(...) }}` macro.
models:
  dbt_ecommerce:
    staging:
      +materialized: view
    marts:
      +materialized: table
```

### 12.3. dbt source definitions & tests

**Đường dẫn:** `dbt_ecommerce/models/staging/e_com_source.yml`

File khai báo bốn bảng RAW và các bài kiểm tra `unique`, `not_null`, `relationships` cho các cột liên quan. `source()` được dùng trong staging để truy xuất raw tables.

```yaml
version: 2

sources:
  - name: e_com_source # Đặt tên cho source
    database: ecommerce_db # Tên database chứa dữ liệu nguồn  
    schema: raw_ecommerce # Tên schema chứa dữ liệu nguồn
    description: "This is the source data for the e-commerce project." # Viết comment cho từng nội dung
    tables:
      - name: customer # Tạo test + description cho từng cột trong bảng
        description: "This table contains customer information."
        columns:
          - name: customer_id
            description: "The unique identifier for each customer."
            tests:
              - unique # Test duplicate values
              - not_null # Test null values

      - name: ecom_sales
        description: "This table contains sales information."
        columns:
          - name: order_id
            description: "The identifier for each order."
            tests:
              - not_null
          - name: customer_id
            description: "The unique identifier for the customer who placed the order."
            tests:
              - relationships: # Set up foreign key relationship to the customers table
                  arguments:
                    to: source('e_com_source', 'customer')
                    field: customer_id
          - name: product_code
            description: "The unique code for the product that was ordered."
            tests:
              - relationships: # Set up foreign key relationship to the products table
                  arguments:
                    to: source('e_com_source', 'product')
                    field: product_code
                  config:
                    severity: warn
          - name: region_code
            description: "The code for the region where the order was placed."
            tests:
              - relationships: # Set up foreign key relationship to the regions table
                  arguments:
                    to: source('e_com_source', 'region')
                    field: region_code
                  config:
                    severity: warn
          - name: order_date
            description: "The date when the order was placed."
            tests:
              - not_null

      - name: product
        description: "This table contains product information."
        columns:
          - name: product_code
            description: "The unique code for each product."
            tests:
              - unique
              - not_null

      - name: region
        description: "This table contains region information."
        columns:
          - name: region_code
            description: "The unique code for each region."
            tests:
              - unique
              - not_null
```

**Dữ liệu nguồn có mã sai:** relationship tests phát hiện bảng `ecom_sales` có các mã không tồn tại trong bảng danh mục:

```text
region_code   RRR0001     → đúng là R0001
product_code  PPP000010   → đúng là P000010
product_code  PPP000002   → đúng là P000002
```

Đây là lỗi của dữ liệu nguồn, được sửa ở model `stg_ecom_sales` (mục 12.4). Vì test chạy trên bảng RAW nên vẫn luôn phát hiện các mã này. Hai test được đặt `severity: warn`:

```text
severity: error (mặc định) → test fail, dbt build bỏ qua (SKIP) mọi model phía sau
severity: warn             → vẫn báo cảnh báo, nhưng không chặn pipeline
```

Kết quả `dbt build`:

```text
Done. PASS=28 WARN=2 ERROR=0 SKIP=0 TOTAL=30
```

### 12.4. Staging models

Các model staging lấy dữ liệu từ `source('e_com_source', ...)` và được cấu hình materialize thành `view`.

#### `stg_customer.sql`

**Đường dẫn:** `dbt_ecommerce/models/staging/stg_customer.sql`

```sql
SELECT
    customer_id,
    first_name,
    last_name,
    birth_date,
    marital_status,
    gender,
    email_address,
    annual_income,
    education_level,
    occupation,
    home_owner
FROM {{ source('e_com_source', 'customer') }}
```

#### `stg_ecom_sales.sql`

**Đường dẫn:** `dbt_ecommerce/models/staging/stg_ecom_sales.sql`

```sql
SELECT
    row_id,
    order_id,
    order_date,
    customer_id,
    segment,
    CASE
        WHEN region_code = 'RRR0001' THEN 'R0001'
        ELSE region_code
    END AS region_code,
    CASE
        WHEN product_code = 'PPP000010' THEN 'P000010'
        WHEN product_code = 'PPP000002' THEN 'P000002'
        ELSE product_code
    END AS product_code,
    quantity,
    sales,
    discount,
    profit
FROM {{ source('e_com_source', 'ecom_sales') }}
```

#### `stg_product.sql`

**Đường dẫn:** `dbt_ecommerce/models/staging/stg_product.sql`

```sql
SELECT
    product_code,
    product,
    category,
    subcategory
FROM {{ source('e_com_source', 'product') }}
```

#### `stg_region.sql`

**Đường dẫn:** `dbt_ecommerce/models/staging/stg_region.sql`

```sql
SELECT
    region_code,
    city,
    state,
    country,
    country_latitude,
    country_longitude,
    region,
    market
FROM {{source ('e_com_source', 'region') }}
```

### 12.5. Một số lệnh dbt đã sử dụng

Chạy từ thư mục chứa `dbt_project.yml`. Mọi lệnh đều chạy qua `dotenv -f ..\.env run --` để nạp biến môi trường, và kèm `--profiles-dir .` để dbt dùng `profiles.yml` trong project thay vì `~/.dbt/profiles.yml`:

```powershell
cd dbt_ecommerce

# Kiểm tra kết nối Snowflake và profile
dotenv -f ..\.env run -- dbt debug --profiles-dir .

# Đọc và kiểm tra project / dependency
dotenv -f ..\.env run -- dbt parse --profiles-dir .

# Build staging trước nếu cần kiểm tra riêng
dotenv -f ..\.env run -- dbt run --select path:models/staging --profiles-dir .

# Chạy model + test theo đúng thứ tự phụ thuộc
dotenv -f ..\.env run -- dbt build --profiles-dir .

# Xem preview một model cụ thể
dotenv -f ..\.env run -- dbt show -s Q11_yoy_growth_pct --limit 20 --profiles-dir .
```

**Phân biệt:** `dbt run` tạo/cập nhật các view và table; `dbt show` chỉ preview query; `dbt test` chạy kiểm thử. Một model build thành công không đồng nghĩa mọi phép tính nghiệp vụ đều đúng.

---

## 13. Business Mart Models (Q1 đến Q17)

Thư mục: `dbt_ecommerce/models/marts/`

Mỗi model trả lời một câu hỏi kinh doanh trong đề bài Xóm E-Com. Tất cả đọc dữ liệu qua `ref()` từ các model staging và được tạo thành **table** trong `ECOMMERCE_DB.DBT_DEV`.

### Q1: `Q1_total_rev_profit.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q1_total_rev_profit.sql`

```sql
-- Q1: Calculate the total revenue and profit for the entire dataset.
SELECT
    SUM(sales) AS total_revenue,
    SUM(profit) AS total_profit
FROM {{ ref('stg_ecom_sales') }};
```

**Ý tưởng:**

> Tính tổng sales và profit bằng hàm SUM.

### Q2: `Q2_total_rev_profit_segments.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q2_total_rev_profit_segments.sql`

```sql
-- Q2: Calculate the total revenue and profit for each segment.
SELECT
    segment,
    SUM(sales) AS total_revenue,
    SUM(profit) AS total_profit
FROM {{ ref('stg_ecom_sales') }}
GROUP BY segment
ORDER BY total_revenue DESC;
```

**Ý tưởng:**

> Do chia theo segment ta sẽ dùng hàm GROUP BY để tính.

### Q3: `Q3_top_10_products.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q3_top_10_products.sql`

```sql
-- Q3: Identify the top 10 best-selling products.
SELECT
    s.product_code,
    p.product,
    SUM(s.quantity) AS total_quantity_sold
FROM {{ ref('stg_ecom_sales') }} AS s
INNER JOIN {{ ref('stg_product') }} AS p
    ON s.product_code = p.product_code
GROUP BY s.product_code, p.product
ORDER BY total_quantity_sold DESC
LIMIT 10;
```

**Ý tưởng:**

> Do bài toán muốn chúng ta tìm 10 sản phẩm bán chạy nhất, nên phải JOIN 2 bảng stg_ecom_sales và stg_product lại với nhau để có thể hiện mã + tên sản phẩm cùng với tổng doanh thu, LIMIT 10 để lấy giới hạn 10 sản phẩm sales cao nhất.

### Q4: `Q4_customer_per_segments.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q4_customer_per_segments.sql`

```sql
-- Q4: Calculate total customer per gender (Male, female and unknown gender) and occupation.
SELECT
    occupation,
    SUM(CASE WHEN gender = 'M' THEN 1 ELSE 0 END) AS male,
    SUM(CASE WHEN gender = 'F' THEN 1 ELSE 0 END) AS female,
    SUM(CASE WHEN gender IS NULL THEN 1 ELSE 0 END) AS unknown_gender,
    COUNT(*) AS total_customers
FROM {{ ref('stg_customer') }}
GROUP BY occupation
ORDER BY total_customers DESC;
```

**Ý tưởng:**

> Ở đây bài toán yêu cầu ta tìm số lượng khách hàng theo từng giới tính và nghề nghiệp, có thể dùng CASE WHEN lồng vào hàm SUM (Ý nghĩa của nó sẽ là nếu là Male nó sẽ trả về 1 nếu ko sẽ trả về 0 và sẽ cộng hết vào là biết được có bao nhiêu khách hàng là nam).

### Q5: `Q5_avg_discount_category.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q5_avg_discount_category.sql`

```sql
-- Q5: Average discount by category
SELECT
    p.category,
    CAST(
        AVG(s.discount) * 100.0
        AS DECIMAL(5, 2)
    ) AS avg_discount
FROM {{ ref ('stg_ecom_sales') }} AS s
INNER JOIN {{ ref ('stg_product') }} AS p
    ON s.product_code = p.product_code
GROUP BY p.category
ORDER BY avg_discount DESC;
```

**Ý tưởng:**

> Ta sẽ join category ở bảng stg_product và tính AVG discount ở bảng stg_ecom_sales, dùng CAST(... AS DECIMAL (5,2)) để kết quả trả về dạng số thập phân được làm tròn 2 số sau dấu phẩy.

### Q6: `Q6_profit_margin_markets.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q6_profit_margin_markets.sql`

```sql
-- Q6: Profit margin by market
SELECT
    r.market,
    CAST(SUM(s.sales) AS DECIMAL(10, 2)) AS total_sales,
    CAST(SUM(s.profit) AS DECIMAL(10, 2)) AS total_profit,
    CAST(
        100.0
        * SUM(s.profit) / NULLIF(SUM(s.sales), 0)
        AS DECIMAL(5, 2)
    ) AS profit_margin
FROM {{ ref ('stg_ecom_sales') }} AS s
INNER JOIN {{ ref ('stg_region') }} AS r
    ON s.region_code = r.region_code
GROUP BY r.market
HAVING COUNT(DISTINCT s.order_id) >= 100
ORDER BY profit_margin DESC;
```

**Ý tưởng:**

> Ta sẽ tìm profit margin bằng cách tính tổng sales và profit của từng market một, HAVING COUNT dùng để lọc những market có ít nhất 100 đơn hàng (Hàm này dùng sau khi GROUP, phân biệt với hàm WHERE dùng trước khi GROUP), dùng NULLIF cho những phép tính chia để tránh việc có thể chia cho số 0 bị lỗi.

### Q7: `Q7_loss_order_segments.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q7_loss_order_segments.sql`

```sql
-- Q7: Loss Order Calculation Segments
WITH order_profit AS (
    SELECT
        order_id,
        segment,
        SUM(profit) AS order_profit
    FROM {{ ref ('stg_ecom_sales') }}
    GROUP BY order_id, segment
)

SELECT
    segment,
    CAST(
        100.0
        * COUNT(CASE WHEN order_profit < 0 THEN 1 END) / NULLIF(COUNT(order_id), 0)
        AS DECIMAL(5, 2)
    ) AS loss_order_pct,
    COUNT(order_id) AS total_order,
    COUNT(CASE WHEN order_profit < 0 THEN 1 END) AS total_loss_order,
    SUM(CASE WHEN order_profit < 0 THEN order_profit ELSE 0 END) AS total_loss_profit
FROM order_profit
GROUP BY segment
ORDER BY loss_order_pct DESC;
```

**Ý tưởng:**

> Ở đây ta sẽ tạo 1 CTE để tính tổng profit cho từng order_id + segment. Sau đó từ CTE đó ta sẽ đếm những order có profit âm, và tính tỷ trọng của chúng so với tổng số order  theo từng segments cùng với tổng loss profit của từng segment.

### Q8: `Q8_identify_churning_VIP_customers.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q8_identify_churning_VIP_customers.sql`

```sql
-- Q8: Identify the top 50 customers based on their total lifetime spend 
-- and calculate the number of days since their last order. 
-- Only include customers who have not placed an order in the last 180 days.
WITH customer_summary AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        SUM(s.sales) AS total_lifetime_spend,
        MAX(s.order_date) AS last_order_date_customer
    FROM {{ ref('stg_customer') }} AS c
    INNER JOIN {{ ref('stg_ecom_sales') }} AS s
        ON c.customer_id = s.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name
    ORDER BY total_lifetime_spend DESC
    LIMIT 50
),

bound AS (
    SELECT MAX(order_date) AS last_order_date
    FROM {{ ref('stg_ecom_sales') }}
)

SELECT
    cs.total_lifetime_spend,
    cs.last_order_date_customer,
    cs.first_name || ' ' || cs.last_name AS customer_name,
    DATEDIFF('day', cs.last_order_date_customer, b.last_order_date) AS days_since_last_order
FROM customer_summary AS cs
CROSS JOIN bound AS b
WHERE DATEDIFF('day', cs.last_order_date_customer, b.last_order_date) >= 180
ORDER BY cs.total_lifetime_spend DESC;
```

**Ý tưởng:**

> Ý tưởng là ta sẽ phải tìm xem những khách nào có mức chi tiêu cao nhất, nhưng đã lâu rồi không mua lại (180 ngày ~ 6 tháng). Đầu tiên tạo 1 CTE lấy ra top 50 khách hàng chi tiêu nhiều nhất cùng với ngày cuối cùng mà họ mua kèm thông tin khách hàng. Tạo 1 CTE dùng để làm biên giới hạn (bound) của ngày cuối cùng có order trong bảng stg_ecom_sales. Sau đó dựa vào 2 CTE đó ta sẽ dùng hàm DATEDIFF để lọc ra những customer có khoảng thời gian cách bound từ 180 ngày trở lên.

### Q9: `Q9_pct_sale_category.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q9_pct_sale_category.sql`

```sql
-- Q9: Calculate the percentage of sales by customer segment for each product category
WITH total_sale_category AS (
    SELECT
        p.category,
        SUM(CASE WHEN s.segment = 'Consumer' THEN s.sales ELSE 0 END) AS consumer_sales,
        SUM(CASE WHEN s.segment = 'Corporate' THEN s.sales ELSE 0 END) AS corporate_sales,
        SUM(CASE WHEN s.segment = 'Self-Employed' THEN s.sales ELSE 0 END) AS self_employed_sales,
        SUM(s.sales) AS total_sales
    FROM {{ ref('stg_ecom_sales') }} AS s
    INNER JOIN {{ ref('stg_product') }} AS p
        ON s.product_code = p.product_code
    GROUP BY p.category
)

SELECT
    category,
    CAST(
        100.0
        * consumer_sales / NULLIF(total_sales, 0)
        AS DECIMAL(5, 2)
    ) AS pct_consumer,
    CAST(
        100.0
        * corporate_sales / NULLIF(total_sales, 0)
        AS DECIMAL(5, 2)
    ) AS pct_corporate,
    CAST(
        100.0
        * self_employed_sales / NULLIF(total_sales, 0)
        AS DECIMAL(5, 2)
    ) AS pct_self_employed,
    total_sales
FROM total_sale_category
ORDER BY category;
```

**Ý tưởng:**

> Idea chính trong câu này sẽ là phải đi tìm tỷ trọng doanh thu của từng segment. Với CTE đầu tiên ta sẽ đi tính tổng doanh thu của từng category, sau đó sẽ dựa vào CTE đó để tính tỷ trọng của từng category một so với tổng doanh thu.

### Q10: `Q10_top_15_total_sales_countries.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q10_top_15_total_sales_countries.sql`

```sql
-- Q10: Top 15 countries by total sales, along with the number of active regions 
-- and total customers and orders in each country.
SELECT
    r.country,
    COUNT(DISTINCT r.region_code) AS region_active,
    COUNT(DISTINCT s.customer_id) AS total_customers,
    COUNT(DISTINCT s.order_id) AS total_orders,
    SUM(s.sales) AS total_sales
FROM {{ ref('stg_ecom_sales') }} AS s
INNER JOIN {{ ref('stg_region') }} AS r
    ON s.region_code = r.region_code
GROUP BY r.country
ORDER BY total_sales DESC
LIMIT 15;
```

**Ý tưởng:**

> Idea chính sẽ là đi tìm xem top 15 quốc gia có doanh thu lớn nhất, số khu vực hoạt động, Số khách hàng và tổng số đơn hàng cho từng quốc gia. Có một lưu ý là region_active có thể được hiểu là số thành phố trong quốc gia ý hoạt động, chứ không được nhầm lẫn sang cột region của bảng stg_region.

### Q11: `Q11_yoy_growth_pct.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q11_yoy_growth_pct.sql`

```sql
-- Q11: Calculate the year-over-year growth in sales for the last 24 months.
WITH sale_months AS (
    SELECT
        DATE_TRUNC('month', order_date) AS month,
        SUM(sales) AS total_sales
    FROM {{ ref('stg_ecom_sales') }}
    GROUP BY DATE_TRUNC('month', order_date)
),

previous_year_sales AS (
    SELECT
        month,
        total_sales,
        LAG(total_sales, 12) OVER (ORDER BY month) AS previous_year_sales
    FROM sale_months
),

bound AS (
    SELECT MAX(month) AS max_month
    FROM sale_months
)

SELECT
    pys.total_sales,
    pys.previous_year_sales,
    CAST(
        100 * (pys.total_sales - pys.previous_year_sales)
        / NULLIF(pys.previous_year_sales, 0) AS DECIMAL(5, 2)
    ) AS yoy_growth_pct,
    TO_CHAR(pys.month, 'YYYY-MM') AS month
FROM previous_year_sales AS pys
CROSS JOIN bound AS b
WHERE month >= DATEADD('month', -23, b.max_month)
ORDER BY pys.month;
```

**Ý tưởng:**

> Ta sẽ tính tăng trưởng theo tháng so với cùng tháng đó năm ngoái (Trong 24 tháng gần nhất). Do là theo tháng nên phải chuyển định dạng order_date về 'YYYY-mm'. Ta sử dụng hàm LAG để trả ra kết quả sale của cùng tháng đó năm ngoái cùng với tạo 1 CTE bound để có giới hạn tháng cuối cùng có order. Và sẽ tạo điều kiện với hàm DATEADD (Hiểu đơn giản là ta sẽ chỉ cho ra những kết quả từ tháng bound và 23 tháng đổ về trước để có tổng là 24 tháng).

### Q12: `Q12_top3_products_categories.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q12_top3_products_categories.sql`

```sql
-- Q12: Top 3 products by profit in each category
WITH sale_products AS (
    SELECT
        p.category,
        p.product,
        p.product_code,
        SUM(s.profit) AS total_profit
    FROM {{ ref('stg_ecom_sales') }} AS s
    INNER JOIN {{ ref('stg_product') }} AS p
        ON s.product_code = p.product_code
    GROUP BY p.product, p.category, p.product_code
),

ranked_products AS (
    SELECT
        category,
        product,
        product_code,
        total_profit,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY total_profit DESC, product_code ASC) AS rank_in_category
    FROM sale_products
)

SELECT
    category,
    product,
    product_code,
    total_profit,
    rank_in_category
FROM ranked_products
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;
```

**Ý tưởng:**

> Ta sẽ tạo 1 CTE tính doanh thu của từng sản trong từng category trước. Sau đó tạo 1 CTE để rank (Lưu ý đề bài bảo top 3 sản phẩm trong mỗi category), ta sẽ sử dụng ROW_NUMBER để đánh dấu rank các sản phẩm theo doanh thu từ cao đến thấp theo từng category. Và cuối cùng sẽ lọc ra những sản phẩm có rank trong khoảng từ 1 đến 3.

### Q13: `Q13_customer_buy_in_multi_region.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q13_customer_buy_in_multi_region.sql`

```sql
-- Q13: Identify customers who have made purchases in multiple regions and calculate the percentage of such customers.
WITH customer_details AS (
    SELECT
        customer_id,
        order_id,
        region_code,
        order_date,
        sales
    FROM {{ ref('stg_ecom_sales') }}

),

first_region AS (
    SELECT
        customer_id,
        region_code,
        sales,
        FIRST_VALUE(region_code) OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS first_region
    FROM customer_details
),

flag_customers AS (
    SELECT
        customer_id,
        first_region,
        region_code,
        sales,
        CASE
            WHEN first_region != region_code THEN 1
            ELSE 0
        END AS flag_customers
    FROM first_region
),

customer_region_summary AS (
    SELECT
        customer_id,
        first_region,
        SUM(sales) AS total_sales,
        MAX(flag_customers) AS is_multi_region,
        COUNT(DISTINCT region_code) AS region_count
    FROM flag_customers
    GROUP BY customer_id, first_region
),

pct_multi_region AS (
    SELECT CAST(100.0 * SUM(is_multi_region) / NULLIF(COUNT(*), 0) AS DECIMAL(5, 2)) AS multi_region_pct
    FROM customer_region_summary
)

SELECT
    crs.customer_id,
    r.city AS first_city,
    r.country,
    crs.total_sales,
    pmr.multi_region_pct
FROM customer_region_summary AS crs
CROSS JOIN pct_multi_region AS pmr
INNER JOIN {{ ref('stg_region') }} AS r
    ON crs.first_region = r.region_code
WHERE crs.is_multi_region = 1
ORDER BY crs.total_sales DESC
LIMIT 20;
```

**Ý tưởng:**

> Idea chính ở đây sẽ là phải đi tìm được số lượng khách hàng mua ở nhiều khu vực khác nhau để có thể tính tỷ trọng. Đầu tiên ta sẽ tạo 1 CTE có các thông tin cơ bản về order của 1 customer. Sau đó ta sẽ tạo 1 CTE để biết được nơi mà khách hàng mua đầu tiền (Dùng hàm FIRST_VALUE), từ CTE này ta sẽ flag những nơi khác nơi đầu tiên khách hàng mua (Nếu khác sẽ trả về 1, nếu ko sẽ trả về 0). Từ đó ta sẽ có thể tính được số % khách hàng có mua ở nhiều khu vực khác nhau.

### Q14: `Q14_frm_segmentation.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q14_frm_segmentation.sql`

```sql
-- Q14: Customer Segmentation based on RFM (Recency, Frequency, Monetary) analysis
WITH bound AS (
    SELECT MAX(order_date) AS last_order_date
    FROM {{ ref('stg_ecom_sales') }}
),

customer_details AS (
    SELECT
        s.customer_id,
        MAX(s.order_date) AS last_order_customer,
        DATEDIFF('day', MAX(s.order_date), MAX(b.last_order_date)) AS days_since_last_order,
        COUNT(DISTINCT s.order_id) AS total_orders,
        SUM(s.sales) AS total_spent
    FROM {{ ref('stg_ecom_sales') }} AS s
    CROSS JOIN bound AS b
    GROUP BY s.customer_id
),

filter_segments AS (
    SELECT
        customer_id,
        days_since_last_order AS recency_days,
        total_orders AS frequency,
        total_spent AS monetary,
        NTILE(5) OVER (ORDER BY days_since_last_order DESC) AS n_recency,
        NTILE(5) OVER (ORDER BY total_orders ASC) AS n_orders,
        NTILE(5) OVER (ORDER BY total_spent ASC) AS n_spend
    FROM customer_details
)

SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    n_recency,
    n_orders,
    n_spend,
    n_recency + n_orders + n_spend AS rfm_score
FROM filter_segments
ORDER BY rfm_score DESC
LIMIT 20;
```

**Ý tưởng:**

> Ta sẽ phải đi tìm recency, frequency, monetary của từng khách hàng và sau đó tính điểm để xếp hạng. Với recency ta sẽ so sánh với ngày cuối cùng có order (Dùng hàm DATEFDIFF), với frequency ta sẽ dùng hàm count (Lưu ý tránh bị lặp order do 1 order có thể sẽ có nhiều dòng) và với monetary ta sẽ dùng hàm SUM - Tính cho từng customer_id. Sau đó ta sẽ dùng hàm NTILE(5) để giúp chia ra 5 phân khúc điểm khác nhau rồi sau đó cộng lại và xếp hạng top 20.

### Q15: `Q15_pair_products.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q15_pair_products.sql`

```sql
WITH order_products AS (
    SELECT DISTINCT
        order_id,
        product_code
    FROM {{ ref('stg_ecom_sales') }}
),

self_joined AS (
    SELECT
        a.order_id,
        a.product_code AS product_code_a,
        b.product_code AS product_code_b
    FROM order_products AS a
    INNER JOIN order_products AS b
        ON a.order_id = b.order_id AND a.product_code < b.product_code
)

SELECT
    pa.product AS product_a,
    pb.product AS product_b,
    COUNT(*) AS pair_count
FROM self_joined AS sj
INNER JOIN {{ ref('stg_product') }} AS pa
    ON sj.product_code_a = pa.product_code
INNER JOIN {{ ref('stg_product') }} AS pb
    ON sj.product_code_b = pb.product_code
GROUP BY product_a, product_b
ORDER BY pair_count DESC
LIMIT 15
```

**Ý tưởng:**

> Ý tưởng là ta sẽ phải tạo ra được 1 bảng sao cho có cột product a và cột product b tương ứng với 1 cặp sản phẩm. Ta có thể JOIN 2 bảng trùng nhau lại nhưng phải để ý điều kiện khi JOIN (tránh việc product_code a trùng với product_code b). Khi đã có bảng mới tương ứng với các cặp sản phẩm thì ta sẽ đếm xem các cặp xuất hiện bao nhiêu lần.

### Q16: `Q16_discount_band_profit.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q16_discount_band_profit.sql`

Q5 mới chỉ tính mức giảm giá trung bình theo category, chưa đặt giảm giá cạnh lợi nhuận. Q16 trả lời trực tiếp câu hỏi "giảm giá bao nhiêu thì bắt đầu lỗ".

```sql
-- Q16: Profit margin by discount band.
-- At which discount level do order lines start to lose money?
WITH banded AS (
    SELECT
        order_id,
        sales,
        profit,
        CASE
            WHEN discount = 0 THEN '1. 0%'
            WHEN discount <= 0.1 THEN '2. 1-10%'
            WHEN discount <= 0.2 THEN '3. 11-20%'
            WHEN discount <= 0.4 THEN '4. 21-40%'
            ELSE '5. >40%'
        END AS discount_band
    FROM {{ ref('stg_ecom_sales') }}
)

SELECT
    discount_band,
    COUNT(*) AS total_lines,
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(sales) AS total_sales,
    SUM(profit) AS total_profit,
    CAST(
        100.0 * SUM(profit) / NULLIF(SUM(sales), 0) AS DECIMAL(6, 2)
    ) AS profit_margin,
    CAST(
        100.0 * SUM(sales) / SUM(SUM(sales)) OVER () AS DECIMAL(5, 2)
    ) AS pct_of_total_sales,
    CAST(
        100.0 * SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 2)
    ) AS pct_loss_lines
FROM banded
GROUP BY discount_band
ORDER BY discount_band
```

**Ý tưởng:**

> Chia từng dòng bán hàng vào 5 nhóm mức giảm giá bằng CASE WHEN, rồi GROUP BY theo nhóm để tính doanh thu, lợi nhuận, biên lợi nhuận và tỷ lệ dòng bị lỗ. `SUM(SUM(sales)) OVER ()` là window function chạy sau GROUP BY, cho ra tổng doanh thu toàn bảng để tính mỗi nhóm chiếm bao nhiêu phần trăm.

**Kết quả (dữ liệu 2020-2023, 51.290 dòng):**

| Nhóm giảm giá | Số dòng | Doanh thu | Lợi nhuận | Biên lợi nhuận | Tỷ lệ dòng lỗ |
| :--- | ---: | ---: | ---: | ---: | ---: |
| 0% | 29.470 | 3.647.815 | 1.141.918 | 31,30% | 0,00% |
| 1-10% | 4.218 | 563.810 | 113.451 | 20,12% | 0,00% |
| 11-20% | 6.315 | 832.883 | 98.227 | 11,79% | 43,50% |
| 21-40% | 4.430 | 594.576 | -51.387 | -8,64% | 52,05% |
| >40% | 6.857 | 878.590 | -236.794 | -26,95% | 87,33% |

**Nhận định:**

> Biên lợi nhuận giảm dần theo mức giảm giá và chuyển sang âm từ mức trên 20%. Hai nhóm trên 20% chiếm khoảng 23% doanh thu nhưng lỗ 288.181, bằng 27% tổng lợi nhuận cả giai đoạn (1.065.414).
>
> Đề xuất: đặt trần giảm giá 20%, đơn nào cần giảm sâu hơn phải được duyệt riêng.

### Q17: `Q17_yearly_profit_discount_impact.sql`

**Đường dẫn:** `dbt_ecommerce/models/marts/Q17_yearly_profit_discount_impact.sql`

```sql
-- Q17: Split yearly profit into deep-discount lines (discount > 20%) and the rest.
-- Explains why profit fell in 2023 while sales kept growing.
WITH yearly AS (
    SELECT
        YEAR(order_date) AS order_year,
        SUM(sales) AS total_sales,
        SUM(profit) AS total_profit,
        SUM(CASE WHEN discount > 0.2 THEN sales ELSE 0 END) AS deep_discount_sales,
        SUM(CASE WHEN discount > 0.2 THEN profit ELSE 0 END) AS deep_discount_profit,
        SUM(CASE WHEN discount <= 0.2 THEN profit ELSE 0 END) AS other_profit
    FROM {{ ref('stg_ecom_sales') }}
    GROUP BY YEAR(order_date)
)

SELECT
    order_year,
    total_sales,
    total_profit,
    deep_discount_profit,
    other_profit,
    CAST(
        100.0 * total_profit / NULLIF(total_sales, 0) AS DECIMAL(5, 2)
    ) AS profit_margin,
    CAST(
        100.0 * deep_discount_sales / NULLIF(total_sales, 0) AS DECIMAL(5, 2)
    ) AS pct_sales_deep_discount,
    total_profit - LAG(total_profit) OVER (ORDER BY order_year) AS profit_change,
    deep_discount_profit
    - LAG(deep_discount_profit) OVER (ORDER BY order_year) AS deep_discount_profit_change
FROM yearly
ORDER BY order_year
```

**Ý tưởng:**

> Tách lợi nhuận mỗi năm thành hai phần bằng conditional aggregation: phần đến từ các dòng giảm giá trên 20% và phần còn lại. Sau đó dùng LAG để tính mỗi phần thay đổi bao nhiêu so với năm trước. Phần nào thay đổi nhiều nhất thì đó là nguyên nhân chính.

**Kết quả:**

| Năm | Doanh thu | Lợi nhuận | Biên lợi nhuận | % doanh thu giảm giá >20% | Lợi nhuận nhóm giảm giá >20% | Lợi nhuận phần còn lại |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| 2020 | 1.148.361 | 207.116 | 18,04% | 22,97% | -46.099 | 253.216 |
| 2021 | 1.405.876 | 259.697 | 18,47% | 21,23% | -53.586 | 313.283 |
| 2022 | 1.770.790 | 318.672 | 18,00% | 22,49% | -77.331 | 396.003 |
| 2023 | 2.192.647 | 279.929 | 12,77% | 23,38% | -111.165 | 391.094 |

**Nhận định:**

> Năm 2023 doanh thu tăng 24% nhưng lợi nhuận giảm 12% (giảm 38.743). Khoản lỗ của nhóm giảm giá trên 20% tăng thêm 33.834, tức là giải thích được 87% mức sụt. Lợi nhuận phần còn lại gần như đi ngang (396.003 xuống 391.094) dù doanh thu tăng mạnh, nên đây cũng là điểm cần xem tiếp.
>
> Biên lợi nhuận năm 2023 giảm ở cả 5 thị trường, mạnh nhất ở Asia Pacific (13,37% xuống 7,21%). Đề xuất trần giảm giá 20% ở Q16 vì vậy nên áp dụng cho mọi thị trường.

---

## 14. Orchestration with Airflow

Đến bước 13, pipeline vẫn phải chạy tay 2 lệnh:

```text
python dlt_ingestion\sqlserver_to_snowflake.py
        ↓
dbt build
```

Airflow tự động hóa việc này:

- chạy pipeline **theo lịch** (mỗi ngày một lần);
- đảm bảo **dbt chỉ chạy khi dlt đã thành công**;
- tự **retry** khi lỗi và lưu log của từng lần chạy;
- hiển thị tiến độ trên giao diện web, **mỗi dbt model là một task riêng**.

### 14.1. Tools

```text
Docker Desktop = chạy các container Linux trên Windows
Astro CLI      = dựng sẵn toàn bộ Airflow (scheduler, database, UI) trong Docker
Cosmos         = đọc project dbt, biến mỗi model thành một task Airflow
```

Cài Astro CLI:

```powershell
winget install -e --id Astronomer.Astro
```

Kiểm tra:

```powershell
docker --version
astro version
```

> Docker Desktop phải được **mở trước** mỗi lần chạy Airflow. Nếu chưa mở, lệnh `astro` sẽ báo không kết nối được Docker.

### 14.2. Create Astro Project

Toàn bộ phần Airflow nằm trong thư mục riêng `airflow/`, không đụng tới `dlt_ingestion/` và `dbt_ecommerce/`.

```powershell
mkdir airflow
cd airflow
astro dev init
```

`astro dev init` tạo ra:

```text
airflow/
├── dags/                  # nơi đặt file DAG
├── include/               # code phụ trợ
├── Dockerfile             # công thức dựng image Airflow
├── requirements.txt       # thư viện Python cho môi trường Airflow
├── packages.txt           # gói hệ điều hành Linux (apt)
├── airflow_settings.yaml  # connection, variable cho môi trường local
└── .astro/                # cấu hình của Astro CLI
```

Xóa file DAG mẫu `dags/exampledag.py`.

### 14.3. Dockerfile

Image mặc định của Astro còn thiếu 2 thứ:

```text
ODBC Driver 18 for SQL Server   → để dlt đọc được SQL Server
dbt                             → để Cosmos chạy dbt models
```

**Đường dẫn:** `airflow/Dockerfile`

```dockerfile
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
```

Giải thích:

- `USER root` ... `USER astro`: cài gói hệ thống cần quyền root, cài xong trả lại user `astro` mà Airflow dùng để chạy.
- `msodbcsql18`: trên Windows driver đã có sẵn, nhưng container chạy **Linux** nên phải cài riêng. `ACCEPT_EULA=Y` là bắt buộc để Microsoft cho cài.
- `dbt_venv`: dbt được cài trong **một venv riêng** tại `/usr/local/airflow/dbt_venv`, vì thư viện của dbt và của Airflow hay yêu cầu version khác nhau của cùng một package. Version được ghim giống `requirements.txt` ở thư mục gốc để máy local và Airflow dùng cùng một bản dbt.

### 14.4. Airflow requirements.txt

**Đường dẫn:** `airflow/requirements.txt`

```text
astronomer-cosmos
dlt[snowflake,sql_database]==1.31.0
pyodbc==5.3.0
python-dotenv==1.2.4
```

File này khác với `requirements.txt` ở thư mục gốc:

```text
requirements.txt (gốc)     → cho .venv trên máy local và CI
airflow/requirements.txt   → cho môi trường Airflow bên trong container
```

- `astronomer-cosmos`: file DAG import `cosmos`;
- `dlt`, `pyodbc`: task dlt chạy hàm `run_pipeline()` trực tiếp trong Airflow;
- `python-dotenv`: script dlt có dòng `from dotenv import load_dotenv`.

dbt không có trong file này vì đã cài trong `dbt_venv`.

### 14.5. Mount dlt & dbt Code into Container

Container chỉ nhìn thấy nội dung thư mục `airflow/`. Để container đọc được `dlt_ingestion/` và `dbt_ecommerce/` mà không phải copy code, dùng **volume mount**.

**Đường dẫn:** `airflow/docker-compose.override.yml`

```yaml
services:
  scheduler:
    volumes:
      - ../dbt_ecommerce:/usr/local/airflow/include/dbt_ecommerce
      - ../dlt_ingestion:/usr/local/airflow/include/dlt_ingestion
  dag-processor:
    volumes:
      - ../dbt_ecommerce:/usr/local/airflow/include/dbt_ecommerce
      - ../dlt_ingestion:/usr/local/airflow/include/dlt_ingestion
```

Mỗi dòng có dạng:

```text
<thư mục trên máy> : <đường dẫn trong container>
../dbt_ecommerce   : /usr/local/airflow/include/dbt_ecommerce
```

Mount vào 2 service:

```text
scheduler       = nơi task thực sự chạy
dag-processor   = nơi Airflow đọc file DAG (Cosmos đọc project dbt ở bước này)
```

Nhờ mount, sửa model trên Windows là container thấy ngay, không cần build lại image. Cấu trúc repo vẫn giữ nguyên: mỗi công cụ một thư mục ở gốc, dlt và dbt vẫn chạy độc lập được từ máy local.

### 14.6. Start Airflow

Mở Docker Desktop, đợi trạng thái **Engine running**, sau đó trong thư mục `airflow`:

```powershell
astro dev start -e ..\.env
```

`-e ..\.env` cho Astro dùng file `.env` ở thư mục gốc, nên toàn bộ credentials ở bước 3 được đưa thẳng vào container.

Giao diện Airflow mở ở cổng mặc định của Astro:

```text
http://localhost:8080
```

> Nếu máy đã có chương trình khác dùng cổng `8080` (ví dụ một project Airflow khác đang chạy), cần tắt chương trình đó trước.

Kiểm tra bên trong container:

```powershell
astro dev bash
```

```bash
odbcinst -q -d                  # [ODBC Driver 18 for SQL Server]
dbt_venv/bin/dbt --version      # Core 1.12.6, snowflake 1.12.5
ls include/dbt_ecommerce        # dbt_project.yml, profiles.yml, models ...
ls include/dlt_ingestion        # sqlserver_to_snowflake.py
env | grep DBT_SNOWFLAKE_USER   # biến từ .env đã vào container
exit
```

> `/usr/local/airflow` là thư mục làm việc mặc định (`AIRFLOW_HOME`) của image Astro. Mọi đường dẫn trong container đều bắt đầu từ đây.

### 14.7. Create the DAG

**Đường dẫn:** `airflow/dags/ecommerce_pipeline.py`

```python
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
```

#### Đường dẫn

```text
DBT_PROJECT_PATH, DLT_PATH  = vế phải của dòng mount trong docker-compose.override.yml
DBT_EXECUTABLE              = dbt_venv tạo trong Dockerfile (Linux: bin/dbt, Windows: Scripts\dbt.exe)
```

#### Profile

`ProfileConfig` cho Cosmos dùng thẳng file `dbt_ecommerce/profiles.yml`. File này lấy giá trị bằng `env_var()`, mà các biến đã có trong container nhờ `-e ..\.env`, nên không cần tạo thêm Airflow Connection.

#### DAG settings

```text
dag_id            = tên hiển thị trên giao diện
schedule          = "@daily" → chạy mỗi ngày một lần
start_date        = ngày DAG bắt đầu có hiệu lực
catchup=False     = không chạy bù các ngày đã qua kể từ start_date
max_active_runs=1 = lần chạy sau phải đợi lần trước xong
tags              = nhãn để lọc trên giao diện
```

`max_active_runs=1` cần thiết vì 2 lần chạy song song sẽ dùng chung thư mục làm việc của dlt và ghi đè file của nhau.

#### Task 1: `load_raw_with_dlt`

```text
@task(retries=2)                 = biến hàm thành task, lỗi thì tự chạy lại tối đa 2 lần
sys.path.insert(0, DLT_PATH)     = cho Python tìm file trong thư mục dlt_ingestion
from ... import run_pipeline     = lấy hàm run_pipeline() từ script ở bước 12.1
run_pipeline()                   = chạy pipeline dlt
```

Lệnh `import` được đặt **bên trong hàm**, vì Airflow đọc lại file DAG vài chục giây một lần, import dlt ở đầu file sẽ làm mỗi lần đọc bị chậm.

#### Task group 2: `dbt_transform`

`DbtTaskGroup` của Cosmos đọc project dbt và tạo **một task cho mỗi model** (19 task), nối với nhau theo `ref()`.

```text
ProjectConfig(..., partial_parse=False)  = vị trí project dbt, đọc lại toàn bộ project mỗi lần chạy
profile_config                           = cách kết nối Snowflake
ExecutionConfig(dbt_executable_path=...) = dùng dbt trong dbt_venv
```

`partial_parse=False`: dbt không dùng file nhớ tạm `target/partial_parse.msgpack`. File này do dbt trên Windows tạo, ghi đường dẫn bằng dấu `\` nên dbt trên Linux không đọc được. Với 21 model, đọc lại toàn bộ chỉ tốn thêm vài giây.

> Cosmos mặc định không tạo task cho **source**, nên các test trong `e_com_source.yml` chưa chạy trong Airflow. Test khai báo cho model staging/mart sẽ được tạo thành task `<model>_test` chạy ngay sau model đó.

#### Dependencies

```python
load_raw_with_dlt() >> dbt_transform
```

`>>` nghĩa là dbt chỉ bắt đầu khi dlt thành công:

```text
load_raw_with_dlt
        ↓
dbt_transform
    ├── stg_customer_run
    ├── stg_ecom_sales_run
    ├── stg_product_run
    └── stg_region_run
            ↓
    Q1_..._run ... Q17_..._run
```

### 14.8. Run the DAG

1. Vào `http://localhost:8080` → **Dags** → `ecommerce_pipeline`.
2. Bật công tắc ở đầu dòng (DAG mới tạo luôn ở trạng thái tạm dừng).
3. Bấm **Trigger** để chạy tay, hoặc để Airflow chạy theo lịch.
4. Mở tab **Graph** để theo dõi: xanh lá là thành công, đỏ là lỗi. Bấm vào một task → tab **Logs** để xem log.

Kết quả:

```text
load_raw_with_dlt        → Success (~50 giây)
dbt_transform (19 task)  → Success
```

### 14.9. Astro Commands

Chạy trong thư mục `airflow`:

```powershell
astro dev start -e ..\.env     # dựng image và khởi động Airflow
astro dev restart -e ..\.env   # build lại image sau khi sửa Dockerfile / requirements.txt
astro dev stop                 # tắt Airflow, giải phóng RAM
astro dev ps                   # liệt kê các container đang chạy
astro dev bash                 # mở terminal bên trong container
```


**Orchestration phase completed successfully.**

---

## 15. CI with GitHub Actions

**CI (Continuous Integration)** là bước kiểm tra tự động: mỗi lần push code hoặc mở pull request, GitHub cấp một máy Linux mới, tải code về và chạy các lệnh kiểm tra.

```text
git push
    ↓
GitHub Actions (máy Linux mới)
    ↓
pip install -r requirements.txt
    ↓
black --check     → format code Python
    ↓
sqlfluff lint     → quy ước viết SQL
    ↓
dbt parse         → cấu trúc project dbt
    ↓
✓ xanh / ✗ đỏ trên commit
```

Lợi ích:

- lỗi được phát hiện **ngay sau khi push**, trước khi Airflow chạy và chạm tới Snowflake;
- không phụ thuộc vào việc có nhớ tự kiểm tra hay không;
- máy CI chỉ cài đúng những gì trong `requirements.txt`, nên **CI xanh nghĩa là người khác clone repo về cũng cài và chạy được**.

Ba công cụ kiểm tra 3 thứ khác nhau:

```text
black       = format code Python (thụt lề, xuống dòng, khoảng trắng, dấu nháy)
sqlfluff    = quy ước viết SQL (chữ hoa keyword, AS, thụt lề, độ dài dòng)
dbt parse   = cấu trúc project dbt (ref()/source() trỏ đúng, YAML/Jinja đúng cú pháp)
```

> black và sqlfluff chỉ kiểm tra **cách trình bày**, không kiểm tra logic. Một câu SQL tính sai công thức nhưng viết đúng quy ước vẫn qua được lint. Độ đúng của dữ liệu do các dbt test kiểm tra khi chạy `dbt build`.

### 15.1. Format Python with black

Chạy ở thư mục gốc:

```powershell
black .
```

black tự sửa toàn bộ file `.py` trong repo (script dlt, file DAG). Thư mục `.venv` được bỏ qua vì nằm trong `.gitignore`.

Kiểm tra (đây cũng là lệnh CI chạy):

```powershell
black --check .
```

Kết quả:

```text
All done! ✨ 🍰 ✨
4 files would be left unchanged.
```

black **không có tùy chọn style**: chỉ có một kiểu format duy nhất, nên không cần file cấu hình.

### 15.2. Lint SQL with sqlfluff

#### Chọn templater

Model dbt chứa Jinja (`{{ ref() }}`, `{{ source() }}`), sqlfluff phải dịch ra SQL trước khi kiểm tra:

```text
templater = dbt     → gọi dbt compile thật, cần profile dbt hoạt động
templater = jinja   → thay ref()/source() bằng tên bảng giả, không cần Snowflake
```

Project dùng `jinja` vì mục tiêu của lint là kiểm tra cách viết SQL, không cần tên bảng thật. Nhờ đó CI không cần kết nối Snowflake và không cần lưu mật khẩu lên GitHub.

#### Cấu hình

**Đường dẫn:** `.sqlfluff`

```ini
[sqlfluff]
dialect = snowflake
templater = jinja
max_line_length = 120
# RF04: không cho dùng keyword làm tên cột. Project có cột tên month, product
# lấy từ dữ liệu nguồn, đổi tên sẽ phải sửa cả mart và Power BI
exclude_rules = RF04

[sqlfluff:templater:jinja]
apply_dbt_builtins = True

[sqlfluff:rules:capitalisation.keywords]
capitalisation_policy = upper

[sqlfluff:rules:capitalisation.functions]
extended_capitalisation_policy = upper

[sqlfluff:rules:capitalisation.literals]
capitalisation_policy = upper
```

Giải thích:

```text
dialect = snowflake          → kiểm tra theo cú pháp Snowflake (DATEDIFF, QUALIFY...)
apply_dbt_builtins = True    → tự cung cấp bản giả của ref, source, config
max_line_length = 120        → mặc định 80 hơi chật với các dòng CAST(... AS DECIMAL)
exclude_rules = RF04         → cho phép tên cột trùng keyword (month, product)
capitalisation...            → keyword, hàm, NULL/TRUE viết hoa
```

**Đường dẫn:** `.sqlfluffignore`

```text
dbt_ecommerce/target/
dbt_ecommerce/dbt_packages/
dbt_ecommerce/logs/
```

File này để sqlfluff bỏ qua các file do dbt tự sinh.

#### Lint và fix

```powershell
# Liệt kê lỗi (CI chạy lệnh này)
sqlfluff lint dbt_ecommerce/models

# Tự sửa các lỗi sửa được
sqlfluff fix dbt_ecommerce/models
```

Mỗi lỗi có dạng:

```text
== [dbt_ecommerce\models\marts\Q8_identify_churning_VIP_customers.sql] FAIL
L:  31 | P:  10 | RF02 | Unqualified reference 'total_lifetime_spend' found in select
                        | with more than one referenced table/view.
```

```text
L     = dòng
P     = vị trí trong dòng
RF02  = mã quy tắc
```

Một số quy tắc thường gặp:

```text
AL01  = alias bảng phải có AS              (tự sửa được)
LT01  = khoảng trắng thừa/thiếu            (tự sửa được)
LT02  = thụt lề sai                        (tự sửa được)
LT12  = file phải kết thúc bằng 1 dòng trống (tự sửa được)
LT05  = dòng quá dài                       (sửa tay: tách dòng)
RF02  = SELECT từ nhiều bảng thì cột phải có tiền tố bảng (sửa tay: cs.total_sales)
```

Sau khi `fix`, chạy lại `dbt build` để chắc model vẫn ra đúng kết quả:

```powershell
cd dbt_ecommerce
dotenv -f ..\.env run -- dbt build --profiles-dir .
```

### 15.3. GitHub Actions Workflow

**Đường dẫn:** `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  lint-and-validate:
    runs-on: ubuntu-latest

    env:
      SNOWFLAKE_ACCOUNT: ci_dummy
      DBT_SNOWFLAKE_USER: ci_dummy
      DBT_SNOWFLAKE_PASSWORD: ci_dummy
      DBT_SNOWFLAKE_ROLE: ci_dummy
      DBT_SNOWFLAKE_WAREHOUSE: ci_dummy
      DBT_SNOWFLAKE_DATABASE: ECOMMERCE_DB
      DBT_SNOWFLAKE_SCHEMA: DBT_DEV

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: pip

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Check Python format (black)
        run: black --check --diff .

      - name: Lint SQL (sqlfluff)
        run: sqlfluff lint dbt_ecommerce/models

      - name: Validate dbt project (dbt parse)
        working-directory: dbt_ecommerce
        run: dbt parse --profiles-dir .
```

Giải thích:

```text
on: push / pull_request   → chạy mỗi lần push lên main và mỗi lần mở/cập nhật pull request
runs-on: ubuntu-latest    → GitHub cấp một máy Linux mới cho mỗi lần chạy, chạy xong thì xóa
actions/checkout          → tải code của repo về máy đó
setup-python + cache      → cài Python 3.12, cache thư viện để các lần sau cài nhanh hơn
black --check --diff      → file sai format thì báo đỏ, kèm đoạn cần sửa
sqlfluff lint             → có lỗi SQL thì báo đỏ
dbt parse                 → đọc toàn bộ project dbt, kiểm tra ref(), source(), YAML, Jinja
```

#### Vì sao dùng giá trị giả trong `env`

`profiles.yml` lấy giá trị bằng `env_var()`, nên dbt cần các biến này tồn tại. Nhưng `dbt parse` **chỉ đọc project, không kết nối Snowflake**, nên giá trị giả (`ci_dummy`) là đủ. Repo không phải lưu mật khẩu thật lên GitHub Secrets.

Bước nào lỗi thì các bước sau không chạy và cả lần chạy báo đỏ.

### 15.4. Push and Check Results

```powershell
git add .
git status
git commit -m "Add CI: black, sqlfluff, dbt parse"
git push
```

Trên GitHub, mở tab **Actions** → chọn lần chạy để xem kết quả từng bước. Mỗi commit trên repo có dấu:

```text
✓ xanh  → cả 3 bước đều qua
✗ đỏ    → bấm vào bước bị đỏ để đọc log
```

### 15.5. CI and CD

```text
CI (Continuous Integration) = tự động kiểm tra code mỗi lần thay đổi
CD (Continuous Deployment)  = CI xanh thì tự động triển khai (ví dụ chạy dbt build lên production)
```

Project hiện chạy Airflow trên máy local nên chưa có môi trường để triển khai. Phạm vi của bước này là **CI: validate code**.

**CI phase completed successfully.**

---

## 16. Visualization with Power BI

> Đang thực hiện. Phần dưới đây là kế hoạch.

### 16.1. Data Source

Power BI đọc các bảng mart do dbt tạo:

```text
Snowflake: ECOMMERCE_DB.DBT_DEV.Q1_* ... Q17_*
        ↓
Power BI Desktop (Snowflake connector)
```

Power BI chỉ đọc bảng đã được dbt làm sạch và tính sẵn, không xử lý lại dữ liệu raw. Logic nghiệp vụ nằm ở một chỗ (dbt), dashboard chỉ hiển thị.

### 16.2. Role for Power BI

Giống dlt (mục 5), Power BI dùng một role riêng chỉ có quyền **đọc** schema mart:

```sql
CREATE ROLE IF NOT EXISTS BI_READER_ROLE;

GRANT USAGE ON WAREHOUSE ECOMMERCE_WH TO ROLE BI_READER_ROLE;
GRANT USAGE ON DATABASE ECOMMERCE_DB TO ROLE BI_READER_ROLE;
GRANT USAGE ON SCHEMA ECOMMERCE_DB.DBT_DEV TO ROLE BI_READER_ROLE;

GRANT SELECT ON ALL TABLES IN SCHEMA ECOMMERCE_DB.DBT_DEV TO ROLE BI_READER_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ECOMMERCE_DB.DBT_DEV TO ROLE BI_READER_ROLE;
```

`FUTURE TABLES` cần thiết vì dbt tạo lại các bảng mart mỗi lần chạy. Không có dòng này, sau mỗi lần `dbt build` Power BI sẽ mất quyền đọc bảng mới.

### 16.3. Connect

```text
Power BI Desktop → Get Data → Snowflake
Server    = <account_identifier>.snowflakecomputing.com
Warehouse = ECOMMERCE_WH
Role      = BI_READER_ROLE
```

Chế độ kết nối:

```text
Import       = Power BI tải dữ liệu về file .pbix, dashboard nhanh, phải refresh để có dữ liệu mới
DirectQuery  = mỗi lần xem dashboard đều query Snowflake, dữ liệu luôn mới nhưng tốn credit
```

Dataset nhỏ (khoảng 100 nghìn dòng) và tĩnh nên dùng **Import**.

### 16.4. Dashboard Plan

Mỗi trang dashboard trả lời một vấn đề kinh doanh trong đề bài Xóm E-Com:

```text
Trang 1: Overview               → Q1, Q2
Trang 2: Discount & Profit      → Q5, Q7, Q16, Q17 (discount có làm giảm lợi nhuận không?)
Trang 3: Segment Profitability  → Q2, Q7, Q9 (segment nào lời nhất?)
Trang 4: Markets & Growth       → Q6, Q10, Q11 (thị trường nào đang tăng trưởng?)
Trang 5: Customers              → Q8, Q13, Q14 (khách hàng có quay lại mua không?)
Trang 6: Products               → Q3, Q12, Q15
```

> Các bảng Q1 đến Q17 là kết quả đã tổng hợp sẵn, phù hợp để hiển thị nhưng khó lọc thêm (ví dụ lọc theo năm hoặc theo quốc gia trên cùng một trang). Nếu dashboard cần slicer linh hoạt, có thể bổ sung trong dbt một lớp model dạng fact/dimension (ví dụ `fct_sales`, `dim_customer`, `dim_product`, `dim_region`) để Power BI tự tổng hợp.